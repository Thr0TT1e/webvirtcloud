#!/bin/bash
#/ Usage: webvirtcloud.sh [-vh]
#/
#/ Install Webvirtcloud virtualization web interface.
#/
#/ OPTIONS:
#/   -v | --verbose    Enable verbose output.
#/   -h | --help       Show this message.

########################################################
#            Webvirtcloud Install Script               #
# Script created by Mike Tucker(mtucker6784@gmail.com) #
#              adapted by catborise                    #
#              catborise@gmail.com                     #
#                                                      #
#  Feel free to modify, but please give                #
#  credit where it's due. Thanks!                      #
########################################################

echo "export PYTHONPATH=/home/$USER/.local/bin/:$PATH" >> $USER/.bashrc

# Parse arguments
while true; do
  case "$1" in
    -h|--help)
      show_help=true
      shift
      ;;
    -v|--verbose)
      set -x
      verbose=true
      shift
      ;;
    -*)
      echo "Error: invalid argument: '$1'" 1>&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

print_usage () {
  grep '^#/' <"$0" | cut -c 4-
  exit 1
}

if [ -n "$show_help" ]; then
  print_usage
else
  for x in "$@"; do
    if [ "$x" = "--help" ] || [ "$x" = "-h" ]; then
      print_usage
    fi
  done
fi

# ensure running as root
if [ "$(id -u)" != "0" ]; then
    #Debian doesnt have sudo if root has a password.
    if ! hash sudo 2>/dev/null; then
        exec su -c "$0" "$@"
    else
        exec sudo "$0" "$@"
    fi
fi

clear

readonly APP_USER="wvcuser"
readonly APP_REPO_URL="https://github.com/retspen/webvirtcloud.git"
readonly APP_NAME="webvirtcloud"
readonly APP_PATH="/opt/$APP_NAME"

#readonly PYTHON="python3"
readonly PYTHON=/opt/python-3.8.9/bin/python3.8/python

progress () {
  spin[0]="-"
  spin[1]="\\"
  spin[2]="|"
  spin[3]="/"

  echo -n " "
  while kill -0 "$pid" > /dev/null 2>&1; do
    for i in "${spin[@]}"; do
      echo -ne "\\b$i"
      sleep .3
    done
  done
  echo ""
}

log () {
  if [ -n "$verbose" ]; then
    eval "$@" |& tee -a /var/log/webvirtcloud-install.log
  else
    eval "$@" |& tee -a /var/log/webvirtcloud-install.log >/dev/null 2>&1
  fi
}

