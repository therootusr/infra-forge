#!/usr/bin/env bash
set -euo pipefail

# Configures Oh My Zsh, Powerlevel10k, and dotfiles for the current user.
#
# Pre-requisites: zsh, git
#
# Install:
#   curl -fsSL https://raw.githubusercontent.com/therootusr/infra-forge/refs/heads/master/scripts/setup_zsh.sh | bash

kZshPlugins="${ZSH_PLUGINS:-git kubectl helm docker terraform}"
kOmzInstallUrl="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh"
kP10kRepoUrl="https://github.com/romkatv/powerlevel10k.git"
kZshrcPath="$HOME/.zshrc"
kDotfilesRepoUrl="${DOTFILES_REPO_URL:-https://github.com/therootusr/dotfiles.git}"
kDotfilesRepoDir="${DOTFILES_REPO_DIR:-$HOME/workspace/personal/dotfiles}"
kDotfilesSetupRelPath="shell/zsh/setup.sh"

function f_log() {
  local severity="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  echo "$severity: [$timestamp]: $message"
}

function f_install_omz() {
  f_log "INFO" "installing Oh My Zsh..."
  local omz_dir="$HOME/.oh-my-zsh"

  if [ ! -d "$omz_dir" ]; then
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL "$kOmzInstallUrl")" "" --unattended
  fi

  if [ ! -f "$kZshrcPath" ]; then
    if [ -f "$omz_dir/templates/zshrc.zsh-template" ]; then
      cp "$omz_dir/templates/zshrc.zsh-template" "$kZshrcPath"
    else
      touch "$kZshrcPath"
    fi
  fi
}

function f_configure_plugins() {
  f_log "INFO" "configuring Zsh plugins..."

  if grep -q '^plugins=' "$kZshrcPath"; then
    sed -i "s/^plugins=.*/plugins=($kZshPlugins)/" "$kZshrcPath"
  else
    echo "plugins=($kZshPlugins)" >> "$kZshrcPath"
  fi
}

function f_install_p10k() {
  f_log "INFO" "installing Powerlevel10k theme..."
  local zsh_custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  local theme_dir="$zsh_custom/themes/powerlevel10k"

  if [ ! -d "$theme_dir" ]; then
    git clone --depth=1 "$kP10kRepoUrl" "$theme_dir"
  fi

  if grep -q '^ZSH_THEME=' "$kZshrcPath"; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$kZshrcPath"
  else
    echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$kZshrcPath"
  fi

  if ! grep -q '^POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' "$kZshrcPath"; then
    echo 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true' >> "$kZshrcPath"
  fi

  f_log "INFO" "powerlevel10k installed. Run 'p10k configure' to customize."
}

function f_run_dotfiles_setup() {
  f_log "INFO" "setting up dotfiles..."
  mkdir -p "$kDotfilesRepoDir"

  if [ ! -d "$kDotfilesRepoDir/.git" ]; then
    git clone "$kDotfilesRepoUrl" "$kDotfilesRepoDir"
  else
    f_log "INFO" "dotfiles repo already present, skipping clone"
  fi

  local script_full_path="$kDotfilesRepoDir/$kDotfilesSetupRelPath"
  if [ -f "$script_full_path" ]; then
    f_log "INFO" "executing $script_full_path..."
    bash "$script_full_path"
  else
    f_log "ERROR" "script $script_full_path not found in the cloned repo"
    return 1
  fi
}

function f_main() {
  f_log "INFO" "starting Zsh setup for user $(id -un)..."
  f_install_omz
  f_configure_plugins
  f_install_p10k
  f_run_dotfiles_setup
  f_log "INFO" "Zsh setup complete"
}

# Run f_main when executed directly (BASH_SOURCE[0] == $0) or piped via
# curl | bash (BASH_SOURCE[0] is unset). Skip when sourced from another script.
if [[ -z "${BASH_SOURCE[0]:-}" ]] || [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  f_main "$@"
fi
