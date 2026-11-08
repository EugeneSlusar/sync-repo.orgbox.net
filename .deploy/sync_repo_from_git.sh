#!/usr/bin/env bash

set -Eeuo pipefail

# Вывод Git внутри скрипта не должен открывать less и ждать нажатия q.
# Переопределяем pager только для этого процесса, не меняя настройки пользователя.
export GIT_PAGER=cat

SCRIPT_VERSION="1.5.1"
AUTO_MODE=false

case "${1:-}" in
    --version|-v)
        echo "sync_repo_from_git.sh ${SCRIPT_VERSION}"
        exit 0
        ;;
    --auto)
        AUTO_MODE=true
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
SSH_WRAPPER_FILE=""
UPDATE_TEMP_FILE=""
ACTIONS_PRIVATE_KEY_TEMP=""
GH_BIN=""
GITHUB_SETUP_TOKEN=""
GH_CLI_VERSION="${SYNC_REPO_GH_VERSION:-2.89.0}"
TOOL_REPOSITORY_URL="${SYNC_REPO_TOOL_REPOSITORY:-https://github.com/EugeneSlusar/sync-repo.orgbox.net.git}"
TOOL_REPOSITORY_REF="${SYNC_REPO_TOOL_REF:-main}"

cleanup() {
    if [[ -n "${SSH_WRAPPER_FILE}" ]] && [[ -f "${SSH_WRAPPER_FILE}" ]]; then
        rm -f -- "${SSH_WRAPPER_FILE}"
    fi
    if [[ -n "${ASKPASS_FILE}" ]] && [[ -f "${ASKPASS_FILE}" ]]; then
        rm -f -- "${ASKPASS_FILE}"
    fi
    if [[ -n "${UPDATE_TEMP_FILE}" ]] && [[ -f "${UPDATE_TEMP_FILE}" ]]; then
        rm -f -- "${UPDATE_TEMP_FILE}"
    fi
    if [[ -n "${ACTIONS_PRIVATE_KEY_TEMP}" ]] && [[ -f "${ACTIONS_PRIVATE_KEY_TEMP}" ]]; then
        rm -f -- "${ACTIONS_PRIVATE_KEY_TEMP}" "${ACTIONS_PRIVATE_KEY_TEMP}.pub"
    fi
}

trap cleanup EXIT

printf '\033[2J\033[H'

# Единая цветовая схема (цвета только в терминале, отключаются через NO_COLOR):
#   бирюзовый — имя поля/секрета, оранжевый — значение (его копируют),
#   серый — подсказка, красный — предупреждение, жирный белый — заголовок шага.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_LABEL=$'\033[1;36m'; C_VALUE=$'\033[1;38;5;208m'; C_HINT=$'\033[38;5;245m'
    C_WARN=$'\033[1;31m'; C_HEAD=$'\033[1;97m'; C_RESET=$'\033[0m'
else
    C_LABEL=""; C_VALUE=""; C_HINT=""; C_WARN=""; C_HEAD=""; C_RESET=""
fi
print_heading() { printf '%s%s%s\n' "${C_HEAD}" "$1" "${C_RESET}"; }
print_hint() { printf '%s%s%s\n' "${C_HINT}" "$1" "${C_RESET}"; }
print_warning() { printf '%s%s%s\n' "${C_WARN}" "$1" "${C_RESET}"; }
print_field() {
    printf '%s%s%s\n    %s%s%s\n' "${C_LABEL}" "$1" "${C_RESET}" "${C_VALUE}" "$2" "${C_RESET}"
}
print_legend() {
    printf '%s%s%s · %s%s%s · %s%s%s · %s%s%s\n' \
        "${C_LABEL}" "$(t m001 "cyan = name")" "${C_RESET}" \
        "${C_VALUE}" "$(t m002 "orange = what to copy")" "${C_RESET}" \
        "${C_HINT}" "$(t m003 "grey = hint")" "${C_RESET}" \
        "${C_WARN}" "$(t m004 "red = warning")" "${C_RESET}"
}
# Имя секрета и его значение разделены: копируется только оранжевый текст между ▼ и ▲.
print_secret() {
    local name="$1" value="$2" kind="${3:-single}"
    echo
    printf '%s%s%s  %s%s%s\n' "${C_LABEL}" "${name}" "${C_RESET}" "${C_HINT}" "$(t m005 "← type into the Name field")" "${C_RESET}"
    if [[ "${kind}" == multiline ]]; then
        print_hint "$(t m006 "▼▼▼ value (several lines): copy from the first to the last line ▼▼▼")"
    else
        print_hint "$(t m007 "▼▼▼ value: copy only the line below and paste it into the Secret field ▼▼▼")"
    fi
    printf '%s%s%s\n' "${C_VALUE}" "${value}" "${C_RESET}"
    print_hint "$(t m008 "▲▲▲ end of value ▲▲▲")"
}

# Git before 2.7 has no `remote get-url`; read the configured fetch URL there.
git_remote_url() {
    git remote get-url "$1" 2>/dev/null || git config --get "remote.$1.url"
}

is_tool_repository() {
    local current_remote normalized_current normalized_tool

    current_remote="$(cd -- "${REPO_DIR}" && git_remote_url origin 2>/dev/null || true)"
    normalized_current="${current_remote%.git}"
    normalized_tool="${TOOL_REPOSITORY_URL%.git}"
    [[ "${normalized_current}" == "${normalized_tool}" ]] \
        || [[ "${normalized_current}" == "git@github.com:EugeneSlusar/sync-repo.orgbox.net" ]]
}

# ---- Языки интерфейса -------------------------------------------------------
# Английский встроен в скрипт и работает без сети. Остальные языки лежат в Git
# отдельными пакетами .deploy/lang/<код>.sh; скачивается и загружается только
# выбранный язык, остальные пакеты не трогаются.
SUPPORTED_LANGUAGES="en ru"
LANGUAGE_CODE="en"
LANGUAGE_DIR="${SYNC_REPO_LANG_DIR:-${PROJECT_CONFIG_DIR}/lang}"
LANGUAGE_PACK_BASE_URL="https://raw.githubusercontent.com/EugeneSlusar/sync-repo.orgbox.net/${TOOL_REPOSITORY_REF}/.deploy/lang"

language_name() {
    case "$1" in
        en) printf 'English' ;;
        ru) printf 'Русский' ;;
        *) printf '%s' "$1" ;;
    esac
}

# t ID "English text": текст из загруженного языкового пакета или английский по умолчанию.
# Шаблоны пакета могут содержать только ${переменные}; код и подстановки команд запрещены.
t() {
    local _id="L_$1" _tpl
    if [[ -n "${!_id+x}" ]]; then
        _tpl="${!_id}"
        eval "printf '%s' \"${_tpl}\""
    else
        printf '%s' "$2"
    fi
}

# Пакет — это только комментарии и строки L_имя='текст' без `...` и $(...).
language_pack_is_safe() {
    local file="$1"
    bash -n "${file}" 2>/dev/null || return 1
    if grep -qE '`|\$\(' "${file}"; then return 1; fi
    if grep -vqE "^(#.*|L_[A-Za-z0-9_]+='[^']*'|)\$" "${file}"; then return 1; fi
    return 0
}

fetch_language_pack() {
    local code="$1" tmp
    [[ "${SYNC_REPO_AUTO_UPDATE:-1}" == "1" ]] || return 1
    command -v curl >/dev/null 2>&1 || return 1
    mkdir -p -- "${LANGUAGE_DIR}" 2>/dev/null || return 1
    tmp="$(mktemp "${LANGUAGE_DIR}/.pack.XXXXXX")" || return 1
    if curl -fsSL --connect-timeout 10 --max-time 30 "${LANGUAGE_PACK_BASE_URL}/${code}.sh" -o "${tmp}" \
        && language_pack_is_safe "${tmp}"; then
        mv -f -- "${tmp}" "${LANGUAGE_DIR}/${code}.sh"
        return 0
    fi
    rm -f -- "${tmp}"
    return 1
}

load_language_pack() {
    local code="$1" file="${LANGUAGE_DIR}/$1.sh"
    [[ "${code}" == en ]] && return 0
    # В репозитории инструмента пакеты отслеживаются Git, в остальных проектах скачиваются.
    if [[ -z "${SYNC_REPO_LANG_DIR:-}" ]] && ! is_tool_repository; then
        fetch_language_pack "${code}" || true
    fi
    if [[ -f "${file}" ]] && language_pack_is_safe "${file}"; then
        # shellcheck disable=SC1090
        source "${file}"
        return 0
    fi
    return 1
}

