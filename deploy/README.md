# Памятка: сервер меню

Все команды — на сервере, из папки `/srv/menu/deploy`, если не сказано
другое. Сервер — Linux (Ubuntu 22.04/24.04), не меньше 2 ГБ памяти: первая
сборка образа (Flutter) требует её больше всего.

| Что случилось | Раздел |
|---|---|
| Первый раз ставим | [1. Первый запуск](#1-первый-запуск) |
| Вышла новая версия | [2. Обновление](#2-обновление) |
| После обновления что-то сломалось | [3. Откат](#3-откат) |
| Пропали или испорчены данные | [4. Восстановление из копии](#4-восстановление-из-копии) |
| Проверить, всё ли в порядке | [5. Проверка](#5-проверка) |

---

## 1. Первый запуск

**1.1. Домен.** У регистратора домена создайте записи типа `A` на IP
сервера: для `домен` и для `www.домен`. Подождите, пока заработает:

```sh
ping домен        # должен отвечать IP вашего сервера
```

Без этого HTTPS-сертификат не выдадут. Если `www` не нужен — уберите его
из `Caddyfile` или `nginx-menu.conf`.

**1.2. Docker** (если на сервере его ещё нет):

```sh
curl -fsSL https://get.docker.com | sh
```

Наружу должны быть открыты только порты 80 и 443 (и 22 для SSH).

**Кто держит 80/443.** Если на сервере уже работает другой проект со своим
nginx (как Prosto ERP), Caddy не запускается. Меню не открывает на сервере
ни одного порта: тот nginx достаёт до него по общей сети Docker `edge` по
имени `cafe-menu:8090`. Сеть создаётся один раз и ничья — её не удалит
`docker compose down` ни одного из проектов:

```sh
docker network create edge
```

В nginx того проекта: сеть `edge` в его `docker-compose` (как `external`),
блок из `nginx-menu.conf` и сертификат для домена меню. Это правка чужого
работающего сайта — порядок такой:

1. сертификат для домена меню (тем же способом, что у того проекта);
2. блок `nginx-menu.conf` в конфиг nginx, домен и пути сертификата — свои;
3. `nginx -t` — проверка конфига; только при «test is successful» —
   применение;
4. сразу проверить, что сайт того проекта открывается.

Если сервер только для меню — в `.env` раскомментируйте
`COMPOSE_PROFILES=caddy`, и HTTPS сделает свой Caddy, nginx не нужен.

**1.3. Код проекта.** С вашего компьютера, в Git Bash, из папки проекта:

```sh
tar czf menu.tgz --exclude=build --exclude=.dart_tool --exclude=data \
  --exclude=import-data --exclude=backups --exclude=.env .
scp menu.tgz root@IP-сервера:/srv/
```

На сервере:

```sh
mkdir -p /srv/menu && tar xzf /srv/menu.tgz -C /srv/menu && rm /srv/menu.tgz
cd /srv/menu/deploy
```

**1.4. Настройки:**

```sh
cp .env.example .env
nano .env         # DOMAIN, MENU_URL, PUBLIC_URL, BILLING_CONTACT
```

`MENU_VERSION` поставьте датой: `MENU_VERSION=2026-10-19` — по ней потом
откатываются.

**1.5. Папки для данных.** Сервер в контейнере работает от пользователя
1001, ему нужно право писать:

```sh
mkdir -p data backups
chown 1001:1001 data backups
```

**1.6. «Андалус» (перенос из Supabase)** — до запуска. На своём
компьютере, в папке `server/`:

```sh
DATA_DIR=import-data dart run bin/import_supabase.dart \
  https://ПРОЕКТ.supabase.co КЛЮЧ_anon "Андалус" 3
```

Затем полное меню каждого филиала — из его выгрузки номенклатуры 1С. Оно
заменяет меню из Supabase; переводы и 3D-модели совпавших по названию блюд
сохраняются:

```sh
DATA_DIR=import-data dart run bin/import_1c.dart D:/nomenclature2.json center
DATA_DIR=import-data dart run bin/import_1c.dart D:/nomenclaturemonte.json ntcn
```

И карты глубины для «живого фото» (без них блюдо только сдвигается целиком,
без объёма; ~3 минуты на 450 фото, нужны `pip install onnxruntime pillow
numpy` и модель Depth Anything V2 Small в формате ONNX):

```sh
python tool/depth_maps.py model.onnx import-data/uploads
```

Получится папка `server/import-data` (база и фото). У кафе сразу пробный
срок 14 дней — оплату потом ставите в главной админке. Перенесите папку на
сервер:

```sh
scp -r import-data/. root@IP-сервера:/srv/menu/deploy/data/
```

И на сервере снова: `chown -R 1001:1001 data`.

**1.7. Запуск** (первая сборка — 10–15 минут):

```sh
docker network create edge   # если уже есть — «already exists», это нормально
docker compose up -d --build
docker compose ps          # menu должен стать healthy (и caddy — running,
                           # если включён)
docker compose exec menu curl -fsS http://localhost:8090/api/health  # {"status":"ok",...}
```

После этого — пересылка с домена (nginx или Caddy, см. выше).

**1.8. Главный администратор** (пароль спросит, на экран не выводится):

```sh
docker compose exec menu /app/server/bin/server create-superadmin ВАШ_ЛОГИН
```

Вход: `https://домен/menu-kg/`. Там же выдайте «Андалусу» логин кафе и
выставьте срок оплаты.

**1.9. Ночные копии:**

```sh
chmod +x backup.sh
crontab -e
```

Добавьте строку:

```
0 3 * * * /srv/menu/deploy/backup.sh >> /srv/menu/deploy/backups/backup.log 2>&1
```

Проверьте сразу, не дожидаясь ночи: `./backup.sh` — в `backups/db/`
появится файл `menu-….db`.

> Копии лежат на том же диске. Если сервер умрёт целиком, они пропадут
> вместе с ним. Раз в неделю забирайте их к себе:
> `scp -r root@IP-сервера:/srv/menu/deploy/backups ./menu-backups`

---

## 2. Обновление

1. Залейте новый код, как в шаге 1.3 (папки `deploy/data`, `deploy/backups`
   и `.env` архив не трогает — они не в нём).
2. Копия базы **перед** обновлением:
   ```sh
   ./backup.sh
   ```
3. Запомните текущую версию и поставьте новую:
   ```sh
   grep MENU_VERSION .env      # например 2026-10-19 — запишите
   nano .env                   # MENU_VERSION=2026-11-02 (сегодняшняя дата)
   ```
4. Сборка и запуск:
   ```sh
   docker compose up -d --build
   ```
5. [Проверка](#5-проверка). Меню гостей и вход в админку открываются — готово.

Пока идёт сборка, старая версия продолжает работать. Перерыв для гостей —
несколько секунд при перезапуске.

---

## 3. Откат

Новая версия работает плохо — вернуть прежнюю:

```sh
docker images menu-platform      # какие версии есть на сервере
nano .env                        # MENU_VERSION=прежняя дата
docker compose up -d             # без --build: берётся готовый образ
```

Данные кафе при этом остаются. Если новая версия успела **испортить
данные** — после отката восстановите копию, сделанную перед обновлением
(раздел 4).

Старые образы занимают место. Когда новая версия проработала неделю без
проблем, лишние можно удалить: `docker image rm menu-platform:старая-дата`.

---

## 4. Восстановление из копии

Возвращает базу и фото на момент копии. Всё, что кафе изменили **после**
неё, пропадёт — выбирайте самую свежую подходящую копию.

```sh
ls -lt backups/db | head         # копии, сверху самые новые
docker compose stop menu
docker compose run --rm menu /app/server/bin/server restore /backups/db/menu-2026-10-19_03-00-00.db
docker compose start menu
```

Текущая база не удаляется, а сохраняется рядом:
`data/menu.db.before-restore-…`. Если восстановили не ту копию — её можно
вернуть так же, командой `restore` с этим файлом.

Если сервер не дал восстановить с сообщением «Порт 8090 занят» — значит,
`menu` не остановлен: повторите `docker compose stop menu`.

---

## 5. Проверка

```sh
curl -fsS https://домен/api/health    # {"status":"ok",...}
docker compose ps                     # menu: healthy
docker compose logs --tail=100 menu   # последние записи сервера
docker compose logs -f caddy          # HTTPS, если включён Caddy (Ctrl+C — выйти)
tail backups/backup.log               # как прошли ночные копии
ls -lt backups/db | head -3           # дата последней копии
df -h /srv                            # место на диске
```

Что означают ответы `/api/health`:

- `"status":"ok"` — всё работает;
- ответ 503 — сервер жив, но нет доступа к базе или к папке файлов: смотрите
  `docker compose logs menu`, часто это права на `data` (шаг 1.5);
- нет ответа — `docker compose ps`; если `menu` не запущен, то
  `docker compose up -d` и снова логи.

Перезапуск всего: `docker compose restart`. Сервер после перезагрузки
машины поднимается сам.
