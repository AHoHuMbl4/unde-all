# Server: ximilar-sync
<!-- Полная карта сервера. Обновляй при ЛЮБЫХ инфра-изменениях. -->

---

## Identity

- **Name:** ximilar-sync
- **Role:** Синхронизация каталога товаров из Staging DB в Ximilar Collection для Fashion Recognition Pipeline
- **Provider:** Hetzner Cloud
- **Plan/Model:** CX23 (shared vCPU)
- **Location:** Hetzner Cloud (EU)
- **Project:** UNDE

### Назначение

Сервер выполняет одну задачу: берёт товары из базы данных (`raw_products`), у которых уже загружены фото на S3, и отправляет эти фото с метаданными в Ximilar Collection. Ximilar индексирует изображения, и Recognition Pipeline может искать визуально похожие товары по фото пользователя.

### Место в архитектуре UNDE

```
Scrapers → Staging DB → [ximilar-sync] → Ximilar Collection → Recognition Pipeline → User
           (raw_products)                   (indexed photos)      (visual search)
```

Ximilar-sync — связующее звено между хранилищем товаров и сервисом визуального поиска.

---

## Hardware

| Parameter    | Value                                          |
|--------------|------------------------------------------------|
| **CPU**      | Intel Xeon Processor (Skylake, IBRS) — 2 vCPU  |
| **CPU Clock**| ~2.1 GHz (BogoMIPS: 4190.15)                  |
| **RAM**      | 3.7 GiB total (swap: none)                     |
| **Storage**  | 40 GB SSD (/dev/sda, 38.1G usable, ~9% used)  |
| **Hypervisor**| KVM (QEMU)                                    |

### Disk layout

```
NAME    SIZE  TYPE  MOUNTPOINTS
sda    38.1G  disk
├─sda1 37.9G  part  /              (ext4, main filesystem)
├─sda14   1M  part                 (BIOS boot)
└─sda15 256M  part  /boot/efi      (EFI system)
```

### Disk usage

```
/dev/sda1              38G  3.0G   33G    9%   (OS + Docker + app)
/var/lib/docker             702M               (Docker images + containers)
/opt/unde/ximilar-sync      112K               (app source code)
```

---

## Network

- **Public IP:** 89.167.93.187 (eth0, /32)
- **Private IP:** 10.1.0.11 (enp7s0, /32, Hetzner Cloud Network)
- **Domain/DNS:** нет привязанных доменов
- **Firewall:** не настроен на сервере (делается отдельно на уровне Hetzner Cloud Firewall)
- **SSH access:** порт 22, user root, SSH key auth

### Interfaces

| Interface | IP               | Type    | MTU  | Description                  |
|-----------|------------------|---------|------|------------------------------|
| eth0      | 89.167.93.187/32 | public  | 1500 | Hetzner public IP            |
| enp7s0    | 10.1.0.11/32     | private | 1450 | Hetzner Cloud Network        |
| docker0   | 172.17.0.1/16    | bridge  | 1500 | Default Docker bridge (down) |
| br-174..  | 172.18.0.1/16    | bridge  | 1500 | ximilar-sync_default network |

### Routing

```
default         via 172.31.1.1 dev eth0    (→ internet)
10.1.0.0/16     via 10.1.0.1  dev enp7s0  (→ Hetzner private network, MTU 1450)
172.18.0.0/16   dev br-17456215f964        (→ Docker containers)
```

### Traffic directions

| From → To              | Port  | Direction | Protocol  | Description              |
|------------------------|-------|-----------|-----------|--------------------------|
| ximilar-sync → Redis   | 6379  | outbound  | TCP       | Task queue               |
| ximilar-sync → Staging | 6432  | outbound  | TCP       | Product data             |
| ximilar-sync → Ximilar | 443   | outbound  | HTTPS     | Image upload             |
| Prometheus → ximilar   | 9100  | inbound   | HTTP      | Metrics scraping         |
| Admin → ximilar        | 22    | inbound   | SSH       | Management               |

---

## OS & base setup

| Parameter    | Value                             |
|--------------|-----------------------------------|
| **OS**       | Ubuntu 24.04.3 LTS (Noble Numbat) |
| **Kernel**   | 6.8.0-90-generic (x86_64)        |
| **Hostname** | ximilar-sync                      |
| **Timezone** | UTC (Etc/UTC, +0000)              |
| **NTP**      | active, clock synchronized        |
| **Swap**     | none                              |

