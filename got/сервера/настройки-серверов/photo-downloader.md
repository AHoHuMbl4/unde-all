# photo-downloader — Полная документация сервера

> Последнее обновление: 2026-02-23

---

## 1. Железо (Hardware)

| Параметр     | Значение                         |
|--------------|----------------------------------|
| Провайдер    | Hetzner Cloud                    |
| Тип сервера  | CX23                             |
| CPU          | 2 vCPU — AMD EPYC-Rome, 1 socket, 2 cores, 1 thread/core, x86_64 |
| RAM          | 4 GB (3.7 GiB доступно)         |
| Swap         | Нет (0B)                         |
| Диск         | 40 GB NVMe (/dev/sda, QEMU)     |
| Занято диска | ~3.5 GB (10%)                    |
| Public IP    | 89.167.99.242 (eth0)             |
| Private IP   | 10.1.0.10 (enp7s0, Hetzner Cloud Private Network) |
| Docker bridge| 172.17.0.1/16, 172.18.0.1/16    |

---

## 2. ОС и системные настройки

| Параметр     | Значение                         |
|--------------|----------------------------------|
| OS           | Ubuntu 24.04.3 LTS               |
| Kernel       | 6.8.0-90-generic                 |
| Hostname     | photo-downloader                 |
| Machine ID   | e5664cd125e64141b4ac27f9a4e61b7c |
| Timezone     | Etc/UTC (UTC, +0000)             |
| NTP          | active (systemd-timesyncd)       |
| DNS          | 127.0.0.53 (systemd-resolved)    |
| Default GW   | 172.31.1.1 via eth0              |

---

## 3. Установленное ПО

| Компонент        | Версия   | Как установлен              | Путь / Расположение                    | Статус  |
|------------------|----------|-----------------------------|----------------------------------------|---------|
| Docker Engine    | 29.2.1   | get.docker.com script       | /usr/bin/docker                        | running |
| Docker Compose   | v5.0.2   | Docker plugin (bundled)     | docker compose (plugin)                | running |
| containerd       | —        | Вместе с Docker             | /usr/bin/containerd                    | running |
| node_exporter    | 1.8.2    | Бинарь + systemd service    | /usr/local/bin/node_exporter           | active  |
| Git              | 2.43.0   | apt (system)                | /usr/bin/git                           | —       |
| Python           | 3.12.3   | apt (system)                | /usr/bin/python3                       | —       |
| OpenSSH          | —        | apt (system)                | /usr/sbin/sshd                         | running |
| qemu-guest-agent | —        | apt (Hetzner image)         | —                                      | running |

---

## 4. Слушающие порты

| Порт  | Bind адрес      | Сервис            | Протокол | Процесс          |
|-------|-----------------|-------------------|----------|-------------------|
| 22    | 0.0.0.0 / [::] | SSH (sshd)        | TCP      | sshd (pid 1390)   |
| 53    | 127.0.0.53/54   | DNS (resolved)    | TCP      | systemd-resolved  |
| 9100  | 0.0.0.0         | node_exporter     | HTTP     | node_exporter (pid 3929) |

> Примечание: Docker-контейнеры photo-downloader и downloader-beat НЕ публикуют порты наружу. Они обращаются к внешним сервисам (DB, Redis, S3, Proxy) изнутри.

---

## 5. Systemd-сервисы (активные, кроме стандартных)

| Сервис                        | Описание                              |
|-------------------------------|---------------------------------------|
| docker.service                | Docker Engine                         |
| containerd.service            | Container runtime                     |
| node_exporter.service         | Prometheus Node Exporter              |
| ssh.service                   | OpenSSH server                        |
| qemu-guest-agent.service      | Hetzner Cloud гостевой агент          |
| hc-net-ifup@enp7s0.service   | Hetzner Cloud private network         |
| unattended-upgrades.service   | Автоматические обновления безопасности|

---

## 6. node_exporter — systemd unit

