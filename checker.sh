#!/bin/sh

# Настройки
FOLDER="/root/checker"
LAST_SENT_IDS_FILE="$FOLDER/last_sent_ids.txt"
URL=$(echo $(cat $FOLDER/link.txt))
CHAT_ID=$(echo $(cat $FOLDER/chat_id.txt))
BOT_TOKEN=$(echo $(cat $FOLDER/bot_token.txt))

# XPath паттерны
# Иногда отдаётся страничка с другой разметкой, поэтому вариантов несколько
IDS_PATTERN='//div[@itemtype="http://schema.org/Product"]/@data-marker'

TITLES_PATTERN='//div[@data-marker="leftChildrenVerticalContainer"]/div/text()'
TITLES_PATTERN_TWO='//p[@data-marker="item/title"]/span/text()'
TITLES_PATTERN_THREE='//div[@data-marker="mainVerticalContainerLeft"]/div/div/text()'

PRICES_PATTERN='//div[@data-marker="priceLabelList"]/span/text()'
PRICES_PATTERN_TWO='//div[@itemprop="offers"]/div[@itemprop="price"]/text()'
PRICES_PATTERN_THREE='//div[@data-marker="priceFlexContainerGrid"]/div/text()'

PREVIEWS_PATTERN='//div[@itemtype="http://schema.org/Product"]//img/@src'

# -------------------------------------------------------------------------

echo $(date '+%Y-%m-%d %H:%M:%S') - Работаем: $URL

# Скачиваем страницу
CONTENT=$(wget -qO- "$URL")

# Парсим
# ID
IDS=$(echo "$CONTENT" | xmllint --noout --html --xpath "$IDS_PATTERN" - 2> /dev/null | grep -o '[0-9]*')

# Названия
echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую первый XPath паттерн для названий..."
TITLES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$TITLES_PATTERN" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1 | sed 's/</%3C/g; s/#/%23/g; s/>/%3E/g; s/&/%26/g') # html escape
#echo "$TITLES"
if [ -z "$TITLES" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую второй XPath паттерн для названий..."
    TITLES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$TITLES_PATTERN_TWO" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1 | sed 's/</%3C/g; s/#/%23/g; s/>/%3E/g; s/&/%26/g') # html escape
    #echo "$TITLES"
fi
if [ -z "$TITLES" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую третий XPath паттерн для названий..."
    TITLES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$TITLES_PATTERN_THREE" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1 | sed 's/</%3C/g; s/#/%23/g; s/>/%3E/g; s/&/%26/g') # html escape
    #echo "$TITLES"
fi

# Цены
echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую первый XPath паттерн для цен..."
PRICES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$PRICES_PATTERN" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1)
echo "$PRICES"
if [ -z "$PRICES" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую второй XPath паттерн для цен..."
    PRICES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$PRICES_PATTERN_TWO" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1)
    #echo "$PRICES"
fi
if [ -z "$PRICES" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - пробую третий XPath паттерн для цен..."
    PRICES=$(echo "$CONTENT" | xmllint --noout --html --xpath "$PRICES_PATTERN_THREE" - 2> /dev/null | iconv -s -f utf-8 -t iso-8859-1)
    #echo "$PRICES"
fi

# Картинки
PREVIEWS=$(echo "$CONTENT" | xmllint --noout --html --xpath "$PREVIEWS_PATTERN" - 2> /dev/null | grep -o 'http[^"]*')

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

# Отправляем
exec 3< <(echo "$TITLES")
exec 4< <(echo "$PRICES")
exec 5< <(echo "$PREVIEWS")

while IFS= read -r id || [[ -n "$id" ]]; do
    read -r -u 3 title
    read -r -u 4 price
    read -r -u 5 preview

    if grep -qxF "$id" $LAST_SENT_IDS_FILE; then
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Объявление $id уже отправляли, пропускаем..."
      continue
    fi

    MESSAGE_TEXT="<b>$title</b>%0A$price%0A—————%0A<a href=%22https://avito.ru/$id%22>https://avito.ru/$id</a>"
    
    if [[ -z "$preview" ]]; then
      LINK="https://api.telegram.org/bot$BOT_TOKEN/sendMessage?chat_id=$CHAT_ID&text=$MESSAGE_TEXT&parse_mode=html"
      wget -qO /dev/null "$LINK"
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Отправил объявление: $title за $price ["https://avito.ru/$id"]"
    else
      LINK="https://api.telegram.org/bot$BOT_TOKEN/sendPhoto?chat_id=$CHAT_ID&photo=$preview?a&caption=$MESSAGE_TEXT&parse_mode=html"
      wget -qO /dev/null "$LINK"
      echo "$(date '+%Y-%m-%d %H:%M:%S') - Отправил объявление: $title за $price ["https://avito.ru/$id"]"
    fi

    echo "$id" >> $LAST_SENT_IDS_FILE
    
done < <(echo "$IDS") 

exec 3<&-
exec 4<&-
exec 5<&-