---

## Installed software

### System packages

| Component               | Version | How Installed                | Status  |
|-------------------------|---------|------------------------------|---------|
| Docker Engine           | 29.2.1  | apt (docker-ce)              | running |
| Docker CLI              | 29.2.1  | apt (docker-ce-cli)          | —       |
| Docker Compose (plugin) | 5.0.2   | apt (docker-compose-plugin)  | plugin  |
| Docker Buildx (plugin)  | 0.31.1  | apt (docker-buildx-plugin)   | plugin  |
| containerd              | 2.2.1   | apt (containerd.io)          | running |
| node_exporter           | 1.8.2   | binary + systemd             | running |
| Python                  | 3.12.3  | system (Ubuntu)              | present |
| Git                     | 2.43.0  | system (Ubuntu)              | present |
| curl                    | 8.5.0   | system (Ubuntu)              | present |
| OpenSSL                 | 3.0.13  | system (Ubuntu)              | present |

### Python packages (inside Docker containers)

| Package          | Version  | Purpose                                |
|------------------|----------|----------------------------------------|
| celery[redis]    | 5.4.0    | Distributed task queue + Redis support |
| redis            | 5.2.1    | Redis client library                   |
| requests         | 2.32.3   | HTTP client for Ximilar API            |
| psycopg2-binary  | 2.9.10   | PostgreSQL driver for Staging DB       |

### Running systemd services

| Service               | Description                                | Status  |
|-----------------------|--------------------------------------------|---------|
| docker.service        | Docker Application Container Engine        | running |
| containerd.service    | containerd container runtime               | running |
| node_exporter.service | Prometheus Node Exporter 1.8.2             | running |
| ssh.service           | OpenBSD Secure Shell server                | running |
| cron.service          | Regular background program processing      | running |
| rsyslog.service       | System Logging Service                     | running |
| unattended-upgrades   | Automatic security updates                 | running |
| qemu-guest-agent      | QEMU/Hetzner hypervisor agent              | running |

---

## Listening ports

| Port | Bind      | Process         | Protocol  | Purpose                         |
|------|-----------|-----------------|-----------|----------------------------------|
| 22   | 0.0.0.0   | sshd            | TCP       | SSH access                       |
| 53   | 127.0.0.53| systemd-resolve | TCP/UDP   | Local DNS resolver               |
| 53   | 127.0.0.54| systemd-resolve | TCP/UDP   | Local DNS resolver (alt)         |
| 9100 | 0.0.0.0   | node_exporter   | TCP/HTTP  | Prometheus metrics               |

> Контейнеры не публикуют портов наружу — они не принимают входящие HTTP запросы, а только инициируют исходящие подключения.

---

## Running containers & services

| Container      | Image                      | Size   | Command                                        | Memory Limit | Restart Policy  | Status  |
|----------------|----------------------------|--------|-------------------------------------------------|-------------|-----------------|---------|
| ximilar-sync   | ximilar-sync-ximilar-sync  | 501 MB | `celery -A app.celery_app worker --loglevel=info --concurrency=2` | 1 GB | unless-stopped | running |
| ximilar-beat   | ximilar-sync-ximilar-beat  | 501 MB | `celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule` | — | unless-stopped | running |
| node_exporter  | binary /usr/local/bin      | —      | `node_exporter --web.listen-address=0.0.0.0:9100` | — | always (systemd) | running |

### Docker networks

| Network                | Driver | Subnet         | Connected Containers                                    |
|------------------------|--------|----------------|---------------------------------------------------------|
| ximilar-sync_default   | bridge | 172.18.0.0/16  | ximilar-sync (172.18.0.2), ximilar-beat (172.18.0.3)   |

---

## Docker Compose files

Один файл: `docker-compose.yml` — два сервиса:

