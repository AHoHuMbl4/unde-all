# Collage Server — полная документация

## Назначение

Сервер **collage** — Celery-воркер, который автоматически склеивает все фотографии одного SKU (товара конкретного цвета) в один горизонтальный коллаж. Коллаж нужен для fal.ai virtual try-on: модель получает все ракурсы товара (перед, зад, бок, деталь, на модели) в одном файле.

Это промежуточное звено в pipeline:
```
Photo Downloader → [Collage Worker] → fal.ai Try-On
```

---

## Сервер

| Параметр     | Значение                       |
|--------------|--------------------------------|
| Хостинг      | Hetzner Cloud                  |
| Модель       | CX33                           |
| CPU          | 4 vCPU (AMD EPYC)             |
| RAM          | 8 GB                           |
| Диск         | 80 GB NVMe                     |
| Public IP    | 65.109.172.52                  |
| Private IP   | 10.1.0.16                      |
| Hostname     | collage                        |
| OS           | Ubuntu 24.04.3 LTS (Noble)     |
| Kernel       | 6.8.0-90-generic               |
| Timezone     | UTC                            |

### Маршрутизация

```
Default gateway: 172.31.1.1 via eth0 (public)
Public:  65.109.172.52/32  on eth0
Private: 10.1.0.16/32      on enp7s0 (Hetzner internal network)
```

Весь трафик к другим серверам UNDE (Redis, PgBouncer) идёт через private network `10.1.0.0/16`.
Трафик к S3 (hel1.your-objectstorage.com) идёт через public interface.

---

## Установленное ПО

| Компонент       | Версия | Установка                 | Статус  |
|-----------------|--------|---------------------------|---------|
| Docker Engine   | 29.2.1 | docker-ce apt repo        | active  |
| Docker Compose  | 5.0.2  | docker-compose-plugin apt | active  |
| node_exporter   | 1.8.2  | binary из GitHub release  | active  |
| Python (system) | 3.12.3 | Ubuntu default            | —       |

### Открытые порты

| Порт | Протокол | Сервис        | Bind    |
|------|----------|---------------|---------|
| 22   | TCP      | sshd          | 0.0.0.0 |
| 9100 | TCP      | node_exporter | 0.0.0.0 |

---

## Как работает проект на этом сервере

### Docker-контейнеры

| Контейнер       | Образ                         | Размер | Роль                          | Статус |
|-----------------|-------------------------------|--------|-------------------------------|--------|
| collage-worker  | collage-collage-worker:latest | 329 MB | Celery worker (concurrency=2) | Up     |
| collage-beat    | collage-collage-beat:latest   | 329 MB | Celery beat (планировщик)     | Up     |

Оба контейнера описаны в `/opt/unde/collage/docker-compose.yml`.
Worker ограничен 4 GB RAM, резервирует 1 GB.

### Алгоритм работы

```
  ┌─────────────────────┐         ┌──────────────────────────────┐
  │ Staging DB          │         │ S3: unde-images              │
  │ 10.1.0.8:6432       │         │ hel1.your-objectstorage.com  │
  │ (PgBouncer)         │         │                              │
  │                     │         │ originals/{brand}/{id}/N.jpg │
  │ raw_products        │         │ collages/{brand}/{id}.jpg    │
  │ scraper_logs        │         └──────────┬───────────────────┘
  └──────┬──────────────┘                    │
         │                                   │
         │ 1. SELECT WHERE                   │ 2. Download
         │    image_status='uploaded'         │    originals
         ▼                                   ▼
  ┌──────────────────────────────────────────────┐
  │  collage-worker (Celery, concurrency=2)      │
  │                                              │
  │  Для каждого SKU:                            │
  │  1. Скачать все оригиналы из S3              │
  │  2. Привести к одной высоте (max height)     │
  │  3. Склеить по горизонтали в одно изображение│
  │  4. Сохранить JPEG quality=95, 4:4:4         │
  │  5. Загрузить коллаж обратно в S3            │
  │  6. Обновить статус в DB → collage_ready     │
  └──────────────────────────────────────────────┘
         │                                   │
         │ UPDATE image_status,              │ Upload collage
         │ collage_url                       │
         ▼                                   ▼
  Staging DB                           S3 collages/
```

**Пошагово:**
1. `collage-beat` запускает задачу `process_new` каждые 15 минут
2. Worker берёт из Staging DB до 100 записей с `image_status='uploaded'`
3. Для каждого SKU: скачивает все его оригинальные фото из S3 bucket `unde-images`
4. Все фото приводятся к одной высоте (max height среди всех фото SKU), пропорции сохраняются
5. Фото склеиваются горизонтально в один коллаж (Pillow)
6. Коллаж сохраняется как JPEG quality=95, subsampling=0 (4:4:4 — без потери цвета)
7. Коллаж загружается в S3: `collages/{brand}/{external_id}.jpg`
8. В DB обновляется: `collage_url` = публичный URL, `image_status` = `collage_ready`
9. При ошибке: `image_status` = `error`, `error_message` = текст ошибки
10. Результат батча логируется в `scraper_logs`

