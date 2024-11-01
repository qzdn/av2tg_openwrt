#!/bin/sh

#####################################################################################
#                                                                                   #
#   1. Настройки                                                                    #
#   1.1. Установите пакеты: opkg update && opkg install libxml2-utils iconv         #    
#   1.2. Положите скрипт в отдельную папку, например, /root/av2tg.                  #
#   1.3. Положите рядом со скриптом файл настроек settings.txt, в котором:          #
#   - на первой строке - chat_id (узнать можно у @JsonDumpBot)                      #
#   - на второй строке - bot_token (@BotFather)                                     #
#   - на третьей строке - url настроенного поиска (https://avito.ru/moscow/...)     #                                                                                                      #
#   Пример:                                                                         #
#       123456                                                                      #
#       1111111111:...                                                              #
#       https://www.avito.ru/moskva/telefony/mobile-ASgBAgICAUSwwQ2I_Dc?f=AS...     #
#                                                                                   #
#   2. Выдайте права на запуск:                                                     #
#       chmod +x checker.sh                                                         #
#                                                                                   #
#   3. Добавьте в cron:                                                             #
#       */5 * * * * /root/av2tg/checker.sh > /root/av2tg/messages.log 2>&1 &        #
#                                                                                   #
#   Посмотреть, что случилось в процессе работы, можно в файле messages.log         #
#   после запуска скрипта в cron, либо через ./checker.sh > messages.log 2>&1       #
#                                                                                   #
#####################################################################################

# Пути к файлам
WORKING_FOLDER=$(dirname "$0")
SETTINGS_FILE="settings.txt"
SENT_IDS_FILE="sent_ids.txt"

cd "${WORKING_FOLDER}"
[ -f "${SETTINGS_FILE}" ] || { echo "$(date "+%Y-%m-%d %H:%M:%S") - отсутствует файл настроек ${SETTINGS_FILE}"; exit 1; }

# Читаем файл настроек
SETTINGS=$(cat "${SETTINGS_FILE}")
CHAT_ID=$(echo "${SETTINGS}" | sed -n "1p" | tr -d "\n\r")
BOT_TOKEN=$(echo "${SETTINGS}" | sed -n "2p" | tr -d "\n\r")
SEARCH_URL=$(echo "${SETTINGS}" | sed -n "3p" | tr -d "\n\r")

# XPath паттерны
ADS_PATTERN="//div[@data-marker=\"item\"]"
IDS_PATTERN="//div[@data-marker=\"item\"]/@data-item-id"
TITLES_PATTERN="//h3[@itemprop=\"name\"]/text()"
PRICES_PATTERN="//meta[@itemprop=\"price\"]/@content"
PREVIEWS_PATTERN="//img[@itemprop=\"image\"]/@srcset"

get_digits() { grep -o "[0-9]*"; }
fix_charset() { iconv -f utf-8 -t iso-8859-1; }
xpath_parse() { echo "$1" | xmllint --noout --html --xpath "$2" - 2>/dev/null | fix_charset; }
html_escape() { sed 's/ /%20/g; s/</%3C/g; s/>/%3E/g; s/&/%26/g; s/#/%23/g; s/"/%22/g; s/?/%3F/g; s/=/%3D/g; s/\./%2E/g; s/\:/%3A/g; '; }

#####################################################################################

# Скачиваем страницу
echo "$(date "+%Y-%m-%d %H:%M:%S") - скачивание ${SEARCH_URL}..."
# Удаляем лишние переносы строк и пробелы
CONTENT=$(wget -qO- "${SEARCH_URL}" | tr "\n" " ")

# Получаем объявления по отдельности
echo "$(date "+%Y-%m-%d %H:%M:%S") - парсинг объявлений..."
ADS=$(xpath_parse "${CONTENT}" "${ADS_PATTERN}")

# Проверяем, нашли ли объявления
if [ -z "${ADS}" ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - объявления не найдены: блок от Авито, некорректная страница/адрес или что-то ещё :("
    exit 1
fi

# Проверяем и укорачиваем файл sent_ids.txt, если отправленных объявлений > 200
[ -f "${SENT_IDS_FILE}" ] || { echo "$(date "+%Y-%m-%d %H:%M:%S") - создание ${SENT_IDS_FILE}..."; touch "$SENT_IDS_FILE"; }
LINE_COUNT=$(wc -l < "${SENT_IDS_FILE}")
if [ "${LINE_COUNT}" -gt 200 ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - отправленных объявлений больше 200, укорачиваем ${SENT_IDS_FILE}..."
    sed -i "1,$((LINE_COUNT - 200 + 1))d" "${SENT_IDS_FILE}"
fi

# Читаем отправленные ID
SENT_IDS=$(cat "${SENT_IDS_FILE}")

# Обработка объявлений
echo "$ADS" | while read -r ad; do
    if [ -z "${ad}" ]; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - пустой элемент объявления, пропускаем..."
        continue
    fi
    
    ID=$(xpath_parse "${ad}" "${IDS_PATTERN}" | get_digits)
    TITLE=$(xpath_parse "${ad}" "${TITLES_PATTERN}" | html_escape)
    PRICE=$(xpath_parse "${ad}" "${PRICES_PATTERN}" | get_digits)
    PREVIEW=$(xpath_parse "${ad}" "${PREVIEWS_PATTERN}" | sed -n "s/.*472w,\s*\(https[^,]*\)\s*636w.*/\1/p")

    # Если значения пусты - пропускаем
    if [ -z "${ID}" ] || [ -z "${TITLE}" ] || [ -z "${PRICE}" ]; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - неполные данные для объявления, пропускаем..."
        continue
    fi

    # Проверка на пустые превью
    if [ -z "${PREVIEW}" ]; then
        PREVIEW="-" # Пустая строка для совпадения с другими элементами
    fi

    # Формируем сообщение
    MESSAGE_TEXT="<b>${TITLE}</b>%0A${PRICE}₽%0A—————%0A<a href=\"https://avito.ru/${ID}\">https://avito.ru/${ID}</a>"
    
    # Проверяем, отправляли ли уже это объявление
    if echo "${SENT_IDS}" | grep -qxF "${ID}"; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - ${ID} - ${TITLE} уже отправляли, пропускаем..."
        continue
    fi

    # Формируем параметры для отправки
    if [ "${PREVIEW}" != "-" ]; then
        PARAMS="sendPhoto?chat_id=${CHAT_ID}&photo=${PREVIEW}&caption=${MESSAGE_TEXT}&parse_mode=html"
    else
        PARAMS="sendMessage?chat_id=${CHAT_ID}&text=${MESSAGE_TEXT}&parse_mode=html"
    fi

    # Отправляем сообщение
    echo "$(date "+%Y-%m-%d %H:%M:%S") - отправка ${TITLE} за ${PRICE}Р [https://avito.ru/${ID}]..."
    wget -q -O /dev/null "https://api.telegram.org/bot${BOT_TOKEN}/${PARAMS}"   # https://core.telegram.org/bots/api#making-requests
    
    # Добавляем ID в файл
    echo "$ID" >> "$SENT_IDS_FILE"
done
