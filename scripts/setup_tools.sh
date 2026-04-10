#!/bin/bash

# setup_tools.sh - install tools on a fresh linux-amd64 workstation
#
# - Installs tools to ~/.local
# - Skips tools already on PATH; does not verify installed version matches
#   the version this script would have installed
# - Downloads are sha256-verified where possible
# - Privileged installs (apt/snap) are gated behind an interactive prompt
#   at the end; sudo credentials are relinquished immediately after
#
# Assumes: Linux x86_64, bash, curl, tar, sha256sum, sudo
#
# NOTE: If this script installs a local go, may wanna add to your env:
#       export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
#
# NOTE: Automated install not recommended for secure environments.
#       Best to look at the latest install instructions, vers from the publishers.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/therootusr/infra-forge/refs/heads/master/scripts/setup_tools.sh | bash

set -euo pipefail

function f_verify_sha256() {
  local file=$1
  local expected=$2
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    echo "FATAL: sha256 mismatch for $file"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    exit 1
  fi
}

# Download a tarball, verify its sha256, extract, and clean up.
# Extra args after dest are passed to tar (e.g. --strip-components=1).
function f_maybe_download_verify_extract() {
  local cmd=$1
  local url=$2
  local sha256=$3
  local dest=$4
  shift 4
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  cd "$tmp_dir"
  local archive
  archive=$(basename "$url")
  echo "INFO: installing $archive ($url)"
  curl -fsSLo "$archive" "$url"
  f_verify_sha256 "$archive" "$sha256"
  tar -C "$dest" -xzf "$archive" "$@"
  cd -
  rm -r "$tmp_dir"
}

function f_maybe_uv_tool_install() {
  local cmd=$1
  local pkg=$2
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  uv tool install --prerelease=allow "$pkg"
}

function f_maybe_install_from_script() {
  local cmd=$1
  local url=$2
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  echo "INFO: installing $cmd ($url)"
  curl -fsS "$url" | bash
}

# Download a .deb, verify sha256, extract a single binary to ~/.local/bin.
function f_maybe_install_from_deb() {
  local cmd=$1
  local url=$2
  local sha256=$3
  local bin_path=$4  # path to the binary inside the deb
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  cd "$tmp_dir"
  local deb
  deb=$(basename "$url")
  echo "INFO: installing $cmd ($url)"
  curl -fsSLo "$deb" "$url"
  f_verify_sha256 "$deb" "$sha256"
  dpkg-deb -x "$deb" .
  mv -v "./${bin_path}" ~/.local/bin
  cd -
  rm -r "$tmp_dir"
}

kStartingDir=$PWD
kTmpDir=$(mktemp -d)
cd "$kTmpDir"

mkdir -pv ~/.local/bin
export PATH="$HOME/.local/bin:$PATH"

#------------------------------------------------------------------------------
# SSM plugin: needed by aws cli for `aws ssm start-session`
#------------------------------------------------------------------------------
f_maybe_install_from_deb "session-manager-plugin" \
  "https://s3.amazonaws.com/session-manager-downloads/plugin/1.2.804.0/ubuntu_64bit/session-manager-plugin.deb" \
  "5ca19f45bd29082cd28f5001444cc0e9743b866f6431503dfd528bdc81a21bc3" \
  "usr/local/sessionmanagerplugin/bin/session-manager-plugin"