```yaml
services:
  ximilar-sync:                                # Celery Worker
    build: .                                   # python:3.12-slim, 501 MB
    container_name: ximilar-sync
    restart: unless-stopped
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file: .env
    volumes:
      - ./app:/app/app                         # Code mount (hot reload)
      - ./data:/app/data                       # Runtime data
    deploy:
      resources:
        limits:
          memory: 1G                           # Hard limit — OOM kill при превышении

  ximilar-beat:                                # Celery Beat Scheduler
    build: .
    container_name: ximilar-beat
    restart: unless-stopped
    command: celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
```

---

## Volumes & persistent data

| Host Path                        | Container Path   | Content                     | Used By      | Backup? |
|----------------------------------|------------------|-----------------------------|--------------|---------|
| /opt/unde/ximilar-sync/app      | /app/app         | Application Python code     | sync + beat  | git     |
| /opt/unde/ximilar-sync/data     | /app/data        | celerybeat-schedule (runtime)| sync + beat | no      |

---

## Environment & secrets

Файл: `/opt/unde/ximilar-sync/.env`

```bash
# ===== Database =====
STAGING_DB_URL=postgresql://ximilar:TsdSsI9ysTDgx6JUQXC60zSU@10.1.0.8:6432/unde_staging

# ===== Message Broker =====
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/7

# ===== Ximilar API =====
XIMILAR_API_TOKEN=xxx                    # TODO: заполнить когда получим от Ximilar
XIMILAR_COLLECTION_ID=xxx               # TODO: заполнить когда получим от Ximilar
XIMILAR_API_URL=https://api.ximilar.com

# ===== Application =====
XIMILAR_RATE_LIMIT=10                    # Максимум запросов к Ximilar в секунду
BATCH_SIZE=1000                          # Максимум товаров за один запуск задачи
```

---

## Application architecture

### Обзор

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ximilar-sync server (10.1.0.11)                     │
│                                                                             │
│  ┌───────────────────────┐         ┌───────────────────────────────────┐    │
│  │    ximilar-beat        │         │        ximilar-sync               │    │
│  │    (Celery Beat)       │         │        (Celery Worker)            │    │
│  │                        │         │                                   │    │
│  │  Планирует задачи:     │  Redis  │  Выполняет задачи:                │    │
│  │  • ximilar_sync (Вс)  │────────▶│  1. SELECT pending из Staging DB  │    │
│  │  • ximilar_retry (12h)│  queue  │  2. POST каждое фото в Ximilar   │    │
│  │                        │         │  3. UPDATE статус в Staging DB    │    │
│  │  Schedule хранится в:  │         │  4. INSERT лог в scraper_logs     │    │
│  │  /app/data/celerybeat  │         │                                   │    │
│  │  -schedule             │         │  Concurrency: 2 процесса          │    │
│  └───────────────────────┘         │  Memory limit: 1 GB               │    │
│                                     │  Max tasks per child: 100         │    │
│                                     └───────────────────────────────────┘    │
│                                                                             │
│  ┌────────────────────────────┐                                             │
│  │  node_exporter (:9100)     │  ← Prometheus собирает метрики             │
│  └────────────────────────────┘                                             │
└─────────────────────────────────────────────────────────────────────────────┘
        │                    │                         │
        │ TCP :6379/7        │ TCP :6432               │ HTTPS :443
        ▼                    ▼                         ▼
   ┌──────────┐      ┌──────────────┐          ┌──────────────────┐
   │  Redis   │      │  Staging DB  │          │   Ximilar API    │
   │ 10.1.0.4 │      │  10.1.0.8    │          │ api.ximilar.com  │
   │  db: 7   │      │  PgBouncer   │          │                  │
   │          │      │  :6432       │          │  Fashion         │
   │  broker  │      │  unde_staging│          │  Recognition     │
   │  +result │      │              │          │  Collection      │
   └──────────┘      └──────────────┘          └──────────────────┘
```

### Как работает синхронизация (пошагово)

**Задача `ximilar_sync` (еженедельно, Вс 10:00 UTC):**

```
1. Celery Beat кладёт задачу "ximilar_sync" в Redis очередь
                    │
2. Worker забирает задачу из очереди
                    │
3. Worker делает SQL запрос к Staging DB:
   SELECT id, external_id, brand, name, category, price, image_urls
   FROM raw_products
   WHERE image_status IN ('uploaded', 'collage_ready')
     AND ximilar_status = 'pending'
   ORDER BY id LIMIT 1000
                    │
