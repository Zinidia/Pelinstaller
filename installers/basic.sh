#!/bin/bash

# Pelican Installer
# Copyright Matthew Jacob 2021-2024

# ------------------ Variables ----------------- #
# Path (export everything that is possible, doesn't matter that it exists already)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# Operating System
export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

# Download URLs
export PANEL_DL_URL="https://github.com/pelican-dev/panel/releases/latest/download/panel.tar.gz"
export WINGS_DL_URL="https://github.com/pelican-dev/wings/releases/latest/download/wings_linux_"
export GIT_REPO_URL="https://raw.githubusercontent.com/pelican-installer/pelican-installer/Production"

# Colors
COLOR_YELLOW='\033[1;33m'
COLOR_GREEN='\033[0;32m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

# Domain name / IP
IP_ADDRESS="$(hostname -I | awk '{print $1}')"

# Default User credentials
MYSQL_PASSWORD=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~' | fold -w 32 | head -n 1)
USER_PASSWORD=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | fold -w 32 | head -n 1)

# Database host
MYSQL_DBHOST_HOST="127.0.0.1"
MYSQL_DBHOST_USER="pelicanuser"
MYSQL_DBHOST_PASSWORD="${MYSQL_DBHOST_PASSWORD:-}"

# -------------- Load Lib -------------- #
# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/main.sh
  source <(curl -sSL "$GIT_REPO_URL"/lib/main.sh)
  ! fn_exists lib_loaded && echo "* ERROR: Could not load lib script" && exit 1
fi

# -------------------- MYSQL ------------------- #
create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"

  output "Creating database user $db_user_name..."

  mariadb -u root -e "CREATE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Database user $db_user_name created"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Granting all privileges on $db_name to $db_user_name..."

  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  output "Privileges granted"

}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  output "Creating database $db_name..."

  mariadb -u root -e "CREATE DATABASE $db_name;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"

  output "Database $db_name created"
}

# --------------- Package Manager -------------- #
# Argument for quite mode
update_repos() {
  local args=""
  [[ $1 == true ]] && args="-qq"
  case "$OS" in
  ubuntu | debian)
    apt -y $args update
    ;;
  *)
    # Do nothing as AlmaLinux and RockyLinux update metadata before installing packages.
    ;;
  esac
}

# First argument list of packages to install, second argument for quite mode
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval needed for proper expansion of arguments
  case "$OS" in
  ubuntu | debian)
    eval apt -y $args install "$1"
    ;;
  rocky | almalinux)
    eval dnf -y $args install "$1"
    ;;
  esac
}

# ------------------ Firewall ------------------ #
install_firewall() {
  case "$OS" in
  ubuntu | debian)
    output ""
    output "Installing Uncomplicated Firewall (UFW)"

    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi

    ufw --force enable

    success "Enabled Uncomplicated Firewall (UFW)"

    ;;
  rocky | almalinux)

    output ""
    output "Installing FirewallD"+

    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi

    systemctl --now enable firewalld >/dev/null

    success "Enabled FirewallD"

    ;;
  esac
}

firewall_ports() {
  case "$OS" in
  ubuntu | debian)
    for port in $1; do
      ufw allow "$port"
    done
    ufw --force reload
    ;;
  rocky | almalinux)
    for port in $1; do
      firewall-cmd --zone=public --add-port="$port"/tcp --permanent
    done
    firewall-cmd --reload -q
    ;;
  esac
}

# --------- Main installation functions -------- #
install_composer() {
  output "Installing composer.."
  curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
  success "Composer installed!"
}

