#!/bin/sh

FIRST_RUN=1

# Пути к файлам
WORKING_FOLDER=$(dirname "$0")
SETTINGS_FILE="settings.txt"
SENT_IDS_FILE="sent_ids.txt"
PREV_RUN_IDS_FILE="prev_run_ids.txt"
USER_AGENTS_FILE="user_agents.txt"

# XPath паттерны
ADS_PATTERN="//div[@data-marker=\"item\" and not(ancestor::div[@data-marker=\"itemsCarousel\"])]"
IDS_PATTERN="//div[@data-marker=\"item\"]/@data-item-id"
TITLES_PATTERN="//a[@itemprop=\"url\"]/text()"
PRICES_PATTERN="//meta[@itemprop=\"price\"]/@content"
PREVIEWS_PATTERN="(//img[@itemprop=\"image\"])[1]/@srcset"

log() { echo "$(date "+%Y-%m-%d %H:%M:%S") - $*"; }
get_digits() { grep -o "[0-9]*"; }

# xmllint почему-то ломает кодировку у кириллицы, исправляем костылём
xpath_parse() { 
    echo "$1" | sed '1i\<?xml version="1.0" encoding="UTF-8"?>' | \
    xmllint --noout --html --xpath "$2" - 2>/dev/null; 
}

# https://core.telegram.org/bots/api#making-requests
send_tg_message() { wget -q -O /dev/null "$1" --post-data="$2"; }

html_escape() {
    sed -e 's/"/%22/g' -e 's/#/%23/g' -e 's/%/%25/g'  -e 's/&/%26/g' \
        -e "s/'/%27/g" -e 's/+/%2B/g' -e 's/\./%2E/g' -e 's/\//%2F/g' \
        -e 's/:/%3A/g' -e 's/</%3C/g' -e 's/=/%3D/g' -e 's/>/%3E/g' -e 's/?/%3F/g'
}

################################################################################

cd "${WORKING_FOLDER}"

log "проверка наличия сети..."
if ! ping -c 3 -W 1 api.telegram.org >/dev/null 2>&1; then
    log "отсутствует соединение c api.telegram.org"
    exit 1
fi

# Проверка доступности xmllint
command -v xmllint >/dev/null 2>&1 || { log "не установлен пакет libxml2-utils"; exit 1; }

# Читаем файл настроек
if [ ! -f "${SETTINGS_FILE}" ]; then
    log "отсутствует файл настроек ${SETTINGS_FILE}"
    exit 1
fi

SETTINGS=$(cat "${SETTINGS_FILE}")
CHAT_ID=$(echo "${SETTINGS}" | sed -n "1p" | tr -d "\n\r")
BOT_TOKEN=$(echo "${SETTINGS}" | sed -n "2p" | tr -d "\n\r")
COOKIES=$(echo "${SETTINGS}" | sed -n "3p" | tr -d "\n\r")
SEARCH_URL=$(echo "${SETTINGS}" | sed -n "4p" | tr -d "\n\r")

# Проверяем, что все данные указаны
if [ -z "${CHAT_ID}" ] || \
    [ -z "${BOT_TOKEN}" ] || \
    [ -z "${COOKIES}" ] || \
    [ -z "${SEARCH_URL}" ]; then
    log "в ${SETTINGS_FILE} не хватает данных (CHAT_ID, BOT_TOKEN, COOKIES или SEARCH_URL)"
    exit 1
fi

# Скачиваем страницу, удаляем лишние переносы строк
log "скачиваю "${SEARCH_URL}"..."

# https://stackoverflow.com/a/449890
USER_AGENT=$(head -$(( ${RANDOM} % `wc -l < "${USER_AGENTS_FILE}"` + 1 )) "${USER_AGENTS_FILE}" | tail -1)

CONTENT=$(wget -qO- --timeout=30 \
          --user-agent="${USER_AGENT}" \
          --header="Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8" \
          --header="Accept-Language: ru-RU,ru;q=0.9" \
          --header="Accept-Encoding: gzip;q=1.0" \
          --header="Cache-Control: no-cache, max-age=0" \
          --header="Connection: keep-alive" \
          --header="Cookie: ${COOKIES}" \
          --header="DNT: 1" \
          --header="Host: www.avito.ru" \
          --header="Referer: https://www.avito.ru/autosearch" \
          --header="Referrer-Policy: origin" \
          --header="Sec-Fetch-Dest: document" \
          --header="Sec-Fetch-Mode: navigate" \
          --header="Sec-Fetch-Site: same-origin" \
          --header="Upgrade-Insecure-Requests: 1" \
          "${SEARCH_URL}" 2>&1 | gunzip -c - | tr -d "\n\r")

# Проверяем, что ответ не пустой
if [ -z "${CONTENT}" ]; then
    log "пустой ответ от Авито, возможен блок (429)"
    exit 1
fi

# Получаем объявления по отдельности
log "парсинг объявлений..."
ADS=$(xpath_parse "${CONTENT}" "${ADS_PATTERN}")
if [ -z "${ADS}" ]; then
    log "объявления не найдены: некорректный url, сменилась разметка или что-то ещё :("
    exit 1
fi
CONTENT=""

# Получаем ID объявлений
IDS=$(xpath_parse "${ADS}" "${IDS_PATTERN}" | get_digits)

