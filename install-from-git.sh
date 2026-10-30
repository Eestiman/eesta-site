#!/usr/bin/env bash
set -Eeuo pipefail

# Пример:
# REPOSITORY=git@github.com:USERNAME/eesta-site.git ./install-from-git.sh

REPOSITORY="${REPOSITORY:?Укажите REPOSITORY, например git@github.com:USERNAME/eesta-site.git}"
BRANCH="${BRANCH:-main}"
APP_DIR="${APP_DIR:-/opt/eesta-site}"
DEPLOY_KEY="${DEPLOY_KEY:-/root/.ssh/eesta_site_deploy}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите скрипт от root." >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  apt-get update
  apt-get install -y git
fi

if [[ ! -f "${DEPLOY_KEY}" ]]; then
  echo "Не найден Deploy Key: ${DEPLOY_KEY}" >&2
  exit 1
fi

export GIT_SSH_COMMAND="ssh -i ${DEPLOY_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"

if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only origin "${BRANCH}"
elif [[ -e "${APP_DIR}" ]]; then
  echo "${APP_DIR} уже существует, но не является Git-репозиторием." >&2
  exit 1
else
  git clone --branch "${BRANCH}" --single-branch "${REPOSITORY}" "${APP_DIR}"
fi

chmod +x "${APP_DIR}/install.sh"
"${APP_DIR}/install.sh"

echo "Установка завершена. Для обновления повторно запустите эту же команду."