panel_dl() {
  output "Downloading pelican panel files .. "
  mkdir -p /var/www/pelican
  cd /var/www/pelican || exit

  curl -Lo panel.tar.gz "$PANEL_DL_URL"
  tar -xzvf panel.tar.gz
  chmod -R 755 storage/* bootstrap/cache/

  cp .env.example .env

  success "Downloaded Pelican Panel files!"
}

install_composer_deps() {
  output "Installing composer dependencies.."
  [ "$OS" == "rocky" ] || [ "$OS" == "almalinux" ] && export PATH=/usr/local/bin:$PATH
  COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader
  success "Installed composer dependencies!"
}

# Configure environment
configure_env() {
  output "Configuring environment.."

  local app_url="http://$IP_ADDRESS"

  # Generate encryption key
  php artisan key:generate --force

  # Replace the egg docker images with ForestRacks's optimized images
  for file in /var/www/pelican/database/Seeders/eggs/*/*.json; do
    # Extract the docker_images field from the file using jq
    docker_images=$(jq -r '.docker_images' "$file")

    # Check if the replacement match exists in the docker_images field
    if echo "$docker_images" | grep -q "ghcr.io/pelican/yolks:java_" || echo "$docker_images" | grep -q "quay.io/pelican/core:rust" || echo "$docker_images" | grep -q "quay.io/pelican/games:source" || echo "$docker_images" | grep -q "ghcr.io/pelican/games:source" || echo "$docker_images" | grep -q "quay.io/parkervcp/pelican-images:debian_source"; then
      # Read the contents of the file into a variable
      contents=$(<"$file")

      # Update the docker_images object using multiple jq filters
      contents=$(echo "$contents" | jq '.docker_images |= map_values(. | gsub("ghcr.io/pelican/yolks:java_"; "ghcr.io/forestracks/java:"))' | jq '.docker_images |= map_values(. | gsub("quay.io/pelican/core:rust"; "ghcr.io/forestracks/games:rust"))' | jq '.docker_images |= map_values(. | gsub("quay.io/pelican/games:source"; "ghcr.io/forestracks/games:steam"))' | jq '.docker_images |= map_values(. | gsub("ghcr.io/pelican/games:source"; "ghcr.io/forestracks/games:steam"))' | jq '.docker_images |= map_values(. | gsub("quay.io/parkervcp/pelican-images:debian_source"; "ghcr.io/forestracks/base:main"))')

      # Replace the forward slashes in the docker_images object using sed
      contents=$(echo "$contents" | sed 's/\//\\\//g')
    
      # Write the modified contents back to the file
      echo "$contents" > "$file"
    fi
  done

  # Fill in environment:setup automatically
  php artisan p:environment:setup \
    --telemetry=false \
    --author="admin@example.com" \
    --url="$app_url" \
    --timezone="America/Chicago" \
    --cache="redis" \
    --session="redis" \
    --queue="redis" \
    --redis-host="127.0.0.1" \
    --redis-pass="null" \
    --redis-port="6379" \
    --settings-ui=true

  # Configure database and backup credentials
  php artisan p:environment:database \
    --driver="mysql" \
    --host="127.0.0.1" \
    --port="3306" \
    --database="panel" \
    --username="pelican" \
    --password="$MYSQL_PASSWORD"
  # cp /var/www/pelican/.env /etc/pelican/.env

  # Seed database
  php artisan migrate --seed --force

  # Create user account
  php artisan p:user:make \
    --email="admin@example.com" \
    --username="admin" \
    --name-first="Admin" \
    --name-last="User" \
    --password="$USER_PASSWORD" \
    --admin=1

  # Create a server location
  php artisan p:location:make \
    --short=Main \
    --long="Primary location"

  # Create a node
  php artisan p:node:make \
    --name="Node01" \
    --description="First Node" \
    --fqdn=$IP_ADDRESS \
    --public=1 \
    --locationId=1 \
    --scheme="http" \
    --proxy="no" \
    --maintenance=0 \
    --maxMemory="$(free -m | awk 'FNR == 2 {print $2}')" \
    --overallocateMemory=0 \
    --maxDisk="$(df --total -m | tail -n 1 | awk '{print $2}')" \
    --overallocateDisk=0 \
    --uploadSize=100 \
    --daemonListeningPort=8080 \
    --daemonSFTPPort=2022 \
    --daemonBase="/var/lib/pelican/volumes"

  # Fetch wings configuration
  mkdir -p /etc/pelican
  echo "$(php artisan p:node:configuration 1)" > /etc/pelican/config.yml

  success "Configured environment!"
}

