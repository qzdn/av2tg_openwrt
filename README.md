# av2tg_openwrt

### Пакеты

```sh
$ opkg update && opkg install libxml2-utils iconv
```

### checker.sh

Положите файл в отдельно созданную директорию, например `/root/av2tg_openwrt`. В самом файле укажите полный путь в строке `FOLDER="/root/av2tg_openwrt"`.

### link.txt

Настройте параметры поиска **_в мобильной версии сайта_**, установите сортировку "По дате" и вставьте ссылку в `link.txt`, который должен лежать рядом с `checker.sh`.

### chat_id.txt

Создайте `chat_id.txt` рядом с `checker.sh`.  
[@JsonDumpBot](https://t.me/JsonDumpBot) > `chat_id.txt`

```json
{
  ...
  "message": {
    ...
    "chat": {
          "id": 123456
          ...
    },
    ...
  }
}
```

### bot_token.txt

Создайте `bot_token.txt` рядом с `checker.sh`.  
[@BotFather](https://t.me/BotFather) > `bot_token.txt`

### Права

```sh
$ chmod +x checker.sh
```

### Cron:

`*/5 * * * * /root/av2tg_openwrt/checker.sh > /root/av2tg_openwrt/messages.log 2>&1 &`