4. Для каждого товара (product):
   │
   ├─ Извлекает массив URL фотографий из image_urls (JSONB)
   │  Пример: ["https://s3.../photo1.jpg", "https://s3.../photo2.jpg"]
   │
   ├─ Для КАЖДОГО фото отправляет POST запрос в Ximilar API:
   │  POST https://api.ximilar.com/recognition/v2/collectImage
   │  Headers: Authorization: Token {XIMILAR_API_TOKEN}
   │  Body: {
   │      "collection_id": "...",
   │      "image": "https://s3.../photo.jpg",     ← Ximilar скачает сам
   │      "metadata": {
   │          "sku_id": "ABC-123",
   │          "brand": "Nike",
   │          "name": "Air Max 90",
   │          "category": "Sneakers",
   │          "price": "599.00",
   │          "currency": "AED"
   │      }
   │  }
   │  ← Задержка 0.15 сек между запросами (rate limit ~10 req/s)
   │
   ├─ При успехе ВСЕХ фото:
   │  UPDATE raw_products SET ximilar_status='synced', ximilar_synced_at=NOW()
   │
   └─ При ошибке любого фото:
      UPDATE raw_products SET ximilar_status='error', error_message='...'
                    │
5. После обработки всего batch — запись в scraper_logs:
   INSERT INTO scraper_logs (scraper_name='ximilar_sync',
     status='success'|'partial'|'error', records_fetched, records_new, ...)
```

**Задача `ximilar_retry` (ежедневно, 12:00 UTC):**
Аналогичная логика, но выбирает товары со статусом `error`, у которых `updated_at` старше 6 часов.

### Состояния товара (ximilar_status)

```
              ximilar_sync (weekly)
                    │
    ┌───────────────┼───────────────┐
    │               │               │
    ▼               ▼               ▼
 pending ──────► synced         error
    ▲                              │
    │                              │ ximilar_retry (daily, >6h old)
    │                              │
    └──────────── retry ◄──────────┘
                    │
              ┌─────┴─────┐
              ▼           ▼
           synced       error (again)
```

---

## Celery configuration

### Worker settings

| Parameter                         | Value | Description                                           |
|-----------------------------------|-------|-------------------------------------------------------|
| concurrency                       | 2     | Два параллельных процесса (по числу vCPU)             |
| worker_max_tasks_per_child        | 100   | Worker перезапускается после 100 задач (leak prevention)|
| worker_prefetch_multiplier        | 1     | Берёт по одной задаче за раз (fair scheduling)        |
| task_acks_late                    | True  | Подтверждает задачу после выполнения (не до)           |
| task_reject_on_worker_lost        | True  | Возвращает задачу в очередь при гибели worker'а       |
| broker_connection_retry_on_startup| True  | Реконнект к Redis при старте                          |
| task_serializer                   | json  | JSON сериализация задач                               |
| timezone                          | UTC   | Все расписания в UTC                                  |

### Beat schedule

| Task ID              | Celery Task Name          | Schedule                | Description                              |
|----------------------|---------------------------|-------------------------|------------------------------------------|
| ximilar-sync-weekly  | app.tasks.ximilar_sync    | Sunday 10:00 UTC        | Основная синхронизация pending товаров    |
| ximilar-retry-daily  | app.tasks.ximilar_retry   | Daily 12:00 UTC         | Повторная синхронизация error товаров     |

---

## Database interaction

### Staging DB connection

| Parameter  | Value                                                     |
|------------|-----------------------------------------------------------|
| Host       | 10.1.0.8                                                  |
| Port       | 6432 (PgBouncer, не напрямую PostgreSQL)                  |
| Database   | unde_staging                                              |
| User       | ximilar                                                   |
| Password   | TsdSsI9ysTDgx6JUQXC60zSU                                 |
| Driver     | psycopg2-binary 2.9.10                                    |
| Connection | Per-query (open → execute → commit → close)               |

### Таблица raw_products — поля для Ximilar Sync

| Column             | Type           | Description                                          |
|--------------------|----------------|------------------------------------------------------|
| id                 | BIGSERIAL PK   | Internal ID                                          |
| external_id        | VARCHAR(100)   | SKU ID (→ sku_id в Ximilar metadata)                 |
| brand              | VARCHAR(50)    | Бренд товара                                         |
| name               | TEXT           | Название товара                                      |
| category           | TEXT           | Категория товара                                     |
| price              | DECIMAL(10,2)  | Цена (→ строка, currency=AED)                        |
| image_urls         | JSONB          | Массив S3 URL'ов всех фото товара                    |
| image_status       | VARCHAR(20)    | 'uploaded' или 'collage_ready' → готово к синхронизации|
| ximilar_status     | VARCHAR(20)    | 'pending' → 'synced' или 'error'                     |
| ximilar_synced_at  | TIMESTAMPTZ    | Время успешной синхронизации                         |
| error_message      | TEXT           | Текст ошибки (при ximilar_status='error')            |
| updated_at         | TIMESTAMPTZ    | Время последнего обновления записи                   |

### SQL запросы приложения

**1. Получение pending товаров:**
```sql
SELECT id, external_id, brand, name, category, price, image_urls
FROM raw_products
WHERE image_status IN ('uploaded', 'collage_ready')
  AND ximilar_status = 'pending'
