#!/bin/sh

###############################################################################
#  1. Настройки                                                               #
#    1.1. Установите пакеты:                                                  #
#      opkg update && opkg install libxml2-utils                              #
#    1.2. Положите скрипт в отдельную папку, например, /root/av2tg            #
#    1.3. Положите рядом со скриптом файл настроек settings.txt:              #
#      - На первой строке - chat_id (узнать можно у @JsonDumpBot)             #
#      - На второй строке - bot_token (@BotFather)                            #
#      - На третьей строке - куки ft ("Aa1aA1a/A+...")                        #
#        Получить cookies можно, например, с помощью "Get cookies.txt         #
#        LOCALLY" для Chrome)                                                 #
#      - На четвёртой строке - url настроенного поиска                        #
#        (например, https://www.avito.ru/moskva/telefony/mobile-ASgBA...)     #
#        Также необходимо выставить сортировку "По дате".                     #
#                                                                             #
#  Пример файла settings.txt:                                                 #
#    123456                                                                   #
#    1111111111:AA...                                                         #
#    "Aa1aA1a/A+..."                                                          #
#    https://www.avito.ru/moskva/telefony/mobile-ASgBAgICAUSwwQ2...           #
#                                                                             #
#  2. Выдайте права на запуск:                                                #
#    chmod +x checker.sh                                                      #
#                                                                             #
#  3. Добавьте в cron c периодом >5-7 минут. Например:                        #
#    */10 * * * * /root/av2tg/checker.sh > /root/av2tg/messages.log 2>&1 &    #
###############################################################################

FIRST_RUN=0

# Пути к файлам
WORKING_FOLDER=$(dirname "$0")
SETTINGS_FILE="settings.txt"
SENT_IDS_FILE="sent_ids.txt"

# XPath паттерны
FIREWALL_PATTERN="//div[@class=\"firewall-container\"]"
ADS_PATTERN="//div[@data-marker=\"item\" and not(ancestor::div[@data-marker=\"itemsCarousel\"])]"
IDS_PATTERN="//div[@data-marker=\"item\"]/@data-item-id"
TITLES_PATTERN="//a[@itemprop=\"url\"]/text()"
PRICES_PATTERN="//meta[@itemprop=\"price\"]/@content"
PREVIEWS_PATTERN="(//img[@itemprop=\"image\"])[1]/@srcset"

USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:139.0) Gecko/20100101 Firefox/139.0"

log() { echo "$(date "+%Y-%m-%d %H:%M:%S") - $*"; }
get_digits() { grep -o "[0-9]*"; }
# xmllint почему-то ломает кодировку у кириллицы, исправляем костылём
xpath_parse() { echo "$1" | sed '1i\<?xml version="1.0" encoding="UTF-8"?>' | xmllint --noout --html --xpath "$2" - 2>/dev/null; }
html_escape() {
    sed -e 's/"/%22/g' -e 's/#/%23/g' -e 's/%/%25/g'  -e 's/&/%26/g' \
        -e "s/'/%27/g" -e 's/+/%2B/g' -e 's/\./%2E/g' -e 's/\//%2F/g' \
        -e 's/:/%3A/g' -e 's/</%3C/g' -e 's/=/%3D/g' -e 's/>/%3E/g' -e 's/?/%3F/g'
}

###############################################################################

cd "$WORKING_FOLDER"

# Проверка доступности утилит
for cmd in xmllint; do
    if ! which "$cmd" >/dev/null 2>&1; then
        log "ошибка: $cmd не установлен"
        exit 1
    fi
done

# Читаем файл настроек
if [ ! -f "$SETTINGS_FILE" ]; then
    log "отсутствует файл настроек ${SETTINGS_FILE}"
    exit 1
fi

SETTINGS=$(cat "$SETTINGS_FILE")
CHAT_ID=$(echo "$SETTINGS" | sed -n "1p" | tr -d "\n\r")
BOT_TOKEN=$(echo "$SETTINGS" | sed -n "2p" | tr -d "\n\r")
FT_COOKIE=$(echo "$SETTINGS" | sed -n "3p" | tr -d "\n\r")
SEARCH_URL=$(echo "$SETTINGS" | sed -n "4p" | tr -d "\n\r")

# Проверяем, что все данные указаны
if [ -z "$CHAT_ID" ] || [ -z "$BOT_TOKEN" ] || [ -z "$FT_COOKIE" ] || [ -z "$SEARCH_URL" ]; then
    log "в settings.txt не хватает данных (CHAT_ID, BOT_TOKEN, FT_COOKIE или SEARCH_URL)"
    exit 1