### Что такое коллаж (визуально)

```
Фото SKU "Zara Blazer Black" (image_urls из raw_products):

┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│  1  │ │  2  │ │  3  │ │  4  │
│перед│ │ зад │ │ бок │ │детал│
└─────┘ └─────┘ └─────┘ └─────┘
                    │
                    ▼ Горизонтальная склейка
    ┌───────────────────────────────┐
    │ ┌───┐ ┌───┐ ┌───┐ ┌───┐     │
    │ │ 1 │ │ 2 │ │ 3 │ │ 4 │     │
    │ └───┘ └───┘ └───┘ └───┘     │
    │       КОЛЛАЖ                 │
    │  JPEG q=95, оригинальное     │
    │  разрешение, 4:4:4           │
    └───────────────────────────────┘
                    │
                    ▼
        fal.ai try-on получает
        все ракурсы в одном файле
```

**ВАЖНО:** Разрешение НЕ уменьшается. Качество коллажа напрямую влияет на качество virtual try-on.

### Расписание (Celery Beat)

| Задача        | Расписание          | Описание                                                  |
|---------------|---------------------|-----------------------------------------------------------|
| process_new   | Каждые 15 мин       | Обработать SKU с image_status='uploaded' (до 100 за раз)  |
| retry_failed  | Каждый час в :30    | Повтор ошибочных (cooldown 1 час, до 50 за раз)          |
| cleanup_temp  | Ежедневно 04:00 UTC | Очистка временных файлов /app/data/                       |

---

## Внешние зависимости

| Сервис      | Хост                          | Порт | Протокол  | Назначение                          |
|-------------|-------------------------------|------|-----------|-------------------------------------|
| Staging DB  | 10.1.0.8 (PgBouncer)         | 6432 | TCP       | raw_products, scraper_logs          |
| Redis       | 10.1.0.4                      | 6379 | TCP       | Celery broker (DB 8)                |
| S3 Storage  | hel1.your-objectstorage.com   | 443  | HTTPS     | Оригиналы + коллажи (unde-images)   |
| GitLab      | gitlab-real.unde.life         | 80   | HTTP      | Git-репозиторий проекта             |

### Staging DB — используемые таблицы

**raw_products** (чтение + обновление):
- `id` BIGSERIAL PRIMARY KEY
- `external_id` VARCHAR(100) — ID SKU
- `brand` VARCHAR(50) — "zara", "bershka", ...
- `image_urls` JSONB — массив S3 URL'ов всех фото SKU
- `collage_url` TEXT — URL коллажа (записывается воркером)
- `image_status` VARCHAR(20) — 'uploaded' → 'collage_ready' | 'error'
- `error_message` TEXT
- `updated_at` TIMESTAMPTZ

**scraper_logs** (запись):
- `scraper_name` = 'collage_worker'
- `status` = 'success' | 'partial' | 'error'
- `records_fetched`, `records_new`, `records_errors`
- `started_at`, `completed_at`, `duration_seconds`

### S3 пути

| Тип        | Путь в S3                                  | Пример публичного URL                                               |
|------------|--------------------------------------------|--------------------------------------------------------------------|
| Оригиналы  | `originals/{brand}/{external_id}/N.jpg`    | https://unde-images.hel1.your-objectstorage.com/originals/zara/512913640/1.jpg |
| Коллажи    | `collages/{brand}/{external_id}.jpg`       | https://unde-images.hel1.your-objectstorage.com/collages/zara/512913640.jpg    |

---

## Переменные окружения (.env)

| Переменная       | Описание                                | Пример                                              |
|------------------|-----------------------------------------|------------------------------------------------------|
| STAGING_DB_URL   | PostgreSQL через PgBouncer              | `postgresql://collage:...@10.1.0.8:6432/unde_staging`|
| REDIS_URL        | Redis broker                            | `redis://:...@10.1.0.4:6379/8`                       |
| S3_ENDPOINT      | S3-совместимый endpoint                 | `https://hel1.your-objectstorage.com`                |
| S3_ACCESS_KEY    | S3 access key                           | —                                                    |
| S3_SECRET_KEY    | S3 secret key                           | —                                                    |
| S3_BUCKET        | Имя S3 bucket                           | `unde-images`                                        |
| BATCH_SIZE       | Макс. SKU за батч                       | `100`                                                |
| COLLAGE_QUALITY  | Качество JPEG (1–100)                   | `95`                                                 |