**Файл:** `/etc/systemd/system/node_exporter.service`
**Бинарь:** `/usr/local/bin/node_exporter` (v1.8.2)
**Пользователь:** `node_exporter` (no-login, no-home)

```ini
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Команды:
- `systemctl status node_exporter`
- `curl http://localhost:9100/metrics | head`

---

## 7. Docker-контейнеры

| Контейнер        | Image                              | Размер | Роль                  | Restart policy  | Memory limit | Статус  |
|------------------|------------------------------------|--------|-----------------------|-----------------|-------------|---------|
| photo-downloader | photo-downloader-photo-downloader  | 580 MB | Celery worker (2 proc)| unless-stopped  | 2 GB        | running |
| downloader-beat  | photo-downloader-downloader-beat   | 580 MB | Celery beat scheduler | unless-stopped  | —           | running |

Дополнительные образы на сервере:
| Image              | Tag       | Размер |
|--------------------|-----------|--------|
| postgres           | 16-alpine | 395 MB |
| prom/node-exporter | v1.7.0    | 37.4 MB|

---

## 8. Docker Compose

**Файл:** `/opt/unde/photo-downloader/docker-compose.yml`

```yaml
services:
  photo-downloader:
    build: .
    container_name: photo-downloader
    restart: unless-stopped
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 2G

  downloader-beat:
    build: .
    container_name: downloader-beat
    restart: unless-stopped
    command: celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
```

> node-exporter работает как systemd service, не в Docker.

---

## 9. Dockerfile

**Базовый образ:** `python:3.12-slim`

```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libpq-dev gcc \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
COPY scripts/ ./scripts/
RUN chmod +x scripts/*.sh
RUN mkdir -p /app/data
CMD ["celery", "-A", "app.celery_app", "worker", "--loglevel=info", "--concurrency=2"]
```

---

## 10. Python-зависимости

| Пакет            | Версия  | Назначение                          |
|------------------|---------|-------------------------------------|
| celery[redis]    | 5.4.0   | Task queue + Redis broker           |
| aiohttp          | 3.11.11 | Async HTTP (скачивание через proxy) |
| boto3            | 1.35.86 | S3 upload в Hetzner Object Storage  |
| psycopg2-binary  | 2.9.10  | PostgreSQL (Staging DB)             |
| Pillow           | 11.1.0  | Валидация скачанных изображений     |

---

## 11. Структура проекта

```
/opt/unde/photo-downloader/  →  symlink на /root/cursor/1/
├── docker-compose.yml          # Оркестрация контейнеров
├── Dockerfile                  # Сборка образа (python:3.12-slim)
├── .env                        # Реальные credentials (НЕ в git)
├── .env.example                # Шаблон без секретов (в git)
├── .gitignore
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py           # Celery config + beat schedule (3 задачи)
│   ├── tasks.py                # download_pending, retry_failed, cleanup_temp
│   ├── downloader.py           # Async скачивание через Bright Data proxy
│   ├── storage.py              # S3 upload через boto3 (напрямую, без proxy)
│   └── db.py                   # PostgreSQL: get_pending, get_failed, update_status, insert_log
├── scripts/
│   ├── run-batch.sh            # Ручной запуск download_pending
│   └── health-check.sh         # Проверка всех сервисов
├── data/                       # Временные файлы (очищается ежедневно в 05:00 UTC)
├── memory-bank/                # Память проекта (6+ файлов)
├── .cursor/rules/              # Правила для Cursor IDE
├── CLAUDE.md                   # Правила для Claude Code CLI
└── AGENTS.md                   # Универсальный якорь правил для AI-агентов
```

---

