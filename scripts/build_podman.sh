#!/usr/bin/env bash

# build_podman.sh - ILLUSTRATIVE ONLY: the steps to build podman from official
# sources and bundle it for a rootless, home-directory install on Ubuntu 24.04.
#
# Written up from steps that were run once by hand. This script as a whole has
# not been run: read it before running any part of it.
#
# Produces ~/podman-bundle-v6.1.2-linux-amd64.tgz:
#   podman/      extract into <target-home>/.local   (-> ~/.local/podman)
#   containers/  extract into <target-home>/.config  (-> ~/.config/containers)
#   SHA256SUMS   checksums of the files above
#
# Sources, all official, versions pinned:
#   podman v6.1.2, rootlessport   source, github.com/podman-container-tools/podman
#                                 (git commit pinned)
#   pasta (passt 2026_01_20)      source, Ubuntu 26.04's archive (default) or
#                                 passt.top (tarball sha256 or commit pinned)
#   conmon v2.2.1, crun 1.30,     release binaries, github.com/containers/*
#     netavark v2.1.0,            (sha256 pinned; crun also publishes .asc
#     aardvark-dns v2.1.0          signatures, not verified here)
#   catatonit v0.2.1              release binary, github.com/openSUSE/catatonit
#                                 (sha256 pinned; .asc not verified here)
#   seccomp.json                  github.com/podman-container-tools/container-libs
#                                 (tag pinned; no published checksum)
#   go 1.26.8                     go.dev (sha256 pinned; build only, not bundled)
#
# Build host: a throwaway Ubuntu 24.04 amd64 VM with sudo and internet access,
# the same Ubuntu release as the target. podman links against the system glibc,
# libseccomp and libsqlite3, so a binary built on a newer release may not run on
# the target. The -dev packages are needed only here, not on the target.
# The build is mostly serial, so a few fast cores beat many slow ones
# (e.g. EC2 m8azn.3xlarge).
#
# Usage (on the build VM, as the default non-root user):
#   TARGET_HOME=/home/<user> bash build_podman.sh
#
#   TARGET_HOME   home dir of the user who will run podman on the target;
#                 containers.conf needs absolute paths under it (required)
#   PASST_SOURCE  where pasta's source comes from: ubuntu (default) | upstream
#   WORK_DIR      scratch dir for the build (default: ~/podman-build)
#
#------------------------------------------------------------------------------
# On the target, as <user>, once the build is done:
#
# 1. Copy the bundle over; its sha256 should match what the build printed:
#      scp <build-vm>:podman-bundle-v6.1.2-linux-amd64.tgz ~/
#      sha256sum ~/podman-bundle-v6.1.2-linux-amd64.tgz
#
# 2. Extract, and put podman (only podman) on PATH:
#      tar -C ~/.local  -xzf ~/podman-bundle-v6.1.2-linux-amd64.tgz podman
#      tar -C ~/.config -xzf ~/podman-bundle-v6.1.2-linux-amd64.tgz containers
#      ln -sf ~/.local/podman/bin/podman ~/.local/bin/podman
#
# 3. One-time root setup (sudo):
#    a) newuidmap/newgidmap: the setuid helpers that map the user's /etc/subuid
#       and /etc/subgid ranges into the user namespace. Without them:
#         Error: command required for rootless mode with multiple IDs: exec: "newuidmap": ...
#
#         sudo apt-get install -y uidmap
#         grep "^<user>:" /etc/subuid /etc/subgid   # needs a range for <user>
#
#    b) An AppArmor profile for the home-dir podman. Ubuntu 24.04 sets
#       kernel.apparmor_restrict_unprivileged_userns=1, and the stock
#       /etc/apparmor.d/podman profile only covers /usr/bin/podman. Without it:
#         failed to reexec: Permission denied
#       and the kernel log shows apparmor="DENIED" operation="exec"
#       profile="unprivileged_userns" info="Failed name lookup - disconnected path".
#       The profile must name the real binary, not the ~/.local/bin symlink.
#
#         sudo tee /etc/apparmor.d/home.<user>.local.podman.bin.podman >/dev/null <<'EOF'
#         # Same as the stock /etc/apparmor.d/podman profile, but for a home-dir install
#         abi <abi/4.0>,
#         include <tunables/global>
#
#         profile podman-<user> /home/<user>/.local/podman/bin/podman flags=(unconfined) {
#           userns,
#         }
#         EOF
#         sudo apparmor_parser -r /etc/apparmor.d/home.<user>.local.podman.bin.podman
#
# 4. Check it works:
#      podman --version
#      podman unshare cat /proc/self/uid_map   # "0 <uid> 1" and "1 <subuid-start> <count>"
#      podman info | grep -E 'rootless:|cgroupManager:|seccompEnabled:|graphDriverName:'
#      podman run --rm docker.io/library/alpine echo hello
#
# Optional zsh completion: add this before compinit / oh-my-zsh is sourced:
#   fpath=(~/.local/podman/share/zsh/site-functions $fpath)
#
# Uninstall (image layers are owned by sub-UIDs, so reset before rm):
#   podman system reset
#   rm -rf ~/.local/podman ~/.local/bin/podman ~/.config/containers
#   sudo apparmor_parser -R /etc/apparmor.d/home.<user>.local.podman.bin.podman
#   sudo rm /etc/apparmor.d/home.<user>.local.podman.bin.podman
#
# Not covered: Quadlet / systemd units (systemd only loads generators from
# system directories).