resolve_language() {
    local code="${SYNC_REPO_LANG:-}"
    if [[ -z "${code}" && -f "${CONFIG_FILE}" ]]; then
        code="$(sed -n 's/^SYNC_REPO_LANG=//p' "${CONFIG_FILE}" | head -n 1 | tr -d '\r')"
    fi
    case " ${SUPPORTED_LANGUAGES} " in
        *" ${code} "*) ;;
        *) code="en" ;;
    esac
    if [[ "${code}" != en ]] && ! load_language_pack "${code}"; then
        echo "Warning: language pack '${code}' is unavailable (no network or no cached copy). Using English." >&2
        code="en"
    fi
    LANGUAGE_CODE="${code}"
}

resolve_language

# Меню «Сменить язык»: проверяет, что пакет загружается, сохраняет выбор и перезапускает скрипт.
change_language() {
    local choice lang new="" index=1 marker current_name

    echo
    print_heading "$(t m009 "Interface language")"
    for lang in ${SUPPORTED_LANGUAGES}; do
        marker=" "
        [[ "${lang}" == "${LANGUAGE_CODE}" ]] && marker="*"
        printf '  %s %s) %s\n' "${marker}" "${index}" "$(language_name "${lang}")"
        index=$((index + 1))
    done
    current_name="$(language_name "${LANGUAGE_CODE}")"
    read -r -p "$(t m010 "Choose language [${current_name}]: ")" choice || return 0
    [[ -n "${choice}" ]] || return 0
    index=1
    for lang in ${SUPPORTED_LANGUAGES}; do
        if [[ "${choice}" == "${index}" || "${choice}" == "${lang}" ]]; then
            new="${lang}"
        fi
        index=$((index + 1))
    done
    if [[ -z "${new}" ]]; then
        echo "$(t m011 "Error: no such language in the list.")"
        return 0
    fi
    [[ "${new}" != "${LANGUAGE_CODE}" ]] || return 0
    if ! ( load_language_pack "${new}" ) >/dev/null 2>&1; then
        echo "$(t m012 "Error: could not load language pack ${new}. Check your internet connection.")"
        return 0
    fi
    LANGUAGE_CODE="${new}"
    save_config
    unset SYNC_REPO_LANG
    exec bash "${SCRIPT_FILE}"
}

update_script_from_central_repository() {
    local raw_url current_mode available_version update_choice newest_version

    [[ "${SYNC_REPO_AUTO_UPDATE:-1}" == "1" ]] || return 0
    is_tool_repository && return 0
    command -v curl >/dev/null 2>&1 || return 0

    raw_url="https://raw.githubusercontent.com/EugeneSlusar/sync-repo.orgbox.net/${TOOL_REPOSITORY_REF}/.deploy/sync_repo_from_git.sh"
    if ! UPDATE_TEMP_FILE="$(mktemp "${SCRIPT_DIR}/.sync-repo-update.XXXXXX")"; then
        echo "$(t m013 "Warning: the script directory is not writable, self-update is unavailable.")" >&2
        return 0
    fi
    if ! curl -fsSL --connect-timeout 10 --max-time 30 "${raw_url}" -o "${UPDATE_TEMP_FILE}"; then
        echo "$(t m014 "Warning: could not check for a sync_repo_from_git.sh update.")" >&2
        return 0
    fi

    if ! bash -n "${UPDATE_TEMP_FILE}"; then
        echo "$(t m015 "Warning: the downloaded update failed the Bash syntax check.")" >&2
        return 0
    fi

    if ! cmp -s "${SCRIPT_FILE}" "${UPDATE_TEMP_FILE}"; then
        # Read the version without executing downloaded code before consent.
        available_version="$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' "${UPDATE_TEMP_FILE}" | head -n 1)"
        if [[ ! "${available_version}" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
            echo "$(t m016 "Warning: could not determine the version of the downloaded script.")" >&2
            return 0
        fi
        newest_version="$(printf '%s\n' "${SCRIPT_VERSION}" "${available_version}" | LC_ALL=C sort -V | tail -n 1)"
        if [[ "${available_version}" == "${SCRIPT_VERSION}" ]] \
            || [[ "${newest_version}" != "${available_version}" ]]; then
            rm -f -- "${UPDATE_TEMP_FILE}"
            UPDATE_TEMP_FILE=""
            return 0
        fi

        echo "$(t m017 "A new script version is available: ${available_version} (installed ${SCRIPT_VERSION}).")"
        if [[ "${AUTO_MODE}" == true ]]; then
            echo "$(t m018 "In --auto mode the script does not update without confirmation. Continuing with ${SCRIPT_VERSION}.")"
            echo "$(t m019 "To update, run the script interactively, without --auto.")"
            rm -f -- "${UPDATE_TEMP_FILE}"
            UPDATE_TEMP_FILE=""
            return 0
        fi
        echo "$(t m020 "1) Yes, update the script and continue")"
        echo "$(t m021 "2) No, continue with the installed version")"
        if ! IFS= read -r -p "$(t m022 "Choose an option [2]: ")" update_choice; then
            update_choice="2"
        fi
        case "${update_choice}" in
            1|y|Y|yes|Yes|YES|д|Д|да|Да|ДА) ;;
            *)
                echo "$(t m023 "Script update skipped. Continuing with ${SCRIPT_VERSION}.")"
                rm -f -- "${UPDATE_TEMP_FILE}"
                UPDATE_TEMP_FILE=""
                return 0
                ;;
        esac

        current_mode="$(stat -c '%a' "${SCRIPT_FILE}" 2>/dev/null || true)"
        if [[ -n "${current_mode}" ]]; then
            chmod "${current_mode}" "${UPDATE_TEMP_FILE}" 2>/dev/null || chmod +x "${UPDATE_TEMP_FILE}"
        else
            chmod +x "${UPDATE_TEMP_FILE}"
        fi
        mv -f -- "${UPDATE_TEMP_FILE}" "${SCRIPT_FILE}"
        UPDATE_TEMP_FILE=""
        echo "$(t m024 "sync_repo_from_git.sh was updated from the central repository.")"
        # Continue with the downloaded version, preserving --auto and other arguments.
        exec bash "${SCRIPT_FILE}" "$@"
    fi
}

update_script_from_central_repository "$@"

ensure_local_files_are_excluded() {
    local exclude_file exclude_pattern protected_file relative_path

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

    # Older Git treats info/exclude as a revision when --git-path is unknown.
    # Preserve modern Git's linked-worktree resolution; fall back to --git-dir.
    if ! exclude_file="$(git rev-parse --git-path info/exclude 2>/dev/null)" \
        || [[ -z "${exclude_file}" || "${exclude_file}" == --git-path* ]]; then
        exclude_file="$(git rev-parse --git-dir)/info/exclude"
    fi

    mkdir -p -- "$(dirname -- "${exclude_file}")"
    touch "${exclude_file}"
    for protected_file in \
        "${SCRIPT_FILE}" \
        "${CONFIG_FILE}" \
        "${PROJECT_CONFIG_DIR}/.sync-repo-ssh.*" \
        "${PROJECT_CONFIG_DIR}/.sync-repo-askpass.*" \
        "${PROJECT_CONFIG_DIR}/.sync-repo-gh.*" \
        "${PROJECT_CONFIG_DIR}/bin/gh" \
        "${PROJECT_CONFIG_DIR}/sync_repo_deploy_key" \
        "${PROJECT_CONFIG_DIR}/sync_repo_deploy_key.pub" \
        "${PROJECT_CONFIG_DIR}/github_actions_deploy_key.pub" \
        "${PROJECT_CONFIG_DIR}/lang/*"; do
        [[ "${protected_file}" == "${REPO_DIR}/"* ]] || continue
        # В репозитории инструмента языковые пакеты отслеживаются Git.
        if [[ "${protected_file}" == */lang/'*' ]] && is_tool_repository; then continue; fi
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
        echo "$(t m025 "# sync_repo_from_git.sh settings. Do not add to Git.")"
        echo "$(t m026 "# REPOSITORY_URL — address of the remote Git repository (HTTPS or SSH).")"
        echo "$(t m027 "# REMOTE — local name of the Git connection, usually origin.")"
        echo "$(t m028 "# BRANCH — branch to deploy on the server.")"
        echo "$(t m029 "# AUTH_SECRET — PAT or password; keep this file with 600 permissions only.")"
        echo "$(t m030 "# SYNC_REPO_LANG — interface language: en or ru.")"
        printf 'REPOSITORY_URL=%s\n' "${REPOSITORY_URL}"
        printf 'REMOTE=%s\n' "${REMOTE}"
        printf 'BRANCH=%s\n' "${BRANCH}"
        printf 'AUTH_MODE=%s\n' "${AUTH_MODE}"
        printf 'AUTH_USERNAME=%s\n' "${AUTH_USERNAME}"
        printf 'AUTH_SECRET=%s\n' "${AUTH_SECRET}"
        printf 'SSH_PRIVATE_KEY=%s\n' "${SSH_PRIVATE_KEY}"
        printf 'SYNC_REPO_LANG=%s\n' "${LANGUAGE_CODE}"
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
        echo "$(t m031 "Error: ssh-keygen is not installed on the server.")" >&2
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
        echo "$(t m032 "Creating SSH Deploy Key...")"
        ssh-keygen -q -t ed25519 -C "${key_comment}" -f "${SSH_PRIVATE_KEY_PATH}" -N ""
    elif [[ ! -f "${public_key_path}" ]]; then
        ssh-keygen -y -f "${SSH_PRIVATE_KEY_PATH}" > "${public_key_path}"
    fi

    chmod 600 "${SSH_PRIVATE_KEY_PATH}"
    chmod 644 "${public_key_path}"
    convert_repository_url_to_ssh

    echo
    echo "$(t m033 "Public Deploy Key:")"
    echo "------------------------------------------------------------"
    command cat "${public_key_path}"
    echo "------------------------------------------------------------"
    echo "$(t m034 "Add it to GitHub: Repository → Settings → Deploy keys → Add deploy key.")"
    echo "$(t m035 "A key without Allow write access is enough to update the server.")"
    echo
    read -r -p "$(t m036 "After adding the key, press Enter to continue... ")"
}

