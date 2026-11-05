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
# Install MariaDB
export INSTALL_MARIADB=false

# Firewall
export CONFIGURE_FIREWALL=false

# TLS Cert
export CONFIGURE_LETSENCRYPT=false
export HOSTNAME=""
export EMAIL=""

# Database host
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="pelicanuser"
export MYSQL_DBHOST_PASSWORD=""

# ------------ User input functions ------------ #
ask_letsencrypt() {
  if [ "$CONFIGURE_FIREWALL" == false ]; then
    warning "Let's Encrypt requires port 80/443 to be opened! You have opted out of the automatic firewall configuration; use this at your own risk (if port 80/443 is closed, the script will fail)!"
  fi

  warning "You cannot use Let's Encrypt with your hostname as an IP address! It must be a FQDN (e.g. node01.example.com)."

  echo -e -n "* Do you want to automatically configure HTTPS using Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
  fi
}

ask_database_user() {
  echo -n "* Do you want to automatically configure a user for database hosts? (y/N): "
  read -r CONFIRM_DBHOST

  if [[ "$CONFIRM_DBHOST" =~ [Yy] ]]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  echo -n "* Do you want to configure MySQL to be accessed externally? (y/N): "
  read -r CONFIRM_DBEXTERNAL

  if [[ "$CONFIRM_DBEXTERNAL" =~ [Yy] ]]; then
    echo -n "* Enter the panel address (blank for any address): "
    read -r CONFIRM_DBEXTERNAL_HOST
    if [ "$CONFIRM_DBEXTERNAL_HOST" == "" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="$CONFIRM_DBEXTERNAL_HOST"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warning "Allow incoming traffic to port 3306 (MySQL) can potentially be a security risk, unless you know what you are doing!"
  echo -n "* Would you like to allow incoming traffic to port 3306? (y/N): "
  read -r CONFIRM_DB_FIREWALL
  if [[ "$CONFIRM_DB_FIREWALL" =~ [Yy] ]]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

# ----------- Installation functions ----------- #
enable_services() {
  [ "$INSTALL_MARIADB" == true ] && systemctl enable mariadb
  [ "$INSTALL_MARIADB" == true ] && systemctl start mariadb
  systemctl start docker
  systemctl enable docker
}

dep_install() {
  output "Installing dependencies for $OS $OS_VER .."

  [ "$CONFIGURE_FIREWALL" == true ] && install_firewall && firewall_ports

  case "$OS" in
  debian | ubuntu)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  almalinux | rocky)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "epel-release"

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"

  # Install MariaDB if needed
  [ "$INSTALL_MARIADB" == true ] && install_packages "mariadb-server"
  [ "$CONFIGURE_LETSENCRYPT" == true ] && install_packages "certbot"

  enable_services

  success "Dependencies installed!"
}

ptdl_dl() {
  echo "* Downloading Pelican Wings.. "

  mkdir -p /etc/pelican /var/run/wings
  curl -fsSL --retry 5 --retry-all-errors --speed-limit 1024 --speed-time 30 -o /usr/local/bin/wings "$WINGS_DL_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  success "Pelican Wings downloaded successfully"
}

systemd_file() {
  output "Installing systemd service .."

  curl -fsSL -o /etc/systemd/system/wings.service "$GIT_REPO_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings

  success "Installed systemd service!"
}

firewall_ports() {
  output "Opening port 22 (SSH), 8080 (Wings Port), 2022 (Wings SFTP Port)"

  [ "$CONFIGURE_LETSENCRYPT" == true ] && firewall_allow_ports "80 443"
  [ "$CONFIGURE_DB_FIREWALL" == true ] && firewall_allow_ports "3306"

  firewall_allow_ports "22 8080 2022"

  success "Firewall ports opened!"
}

letsencrypt() {
  FAILED=false

  output "Configuring LetsEncrypt .."

  # If user has nginx
  systemctl stop nginx || true

  # Obtain certificate
  certbot certonly --no-eff-email --email "$EMAIL" --standalone -d "$HOSTNAME" || FAILED=true

  systemctl start nginx || true

  # Check if it succeded
  if [ ! -d "/etc/letsencrypt/live/$HOSTNAME/" ] || [ "$FAILED" == true ]; then
    warning "The process of obtaining a Let's Encrypt certificate failed!"
  else
    success "The process of obtaining a Let's Encrypt certificate succeeded!"
  fi
}

configure_mysql() {
  output "Configuring MySQL.."

  create_db_user "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_PASSWORD" "$MYSQL_DBHOST_HOST"
  grant_all_privileges "*" "$MYSQL_DBHOST_USER" "$MYSQL_DBHOST_HOST"

  if [ "$MYSQL_DBHOST_HOST" != "127.0.0.1" ]; then
    echo "* Changing MySQL bind address .."

    case "$OS" in
    debian | ubuntu)
      sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mariadb.conf.d/50-server.cnf
      ;;
    almalinux | rocky)
      sed -i 's/^#bind-address=0.0.0.0$/bind-address=0.0.0.0/' /etc/my.cnf.d/mariadb-server.cnf
      ;;
    esac

    systemctl restart mariadb
  fi

  success "MySQL configured!"
}

perform_install() {
  output "Installing Pelican wings .."
  dep_install
  ptdl_dl
  systemd_file
  [ "$CONFIGURE_DBHOST" == true ] && configure_mysql
  [ "$CONFIGURE_LETSENCRYPT" == true ] && letsencrypt

  return 0
}

