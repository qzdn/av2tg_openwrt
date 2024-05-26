#!/bin/sh

# Необходимые пакеты: 
# - wget (по умолчанию установлен uclient-fetch - его должно быть достаточно) 
# - xmllint (парсер)
# - iconv (правит сломанную кодировку кириллицы)
#
# opkg update && opkg install xmllint iconv

# Настройки
FOLDER="/root/checker/"
HTML_FILE="$FOLDER/search_results.html"
LAST_SENT_IDS_FILE="$FOLDER/last_sent_ids.txt"
URL=$(echo $(cat $FOLDER/link.txt))
CHAT_ID=$(echo $(cat $FOLDER/chat_id.txt))
BOT_TOKEN=$(echo $(cat $FOLDER/bot_token.txt))

# XPath паттерны
IDS_PATTERN="//div[@itemtype=\"http://schema.org/Product\"]/@data-marker"
TITLES_PATTERN="//div[@itemtype=\"http://schema.org/Product\"]//div[@data-marker=\"leftChildrenVerticalContainer\"]/div/text()"
PRICES_PATTERN="//div[@itemtype=\"http://schema.org/Product\"]//div[@data-marker=\"priceLabelList\"]/span/text()"
PREVIEWS_PATTERN="//div[@itemtype=\"http://schema.org/Product\"]//img/@src"

# -------------------------------------------------------------------------

echo $(date '+%Y-%m-%d %H:%M:%S') - Работаем: $URL

# Скачиваем страницу
wget -qO "$HTML_FILE" "$URL"

# Парсим
IDS=$(xmllint --noout --html --xpath "$IDS_PATTERN" "$HTML_FILE" 2> /dev/null | grep -o '[0-9]*')
TITLES=$(xmllint --noout --html --xpath "$TITLES_PATTERN" "$HTML_FILE" 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1)
PRICES=$(xmllint --noout --html --xpath "$PRICES_PATTERN" "$HTML_FILE" 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1)
PREVIEWS=$(xmllint --noout --html --xpath "$PREVIEWS_PATTERN" "$HTML_FILE" 2> /dev/null | grep -o 'http[^"]*')

# Проверяем количество ID отправленных объявлений - если > 100, то оставляем только первые 100
if [ ! -f $LAST_SENT_IDS_FILE ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Первый запуск - создаем last_sent_ids.txt..."
    touch $LAST_SENT_IDS_FILE
else
    LINE_COUNT=$(wc -l < $LAST_SENT_IDS_FILE)
    if [ "$LINE_COUNT" -gt 100 ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Отправленных объявлений больше 100. Укорачиваем файл..."
        tail -n 100 $LAST_SENT_IDS_FILE > $FOLDER/last_sent_ids.tmp
        mv $FOLDER/last_sent_ids.tmp $LAST_SENT_IDS_FILE
    fi
fi

exec 3< <(echo "$TITLES")
exec 4< <(echo "$PRICES")
exec 5< <(echo "$PREVIEWS")

while IFS= read -r id || [[ -n "$id" ]]; do
    read -r -u 3 title
    read -r -u 4 price
    read -r -u 5 preview

    MESSAGE_TEXT="<b>$title</b>%0A$price%0A---%0A<a href=\"https://avito.ru/$id\">https://avito.ru/$id</a>"

    if grep -qxF "$id" $LAST_SENT_IDS_FILE; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Объявление $id уже отправляли, пропускаем..."
      continue
    fi

    if [[ -z "$preview" ]]; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Отправляем объявление: $title за $price ["https://avito.ru/$id"]"
      LINK="https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$MESSAGE_TEXT&parse_mode=html"
      wget -q -O /dev/null "$LINK"
    else
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Отправляем объявление: $title за $price ["https://avito.ru/$id"]"
      LINK="https://api.telegram.org/bot$BOT_TOKEN/sendPhoto?chat_id=$CHAT_ID&photo=$preview&caption=$MESSAGE_TEXT&parse_mode=html"
      wget -q -O /dev/null "$LINK"
    fi

    echo "$id" >> $LAST_SENT_IDS_FILE
    
done < <(echo "$IDS") 

exec 3<&-
exec 4<&-
exec 5<&-