request_auth() {
    local auth_choice token

    echo
    echo "$(t m037 "Authentication is needed so the server can read a private repository.")"
    echo "$(t m038 "A public repository usually needs no key, but a Deploy Key is recommended for servers.")"
    echo "$(t m039 "Repository access method:")"
    echo "$(t m040 "  1) SSH Deploy Key — the key is created on the server; add its public part to the")"
    echo "$(t m041 "     repository's Settings → Deploy keys. Choose this for permanent deployment.")"
    echo "$(t m042 "  2) GitHub Personal Access Token (PAT) — a secret token from GitHub Settings → Developer settings.")"
    echo "$(t m043 "  3) Login and password/PAT — legacy method; GitHub.com does not accept regular passwords.")"
    read -r -p "$(t m044 "Choose an option [1]: ")" auth_choice
    auth_choice="${auth_choice:-1}"

    case "${auth_choice}" in
        1)
            setup_deploy_key
            ;;
        2)
            read -r -s -p "GitHub Personal Access Token: " token
            echo
            if [[ -z "${token}" ]]; then
                echo "$(t m045 "Error: the token cannot be empty.")" >&2
                exit 1
            fi
            AUTH_MODE="token"
            AUTH_USERNAME="x-access-token"
            AUTH_SECRET="${token}"
            SSH_PRIVATE_KEY=""
            ;;
        3)
            AUTH_MODE="basic"
            read -r -p "$(t m046 "GitHub login: ")" AUTH_USERNAME
            read -r -s -p "$(t m047 "Password or Personal Access Token: ")" AUTH_SECRET
            echo
            SSH_PRIVATE_KEY=""

            if [[ -z "${AUTH_USERNAME}" ]] || [[ -z "${AUTH_SECRET}" ]]; then
                echo "$(t m048 "Error: login and password cannot be empty.")" >&2
                exit 1
            fi

            echo "$(t m049 "Note: GitHub.com does not accept regular passwords — use a PAT.")"
            ;;
        *)
            echo "$(t m050 "Error: unknown authentication method.")" >&2
            exit 1
            ;;
    esac
}

create_github_repository() {
    local repository_name visibility repository_visibility

    if ! command -v gh >/dev/null 2>&1; then
        echo "$(t m051 "Error: to create a GitHub repository, install GitHub CLI (gh).")" >&2
        echo "$(t m052 "Documentation: https://cli.github.com/")" >&2
        exit 1
    fi
    if ! gh auth status >/dev/null 2>&1; then
        echo "$(t m053 "First sign in to GitHub CLI with: gh auth login")" >&2
        exit 1
    fi

    echo
    echo "$(t m054 "Creating a GitHub repository from the current project")"
    default_repository_name="$(basename -- "${REPO_DIR}")"
    read -r -p "$(t m055 "Repository name [${default_repository_name}]: ")" repository_name
    repository_name="${repository_name:-${default_repository_name}}"
    if [[ ! "${repository_name}" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        echo "$(t m056 "Error: the repository name contains invalid characters.")" >&2
        exit 1
    fi

    echo "$(t m057 "1) Private repository")"
    echo "$(t m058 "2) Public repository")"
    read -r -p "$(t m059 "Repository visibility [1]: ")" visibility
    case "${visibility}" in
        2) repository_visibility="--public" ;;
        *) repository_visibility="--private" ;;
    esac

    echo "$(t m060 "Initializing local Git repository...")"
    git init -b main >/dev/null 2>&1 || git init >/dev/null
    git checkout -B main >/dev/null 2>&1
    git add -A
    if ! git diff --cached --quiet; then
        git commit -m "Initial commit" >/dev/null
    elif ! git rev-parse --verify HEAD >/dev/null 2>&1; then
        git commit --allow-empty -m "Initial commit" >/dev/null
    fi

    echo "$(t m061 "Creating repository on GitHub...")"
    gh repo create "${repository_name}" "${repository_visibility}" \
        --source="${REPO_DIR}" --remote="${REMOTE}" --push
    REPOSITORY_URL="$(git_remote_url "${REMOTE}")"
    echo "$(t m062 "GitHub repository connected: ${REPOSITORY_URL}")"
}

# owner/repo из URL GitHub (https, scp-подобный SSH или ssh://).
github_slug_from_url() {
    local url="$1" slug

    case "${url}" in
        ssh://*) slug="${url#ssh://}"; slug="${slug#*/}" ;;
        http://*|https://*) slug="${url#*://}"; slug="${slug#*@}"; slug="${slug#*/}" ;;
        *@*:*) slug="${url#*:}" ;;
        *) return 1 ;;
    esac
    slug="${slug%.git}"
    slug="${slug%/}"
    [[ "${slug}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || return 1
    printf '%s\n' "${slug}"
}

# gh на shared-хостингах с лимитом потоков (ulimit -u) падает в Go-рантайме
# ("failed to create new OS thread"). Ограничиваем потоки ВСЕГДА, а не только после
# сбоя: `gh --version` проходит и без лимитов, но `gh api`/`gh secret set` уже нет.
limit_go_threads() {
    export GOMAXPROCS="${GOMAXPROCS:-1}"
    export GODEBUG="${GODEBUG:+${GODEBUG},}asyncpreemptoff=1"
    export GOGC="${GOGC:-50}"
}

gh_runs() {
    local bin="$1"

    limit_go_threads
    "${bin}" --version >/dev/null 2>&1
}

# Находит GitHub CLI или скачивает его в .deploy/bin без root-прав.
ensure_gh_cli() {
    local candidate arch url work

    for candidate in "${SYNC_REPO_GH_BIN:-}" "$(command -v gh 2>/dev/null || true)" "${PROJECT_CONFIG_DIR}/bin/gh" "${HOME}/.local/bin/gh" "${HOME}/bin/gh"; do
        if [[ -n "${candidate}" ]] && [[ -x "${candidate}" ]] && gh_runs "${candidate}"; then
            GH_BIN="${candidate}"
            return 0
        fi
    done

    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) machine_arch="$(uname -m)"; echo "$(t m063 "GitHub CLI: architecture ${machine_arch} is not supported for automatic installation.")" >&2; return 1 ;;
    esac
    command -v curl >/dev/null 2>&1 && command -v tar >/dev/null 2>&1 || {
        echo "$(t m064 "GitHub CLI: curl and tar are required to download it.")" >&2
        return 1
    }

    url="https://github.com/cli/cli/releases/download/v${GH_CLI_VERSION}/gh_${GH_CLI_VERSION}_linux_${arch}.tar.gz"
    echo "$(t m065 "Downloading GitHub CLI ${GH_CLI_VERSION} to ${PROJECT_CONFIG_DIR}/bin ...")"
    work="$(mktemp -d "${PROJECT_CONFIG_DIR}/.sync-repo-gh.XXXXXX")" || {
        echo "$(t m066 "GitHub CLI: could not create a temporary directory in ${PROJECT_CONFIG_DIR}.")" >&2
        return 1
    }
    if ! curl -fsSL --connect-timeout 15 -o "${work}/gh.tar.gz" "${url}"; then
        echo "$(t m067 "GitHub CLI: download error ${url}")" >&2
        echo "$(t m068 "  (check that the server can reach github.com and release-assets.githubusercontent.com)")" >&2
        rm -rf -- "${work}"
        return 1
    fi
    if ! tar -xzf "${work}/gh.tar.gz" -C "${work}"; then
        archive_size="$(wc -c < "${work}/gh.tar.gz")"
        echo "$(t m069 "GitHub CLI: could not unpack the archive (size: ${archive_size} bytes).")" >&2
        rm -rf -- "${work}"
        return 1
    fi
    local gh_src="" install_dir run_error=""
    for gh_src in "${work}"/gh_*/bin/gh; do break; done
    if [[ ! -f "${gh_src}" ]]; then
        echo "$(t m070 "GitHub CLI: bin/gh binary not found in the archive.")" >&2
        rm -rf -- "${work}"
        return 1
    fi
    # Рабочий каталог проекта может быть смонтирован с noexec: пробуем другие места.
    for install_dir in "${PROJECT_CONFIG_DIR}/bin" "${HOME}/.local/bin" "${HOME}/bin" "${TMPDIR:-/tmp}/sync-repo-gh-$(id -u)"; do
        mkdir -p -- "${install_dir}" 2>/dev/null || continue
        cp -- "${gh_src}" "${install_dir}/gh" 2>/dev/null || continue
        chmod 755 "${install_dir}/gh" 2>/dev/null || continue
        if gh_runs "${install_dir}/gh"; then
            rm -rf -- "${work}"
            GH_BIN="${install_dir}/gh"
            echo "$(t m071 "GitHub CLI installed: ${GH_BIN}")"
            return 0
        fi
        run_error="$("${install_dir}/gh" --version 2>&1 | head -n 8)" || true
        echo "$(t m072 "GitHub CLI: ${install_dir}/gh does not start: ${run_error:-no output}")" >&2
        rm -f -- "${install_dir}/gh"
    done
    rm -rf -- "${work}"
    echo "$(t m073 "GitHub CLI: no directory found from which files can be executed.")" >&2
    return 1
}