ORDER BY id LIMIT 1000
```

**2. Получение error товаров для retry:**
```sql
SELECT id, external_id, brand, name, category, price, image_urls
FROM raw_products
WHERE ximilar_status = 'error'
  AND updated_at < NOW() - INTERVAL '6 hours'
ORDER BY id LIMIT 1000
```

**3. Обновление статуса (success):**
```sql
UPDATE raw_products
SET ximilar_status = 'synced', ximilar_synced_at = NOW(),
    error_message = NULL, updated_at = NOW()
WHERE id = %s
```

**4. Обновление статуса (error):**
```sql
UPDATE raw_products
SET ximilar_status = 'error', error_message = %s, updated_at = NOW()
WHERE id = %s
```

**5. Запись лога batch'а:**
```sql
INSERT INTO scraper_logs
    (scraper_name, status, records_fetched, records_new, records_errors,
     started_at, completed_at, duration_seconds, error_message)
VALUES ('ximilar_sync', %s, %s, %s, %s, %s, %s, %s, %s)
```

### Таблица scraper_logs — формат записи

| Field            | Value               | Description                               |
|------------------|----------------------|------------------------------------------|
| scraper_name     | 'ximilar_sync'       | Константа                                |
| status           | 'success' / 'partial' / 'error' | Итог batch'а                  |
| records_fetched  | N                    | Выбрано из БД                            |
| records_new      | M                    | Успешно синхронизировано                 |
| records_errors   | K                    | С ошибками                               |
| started_at       | timestamp            | Начало batch'а                           |
| completed_at     | timestamp            | Конец batch'а                            |
| duration_seconds | float                | Длительность в секундах                  |

---

## Ximilar API integration

### Credentials

| Parameter           | Env Variable           | Value                          |
|---------------------|------------------------|--------------------------------|
| API URL             | XIMILAR_API_URL        | https://api.ximilar.com        |
| API Token           | XIMILAR_API_TOKEN      | xxx (TODO: fill when available)|
| Collection ID       | XIMILAR_COLLECTION_ID  | xxx (TODO: fill when available)|
| Rate Limit          | XIMILAR_RATE_LIMIT     | 10 req/sec                     |

### HTTP Client

- Library: `requests` 2.32.3 с persistent Session (connection reuse)
- Timeout: 30 секунд
- Auth: `Authorization: Token {XIMILAR_API_TOKEN}`
- Rate limiting: `time.sleep(1/RATE_LIMIT + 0.05)` = 0.15 сек между запросами

### Endpoints

**POST /recognition/v2/collectImage** — добавление фото в Collection
```json
{
    "collection_id": "xxx",
    "image": "https://s3.example.com/photo.jpg",
    "metadata": {
        "sku_id": "ABC-123", "brand": "Nike", "name": "Air Max 90",
        "category": "Sneakers", "price": "599.00", "currency": "AED"
    }
}
```
- Ximilar скачивает фото по URL самостоятельно (публичные S3)
- Каждое фото SKU = отдельный POST
- Ximilar индексирует все ракурсы и матчит по лучшему автоматически

**POST /recognition/v2/collectRemove** — удаление из Collection (реализовано, не используется)

---

## External dependencies

| Service        | Host              | Port  | Protocol     | Auth                                    | Purpose                       |
|----------------|-------------------|-------|--------------|-----------------------------------------|-------------------------------|
| Staging DB     | 10.1.0.8          | 6432  | TCP/PostgreSQL | user: ximilar, pass: TsdSsI9ysTDgx6... | Источник каталога товаров     |
| Redis          | 10.1.0.4          | 6379  | TCP/Redis     | password, database 7                     | Celery broker + result backend|
| Ximilar API    | api.ximilar.com   | 443   | HTTPS         | Token (XIMILAR_API_TOKEN)               | Загрузка фото в Collection   |

### Что будет если зависимость недоступна

| Зависимость  | Поведение                                                       |
|--------------|-----------------------------------------------------------------|
| Redis down   | Worker не запустится, Beat не сможет ставить задачи             |
| Staging DB   | Задача упадёт с ошибкой подключения                             |
| Ximilar API  | Конкретный товар получит status='error', остальные продолжатся   |

---

## Network topology

```
                              Internet
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                     Hetzner Cloud — Private Network 10.1.0.0/16            │
│                                                                            │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────────────┐ │
│  │    10.1.0.4       │  │    10.1.0.8       │  │      10.1.0.11           │ │
│  │    Redis Server   │  │    Staging DB     │  │      ximilar-sync        │ │
│  │                   │  │                   │  │      (this server)       │ │
│  │  :6379 (Redis)    │  │  :6432 (PgBouncer)│  │                          │ │
│  │                   │  │  :5432 (Postgres) │  │  Public: 89.167.93.187   │ │
│  │  DB 7 = celery    │  │  DB: unde_staging │  │  :22   (SSH)             │ │
│  │  broker + results │  │  User: ximilar    │  │  :9100 (node_exporter)   │ │
│  └──────────────────┘  └──────────────────┘  │                          │ │
│           ▲                     ▲              │  Docker internal:        │ │
│           │ TCP :6379           │ TCP :6432    │  172.18.0.1 (bridge)     │ │
│           │                     │              │  172.18.0.2 (sync)       │ │
│           └─────────────────────┼──────────────┤  172.18.0.3 (beat)      │ │
│                                 │              └────────┬─────────────────┘ │
└─────────────────────────────────┼───────────────────────┼──────────────────┘
                                                          │
                                               HTTPS :443 │
                                                          ▼
                                               ┌────────────────────┐
                                               │  api.ximilar.com   │
                                               │  Ximilar Cloud     │
                                               │  (Fashion AI)      │
                                               └────────────────────┘
