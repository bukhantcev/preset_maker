#!/usr/bin/env bash
set -Eeuo pipefail

APP_NAME="presetmaker"
APP_IMAGE_DEFAULT="chtotos/presetmaker:latest"
APP_DIR_DEFAULT="/opt/presetmaker"
HTTP_PORT="8000"
CERTBOT_WEBROOT="/var/www/presetmaker-certbot"

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_as_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

prompt_required() {
  local label="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -p "${label}: " value
  done
  printf '%s' "${value}"
}

prompt_secret() {
  local label="$1"
  local value=""
  while [[ -z "${value}" ]]; do
    read -r -s -p "${label}: " value
    echo
  done
  printf '%s' "${value}"
}

env_quote() {
  local value="${1//$'\r'/}"
  if [[ "${value}" == *$'\n'* ]]; then
    echo "Значения для .env не должны содержать перенос строки." >&2
    exit 1
  fi
  printf "'%s'" "$(printf '%s' "${value}" | sed "s/'/\\\\'/g")"
}

detect_compose() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif need_cmd docker-compose; then
    echo "docker-compose"
  else
    echo ""
  fi
}

install_base_packages() {
  run_as_root apt-get update
  run_as_root apt-get install -y ca-certificates curl gnupg lsb-release openssl ufw
}

install_docker() {
  if need_cmd docker && docker --version >/dev/null 2>&1 && [[ -n "$(detect_compose)" ]]; then
    echo "Docker уже установлен."
    return
  fi

  echo "Ставлю Docker..."
  install_base_packages
  run_as_root install -m 0755 -d /etc/apt/keyrings
  local docker_os
  docker_os="$(. /etc/os-release && echo "${ID}")"
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    local docker_gpg_tmp
    docker_gpg_tmp="$(mktemp)"
    curl -fsSL "https://download.docker.com/linux/${docker_os}/gpg" -o "${docker_gpg_tmp}"
    run_as_root gpg --dearmor -o /etc/apt/keyrings/docker.gpg "${docker_gpg_tmp}"
    rm -f "${docker_gpg_tmp}"
    run_as_root chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename
  codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
  if [[ -z "${codename}" ]]; then
    codename="$(lsb_release -cs)"
  fi

  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${docker_os} ${codename} stable" |
    run_as_root tee /etc/apt/sources.list.d/docker.list >/dev/null

  run_as_root apt-get update
  run_as_root apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  run_as_root systemctl enable --now docker
}

install_nginx_certbot() {
  echo "Проверяю Nginx и Certbot..."
  install_base_packages
  run_as_root apt-get install -y nginx certbot python3-certbot-nginx
  run_as_root systemctl enable --now nginx
}

write_env() {
  local env_path="$1"
  local secret_key="$2"
  local yandex_client_id="$3"
  local yandex_client_secret="$4"
  local admin_email="$5"
  local admin_password="$6"

  run_as_root tee "${env_path}" >/dev/null <<EOF
SECRET_KEY=$(env_quote "${secret_key}")
SQLALCHEMY_DATABASE_URL=$(env_quote "sqlite:////data/passport_creator.db")
BASE_TEMP_DIR=$(env_quote "/tmp/passport_creator/users")
YANDEX_CLIENT_ID=$(env_quote "${yandex_client_id}")
YANDEX_CLIENT_SECRET=$(env_quote "${yandex_client_secret}")
ADMIN_EMAIL=$(env_quote "${admin_email}")
ADMIN_PASSWORD=$(env_quote "${admin_password}")
EOF
  run_as_root chmod 600 "${env_path}"
}

write_compose() {
  local compose_path="$1"
  local image="$2"
  run_as_root tee "${compose_path}" >/dev/null <<EOF
services:
  web:
    image: ${image}
    restart: unless-stopped
    env_file:
      - .env
    environment:
      - PYTHONUNBUFFERED=1
    ports:
      - "127.0.0.1:${HTTP_PORT}:8000"
    volumes:
      - ./data:/data
      - passport_projects:/tmp/passport_creator

volumes:
  passport_projects:
EOF
}

write_nginx_http() {
  local domain="$1"
  local nginx_path="/etc/nginx/sites-available/${APP_NAME}"
  run_as_root mkdir -p "${CERTBOT_WEBROOT}"
  run_as_root tee "${nginx_path}" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    client_max_body_size 500m;

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF
  run_as_root ln -sf "${nginx_path}" "/etc/nginx/sites-enabled/${APP_NAME}"
  run_as_root nginx -t
  run_as_root systemctl reload nginx
}