install_packages () {
  echo -e "
       \033[1;31mДистрибутив - $distro, версия - $version\033[0m
       "
  case $distro in
    ubuntu|debian|AstraLinuxSE)
      for p in $PACKAGES; do
        if dpkg -s "$p" >/dev/null 2>&1; then
          echo "  * $p уже установлено"
        else
          echo "  * Установка $p"
          log "DEBIAN_FRONTEND=noninteractive apt-get install -y $p"
        fi
      done;
      ;;
  esac
}

# configure_nginx () {
#   # Remove default configuration 
#   rm /etc/nginx/nginx.conf
#   if [ -f /etc/nginx/sites-enabled/default ]; then
#     rm /etc/nginx/sites-enabled/default
#   fi

#   chown -R "$nginx_group":"$nginx_group" /var/lib/nginx
#   # Copy new configuration and webvirtcloud.conf
#   echo "  * Copying Nginx configuration ($distro)"
#   cp "$APP_PATH"/conf/nginx/"$distro"_nginx.conf /etc/nginx/nginx.conf
#   cp "$APP_PATH"/conf/nginx/webvirtcloud.conf /etc/nginx/conf.d/

#   if [ -n "$fqdn" ]; then
#      fqdn_escape="$(echo -n "$fqdn"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
#      sed -i "s|\\(#server_name\\).*|server_name $fqdn_escape;|" "$nginxfile"
#   fi

#   novncd_port_escape="$(echo -n "$novncd_port"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
#   sed -i "s|\\(server 127.0.0.1:\\).*|\\1$novncd_port_escape;|" "$nginxfile"

# }

# configure_supervisor () {
#   # Copy template supervisor service for gunicorn and novnc
#   echo "  * Copying supervisor configuration"
#   cp "$APP_PATH"/conf/supervisor/webvirtcloud.conf "$supervisor_conf_path"/"$supervisor_file_name"
#   nginx_group_escape="$(echo -n "$nginx_group"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
#   sed -i "s|^\\(user=\\).*|\\1$nginx_group_escape|" "$supervisor_conf_path/$supervisor_file_name"
# }

create_user () {
  echo "* Creating webvirtcloud user."

  if [ "$distro" == "ubuntu" ] || [ "$distro" == "debian" ] || [ "$distro" == "AstraLinuxSE" ] ; then
    adduser --quiet --disabled-password --gecos '""' "$APP_USER"
  else
    adduser "$APP_USER"
  fi

  usermod -a -G "$nginx_group" "$APP_USER"
}

run_as_app_user () {
  echo -e "
  \033[1;31mAPP_USER -> $APP_USER
  \033[0m"
  if ! hash sudo 2>/dev/null; then
      su -c "$@" "$APP_USER"
  else
      sudo -i -u "$APP_USER" "$@"
  fi
}

activate_python_environment () {
    $PYTHON -m pip install virtualenv
    cd "$APP_PATH" || exit
    $PYTHON -m venv venv
#    virtualenv -p "$PYTHON" venv
    # shellcheck disable=SC1091
    source venv/bin/activate
}

generate_secret_key() {
  "$PYTHON" - <<END
import random
print(''.join(random.SystemRandom().choice('abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*(-_=+)') for i in range(50)))
END
}

install_webvirtcloud () {
  create_user
 
  echo -e "* Клонирование репозитория \033[1;32m$APP_NAME \033[0mиз github в веб-каталог."
  log "git clone $APP_REPO_URL $APP_PATH"

  echo -e "* Настройка \033[1;32msettings.py \033[0mфайла."
  cp "$APP_PATH/webvirtcloud/settings.py.template" "$APP_PATH/webvirtcloud/settings.py"
  
  secret_key=$(generate_secret_key)

  echo "* Секретный ключ для Django сгенерирован: \033[1;32m$secret_key\033[0m"
  tzone_escape="$(echo -n "$tzone"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
  secret_key_escape="$(echo -n "$secret_key"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
  novncd_port_escape="$(echo -n "$novncd_port"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
  novncd_public_port_escape="$(echo -n "$novncd_public_port"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"
  novncd_host_escape="$(echo -n "$novncd_host"|sed -e 's/[](){}<>=:\!\?\+\|\/\&$*.^[]/\\&/g')"

  #TODO escape SED delimiter in variables
  sed -i "s|^\\(TIME_ZONE = \\).*|\\1$tzone_escape|" "$APP_PATH/webvirtcloud/settings.py"
  sed -i "s|^\\(SECRET_KEY = \\).*|\\1\'$secret_key_escape\'|" "$APP_PATH/webvirtcloud/settings.py"
  sed -i "s|^\\(WS_PORT = \\).*|\\1$novncd_port_escape|" "$APP_PATH/webvirtcloud/settings.py"
  sed -i "s|^\\(WS_PUBLIC_PORT = \\).*|\\1$novncd_public_port_escape|" "$APP_PATH/webvirtcloud/settings.py"
  sed -i "s|^\\(WS_HOST = \\).*|\\1\'$novncd_host_escape\'|" "$APP_PATH/webvirtcloud/settings.py"

  echo "* Активация виртуальной среды."
  activate_python_environment

  echo "* Установка Python зависимостей для приложения."
  
  $PYTHON -m pip install -U pip
  $PYTHON -m pip install -r conf/requirements.txt -q
#  $pip3 install --upgrade pip
#  $pip3 install --requirement conf/requirements.txt --quiet

  chown -R "$nginx_group":"$nginx_group" "$APP_PATH"

  echo "* Django Migrate."
  log "$PYTHON $APP_PATH/manage.py migrate"
  $PYTHON $APP_PATH/manage.py migrate
  $PYTHON $APP_PATH/manage.py makemigrations

  chown -R "$nginx_group":"$nginx_group" "$APP_PATH"
}

set_firewall () {
  echo "* Настройка Firewall."
  if [ "$(firewall-cmd --state)" == "running" ]; then
    echo "* Настройка брандмауэра для разрешения трафика HTTP и novnc."
    log "firewall-cmd --zone=public --add-port=http/tcp --permanent"
    log "firewall-cmd --zone=public --add-port=$novncd_port/tcp --permanent"
    #firewall-cmd --zone=public --add-port=$novncd_port/tcp --permanent
    log "firewall-cmd --zone=public --add-port=$novncd_public_port/tcp --permanent"
    #firewall-cmd --zone=public --add-port=$novncd_public_port/tcp --permanent
    log "firewall-cmd --reload"
    #firewall-cmd --reload
  fi
}

set_selinux () {
  #Проверьте, принудительно ли SELinux
  if [ "$(getenforce)" == "Enforcing" ]; then
    echo "* Настройка SELinux."
    #Устанавливает тип контекста SELinux, чтобы скриптам, запущенным в процессе веб-сервера, был разрешен доступ для чтения/записи.
    chcon -R -h -t httpd_sys_rw_content_t "$APP_PATH/"
    setsebool -P httpd_can_network_connect 1
  fi
}

set_hosts () {
  echo "* Настройка файла hosts."
  echo >> /etc/hosts "127.0.0.1 $(hostname) $fqdn"
}

# restart_supervisor () {
#     echo "* Setting Supervisor to start on boot and restart."
#     log "systemctl enable $supervisor_service"
#     #systemctl enable $supervisor_service
#     log "systemctl restart $supervisor_service"
#     #systemctl restart $supervisor_service
# }

# restart_nginx () {
#     echo "* Setting Nginx to start on boot and starting Nginx."
#     log "systemctl enable nginx.service"
#     #systemctl enable nginx.service
#     log "systemctl restart nginx.service"
#     #systemctl restart nginx.service
# }


if [[ -f /etc/lsb-release || -f /etc/debian_version ]]; then
  distro="$(lsb_release -is)"
  version="$(lsb_release -rs)"
  codename="$(lsb_release -cs)"
elif [ -f /etc/os-release ]; then
  # shellcheck disable=SC1091
  distro="$(source /etc/os-release && echo "$ID")"
  # shellcheck disable=SC1091
  version="$(source /etc/os-release && echo "$VERSION_ID")"
  #Order is important here.  If /etc/os-release and /etc/centos-release exist, we're on centos 7.
  #If only /etc/centos-release exist, we're on centos6(or earlier).  Centos-release is less parsable,
  #so lets assume that it's version 6 (Plus, who would be doing a new install of anything on centos5 at this point..)
  #/etc/os-release properly detects fedora
elif [ -f /etc/centos-release ]; then
  distro="centos"
  version="8"
else
  distro="unsupported"
fi

sudo bash /mnt/mount.sh

echo '
      КП КОП 2.0
'

echo -e " 
\033[1;4;32mУстановка модуля управления виртуальными машинами КП КОП 2.0!\033[0m
"
shopt -s nocasematch
# case $distro in
#   *ubuntu*)
#     echo "  The installer has detected $distro version $version codename $codename."
#     distro=ubuntu
#     nginx_group=www-data
#     nginxfile=/etc/nginx/conf.d/$APP_NAME.conf
#     supervisor_service=supervisord
#     supervisor_conf_path=/etc/supervisor/conf.d
#     supervisor_file_name=webvirtcloud.conf
#     ;;
#   *debian*|*AstraLinuxSE*)
#     echo "  The installer has detected $distro version $version codename $codename."
#     distro=debian
#     nginx_group=www-data
#     nginxfile=/etc/nginx/conf.d/$APP_NAME.conf
#     supervisor_service=supervisor
#     supervisor_conf_path=/etc/supervisor/conf.d
#     supervisor_file_name=webvirtcloud.conf
#     ;;
#   *)
#     echo "  The installer was unable to determine your OS. Exiting for safety."
#     exit 1
#     ;;
# esac

echo -e "     \033[1;31mДистрибутив - $distro, версия - $version\033[0m"

setupfqdn=default
until [[ $setupfqdn == "yes" ]] || [[ $setupfqdn == "no" ]]; do
  echo -n "  Q. Do you want to configure fqdn for Nginx? (y/n) "
  read -r setupfqdn

  case $setupfqdn in
    [yY] | [yY][Ee][Ss] )
    echo -n "  Q. Какое полное доменное имя вашего сервера? ($(hostname --fqdn)): "
      read -r fqdn
      if [ -z "$fqdn" ]; then
      readonly fqdn="$(hostname --fqdn)"
      fi
      setupfqdn="yes"
      echo "     Установка на $fqdn"
      echo ""
      ;;
    [nN] | [n|N][O|o] )
      setupfqdn="no"
      ;;
    *)  echo -e "  \033[1;31mНеверный ответ. Пожалуйста, введите \033[1;32my \033[1;31mили \033[1;32mn\033[0m"
      ;;
  esac
done

echo -n "  Q. Вы хотите изменить номер сервисного порта NOVNC? (По умолчанию: 6080) "
read -r novncd_port
if [ -z "$novncd_port" ]; then
  readonly novncd_port=6080
fi
echo "     Настройка порта службы novnc $novncd_port"
echo ""

echo -n "  Q. Вы хотите изменить номер публичного порта NOVNC для обратного прокси (например, 80 или 443)? (По умолчанию: 6080) "
read -r novncd_public_port
if [ -z "$novncd_public_port" ]; then
  readonly novncd_public_port=6080
fi
echo "     Настройка публичного порта novnc $novncd_public_port"
echo ""

echo -n "  Q. Вы хотите изменить IP-адрес прослушивания хоста NOVNC? (По умолчанию: 0.0.0.0) "
read -r novncd_host
if [ -z "$novncd_host" ]; then
  readonly novncd_host="0.0.0.0"
fi
echo "     Настройка IP-адреса хоста novnc $novncd_host"
echo ""


case $distro in
  debian)
  # shellcheck disable=SC2072
  if [[ "$version" -ge 9 ]] || [[ "$version" == "1.6" ]]; then
    # Install for Debian 9.x / 10.x
    tzone=\'$(cat /etc/timezone)\'

    echo -n "* Обновление установленных пакетов в ОС."
    log "apt-get update && apt-get -y upgrade" & pid=$!
    progress

    echo "*  Установка зависимостей ОС."
#    PACKAGES="git virtualenv python3-virtualenv python3-dev python3-lxml libvirt-dev zlib1g-dev libxslt1-dev nginx supervisor libsasl2-modules gcc pkg-config python3-guestfs uuid"
    PACKAGES="git python3-virtualenv python3-dev python3-lxml libvirt-dev zlib1g-dev libxslt1-dev nginx supervisor libsasl2-modules gcc pkg-config python3-guestfs uuid"
    install_packages

    set_hosts

    install_webvirtcloud

    # echo "* Configuring Nginx."
    # configure_nginx

    # echo "* Configuring Supervisor."
    # configure_supervisor

    # restart_supervisor
    # restart_nginx
  fi
  ;;
  AstraLinuxSE)
    # Install for Debian 9.x / 10.x
    tzone=\'$(cat /etc/timezone)\'

    echo -n "* Обновление установленных пакетов."
    log "apt-get update && apt-get -y upgrade" & pid=$!
    progress

    echo "*  Установка зависимостей ОС."
    PACKAGES="git virtualenv python3-virtualenv python3-dev python3-lxml libvirt-dev zlib1g-dev libxslt1-dev nginx supervisor libsasl2-modules gcc pkg-config python3-guestfs uuid"
    install_packages

    set_hosts

    install_webvirtcloud

#    echo "* Configuring Nginx."
#    configure_nginx

#    echo "* Configuring Supervisor."
#    configure_supervisor
#
#    restart_supervisor
#    restart_nginx
  ;;
esac


echo ""
echo "  ***Открыть http://$fqdn, логин и пароль для входа: admin.***"
echo ""
echo ""
echo "* Очистка установки..."
rm -f webvirtcloud.sh
rm -f install.sh
echo "* Всё сделано!"
sleep 1