```

---

## Monitoring & logs

### node_exporter

- **Endpoint:** http://10.1.0.11:9100/metrics
- **Метрики:** CPU, RAM, disk, network, filesystem
- **Systemd unit:** `/etc/systemd/system/node_exporter.service`

```ini
[Unit]
Description=Node Exporter 1.8.2
Documentation=https://github.com/prometheus/node_exporter
Wants=network-online.target
After=network-online.target

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

### Application logs

```bash
docker compose logs -f                       # Все контейнеры
docker compose logs -f ximilar-sync          # Только worker
docker compose logs -f ximilar-beat          # Только scheduler
docker compose logs --tail=50 ximilar-sync   # Последние 50 строк
```

### Пример вывода worker'а

```
[INFO] Starting ximilar_sync task
[INFO] Found 42 pending products
[INFO] Synced product SKU-001 (3 images)
[INFO] Synced product SKU-002 (5 images)
[ERROR] Error syncing product SKU-003: 429 Too Many Requests
[INFO] ximilar_sync completed: 40 synced, 2 errors, 127.3s
```

### Alerts

Не настроены. Ошибки видны в логах и в таблице `scraper_logs` Staging DB.

---

## Project file structure

```
/opt/unde/ximilar-sync/
│
├── docker-compose.yml           # 2 сервиса: worker (concurrency=2, 1GB limit) + beat
├── Dockerfile                   # python:3.12-slim + libpq-dev gcc → 501 MB
├── .env                         # Все credentials (приватный GitLab — допустимо)
├── .env.example                 # Шаблон без реальных секретов
├── requirements.txt             # celery[redis], redis, requests, psycopg2-binary
│
├── app/
│   ├── __init__.py
│   ├── celery_app.py            # Celery config + beat schedule (2 задачи)
│   ├── tasks.py                 # ximilar_sync (weekly) + ximilar_retry (daily)
│   ├── ximilar_client.py        # HTTP client: add_image(), remove_image(), rate limiting
│   └── db.py                    # SQL: get_pending, get_error, update_status, insert_log
│
├── scripts/
│   ├── run-sync.sh              # Ручной запуск
│   └── health-check.sh          # Проверка здоровья
│
└── data/
    └── celerybeat-schedule      # Runtime (автогенерация Celery Beat)
```

