#!/usr/bin/env bash

set -Eeuo pipefail

SCRIPT_VERSION="1.1.0"

case "${1:-}" in
    --version|-v)
        echo "sync_repo_from_git.sh ${SCRIPT_VERSION}"
        exit 0
        ;;
esac

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_FILE="${SCRIPT_DIR}/$(basename -- "${BASH_SOURCE[0]}")"
if [[ -n "${GIT_REPO_DIR:-}" ]]; then
    REPO_DIR="${GIT_REPO_DIR}"
elif [[ "$(basename -- "${SCRIPT_DIR}")" == ".deploy" ]]; then
    REPO_DIR="${SCRIPT_DIR}/.."
else
    REPO_DIR="$(pwd)"
fi
REPO_DIR="$(cd -- "${REPO_DIR}" && pwd)"
PROJECT_CONFIG_DIR="${GIT_SYNC_CONFIG_DIR:-${SCRIPT_DIR}}"
CONFIG_FILE="${GIT_SYNC_CONFIG:-${PROJECT_CONFIG_DIR}/sync_repo_from_git.conf}"
SCRIPT_RELATIVE_PATH=""
if [[ "${SCRIPT_FILE}" == "${REPO_DIR}/"* ]]; then
    SCRIPT_RELATIVE_PATH="${SCRIPT_FILE#"${REPO_DIR}/"}"
fi
REMOTE=""
REPOSITORY_URL=""
BRANCH=""
AUTH_MODE=""
AUTH_USERNAME=""
AUTH_SECRET=""
SSH_PRIVATE_KEY=""
SSH_PRIVATE_KEY_PATH=""
ASKPASS_FILE=""
UPDATE_TEMP_FILE=""
TOOL_REPOSITORY_URL="${SYNC_REPO_TOOL_REPOSITORY:-https://github.com/EugeneSlusar/sync-repo.orgbox.net.git}"
TOOL_REPOSITORY_REF="${SYNC_REPO_TOOL_REF:-main}"

cleanup() {
    if [[ -n "${ASKPASS_FILE}" ]] && [[ -f "${ASKPASS_FILE}" ]]; then
        rm -f -- "${ASKPASS_FILE}"
    fi
    if [[ -n "${UPDATE_TEMP_FILE}" ]] && [[ -f "${UPDATE_TEMP_FILE}" ]]; then
        rm -f -- "${UPDATE_TEMP_FILE}"
    fi
}

trap cleanup EXIT

printf '\033[2J\033[H'

is_tool_repository() {
    local current_remote normalized_current normalized_tool

    current_remote="$(git -C "${REPO_DIR}" remote get-url origin 2>/dev/null || true)"
    normalized_current="${current_remote%.git}"
    normalized_tool="${TOOL_REPOSITORY_URL%.git}"
    [[ "${normalized_current}" == "${normalized_tool}" ]] \
        || [[ "${normalized_current}" == "git@github.com:EugeneSlusar/sync-repo.orgbox.net" ]]
}

update_script_from_central_repository() {
    local raw_url current_mode

    [[ "${SYNC_REPO_AUTO_UPDATE:-1}" == "1" ]] || return 0
    is_tool_repository && return 0
    command -v curl >/dev/null 2>&1 || return 0

    raw_url="https://raw.githubusercontent.com/EugeneSlusar/sync-repo.orgbox.net/${TOOL_REPOSITORY_REF}/.deploy/sync_repo_from_git.sh"
    UPDATE_TEMP_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-repo-script.XXXXXX")"
    if ! curl -fsSL --connect-timeout 10 --max-time 30 "${raw_url}" -o "${UPDATE_TEMP_FILE}"; then
        echo "Предупреждение: не удалось проверить обновление sync_repo_from_git.sh." >&2
        return 0
    fi

    if ! cmp -s "${SCRIPT_FILE}" "${UPDATE_TEMP_FILE}"; then
        current_mode="$(stat -c '%a' "${SCRIPT_FILE}" 2>/dev/null || true)"
        mv -f -- "${UPDATE_TEMP_FILE}" "${SCRIPT_FILE}"
        UPDATE_TEMP_FILE=""
        if [[ -n "${current_mode}" ]]; then
            chmod "${current_mode}" "${SCRIPT_FILE}" 2>/dev/null || chmod +x "${SCRIPT_FILE}"
        else
            chmod +x "${SCRIPT_FILE}"
        fi
        echo "Скрипт sync_repo_from_git.sh обновлён из центрального репозитория."
    fi
}

