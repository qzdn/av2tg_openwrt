#!/bin/sh

# Настройки
FOLDER="/root/av2tg_openwrt"
BOT_TOKEN=$(cat "$FOLDER/bot_token.txt")
CHAT_ID=$(cat "$FOLDER/chat_id.txt")
URL=$(cat "$FOLDER/link.txt")
SENT_IDS_FILE="$FOLDER/sent_ids.txt"

# XPath паттерны
# Иногда отдаётся страничка с другой разметкой, поэтому вариантов несколько [25,30]
IDS_PATTERN='//div[@itemtype="http://schema.org/Product"]/@data-marker'
TITLES_PATTERN='//div[@data-marker="leftChildrenVerticalContainer"]/div/text() | //div[@data-marker="mainVerticalContainerLeft"]/div[4]/div/text()'
PRICES_PATTERN='//div[@data-marker="priceLabelList"]/span/text() | //div[@data-marker="priceFlexContainerGrid"]/div[2]/text()'
PREVIEWS_PATTERN='//div[@itemtype="http://schema.org/Product"]//img/@srcset'

xpath_parse() {
    echo "$CONTENT" | xmllint --noout --html --xpath "$1" - 2>/dev/null
}

fix_charset() {
    cat | iconv -s -f utf-8 -t iso-8859-1
}

html_escape() {
    # Почему API отдаёт 400, если в названии есть заглавная H (эйч) - загадка дыры.
    cat | sed 's/</%3C/g; s/>/%3E/g; s/&/%26/g; s/#/%23/g; s/"/%22/g; s/H/%48/g'
}

# -------------------------------------------------------------------------

# Скачиваем страницу
echo "$(date '+%Y-%m-%d %H:%M:%S') - скачивание $URL..."
CONTENT=$(wget -qO- "$URL") || { echo "$(date '+%Y-%m-%d %H:%M:%S') - ошибка скачивания"; exit 1; }

# Парсинг
echo "$(date '+%Y-%m-%d %H:%M:%S') - парсинг IDs..."
IDS=$(xpath_parse "$IDS_PATTERN" | grep -o '[0-9]*')

echo "$(date '+%Y-%m-%d %H:%M:%S') - парсинг названий..."
TITLES=$(xpath_parse "$TITLES_PATTERN" | fix_charset | html_escape)

echo "$(date '+%Y-%m-%d %H:%M:%S') - парсинг цен..."
PRICES=$(xpath_parse "$PRICES_PATTERN" | fix_charset)

echo "$(date '+%Y-%m-%d %H:%M:%S') - парсинг превью..."
PREVIEWS=$(xpath_parse "$PREVIEWS_PATTERN" | grep -Eo '558w,\s(https[^,]+)\s678w' | sed 's/558w, //; s/ 678w//')

# Проверяем и укорачиваем файл sent_ids.txt, если отправленных объявлений > 100
if [ ! -f "$SENT_IDS_FILE" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - первый запуск, создание sent_ids.txt..."
    touch "$SENT_IDS_FILE"
else
    LINE_COUNT=$(wc -l < "$SENT_IDS_FILE")
    if [ "$LINE_COUNT" -gt 100 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - отправленных объявлений больше 100, укорачивание файла..."
        START_LINE=$((LINE_COUNT - 100 + 1)) && sed -i "1,${START_LINE}d" "$SENT_IDS_FILE"
    fi
fi

# Отправляем сообщения в Telegram
exec 3< <(echo "$TITLES")
exec 4< <(echo "$PRICES")
exec 5< <(echo "$PREVIEWS")

while IFS= read -r id || [ -n "$id" ]; do
    read -r -u 3 title
    read -r -u 4 price
    read -r -u 5 preview

    if grep -qxF "$id" "$SENT_IDS_FILE"; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $id уже отправляли, пропускаем..."
        continue
    fi

    MESSAGE_TEXT="<b>$title</b>%0A$price%0A—————%0A<a href=%22https://avito.ru/$id%22>https://avito.ru/$id</a>"

    if [ -z "$preview" ]; then
        LINK="https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$MESSAGE_TEXT&parse_mode=html"
    else
        LINK="https://api.telegram.org/bot$BOT_TOKEN/sendPhoto?chat_id=$CHAT_ID&photo=$preview?a&caption=$MESSAGE_TEXT&parse_mode=html"
    fi

    echo "$(date '+%Y-%m-%d %H:%M:%S') - отправка $title за $price [https://avito.ru/$id]..."
    wget -qO /dev/null "$LINK"
    echo "$id" >> "$SENT_IDS_FILE"

done < <(echo "$IDS")

exec 3<&-
exec 4<&-
exec 5<&-

