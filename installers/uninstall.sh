#!/bin/bash

set -e

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

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -fsSL "$GIT_REPO_URL"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# ------------------ Variables ----------------- #
export RM_PANEL=false
export RM_WINGS=false

# ---------- Uninstallation functions ---------- #
rm_panel_files() {
  output "Removing panel files .."
  rm -rf /var/www/pelican /usr/local/bin/composer
  case "$OS" in
  debian | ubuntu)
    rm -f /etc/nginx/sites-enabled/pelican.conf
    rm -f /etc/nginx/sites-available/pelican.conf
    [ -e /etc/nginx/sites-available/default ] && ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
    ;;
  almalinux | rocky)
    rm -f /etc/nginx/conf.d/pelican.conf
    ;;
  esac
  systemctl restart nginx
  success "Removed panel files."
}

rm_docker_containers() {
  output "Removing docker containers and images .."

  docker system prune -a -f

  success "Removed docker containers and images."
}

rm_wings_files() {
  output "Removing wings files .."

  # Stop and remove wings service
  systemctl disable --now wings || true
  rm -rf /etc/systemd/system/wings.service

  rm -rf /etc/pelican /usr/local/bin/wings /var/lib/pelican
  success "Removed wings files."
}

rm_services() {
  output "Removing services .."
  systemctl disable --now pelican-queue || true
  rm -rf /etc/systemd/system/pelican-queue.service
  case "$OS" in
  debian | ubuntu)
    systemctl disable --now redis-server || true
    ;;
  almalinux | rocky)
    systemctl disable --now "$REDIS_PACKAGE" || true
    systemctl disable --now php-fpm || true
    rm -rf /etc/php-fpm.d/www-pelican.conf
    ;;
  esac
  success "Removed services."
}

rm_cron() {
  output "Removing cron jobs .."
  local web_user=www-data
  [[ "$OS" =~ ^(rocky|almalinux)$ ]] && web_user=nginx
  (crontab -u "$web_user" -l 2>/dev/null || true) | grep -vF "/var/www/pelican/artisan schedule:run" | crontab -u "$web_user" -
  success "Removed cron jobs."
}

rm_database() {
  output "Removing database .."
  valid_db=$(mariadb -u root -e "SELECT schema_name FROM information_schema.schemata;" | grep -v -E -- 'schema_name|information_schema|performance_schema|mysql' || true)
  warning "Be careful! This database will be deleted!"
  if [[ "$valid_db" == *"panel"* ]]; then
    echo -n "* Database called panel has been detected. Is it the Pelican database? (y/N): "
    read -r is_panel
    if [[ "$is_panel" =~ [Yy] ]]; then
      DATABASE=panel
    else
      print_list "$valid_db"
    fi
  else
    print_list "$valid_db"
  fi
  while [ -z "$DATABASE" ] || [[ $valid_db != *"$database_input"* ]]; do
    echo -n "* Choose the panel database (to skip don't input anything): "
    read -r database_input
    if [[ -n "$database_input" ]]; then
      DATABASE="$database_input"
    else
      break
    fi
  done
  [[ -n "$DATABASE" ]] && mariadb -u root -e "DROP DATABASE $DATABASE;"
  # Exclude usernames User and root (Hope no one uses username User)
  output "Removing database user .."
  valid_users=$(mariadb -u root -e "SELECT user FROM mysql.user;" | grep -v -E -- 'user|root' || true)
  warning "Be careful! This user will be deleted!"
  if [[ "$valid_users" == *"pelican"* ]]; then
    echo -n "* User called pelican has been detected. Is it the pelican user? (y/N): "
    read -r is_user
    if [[ "$is_user" =~ [Yy] ]]; then
      DB_USER=pelican
    else
      print_list "$valid_users"
    fi
  else
    print_list "$valid_users"
  fi
  while [ -z "$DB_USER" ] || [[ $valid_users != *"$user_input"* ]]; do
    echo -n "* Choose the panel user (to skip don't input anything): "
    read -r user_input
    if [[ -n "$user_input" ]]; then
      DB_USER=$user_input
    else
      break
    fi
  done
  [[ -n "$DB_USER" ]] && mariadb -u root -e "DROP USER $DB_USER@'127.0.0.1';"
  mariadb -u root -e "FLUSH PRIVILEGES;"
  success "Removed database and database user."
}

# --------------- Main functions --------------- #
perform_uninstall() {
  [ "$RM_PANEL" == true ] && rm_panel_files
  [ "$RM_PANEL" == true ] && rm_cron
  [ "$RM_PANEL" == true ] && rm_database
  [ "$RM_PANEL" == true ] && rm_services
  [ "$RM_WINGS" == true ] && rm_docker_containers
  [ "$RM_WINGS" == true ] && rm_wings_files

  return 0
}

# ------------------ Uninstall ----------------- #
main() {
  welcome ""

  # Check for existing installation
  if [ -d "/var/www/pelican" ]; then
    output "Panel installation has been detected."
    echo -e -n "* Do you want to remove panel? (y/N): "
    read -r RM_PANEL_INPUT
    [[ "$RM_PANEL_INPUT" =~ [Yy] ]] && RM_PANEL=true
  fi

  if [ -d "/etc/pelican" ]; then
    output "Wings installation has been detected."
    warning "This will remove all the servers!"
    echo -e -n "* Do you want to remove Wings (daemon)? (y/N): "
    read -r RM_WINGS_INPUT
    [[ "$RM_WINGS_INPUT" =~ [Yy] ]] && RM_WINGS=true
  fi

  if [ "$RM_PANEL" == false ] && [ "$RM_WINGS" == false ]; then
    error "Nothing to uninstall!"
    exit 1
  fi

  summary

  # Confirm uninstallation
  echo -e -n "* Continue with uninstallation? (y/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    perform_uninstall
  else
    error "Uninstallation aborted."
    exit 1
  fi
}

summary() {
  print_brake 30
  output "Uninstall panel? $RM_PANEL"
  output "Uninstall wings? $RM_WINGS"
  print_brake 30
}

goodbye() {
  print_brake 62
  [ "$RM_PANEL" == true ] && output "Panel uninstallation completed"
  [ "$RM_WINGS" == true ] && output "Wings uninstallation completed"
  output "Thank you for using this script."
  print_brake 62
}

main
goodbye