update_script_from_central_repository

ensure_local_files_are_excluded() {
    local exclude_file exclude_pattern protected_file relative_path

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    exclude_file="$(git rev-parse --git-path info/exclude)"

    mkdir -p -- "$(dirname -- "${exclude_file}")"
    touch "${exclude_file}"
    for protected_file in \
        "${CONFIG_FILE}" \
        "${PROJECT_CONFIG_DIR}/sync_repo_deploy_key" \
        "${PROJECT_CONFIG_DIR}/sync_repo_deploy_key.pub"; do
        relative_path="${protected_file#"${REPO_DIR}/"}"
        exclude_pattern="/${relative_path}"
        if ! grep -Fqx -- "${exclude_pattern}" "${exclude_file}"; then
            printf '%s\n' "${exclude_pattern}" >> "${exclude_file}"
        fi
    done
}

load_config() {
    local key value

    [[ -f "${CONFIG_FILE}" ]] || return 1

    while IFS='=' read -r key value || [[ -n "${key}" ]]; do
        value="${value%$'\r'}"
        case "${key}" in
            REPOSITORY_URL) REPOSITORY_URL="${value}" ;;
            REMOTE) REMOTE="${value}" ;;
            BRANCH) BRANCH="${value}" ;;
            AUTH_MODE) AUTH_MODE="${value}" ;;
            AUTH_USERNAME) AUTH_USERNAME="${value}" ;;
            AUTH_SECRET) AUTH_SECRET="${value}" ;;
            SSH_PRIVATE_KEY) SSH_PRIVATE_KEY="${value}" ;;
        esac
    done < "${CONFIG_FILE}"

    return 0
}

auth_config_is_valid() {
    if [[ "${AUTH_MODE}" == "ssh" ]] && [[ -n "${SSH_PRIVATE_KEY}" ]]; then
        resolve_ssh_private_key
        [[ -f "${SSH_PRIVATE_KEY_PATH}" ]]
        return
    fi

    if [[ "${AUTH_MODE}" == "token" ]] && [[ -n "${AUTH_SECRET}" ]]; then
        AUTH_USERNAME="x-access-token"
        return 0
    fi

    [[ "${AUTH_MODE}" == "basic" ]] && [[ -n "${AUTH_USERNAME}" ]] && [[ -n "${AUTH_SECRET}" ]]
}

save_config() {
    mkdir -p -- "${PROJECT_CONFIG_DIR}"
    umask 077
    {
        echo "# Настройки sync_repo_from_git.sh. Не добавлять в Git."
        echo "# REPOSITORY_URL — адрес удалённого Git-репозитория (HTTPS или SSH)."
        echo "# REMOTE — локальное имя подключения Git, обычно origin."
        echo "# BRANCH — ветка, которую нужно разворачивать на сервере."
        echo "# AUTH_SECRET — PAT или пароль; хранить этот файл только с правами 600."
        printf 'REPOSITORY_URL=%s\n' "${REPOSITORY_URL}"
        printf 'REMOTE=%s\n' "${REMOTE}"
        printf 'BRANCH=%s\n' "${BRANCH}"
        printf 'AUTH_MODE=%s\n' "${AUTH_MODE}"
        printf 'AUTH_USERNAME=%s\n' "${AUTH_USERNAME}"
        printf 'AUTH_SECRET=%s\n' "${AUTH_SECRET}"
        printf 'SSH_PRIVATE_KEY=%s\n' "${SSH_PRIVATE_KEY}"
    } > "${CONFIG_FILE}"
    chmod 600 "${CONFIG_FILE}"
}