Реальные значения в `/opt/unde/collage/.env` (НЕ в git). Шаблон: `.env.example`.

---

## Сетевая топология

```
                     Internet
                        │
                  ┌─────┴──────┐
                  │  Hetzner   │
                  │  Cloud     │
                  └─────┬──────┘
                        │
         ┌──────────────┼──────────────────┐
         │              │                  │
    ┌────┴─────┐  ┌─────┴──────┐  ┌───────┴──────┐
    │ 10.1.0.4 │  │ 10.1.0.8  │  │ 10.1.0.16    │
    │ Redis    │  │ PgBouncer  │  │ COLLAGE      │
    │ :6379    │  │ :6432      │  │              │
    │          │  │            │  │ worker  x2   │
    │ DB 8:    │  │ Staging DB │  │ beat   x1    │
    │ collage  │  │            │  │ node_exp     │
    │ broker   │  │            │  │ :9100        │
    └──────────┘  └────────────┘  └──────────────┘
                                        │
                                        │ HTTPS
                                        ▼
                               ┌─────────────────┐
                               │ Hetzner S3       │
                               │ hel1.your-       │
                               │ objectstorage    │
                               │ .com             │
                               │ bucket:          │
                               │ unde-images      │
                               └─────────────────┘
```

---

## Структура проекта на сервере

```
/opt/unde/collage/              ← git clone из GitLab
├── docker-compose.yml          ← 2 сервиса: worker + beat
├── Dockerfile                  ← python:3.12-slim + Pillow deps
├── .env                        ← реальные секреты (НЕ в git)
├── .env.example                ← шаблон без секретов
├── requirements.txt            ← celery, Pillow, boto3, psycopg2
├── app/
│   ├── __init__.py
│   ├── celery_app.py           ← Celery config + beat schedule
│   ├── tasks.py                ← process_new, retry_failed, cleanup_temp
│   ├── collage.py              ← склейка изображений (Pillow)
│   ├── storage.py              ← S3 download/upload (boto3)
│   └── db.py                   ← PostgreSQL запросы (psycopg2)
├── scripts/
│   ├── run-batch.sh            ← ручной запуск батча
│   └── health-check.sh         ← проверка здоровья
└── data/                       ← временные файлы (очищается ежедневно)
```

---

## Стек технологий

| Технология       | Назначение                          |
|------------------|-------------------------------------|
| Python 3.12      | Язык приложения (в Docker)          |
| Celery 5.4       | Task queue + beat scheduler         |
| Redis            | Celery broker (DB 8)                |
| Pillow 11.1      | Склейка изображений                 |
| boto3            | S3 операции (download/upload)       |
| psycopg2-binary  | PostgreSQL клиент (через PgBouncer) |
| Docker Compose   | Оркестрация контейнеров             |

---

## Развёртывание на чистом сервере

```bash
# 1. Docker
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

# 2. node_exporter
cd /tmp
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz | tar xz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
useradd --no-create-home --shell /bin/false node_exporter
# Создать /etc/systemd/system/node_exporter.service (см. ниже)
systemctl daemon-reload && systemctl enable --now node_exporter

# 3. Проект
mkdir -p /opt/unde
git clone http://gitlab-real.unde.life/unde/collage.git /opt/unde/collage
cd /opt/unde/collage
cp .env.example .env
nano .env  # заполнить реальные credentials

# 4. Запуск
docker compose build
docker compose up -d

# 5. Проверка
docker compose ps
docker compose logs -f
curl localhost:9100/metrics | head
```

---

## node_exporter — systemd unit

```ini
[Unit]
Description=Prometheus Node Exporter
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

---

## Полезные команды

```bash
# Статус контейнеров
docker compose -f /opt/unde/collage/docker-compose.yml ps

# Логи
docker compose -f /opt/unde/collage/docker-compose.yml logs -f collage-worker
docker compose -f /opt/unde/collage/docker-compose.yml logs -f collage-beat

# Ручной запуск батча
docker compose -f /opt/unde/collage/docker-compose.yml exec collage-worker \
  celery -A app.celery_app call app.tasks.process_new

# Перезапуск
docker compose -f /opt/unde/collage/docker-compose.yml restart

# Обновление после git push
cd /opt/unde/collage && git pull && docker compose build && docker compose up -d

# Health check
/opt/unde/collage/scripts/health-check.sh
```

---

## Git-репозиторий

- **URL**: http://gitlab-real.unde.life/unde/collage
- **Ветка**: master
- **Deploy path**: /opt/unde/collage/
- Секреты в `.env` (gitignored), шаблон в `.env.example`
