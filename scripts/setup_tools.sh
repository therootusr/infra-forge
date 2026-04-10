#!/bin/bash

# setup_tools.sh - install tools on a fresh linux-amd64 workstation
#
# - Installs tools to ~/.local
# - Skips tools already on PATH; does not verify installed version matches
#   the version this script would have installed
# - Downloads are sha256-verified where possible
# - Privileged installs (apt/snap) are gated behind an interactive prompt
#   at the end; sudo credentials are relinquished immediately after.
#   To skip the prompt (e.g. for automation), set RUN_APT_SNAP_INSTALL=y
#   in the env
#
# Assumes: Linux x86_64, bash, curl, tar, unzip, sha256sum, sudo
#
# NOTE: If this script installs a local go, may wanna add to your env:
#       export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
#
# NOTE: zoxide is only a binary until the shell hooks it; add to your shell rc
#       (last, so it can wrap any cd already defined) to get z/zi:
#       eval "$(zoxide init zsh)"   # bash/fish/etc: zoxide init --help
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

function f_maybe_download_verify_install() {
  local cmd=$1
  local url=$2
  local dest=$3
  local sha256=${4:-}
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  cd "$tmp_dir"
  local filename
  filename=$(basename "$url")
  echo "INFO: installing $filename ($url)"
  curl -fsSLo "$filename" "$url"
  if [ "$sha256" != "" ]; then
    f_verify_sha256 "$filename" "$sha256"
  fi
  chmod +x "$filename"
  mv -v --backup=numbered "$filename" "$dest"
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
  curl -fsSL "$url" | bash
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

# Download a zip, verify sha256, extract, and run an install command from
# the archive root (a bundled installer, or mv for bare-binary archives).
# Args after sha256 form the install command.
function f_maybe_install_from_zip() {
  local cmd=$1
  local url=$2
  local sha256=$3
  shift 3
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  cd "$tmp_dir"
  local archive
  archive=$(basename "$url")
  echo "INFO: installing $cmd ($url)"
  curl -fsSLo "$archive" "$url"
  f_verify_sha256 "$archive" "$sha256"
  unzip -q "$archive"
  "$@"
  cd -
  rm -r "$tmp_dir"
}

# Download a gzipped single binary (bare .gz, not a tarball), verify its
# sha256, decompress, and install as ~/.local/bin/<cmd>.
function f_maybe_install_from_gz() {
  local cmd=$1
  local url=$2
  local sha256=$3
  if command -v "$cmd" &> /dev/null; then
    echo "INFO: '$cmd' already installed, skipping"
    return 0
  fi
  local tmp_dir
  tmp_dir=$(mktemp -d)
  cd "$tmp_dir"
  local archive
  archive=$(basename "$url")
  echo "INFO: installing $cmd ($url)"
  curl -fsSLo "$archive" "$url"
  f_verify_sha256 "$archive" "$sha256"
  gunzip -c "$archive" > "$cmd"
  chmod +x "$cmd"
  mv -v "$cmd" ~/.local/bin
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

#----------- fzf -------------

# sha256 from https://github.com/junegunn/fzf/releases/download/v0.74.0/fzf_0.74.0_checksums.txt
f_maybe_download_verify_extract fzf \
  https://github.com/junegunn/fzf/releases/download/v0.74.0/fzf-0.74.0-linux_amd64.tar.gz \
  cf919f05b7581b4c744d764eaa704665d61dd6d3ca785f0df2351281dff60cda \
  ~/.local/bin fzf

#----------- zoxide -------------

# Kept next to fzf: zoxide's interactive query (zi) shells out to it.
# The archive holds man pages and completions alongside the binary, extract
# just the bin; `zoxide init` emits its own completions for the z/zi shell
# funcs anyway. No glibc floor to track (static musl build used).
# The release publishes no checksums file;
f_maybe_download_verify_extract zoxide \
  https://github.com/ajeetdsouza/zoxide/releases/download/v0.10.0/zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz \
  2d93385b99f3e82cf2701609a1bffcad863fbeb75aa3fe7eb6be4d29be68b1ae \
  ~/.local/bin zoxide

#----------- neovim -------------

# Full prefix tree (bin/lib/share), not a lone binary: extract into ~/.local
# so bin/nvim lands on PATH and share/nvim/runtime sits beside it. No checksum
# published for this release, so sha256 is self-computed. The prebuilt binary
# needs glibc >= 2.34 (Ubuntu 22.04 ships 2.35).
f_maybe_download_verify_extract nvim \
  https://github.com/neovim/neovim/releases/download/v0.12.4/nvim-linux-x86_64.tar.gz \
  012bf3fcac5ade43914df3f174668bf64d05e049a4f032a388c027b1ebd78628 \
  ~/.local --strip-components=1

#----------- clangd -------------

# Prefix tree (bin/clangd + lib/clang builtin headers) in a versioned dir, plus a
# stray LICENSE.TXT, so don't merge into ~/.local: keep it in a dedicated dir and
# symlink the binary onto PATH (clangd resolves lib/ via /proc/self/exe, so the
# symlink works). No checksum published for the release, so sha256 is self-computed.
if ! command -v clangd &> /dev/null; then
  rm -rf ~/.local/clangd
  f_maybe_install_from_zip clangd \
    https://github.com/clangd/clangd/releases/download/22.1.6/clangd-linux-22.1.6.zip \
    a9c77443af2e447ed467e84771848d3a6ac1c56f84bcfcde717e66318de77cfa \
    mv clangd_22.1.6 ~/.local/clangd
  ln -sfv ~/.local/clangd/bin/clangd ~/.local/bin/clangd
fi

#----------- tree-sitter cli -------------

# Prebuilt binary is a lone gzip (this version publishes no tarball/zip) with no
# checksum file, so sha256 is self-computed. Pinned to 0.25.10, NOT the latest
# 0.26.x: the 0.26 binaries need glibc 2.39, but the 22.04 target has 2.35.
# 0.25.10 is the newest release built against an older glibc (2.34). Note the
# floor is non-monotonic across versions, so re-check it on any bump.
f_maybe_install_from_gz tree-sitter \
  https://github.com/tree-sitter/tree-sitter/releases/download/v0.25.10/tree-sitter-linux-x64.gz \
  8283ddba69253c698f6e987ba0e2f9285e079c8db4d36ebe1394b5bb3a0ebdfd

#----------- kubectl -------------

kK8sVersion=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
kK8sBinBase="https://dl.k8s.io/release/${kK8sVersion}/bin/linux/amd64"
kKubectlSha256=$(curl -fsSL "${kK8sBinBase}/kubectl.sha256")
f_maybe_download_verify_install kubectl \
  "${kK8sBinBase}/kubectl" \
  ~/.local/bin \
  "$kKubectlSha256"

#----------- helm -------------

# Binaries for https://github.com/helm/helm/releases/tag/v4.2.2 are hosted
# on get.helm.sh (not attached as GitHub release assets)
f_maybe_download_verify_extract helm \
  https://get.helm.sh/helm-v4.2.2-linux-amd64.tar.gz \
  9adafecab4d406853bba163a70e9f104f47dbbf65ce24b7653bae7e36150bcb6 \
  ~/.local/bin --strip-components=1 linux-amd64/helm

#----------- aws cli -------------

# https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
f_maybe_install_from_zip aws \
  https://awscli.amazonaws.com/awscli-exe-linux-x86_64-2.35.15.zip \
  50692e3e2a606007d7789b5a307dca41452a965dea1f3d3687972da6e5adc86c \
  ./aws/install --install-dir ~/.local/aws-cli --bin-dir ~/.local/bin

#----------- terraform -------------

# sha256 from https://releases.hashicorp.com/terraform/1.15.7/terraform_1.15.7_SHA256SUMS
f_maybe_install_from_zip terraform \
  https://releases.hashicorp.com/terraform/1.15.7/terraform_1.15.7_linux_amd64.zip \
  73bbb8f5188ad75d4fb853fd100ae4d7e146ef7af7db18776109642fdb7759d2 \
  mv -v ./terraform ~/.local/bin

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
go install golang.org/x/tools/gopls@latest

go install carvel.dev/ytt/cmd/ytt@latest

# buf: protobuf lint / breaking-change / codegen driver.
#
# Trade-off vs. the release tarball at github.com/bufbuild/buf/releases: that
# one ships an upstream sha256 plus man pages, shell completions, and the
# protoc-gen-buf-{lint,breaking} plugins. Building from source here means the
# module is verified against the Go checksum db rather than a release sha256,
# and those extras are not installed. The plugins are only needed to drive
# buf's checks as protoc plugins (`buf lint` / `buf breaking` do not use them):
#   go install github.com/bufbuild/buf/cmd/protoc-gen-buf-lint@v1.72.0
#   go install github.com/bufbuild/buf/cmd/protoc-gen-buf-breaking@v1.72.0
#
# NOTE: buf can emit its own zsh completion, which the tarball would have
#       supplied; the dir must be on fpath ahead of compinit (oh-my-zsh does
#       not add it):
#       buf completion zsh > ~/.local/share/zsh/site-functions/_buf
go install github.com/bufbuild/buf/cmd/buf@latest

#------------------------------------------------------------------------------
# Misc
#------------------------------------------------------------------------------

f_maybe_install_from_script claude https://claude.ai/install.sh
f_maybe_install_from_script cursor-agent https://cursor.com/install
f_maybe_install_from_script copilot https://gh.io/copilot-install
f_maybe_install_from_script codex https://chatgpt.com/codex/install.sh

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
f_maybe_uv_tool_install basedpyright basedpyright@latest

#------------------------------------------------------------------------------
# All privileged cmds at the end
#------------------------------------------------------------------------------
# inline sudo in cmds; so, the entire script doesn't have to be run as root

# Set RUN_APT_SNAP_INSTALL=y in the env to skip the prompt (for automation).
if [ -n "${RUN_APT_SNAP_INSTALL:-}" ]; then
  echo "INFO: RUN_APT_SNAP_INSTALL='$RUN_APT_SNAP_INSTALL' from env, skipping prompt"
elif [ -t 0 ] || [ -e /dev/tty ]; then
  echo "Do you want to install apt/snap packages? (y/n)"
  read -r RUN_APT_SNAP_INSTALL </dev/tty 2>/dev/null || RUN_APT_SNAP_INSTALL=""
else
  echo "WARNING: no valid TTY found: cannot prompt user for confirmation: skipping apt/snap pkgs"
  exit 0
fi

if [ "$RUN_APT_SNAP_INSTALL" != "y" ]; then
  echo "WARNING: user confirmation not received: skipping apt/snap pkgs"
  exit 0
fi

#------------------------------------------------------------------------------
# apt (Ubuntu 22.04.5 LTS, kernel: 5.15.0-160-generic)
#------------------------------------------------------------------------------

trap 'echo "INFO: relinquish sudo privs:" && sudo -k' EXIT

sudo apt update

sudo DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TZ=UTC apt install -y \
    bat ca-certificates clang-format elinks file fio git \
    gnupg iotop jq less locales mandoc nmap openssh-client \
    postgresql-client-common rocksdb-tools skopeo tzdata vim zsh
# https://github.com/sharkdp/bat
# Setting up bat (0.19.0-1ubuntu0.1) ...
ln -sv /usr/bin/batcat "$HOME/.local/bin/bat"

sudo locale-gen en_US.UTF-8

#------------------------------------------------------------------------------
# snap  (Ubuntu 22.04.5 LTS, kernel: 5.15.0-160-generic)
#------------------------------------------------------------------------------

# sudo snap install kubectl --classic # curl install instead
# sudo snap install helm --classic # curl install instead
# sudo snap install terraform --classic # curl install instead
# sudo snap install aws-cli --classic # curl install instead
# snap install glow # mv-ed to go install instead
# glow 2.1.1 from Charm (charmbracelet) installed