#------------------------------------------------------------------------------
# teleport cli setup
#------------------------------------------------------------------------------
#
# For tsh login on remote via --headless:
#     $ tsh --proxy=<proxy> --headless --user=<username> ...
#     had to set up passkey MFA on my laptop in my quick experiments
#     (authenticator based MFA didn't work either IIRC)
#     without MFA setup: error during auth on local (laptop):
#         ApiError: expected MFA auth challenge response \
#         The requested session doesn't exist or is invalid. Please generate a new request.
# However, after adding MFA to a test teleport account, teleport (GUI
# at least) won't allow disabling it. Thus, will enable MFA lazily on a
# need-only basis.
#
# Also, callback override may be able to achieve remote teleport auth without
# headless mode. However, our config blocks overriding the callback endpoint:
#     $ tsh --proxy=<proxy> --auth=okta --bind-addr=<ip-A>:18443 --callback=<ip-A>:18443 ls
#         Logging in from a remote host means that credentials will be stored
#         on the remote host. Make sure that you trust the provided callback
#         host (10.k1.k2.k3:18443) and that it resolves to the provided bind
#         addr (10.k1.k2.k3:18443). Continue? [y/N]: y
#         ERROR: Failed to login due to a disallowed callback URL. Please check Teleport's log for more details.
#
# As a workaround, tsh_okta_remote_login can be run to perform OKTA login on
# remote via SSH tunneling:
# $ tsh_okta_remote_login $COLO $PROXY_URL
# function tsh_okta_remote_login() {
#   ...
#   ...
#   ...
#   local is_tunnel_set=false
#   while IFS= read -r line; do
#     printf '%s\n' "$line"
#     if [[ "$is_tunnel_set" == true ]]; then
#       continue
#     fi
#     local port=$(printf '%s' "$line" | grep -oE '127\.0\.0\.1:[0-9]+' | head -1 | cut -d: -f2)
#     if [[ -n "$port" ]]; then
#       # Don't want the port to be persistently forwarded by the controlmaster
#       # Also, detach bg ssh STDIN from loop's/process-substitution's STDIN
#       # ctrl+c WON'T auto terminate this tunnel (enhance for it, if needed)
#       # -f forks only post connection and -L proxy set up completion,
#       # so the next cmd can safely run.
#       # -f implies -n + we manually redirect stdin too (should be ok perhaps)
#       /usr/bin/ssh -F /dev/null \
#                    -o stricthostkeychecking=no \
#                    -o UserKnownHostsFile=/dev/null \
#                    -o LogLevel=ERROR \
#                    -o ExitOnForwardFailure=yes \
#                    -L "${port}:localhost:${port}" \
#                    -fN "$remote" < /dev/null
#       # open in chrome locally
#       open "$(echo -n $line | tr -d ' ')"
#       # tunnel_pid=$! # When tunnel_pid dies, want the port to be freed up
#       is_tunnel_set=true
#     fi
#   # --auth=okta for newer version (17.5.4), --auth=okta-connector for older (e.g. 7.3.26)
#   done < <(ssh "$remote" "~/.local/bin/$tsh_bin --proxy=$tsh_proxy login --browser=none" 2>&1)
#
#   # Alternative would be: `ssh -MS "$ctlfile" ...`, and then:
#   # `ssh -S "$ctlfile" -O exit "$remote"`
#   kill "$(lsof -tiTCP:${port} -sTCP:LISTEN)"
# }
#
#------------------------------------------------------------------------------
#
# Apparently, the right way to work with multiple binaries is via setting:
#   TELEPORT_HOME and TELEPORT_TOOLS_VERSION
# $ TELEPORT_TOOLS_VERSION=7.3.26 tsh --proxy=<proxy> login
#   Update progress: [▒▒▒▒▒▒▒▒▒▒] (Ctrl-C to cancel update)
#   ERROR: hash file is not found: "https://cdn.teleport.dev/teleport-v7.3.26-linux-amd64-bin.tar.gz.sha256"
# However, as noticed above, sha256 is missing for v7.3.26. Manually install
# the required tsh bins below for now.
#------------------------------------------------------------------------------

# IMPORTANT: Assuming linux + amd64 arch; other archs have diff download link
function f_set_up_teleport_for_version() {
  local version=$1
  local sha256=$2

  if [ -f ~/.local/bin/tsh-${version} ]; then
    echo "INFO: 'tsh-${version}' already installed, skipping"
    return 0
  fi

  # https://goteleport.com/docs/installation/linux/
  # curl https://<proxy-fqdn>/scripts/install.sh
  # Look at install_via_curl function to determine the download URL
  # curl -O https://cdn.teleport.dev/teleport-ent-v17.5.4-linux-amd64-bin.tar.gz
  # file ./teleport-ent/tsh
  # teleport-ent/tsh: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV), dynamically linked, interpreter /lib64/ld-linux-x86-64.so.2, BuildID[sha1]=f0b90a3b2013ab22cbb36634b0a678e4ff93cb7a, for GNU/Linux 2.6.32, stripped
  f_maybe_download_verify_extract "tsh-${version}" \
    "https://cdn.teleport.dev/teleport-ent-v${version}-linux-amd64-bin.tar.gz" \
    "$sha256" ~/.local/bin --strip-components=1 teleport-ent/tsh

  mv -v ~/.local/bin/tsh ~/.local/bin/tsh-${version}
  chmod +x ~/.local/bin/tsh-${version}
  ln -sf ~/.local/bin/tsh-17.5.4 ~/.local/bin/tsh
}

f_set_up_teleport_for_version 17.5.4 c9df9d29f2bf0f74fcd23447cba5354f68d16942ee45dcd588d17449fdf9b8ef
f_set_up_teleport_for_version 7.3.26 51acea74ff230c44395f654e4ad1641768fee71adf13c535ea2f6ed83719b745

#------------------------------------------------------------------------------
# Standalone
#------------------------------------------------------------------------------

#----------- git-delta -------------

f_maybe_download_verify_extract delta \
  https://github.com/dandavison/delta/releases/download/0.19.2/delta-0.19.2-x86_64-unknown-linux-musl.tar.gz \
  f1ea01ca7728ce3462debc359f39dfc7cbbc1a63224b71fefabf92042864aa1b \
  ~/.local/bin --strip-components=1 delta-0.19.2-x86_64-unknown-linux-musl/delta

#----------- shellcheck -------------
f_maybe_download_verify_extract shellcheck \
  https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.gz \
  b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6 \
  ~/.local/bin --strip-components=1 shellcheck-v0.11.0/shellcheck