# updatedAt секрета в Actions-secrets репозитория (пусто, если секрета нет).
# Возвращает ненулевой код, если список прочитать не удалось.
# Использует token и slug вызывающей функции.
github_secret_updated_at() {
    GH_TOKEN="${token}" "${GH_BIN}" secret list --repo "${slug}" --app actions \
        --json name,updatedAt --jq ".[] | select(.name==\"$1\") | .updatedAt"
}

# Всегда ПЕРЕЗАПИСЫВАЕТ секрет в Repository secrets (Actions) и проверяет результат:
# пустое значение не пишется, после записи секрет должен быть в списке и обновиться.
# Аргументы: имя, вид значения (value|file), значение или путь к файлу.
set_github_secret() {
    local name="$1" kind="$2" source_value="$3" before after
    local -a gh_args=(secret set "$1" --repo "${slug}" --app actions)

    if [[ "${kind}" == file ]]; then
        grep -q '[^[:space:]]' -- "${source_value}" 2>/dev/null || {
            echo "$(t m224 "  ✗ ${name} — refusing to write an empty value.")" >&2
            return 1
        }
    else
        [[ -n "${source_value//[[:space:]]/}" ]] || {
            echo "$(t m224 "  ✗ ${name} — refusing to write an empty value.")" >&2
            return 1
        }
    fi
    if ! before="$(github_secret_updated_at "${name}")"; then
        echo "$(t m225 "  ✗ ${name} — could not read the secrets list to verify (the token needs Secrets: Read).")" >&2
        return 1
    fi
    if [[ "${kind}" == file ]]; then
        GH_TOKEN="${token}" "${GH_BIN}" "${gh_args[@]}" < "${source_value}" >/dev/null || {
            echo "$(t m228 "  ✗ ${name} — GitHub CLI failed to write the secret.")" >&2
            return 1
        }
    else
        printf '%s' "${source_value}" | GH_TOKEN="${token}" "${GH_BIN}" "${gh_args[@]}" >/dev/null || {
            echo "$(t m228 "  ✗ ${name} — GitHub CLI failed to write the secret.")" >&2
            return 1
        }
    fi
    if ! after="$(github_secret_updated_at "${name}")" || [[ -z "${after}" ]]; then
        echo "$(t m226 "  ✗ ${name} — written, but not found in the repository Actions secrets afterwards.")" >&2
        return 1
    fi
    if [[ -z "${before}" ]]; then
        echo "$(t m222 "  ✓ ${name} — created")"
    elif [[ "${after}" != "${before}" ]]; then
        echo "$(t m223 "  ✓ ${name} — overwritten")"
    else
        echo "$(t m227 "  ✗ ${name} — GitHub did not update the secret (update time unchanged).")" >&2
        return 1
    fi
}

# Создаёт секреты и коммитит deploy.yml в GitHub через API. Токен нигде не сохраняется.
# Аргументы: host port user path known_hosts private_key_file(или пусто) workflow_file
configure_github_automatically() {
    local deploy_host="$1" deploy_port="$2" deploy_user="$3" deploy_path="$4"
    local known_hosts="$5" private_key_file="$6" workflow_file="$7"
    local slug remote_url token branch sha content_b64 api_path
    local -a put_args

    remote_url="$(cd -- "${REPO_DIR}" && git_remote_url "${REMOTE:-origin}" 2>/dev/null || true)"
    slug="$(github_slug_from_url "${remote_url:-${REPOSITORY_URL}}" 2>/dev/null || true)"
    if [[ -z "${slug}" ]]; then
        read -r -p "$(t m074 "GitHub repository (owner/name): ")" slug || return 1
        [[ "${slug}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "$(t m075 "Invalid repository format.")" >&2; return 1; }
    fi
    branch="${BRANCH:-main}"

    ensure_gh_cli || return 1

    token="${GH_TOKEN:-${GITHUB_TOKEN:-${GITHUB_SETUP_TOKEN:-}}}"
    if [[ -z "${token}" ]]; then
        echo
        echo "$(t m076 "A GitHub token is needed only for this setup (it is not saved to any file).")"
        echo "$(t m077 "Create a fine-grained token: https://github.com/settings/personal-access-tokens/new")"
        echo "  • Repository access: Only select repositories → ${slug}"
        echo "  • Permissions: Secrets — Read and write; Contents — Read and write; Workflows — Read and write"
        read -r -s -p "$(t m078 "GitHub token: ")" token || return 1
        echo
    fi
    token="${token//[[:space:]]/}"
    GITHUB_SETUP_TOKEN="${token}"
    [[ -n "${token}" ]] || { echo "$(t m079 "Token not provided.")" >&2; return 1; }

    local api_error
    if ! api_error="$(GH_TOKEN="${token}" "${GH_BIN}" api "repos/${slug}" --jq .full_name 2>&1)"; then
        echo "$(t m080 "Error: the token does not give access to ${slug}.")" >&2
        api_error_head="$(printf '%s\n' "${api_error}" | head -n 5)"
        echo "$(t m081 "GitHub response: ${api_error_head}")" >&2
        echo "$(t m082 "Check: the token is pasted in full; Resource owner is the repository owner;")" >&2
        echo "$(t m083 "Repository access includes ${slug}; the token has not expired.")" >&2
        return 1
    fi

    echo "$(t m084 "Creating secrets in ${slug} ...")"
    echo "$(t m229 "Target: ${slug} → Settings → Secrets and variables → Actions → Repository secrets.")"
    local name value secrets_failed=0
    if [[ -z "${private_key_file}" ]]; then
        # Приватная часть прежнего ключа на сервере не хранится: писать нечего.
        # Если секрета в GitHub нет, просим вызывающую функцию создать новый ключ.
        local existing_key_time
        if ! existing_key_time="$(github_secret_updated_at DEPLOY_SSH_KEY)"; then
            echo "$(t m225 "  ✗ DEPLOY_SSH_KEY — could not read the secrets list to verify (the token needs Secrets: Read).")" >&2
            return 1
        fi
        if [[ -z "${existing_key_time}" ]]; then
            print_warning "$(t m230 "DEPLOY_SSH_KEY is missing in ${slug} and the private part of the old key is not stored on the server. A new key pair will be created.")"
            return 3
        fi
    fi
    for name in DEPLOY_HOST DEPLOY_PORT DEPLOY_USER DEPLOY_PATH DEPLOY_KNOWN_HOSTS; do
        case "${name}" in
            DEPLOY_HOST) value="${deploy_host}" ;;
            DEPLOY_PORT) value="${deploy_port}" ;;
            DEPLOY_USER) value="${deploy_user}" ;;
            DEPLOY_PATH) value="${deploy_path}" ;;
            DEPLOY_KNOWN_HOSTS) value="${known_hosts}" ;;
        esac
        set_github_secret "${name}" value "${value}" || secrets_failed=$((secrets_failed + 1))
    done
    if [[ -n "${private_key_file}" ]]; then
        set_github_secret DEPLOY_SSH_KEY file "${private_key_file}" || secrets_failed=$((secrets_failed + 1))
    else
        echo "$(t m231 "  • DEPLOY_SSH_KEY already exists in ${slug}; its value cannot be read back. To replace it, choose option 2 (create new keys) next time.")"
    fi
    if (( secrets_failed > 0 )); then
        echo "$(t m232 "Error: ${secrets_failed} secret(s) were not written. Nothing is claimed as configured.")" >&2
        return 1
    fi

    api_path="repos/${slug}/contents/.github/workflows/deploy.yml"
    sha="$(GH_TOKEN="${token}" "${GH_BIN}" api "${api_path}?ref=${branch}" --jq .sha 2>/dev/null || true)"
    content_b64="$(base64 < "${workflow_file}" | tr -d '\n')"
    put_args=(-X PUT "${api_path}" -f message="Add deploy workflow" -f branch="${branch}" -f content="${content_b64}")
    [[ -z "${sha}" ]] || put_args+=(-f sha="${sha}")
    if ! GH_TOKEN="${token}" "${GH_BIN}" api "${put_args[@]}" >/dev/null; then
        echo "$(t m088 "Error: could not commit deploy.yml to branch ${branch}.")" >&2
        return 1
    fi
    echo "$(t m089 "  ✓ .github/workflows/deploy.yml committed to ${branch}")"

    # Файл теперь есть в репозитории: локальную неотслеживаемую копию убираем,
    # чтобы она не блокировала обновление конфликтом путей.
    if ! (cd -- "${REPO_DIR}" && git ls-files --error-unmatch -- "${workflow_file#"${REPO_DIR}/"}" >/dev/null 2>&1); then
        rm -f -- "${workflow_file}"
    fi
    return 0
}