set -euo pipefail

kTargetHome="${TARGET_HOME:?set TARGET_HOME to the target user's home dir, e.g. TARGET_HOME=/home/alice}"
kPasstSource="${PASST_SOURCE:-ubuntu}"
kWorkDir="${WORK_DIR:-$HOME/podman-build}"

kPodmanVersion="v6.1.2"
kPodmanCommit="04f3aa430e6df81bea059978bc5bafbc846ba3e7"
kPodmanRepoUrl="https://github.com/podman-container-tools/podman.git"

kGoVersion="1.26.8"
kGoSha256="d0f743b33e8d8945e6b1f432edd15785c70507121d6e2a723b21285eddf8b57b"

# Same upstream release either way: the Ubuntu package version encodes the
# passt tag (YYYY_MM_DD.<commit>)
kPasstVersion="2026_01_20.386b5f5"
kPasstUbuntuVersion="0.0~git20260120.386b5f5-1"
kPasstOrigSha256="cc0a86b0ac28e1e5b2a4243bcf7fa84b14dd91c7dc883a78896060111e12d105"
kPasstRepoUrl="https://passt.top/passt"

kConmonUrl="https://github.com/containers/conmon/releases/download/v2.2.1/conmon.amd64"
kConmonSha256="1d97294c14c43d477e0a0826e9cd0f2a2af373ddfafe6f10252e8a3c43f32be6"
# The systemd-enabled build (not -disable-systemd): needed for the default
# systemd cgroup manager, which makes --memory/--cpus work rootless
kCrunUrl="https://github.com/containers/crun/releases/download/1.30/crun-1.30-linux-amd64"
kCrunSha256="8093b6d104408d6c8dfdd3436e06dbf345074587e0848c1e262a17b96847d6fb"
# netavark and aardvark-dns are dynamically linked; netavark needs glibc >= 2.39
kNetavarkUrl="https://github.com/containers/netavark/releases/download/v2.1.0/netavark.gz"
kNetavarkSha256="39fb540daf7578a793510b27b592b10f17b5d9aa3b07bc5c3f40881f12d590bd"
kAardvarkDnsUrl="https://github.com/containers/aardvark-dns/releases/download/v2.1.0/aardvark-dns.gz"
kAardvarkDnsSha256="a7bc5252ee0e083f3f46d5bb9dc5f0abdbaa31a70a5a19012412dc8055ac2976"
kCatatonitUrl="https://github.com/openSUSE/catatonit/releases/download/v0.2.1/catatonit.x86_64"
kCatatonitSha256="8293951eaa7767fa411e3b89777bd01bc5e56db9ba6d145ad10cc4d05b01e961"

# Pinned to the container-libs tag podman v6.1.2 vendors (go.podman.io/common v0.69.2)
kSeccompJsonUrl="https://raw.githubusercontent.com/podman-container-tools/container-libs/common/v0.69.2/common/pkg/seccomp/seccomp.json"

kBundleDir="$kWorkDir/bundle"
kPrefixDir="$kBundleDir/podman"
kHelperDir="$kPrefixDir/libexec/podman"
kConfDir="$kBundleDir/containers"
kBundlePath="$HOME/podman-bundle-${kPodmanVersion}-linux-amd64.tgz"

# Where the bundle ends up on the target (written into containers.conf)
kTargetPrefix="$kTargetHome/.local/podman"
kTargetConfDir="$kTargetHome/.config/containers"

function f_log() {
  local severity="$1"
  shift
  echo "$severity: [$(date +'%Y-%m-%d %H:%M:%S')]: $*"
}

function f_fatal() {
  f_log "FATAL" "$@"
  exit 1
}

function f_verify_sha256() {
  local file=$1
  local expected=$2
  local actual
  actual=$(sha256sum "$file" | cut -d' ' -f1)
  if [ "$actual" != "$expected" ]; then
    f_fatal "sha256 mismatch for $file: expected $expected, got $actual"
  fi
}

function f_download_verify() {
  local url=$1
  local dest=$2
  local sha256=$3
  f_log "INFO" "downloading $url"
  curl -fsSLo "$dest" "$url"
  f_verify_sha256 "$dest" "$sha256"
}

