#!/usr/bin/env bash
set -Eeuo pipefail

# Публичный репозиторий:
# REPOSITORY=https://github.com/USERNAME/eesta-site.git ./install-from-git.sh
#
# Приватный репозиторий:
# REPOSITORY=git@github.com:USERNAME/eesta-site.git \
# DEPLOY_KEY=/root/.ssh/eesta_site_deploy ./install-from-git.sh

REPOSITORY="${REPOSITORY:?Укажите адрес Git-репозитория}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-/opt/eesta-site}"
DEPLOY_KEY="${DEPLOY_KEY:-}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите скрипт от root." >&2
  exit 1
fi

if [[ -z "${DOMAIN:-}" ]]; then
  read -r -p "Укажите домен для установки: " DOMAIN
fi

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

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y git
fi

if [[ -n "${DEPLOY_KEY}" ]]; then
  if [[ ! -f "${DEPLOY_KEY}" ]]; then
    echo "Не найден Deploy Key: ${DEPLOY_KEY}" >&2
    exit 1
  fi
  export GIT_SSH_COMMAND="ssh -i ${DEPLOY_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
elif [[ "${REPOSITORY}" == git@* ]]; then
  echo "Для SSH-адреса укажите DEPLOY_KEY либо используйте публичный HTTPS-адрес." >&2
  exit 1
fi

if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
elif [[ -e "${APP_DIR}" ]]; then
  echo "${APP_DIR} уже существует, но не является Git-репозиторием." >&2
  exit 1
else
  git clone --branch "${BRANCH}" --single-branch "${REPOSITORY}" "${APP_DIR}"
fi

chmod +x "${APP_DIR}/install.sh"
DOMAIN="${DOMAIN}" WEB_ROOT="${WEB_ROOT}" "${APP_DIR}/install.sh"

echo "Установка ${DOMAIN} завершена. Для обновления повторно запустите эту же команду."