#----------- hwatch -------------
f_maybe_download_verify_extract hwatch \
  https://github.com/blacknon/hwatch/releases/download/0.3.20/hwatch-0.3.20.x86_64-unknown-linux-musl.tar.gz \
  b35ba7477b47c29bc79dfba2432b820f21be47e1b4ef162e8617179c137fa150 \
  ~/.local/bin --strip-components=1 bin/hwatch

cd "$kStartingDir"
rm -r "$kTmpDir"

#------------------------------------------------------------------------------
# go setup (local install if not available)
#------------------------------------------------------------------------------
if ! command -v go &> /dev/null; then
  kGoVersion=1.26.2
  kGoSha256=990e6b4bbba816dc3ee129eaeaf4b42f17c2800b88a2166c265ac1a200262282
  echo "WARNING: go not found, installing go${kGoVersion} to ~/.local/go"
  if [ -d ~/.local/go ]; then
    echo "FATAL: ~/.local/go already exists but go is not on PATH; reconcile manually"
    exit 1
  fi
  f_maybe_download_verify_extract go "https://go.dev/dl/go${kGoVersion}.linux-amd64.tar.gz" "$kGoSha256" ~/.local
  export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
  go version
fi

#------------------------------------------------------------------------------
# go tools setup
#------------------------------------------------------------------------------

# set up go-tools
go install github.com/bazelbuild/bazelisk@latest
go install github.com/bazelbuild/buildtools/buildifier@latest
go install github.com/ankitpokhrel/jira-cli/cmd/jira@latest

CGO_ENABLED=0 GOTOOLCHAIN=go1.21.13 go install -ldflags="-s -w" github.com/okta/okta-aws-cli/v2/cmd/okta-aws-cli@v2.5.2

go install github.com/yannh/kubeconform/cmd/kubeconform@latest
GOTOOLCHAIN=go1.25.0 go install github.com/jesseduffield/lazygit@latest
go install github.com/jesseduffield/lazydocker@latest

go install github.com/charmbracelet/glow/v2@latest
go install github.com/wagoodman/dive@latest

#------------------------------------------------------------------------------
# Misc
#------------------------------------------------------------------------------

f_maybe_install_from_script claude https://claude.ai/install.sh
f_maybe_install_from_script cursor-agent https://cursor.com/install
f_maybe_install_from_script copilot https://gh.io/copilot-install

#------------------------------------------------------------------------------
# uv setup + tools
#------------------------------------------------------------------------------
if ! command -v uv &> /dev/null; then
  kUvVersion=0.11.6
  kUvSha256=aa342a53abe42364093506d7704214d2cdca30b916843e520bc67759a5d20132
  kUvArchive="uv-x86_64-unknown-linux-musl.tar.gz"
  echo "WARNING: uv not found, installing uv ${kUvVersion}"
  f_maybe_download_verify_extract uv \
    "https://github.com/astral-sh/uv/releases/download/${kUvVersion}/${kUvArchive}" \
    "$kUvSha256" ~/.local/bin --strip-components=1
  uv --version
fi
f_maybe_uv_tool_install az azure-cli@latest

#------------------------------------------------------------------------------
# All privileged cmds at the end
#------------------------------------------------------------------------------
# inline sudo in cmds; so, the entire script doesn't have to be run as root

if [ -t 0 ] || [ -e /dev/tty ]; then
  echo "Do you want to install apt/snap packages? (y/n)"
  if read -r RUN_APT_SNAP_INSTALL </dev/tty 2>/dev/null; then
    if [ "$RUN_APT_SNAP_INSTALL" != "y" ]; then
      echo "WARNING: user confirmation not received: skipping apt/snap pkgs"
      exit 0
    fi
  fi
else
  echo "WARNING: no valid TTY found: cannot prompt user for confirmation: skipping apt/snap pkgs"
  exit 0
fi

#------------------------------------------------------------------------------
# apt (Ubuntu 22.04.5 LTS, kernel: 5.15.0-160-generic)
#------------------------------------------------------------------------------

trap 'echo "INFO: relinquish sudo privs:" && sudo -k' EXIT

sudo apt update

# apt install zsh
sudo apt install -y \
    clang-format nmap iotop elinks fzf skopeo fio postgresql-client-common \
    bat rocksdb-tools
# https://github.com/sharkdp/bat
# Setting up bat (0.19.0-1ubuntu0.1) ...

#------------------------------------------------------------------------------
# snap  (Ubuntu 22.04.5 LTS, kernel: 5.15.0-160-generic)
#------------------------------------------------------------------------------

sudo snap install jq
sudo snap install clangd --classic
sudo snap install kubectl --classic
sudo snap install helm --classic
sudo snap install terraform --classic
sudo snap install aws-cli --classic
# snap install glow # mv-ed to go install instead
# glow 2.1.1 from Charm (charmbracelet) installed