## 12. Архитектура приложения

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    photo-downloader server (10.1.0.10)                   │
│                                                                         │
│  ┌────────────────┐        ┌────────────────────────────┐               │
│  │ downloader-beat │──task──▶│ photo-downloader (worker)  │              │
│  │ (celery beat)   │        │ celery, 2 processes        │              │
│  │                 │        │                            │              │
│  │ Расписание:     │        │ 1. Получить pending из DB  │              │
│  │  - */15 download│        │ 2. Скачать фото ч/з proxy  │              │
│  │  - :30  retry   │        │ 3. Проверить (Pillow)      │              │
│  │  - 05:00 cleanup│        │ 4. Залить в S3 (напрямую)  │              │
│  └────────────────┘        │ 5. Обновить статус в DB    │              │
│                             │ 6. Записать лог            │              │
│                             └──────┬────┬────┬───────────┘              │
│                                    │    │    │                          │
│  ┌──────────────┐                  │    │    │                          │
│  │ node_exporter │ :9100 metrics   │    │    │                          │
│  │ (systemd)     │                 │    │    │                          │
│  └──────────────┘                  │    │    │                          │
└────────────────────────────────────┼────┼────┼──────────────────────────┘
                                     │    │    │
                 ┌───────────────────┘    │    └──────────────────┐
                 ▼                        ▼                       ▼
     ┌───────────────────┐   ┌──────────────────────┐   ┌──────────────────┐
     │ Staging DB         │   │ Bright Data Proxy     │   │ Hetzner S3       │
     │ 10.1.0.8:6432      │   │ brd.superproxy.io     │   │ hel1.your-       │
     │ (PgBouncer)        │   │ :33335                │   │ objectstorage.com│
     │ DB: unde_staging    │   │ Residential proxy     │   │ Bucket:          │
     │ User: downloader    │   │ Auto IP rotation      │   │ unde-images      │
     └───────────────────┘   │ MITM (ssl=False)       │   └──────────────────┘
                              └──────────────────────┘
                 │
                 ▼
     ┌───────────────────┐
     │ Redis              │
     │ 10.1.0.4:6379/7    │
     │ Celery broker      │
     └───────────────────┘
