#!/usr/bin/env bash
set -Eeuo pipefail

CADDYFILE="${CADDYFILE:-/etc/caddy/Caddyfile}"
CADDY_SITES_DIR="${CADDY_SITES_DIR:-/etc/caddy/sites}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите скрипт от root: sudo $0" >&2
  exit 1
fi

if [[ -z "${DOMAIN:-}" ]]; then
  read -r -p "Укажите домен для установки: " DOMAIN
fi

DOMAIN="$(printf '%s' "${DOMAIN}" | LC_ALL=C tr -cd 'A-Za-z0-9.:/-')"
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"
DOMAIN="${DOMAIN%%:*}"
DOMAIN="${DOMAIN,,}"

if [[ ! "${DOMAIN}" =~ ^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$ ]]; then
  echo "Некорректный домен: ${DOMAIN}" >&2
  exit 1
fi

WEB_ROOT="${WEB_ROOT:-/var/www/${DOMAIN}}"

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

# При первой установке создаём основной Caddyfile из шаблона.
if [[ ! -f "${CADDYFILE}" ]]; then
  install -d -m 0755 "$(dirname -- "${CADDYFILE}")"
  sed \
    -e "s/fi2\\.eesta\\.pro/${DOMAIN}/g" \
    -e "s|/var/www/selfsteal|${WEB_ROOT}|g" \
    "${SCRIPT_DIR}/Caddyfile" >"${CADDYFILE}"
  chmod 0644 "${CADDYFILE}"
  echo "Создан ${CADDYFILE}"
elif grep -Fq "https://${DOMAIN}" "${CADDYFILE}"; then
  # Для ранее установленного домена меняем только root его HTTPS-блока.
  cp -a "${CADDYFILE}" "${CADDYFILE}.backup"
  awk -v domain="${DOMAIN}" -v web_root="${WEB_ROOT}" '
    index($0, "https://" domain) { site = 1 }
    site && $1 == "root" && $2 == "*" {
      match($0, /^[[:space:]]*/)
      print substr($0, RSTART, RLENGTH) "root * " web_root
      next
    }
    { print }
    site && /^[[:space:]]*}/ { site = 0 }
  ' "${CADDYFILE}.backup" >"${CADDYFILE}"
  echo "Путь сайта ${DOMAIN} обновлён в ${CADDYFILE}"
else
  # Дополнительные домены размещаем в отдельных управляемых фрагментах.
  install -d -m 0755 "${CADDY_SITES_DIR}"
  SITE_FILE="${CADDY_SITES_DIR}/${DOMAIN}.caddy"
  cat >"${SITE_FILE}" <<EOF
http://${DOMAIN} {
	bind 0.0.0.0
	redir https://${DOMAIN}{uri} permanent
}

https://${DOMAIN} {
	root * ${WEB_ROOT}
	encode zstd gzip

	header {
		X-Robots-Tag "noindex, nofollow, noarchive, nosnippet"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		-Server
	}

	file_server
}
EOF
  if ! grep -Fq "import ${CADDY_SITES_DIR}/*.caddy" "${CADDYFILE}"; then
    printf '\nimport %s/*.caddy\n' "${CADDY_SITES_DIR}" >>"${CADDYFILE}"
  fi
  caddy fmt --overwrite "${SITE_FILE}"
  echo "Создана конфигурация ${SITE_FILE}"
fi

caddy fmt --overwrite "${CADDYFILE}"
caddy validate --config "${CADDYFILE}"
systemctl reload caddy

echo
echo "Сайт установлен в ${WEB_ROOT}"
echo "Проверка локального TLS:"
echo "openssl s_client -connect 127.0.0.1:9443 -servername ${DOMAIN} -brief"