fi

# Скачиваем страницу, удаляем лишние переносы строк
log "скачиваю ${SEARCH_URL}..."
CONTENT=$(wget -U "${USER_AGENT}" --header="ft: ${FT_COOKIE}" -qO- "${SEARCH_URL}" | tr -d "\n\r")

# Проверяем, что ответ не пустой
if [ -z "$CONTENT" ]; then
    log "пустой ответ от Авито, возможен блок (429)"
    exit 1
fi

# Проверяем на наличие блока
is_blocked=$(echo "$CONTENT" | xmllint --html --xpath "$FIREWALL_PATTERN" - 2>/dev/null)
if [ -n "$is_blocked" ]; then
    log "блок от Авито :("
    exit 1
fi

# Получаем объявления по отдельности и проверяем
log "парсинг объявлений..."
ADS=$(xpath_parse "${CONTENT}" "${ADS_PATTERN}")
if [ -z "${ADS}" ]; then
    log "объявления не найдены: некорректный url, сменилась разметка или что-то ещё :("
    exit 1
fi

# Проверяем, что файл sent_ids.txt существует и он не пустой. 
# Иначе считаем, что это первый запуск и создаём его.
if [ ! -s "${SENT_IDS_FILE}" ]; then
    log "первый запуск, создаю ${SENT_IDS_FILE}..."
    touch "$SENT_IDS_FILE"
    FIRST_RUN=1
else
    # Укорачиваем файл sent_ids.txt, если отправленных объявлений > 200
    log "проверяю количество отправленных объявлений в ${SENT_IDS_FILE}..."
    LINE_COUNT=$(wc -l < "${SENT_IDS_FILE}")
    if [ "${LINE_COUNT}" -gt 200 ]; then
        log "отправленных объявлений больше 200, укорачиваю ${SENT_IDS_FILE}..."
        sed -i "1,$((LINE_COUNT - 200 + 1))d" "${SENT_IDS_FILE}"
    fi
    FIRST_RUN=0
fi

# Обработка объявлений
SENT_IDS=$(cat "${SENT_IDS_FILE}")
echo "$ADS" | while read -r ad; do
    if [ -z "${ad}" ]; then
        log "пустое объявление, пропускаю..."
        continue
    fi

    ID=$(xpath_parse "${ad}" "${IDS_PATTERN}" | get_digits)
    TITLE=$(xpath_parse "${ad}" "${TITLES_PATTERN}" | html_escape)
    PRICE=$(xpath_parse "${ad}" "${PRICES_PATTERN}" | get_digits)
    PREVIEW=$(xpath_parse "${ad}" "${PREVIEWS_PATTERN}" | sed -n "s/.*472w,\s*\(https[^,]*\)\s*636w.*/\1/p")

    # Если первый запуск - просто сохраняем айдишники в sent_ids.txt не отправляя
    if [ "$FIRST_RUN" -eq 1 ]; then
        log "сохраняю ${ID}..."
        echo "$ID" >> "$SENT_IDS_FILE"
        continue
    fi

    # Проверяем, отправляли ли уже это объявление
    if echo "${SENT_IDS}" | grep -qxF "${ID}"; then
        log "${ID} - \"${TITLE}\" уже отправлялось, пропускаю..."
        continue
    fi

    # Если значения пусты - пропускаем
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

    # Формируем параметры для отправки
    if [ "${PREVIEW}" != "-" ]; then
        PARAMS="sendPhoto?chat_id=${CHAT_ID}&photo=${PREVIEW}&caption=${MESSAGE_TEXT}&parse_mode=html"
    else
        PARAMS="sendMessage?chat_id=${CHAT_ID}&text=${MESSAGE_TEXT}&parse_mode=html"
    fi

    # Отправляем сообщение
    log "отправляю ${TITLE} за ${PRICE}Р [https://avito.ru/${ID}]..."
    # https://core.telegram.org/bots/api#making-requests
    wget -q -O /dev/null "https://api.telegram.org/bot${BOT_TOKEN}/${PARAMS}"

    # Добавляем ID в список отправленных
    echo "$ID" >> "$SENT_IDS_FILE"
done

# Сообщение, отправляемое при первом запуске
if [ "$FIRST_RUN" -eq 1 ]; then
    INIT_MSG=$(echo "Сохранил все объявления с первой страницы (${SEARCH_URL}), жду новых 😇" | html_escape)
    wget -q -O /dev/null "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage?chat_id=${CHAT_ID}&text=${INIT_MSG}&parse_mode=html"
    log "отправил приветственное сообщение"
fi
