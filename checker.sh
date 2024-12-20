#!/bin/sh

#########################################################################################
#                                                                                       #
#   1. Настройки                                                                        #
#       1.1. Установите пакеты: opkg update && opkg install libxml2-utils iconv curl    #
#       1.2. Положите скрипт в отдельную папку, например, /root/av2tg.                  #
#       1.3. Положите рядом со скриптом файл настроек settings.txt:                     #
#            - На первой строке - chat_id (узнать можно у @JsonDumpBot)                 #
#            - На второй строке - bot_token (@BotFather)                                #
#            - На третьей строке - url настроенного поиска (https://avito.ru/all/...).  #
#              Необходимо выставить сортировку "По дате". Также можно исключать слова   #
#              из поиска через "-" (например, iphone 15 -разбитый).                     #
#                                                                                       #
#       Пример файла settings.txt:                                                      #
#       	123456                                                                      #
#       	1111111111:...                                                              #
#       	https://www.avito.ru/moskva/telefony/mobile-ASgBAgICAUSwwQ2I_Dc?f=AS...     #
#                                                                                       #
#		1.4. При бане по IP можно попробовать экспортировать куки из браузера           #
#			в cookies.txt в формате Netscape (например, с помощью "Get cookies.txt      #
#           LOCALLY" для Chrome) - их также нужно положить рядом с checker.sh           #
#                                                                                       #
#   2. Выдайте права на запуск:                                                         #
#       chmod +x checker.sh                                                             #
#                                                                                       #
#   3. Добавьте в cron c периодом <=5 минут. Например:                                  #
#       */5 * * * * /root/av2tg/checker.sh > /root/av2tg/messages.log 2>&1 &            #
#                                                                                       #
#########################################################################################

# Пути к файлам
WORKING_FOLDER=$(dirname "$0")
SETTINGS_FILE="settings.txt"
SENT_IDS_FILE="sent_ids.txt"
COOKIES_FILE="cookies.txt"

# XPath паттерны
FIREWALL_PATTERN="//div[@class=\"firewall-container\"]"
ADS_PATTERN="//div[@data-marker=\"item\"]"
IDS_PATTERN="//div[@data-marker=\"item\"]/@data-item-id"
TITLES_PATTERN="//h3[@itemprop=\"name\"]/text()"
PRICES_PATTERN="//meta[@itemprop=\"price\"]/@content"
PREVIEWS_PATTERN="//img[@itemprop=\"image\"]/@srcset"

USER_AGENT="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"

get_digits() { grep -o "[0-9]*"; }
fix_charset() { iconv -f utf-8 -t iso-8859-1; }
xpath_parse() { echo "$1" | xmllint --noout --html --xpath "$2" - 2>/dev/null | fix_charset; }
html_escape() { sed 's/ /%20/g; s/</%3C/g; s/>/%3E/g; s/&/%26/g; s/#/%23/g; s/"/%22/g; s/?/%3F/g; s/=/%3D/g; s/\./%2E/g; s/\:/%3A/g; '; }

#####################################################################################

cd "$WORKING_FOLDER"

# Проверка доступности утилит
for cmd in curl xmllint iconv; do
    if ! which "$cmd" >/dev/null 2>&1; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - ошибка: $cmd не установлен"
        exit 1
    fi
done

# Читаем файл настроек
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - отсутствует файл настроек ${SETTINGS_FILE}"
    exit 1
fi

SETTINGS=$(cat "$SETTINGS_FILE")
CHAT_ID=$(echo "$SETTINGS" | sed -n "1p" | tr -d "\n\r")
BOT_TOKEN=$(echo "$SETTINGS" | sed -n "2p" | tr -d "\n\r")
SEARCH_URL=$(echo "$SETTINGS" | sed -n "3p" | tr -d "\n\r")

# Скачиваем страницу, удаляем лишние переносы строк и пробелы
echo "$(date "+%Y-%m-%d %H:%M:%S") - скачиваю ${SEARCH_URL}..."
CONTENT=$(wget -qO- "${SEARCH_URL}" | tr "\n" " ")

