#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pelican-installer'                                                        #
#                                                                                    #
# Copyright (C) 2018 - 2024, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
# Copyright (C) 2021 - 2024, Matthew Jacob, <me@matthew.expert>                      #
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
# https://github.com/pelican-installer/pelican-installer/blob/Production/LICENSE.md  #
#                                                                                    #
# This script is not associated with the official Pelican Project.                   #
# https://github.com/pelican-installer/pelican-installer                             #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #

# Domain name / IP
export IP_ADDRESS="$(hostname -I | awk '{print $1}')"

# Initial admin account
export USER_PASSWORD=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | fold -w 32 | head -n 1)

# ------------ User input functions ------------ #

main() {
  # check if we can detect an already existing installation
  if [ -d "/var/www/pelican" ]; then
    warning "The script has detected that you already have Pelican panel on your system! You cannot run the script multiple times, it will fail!"
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Installation aborted!"
      exit 1
    fi
  fi

  welcome "basic"
  check_os_x86_64
  summary

  # confirm installation
  echo -e -n "\n* Initial configuration completed. Continue with installation? (y/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "basic"
  else
    error "Installation aborted."
    exit 1
  fi
}

summary() {
  print_brake 62
  output "Pelican Panel installed successfully!"
  output "Panel URL: http://$IP_ADDRESS"
  output "Username: admin"
  output "Password: $USER_PASSWORD"
  print_brake 62
}

# run script
main