# Set proper directory permissions for distro
set_folder_permissions() {
  # Assign directory user
  case "$OS" in
  debian | ubuntu)
    chown -R www-data:www-data ./*
    ;;
  rocky | almalinux)
    chown -R nginx:nginx ./*
    ;;
  esac
}

insert_cronjob() {
  output "Installing cronjob.. "

  crontab -l | {
    cat
    output "* * * * php /var/www/pelican/artisan schedule:run >> /dev/null 2>&1"
  } | crontab -

  success "Cronjob installed!"
}

pteroq_systemd() {
  output "Installing pteroq service.."

  curl -o /etc/systemd/system/pteroq.service "$GIT_REPO_URL"/configs/pteroq.service

  case "$OS" in
  debian | ubuntu)
    sed -i -e "s@<user>@www-data@g" /etc/systemd/system/pteroq.service
    ;;
  rocky | almalinux)
    sed -i -e "s@<user>@nginx@g" /etc/systemd/system/pteroq.service
    ;;
  esac

  systemctl enable pteroq.service
  systemctl start pteroq

  success "Installed pteroq systemd service!"
}

# -------- OS specific install functions ------- #
enable_services() {
  case "$OS" in
  ubuntu | debian)
    systemctl enable redis-server
    systemctl start redis-server
    ;;
  rocky | almalinux)
    systemctl enable redis
    systemctl start redis
    ;;
  esac
  systemctl enable nginx
  systemctl enable mariadb
  systemctl start mariadb
}

selinux_allow() {
  setsebool -P httpd_can_network_connect 1 || true # These commands can fail OK
  setsebool -P httpd_execmem 1 || true
  setsebool -P httpd_unified 1 || true
}

php_fpm_conf() {
  curl -o /etc/php-fpm.d/www-pelican.conf "$GIT_REPO_URL"/configs/www-pelican.conf

  systemctl enable php-fpm
  systemctl start php-fpm
}

ubuntu_dep() {
  # Install deps for adding repos
  install_packages "software-properties-common apt-transport-https ca-certificates gnupg jq"

  # Add Ubuntu universe repo
  add-apt-repository universe -y

  # Add PPA for PHP (we need 8.3)
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
}

debian_dep() {
  # Install deps for adding repos
  install_packages "dirmngr ca-certificates apt-transport-https lsb-release"

  # Install PHP 8.3 using sury's repo
  curl -o /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
  echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list
}

alma_rocky_dep() {
  # SELinux tools
  install_packages "policycoreutils selinux-policy selinux-policy-targeted \
    setroubleshoot-server setools setools-console mcstrans"

  # Add remi repo (php8.3)
  install_packages "epel-release http://rpms.remirepo.net/enterprise/remi-release-$OS_VER_MAJOR.rpm"
  dnf module enable -y php:remi-8.3
}

panel_deps() {
  output "Installing dependencies for $OS $OS_VER..."

  # Update repos before installing
  update_repos

  case "$OS" in
  ubuntu | debian)
    [ "$OS" == "ubuntu" ] && ubuntu_dep
    [ "$OS" == "debian" ] && debian_dep

    update_repos

    # Install dependencies
    install_packages "php8.3 php8.3-{cli,common,gd,intl,mysql,mbstring,bcmath,xml,fpm,curl,zip} \
      mariadb-common mariadb-server mariadb-client \
      nginx \
      redis-server \
      zip unzip tar \
      git cron"

    ;;
  rocky | almalinux)
    alma_rocky_dep

    # Install dependencies
    install_packages "php php-{common,fpm,cli,json,intl,mysqlnd,mcrypt,gd,mbstring,pdo,zip,bcmath,dom,opcache,posix} \
      mariadb mariadb-server \
      nginx \
      redis \
      zip unzip tar \
      git cronie"

    # Allow Nginx
    selinux_allow

    # Create config for PHP FPM
    php_fpm_conf
    ;;
  esac

  enable_services

  success "Dependencies installed!"
}

# ------ Webserver configuration functions ----- #
configure_nginx() {
  output "Configuring nginx .."

  case "$OS" in
  ubuntu | debian)
    PHP_SOCKET="/run/php/php8.3-fpm.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/sites-available"
    CONFIG_PATH_ENABL="/etc/nginx/sites-enabled"
    ;;
  rocky | almalinux)
    PHP_SOCKET="/var/run/php-fpm/pelican.sock"
    CONFIG_PATH_AVAIL="/etc/nginx/conf.d"
    CONFIG_PATH_ENABL="$CONFIG_PATH_AVAIL"
    ;;
  esac

  rm -rf "$CONFIG_PATH_ENABL"/default
  curl -o "$CONFIG_PATH_AVAIL"/pelican.conf "$GIT_REPO_URL"/configs/nginx.conf
  sed -i -e "s@<domain>@${IP_ADDRESS}@g" "$CONFIG_PATH_AVAIL"/pelican.conf
  sed -i -e "s@<php_socket>@${PHP_SOCKET}@g" "$CONFIG_PATH_AVAIL"/pelican.conf

  case "$OS" in
  ubuntu | debian)
    ln -sf "$CONFIG_PATH_AVAIL"/pelican.conf "$CONFIG_PATH_ENABL"/pelican.conf
    ;;
  esac

  systemctl restart nginx
  success "Nginx configured!"
}


# --------------- Wings functions --------------- #
wings_deps() {
  output "Installing dependencies for $OS $OS_VER..."

  case "$OS" in
  ubuntu | debian)
    install_packages "ca-certificates gnupg lsb-release"

    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    ;;

  rocky | almalinux)
    install_packages "dnf-utils"
    dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo

    install_packages "device-mapper-persistent-data lvm2"
    ;;
  esac

  # Update the new repos
  update_repos

  # Install dependencies
  install_packages "docker-ce docker-ce-cli containerd.io"

  systemctl start docker
  systemctl enable docker

  success "Dependencies installed!"
}

wings_dl() {
  echo "* Downloading Pelican Wings.. "

  mkdir -p /etc/pelican
  curl -L -o /usr/local/bin/wings "$WINGS_DL_URL$ARCH"

  chmod u+x /usr/local/bin/wings

  success "Pelican Wings downloaded successfully"
}

wings_systemd() {
  output "Installing systemd service.."

  curl -o /etc/systemd/system/wings.service "$GIT_REPO_URL"/configs/wings.service
  systemctl daemon-reload
  systemctl enable wings

  sleep 3
  systemctl start wings

  success "Installed wings systemd service!"
}

# --------------- Execute functions --------------- #
output "Starting Pelican Panel installation.. this might take a while!"
panel_deps
install_composer
panel_dl
install_composer_deps
create_db_user "pelican" "$MYSQL_PASSWORD"
create_db "panel" "pelican"
configure_env
set_folder_permissions
insert_cronjob
pteroq_systemd
configure_nginx
install_firewall
firewall_ports "22 80 443 8080 2022"
output "Installing Pelican Wings.."
wings_deps
wings_dl
wings_systemd