# Проверяем на наличие бана и используем cookies.txt при его наличии
if [ -z "$CONTENT" ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - бан IP от Авито, пробую загрузку с использованием cookies.txt..."
    CONTENT=$(curl -s -A "${USER_AGENT}" --cookie "${COOKIES_FILE}" "${SEARCH_URL}" | tr "\n" " ")
    is_blocked=$(echo "$CONTENT" | xmllint --html --xpath "$FIREWALL_PATTERN" - 2>/dev/null)
    if [ -n "$is_blocked" ]; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - бан сохраняется даже с использованием cookies :("
        exit 1
    fi
fi

# Получаем объявления по отдельности и проверяем
echo "$(date "+%Y-%m-%d %H:%M:%S") - парсинг объявлений..."
ADS=$(xpath_parse "${CONTENT}" "${ADS_PATTERN}")
if [ -z "${ADS}" ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - объявления не найдены: некорректный адрес поиска, сменилась разметка или что-то ещё :("
    exit 1
fi

# Проверяем и укорачиваем файл sent_ids.txt, если отправленных объявлений > 200
[ -f "${SENT_IDS_FILE}" ] || { echo "$(date "+%Y-%m-%d %H:%M:%S") - создаю ${SENT_IDS_FILE}..."; touch "$SENT_IDS_FILE"; }
LINE_COUNT=$(wc -l < "${SENT_IDS_FILE}")
if [ "${LINE_COUNT}" -gt 200 ]; then
    echo "$(date "+%Y-%m-%d %H:%M:%S") - отправленных объявлений больше 200, укорачиваю ${SENT_IDS_FILE}..."
    sed -i "1,$((LINE_COUNT - 200 + 1))d" "${SENT_IDS_FILE}"
fi

# Обработка объявлений
SENT_IDS=$(cat "${SENT_IDS_FILE}")
echo "$ADS" | while read -r ad; do
    if [ -z "${ad}" ]; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - пустой элемент объявления, пропускаю..."
        continue
    fi
    
    ID=$(xpath_parse "${ad}" "${IDS_PATTERN}" | get_digits)
    TITLE=$(xpath_parse "${ad}" "${TITLES_PATTERN}" | html_escape)
    PRICE=$(xpath_parse "${ad}" "${PRICES_PATTERN}" | get_digits)
    PREVIEW=$(xpath_parse "${ad}" "${PREVIEWS_PATTERN}" | sed -n "s/.*472w,\s*\(https[^,]*\)\s*636w.*/\1/p")

    # Если значения пусты - пропускаем
    if [ -z "${ID}" ] || [ -z "${TITLE}" ] || [ -z "${PRICE}" ]; then
        echo "$(date "+%Y-%m-%d %H:%M:%S") - неполные данные для объявления, пропускаю..."
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
        echo "$(date "+%Y-%m-%d %H:%M:%S") - ${ID} - ${TITLE} уже отправлялось, пропускаю..."
        continue
    fi

    # Формируем параметры для отправки
    if [ "${PREVIEW}" != "-" ]; then
        PARAMS="sendPhoto?chat_id=${CHAT_ID}&photo=${PREVIEW}&caption=${MESSAGE_TEXT}&parse_mode=html"
    else
        PARAMS="sendMessage?chat_id=${CHAT_ID}&text=${MESSAGE_TEXT}&parse_mode=html"
    fi

    # Отправляем сообщение
    echo "$(date "+%Y-%m-%d %H:%M:%S") - отправляю ${TITLE} за ${PRICE}Р [https://avito.ru/${ID}]..."
    wget -q -O /dev/null "https://api.telegram.org/bot${BOT_TOKEN}/${PARAMS}"   # https://core.telegram.org/bots/api#making-requests
    
    # Добавляем ID в файл
    echo "$ID" >> "$SENT_IDS_FILE"
done
