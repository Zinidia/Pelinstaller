#!/bin/bash

set -eo pipefail

######################################################################################
#                                                                                    #
# Project 'Pelinstaller'                                                             #
#                                                                                    #
# Copyright (C) 2018 - 2024, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
# Copyright (C) 2021 - 2026, Matthew Jacob, <git@matthew.network>                    #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/Zinidia/Pelinstaller/blob/Production/LICENSE.md                 #
#                                                                                    #
# This script is not associated with the official Pelican Project.                   #
# https://github.com/Zinidia/Pelinstaller                                            #
#                                                                                    #
######################################################################################

output() {
  echo "* ${1}"
}

error() {
  COLOR_RED='\033[0;31m'
  COLOR_NC='\033[0m'

  echo ""
  echo -e "* ${COLOR_RED}ERROR${COLOR_NC}: $1"
  echo ""
}

# Parse args
REPO="${REPO:-Zinidia/Pelinstaller}"
BRANCH="${BRANCH:-Production}"
MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --repo=*) REPO="${1#*=}"; shift ;;
    --branch|--source) BRANCH="$2"; shift 2 ;;
    --branch=*|--source=*) BRANCH="${1#*=}"; shift ;;
    basic|docker|panel|wings|both|uninstall)
      MODE="$1"; shift ;;
    *) error "Unknown argument: '$1'. Expected a mode (basic, docker, panel, wings, both, uninstall) arg --repo or --branch."; exit 1 ;;
  esac
done

export REPO BRANCH
export GIT_REPO_URL="https://raw.githubusercontent.com/$REPO/$BRANCH"
LOG_PATH="/tmp/pelinstaller.log"

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  error "This script must be executed with root privileges (sudo)." 1>&2
  exit 1
fi

# Check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* Installing dependencies."
  # Rockey / Alma
  if [ -n "$(command -v yum)" ]; then
    yum update -y >> /dev/null 2>&1
    yum -y install curl >> /dev/null 2>&1
  fi
  # Debian / Ubuntu
  if [ -n "$(command -v apt)" ]; then
    DEBIAN_FRONTEND=noninteractive apt update -y >> /dev/null 2>&1
    DEBIAN_FRONTEND=noninteractive apt install -y --no-install-recommends snapd cron curl wget gzip jq >> /dev/null 2>&1
  fi
  # Check if curl is installed
  if ! [ -x "$(command -v curl)" ]; then
    echo "* curl is required in order for this script to work."
    echo "* install using apt (Debian and derivatives) or yum/dnf (CentOS)"
    exit 1
  fi
fi

# Lib Functions
LIB_PATH="/tmp/lib.sh"
curl -fsSL -o "$LIB_PATH" "$GIT_REPO_URL"/lib/lib.sh
trap 'rm -f "$LIB_PATH"' EXIT
# shellcheck source=lib/lib.sh
source "$LIB_PATH"

run_mode() {
  local mode="$1"
  local script
  script="$(mktemp)"
  curl -fsSL -o "$script" "$GIT_REPO_URL/installers/$mode.sh"
  echo -e "\n\n* Pelinstaller $(date) \n\n" >>"$LOG_PATH"
  bash "$script" 2>&1 | tee -a "$LOG_PATH"
  rm -f "$script"
}

execute_arg() {
  case "$1" in
    basic)     run_mode "basic" ;;
    docker)    run_mode "docker" ;;
    panel)     run_mode "panel" ;;
    wings)     run_mode "wings" ;;
    both)      run_mode "panel"; run_mode "wings" ;;
    uninstall) run_mode "uninstall" ;;
    *) error "Invalid option '$1'. Expected one of: basic, docker, panel, wings, both, uninstall."; exit 1 ;;
  esac
}

welcome ""

# ----------------- Non-interactive CLI args ----------------- #
if [[ -n "$MODE" ]]; then
  execute_arg "$MODE"
  exit 0
fi

# Check for existing installation
if [ -d "/var/www/pelican" ]; then
  existing_choice=""
  while [ -z "$existing_choice" ]; do
    error "The script has detected that you already have Pelican panel on your system!"
    output "[1] Uninstall Pelican - Attempt automated Pelican uninstallation."
    output "[2] Continue Anyway - Ignore warnings and attempt to install Pelican anyway."
    output "[3] Exit Installer - Cancel installation process."

    echo -n "* Input 1-3: "
    read -r action || true
    case "$action" in
      1)
        existing_choice="uninstall"
        echo "Attempting uninstall .."
        run_mode "uninstall"
        echo -e -n "* Pelican successfully uninstalled, attempt an install now? (y/N): "
        read -r CONFIRM_PROCEED || true
        if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
          error "Installation aborted!"
          exit 1
        fi
        ;;
      2)
        existing_choice="continue"
        echo "Attempting to proceed anyway .."
        ;;
      3)
        echo "Exiting installer .."
        exit 1
        ;;
      *)
        error "Invalid option. Please input a number between 1 and 3."
        ;;
    esac
  done
fi

# ----------------- Stage 1: Panel install mode ----------------- #
panel_mode=""
while [ -z "$panel_mode" ]; do
  output "What Panel installation mode would you like to use?"
  output "[0] Skip - Do not install the panel (default)"
  output "[1] Basic - Zero prompts, development environment (panel + wings, HTTP-only)"
  output "[2] Docker (Recommended) - Docker compose using the official ghcr images"
  output "[3] Bare metal - Standard install without Docker (prompts for FQDN/SSL)"

  echo -n "* Input 0-3 [0]: "
  read -r action || true
  [ -z "$action" ] && action=0

  case "$action" in
    0) panel_mode="skip" ;;
    1) panel_mode="basic" ;;
    2) panel_mode="docker" ;;
    3) panel_mode="panel" ;;
    *) error "Invalid option" ;;
  esac
done

# ----------------- Stage 2: Wings install ----------------- #
wings_mode="skip"
# Basic mode automatically installs wings
if [ "$panel_mode" != "basic" ]; then
  chosen=""
  while [ -z "$chosen" ]; do
    output "Do you want to install Wings (the machine daemon)?"
    output "[0] Skip - Do not install wings (default)"
    output "[1] Install Wings"

    echo -n "* Input 0-1 [0]: "
    read -r action || true
    [ -z "$action" ] && action=0

    case "$action" in
      0) chosen="skip" ;;
      1) chosen="wings"; wings_mode="wings" ;;
      *) error "Invalid option" ;;
    esac
  done
fi

# ----------------- Execute selections ----------------- #
case "$panel_mode" in
  basic)  run_mode "basic" ;;
  docker) run_mode "docker" ;;
  panel)  run_mode "panel" ;;
  skip)   output "Skipping panel installation." ;;
esac

[ "$wings_mode" == "wings" ] && run_mode "wings"

if [ "$panel_mode" == "skip" ] && [ "$wings_mode" == "skip" ]; then
  output "Nothing selected. Exiting."
fi