# Создаёт новую пару ключей для Actions и устанавливает публичную часть в authorized_keys.
# Старые строки этого проекта (тот же комментарий) заменяются: иначе новый ключ не получит доступ.
# Использует переменные setup_actions_autodeploy: actions_key, actions_public, deploy_host.
create_actions_key() {
    local comment="github-actions:${deploy_host}:${REPO_DIR}" key_material tmp_keys

    ACTIONS_PRIVATE_KEY_TEMP="$(mktemp "${TMPDIR:-/tmp}/github-actions-key.XXXXXX")"
    rm -f -- "${ACTIONS_PRIVATE_KEY_TEMP}"
    actions_key="${ACTIONS_PRIVATE_KEY_TEMP}"
    ssh-keygen -q -t ed25519 -C "${comment}" -f "${actions_key}" -N ""
    cp -- "${actions_key}.pub" "${actions_public}"
    chmod 644 "${actions_public}"
    existing_actions_key=false

    mkdir -p -- "${HOME}/.ssh"
    chmod 700 "${HOME}/.ssh"
    touch "${HOME}/.ssh/authorized_keys"
    chmod 600 "${HOME}/.ssh/authorized_keys"
    key_material="$(awk '{print $2}' "${actions_public}")"
    if ! grep -Fq -- "${key_material}" "${HOME}/.ssh/authorized_keys"; then
        tmp_keys="$(mktemp "${HOME}/.ssh/.authorized_keys.XXXXXX")"
        grep -vF -- "${comment}" "${HOME}/.ssh/authorized_keys" > "${tmp_keys}" || true
        cat "${actions_public}" >> "${tmp_keys}"
        chmod 600 "${tmp_keys}"
        mv -f -- "${tmp_keys}" "${HOME}/.ssh/authorized_keys"
    fi
}

# Итог проверки SSH для сообщения мастера. Использует переменные setup_actions_autodeploy.
actions_ssh_result() {
    if [[ "${existing_actions_key}" == true ]]; then
        t m102 "key already configured"
    elif ssh -i "${actions_key}" -p "${deploy_port}" \
        -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=no \
        "${deploy_user}@${deploy_host}" "printf connected" >/dev/null 2>&1; then
        t m103 "connection successful"
    else
        t m104 "check failed; key added to authorized_keys"
    fi
}

setup_actions_autodeploy() {
    local deploy_host deploy_port deploy_user deploy_path workflow_file
    local actions_key actions_public known_hosts ssh_result existing_actions_key

    if ! command -v ssh-keygen >/dev/null 2>&1 || ! command -v ssh-keyscan >/dev/null 2>&1; then
        echo "$(t m090 "Error: GitHub Actions setup needs ssh-keygen and ssh-keyscan.")" >&2
        exit 1
    fi

    echo
    echo "$(t m091 "Auto-deploy setup via GitHub Actions → SSH")"
    default_host="$(hostname -f 2>/dev/null || hostname)"
    read -r -p "$(t m092 "SSH host [${default_host}]: ")" deploy_host
    deploy_host="${deploy_host:-${default_host}}"
    read -r -p "$(t m093 "SSH port [22]: ")" deploy_port
    deploy_port="${deploy_port:-22}"
    default_user="${USER:-$(whoami)}"
    read -r -p "$(t m094 "SSH user [${default_user}]: ")" deploy_user
    deploy_user="${deploy_user:-${default_user}}"
    read -r -p "$(t m095 "Project path [${REPO_DIR}]: ")" deploy_path
    deploy_path="${deploy_path:-${REPO_DIR}}"

    if [[ ! "${deploy_port}" =~ ^[0-9]+$ ]]; then
        echo "$(t m096 "Error: the SSH port must be a number.")" >&2
        exit 1
    fi

    actions_public="${PROJECT_CONFIG_DIR}/github_actions_deploy_key.pub"
    existing_actions_key=false
    if [[ -f "${actions_public}" ]]; then
        echo "$(t m097 "An existing Actions SSH key was found.")"
        echo "$(t m098 "1) Use the existing key")"
        echo "$(t m099 "2) Create new keys")"
        print_hint "$(t m233 "The private part of the old key is not stored on the server. Choose 1 only if the DEPLOY_SSH_KEY secret already holds a valid key; if unsure, choose 2.")"
        read -r -p "$(t m044 "Choose an option [1]: ")" key_choice
        if [[ "${key_choice}" != "2" ]]; then
            existing_actions_key=true
            echo "$(t m100 "The existing key will be used.")"
        fi
    fi
    if [[ "${existing_actions_key}" == false ]]; then
        create_actions_key
    else
        install -d -m 700 "${HOME}/.ssh"
    fi

    known_hosts="$(ssh-keyscan -p "${deploy_port}" -T 10 "${deploy_host}" 2>/dev/null || true)"
    if [[ -z "${known_hosts}" ]]; then
        echo "$(t m101 "Warning: could not get the SSH fingerprint for ${deploy_host}.")" >&2
    fi

    ssh_result="$(actions_ssh_result)"

    workflow_file="${REPO_DIR}/.github/workflows/deploy.yml"
    mkdir -p -- "$(dirname -- "${workflow_file}")"
    cat > "${workflow_file}" <<'WORKFLOW'
name: Deploy to server

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: read

concurrency:
  group: production-deploy
  cancel-in-progress: false

jobs:
  deploy:
    name: Deploy production
    runs-on: ubuntu-latest
    steps:
      - name: Validate deployment secrets
        shell: bash
        run: |
          set -euo pipefail
          for variable in DEPLOY_HOST DEPLOY_USER DEPLOY_PATH DEPLOY_SSH_KEY DEPLOY_KNOWN_HOSTS; do
            if [[ -z "${!variable}" ]]; then
              echo "Missing GitHub Secret: ${variable}" >&2
              exit 1
            fi
          done
        env:
          DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
          DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
          DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}

      - name: Configure SSH
        shell: bash
        run: |
          set -euo pipefail
          install -d -m 700 "$HOME/.ssh"
          printf '%s\n' "$DEPLOY_SSH_KEY" | tr -d '\r' | sed \
            '/^----- BEGIN DEPLOY_SSH_KEY -----$/d; /^----- END DEPLOY_SSH_KEY -----$/d' \
            > "$HOME/.ssh/deploy_key"
          chmod 600 "$HOME/.ssh/deploy_key"
          printf '%s\n' "$DEPLOY_KNOWN_HOSTS" > "$HOME/.ssh/known_hosts"
          chmod 644 "$HOME/.ssh/known_hosts"
        env:
          DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          DEPLOY_KNOWN_HOSTS: ${{ secrets.DEPLOY_KNOWN_HOSTS }}

      - name: Deploy project
        shell: bash
        run: |
          set -euo pipefail
          ssh -i "$HOME/.ssh/deploy_key" \
            -p "${DEPLOY_PORT:-22}" \
            -o BatchMode=yes \
            -o IdentitiesOnly=yes \
            -o StrictHostKeyChecking=yes \
            "${DEPLOY_USER}@${DEPLOY_HOST}" \
            "cd '${DEPLOY_PATH}' && bash .deploy/sync_repo_from_git.sh --auto"
        env:
          DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
          DEPLOY_PORT: ${{ secrets.DEPLOY_PORT }}
          DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
          DEPLOY_PATH: ${{ secrets.DEPLOY_PATH }}
