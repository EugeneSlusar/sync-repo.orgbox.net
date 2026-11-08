# sync_repo_from_git.sh language pack: Русский (ru)
# Только комментарии и строки L_<id>='текст'. Допустимы переменные ${имя};
# обратные кавычки, подстановки команд и одинарные кавычки внутри текста запрещены.
# Строка '# en:' — английский оригинал для переводчика.

# en: cyan = name
L_m001='бирюзовый — имя'
# en: orange = what to copy
L_m002='оранжевый — что копировать'
# en: grey = hint
L_m003='серый — подсказка'
# en: red = warning
L_m004='красный — предупреждение'
# en: ← type into the Name field
L_m005='← впишите в поле Name'
# en: ▼▼▼ value (several lines): copy from the first to the last line ▼▼▼
L_m006='▼▼▼ значение (несколько строк): копируйте от первой до последней строки ▼▼▼'
# en: ▼▼▼ value: copy only the line below and paste it into the Secret field ▼▼▼
L_m007='▼▼▼ значение: копируйте только строку ниже, вставьте в поле Secret ▼▼▼'
# en: ▲▲▲ end of value ▲▲▲
L_m008='▲▲▲ конец значения ▲▲▲'
# en: Interface language
L_m009='Язык интерфейса'
# en: Choose language [${current_name}]:
L_m010='Выберите язык [${current_name}]: '
# en: Error: no such language in the list.
L_m011='Ошибка: такого языка нет в списке.'
# en: Error: could not load language pack ${new}. Check your internet connection.
L_m012='Ошибка: не удалось загрузить языковой пакет ${new}. Проверьте доступ к интернету.'
# en: Warning: the script directory is not writable, self-update is unavailable.
L_m013='Предупреждение: каталог скрипта недоступен для самообновления.'
# en: Warning: could not check for a sync_repo_from_git.sh update.
L_m014='Предупреждение: не удалось проверить обновление sync_repo_from_git.sh.'
# en: Warning: the downloaded update failed the Bash syntax check.
L_m015='Предупреждение: скачанное обновление не прошло проверку синтаксиса Bash.'
# en: Warning: could not determine the version of the downloaded script.
L_m016='Предупреждение: не удалось определить версию скачанного скрипта.'
# en: A new script version is available: ${available_version} (installed ${SCRIPT_VERSION}).
L_m017='Доступна новая версия скрипта: ${available_version} (установлена ${SCRIPT_VERSION}).'
# en: In --auto mode the script does not update without confirmation. Continuing with ${SCRIPT_VERSION}.
L_m018='В режиме --auto скрипт не обновляется без подтверждения. Продолжаю с ${SCRIPT_VERSION}.'
# en: To update, run the script interactively, without --auto.
L_m019='Для обновления запустите скрипт интерактивно, без --auto.'
# en: 1) Yes, update the script and continue
L_m020='1) Да, обновить скрипт и продолжить'
# en: 2) No, continue with the installed version
L_m021='2) Нет, продолжить с установленной версией'
# en: Choose an option [2]:
L_m022='Выберите пункт [2]: '
# en: Script update skipped. Continuing with ${SCRIPT_VERSION}.
L_m023='Обновление скрипта пропущено. Продолжаю с ${SCRIPT_VERSION}.'
# en: sync_repo_from_git.sh was updated from the central repository.
L_m024='Скрипт sync_repo_from_git.sh обновлён из центрального репозитория.'
# en: # sync_repo_from_git.sh settings. Do not add to Git.
L_m025='# Настройки sync_repo_from_git.sh. Не добавлять в Git.'
# en: # REPOSITORY_URL — address of the remote Git repository (HTTPS or SSH).
L_m026='# REPOSITORY_URL — адрес удалённого Git-репозитория (HTTPS или SSH).'
# en: # REMOTE — local name of the Git connection, usually origin.
L_m027='# REMOTE — локальное имя подключения Git, обычно origin.'
# en: # BRANCH — branch to deploy on the server.
L_m028='# BRANCH — ветка, которую нужно разворачивать на сервере.'
# en: # AUTH_SECRET — PAT or password; keep this file with 600 permissions only.
L_m029='# AUTH_SECRET — PAT или пароль; хранить этот файл только с правами 600.'
# en: # SYNC_REPO_LANG — interface language: en or ru.
L_m030='# SYNC_REPO_LANG — язык интерфейса: en или ru.'
# en: Error: ssh-keygen is not installed on the server.
L_m031='Ошибка: ssh-keygen не установлен на сервере.'
# en: Creating SSH Deploy Key...
L_m032='Создание SSH Deploy Key...'
# en: Public Deploy Key:
L_m033='Публичный Deploy Key:'
# en: Add it to GitHub: Repository → Settings → Deploy keys → Add deploy key.
L_m034='Добавьте его в GitHub: Repository → Settings → Deploy keys → Add deploy key.'
# en: A key without Allow write access is enough to update the server.
L_m035='Для обновления сервера достаточно ключа без Allow write access.'
# en: After adding the key, press Enter to continue...
L_m036='После добавления ключа нажмите Enter для продолжения... '
# en: Authentication is needed so the server can read a private repository.
L_m037='Авторизация нужна, чтобы сервер мог читать закрытый репозиторий.'
# en: A public repository usually needs no key, but a Deploy Key is recommended for servers.
L_m038='Для открытого репозитория ключ обычно не требуется, но Deploy Key рекомендуется для сервера.'
# en: Repository access method:
L_m039='Способ доступа к репозиторию:'
# en:   1) SSH Deploy Key — the key is created on the server; add its public part to the
L_m040='  1) SSH Deploy Key — ключ создаётся на сервере; публичную часть нужно добавить в'
# en:      repository's Settings → Deploy keys. Choose this for permanent deployment.
L_m041='     Settings → Deploy keys репозитория. Выберите этот вариант для постоянного deploy.'
# en:   2) GitHub Personal Access Token (PAT) — a secret token from GitHub Settings → Developer settings.
L_m042='  2) GitHub Personal Access Token (PAT) — секретный токен из GitHub Settings → Developer settings.'
# en:   3) Login and password/PAT — legacy method; GitHub.com does not accept regular passwords.
L_m043='  3) Логин и пароль/PAT — устаревший способ; на GitHub.com обычный пароль не работает.'
# en: Choose an option [1]:
L_m044='Выберите вариант [1]: '
# en: Error: the token cannot be empty.
L_m045='Ошибка: токен не может быть пустым.'
# en: GitHub login:
L_m046='Логин GitHub: '
# en: Password or Personal Access Token:
L_m047='Пароль или Personal Access Token: '
# en: Error: login and password cannot be empty.
L_m048='Ошибка: логин и пароль не могут быть пустыми.'
# en: Note: GitHub.com does not accept regular passwords — use a PAT.
L_m049='Примечание: GitHub.com не принимает обычные пароли — используйте PAT.'
# en: Error: unknown authentication method.
L_m050='Ошибка: неизвестный способ авторизации.'
# en: Error: to create a GitHub repository, install GitHub CLI (gh).
L_m051='Ошибка: для создания GitHub-репозитория установите GitHub CLI (gh).'
# en: Documentation: https://cli.github.com/
L_m052='Документация: https://cli.github.com/'
# en: First sign in to GitHub CLI with: gh auth login
L_m053='Сначала авторизуйтесь в GitHub CLI командой: gh auth login'
# en: Creating a GitHub repository from the current project
L_m054='Создание GitHub-репозитория из текущего проекта'
# en: Repository name [${default_repository_name}]:
L_m055='Название репозитория [${default_repository_name}]: '
# en: Error: the repository name contains invalid characters.
L_m056='Ошибка: название репозитория содержит недопустимые символы.'
# en: 1) Private repository
L_m057='1) Приватный репозиторий'
# en: 2) Public repository
L_m058='2) Публичный репозиторий'
# en: Repository visibility [1]:
L_m059='Вид репозитория [1]: '
# en: Initializing local Git repository...
L_m060='Инициализация локального Git-репозитория...'
# en: Creating repository on GitHub...
L_m061='Создание репозитория на GitHub...'
# en: GitHub repository connected: ${REPOSITORY_URL}
L_m062='GitHub-репозиторий подключён: ${REPOSITORY_URL}'
# en: GitHub CLI: architecture ${machine_arch} is not supported for automatic installation.
L_m063='GitHub CLI: архитектура ${machine_arch} не поддерживается для автоустановки.'
# en: GitHub CLI: curl and tar are required to download it.
L_m064='GitHub CLI: для скачивания нужны curl и tar.'
# en: Downloading GitHub CLI ${GH_CLI_VERSION} to ${PROJECT_CONFIG_DIR}/bin ...
L_m065='Скачиваю GitHub CLI ${GH_CLI_VERSION} в ${PROJECT_CONFIG_DIR}/bin ...'
# en: GitHub CLI: could not create a temporary directory in ${PROJECT_CONFIG_DIR}.
L_m066='GitHub CLI: не удалось создать временный каталог в ${PROJECT_CONFIG_DIR}.'
# en: GitHub CLI: download error ${url}
L_m067='GitHub CLI: ошибка скачивания ${url}'
# en:   (check that the server can reach github.com and release-assets.githubusercontent.com)
L_m068='  (проверьте доступ сервера к github.com и release-assets.githubusercontent.com)'
# en: GitHub CLI: could not unpack the archive (size: ${archive_size} bytes).
L_m069='GitHub CLI: не удалось распаковать архив (размер: ${archive_size} байт).'
# en: GitHub CLI: bin/gh binary not found in the archive.
L_m070='GitHub CLI: в архиве не найден бинарник bin/gh.'
# en: GitHub CLI installed: ${GH_BIN}
L_m071='GitHub CLI установлен: ${GH_BIN}'
# en: GitHub CLI: ${install_dir}/gh does not start: ${run_error:-no output}
L_m072='GitHub CLI: ${install_dir}/gh не запускается: ${run_error:-нет вывода}'
# en: GitHub CLI: no directory found from which files can be executed.
L_m073='GitHub CLI: не удалось найти каталог, из которого можно запускать файлы.'
# en: GitHub repository (owner/name):
L_m074='Репозиторий GitHub (владелец/название): '
# en: Invalid repository format.
L_m075='Неверный формат репозитория.'
# en: A GitHub token is needed only for this setup (it is not saved to any file).
L_m076='Нужен токен GitHub только для этой настройки (в файлы он не сохраняется).'
# en: Create a fine-grained token: https://github.com/settings/personal-access-tokens/new
L_m077='Создайте fine-grained токен: https://github.com/settings/personal-access-tokens/new'
# en: GitHub token:
L_m078='Токен GitHub: '
# en: Token not provided.
L_m079='Токен не указан.'
# en: Error: the token does not give access to ${slug}.
L_m080='Ошибка: токен не даёт доступа к ${slug}.'
# en: GitHub response: ${api_error_head}
L_m081='Ответ GitHub: ${api_error_head}'
# en: Check: the token is pasted in full; Resource owner is the repository owner;
L_m082='Проверьте: токен вставлен целиком; Resource owner — владелец репозитория;'
# en: Repository access includes ${slug}; the token has not expired.
L_m083='Repository access включает ${slug}; срок действия токена не истёк.'
# en: Creating secrets in ${slug} ...
L_m084='Создаю secrets в ${slug} ...'
# en: Error: could not commit deploy.yml to branch ${branch}.
L_m088='Ошибка: не удалось закоммитить deploy.yml в ветку ${branch}.'
# en:   ✓ .github/workflows/deploy.yml committed to ${branch}
L_m089='  ✓ .github/workflows/deploy.yml закоммичен в ${branch}'
# en: Error: GitHub Actions setup needs ssh-keygen and ssh-keyscan.
L_m090='Ошибка: для настройки GitHub Actions нужны ssh-keygen и ssh-keyscan.'
# en: Auto-deploy setup via GitHub Actions → SSH
L_m091='Настройка автодеплоя через GitHub Actions → SSH'
# en: SSH host [${default_host}]:
L_m092='SSH-хост [${default_host}]: '
# en: SSH port [22]:
L_m093='SSH-порт [22]: '
# en: SSH user [${default_user}]:
L_m094='SSH-пользователь [${default_user}]: '
# en: Project path [${REPO_DIR}]:
L_m095='Путь проекта [${REPO_DIR}]: '
# en: Error: the SSH port must be a number.
L_m096='Ошибка: SSH-порт должен быть числом.'
# en: An existing Actions SSH key was found.
L_m097='Найден существующий Actions SSH-ключ.'
# en: 1) Use the existing key
L_m098='1) Использовать существующий ключ'
# en: 2) Create new keys
L_m099='2) Создать новые ключи'
# en: The existing key will be used.
L_m100='Будет использован существующий ключ.'
# en: Warning: could not get the SSH fingerprint for ${deploy_host}.
L_m101='Предупреждение: не удалось получить SSH fingerprint для ${deploy_host}.'
# en: key already configured
L_m102='ключ уже настроен'
# en: connection successful
L_m103='подключение успешно'
# en: check failed; key added to authorized_keys
L_m104='проверка не пройдена; ключ добавлен в authorized_keys'
# en: Configure GitHub automatically (secrets and workflow via GitHub CLI)? [Y/n]:
L_m105='Настроить GitHub автоматически (secrets и workflow через GitHub CLI)? [Y/n]: '
# en: Auto-deploy configured: secrets and workflow created in GitHub.
L_m106='Автодеплой настроен: secrets и workflow созданы в GitHub.'
# en: The next push to ${BRANCH:-main} will deploy to ${deploy_host}.
L_m107='Следующий push в ${BRANCH:-main} запустит деплой на ${deploy_host}.'
# en: Press Enter to return to the menu...
L_m108='Нажмите Enter для возврата в меню... '
# en: Automatic setup failed — showing manual setup instructions.
L_m109='Автонастройка не удалась — показываю инструкцию для ручной настройки.'
# en: Auto-deploy prepared. SSH result: ${ssh_result}.
L_m110='Автодеплой подготовлен. Результат SSH: ${ssh_result}.'
# en: File created: ${workflow_file}
L_m111='Создан файл: ${workflow_file}'
# en: WARNING: SSH key files and sync_repo_from_git.conf must never be added to a Git repository.
L_m112='ВНИМАНИЕ: файлы SSH-ключей и sync_repo_from_git.conf нельзя добавлять в Git-репозиторий.'
# en: Step 1. Create secrets: GitHub → Settings → Secrets and variables → Actions → New repository secret
L_m113='Шаг 1. Создайте secrets: GitHub → Settings → Secrets and variables → Actions → New repository secret'
# en: DEPLOY_SSH_KEY cannot be shown again: the private part of the old key was deleted after creation.
L_m115='DEPLOY_SSH_KEY повторно показать нельзя: приватная часть старого ключа удалена после создания.'
# en: To get a new DEPLOY_SSH_KEY, choose option 2 the next time you run the wizard.
L_m116='Для получения нового DEPLOY_SSH_KEY выберите пункт 2 при следующем запуске мастера.'
# en: The public key is already added to the server in ~/.ssh/authorized_keys.
L_m117='Публичный ключ уже добавлен на сервер в ~/.ssh/authorized_keys.'
# en: Step 2. Add the workflow to GitHub via the web interface:
L_m118='Шаг 2. Добавьте workflow в GitHub через веб-интерфейс:'
# en:   1. Open the repository page on GitHub.
L_m119='  1. Откройте страницу репозитория на GitHub.'
# en:   2. Click Add file → Create new file.
L_m120='  2. Нажмите Add file → Create new file.'
# en:   3. Enter .github/workflows/deploy.yml as the file name.
L_m121='  3. В поле имени файла укажите .github/workflows/deploy.yml.'
# en:   4. Paste the workflow text from the block below.
L_m122='  4. Вставьте текст workflow из блока ниже.'
# en:   5. Click Commit changes to the main branch.
L_m123='  5. Нажмите Commit changes в ветку main.'
# en: Sync status
L_m124='Статус синхронизации'
# en:   Local branch:       ${current_branch}
L_m125='  Локальная ветка:    ${current_branch}'
# en:   Local commit:       ${local_commit}
L_m126='  Локальный коммит:   ${local_commit}'
# en:   Remote commit (last fetch): ${remote_commit}
L_m127='  Remote-коммит (последний fetch): ${remote_commit}'
# en:   Ahead locally:      ${ahead} commit(s)
L_m128='  Впереди локально:   ${ahead} коммит(ов)'
# en:   Behind locally:     ${behind} commit(s)
L_m129='  Позади локально:    ${behind} коммит(ов)'
# en:   Local changes: yes
L_m130='  Локальные изменения: есть'
# en:   Local changes: none
L_m131='  Локальные изменения: нет'
# en: Error: Git is not installed on the server.
L_m132='Ошибка: Git не установлен на сервере.'
# en: Install Git and run the script again.
L_m133='Установите Git и повторно запустите скрипт.'
# en: Error: --auto mode needs valid repository settings, but they are missing or invalid.
L_m134='Ошибка: для режима --auto отсутствуют или неверны настройки репозитория.'
# en: First run the regular setup of sync_repo_from_git.sh.
L_m135='Сначала выполните обычную настройку sync_repo_from_git.sh.'
# en: The project is not connected to a remote Git repository yet.
L_m136='Проект ещё не подключён к удалённому Git-репозиторию.'
# en: 1) Connect an existing repository
L_m137='1) Подключить существующий репозиторий'
# en: 2) Create a new GitHub repository
L_m138='2) Создать новый GitHub-репозиторий'
# en: Error: the Git remote name is not configured in --auto mode.
L_m139='Ошибка: в режиме --auto не настроено имя Git remote.'
# en: The Git remote name is a short local name for a Git connection, not a URL.
L_m140='Имя Git remote — короткое локальное имя подключения Git, а не URL.'
# en: Usually the value is origin. If you paste a URL here by mistake,
L_m141='Обычно используется значение origin. Если вы случайно вставите URL сюда,'
# en: the script will detect it and use origin as the connection name.
L_m142='скрипт автоматически распознает его и использует origin как имя подключения.'
# en: Git remote name [origin]:
L_m143='Имя Git remote [origin]: '
# en: Error: the Git repository URL is not configured in --auto mode.
L_m144='Ошибка: в режиме --auto не настроен URL Git-репозитория.'
# en: The Git repository URL is the project address on GitHub/GitLab or another Git server.
L_m145='URL Git-репозитория — адрес проекта на GitHub/GitLab или другом Git-сервере.'
# en: Example: https://github.com/user/project.git
L_m146='Примеры: https://github.com/user/project.git'
# en: Git repository URL [${DETECTED_REPOSITORY_URL}]:
L_m147='URL Git-репозитория [${DETECTED_REPOSITORY_URL}]: '
# en: Git repository URL:
L_m148='URL Git-репозитория: '
# en: Error: the repository URL cannot be empty.
L_m149='Ошибка: URL репозитория не может быть пустым.'
# en: Error: the branch is not configured in --auto mode.
L_m150='Ошибка: в режиме --auto не настроена ветка.'
# en: The branch is the line of development to copy to the server.
L_m151='Ветка — имя линии разработки, которую нужно копировать на сервер.'
# en: The main stable code usually lives in main (sometimes master).
L_m152='Для основного стабильного кода обычно используется main (иногда master).'
# en: Branch [${DEFAULT_BRANCH}]:
L_m153='Ветка [${DEFAULT_BRANCH}]: '
# en: Error: authentication is not configured in --auto mode.
L_m154='Ошибка: в режиме --auto не настроена авторизация.'
# en: Login and password/PAT
L_m155='Логин и пароль/PAT'
# en: not configured
L_m156='не настроена'
# en: Settings saved to ${CONFIG_FILE}.
L_m157='Настройки сохранены в ${CONFIG_FILE}.'
# en: Repository (folder on the server)
L_m158='Репозиторий (папка на сервере)'
# en: Source (where the code comes from)
L_m159='Источник (откуда берём код)'
# en: Branch
L_m160='Ветка'
# en: Authentication
L_m161='Авторизация'
# en: Settings file
L_m162='Файл настроек'
# en: Script version
L_m163='Версия скрипта'
# en: Git:          already configured
L_m164='Git:          уже настроен'
# en: Git:          will be initialized
L_m165='Git:          будет инициализирован'
# en: Remote:       ${REMOTE} will be added
L_m166='Remote:       ${REMOTE} будет добавлен'
# en: Remote:       URL of ${REMOTE} will be updated
L_m167='Remote:       URL ${REMOTE} будет обновлён'
# en: Only files tracked by Git are updated; local files are never mass-cleaned.
L_m168='Обновляются только файлы под управлением Git; общей очистки локальных файлов нет.'
# en: If there are local edits, I will offer to back them up and replace them with the repository version.
L_m169='При локальных правках предложу сохранить копию и заменить их версией из репозитория.'
# en: In --auto mode local edits stop the update; conflicts with local files are protected too.
L_m170='В режиме --auto локальные правки останавливают обновление; конфликты локальных файлов также защищены.'
# en: 1) Yes, update
L_m171='1) Да, обновить'
# en: 2) Sync status
L_m172='2) Статус синхронизации'
# en: 3) Set up auto-deploy via GitHub Actions
L_m173='3) Настроить автодеплой через GitHub Actions'
# en: 4) Change language
L_m174='4) Сменить язык'
# en: 5) Cancel
L_m175='5) Отмена'
# en: Choose an option [5]:
L_m176='Выберите пункт [5]: '
# en: Cancelled.
L_m177='Отменено.'
# en: Error: enter a number from 1 to 5.
L_m178='Ошибка: введите число от 1 до 5.'
# en: Initializing Git repository...
L_m179='Инициализация Git-репозитория...'
# en: Adding remote ${REMOTE}...
L_m180='Добавление remote ${REMOTE}...'
# en: Updating URL of remote ${REMOTE}...
L_m181='Обновление URL remote ${REMOTE}...'
# en: Using SSH Deploy Key ${SSH_PRIVATE_KEY}.
L_m182='Используется SSH Deploy Key ${SSH_PRIVATE_KEY}.'
# en: Using credentials from ${CONFIG_FILE}.
L_m183='Используются данные доступа из ${CONFIG_FILE}.'
# en: Fetching changes from GitHub...
L_m184='Получение изменений из GitHub...'
# en: Error: could not fetch data over SSH.
L_m185='Ошибка: не удалось получить данные по SSH.'
# en: Check the Deploy Key in GitHub, the settings in ${CONFIG_FILE} and repository permissions.
L_m186='Проверьте Deploy Key в GitHub, настройки в ${CONFIG_FILE} и права репозитория.'
# en: Error: could not fetch data from GitHub.
L_m187='Ошибка: не удалось получить данные из GitHub.'
# en: Check the settings in ${CONFIG_FILE}, internet access and repository permissions.
L_m188='Проверьте настройки в ${CONFIG_FILE}, доступ к интернету и права репозитория.'
# en: To reconfigure, delete ${CONFIG_FILE}.
L_m189='Для повторной настройки удалите ${CONFIG_FILE}.'
# en: Check the SSH key, internet access and repository permissions.
L_m190='Проверьте SSH-ключ, доступ к интернету и права репозитория.'
# en: Branch ${REMOTE}/${BRANCH} not found; GitHub reports ${REMOTE_DEFAULT_BRANCH} as the default branch.
L_m191='Ветка ${REMOTE}/${BRANCH} не найдена, GitHub сообщает основной веткой ${REMOTE_DEFAULT_BRANCH}.'
# en: Use ${REMOTE_DEFAULT_BRANCH}? [Y/n]:
L_m192='Использовать ${REMOTE_DEFAULT_BRANCH}? [Y/n]: '
# en: Error: branch ${REMOTE}/${BRANCH} not found.
L_m193='Ошибка: ветка ${REMOTE}/${BRANCH} не найдена.'
# en: Check the branch name in the config ${CONFIG_FILE}.
L_m194='Проверьте имя ветки в конфиге ${CONFIG_FILE}.'
# en: Error: the local history has commits that are not in the target branch.
L_m195='Ошибка: локальная история содержит коммиты, которых нет в целевой ветке.'
# en: Update stopped: local commits will not be discarded.
L_m196='Обновление остановлено: локальные коммиты не будут сброшены.'
# en: Local changes to tracked files detected:
L_m197='Обнаружены локальные изменения отслеживаемых файлов:'
# en: Error: --auto mode does not discard local edits without confirmation.
L_m198='Ошибка: режим --auto не сбрасывает локальные правки без подтверждения.'
# en: Run the script without --auto and choose restoring from the repository.
L_m199='Запустите скрипт без --auto и выберите восстановление из репозитория.'
# en: Changes in the working files (relative to the index):
L_m200='Изменения в рабочих файлах (относительно индекса):'
# en: Changes staged with git add (relative to HEAD):
L_m201='Изменения, подготовленные через git add (относительно HEAD):'
# en: Replace these edits with the ${REMOTE}/${BRANCH} version?
L_m202='Заменить эти правки версией ${REMOTE}/${BRANCH}?'
# en: 1) Yes, back up the edits and restore from the repository
L_m203='1) Да, сохранить резервную копию правок и восстановить из репозитория'
# en: 2) No, keep the edits and cancel the update
L_m204='2) Нет, оставить правки и отменить обновление'
# en: No confirmation received. Edits kept, update cancelled.
L_m205='Подтверждение не получено. Правки сохранены, обновление отменено.'
# en: Edits kept, update cancelled.
L_m206='Правки сохранены, обновление отменено.'
# en: Error: restoring local edits requires Git 2.23 or newer.
L_m207='Ошибка: для восстановления локальных правок нужен Git 2.23 или новее.'
# en: Edits are untouched. Update Git and run the script again.
L_m208='Правки сохранены без изменений. Обновите Git и повторите запуск.'
# en: Error: could not back up the edits. Restore cancelled.
L_m209='Ошибка: не удалось сохранить резервную копию правок. Восстановление отменено.'
# en: Edits backed up: ${BACKUP_REF}
L_m210='Резервная копия правок сохранена: ${BACKUP_REF}'
# en: To restore the edits: git stash apply --index ${BACKUP_REF}
L_m211='Для возврата правок: git stash apply --index ${BACKUP_REF}'
# en: Error: local changes remain (for example, in submodules). Update stopped.
L_m212='Ошибка: остались локальные изменения (например, в подмодулях). Обновление остановлено.'
# en: Syncing the working copy...
L_m213='Синхронизация рабочей копии...'
# en: Error: Git could not safely update the working copy.
L_m214='Ошибка: Git не смог безопасно обновить рабочую копию.'
# en: See the message above: a conflict with a local file or an access error is possible.
L_m215='Проверьте сообщение выше: возможен конфликт с локальным файлом или ошибка доступа.'
# en: GIT_CLEAN=1 ignored: mass cleaning is disabled in version ${SCRIPT_VERSION}.
L_m216='GIT_CLEAN=1 проигнорирован: общая очистка отключена в версии ${SCRIPT_VERSION}.'
# en: ✓ Your local files (keys, config, uploads) are untouched. Nothing to do.
L_m217='✓ Ваши локальные файлы (ключи, конфиг, загрузки) не тронуты. Ничего делать не нужно.'
# en: Done: the server is synchronized with ${REMOTE}/${BRANCH}.
L_m218='Готово: сервер синхронизирован с ${REMOTE}/${BRANCH}.'
# en: not detected
L_m219='не определена'
# en: no commits
L_m220='нет коммитов'
# en: no data
L_m221='нет данных'
# en:   ✓ ${name} — created
L_m222='  ✓ ${name} — создан'
# en:   ✓ ${name} — overwritten
L_m223='  ✓ ${name} — перезаписан'
# en:   ✗ ${name} — refusing to write an empty value.
L_m224='  ✗ ${name} — пустое значение не записывается.'
# en:   ✗ ${name} — could not read the secrets list to verify (the token needs Secrets: Read).
L_m225='  ✗ ${name} — не удалось прочитать список secrets для проверки (токену нужно право Secrets: Read).'
# en:   ✗ ${name} — written, but not found in the repository Actions secrets afterwards.
L_m226='  ✗ ${name} — записан, но после этого не найден в Actions secrets репозитория.'
# en:   ✗ ${name} — GitHub did not update the secret (update time unchanged).
L_m227='  ✗ ${name} — GitHub не обновил секрет (время изменения не изменилось).'
# en:   ✗ ${name} — GitHub CLI failed to write the secret.
L_m228='  ✗ ${name} — GitHub CLI не смог записать секрет.'
# en: Target: ${slug} → Settings → Secrets and variables → Actions → Repository secrets.
L_m229='Куда пишем: ${slug} → Settings → Secrets and variables → Actions → Repository secrets.'
# en: DEPLOY_SSH_KEY is missing in ${slug} and the private part of the old key is not stored on the server. A new key pair will be created.
L_m230='DEPLOY_SSH_KEY отсутствует в ${slug}, а приватная часть старого ключа на сервере не хранится. Будет создана новая пара ключей.'
# en:   • DEPLOY_SSH_KEY already exists in ${slug}; its value cannot be read back. To replace it, choose option 2 (create new keys) next time.
L_m231='  • DEPLOY_SSH_KEY уже есть в ${slug}; его значение прочитать нельзя. Чтобы заменить, в следующий раз выберите пункт 2 (создать новые ключи).'
# en: Error: ${secrets_failed} secret(s) were not written. Nothing is claimed as configured.
L_m232='Ошибка: секретов не записано: ${secrets_failed}. Автодеплой не считается настроенным.'
# en: The private part of the old key is not stored on the server. Choose 1 only if the DEPLOY_SSH_KEY secret already holds a valid key; if unsure, choose 2.
L_m233='Приватная часть старого ключа на сервере не хранится. Выбирайте 1, только если секрет DEPLOY_SSH_KEY уже содержит рабочий ключ; если не уверены, выбирайте 2.'
# en: You chose the existing key: DEPLOY_SSH_KEY is NOT shown and NOT written by this run. Make sure it already exists in the repository secrets; otherwise run the wizard again and choose option 2.
L_m234='Вы выбрали существующий ключ: DEPLOY_SSH_KEY в этом запуске НЕ показывается и НЕ записывается. Убедитесь, что он уже есть в secrets репозитория, иначе запустите мастер снова и выберите пункт 2.'
# en: Running post-deploy hook .deploy/post_deploy.sh ...
L_m235='Запускаю хук после деплоя .deploy/post_deploy.sh ...'
# en: Error: the post-deploy hook failed (exit code ${hook_status}). Files are synchronized, but the post-deploy step did not finish.
L_m236='Ошибка: хук после деплоя завершился с кодом ${hook_status}. Файлы синхронизированы, но шаг после деплоя не выполнен.'
# en:   • .github/workflows/deploy.yml already exists in ${branch}: left unchanged, only secrets were written. To replace it, set SYNC_REPO_OVERWRITE_WORKFLOW=1.
L_m237='  • .github/workflows/deploy.yml уже есть в ${branch}: не изменён, записаны только secrets. Чтобы заменить файл, задайте SYNC_REPO_OVERWRITE_WORKFLOW=1.'