function f_check_host() {
  # shellcheck source=/dev/null
  . /etc/os-release
  if [ "${ID:-}" != "ubuntu" ] || [ "${VERSION_ID:-}" != "24.04" ]; then
    f_fatal "expected Ubuntu 24.04 (same release as the target), found ${PRETTY_NAME:-unknown}"
  fi
  if [ "$(uname -m)" != "x86_64" ]; then
    f_fatal "expected x86_64, found $(uname -m)"
  fi
  if [ "$(id -u)" -eq 0 ]; then
    f_fatal "run as a normal user with sudo, not as root"
  fi
  case "$kTargetHome" in
    /?*) ;;
    *) f_fatal "TARGET_HOME must be an absolute path, got '$kTargetHome'" ;;
  esac
  case "$kWorkDir" in
    /?*) ;;
    *) f_fatal "WORK_DIR must be an absolute path other than /, got '$kWorkDir'" ;;
  esac
}

function f_install_build_deps() {
  # A fresh cloud VM may still be running its first-boot apt jobs
  if command -v cloud-init &> /dev/null; then
    cloud-init status --wait > /dev/null || true
  fi
  f_log "INFO" "installing build dependencies"
  sudo apt-get update
  # pkg-config + libseccomp-dev: seccomp build tag
  # libsystemd-dev: systemd build tag (journald events, systemd cgroup manager)
  # libsqlite3-dev: link Ubuntu's SQLite instead of compiling the bundled copy
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential ca-certificates curl git pkg-config \
    libseccomp-dev libsystemd-dev libsqlite3-dev
}

function f_install_go() {
  local tarball="go${kGoVersion}.linux-amd64.tar.gz"
  f_download_verify "https://go.dev/dl/$tarball" "$kWorkDir/$tarball" "$kGoSha256"
  rm -rf "$kWorkDir/go"
  tar -C "$kWorkDir" -xzf "$kWorkDir/$tarball"
  export PATH="$kWorkDir/go/bin:$PATH"
  # Use exactly this toolchain; never auto-download another one
  export GOTOOLCHAIN=local
  go version
}

function f_build_podman() {
  local src="$kWorkDir/podman"
  rm -rf "$src"
  git clone --quiet --depth 1 --branch "$kPodmanVersion" "$kPodmanRepoUrl" "$src"
  local head
  head=$(git -C "$src" rev-parse HEAD)
  if [ "$head" != "$kPodmanCommit" ]; then
    f_fatal "podman $kPodmanVersion is at $head, expected $kPodmanCommit"
  fi

  f_log "INFO" "building podman $kPodmanVersion"
  # podman's Makefile adds the seccomp, systemd and libsqlite3 build tags when
  # the matching -dev packages are installed. containers_image_openpgp checks
  # image signatures in pure Go, so libgpgme-dev isn't needed.
  # No -march / GOAMD64: keep the baseline x86-64 target.
  CC=gcc CGO_ENABLED=1 make -C "$src" podman rootlessport \
    EXTRA_BUILDTAGS=containers_image_openpgp

  local tags
  tags=$(go version -m "$src/bin/podman" | awk '$1 == "build" && $2 ~ /^-tags=/ {print $2}')
  local tag
  for tag in seccomp systemd libsqlite3 containers_image_openpgp; do
    if [[ ",${tags#-tags=}," != *",$tag,"* ]]; then
      f_fatal "podman was built without the '$tag' build tag ($tags); is its -dev package installed?"
    fi
  done
  "$src/bin/podman" --version

  install -Dm755 "$src/bin/podman" "$kPrefixDir/bin/podman"
  install -Dm755 "$src/bin/rootlessport" "$kHelperDir/rootlessport"
  install -Dm644 "$src/completions/zsh/_podman" "$kPrefixDir/share/zsh/site-functions/_podman"
}

# Ubuntu 24.04's own passt (Feb 2024) predates the --map-guest-addr option
# podman 6 always passes, so take Ubuntu 26.04's source package instead.
# apt checks it against the archive's signed index.
function f_fetch_passt_ubuntu() {
  local src=$1
  local list=/etc/apt/sources.list.d/resolute-src.sources
  local orig="passt_${kPasstUbuntuVersion%-*}.orig.tar.xz"
  f_log "INFO" "fetching passt source from Ubuntu's archive (26.04, resolute)"
  sudo tee "$list" > /dev/null <<'EOF'
Types: deb-src
URIs: http://archive.ubuntu.com/ubuntu
Suites: resolute
Components: universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
  sudo apt-get update
  (cd "$kWorkDir" && apt-get source --download-only "passt=$kPasstUbuntuVersion")
  # Only needed for this one download
  sudo rm -f "$list"
  f_verify_sha256 "$kWorkDir/$orig" "$kPasstOrigSha256"
  # The pristine upstream tarball; Debian's patches aren't applied
  rm -rf "$src"
  mkdir -p "$src"
  tar -C "$src" --strip-components=1 -xf "$kWorkDir/$orig"
}