resolve_ssh_private_key() {
    if [[ "${SSH_PRIVATE_KEY}" == /* ]]; then
        SSH_PRIVATE_KEY_PATH="${SSH_PRIVATE_KEY}"
    else
        SSH_PRIVATE_KEY_PATH="${PROJECT_CONFIG_DIR}/${SSH_PRIVATE_KEY}"
    fi
}

convert_repository_url_to_ssh() {
    local host repository_path

    if [[ "${REPOSITORY_URL}" =~ ^https?://([^/]+)/(.+)$ ]]; then
        host="${BASH_REMATCH[1]}"
        repository_path="${BASH_REMATCH[2]}"
        REPOSITORY_URL="git@${host}:${repository_path}"
    fi
}

setup_deploy_key() {
    local public_key_path key_comment

    if ! command -v ssh-keygen >/dev/null 2>&1; then
        echo "Ошибка: ssh-keygen не установлен на сервере." >&2
        exit 1
    fi

    AUTH_MODE="ssh"
    AUTH_USERNAME=""
    AUTH_SECRET=""
    SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY:-sync_repo_deploy_key}"
    resolve_ssh_private_key
    public_key_path="${SSH_PRIVATE_KEY_PATH}.pub"
    key_comment="deploy-key:$(hostname):${BRANCH}"

    if [[ ! -f "${SSH_PRIVATE_KEY_PATH}" ]]; then
        echo "Создание SSH Deploy Key..."
        ssh-keygen -q -t ed25519 -C "${key_comment}" -f "${SSH_PRIVATE_KEY_PATH}" -N ""
    elif [[ ! -f "${public_key_path}" ]]; then
        ssh-keygen -y -f "${SSH_PRIVATE_KEY_PATH}" > "${public_key_path}"
    fi

    chmod 600 "${SSH_PRIVATE_KEY_PATH}"
    chmod 644 "${public_key_path}"
    convert_repository_url_to_ssh

    echo
    echo "Публичный Deploy Key:"
    echo "------------------------------------------------------------"
    command cat "${public_key_path}"
    echo "------------------------------------------------------------"
    echo "Добавьте его в GitHub: Repository → Settings → Deploy keys → Add deploy key."
    echo "Для обновления сервера достаточно ключа без Allow write access."
    echo
    read -r -p "После добавления ключа нажмите Enter для продолжения... "
}

request_auth() {
    local auth_choice token

    echo
    echo "Авторизация нужна, чтобы сервер мог читать закрытый репозиторий."
    echo "Для открытого репозитория ключ обычно не требуется, но Deploy Key рекомендуется для сервера."
    echo "Способ доступа к репозиторию:"
    echo "  1) SSH Deploy Key — ключ создаётся на сервере; публичную часть нужно добавить в"
    echo "     Settings → Deploy keys репозитория. Выберите этот вариант для постоянного deploy."
    echo "  2) GitHub Personal Access Token (PAT) — секретный токен из GitHub Settings → Developer settings."
    echo "  3) Логин и пароль/PAT — устаревший способ; на GitHub.com обычный пароль не работает."
    read -r -p "Выберите вариант [1]: " auth_choice
    auth_choice="${auth_choice:-1}"

    case "${auth_choice}" in
        1)
            setup_deploy_key
            ;;
        2)
            read -r -s -p "GitHub Personal Access Token: " token
            echo
            if [[ -z "${token}" ]]; then
                echo "Ошибка: токен не может быть пустым." >&2
                exit 1
            fi
            AUTH_MODE="token"
            AUTH_USERNAME="x-access-token"
            AUTH_SECRET="${token}"
            SSH_PRIVATE_KEY=""
            ;;
        3)
            AUTH_MODE="basic"
            read -r -p "Логин GitHub: " AUTH_USERNAME
            read -r -s -p "Пароль или Personal Access Token: " AUTH_SECRET
            echo
            SSH_PRIVATE_KEY=""

            if [[ -z "${AUTH_USERNAME}" ]] || [[ -z "${AUTH_SECRET}" ]]; then
                echo "Ошибка: логин и пароль не могут быть пустыми." >&2
                exit 1
            fi

            echo "Примечание: GitHub.com не принимает обычные пароли — используйте PAT."
            ;;
        *)
            echo "Ошибка: неизвестный способ авторизации." >&2
            exit 1
            ;;
    esac
}

create_github_repository() {
    local repository_name visibility repository_visibility

    if ! command -v gh >/dev/null 2>&1; then
        echo "Ошибка: для создания GitHub-репозитория установите GitHub CLI (gh)." >&2
        echo "Документация: https://cli.github.com/" >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "Сначала авторизуйтесь в GitHub CLI командой: gh auth login" >&2
        exit 1
    fi

    echo
    echo "Создание GitHub-репозитория из текущего проекта"
    read -r -p "Название репозитория [$(basename -- "${REPO_DIR}")]: " repository_name
    repository_name="${repository_name:-$(basename -- "${REPO_DIR}")}"
    if [[ ! "${repository_name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "Ошибка: название репозитория содержит недопустимые символы." >&2
        exit 1
    fi

    echo "1) Приватный репозиторий"
    echo "2) Публичный репозиторий"
    read -r -p "Вид репозитория [1]: " visibility
    case "${visibility}" in
        2) repository_visibility="--public" ;;
        *) repository_visibility="--private" ;;
    esac

    echo "Инициализация локального Git-репозитория..."
    git init -b main >/dev/null 2>&1 || git init >/dev/null
    git checkout -B main >/dev/null 2>&1
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "Initial commit" >/dev/null
    elif ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        git commit --allow-empty -m "Initial commit" >/dev/null
    fi

    echo "Создание репозитория на GitHub..."
    gh repo create "${repository_name}" "${repository_visibility}" \
        --source="${REPO_DIR}" --remote="${REMOTE}" --push
    REPOSITORY_URL="$(git remote get-url "${REMOTE}")"
    echo "GitHub-репозиторий подключён: ${REPOSITORY_URL}"
}

prepare_askpass() {
    ASKPASS_FILE="$(mktemp "${TMPDIR:-/tmp}/sync-repo-askpass.XXXXXX")"
    {
        echo '#!/usr/bin/env bash'
        echo 'case "$1" in'
        echo '    *Username*) printf '\''%s\n'\'' "$SYNC_GIT_USERNAME" ;;'
        echo '    *Password*) printf '\''%s\n'\'' "$SYNC_GIT_PASSWORD" ;;'
        echo 'esac'
    } > "${ASKPASS_FILE}"
    chmod 700 "${ASKPASS_FILE}"
}

fetch_repository() {
    # Shared hosting can impose a very small process/thread limit. Limiting
    # pack processing keeps fetch usable without changing the repository.
    git -c pack.threads=1 -c pack.windowMemory=32m "$@" fetch --prune "${REMOTE}"
}

cd "${REPO_DIR}"

if ! command -v git >/dev/null 2>&1; then
    echo "Ошибка: Git не установлен на сервере." >&2
    echo "Установите Git и повторно запустите скрипт." >&2
    exit 1
fi

GIT_IS_CONFIGURED=false
REMOTE_IS_CONFIGURED=false
CURRENT_BRANCH=""
DETECTED_REPOSITORY_URL=""

load_config || true

if [[ -z "${REMOTE}" ]]; then
    REMOTE="${GIT_REMOTE:-origin}"
fi

LOCAL_REMOTE_CONFIGURED=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git remote get-url "${REMOTE}" >/dev/null 2>&1; then
    LOCAL_REMOTE_CONFIGURED=true
fi

if [[ -z "${REPOSITORY_URL}" ]] && [[ "${LOCAL_REMOTE_CONFIGURED}" == false ]]; then
    echo
    echo "Проект ещё не подключён к удалённому Git-репозиторию."
    echo "1) Подключить существующий репозиторий"
    echo "2) Создать новый GitHub-репозиторий"
    read -r -p "Выберите вариант [1]: " setup_choice
    case "${setup_choice}" in
        2)
            create_github_repository
            ;;
        *)
            ;;
    esac
fi

if [[ -n "${GIT_REMOTE:-}" ]]; then
    REMOTE="${GIT_REMOTE}"
fi
if [[ -z "${REMOTE}" ]]; then
    echo
    echo "Имя Git remote — короткое локальное имя подключения Git, а не URL."
    echo "Обычно используется значение origin. Если вы случайно вставите URL сюда,"
    echo "скрипт автоматически распознает его и использует origin как имя подключения."
    read -r -p "Имя Git remote [origin]: " REMOTE
    REMOTE="${REMOTE:-origin}"
    if [[ "${REMOTE}" == *"://"* ]] || [[ "${REMOTE}" == git@*:* ]]; then
        REPOSITORY_URL="${REMOTE}"
        REMOTE="origin"
    else
        REMOTE="${REMOTE:-origin}"
    fi
fi

if [[ -e "${REPO_DIR}/.git" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    GIT_IS_CONFIGURED=true
    CURRENT_BRANCH="$(git symbolic-ref --quiet --short HEAD || true)"
    ensure_local_files_are_excluded

    if git remote get-url "${REMOTE}" >/dev/null 2>&1; then
        REMOTE_IS_CONFIGURED=true
        DETECTED_REPOSITORY_URL="$(git remote get-url "${REMOTE}")"
    fi
fi

if [[ -n "${GIT_REPOSITORY_URL:-}" ]]; then
    REPOSITORY_URL="${GIT_REPOSITORY_URL}"
fi
if [[ -z "${REPOSITORY_URL}" ]]; then
    echo
    echo "URL Git-репозитория — адрес проекта на GitHub/GitLab или другом Git-сервере."
    echo "Примеры: https://github.com/user/project.git"
    echo "         git@github.com:user/project.git"
    if [[ -n "${DETECTED_REPOSITORY_URL}" ]]; then
        read -r -p "URL Git-репозитория [${DETECTED_REPOSITORY_URL}]: " REPOSITORY_URL
        REPOSITORY_URL="${REPOSITORY_URL:-${DETECTED_REPOSITORY_URL}}"
    else
        read -r -p "URL Git-репозитория: " REPOSITORY_URL
    fi
fi
if [[ -z "${REPOSITORY_URL}" ]]; then
    echo "Ошибка: URL репозитория не может быть пустым." >&2
    exit 1
fi

if [[ -n "${GIT_BRANCH:-}" ]]; then
    BRANCH="${GIT_BRANCH}"
fi
if [[ -z "${BRANCH}" ]]; then
    DEFAULT_BRANCH="${CURRENT_BRANCH:-main}"
    echo
    echo "Ветка — имя линии разработки, которую нужно копировать на сервер."
    echo "Для основного стабильного кода обычно используется main (иногда master)."
    read -r -p "Ветка [${DEFAULT_BRANCH}]: " BRANCH
    BRANCH="${BRANCH:-${DEFAULT_BRANCH}}"
fi

if ! auth_config_is_valid; then
    request_auth
fi

save_config
if [[ "${GIT_IS_CONFIGURED}" == true ]]; then
    ensure_local_files_are_excluded
fi
case "${AUTH_MODE}" in
    ssh) AUTH_DESCRIPTION="SSH Deploy Key" ;;
    token) AUTH_DESCRIPTION="GitHub Personal Access Token" ;;
    basic) AUTH_DESCRIPTION="Логин и пароль/PAT" ;;
    *) AUTH_DESCRIPTION="не настроена" ;;
esac

echo "Настройки сохранены в ${CONFIG_FILE}."
echo
TABLE_LABEL_RULE=""
TABLE_VALUE_RULE=""
printf -v TABLE_LABEL_RULE '%*s' 15 ''
printf -v TABLE_VALUE_RULE '%*s' 92 ''
TABLE_LABEL_RULE="${TABLE_LABEL_RULE// /─}"
TABLE_VALUE_RULE="${TABLE_VALUE_RULE// /─}"
printf '┌%s┬%s┐\n' "${TABLE_LABEL_RULE}" "${TABLE_VALUE_RULE}"
printf '│ %s │ %-90s │\n' "Репозиторий  " "${REPO_DIR}"
printf '│ %s │ %-90s │\n' "Git remote   " "${REMOTE}"
printf '│ %s │ %-90s │\n' "Источник     " "${REPOSITORY_URL}"
printf '│ %s │ %-90s │\n' "Ветка        " "${BRANCH}"
printf '│ %s │ %-90s │\n' "Авторизация  " "${AUTH_DESCRIPTION}"
printf '│ %s │ %-90s │\n' "Конфигурация " "${CONFIG_FILE}"
printf '│ %s │ %-90s │\n' "Версия       " "${SCRIPT_VERSION}"
printf '└%s┴%s┘\n' "${TABLE_LABEL_RULE}" "${TABLE_VALUE_RULE}"
if [[ "${GIT_IS_CONFIGURED}" == true ]]; then
    echo "Git:          уже настроен"
else
    echo "Git:          будет инициализирован"
fi
if [[ "${REMOTE_IS_CONFIGURED}" == false ]]; then
    echo "Remote:       ${REMOTE} будет добавлен"
elif [[ "$(git remote get-url "${REMOTE}")" != "${REPOSITORY_URL}" ]]; then
    echo "Remote:       URL ${REMOTE} будет обновлён"
fi
echo
echo "Локальные изменения отслеживаемых файлов и неотслеживаемые файлы будут удалены."
echo "Файлы из .gitignore (настройки, секреты и runtime-данные) останутся на месте."
echo

while true; do
    echo
    echo "1) Да, обновить"
    echo "2) Отменить"
    printf "Выберите пункт [2]: "
    IFS= read -rsn1 CONFIRM
    printf '\n'
    case "${CONFIRM}" in
        1)
            break
            ;;
        2|"")
            echo "Отменено."
            exit 0
            ;;
        *)
            echo "Ошибка: введите 1 или 2."
            ;;
    esac
done

if [[ "${GIT_IS_CONFIGURED}" == false ]]; then
    echo "Инициализация Git-репозитория..."
    git init
    ensure_local_files_are_excluded
fi

if [[ "${REMOTE_IS_CONFIGURED}" == false ]]; then
    echo "Добавление remote ${REMOTE}..."
    git remote add "${REMOTE}" "${REPOSITORY_URL}"
elif [[ "$(git remote get-url "${REMOTE}")" != "${REPOSITORY_URL}" ]]; then
    echo "Обновление URL remote ${REMOTE}..."
    git remote set-url "${REMOTE}" "${REPOSITORY_URL}"
fi

if [[ "${AUTH_MODE}" == "ssh" ]]; then
    echo "Используется SSH Deploy Key ${SSH_PRIVATE_KEY}."
elif [[ "${REPOSITORY_URL}" == https://* ]]; then
    echo "Используются данные доступа из ${CONFIG_FILE}."
    prepare_askpass
fi

echo "Получение изменений из GitHub..."
if [[ "${AUTH_MODE}" == "ssh" ]]; then
    if ! SYNC_SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY_PATH}" \
        GIT_SSH_COMMAND="ssh -i \"${SSH_PRIVATE_KEY_PATH}\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new" \
        fetch_repository; then
        echo "Ошибка: не удалось получить данные по SSH." >&2
        echo "Проверьте Deploy Key в GitHub, настройки в ${CONFIG_FILE} и права репозитория." >&2
        exit 1
    fi
elif [[ "${REPOSITORY_URL}" == https://* ]]; then
    if ! SYNC_GIT_USERNAME="${AUTH_USERNAME}" \
        SYNC_GIT_PASSWORD="${AUTH_SECRET}" \
        GIT_ASKPASS="${ASKPASS_FILE}" \
        GIT_ASKPASS_REQUIRE=force \
        GIT_TERMINAL_PROMPT=0 \
        git -c pack.threads=1 -c pack.windowMemory=32m -c credential.helper= fetch --prune "${REMOTE}"; then
        echo "Ошибка: не удалось получить данные из GitHub." >&2
        echo "Проверьте настройки в ${CONFIG_FILE}, доступ к интернету и права репозитория." >&2
        echo "Для повторной настройки удалите ${CONFIG_FILE}." >&2
        exit 1
    fi
elif ! fetch_repository; then
    echo "Ошибка: не удалось получить данные из GitHub." >&2
    echo "Проверьте SSH-ключ, доступ к интернету и права репозитория." >&2
    exit 1
fi

if ! git show-ref --verify --quiet "refs/remotes/${REMOTE}/${BRANCH}"; then
    REMOTE_HEAD="$(git symbolic-ref --quiet --short "refs/remotes/${REMOTE}/HEAD" 2>/dev/null || true)"
    REMOTE_DEFAULT_BRANCH="${REMOTE_HEAD#"${REMOTE}/"}"
    if [[ -z "${REMOTE_DEFAULT_BRANCH}" ]]; then
        for candidate_branch in main master; do
            if git show-ref --verify --quiet "refs/remotes/${REMOTE}/${candidate_branch}"; then
                REMOTE_DEFAULT_BRANCH="${candidate_branch}"
                break
            fi
        done
    fi
    if [[ -n "${REMOTE_DEFAULT_BRANCH}" ]] && [[ "${REMOTE_DEFAULT_BRANCH}" != "${BRANCH}" ]]; then
        echo "Ветка ${REMOTE}/${BRANCH} не найдена, GitHub сообщает основной веткой ${REMOTE_DEFAULT_BRANCH}."
        read -r -p "Использовать ${REMOTE_DEFAULT_BRANCH}? [Y/n]: " USE_DEFAULT_BRANCH
        if [[ "${USE_DEFAULT_BRANCH}" != "n" ]] && [[ "${USE_DEFAULT_BRANCH}" != "N" ]]; then
            BRANCH="${REMOTE_DEFAULT_BRANCH}"
            save_config
        fi
    fi
fi

if ! git show-ref --verify --quiet "refs/remotes/${REMOTE}/${BRANCH}"; then
    echo "Ошибка: ветка ${REMOTE}/${BRANCH} не найдена." >&2
    echo "Проверьте имя ветки в конфиге ${CONFIG_FILE}." >&2
    exit 1
fi

echo "Синхронизация рабочей копии..."
git checkout --force -B "${BRANCH}" "${REMOTE}/${BRANCH}"
chmod +x "${SCRIPT_FILE}"
git branch --set-upstream-to="${REMOTE}/${BRANCH}" "${BRANCH}" >/dev/null
if [[ "${GIT_CLEAN:-0}" == "1" ]]; then
    if [[ -n "${SCRIPT_RELATIVE_PATH}" ]]; then
        git clean -fd -e "${SCRIPT_RELATIVE_PATH}"
    else
        git clean -fd -e ".deploy/"
    fi
else
    echo "Локальные неотслеживаемые файлы сохранены. Для очистки задайте GIT_CLEAN=1."
fi

echo "Готово: сервер синхронизирован с ${REMOTE}/${BRANCH}."
git log -1 --oneline