WORKFLOW

    if [[ "${AUTO_MODE}" == false ]]; then
        local auto_answer=""
        echo
        read -r -p "$(t m105 "Configure GitHub automatically (secrets and workflow via GitHub CLI)? [Y/n]: ")" auto_answer || auto_answer="n"
        if [[ ! "${auto_answer}" =~ ^[NnНн] ]]; then
            local setup_status=0
            configure_github_automatically "${deploy_host}" "${deploy_port}" "${deploy_user}" \
                "${deploy_path}" "${known_hosts}" "${actions_key:-}" "${workflow_file}" || setup_status=$?
            if [[ "${setup_status}" == 3 ]]; then
                # Секрета DEPLOY_SSH_KEY в GitHub нет, а приватной части старого ключа тоже нет.
                create_actions_key
                ssh_result="$(actions_ssh_result)"
                setup_status=0
                configure_github_automatically "${deploy_host}" "${deploy_port}" "${deploy_user}" \
                    "${deploy_path}" "${known_hosts}" "${actions_key:-}" "${workflow_file}" || setup_status=$?
            fi
            GITHUB_SETUP_TOKEN=""
            if [[ "${setup_status}" == 0 ]]; then
                if [[ "${existing_actions_key}" == false ]]; then
                    rm -f -- "${actions_key}" "${actions_key}.pub"
                    ACTIONS_PRIVATE_KEY_TEMP=""
                fi
                echo
                echo "$(t m106 "Auto-deploy configured: secrets and workflow created in GitHub.")"
                echo "$(t m107 "The next push to ${BRANCH:-main} will deploy to ${deploy_host}.")"
                read -r -p "$(t m108 "Press Enter to return to the menu... ")" || true
                return 0
            fi
            print_warning "$(t m109 "Automatic setup failed — showing manual setup instructions.")"
        fi
    fi

    echo
    echo "============================================================"
    echo "$(t m110 "Auto-deploy prepared. SSH result: ${ssh_result}.")"
    echo "$(t m111 "File created: ${workflow_file}")"
    print_warning "$(t m112 "WARNING: SSH key files and sync_repo_from_git.conf must never be added to a Git repository.")"
    echo
    print_heading "$(t m113 "Step 1. Create secrets: GitHub → Settings → Secrets and variables → Actions → New repository secret")"
    print_legend
    if [[ "${existing_actions_key}" == false ]]; then
        print_secret DEPLOY_HOST "${deploy_host}"
        print_secret DEPLOY_PORT "${deploy_port}"
        print_secret DEPLOY_USER "${deploy_user}"
        print_secret DEPLOY_PATH "${deploy_path}"
        print_secret DEPLOY_SSH_KEY "$(cat "${actions_key}")" multiline
        print_secret DEPLOY_KNOWN_HOSTS "${known_hosts}" multiline
    else
        print_warning "$(t m234 "You chose the existing key: DEPLOY_SSH_KEY is NOT shown and NOT written by this run. Make sure it already exists in the repository secrets; otherwise run the wizard again and choose option 2.")"
        print_secret DEPLOY_HOST "${deploy_host}"
        print_secret DEPLOY_PORT "${deploy_port}"
        print_secret DEPLOY_USER "${deploy_user}"
        print_secret DEPLOY_PATH "${deploy_path}"
        print_secret DEPLOY_KNOWN_HOSTS "${known_hosts}" multiline
        echo
        print_hint "$(t m115 "DEPLOY_SSH_KEY cannot be shown again: the private part of the old key was deleted after creation.")"
        print_hint "$(t m116 "To get a new DEPLOY_SSH_KEY, choose option 2 the next time you run the wizard.")"
    fi
    echo
    print_hint "$(t m117 "The public key is already added to the server in ~/.ssh/authorized_keys.")"
    echo
    print_heading "$(t m118 "Step 2. Add the workflow to GitHub via the web interface:")"
    echo "$(t m119 "  1. Open the repository page on GitHub.")"
    echo "$(t m120 "  2. Click Add file → Create new file.")"
    echo "$(t m121 "  3. Enter .github/workflows/deploy.yml as the file name.")"
    echo "$(t m122 "  4. Paste the workflow text from the block below.")"
    echo "$(t m123 "  5. Click Commit changes to the main branch.")"
    echo ""
    echo "----- BEGIN .github/workflows/deploy.yml -----"
    cat "${workflow_file}"
    echo "----- END .github/workflows/deploy.yml -----"
    echo "============================================================"
    if [[ "${existing_actions_key}" == false ]]; then
        rm -f -- "${actions_key}"
        ACTIONS_PRIVATE_KEY_TEMP=""
    fi
    read -r -p "$(t m108 "Press Enter to return to the menu... ")"
}

prepare_askpass() {
    # Shared hosting often mounts /tmp with noexec. Git executes this helper,
    # so keep it beside the local configuration and exclude it from Git.
    ASKPASS_FILE="$(mktemp "${PROJECT_CONFIG_DIR}/.sync-repo-askpass.XXXXXX")"
    {
        echo '#!/usr/bin/env bash'
        echo 'case "$1" in'
        echo '    *Username*) printf '\''%s\n'\'' "$SYNC_GIT_USERNAME" ;;'
        echo '    *Password*) printf '\''%s\n'\'' "$SYNC_GIT_PASSWORD" ;;'
        echo 'esac'
    } > "${ASKPASS_FILE}"
    chmod 700 "${ASKPASS_FILE}"
}

prepare_ssh_wrapper() {
    # Git before 2.3 ignores GIT_SSH_COMMAND. GIT_SSH accepts an executable
    # filename, so pass the key through the environment without shell expansion.
    # /tmp may be mounted noexec even after chmod 700. Executable helpers
    # belong beside the configuration; cleanup removes them on exit.
    SSH_WRAPPER_FILE="$(mktemp "${PROJECT_CONFIG_DIR}/.sync-repo-ssh.XXXXXX")"
    {
        echo '#!/usr/bin/env bash'
        echo 'exec ssh -i "$SYNC_SSH_PRIVATE_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "$@"'
    } > "${SSH_WRAPPER_FILE}"
    chmod 700 "${SSH_WRAPPER_FILE}"
}

fetch_repository() {
    # Shared hosting can impose a very small process/thread limit. Limiting
    # pack processing keeps fetch usable without changing the repository.
    git -c pack.threads=1 -c pack.windowMemory=32m "$@" fetch --prune "${REMOTE}"
}

show_sync_status() {
    local current_branch local_commit remote_commit ahead behind changes have_commits

    current_branch="$(git symbolic-ref --quiet --short HEAD || true)"
    local_commit="$(git rev-parse --short HEAD 2>/dev/null || true)"
    remote_commit="$(git rev-parse --short "refs/remotes/${REMOTE}/${BRANCH}" 2>/dev/null || true)"
    have_commits=false
    if [[ -n "${local_commit}" && -n "${remote_commit}" ]]; then have_commits=true; fi
    [[ -n "${current_branch}" ]] || current_branch="$(t m219 "not detected")"
    [[ -n "${local_commit}" ]] || local_commit="$(t m220 "no commits")"
    [[ -n "${remote_commit}" ]] || remote_commit="$(t m221 "no data")"
    changes="$(git status --short 2>/dev/null || true)"

    echo
    echo "$(t m124 "Sync status")"
    echo "$(t m125 "  Local branch:       ${current_branch}")"
    echo "$(t m126 "  Local commit:       ${local_commit}")"
    echo "$(t m127 "  Remote commit (last fetch): ${remote_commit}")"

    if [[ "${have_commits}" == true ]]; then
        read -r ahead behind < <(git rev-list --left-right --count "HEAD...refs/remotes/${REMOTE}/${BRANCH}" 2>/dev/null || echo "0 0")
        echo "$(t m128 "  Ahead locally:      ${ahead} commit(s)")"
        echo "$(t m129 "  Behind locally:     ${behind} commit(s)")"
    fi

    if [[ -n "${changes}" ]]; then
        echo "$(t m130 "  Local changes: yes")"
        printf '%s\n' "${changes}"
    else
        echo "$(t m131 "  Local changes: none")"
    fi
    echo
}