```

**Поток данных:**
1. Apify scrapers → `raw_products` (image_status='pending')
2. celery beat → отправляет `download_pending` каждые 15 мин
3. worker → `SELECT ... WHERE image_status='pending' LIMIT 200`
4. worker → скачивает до 5 фото/товар через Bright Data (aiohttp, 10 concurrent)
5. worker → валидация (Pillow verify), замена `{width}` → `1920`
6. worker → upload в S3: `originals/{brand}/{external_id}/{N}.jpg`
7. worker → UPDATE `image_urls`, `image_status='uploaded'`
8. worker → INSERT в `scraper_logs`

---

## 13. Celery-задачи (расписание)

| Задача            | Расписание         | Описание                                               |
|-------------------|--------------------|--------------------------------------------------------|
| download_pending  | Каждые 15 мин      | Берёт до 200 pending, скачивает фото, загружает в S3   |
| retry_failed      | Каждый час в :30   | Повторяет failed (max 3 попытки, старше 1 часа)        |
| cleanup_temp      | Ежедневно 05:00 UTC| Удаляет временные файлы из /app/data/                  |

---

## 14. Защита от блокировок

| Механизм                | Описание                                          |
|-------------------------|---------------------------------------------------|
| Residential proxy       | Bright Data — каждый запрос с нового residential IP|
| User-Agent rotation     | 8 реальных браузерных User-Agent строк            |
| Rate limiting           | Max 10 concurrent запросов                        |
| Random delay            | 0.5–2 секунды между запросами                     |
| Exponential backoff     | При 429/503: 5s → 15s → 45s → error              |
| Timeout per image       | 30 секунд                                         |
| Timeout per product     | 120 секунд (все фото)                             |
| Max images per product  | 5                                                 |

---

## 15. Внешние зависимости

| Сервис         | Хост                           | Порт  | Протокол | Auth                                  |
|----------------|--------------------------------|-------|----------|---------------------------------------|
| Staging DB     | 10.1.0.8                       | 6432  | TCP/PG   | user: downloader, password в .env     |
| PgBouncer      | 10.1.0.8                       | 6432  | TCP      | Прозрачный пул перед PostgreSQL       |
| Redis          | 10.1.0.4                       | 6379  | TCP      | Password в REDIS_URL, DB 7            |
| Bright Data    | brd.superproxy.io              | 33335 | HTTP     | Customer ID + zone + password в .env  |
| Hetzner S3     | hel1.your-objectstorage.com    | 443   | HTTPS    | S3_ACCESS_KEY + S3_SECRET_KEY в .env  |
| GitLab         | gitlab-real.unde.life          | 80    | HTTP     | Token в git credential store          |

---

## 16. Переменные окружения (.env)

| Переменная           | Описание                                             | Пример значения                          |
|----------------------|------------------------------------------------------|------------------------------------------|
| STAGING_DB_URL       | PostgreSQL строка подключения через PgBouncer         | postgresql://downloader:***@10.1.0.8:6432/unde_staging |
| REDIS_URL            | Redis строка подключения (Celery broker, DB 7)        | redis://:***@10.1.0.4:6379/7             |
| PROXY_URL            | Bright Data residential proxy URL                     | http://brd-customer-***:***@brd.superproxy.io:33335 |
| S3_ENDPOINT          | Hetzner Object Storage endpoint                       | https://hel1.your-objectstorage.com      |
| S3_ACCESS_KEY        | S3 access key                                         | (в .env)                                 |
| S3_SECRET_KEY        | S3 secret key                                         | (в .env)                                 |
| S3_BUCKET            | S3 bucket name                                        | unde-images                              |
| DOWNLOAD_TIMEOUT     | Таймаут скачивания одного фото (секунды)              | 30                                       |
| MAX_RETRIES          | Макс. количество повторных попыток                    | 3                                        |
| BATCH_SIZE           | Количество товаров за один batch                      | 200                                      |
| CONCURRENT_DOWNLOADS | Макс. параллельных скачиваний                         | 10                                       |

> .env файл НЕ коммитится (в .gitignore). Шаблон: `.env.example`

---

## 17. Таблицы БД (используемые)

### raw_products (ключевые поля для photo-downloader)
| Колонка             | Тип                 | Описание                                    |
|---------------------|---------------------|---------------------------------------------|
| id                  | BIGSERIAL PK        | ID записи                                   |
| external_id         | VARCHAR(100)        | ID товара у бренда                           |
| brand               | VARCHAR(50)         | zara, bershka, ...                           |
| original_image_urls | JSONB               | Массив URL фото от Apify (с {width})        |
| image_urls          | JSONB               | Массив S3 URL после upload                   |
| image_status        | VARCHAR(20)         | pending → uploaded \| error                  |
| error_message       | TEXT                | Текст ошибки                                 |
| raw_data            | JSONB               | Доп. данные (retry_count хранится здесь)     |
| updated_at          | TIMESTAMPTZ         | Время последнего обновления                  |

Индексы: `idx_raw_products_image_status`, `idx_raw_products_brand`, `idx_raw_products_external_id`

### scraper_logs
| Колонка          | Тип                 | Описание                                    |
|------------------|---------------------|---------------------------------------------|
| id               | BIGSERIAL PK        |                                              |
| scraper_name     | VARCHAR(100)        | 'photo_downloader' / 'photo_downloader_retry'|
| run_id           | VARCHAR(100)        | UUID каждого запуска                          |
| status           | VARCHAR(20)         | success \| partial \| error                  |
| records_fetched  | INT                 | Сколько взято из DB                           |
| records_new      | INT                 | Сколько успешно загружено                     |
| records_updated  | INT                 | (не используется, = 0)                        |
| records_errors   | INT                 | Сколько ошибок                                |
| started_at       | TIMESTAMPTZ         | Начало batch                                  |
| completed_at     | TIMESTAMPTZ         | Конец batch                                   |
| duration_seconds | INT                 | Длительность в секундах                       |

---

## 18. S3 Object Storage

| Параметр       | Значение                                         |
|----------------|--------------------------------------------------|
| Провайдер      | Hetzner Object Storage (S3-compatible)            |
| Endpoint       | https://hel1.your-objectstorage.com               |
| Bucket         | unde-images                                       |
| Путь фото      | originals/{brand}/{external_id}/{N}.jpg            |
| Публичный URL  | https://unde-images.hel1.your-objectstorage.com/originals/... |

Пример: `https://unde-images.hel1.your-objectstorage.com/originals/zara/512913640/1.jpg`