---

## Operations & management

### Ручной запуск синхронизации

```bash
cd /opt/unde/ximilar-sync
./scripts/run-sync.sh
# Или напрямую:
docker compose exec ximilar-sync celery -A app.celery_app call app.tasks.ximilar_sync
```

### Перезапуск

```bash
docker compose restart ximilar-sync              # Только worker
docker compose restart ximilar-beat              # Только scheduler
docker compose restart                           # Оба
docker compose down && docker compose up -d      # Полный рестарт
```

### Обновление кода

```bash
cd /opt/unde/ximilar-sync
git pull
docker compose up -d --build
```

### Health check

```bash
/opt/unde/ximilar-sync/scripts/health-check.sh
# Или:
docker compose ps
docker compose exec ximilar-sync celery -A app.celery_app inspect ping
curl -s localhost:9100/metrics | head
```

---

## Deploy procedure

```bash
ssh root@10.1.0.11
cd /opt/unde/ximilar-sync
git pull
docker compose up -d --build
docker compose ps
docker compose logs --tail=20
```

---

## Recovery / rebuild from scratch

```bash
# 1. Install Docker
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 2. Install node_exporter 1.8.2
cd /tmp
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz \
  -o node_exporter.tar.gz
tar xzf node_exporter.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
useradd --no-create-home --shell /bin/false node_exporter
# Создать systemd unit (см. секцию Monitoring), затем:
systemctl daemon-reload
systemctl enable --now node_exporter
rm -rf /tmp/node_exporter*

# 3. Clone project
mkdir -p /opt/unde
git clone http://root:glpat-DubSAfGWeEkHd4-D-suZtm86MQp1OjEH.01.0w1eeq22u@gitlab-real.unde.life/unde/ximilar-sync.git /opt/unde/ximilar-sync
cd /opt/unde/ximilar-sync

# 4. Fill credentials
# nano .env  → XIMILAR_API_TOKEN и XIMILAR_COLLECTION_ID

# 5. Build and start
docker compose build
docker compose up -d

# 6. Verify
docker compose ps
docker compose logs --tail=10
curl -s localhost:9100/metrics | head
```

---

## Known limitations & notes

| Item | Details |
|------|---------|
| **Ximilar credentials** | XIMILAR_API_TOKEN и XIMILAR_COLLECTION_ID = `xxx` — заполнить когда получим |
| **Memory limit** | Worker ограничен 1 GB RAM (OOM kill при превышении) |
| **Rate limit** | Ximilar API ~10 req/sec, задержка 0.15 сек между запросами |
| **Batch size** | Максимум 1000 товаров за запуск (BATCH_SIZE) |
| **No deduplication** | Повторная отправка фото не проверяет, есть ли оно уже в Collection |
| **No deletion** | Устаревшие товары не удаляются из Collection автоматически |
| **No alerting** | Ошибки видны только в логах и scraper_logs |
| **No firewall** | Firewall не настроен (делается отдельно на уровне Hetzner) |
| **Swap disabled** | При нехватке RAM контейнер будет OOM killed |

---

## Changelog

| Date       | Change                    | Details                                                        |
|------------|---------------------------|----------------------------------------------------------------|
| 2026-02-24 | Initial server setup      | Ubuntu 24.04, Docker 29.2.1, Compose 5.0.2                    |
| 2026-02-24 | node_exporter installed   | v1.8.2, systemd service, bind 0.0.0.0:9100                    |
| 2026-02-24 | ximilar-sync deployed     | Full app: worker + beat, connected to Redis, containers running |