function f_fetch_passt_upstream() {
  local src=$1
  f_log "INFO" "fetching passt source from $kPasstRepoUrl"
  rm -rf "$src"
  git clone --quiet "$kPasstRepoUrl" "$src"
  git -C "$src" checkout --quiet "$kPasstVersion"
  local head
  head=$(git -C "$src" rev-parse --short=7 HEAD)
  if [ "$head" != "${kPasstVersion##*.}" ]; then
    f_fatal "passt $kPasstVersion is at $head, expected ${kPasstVersion##*.}"
  fi
}

function f_build_pasta() {
  local src="$kWorkDir/passt"
  case "$kPasstSource" in
    ubuntu) f_fetch_passt_ubuntu "$src" ;;
    upstream) f_fetch_passt_upstream "$src" ;;
    *) f_fatal "PASST_SOURCE must be 'ubuntu' or 'upstream', got '$kPasstSource'" ;;
  esac
  f_log "INFO" "building pasta $kPasstVersion"
  make -C "$src" -j"$(nproc)" VERSION="$kPasstVersion"
  # pasta and pasta.avx2 are symlinks to passt and passt.avx2; -P keeps them.
  # passt switches to the .avx2 build at runtime only if the CPU has AVX2.
  cp -P "$src/passt" "$src/passt.avx2" "$src/pasta" "$src/pasta.avx2" "$kHelperDir/"
}

function f_fetch_helpers() {
  local dl="$kWorkDir/downloads"
  rm -rf "$dl"
  mkdir -p "$dl"
  f_download_verify "$kConmonUrl" "$dl/conmon" "$kConmonSha256"
  f_download_verify "$kCrunUrl" "$dl/crun" "$kCrunSha256"
  f_download_verify "$kNetavarkUrl" "$dl/netavark.gz" "$kNetavarkSha256"
  f_download_verify "$kAardvarkDnsUrl" "$dl/aardvark-dns.gz" "$kAardvarkDnsSha256"
  f_download_verify "$kCatatonitUrl" "$dl/catatonit" "$kCatatonitSha256"
  gunzip "$dl/netavark.gz" "$dl/aardvark-dns.gz"
  install -m755 "$dl/conmon" "$dl/crun" "$dl/netavark" "$dl/aardvark-dns" "$dl/catatonit" \
    "$kHelperDir/"
}

function f_write_config() {
  f_log "INFO" "writing config for $kTargetHome"
  curl -fsSLo "$kConfDir/seccomp.json" "$kSeccompJsonUrl"

  # Same as container-libs' default-policy.json (image/v5.41.2): accept any image
  cat > "$kConfDir/policy.json" <<'EOF'
{
    "default": [
        {
            "type": "insecureAcceptAnything"
        }
    ],
    "transports":
        {
            "docker-daemon":
                {
                    "": [{"type":"insecureAcceptAnything"}]
                }
        }
}
EOF

  # Resolve short names like "alpine" against Docker Hub only (no prompt)
  echo 'unqualified-search-registries = ["docker.io"]' > "$kConfDir/registries.conf"

  # containers.conf doesn't expand ~ or $HOME, hence absolute target paths.
  # cgroup_manager stays at its default (systemd).
  cat > "$kConfDir/containers.conf" <<EOF
[containers]
# The static conmon build has no journald log driver
log_driver = "k8s-file"
seccomp_profile = "$kTargetConfDir/seccomp.json"

[engine]
runtime = "crun"
conmon_path = ["$kTargetPrefix/libexec/podman/conmon"]
# netavark, aardvark-dns, pasta, catatonit, rootlessport
helper_binaries_dir = ["$kTargetPrefix/libexec/podman"]

[engine.runtimes]
crun = ["$kTargetPrefix/libexec/podman/crun"]
EOF
}

function f_make_bundle() {
  (cd "$kBundleDir" && find podman containers -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
  tar -C "$kBundleDir" -czf "$kBundlePath" SHA256SUMS podman containers
  tar -tzvf "$kBundlePath"
  f_log "INFO" "bundle: $kBundlePath"
  sha256sum "$kBundlePath"
}

#------------------------------------------------------------------------------
# main
#------------------------------------------------------------------------------
trap 'f_log "FATAL" "failed at line $LINENO: $BASH_COMMAND"' ERR

f_check_host
mkdir -p "$kWorkDir"
rm -rf "$kBundleDir"
mkdir -p "$kPrefixDir/bin" "$kHelperDir" "$kConfDir"

f_install_build_deps
f_install_go
f_build_podman
f_build_pasta
f_fetch_helpers
f_write_config
f_make_bundle

f_log "INFO" "done; see this script's header for installing the bundle on the target"