cd "${REPO_DIR}"

if ! command -v git >/dev/null 2>&1; then
    echo "$(t m132 "Error: Git is not installed on the server.")" >&2
    echo "$(t m133 "Install Git and run the script again.")" >&2
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

if [[ "${AUTO_MODE}" == true ]]; then
    if [[ -z "${REPOSITORY_URL}" ]] || [[ -z "${BRANCH}" ]] || ! auth_config_is_valid; then
        echo "$(t m134 "Error: --auto mode needs valid repository settings, but they are missing or invalid.")" >&2
        echo "$(t m135 "First run the regular setup of sync_repo_from_git.sh.")" >&2
        exit 1
    fi
fi

LOCAL_REMOTE_CONFIGURED=false
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git_remote_url "${REMOTE}" >/dev/null 2>&1; then
    LOCAL_REMOTE_CONFIGURED=true
fi

if [[ -z "${REPOSITORY_URL}" ]] && [[ "${LOCAL_REMOTE_CONFIGURED}" == false ]] && [[ "${AUTO_MODE}" == false ]]; then
    echo
    echo "$(t m136 "The project is not connected to a remote Git repository yet.")"
    echo "$(t m137 "1) Connect an existing repository")"
    echo "$(t m138 "2) Create a new GitHub repository")"
    read -r -p "$(t m044 "Choose an option [1]: ")" setup_choice
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
    if [[ "${AUTO_MODE}" == true ]]; then
        echo "$(t m139 "Error: the Git remote name is not configured in --auto mode.")" >&2
        exit 1
    fi
    echo
    echo "$(t m140 "The Git remote name is a short local name for a Git connection, not a URL.")"
    echo "$(t m141 "Usually the value is origin. If you paste a URL here by mistake,")"
    echo "$(t m142 "the script will detect it and use origin as the connection name.")"
    read -r -p "$(t m143 "Git remote name [origin]: ")" REMOTE
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

    if git_remote_url "${REMOTE}" >/dev/null 2>&1; then
        REMOTE_IS_CONFIGURED=true
        DETECTED_REPOSITORY_URL="$(git_remote_url "${REMOTE}")"
    fi
fi

if [[ -n "${GIT_REPOSITORY_URL:-}" ]]; then
    REPOSITORY_URL="${GIT_REPOSITORY_URL}"
fi
if [[ -z "${REPOSITORY_URL}" ]]; then
    if [[ "${AUTO_MODE}" == true ]]; then
        echo "$(t m144 "Error: the Git repository URL is not configured in --auto mode.")" >&2
        exit 1
    fi
    echo
    echo "$(t m145 "The Git repository URL is the project address on GitHub/GitLab or another Git server.")"
    echo "$(t m146 "Example: https://github.com/user/project.git")"
    echo "         git@github.com:user/project.git"
    if [[ -n "${DETECTED_REPOSITORY_URL}" ]]; then
        read -r -p "$(t m147 "Git repository URL [${DETECTED_REPOSITORY_URL}]: ")" REPOSITORY_URL
        REPOSITORY_URL="${REPOSITORY_URL:-${DETECTED_REPOSITORY_URL}}"
    else
        read -r -p "$(t m148 "Git repository URL: ")" REPOSITORY_URL
    fi
fi
if [[ -z "${REPOSITORY_URL}" ]]; then
    echo "$(t m149 "Error: the repository URL cannot be empty.")" >&2
    exit 1
fi

if [[ -n "${GIT_BRANCH:-}" ]]; then
    BRANCH="${GIT_BRANCH}"
fi
if [[ -z "${BRANCH}" ]]; then
    if [[ "${AUTO_MODE}" == true ]]; then
        echo "$(t m150 "Error: the branch is not configured in --auto mode.")" >&2
        exit 1
    fi
    DEFAULT_BRANCH="${CURRENT_BRANCH:-main}"
    echo
    echo "$(t m151 "The branch is the line of development to copy to the server.")"
    echo "$(t m152 "The main stable code usually lives in main (sometimes master).")"
    read -r -p "$(t m153 "Branch [${DEFAULT_BRANCH}]: ")" BRANCH
    BRANCH="${BRANCH:-${DEFAULT_BRANCH}}"
fi

if ! auth_config_is_valid; then
    if [[ "${AUTO_MODE}" == true ]]; then
        echo "$(t m154 "Error: authentication is not configured in --auto mode.")" >&2
        exit 1
    fi
    request_auth
fi

save_config
if [[ "${GIT_IS_CONFIGURED}" == true ]]; then
    ensure_local_files_are_excluded
fi
case "${AUTH_MODE}" in
    ssh) AUTH_DESCRIPTION="SSH Deploy Key" ;;
    token) AUTH_DESCRIPTION="GitHub Personal Access Token" ;;
    basic) AUTH_DESCRIPTION="$(t m155 "Login and password/PAT")" ;;
    *) AUTH_DESCRIPTION="$(t m156 "not configured")" ;;
esac

echo "$(t m157 "Settings saved to ${CONFIG_FILE}.")"
echo
# Карточка настроек: заголовок поля и под ним значение другим цветом.
# Без рамки, поэтому длинные пути не «разъезжаются» при переносе строк.
# Карточка настроек: название поля, под ним значение другим цветом.
print_field "$(t m158 "Repository (folder on the server)")" "${REPO_DIR}"
print_field "Git remote" "${REMOTE}"
print_field "$(t m159 "Source (where the code comes from)")" "${REPOSITORY_URL}"
print_field "$(t m160 "Branch")" "${BRANCH}"
print_field "$(t m161 "Authentication")" "${AUTH_DESCRIPTION}"
print_field "$(t m162 "Settings file")" "${CONFIG_FILE}"
print_field "$(t m163 "Script version")" "${SCRIPT_VERSION}"
echo
if [[ "${GIT_IS_CONFIGURED}" == true ]]; then
    echo "$(t m164 "Git:          already configured")"
else
    echo "$(t m165 "Git:          will be initialized")"
fi
if [[ "${REMOTE_IS_CONFIGURED}" == false ]]; then
    echo "$(t m166 "Remote:       ${REMOTE} will be added")"
elif [[ "$(git_remote_url "${REMOTE}")" != "${REPOSITORY_URL}" ]]; then
    echo "$(t m167 "Remote:       URL of ${REMOTE} will be updated")"
fi
echo
echo "$(t m168 "Only files tracked by Git are updated; local files are never mass-cleaned.")"
echo "$(t m169 "If there are local edits, I will offer to back them up and replace them with the repository version.")"
echo "$(t m170 "In --auto mode local edits stop the update; conflicts with local files are protected too.")"
echo

if [[ "${AUTO_MODE}" == false ]]; then
    while true; do
        echo
        echo "$(t m171 "1) Yes, update")"
        echo "$(t m172 "2) Sync status")"
        echo "$(t m173 "3) Set up auto-deploy via GitHub Actions")"
        echo "$(t m174 "4) Change language")"
        echo "$(t m175 "5) Cancel")"
        printf "$(t m176 "Choose an option [5]: ")"
        IFS= read -r CONFIRM
        printf '\n'
        case "${CONFIRM}" in
            1)
                break
                ;;
            2)
                show_sync_status
                read -r -p "$(t m108 "Press Enter to return to the menu... ")"
                ;;
            3)
                setup_actions_autodeploy
                ;;
            4)
                change_language
                ;;
            5|"")
                echo "$(t m177 "Cancelled.")"
                exit 0
                ;;
            *)
                echo "$(t m178 "Error: enter a number from 1 to 5.")"
                ;;
        esac
    done
fi

if [[ "${GIT_IS_CONFIGURED}" == false ]]; then
    echo "$(t m179 "Initializing Git repository...")"
    git init
    ensure_local_files_are_excluded
fi

if [[ "${REMOTE_IS_CONFIGURED}" == false ]]; then
    echo "$(t m180 "Adding remote ${REMOTE}...")"
    git remote add "${REMOTE}" "${REPOSITORY_URL}"
elif [[ "$(git_remote_url "${REMOTE}")" != "${REPOSITORY_URL}" ]]; then
    echo "$(t m181 "Updating URL of remote ${REMOTE}...")"
    git remote set-url "${REMOTE}" "${REPOSITORY_URL}"
fi

if [[ "${AUTH_MODE}" == "ssh" ]]; then
    echo "$(t m182 "Using SSH Deploy Key ${SSH_PRIVATE_KEY}.")"