---

## 19. Сетевая топология

```
                        Internet
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
     ┌──────────────┐  ┌────────┐  ┌──────────────────┐
     │ Bright Data  │  │ GitLab │  │ Hetzner S3       │
     │ Residential  │  │ gitlab-│  │ hel1.your-       │
     │ Proxy        │  │ real.  │  │ objectstorage.com│
     │ :33335       │  │ unde.  │  │ :443             │
     └──────────────┘  │ life   │  └──────────────────┘
              ▲        └────────┘           ▲
              │                             │
══════════════╪═════════════════════════════╪══════════════
              │   Hetzner Private Network   │
              │        10.1.0.0/16          │
              │                             │
     ┌────────┴─────────────────────────────┴──────────┐
     │            10.1.0.10 / 89.167.99.242            │
     │              photo-downloader (CX23)             │
     │                                                  │
     │  Docker:                    Systemd:             │
     │  - photo-downloader         - node_exporter:9100 │
     │  - downloader-beat          - sshd:22            │
     │                             - docker             │
     └───────────┬─────────────────────┬───────────────┘
                 │                     │
                 ▼                     ▼
     ┌───────────────────┐   ┌───────────────────┐
     │ 10.1.0.8          │   │ 10.1.0.4          │
     │ Staging DB        │   │ Redis             │
     │ PgBouncer :6432   │   │ :6379/7           │
     │ PostgreSQL        │   │ Celery broker     │
     └───────────────────┘   └───────────────────┘
```

---

## 20. Git-репозиторий

| Параметр    | Значение                                                  |
|-------------|-----------------------------------------------------------|
| GitLab      | http://gitlab-real.unde.life/unde/photo-downloader        |
| Ветка       | main                                                      |
| Remote      | origin → http://gitlab-real.unde.life/unde/photo-downloader.git |
| Auth        | git credential store (~/.git-credentials, вне репо)       |
| Локальный путь | /root/cursor/1 (symlink: /opt/unde/photo-downloader)   |

---

## 21. Развёртывание на чистом сервере

```bash
#!/bin/bash
# === 1. Docker ===
curl -fsSL https://get.docker.com | sh

# === 2. node_exporter 1.8.2 ===
cd /tmp
curl -sLO https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter
cat > /etc/systemd/system/node_exporter.service << 'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target
[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now node_exporter

# === 3. Клонировать проект ===
mkdir -p /opt/unde
git clone http://gitlab-real.unde.life/unde/photo-downloader.git /opt/unde/photo-downloader
cd /opt/unde/photo-downloader

# === 4. Настроить .env ===
cp .env.example .env
nano .env   # заполнить реальными credentials

# === 5. Собрать и запустить ===
docker compose build
docker compose up -d

# === 6. Проверить ===
docker compose ps
docker compose logs --tail=20 photo-downloader
docker compose logs --tail=10 downloader-beat
curl -s http://localhost:9100/metrics | head -5
```

---

## 22. Полезные команды

```bash
# Статус контейнеров
docker compose ps

# Логи worker (следить)
docker compose logs -f photo-downloader

# Логи beat scheduler
docker compose logs -f downloader-beat

# Перезапуск после изменения кода
docker compose restart photo-downloader downloader-beat

# Полный пересбор
docker compose down && docker compose build && docker compose up -d

# Ручной запуск batch
./scripts/run-batch.sh

# Health check
./scripts/health-check.sh

# node_exporter
systemctl status node_exporter
curl http://localhost:9100/metrics | head

# Celery inspect
docker compose exec photo-downloader celery -A app.celery_app inspect ping
docker compose exec photo-downloader celery -A app.celery_app inspect active
```
