#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="${DOMAIN:-fi2.eesta.pro}"
WEB_ROOT="${WEB_ROOT:-/var/www/selfsteal}"
CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите скрипт от root: sudo $0" >&2
  exit 1
fi

for file in index.html robots.txt favicon.svg; do
  if [[ ! -f "${SCRIPT_DIR}/${file}" ]]; then
    echo "Не найден файл ${SCRIPT_DIR}/${file}" >&2
    exit 1
  fi
done

if ! command -v caddy >/dev/null 2>&1; then
  echo "Caddy не установлен. Сначала установите Caddy из официального репозитория." >&2
  exit 1
fi

install -d -m 0755 "${WEB_ROOT}"
install -m 0644 "${SCRIPT_DIR}/index.html" "${WEB_ROOT}/index.html"
install -m 0644 "${SCRIPT_DIR}/robots.txt" "${WEB_ROOT}/robots.txt"
install -m 0644 "${SCRIPT_DIR}/favicon.svg" "${WEB_ROOT}/favicon.svg"

if id caddy >/dev/null 2>&1; then
  chown -R caddy:caddy "${WEB_ROOT}"
fi

# Создаём Caddyfile только при его отсутствии. Существующую конфигурацию,
# где могут быть другие сайты и Layer4-маршруты, скрипт не перезаписывает.
if [[ ! -f "${CADDYFILE}" ]]; then
  install -d -m 0755 "$(dirname -- "${CADDYFILE}")"
  sed "s/fi2\\.eesta\\.pro/${DOMAIN}/g" "${SCRIPT_DIR}/Caddyfile" >"${CADDYFILE}"
  chmod 0644 "${CADDYFILE}"
  echo "Создан ${CADDYFILE}"
else
  echo "Существующий ${CADDYFILE} сохранён без изменений."
fi

caddy fmt --overwrite "${CADDYFILE}"
caddy validate --config "${CADDYFILE}"
systemctl reload caddy

echo
echo "Сайт установлен в ${WEB_ROOT}"
echo "Проверка локального TLS:"
echo "openssl s_client -connect 127.0.0.1:9443 -servername ${DOMAIN} -brief"
