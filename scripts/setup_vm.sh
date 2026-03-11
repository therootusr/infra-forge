#!/bin/bash
set -euo pipefail

# Constants
kShellUser="${1:-ps}"
kShellUserHome="/home/$kShellUser" # $HOME needn't be per expectation
kLogFile="/var/log/vm_setup.log"
kZshPlugins="git kubectl helm docker terraform"

# Logging function
function f_log() {
  local severity="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] [$severity] $message" | tee -a "$kLogFile"
}

function f_update_system() {
  f_log "INFO" "updating system packages..."
  dnf update -y
}

function f_create_system_user() {
  f_log "INFO" "creating user $kShellUser and making it a sudoer..."
  if ! id "$kShellUser" &>/dev/null; then
    useradd -m -G wheel "$kShellUser"
    f_log "INFO" "user $kShellUser created and added to wheel group (sudoers)"
  else
    f_log "INFO" "user $kShellUser already exists"
    # Ensure it's in wheel
    usermod -aG wheel "$kShellUser"
  fi

  # Enable passwordless sudo
  echo "$kShellUser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$kShellUser
  chmod 0440 /etc/sudoers.d/$kShellUser
  f_log "INFO" "passwordless sudo enabled for $kShellUser"
}

function f_setup_authorized_keys_for_system_user() {
  f_log "INFO" "setting up authorized_keys for $kShellUser..."
  local candidate_preset_users=("ec2-user")
  for user in "${candidate_preset_users[@]}"; do
    if ! id "$user" &>/dev/null; then
      f_log "INFO" "user '$user' does not exist, skipping"
      continue
    fi

    if ! [ -f "/home/$user/.ssh/authorized_keys" ]; then
      f_log "INFO" "'/home/$user/.ssh/authorized_keys' file not found for '$user', skipping"
      continue
    fi

    mkdir -p "$kShellUserHome/.ssh"
    cp "/home/$user/.ssh/authorized_keys" "$kShellUserHome/.ssh/authorized_keys"
    chown -R "$kShellUser:$kShellUser" "$kShellUserHome/.ssh"
    chmod 700 "$kShellUserHome/.ssh"
    chmod 600 "$kShellUserHome/.ssh/authorized_keys"
    f_log "INFO" "copied authorized_keys from '$user' to '$kShellUser'"
    return 0
  done
  f_log "WARN" "no authorized_keys found from preset users"
}

function f_install_essentials() {
  f_log "INFO" "enable EPEL repo"
  dnf install -y epel-release

  f_log "INFO" "installing essential tools (git, vim, monitoring tools)..."
  # Assuming: dnf. Also, some/all may already have been installed.
  dnf install -y git vim iotop iftop htop util-linux-user zsh skopeo clang helm awscli wget

  # Ensure curl and unzip are present for other installations
  dnf install -y curl unzip
}

function f_install_docker() {
  # https://docs.docker.com/engine/install/centos/
  f_log "INFO" "installing Docker..."
  dnf remove docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine
  dnf -y install dnf-plugins-core
  dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
  usermod -aG docker $kShellUser
}

function f_install_kubectl() {
  # https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html#linux_amd64_kubectl
  cd /tmp
  curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.2/2025-11-13/bin/linux/amd64/kubectl
  curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.34.2/2025-11-13/bin/linux/amd64/kubectl.sha256
  sha256sum -c kubectl.sha256
  chmod +x ./kubectl
  mkdir -p $kShellUserHome/.local/bin
  mv kubectl $kShellUserHome/.local/bin/kubectl
  f_log "INFO" "kubectl installed to $kShellUserHome/.local/bin/kubectl"
}

function f_setup_zsh_shell() {
  f_log "INFO" "setting up Zsh shell config for $kShellUser..."

  local zsh_path
  zsh_path=$(command -v zsh)
  if [ -z "$zsh_path" ]; then
    f_log "ERROR" "zsh not found in PATH"
    return 1
  fi

  # Change default shell for the user
  usermod --shell "$zsh_path" "$kShellUser"

  local script_dir
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

  local source_script="$script_dir/setup_zsh.sh"
  if [ ! -f "$source_script" ]; then
    f_log "ERROR" "setup_zsh.sh not found at $source_script"
    return 1
  fi

  # Pipe via stdin so the target user doesn't need access to this file's path.
  runuser -l "$kShellUser" -c "ZSH_PLUGINS=\"$kZshPlugins\" bash -s" < "$source_script"
}

function f_cleanup() {
  f_log "INFO" "cleaning up..."
  dnf clean all
}

function f_main() {
  f_log "INFO" "starting VM Setup..."

  # Ensure we are root
  if [ "$(id -u)" -ne 0 ]; then
    f_log "FATAL" "this script must be run as root (sudo)"
    exit 1
  fi

  f_update_system
  f_create_system_user
  f_setup_authorized_keys_for_system_user

  f_install_essentials
  f_install_docker
  f_install_kubectl

  f_setup_zsh_shell

  f_cleanup
  f_log "INFO" "setup complete"
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  f_main "$@"
fi