# Проверяем, что файлы существуют и не пустые
if [ -s "${PREV_RUN_IDS_FILE}" ] && [ -s "${SENT_IDS_FILE}" ]; then
    FIRST_RUN=0

    # Изредка Авито отдаёт объявления без сортировки по дате, что руинит обычную работу скрипта.
    # Проверяем, что >10 из 50 объявлений совпадают с прошлой выдачей из prev_run_ids.txt.
    log "проверяю корректность сортировки Авито (по дате)..."
    MATCHED_IDS=$(printf '%s\n' "${IDS}" | grep -Fxf - "${PREV_RUN_IDS_FILE}" | wc -l)
    if [ "${MATCHED_IDS}" -le 10 ]; then # ≤10
        log "количество совпадений с предыдущим запуском: ${MATCHED_IDS}, возможно, Авито отдало объявления без сортировки по дате"
        # Если prev_run_ids.txt обновлялся больше часа назад, то считаем, что не было сети / скрипт не работал.
        TS_CURRENT=$(date +%s) # Текущее время в unix time
        TS_PREV_RUN_IDS_FILE=$(date +%s -r "${PREV_RUN_IDS_FILE}") # mtime prev_run_ids.txt в unix time 
        TS_DIFF=$((TS_CURRENT - TS_PREV_RUN_IDS_FILE))
        if [ "${TS_DIFF}" -gt 3600 ]; then # 3600 секунд
            log "${PREV_RUN_IDS_FILE} обновлялся больше часа назад - возможно, не было сети. Обновляю ${PREV_RUN_IDS_FILE}..."
            echo "${IDS}" > "${PREV_RUN_IDS_FILE}"

            NOTIF_MSG="Скрипт долгое время не работал, возможен спам"
            send_tg_message "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" "chat_id=${CHAT_ID}&text=${NOTIF_MSG}&parse_mode=html"
            log "отправил уведомление в TG"
            exit 0
        fi

        touch "${PREV_RUN_IDS_FILE}"
        exit 1
    fi

    log "проверяю количество отправленных объявлений в ${SENT_IDS_FILE}..."
    LINE_COUNT=$(wc -l < "${SENT_IDS_FILE}")
    if [ "${LINE_COUNT}" -gt 400 ]; then
        log "отправленных объявлений больше 400, укорачиваю ${SENT_IDS_FILE}..."
        sed -i "1,$((LINE_COUNT - 400))d" "${SENT_IDS_FILE}"
    fi
else
    FIRST_RUN=1

    log "первый запуск, создаю "${PREV_RUN_IDS_FILE}"..."
    > "${PREV_RUN_IDS_FILE}"
    log "первый запуск, создаю "${SENT_IDS_FILE}"..."
    > "${SENT_IDS_FILE}"
fi

# Обработка объявлений
SENT_IDS=$(cat "${SENT_IDS_FILE}")
echo "${ADS}" | while read -r ad; do
    ID=$(xpath_parse "${ad}" "${IDS_PATTERN}" | get_digits)

    # Если первый запуск - просто сохраняем айдишники в sent_ids.txt не отправляя
    if [ "${FIRST_RUN}" -eq 1 ]; then
        log "сохраняю "${ID}" в "${SENT_IDS_FILE}"..."
        echo "${ID}" >> "${SENT_IDS_FILE}"
        continue
    fi

    # Проверяем, отправляли ли уже это объявление
    if echo "${SENT_IDS}" | grep -qxF "${ID}"; then
        log "${ID} уже отправлялось, пропускаю..."
        continue
    fi

    TITLE=$(xpath_parse "${ad}" "${TITLES_PATTERN}" | html_escape)
    PRICE=$(xpath_parse "${ad}" "${PRICES_PATTERN}" | get_digits)
    PREVIEW=$(xpath_parse "${ad}" "${PREVIEWS_PATTERN}" | sed -n 's/.*\(https[^,]*\) 636w.*/\1/p')

    # Если какие-то значения пусты - пропускаем
    if [ -z "${ID}" ] || [ -z "${TITLE}" ] || [ -z "${PRICE}" ]; then
        log "неполные данные для объявления, пропускаю..."
        continue
    fi

    # Проверка на пустые превью
    if [ -z "${PREVIEW}" ]; then
        PREVIEW="-" # Для совпадения с другими элементами
    fi

    # Формируем текст сообщения
    MESSAGE_TEXT="<b>${TITLE}</b>%0A${PRICE}₽%0A—————%0A<a href=\"https://avito.ru/${ID}\">https://avito.ru/${ID}</a>"

    # Формируем ссылку и параметры для отправки
    if [ "${PREVIEW}" != "-" ]; then
        TG_API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto"
        TG_API_URL_PARAMS="chat_id=${CHAT_ID}&photo=${PREVIEW}&caption=${MESSAGE_TEXT}&parse_mode=html"
    else
        TG_API_URL="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
        TG_API_URL_PARAMS="chat_id=${CHAT_ID}&text=${MESSAGE_TEXT}&parse_mode=html"
    fi

    # Отправляем сообщение
    log "отправляю [https://avito.ru/"${ID}"] - "${TITLE}" за "${PRICE}"Р..."
    send_tg_message "${TG_API_URL}" "${TG_API_URL_PARAMS}"

    # Добавляем ID в список отправленных
    echo "${ID}" >> "${SENT_IDS_FILE}"
done

# Сохраняем ID объявлений с текущего запуска в prev_run_ids.txt, чтобы обойти рандомную выдачу Авито
log "сохраняю текущую выборку объявлений в "${PREV_RUN_IDS_FILE}"..."
echo "${IDS}" > "${PREV_RUN_IDS_FILE}"

# Отправляем сообщение при первом запуске
if [ "$FIRST_RUN" -eq 1 ]; then
    INIT_MSG=$(echo "Сохранил все объявления с первой страницы ("${SEARCH_URL}"), жду новых 😇" | html_escape)
    send_tg_message "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" "chat_id=${CHAT_ID}&text=${INIT_MSG}&parse_mode=html"
    log "отправил приветственное сообщение"
fi