write_nginx_https() {
  local domain="$1"
  local nginx_path="/etc/nginx/sites-available/${APP_NAME}"
  run_as_root tee "${nginx_path}" >/dev/null <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};

    location /.well-known/acme-challenge/ {
        root ${CERTBOT_WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    client_max_body_size 500m;

    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 300;
        proxy_send_timeout 300;
    }
}
EOF
  run_as_root ln -sf "${nginx_path}" "/etc/nginx/sites-enabled/${APP_NAME}"
  run_as_root nginx -t
  run_as_root systemctl reload nginx
}

configure_firewall() {
  if need_cmd ufw && run_as_root ufw status | grep -q "Status: active"; then
    run_as_root ufw allow OpenSSH || true
    run_as_root ufw allow 'Nginx Full' || true
  fi
}

issue_certificate() {
  local domain="$1"
  local email="$2"
  echo "Выпускаю SSL-сертификат Let's Encrypt для ${domain}..."
  run_as_root mkdir -p "${CERTBOT_WEBROOT}"
  run_as_root certbot certonly --webroot \
    --non-interactive \
    --agree-tos \
    --keep-until-expiring \
    --webroot-path "${CERTBOT_WEBROOT}" \
    --email "${email}" \
    --cert-name "${domain}" \
    -d "${domain}"
  write_nginx_https "${domain}"
}

main() {
  if [[ ! -f /etc/os-release ]]; then
    echo "Этот установщик рассчитан на Ubuntu/Debian сервер." >&2
    exit 1
  fi
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" && "${ID}" != "debian" ]]; then
    echo "Этот установщик рассчитан на Ubuntu/Debian. Текущая ОС: ${PRETTY_NAME:-unknown}" >&2
    exit 1
  fi

  echo "=== Passport Creator production install ==="
  local domain app_dir image le_email yandex_client_id yandex_client_secret admin_email admin_password secret_key compose_cmd
  domain="$(prompt_required "Домен без https, например pc.example.com")"
  read -r -p "Папка установки [${APP_DIR_DEFAULT}]: " app_dir
  app_dir="${app_dir:-${APP_DIR_DEFAULT}}"
  read -r -p "Docker image [${APP_IMAGE_DEFAULT}]: " image
  image="${image:-${APP_IMAGE_DEFAULT}}"
  le_email="$(prompt_required "Email для Let's Encrypt")"
  yandex_client_id="$(prompt_required "Yandex Client ID")"
  yandex_client_secret="$(prompt_secret "Yandex Client Secret")"
  admin_email="$(prompt_required "Email суперюзера/админа")"
  admin_password="$(prompt_secret "Пароль суперюзера/админа")"
  secret_key="$(openssl rand -hex 32)"

  install_docker
  install_nginx_certbot
  configure_firewall

  run_as_root mkdir -p "${app_dir}/data"
  write_env "${app_dir}/.env" "${secret_key}" "${yandex_client_id}" "${yandex_client_secret}" "${admin_email}" "${admin_password}"
  write_compose "${app_dir}/docker-compose.yml" "${image}"

  compose_cmd="$(detect_compose)"
  if [[ -z "${compose_cmd}" ]]; then
    echo "Docker Compose не найден после установки." >&2
    exit 1
  fi

  echo "Тяну контейнер ${image} и запускаю приложение..."
  (cd "${app_dir}" && run_as_root ${compose_cmd} pull && run_as_root ${compose_cmd} up -d)

  write_nginx_http "${domain}"
  issue_certificate "${domain}" "${le_email}"

  echo "Проверяю приложение..."
  (cd "${app_dir}" && run_as_root ${compose_cmd} ps)
  if ! curl -fsS "https://${domain}/" >/dev/null; then
    echo "Сайт поднят, но HTTPS-проверка не прошла. Проверь DNS домена и логи: cd ${app_dir} && ${compose_cmd} logs -f" >&2
  fi

  echo
  echo "Готово."
  echo "Сайт: https://${domain}"
  echo "Папка: ${app_dir}"
  echo "Админ: ${admin_email}"
  echo
  echo "Yandex OAuth redirect URI, которые нужно добавить в приложение Yandex:"
  echo "  https://${domain}/auth/yandex/callback"
  echo "  https://${domain}/auth/yandex/disk_callback"
  echo
  echo "Полезные команды:"
  echo "  cd ${app_dir} && ${compose_cmd} logs -f"
  echo "  cd ${app_dir} && ${compose_cmd} pull && ${compose_cmd} up -d"
}

main "$@"