# --------------- Main functions --------------- #
main() {
  # Check for existing installation
  if [ -f "/usr/local/bin/wings" ]; then
    warning "The script has detected that you already have Wings installed on your system! You cannot run the script multiple times, it will fail!"
    echo -e -n "* Are you sure you want to proceed? (y/N): "
    read -r CONFIRM_PROCEED || true
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Installation aborted!"
      exit 1
    fi
  fi

  welcome "wings"

  check_virt
  install_docker_kernel_modules

  echo "* "
  echo "* The installer will install Docker, required dependencies for Wings"
  echo "* as well as Wings itself. But it's still required to create the node"
  echo "* on the panel and then place the configuration file on the node manually after"
  echo "* the installation has finished. Read more about this process on the"
  echo "* official documentation: $(hyperlink 'https://pelican.dev/docs/wings/install#configure')"
  echo "* "
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not start Wings automatically (will install systemd service, not start it)."
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: this script will not enable swap (for docker)."
  print_brake 42

  ask_firewall CONFIGURE_FIREWALL

  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    type mysql >/dev/null 2>&1 && HAS_MYSQL=true || HAS_MYSQL=false

    if [ "$HAS_MYSQL" == false ]; then
      INSTALL_MARIADB=true
    fi

    MYSQL_DBHOST_USER="pelicanuser"
    MYSQL_DBHOST_PASSWORD="$(gen_passwd 64)"
  fi

  ask_letsencrypt

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ "$CONFIGURE_LETSENCRYPT" == true ] && [ -z "$HOSTNAME" ]; do
      echo -n "* Set the FQDN to use for Let's Encrypt (node.example.com): "
      read -r HOSTNAME

      ASK=false

      [ -z "$HOSTNAME" ] && error "FQDN cannot be empty"                                                            # Check if FQDN is empty
      bash <(curl -fsSL "$GIT_REPO_URL"/lib/fqdn.sh) "$HOSTNAME" || ASK=true                                 # Check if FQDN is valid
      [ -d "/etc/letsencrypt/live/$HOSTNAME/" ] && error "A certificate with this FQDN already exists!" && ASK=true # Check if cert exists

      [ "$ASK" == true ] && HOSTNAME=""
      [ "$ASK" == true ] && echo -e -n "* Do you still want to automatically configure HTTPS using Let's Encrypt? (y/N): "
      [ "$ASK" == true ] && read -r CONFIRM_SSL

      if [[ ! "$CONFIRM_SSL" =~ [Yy] ]] && [ "$ASK" == true ]; then
        CONFIGURE_LETSENCRYPT=false
        HOSTNAME=""
      fi
    done
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    # Email
    while ! valid_email "$EMAIL"; do
      echo -n "* Enter email address for Let's Encrypt: "
      read -r EMAIL

      valid_email "$EMAIL" || error "Email cannot be empty or invalid"
    done
  fi

  echo -n "* Proceed with installation? (y/N): "

  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    # Firewall
    CONFIGURE_FIREWALL="${CONFIGURE_FIREWALL:-false}"

    # TLS Cert
    CONFIGURE_LETSENCRYPT="${CONFIGURE_LETSENCRYPT:-false}"
    EMAIL="${EMAIL:-}"

    # Database
    INSTALL_MARIADB="${INSTALL_MARIADB:-false}"
    CONFIGURE_DBHOST="${CONFIGURE_DBHOST:-false}"
    CONFIGURE_DB_FIREWALL="${CONFIGURE_DB_FIREWALL:-false}"
    MYSQL_DBHOST_HOST="${MYSQL_DBHOST_HOST:-127.0.0.1}"
    MYSQL_DBHOST_USER="${MYSQL_DBHOST_USER:-pelicanuser}"
    MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

    if [[ $CONFIGURE_DBHOST == true && -z "${MYSQL_DBHOST_PASSWORD}" ]]; then
      error "MySQL database host user password is required"
      exit 1
    fi

    # ---------------- Installation ---------------- #
    perform_install
  else
    error "Installation aborted."
    exit 1
  fi
}

function goodbye {
  echo ""
  print_brake 70
  echo "* Wings installation completed"
  echo "*"
  echo "* To continue, you need to configure Wings to run with your panel"
  echo "* Please refer to the official guide, $(hyperlink 'https://pelican.dev/docs/wings/install#configure')"
  echo "* "
  echo "* You can either copy the configuration file from the panel manually to /etc/pelican/config.yml"
  echo "* or, you can use the \"auto deploy\" button from the panel and simply paste the command in this terminal"
  echo "* "
  echo "* You can then start Wings manually to verify that it's working"
  echo "*"
  echo "* sudo wings"
  echo "*"
  echo "* Once you have verified that it is working, use CTRL+C and then start Wings as a service (runs in the background)"
  echo "*"
  echo "* systemctl start wings"
  echo "*"
  echo -e "* ${COLOR_RED}Note${COLOR_NC}: It is recommended to enable swap (for Docker, read more about it in official documentation)."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "* ${COLOR_RED}Note${COLOR_NC}: If you haven't configured your firewall, ports 8080 and 2022 needs to be open."
  print_brake 70
  echo ""
}

# Run script
main
goodbye
