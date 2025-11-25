# av2tg_openwrt

Уведомлялка о новых объявлениях с Авито для OpenWRT. 

Тестировалось на версии `24.10.4` на роутере `Xiaomi Mi Router 4`.

## Зависимости

- `xmllint` из пакета `libxml2-utils`

Все остальные утилиты (`wget`, `sed`, `gunzip` и т.д.) - из стандартного `busybox`.

## Требования

- ~25 Mb свободной RAM
- ~3 Mb свободной flash памяти (`libxml2`, `libxml2-utils`, временные файлы)

## Настройки

1. Установите пакеты:
```sh
$ opkg update && opkg install libxml2-utils
```

2. Скачайте файлы в отдельную папку, например, `/root/av2tg`:
```sh
$ cd /root && mkdir av2tg && cd av2tg
$ wget -O av2tg.sh https://raw.githubusercontent.com/qzdn/av2tg_openwrt/refs/heads/main/av2tg.sh
$ wget -O user_agents.txt https://raw.githubusercontent.com/qzdn/av2tg_openwrt/refs/heads/main/user_agents.txt
$ touch settings.txt
```

3. Заполните файл настроек `settings.txt`:
- На первой строке - `chat_id` (узнать можно у [@JsonDumpBot](https://t.me/jsondumpbot)).
- На второй строке - `bot_token` ([@BotFather](https://t.me/BotFather)).
- На третьей строке - Request Header `Cookie`. Получить его можно в `Developer Tools` во вкладке `Network` - обновите страницу с настроенным поиском. В первом запросе в `Request Headers` и будет нужный заголовок.
- На четвёртой строке - ссылка на настроенный поиск (с сортировкой `"По дате"`). Желательно не выбирать категории / условия поиска, при которых новые объявления появляются часто (больше 5 в минуту).

Пример файла `settings.txt`:
```
123456
1111111111:AA...
srv_id=...; location=...; ...; ...
https://www.avito.ru/moskva/telefony/mobile-ASgBAgICAUSwwQ2...
```

4. Выдайте права на запуск:
```sh 
$ chmod +x av2tg.sh
```

5. [Добавьте задачу](https://openwrt.org/docs/guide-user/base-system/cron) в `crontab` c периодом около 10 минут:
```sh
$ crontab -e
```
```
*/10 * * * * /root/av2tg/av2tg.sh
```
или
```
# Удаляем логи перед 00:00 и 12:00
59 11,23 * * * rm /root/av2tg/messages.log

# Запускаем скрипт с выводом логов каждые 10 минут со случайной задержкой около минуты с 07:00 до 01:00
*/10 0,7-23 * * * sleep $(( $RANDOM % 60 + 1 )) && /root/av2tg/av2tg.sh >> /root/av2tg/messages.log 2>&1

# ... каждые 30 минут со случайной задержкой около минуты с 01:00 до 07:00
*/30 1-6 * * * sleep $(( $RANDOM % 60 + 1 )) && /root/av2tg/av2tg.sh >> /root/av2tg/messages.log 2>&1
```

