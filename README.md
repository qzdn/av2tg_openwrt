# av2tg_openwrt

### Пакеты

```sh
$ opkg update && opkg install libxml2-utils iconv
```

### link

Настройте параметры поиска **_в мобильной версии сайта_**, установите сортировку "По дате" и вставьте ссылку в `link.txt`

### chat_id

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

### bot_token

[@BotFather](https://t.me/BotFather) > `bot_token.txt`

### Права

```sh
$ chmod +x checker.sh
```

### Cron:

`*/5 * * * * /root/checker/checker.sh > /root/checker/messages.log 2>&1 &`

## TODO

Избавиться от зависимостей полностью, переписав парсинг на `awk`, `grep`, `sed`, etc...