elif [[ "${REPOSITORY_URL}" == https://* ]]; then
    echo "$(t m183 "Using credentials from ${CONFIG_FILE}.")"
    prepare_askpass
fi

echo "$(t m184 "Fetching changes from GitHub...")"
if [[ "${AUTH_MODE}" == "ssh" ]]; then
    prepare_ssh_wrapper
    if ! (
        export SYNC_SSH_PRIVATE_KEY="${SSH_PRIVATE_KEY_PATH}"
        export GIT_SSH="${SSH_WRAPPER_FILE}"
        # Use the same quoted wrapper on old and new Git, even if the caller
        # supplied GIT_SSH_COMMAND (which otherwise overrides GIT_SSH).
        unset GIT_SSH_COMMAND
        fetch_repository
    ); then
        echo "$(t m185 "Error: could not fetch data over SSH.")" >&2
        echo "$(t m186 "Check the Deploy Key in GitHub, the settings in ${CONFIG_FILE} and repository permissions.")" >&2
        exit 1
    fi
elif [[ "${REPOSITORY_URL}" == https://* ]]; then
    if ! SYNC_GIT_USERNAME="${AUTH_USERNAME}" \
        SYNC_GIT_PASSWORD="${AUTH_SECRET}" \
        GIT_ASKPASS="${ASKPASS_FILE}" \
        GIT_ASKPASS_REQUIRE=force \
        GIT_TERMINAL_PROMPT=0 \
        git -c pack.threads=1 -c pack.windowMemory=32m -c credential.helper= fetch --prune "${REMOTE}"; then
        echo "$(t m187 "Error: could not fetch data from GitHub.")" >&2
        echo "$(t m188 "Check the settings in ${CONFIG_FILE}, internet access and repository permissions.")" >&2
        echo "$(t m189 "To reconfigure, delete ${CONFIG_FILE}.")" >&2
        exit 1
    fi
elif ! fetch_repository; then
    echo "$(t m187 "Error: could not fetch data from GitHub.")" >&2
    echo "$(t m190 "Check the SSH key, internet access and repository permissions.")" >&2
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
        echo "$(t m191 "Branch ${REMOTE}/${BRANCH} not found; GitHub reports ${REMOTE_DEFAULT_BRANCH} as the default branch.")"
        read -r -p "$(t m192 "Use ${REMOTE_DEFAULT_BRANCH}? [Y/n]: ")" USE_DEFAULT_BRANCH
        if [[ "${USE_DEFAULT_BRANCH}" != "n" ]] && [[ "${USE_DEFAULT_BRANCH}" != "N" ]]; then
            BRANCH="${REMOTE_DEFAULT_BRANCH}"
            save_config
        fi
    fi
fi

if ! git show-ref --verify --quiet "refs/remotes/${REMOTE}/${BRANCH}"; then
    echo "$(t m193 "Error: branch ${REMOTE}/${BRANCH} not found.")" >&2
    echo "$(t m194 "Check the branch name in the config ${CONFIG_FILE}.")" >&2
    exit 1
fi

# Refuse to reset unpublished commits before offering to restore local edits.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
    if ! git merge-base --is-ancestor HEAD "${REMOTE}/${BRANCH}"; then
        echo "$(t m195 "Error: the local history has commits that are not in the target branch.")" >&2
        echo "$(t m196 "Update stopped: local commits will not be discarded.")" >&2
        exit 1
    fi
fi

if ! git diff --quiet --ignore-submodules=none -- \
    || ! git diff --cached --quiet --ignore-submodules=none --; then
    echo "$(t m197 "Local changes to tracked files detected:")"
    git status --short --untracked-files=no
    if [[ "${AUTO_MODE}" == true ]]; then
        echo "$(t m198 "Error: --auto mode does not discard local edits without confirmation.")" >&2
        echo "$(t m199 "Run the script without --auto and choose restoring from the repository.")" >&2
        exit 1
    fi

    if ! git diff --quiet --ignore-submodules=none --; then
        echo
        echo "$(t m200 "Changes in the working files (relative to the index):")"
        git --no-pager diff --no-ext-diff --no-textconv --ignore-submodules=none --
    fi
    if ! git diff --cached --quiet --ignore-submodules=none --; then
        echo
        echo "$(t m201 "Changes staged with git add (relative to HEAD):")"
        git --no-pager diff --cached --no-ext-diff --no-textconv --ignore-submodules=none --
    fi

    echo
    echo "$(t m202 "Replace these edits with the ${REMOTE}/${BRANCH} version?")"
    echo "$(t m203 "1) Yes, back up the edits and restore from the repository")"
    echo "$(t m204 "2) No, keep the edits and cancel the update")"
    if ! IFS= read -r -p "$(t m022 "Choose an option [2]: ")" RESTORE_CHOICE; then
        echo "$(t m205 "No confirmation received. Edits kept, update cancelled.")"
        exit 0
    fi
    case "${RESTORE_CHOICE}" in
        1|y|Y|yes|Yes|YES|д|Д|да|Да|ДА) ;;
        *)
            echo "$(t m206 "Edits kept, update cancelled.")"
            exit 0
            ;;
    esac

    # `restore` requires Git 2.23. Fail before backup/reset on older versions;
    # replacing it with reset --hard could delete unrelated local files.
    if ! git --list-cmds=main 2>/dev/null | grep -Fx restore >/dev/null; then
        echo "$(t m207 "Error: restoring local edits requires Git 2.23 or newer.")" >&2
        echo "$(t m208 "Edits are untouched. Update Git and run the script again.")" >&2
        exit 1
    fi

    # Create a stash snapshot without changing the worktree, and anchor it with
    # a private Git ref so garbage collection cannot remove the backup.
    if ! BACKUP_COMMIT="$(git stash create "sync-repo: before restoring ${REMOTE}/${BRANCH}")" \
        || [[ -z "${BACKUP_COMMIT}" ]]; then
        echo "$(t m209 "Error: could not back up the edits. Restore cancelled.")" >&2
        exit 1
    fi
    BACKUP_REF="refs/sync-repo/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
    git update-ref "${BACKUP_REF}" "${BACKUP_COMMIT}"
    echo "$(t m210 "Edits backed up: ${BACKUP_REF}")"
    echo "$(t m211 "To restore the edits: git stash apply --index ${BACKUP_REF}")"

    # Clear only tracked/indexed edits. The checkout below then installs the
    # selected remote version without force or deletion of unrelated files.
    git restore --source=HEAD --staged --worktree -- .
    if ! git diff --quiet --ignore-submodules=none -- \
        || ! git diff --cached --quiet --ignore-submodules=none --; then
        echo "$(t m212 "Error: local changes remain (for example, in submodules). Update stopped.")" >&2
        exit 1
    fi
fi

echo "$(t m213 "Syncing the working copy...")"
# Git normally overwrites ignored files at incoming tracked paths. Disable that.
if ! git checkout --no-overwrite-ignore -B "${BRANCH}" "${REMOTE}/${BRANCH}"; then
    echo "$(t m214 "Error: Git could not safely update the working copy.")" >&2
    echo "$(t m215 "See the message above: a conflict with a local file or an access error is possible.")" >&2
    exit 1
fi
chmod +x "${SCRIPT_FILE}"
git branch --set-upstream-to="${REMOTE}/${BRANCH}" "${BRANCH}" >/dev/null
if [[ "${GIT_CLEAN:-0}" == "1" ]]; then
    echo "$(t m216 "GIT_CLEAN=1 ignored: mass cleaning is disabled in version ${SCRIPT_VERSION}.")"
fi
printf '%s%s%s\n' "${C_VALUE}" "$(t m217 "✓ Your local files (keys, config, uploads) are untouched. Nothing to do.")" "${C_RESET}"

# Необязательный шаг после синхронизации: .deploy/post_deploy.sh из репозитория проекта
# (например, миграции БД). Запускается из корня проекта; ненулевой код завершает скрипт
# с ошибкой. Скрипт сам ничего не печатает из секретов; хук тоже не должен их печатать.
POST_DEPLOY_HOOK="${REPO_DIR}/.deploy/post_deploy.sh"
if [[ -f "${POST_DEPLOY_HOOK}" && "${SYNC_REPO_SKIP_HOOK:-0}" != "1" ]]; then
    echo "$(t m235 "Running post-deploy hook .deploy/post_deploy.sh ...")"
    hook_status=0
    (cd -- "${REPO_DIR}" && bash "${POST_DEPLOY_HOOK}") || hook_status=$?
    if [[ "${hook_status}" != 0 ]]; then
        echo "$(t m236 "Error: the post-deploy hook failed (exit code ${hook_status}). Files are synchronized, but the post-deploy step did not finish.")" >&2
        exit "${hook_status}"
    fi
fi

echo "$(t m218 "Done: the server is synchronized with ${REMOTE}/${BRANCH}.")"
git --no-pager log -1 --oneline


