# UNDE Infrastructure — Итоговое ТЗ v6.1

## Принципы архитектуры

- **1 сервер = 1 задача** — изоляция для отладки и масштабирования
- **Staging → Production** — сырые данные не попадают в prod напрямую
- **Фото у нас** — не зависим от CDN брендов, Zara нас не видит
- **Dubai primary, Hetzner replicas** — primary DB в Дубае (bare metal, tmpfs), Hetzner Helsinki — hot standby replicas + бэкапы
- **RAM — единственный bottleneck** — CPU, диск, сеть — всё с запасом 50–100×. Масштабирование = добавление RAM через новые шарды
- **Данные на tmpfs, WAL на NVMe** — максимальная скорость чтения (наносекунды), durability через WAL и streaming replication
- **Chat History + User Knowledge = один шард** — все данные юзера на одном сервере, один запрос для ContextPack
- **Три слоя знания** — User Knowledge (факты) + Semantic Retrieval (эпизоды из чата, pgvector) + Context Agent (мир вокруг юзера)
- **Application-level sharding** — простой hash(user_id) % N в Redis. Никакой магии distributed SQL
- **Client-side verify-and-replay** — нулевая потеря данных при failover. Приложение хранит буфер последних пар и переотправляет при reconnect
- **Failover auto, failback manual** — Patroni переключает на Hetzner автоматически. Возврат на Dubai — только вручную
- **Три агента — сенсоры и актуатор** — Mood Agent (как юзер себя чувствует) + Context Agent (что вокруг) = сенсоры → Persona Agent (как аватар ведёт себя) = актуатор. persona_directive → LLM, voice_params → ElevenLabs, avatar_state → Rive, render_hints → App

---

## Обзор архитектуры

```
                                        INTERNET
                                            │
                        ┌───────────────────┼───────────────────┐
                        │                   │                   │
                        ▼                   ▼                   ▼
                ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
                │  Apify.com   │    │ Zara Mobile  │    │   fal.ai     │
                │  (scrapers)  │    │     API      │    │  (try-on)    │
                └──────┬───────┘    └──────┬───────┘    └──────────────┘
                       │                   │                   ▲
                       │ Резидентные       │ 4 req/час         │
                       │ прокси            │ (наличие)         │
                       ▼                   ▼                   │
              ┌─────────────────┐ ┌─────────────────┐          │
              │ APIFY SERVER    │ │ SCRAPER SERVER  │          │
              │ (10.1.0.7)      │ │ (10.1.0.3)      │          │
              │ Hetzner Helsinki│ │ Hetzner Helsinki│          │
              │                 │ │                 │          │
              │ Задачи:         │ │ Задачи:         │          │
              │ • Метаданные    │ │ • Mobile API    │          │
              │   каталога      │ │   (наличие)     │          │
              │                 │ │ • Sync job      │          │
              └────────┬────────┘ └────────┬────────┘          │
                       │                   │                   │
                       │    ┌──────────────┘                   │
                       │    │                                  │
                       ▼    ▼                                  │
              ┌──────────────────────────────────────┐         │
              │  STAGING DB (10.1.1.3)               │         │
              │  Hetzner Helsinki                    │         │
              │  PostgreSQL 17                       │         │
              │  ├── raw_products (метаданные)       │         │
              │  ├── raw_availability (наличие)      │         │
              │  └── scraper_logs                    │         │
              └─────────────────┬────────────────────┘         │
                                │                              │
     ┌──────────────────────────┼────────────────────┐         │
     │              │           │                    │         │
     ▼              ▼           │                    ▼         │
┌────────────┐ ┌────────────┐  │         ┌─────────────────────────────┐
│PHOTO       │ │XIMILAR     │  │         │  COLLAGE SERVER (10.1.0.8)  │
│DOWNLOADER  │ │SYNC        │  │         │  Hetzner Helsinki           │
│(10.1.0.13) │ │(10.1.0.14) │  │         │                             │
│ • Скачать  │ │ • SKU →    │  │         │  Задачи:                    │
│   фото     │ │   Ximilar  │  │         │  • Скачать из /originals/   │
│ • Upload   │ │   Collection│  │         │  • Склеить в коллаж         │
│   в OS     │ └────────────┘  │         │  • Upload в /collages/      │
└──────┬─────┘                 │         └─────────────────────────────┘
       │                       │
       ▼                       │ SYNC JOB (hourly)
┌─────────────────────┐        ▼
│  OBJECT STORAGE     │ ┌──────────────────────────────────────┐
│  (Hetzner Helsinki) │ │  PRODUCTION DB (10.1.1.2)            │
│                     │ │  Hetzner Helsinki                    │
│  Bucket: unde-images│ │  PostgreSQL 17 + PgBouncer           │
│  ├── /originals/    │ │  └── products                        │
│  └── /collages/     │ │      ├── sku, name, price, brand     │
│                     │ │      ├── image_url (→ /originals/)   │
│  Bucket: user-media │ │      ├── collage_url (→ /collages/)  │
│  └── /{user_id}/    │ │      └── availability (JSONB)        │
│                     │ │  └── routing_table (user → shard)    │
│  Bucket: backups    │ │  └── deleted_messages_registry       │
│  └── /shard-N/      │ └─────────────────┬────────────────────┘
└─────────────────────┘                   │
                     ┌─────────────────────┼──────────────────────┐
                     │                     │                      │
                     ▼                     ▼                      ▼
              ┌──────────────┐  ┌───────────────┐  ┌───────────────────┐
              │ APP SERVER   │  │ TRY-ON SERVICE│  │ RECOGNITION       │
              │ (10.1.0.2)   │  │ (10.1.0.6)    │  │ ORCHESTRATOR      │
              │ Hetzner      │  │ • collage→fal │  │ (10.1.0.9)        │
              │ └── API      │  └───────────────┘  └──┬──────────┬─────┘
              └──────┬───────┘                         │          │
                     │                                 ▼          ▼
                     │                     ┌────────────┐ ┌────────────┐
                     │                     │XIMILAR GW  │ │LLM RERANKER│
                     │                     │(10.1.0.15) │ │(10.1.0.16) │
                     │                     │• detect    │ │• Gemini tag│
                     │                     │• tag       │ │• Gemini    │
                     │                     │• search    │ │  rerank    │
                     │                     └────────────┘ └────────────┘
                     │
                     │  ┌───────────────────────────────────┐
                     │  │ LLM ORCHESTRATOR (10.1.0.17)      │
                     │  │ Hetzner Helsinki                  │
                     │  │ • ContextPack (3 слоя знания)     │
                     │  │   → User Knowledge + Semantic     │
                     │  │     Retrieval + Context Agent      │
                     │  │ • Embedding client (Cohere)       │
                     │  │ • → DeepSeek/Gemini/Claude/Qwen   │
                     │  │ • → Voice Server (текст→TTS)      │
                     │  └───────────────────────────────────┘
                     │
                     │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
                     │  │ MOOD AGENT    │  │ PERSONA AGENT │  │ VOICE SERVER  │
                     │  │ (10.1.0.11)   │  │ (10.1.0.21)   │  │ (10.1.0.12)   │
                     │  │ • Эмоц. анализ│  │ • Характер    │  │ • ElevenLabs  │
                     │  │ • mood_frame  │→ │ • persona_dir │→ │ • TTS stream  │
                     │  └───────────────┘  │ • voice_params│  └───────────────┘
                     │                     │ • avatar_state│
                     │                     │ • render_hints│
                     │                     └───────────────┘
                     │
                     │  ┌───────────────────────────────────┐
                     │  │ CONTEXT AGENT (10.1.0.19)         │
                     │  │ Hetzner Helsinki                  │
                     │  │ • Геолокация, погода, время       │
                     │  │ • Культурный контекст (Рамадан)   │
                     │  │ • Events + Opportunities          │
                     │  │ • → context_frame JSON            │
                     │  └───────────────────────────────────┘
                     │
                     │  ┌─────────────────────────────────────────────────┐
                     │  │ USER DATA LAYER (шардированный)                 │
                     │  │                                                 │
                     │  │ DUBAI PRIMARY SHARD (bare metal, 256 GB RAM)    │
                     │  │ ├── pgdata на tmpfs (RAM) — sub-μs reads       │
                     │  │ ├── WAL на NVMe (synchronous_commit=local)     │
                     │  │ ├── Chat History (pgvector, FTS, партиции)     │
                     │  │ ├── User Knowledge (AES-256)                   │
                     │  │ └── Patroni primary                            │
                     │  │       │                                         │
                     │  │       │ async WAL streaming (120ms)             │
                     │  │       ▼                                         │
                     │  │ HETZNER REPLICA (AX102, 128 GB RAM)            │
                     │  │ ├── Hot standby (NVMe, fsync)                  │
                     │  │ ├── Patroni + etcd → auto failover             │
                     │  │ └── pg_basebackup → Object Storage             │
                     │  │                                                 │
                     │  │ Bucket: unde-user-media 🔒                     │
                     │  └─────────────────────────────────────────────────┘
                     │
                     ▼
              ┌──────────────┐
              │ 📱 ПРИЛОЖЕНИЕ│
              │ Каталог      │
              │ Try-on       │
              │ Recognition  │
              │ Voice + Mood │
              │ Context      │
              └──────────────┘
```

---

## Карта серверов

### Hetzner Helsinki (приложение, каталог, scraping, ML-pipeline)

| Сервер | IP (private) | IP (public) | Задача | Тип | Статус |
|--------|-------------|-------------|--------|-----|--------|
| unde-app | 10.1.0.2 | 46.62.233.30 | API, Nginx, Prometheus | CX43 (160GB) | ✅ Существует |
| scraper | 10.1.0.3 | 46.62.255.184 | Mobile API (наличие) + Sync | CPX22 (80GB) | ✅ Существует |
| push | 10.1.0.4 | 77.42.30.44 | Redis, Celery broker | CPX32 (160GB) | ✅ Существует |
| model-generator | 10.1.0.5 | 89.167.20.60 | AI-модели (аватары) | CPX22 (80GB) | ✅ Существует |
| tryon-service | 10.1.0.6 | 89.167.31.65 | Virtual try-on | CPX22 (80GB) | ✅ Существует |
| **apify** | **10.1.0.7** | — | **Сбор метаданных каталога (Apify.com)** | **CPX21 (80GB)** | 🆕 Создать |
| **collage** | **10.1.0.8** | — | **Склейка фото** | **CPX31 (160GB)** | 🆕 Создать |
| **recognition** | **10.1.0.9** | — | **Recognition Orchestrator (координация pipeline)** | **CPX11 (40GB)** | 🆕 Создать |
| **mood-agent** | **10.1.0.11** | — | **Mood Agent (эмоциональный анализ)** | **CPX11 (40GB)** | 🆕 Создать |
| **voice** | **10.1.0.12** | — | **Voice TTS (ElevenLabs proxy)** | **CPX21 (80GB)** | 🆕 Создать |
| **photo-downloader** | **10.1.0.13** | — | **Скачивание фото брендов → Object Storage** | **CPX21 (80GB)** | 🆕 Создать |
| **ximilar-sync** | **10.1.0.14** | — | **Синхронизация каталога → Ximilar Collection** | **CPX11 (40GB)** | 🆕 Создать |
| **ximilar-gw** | **10.1.0.15** | — | **Ximilar Gateway (detect, tag, search)** | **CPX21 (80GB)** | 🆕 Создать |
| **llm-reranker** | **10.1.0.16** | — | **LLM Reranker (Gemini tag + rerank)** | **CPX11 (40GB)** | 🆕 Создать |
| **llm-orchestrator** | **10.1.0.17** | — | **Диалоговый LLM Orchestrator (генерация ответов аватара)** | **CPX21 (80GB)** | 🆕 Создать |
| **context-agent** | **10.1.0.19** | — | **Context Agent (геолокация, погода, культура, события)** | **CPX11 (40GB)** | 🆕 Создать |
| **persona-agent** | **10.1.0.21** | — | **Persona Agent (характер, тон, стиль, голос, аватар, relationship stage)** | **CPX11 (40GB)** | 🆕 Создать |
| Production DB | 10.1.1.2 | — | PostgreSQL prod + routing_table + tombstone_registry | AX41 (dedicated) | ✅ Существует |
| **staging-db** | **10.1.1.3** | — | **PostgreSQL staging** | **CPX21 (80GB)** | 🆕 Создать |
| GitLab | — | gitlab-real.unde.life | Git репозиторий | — | ✅ Существует |

### Hetzner Helsinki (replicas + etcd + analytics)

| Сервер | IP | Задача | Тип | Статус |
|--------|----|--------|-----|--------|
| **shard-replica-0** | **10.1.1.10** | **Hot standby replica шарда 0 (Patroni + streaming replication)** | **AX102 (128 GB RAM, 2×2TB NVMe)** | 🆕 Создать |
| **etcd-3** | **10.1.1.20** | **etcd quorum node (3-й узел для Patroni)** | **CPX11 (~€4/мес)** | 🆕 Создать |
| **analytics-replica** | — | **Аналитика, B2B отчёты, ML, поведенческий анализ (Фаза 2+)** | **AX162-R (256GB DDR5, $245/мес)** | 📋 Планируется |

### Dubai (primary user data — bare metal)

| Сервер | Задача | Тип | Статус |
|--------|--------|-----|--------|
| **dubai-shard-0** | **Primary DB: Chat History (pgvector, FTS, партиции) + User Knowledge (AES-256). Tmpfs 140 GB, WAL на NVMe** | **Bare metal dedicated (256 GB RAM, 2× EPYC, 2× 2TB NVMe)** | 🆕 Арендовать |
| **etcd-1** | **etcd node на Dubai app-сервере (контейнер)** | **Lightweight VM / контейнер** | 🆕 Создать |

> **Примечание:** Chat History DB и User Knowledge DB больше не являются отдельными серверами на Hetzner. Они объединены на одном шарде (Dubai bare metal primary + Hetzner AX102 replica). Это решение из документов UNDE_Infrastructure_BD и UNDE_Smart_Context_Architecture. При росте до 10,000 юзеров — добавляется второй шард (dubai-shard-1 + shard-replica-1).

---
## 1. SCRAPER SERVER (существующий)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | scraper |
| **Private IP** | 10.1.0.3 |
| **Public IP** | 46.62.255.184 |
| **Тип** | CPX22 |
| **Статус** | ✅ Существует |

### Задачи (обновлённые)

| Задача | Частота | Описание |
|--------|---------|----------|
| **availability_poll** | Каждый час (:00) | Mobile API → Staging DB (наличие в магазинах KZ) |
| **sync_to_production** | Каждый час (:10) | Staging DB → Production DB (verified данные) |

### Что НЕ делает

- ❌ Сбор каталога (это Apify Server)
- ❌ Скачивание фото (это Apify Server)
- ❌ Обработка фото (это Collage Server)

### Конфигурация

```bash
# /opt/unde/scraper/.env

# Staging DB
STAGING_DB_URL=postgresql://scraper:xxx@10.1.1.3:6432/unde_staging

# Production DB
PRODUCTION_DB_URL=postgresql://undeuser:xxx@10.1.1.2:6432/unde_main

# Mobile API
ZARA_USER_AGENT=ZaraApp/15.10.0 ...

# Kazakhstan stores
KZ_ZARA_STORES=6643,9204,9073,16546
```

---

## 2. APIFY SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | apify |
| **Private IP** | 10.1.0.7 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Только сбор метаданных о товарах через Apify.com scrapers:
- Вызов Apify scrapers (резидентные прокси)
- Получение JSON с метаданными: название, цена, размеры, категория, URL фото
- Запись метаданных в Staging DB (image_status='pending')

### Что НЕ делает

- ❌ Скачивание фото (это Photo Downloader, 10.1.0.13)
- ❌ Upload фото в Object Storage (это Photo Downloader)
- ❌ Синхронизация с Ximilar (это Ximilar Sync, 10.1.0.14)

### Задачи

| Задача | Частота | Описание |
|--------|---------|----------|
| **apify_zara** | Еженедельно, Вс 02:00 | Метаданные Zara (~15K товаров) |
| **apify_bershka** | Еженедельно, Вс 03:00 | Метаданные Bershka (~8K товаров) |
| **apify_pullandbear** | Еженедельно, Вс 04:00 | Метаданные Pull&Bear (~6K товаров) |
| **apify_stradivarius** | Еженедельно, Вс 05:00 | Метаданные Stradivarius (~8K товаров) |
| **apify_massimodutti** | Еженедельно, Вс 06:00 | Метаданные Massimo Dutti (~5K товаров) |
| **apify_oysho** | Еженедельно, Вс 07:00 | Метаданные Oysho (~5K товаров) |

### Docker Compose

```yaml
services:
  apify-collector:
    build: .
    container_name: apify-collector
    restart: unless-stopped
    env_file: .env
    deploy:
      resources:
        limits:
          memory: 2G

  celery-beat:
    build: .
    container_name: apify-beat
    restart: unless-stopped
    command: celery -A tasks beat --loglevel=info
    env_file: .env

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.7:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/apify/.env

# Apify
APIFY_TOKEN=apify_api_xxx

# Staging DB
STAGING_DB_URL=postgresql://apify:xxx@10.1.1.3:6432/unde_staging

# Redis (Push Server)
REDIS_URL=redis://:xxx@10.1.0.4:6379/7
```

### Процесс сбора данных

```python
# Псевдокод

def collect_brand(brand: str):
    # 1. Запустить Apify scraper
    run = apify.call(f"datasaurus/{brand}", {
        "startUrls": [f"https://www.{brand}.com/kz/en/"],
        "maxItems": 20000
    })
    
    # 2. Получить результаты
    items = apify.get_dataset_items(run["defaultDatasetId"])
    
    for item in items:
        # 3. Записать метаданные в Staging DB (фото НЕ скачиваем)
        db.execute("""
            INSERT INTO raw_products (source, external_id, brand, name, price,
                                      original_image_urls, image_status, ...)
            VALUES (?, ?, ?, ?, ?, ?, 'pending', ...)
            ON CONFLICT (source, external_id) DO UPDATE SET ...
        """, f"apify_{brand}", item["id"], brand, item["name"],
             item["price"], json.dumps(item["images"]), ...)
```

### Структура директорий

```
/opt/unde/apify/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py
│   ├── tasks.py
│   ├── collectors/
│   │   ├── base.py
│   │   ├── zara.py
│   │   ├── bershka.py
│   │   └── ...
│   └── db.py
├── scripts/
│   ├── run-brand.sh
│   └── health-check.sh
└── data/
```

---

## 3. PHOTO DOWNLOADER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | photo-downloader |
| **Private IP** | 10.1.0.13 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Скачивание фото товаров с сайтов брендов и upload в Object Storage:
- Мониторит Staging DB на записи с `image_status='pending'`
- Скачивает фото по URL из метаданных (до 5 фото на товар)
- Загружает в Object Storage (`/originals/`)
- Обновляет статус на `image_status='uploaded'`

### Почему отдельный сервер

- **Самая хрупкая часть pipeline:** бренды блокируют IP, таймауты, rate limits, капчи
- **Самая тяжёлая по трафику:** ~47K товаров × 5 фото × 300KB = ~70 GB за один цикл
- **Разная частота отказов:** Apify API может работать, а скачивание фото — нет (и наоборот)
- **Отдельный IP:** если заблокируют IP этого сервера, метаданные продолжат собираться

### Задачи

| Задача | Частота | Описание |
|--------|---------|----------|
| **download_pending** | Каждые 15 мин | Скачать фото для товаров с image_status='pending' |
| **retry_failed** | Каждый час (:30) | Повторить неудачные (image_status='error') |
| **cleanup_temp** | Ежедневно 05:00 | Очистить /app/data |

### Docker Compose

```yaml
services:
  photo-downloader:
    build: .
    container_name: photo-downloader
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 2G

  celery-beat:
    build: .
    container_name: downloader-beat
    restart: unless-stopped
    command: celery -A tasks beat --loglevel=info
    env_file: .env

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.13:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/photo-downloader/.env

# Staging DB
STAGING_DB_URL=postgresql://downloader:xxx@10.1.1.3:6432/unde_staging

# Hetzner Object Storage
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=xxx
S3_SECRET_KEY=xxx
S3_BUCKET=unde-images

# Redis (Push Server)
REDIS_URL=redis://:xxx@10.1.0.4:6379/7

# Processing
DOWNLOAD_TIMEOUT=30
MAX_RETRIES=3
BATCH_SIZE=200
CONCURRENT_DOWNLOADS=10
```

### Процесс скачивания

```python
# Псевдокод

def download_pending():
    products = db.query("""
        SELECT id, external_id, brand, original_image_urls
        FROM raw_products
        WHERE image_status = 'pending'
        LIMIT 200
    """)
    
    for product in products:
        try:
            uploaded_urls = []
            for i, url in enumerate(product.original_image_urls[:5]):
                response = requests.get(url, timeout=30)
                local_path = f"/app/data/{product.external_id}_{i}.jpg"
                save(response.content, local_path)
                
                key = f"originals/{product.brand}/{product.external_id}/{i+1}.jpg"
                s3.upload_file(local_path, S3_BUCKET, key)
                uploaded_urls.append(f"{S3_ENDPOINT}/{S3_BUCKET}/{key}")
                os.remove(local_path)
            
            db.execute("""
                UPDATE raw_products
                SET image_urls = ?, image_status = 'uploaded'
                WHERE id = ?
            """, json.dumps(uploaded_urls), product.id)
        except Exception as e:
            db.execute("""
                UPDATE raw_products
                SET image_status = 'error', error_message = ?
                WHERE id = ?
            """, str(e), product.id)
```

### Структура директорий

```
/opt/unde/photo-downloader/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py
│   ├── tasks.py
│   ├── downloader.py
│   ├── storage.py
│   └── db.py
├── scripts/
│   ├── health-check.sh
│   └── test-download.sh
└── data/               # Временные файлы (очищается ежедневно)
```

---

## 4. XIMILAR SYNC SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | ximilar-sync |
| **Private IP** | 10.1.0.14 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Синхронизация каталога товаров в Ximilar Collection (для Fashion Recognition Pipeline):
- Мониторит Staging DB на записи с `ximilar_status='pending'` и `image_status` IN ('uploaded', 'collage_ready')
- Загружает фото в Ximilar Collection с метаданными
- Обновляет статус на `ximilar_status='synced'`

### Почему отдельный сервер

- **Другой внешний API:** Ximilar имеет свои rate limits, своё downtime — не связано с Apify или скачиванием фото
- **Другая частота:** может работать чаще или реже, независимо от сбора каталога
- **Изоляция:** проблемы с Ximilar не блокируют сбор данных и скачивание фото

### Почему CPX11

Лёгкая задача: читает URL'ы из Staging DB, отправляет POST в Ximilar API. I/O bound, минимум CPU/RAM.

### Задачи

| Задача | Частота | Описание |
|--------|---------|----------|
| **ximilar_sync** | Еженедельно, Вс 10:00 | Синхронизация новых/обновлённых SKU → Ximilar Collection |
| **ximilar_retry** | Ежедневно, 12:00 | Повторить неудачные (ximilar_status='error') |

### Docker Compose

```yaml
services:
  ximilar-sync:
    build: .
    container_name: ximilar-sync
    restart: unless-stopped
    env_file: .env
    deploy:
      resources:
        limits:
          memory: 1G

  celery-beat:
    build: .
    container_name: ximilar-beat
    restart: unless-stopped
    command: celery -A tasks beat --loglevel=info
    env_file: .env

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.14:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/ximilar-sync/.env

# Staging DB
STAGING_DB_URL=postgresql://ximilar:xxx@10.1.1.3:6432/unde_staging

# Ximilar
XIMILAR_API_TOKEN=xxx
XIMILAR_COLLECTION_ID=xxx

# Redis (Push Server)
REDIS_URL=redis://:xxx@10.1.0.4:6379/7
```

### Процесс синхронизации

```python
# Псевдокод

def sync_to_ximilar():
    """Загрузить ВСЕ 5-7 фото каждого SKU в Ximilar Collection с метаданными
    (SKU ID, бренд, цена, магазин, этаж). Ximilar индексирует все ракурсы
    и матчит по лучшему автоматически."""
    products = db.query("""
        SELECT id, external_id, brand, name, category, price, image_urls
        FROM raw_products 
        WHERE image_status IN ('uploaded', 'collage_ready')
          AND ximilar_status = 'pending'
        LIMIT 1000
    """)
    
    for product in products:
        try:
            ximilar.add_images(
                collection_id=XIMILAR_COLLECTION_ID,
                images=[{"url": url} for url in product.image_urls],
                metadata={
                    "sku_id": product.external_id,
                    "brand": product.brand,
                    "name": product.name,
                    "category": product.category,
                    "price": str(product.price),
                    "store": product.store_name,
                    "floor": product.floor
                }
            )
            db.execute("""
                UPDATE raw_products 
                SET ximilar_status = 'synced', ximilar_synced_at = NOW()
                WHERE id = ?
            """, product.id)
        except Exception as e:
            db.execute("""
                UPDATE raw_products 
                SET ximilar_status = 'error', error_message = ?
                WHERE id = ?
            """, str(e), product.id)
```

### Структура директорий

```
/opt/unde/ximilar-sync/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py
│   ├── tasks.py
│   ├── ximilar_client.py
│   └── db.py
├── scripts/
│   ├── health-check.sh
│   └── test-sync.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 5. COLLAGE SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | collage |
| **Private IP** | 10.1.0.8 |
| **Тип** | Hetzner CPX31 |
| **vCPU** | 4 |
| **RAM** | 8 GB |
| **Disk** | 160 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Подготовка фото для virtual try-on:
- Скачивание оригиналов из Object Storage
- Склейка нескольких фото в один коллаж
- Upload коллажей в Object Storage
- Обновление URLs в Staging DB

### Что такое коллаж

```
Оригиналы товара (до 5 фото):
┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│  1  │ │  2  │ │  3  │ │  4  │ │  5  │
│перед│ │ зад │ │ бок │ │детал│ │модел│
└─────┘ └─────┘ └─────┘ └─────┘ └─────┘
                    │
                    ▼ Склейка по горизонтали
    ┌─────────────────────────────────────┐
    │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐    │
    │  │ 1 │ │ 2 │ │ 3 │ │ 4 │ │ 5 │    │
    │  └───┘ └───┘ └───┘ └───┘ └───┘    │
    │            КОЛЛАЖ ~500KB-1MB       │
    └─────────────────────────────────────┘
                    │
                    ▼
            fal.ai try-on получает
            все ракурсы в одном файле
```

### Задачи

| Задача | Частота | Описание |
|--------|---------|----------|
| **process_new** | Каждые 15 мин | Обработать товары с image_status='uploaded' |
| **retry_failed** | Каждый час (:30) | Повторить неудачные (image_status='error') |
| **cleanup_temp** | Ежедневно 04:00 | Очистить /app/data |

### Docker Compose

```yaml
services:
  collage-worker:
    build: .
    container_name: collage-worker
    restart: unless-stopped
    env_file: .env
    volumes:
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

  celery-beat:
    build: .
    container_name: collage-beat
    restart: unless-stopped
    command: celery -A tasks beat --loglevel=info
    env_file: .env

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.8:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/collage/.env

STAGING_DB_URL=postgresql://collage:xxx@10.1.1.3:6432/unde_staging
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=xxx
S3_SECRET_KEY=xxx
S3_BUCKET=unde-images
REDIS_URL=redis://:xxx@10.1.0.4:6379/8
BATCH_SIZE=100
COLLAGE_MAX_WIDTH=2048
COLLAGE_QUALITY=85
```

### Процесс обработки

```python
def process_product(product_id: int):
    product = db.query("SELECT ... FROM raw_products WHERE id = ? AND image_status = 'uploaded'", product_id)
    
    # Скачать оригиналы из Object Storage
    images = [Image.open(s3.download(url)) for url in product.image_urls]
    
    # Склеить по горизонтали
    total_width = sum(img.width for img in images)
    max_height = max(img.height for img in images)
    collage = Image.new('RGB', (total_width, max_height), 'white')
    x = 0
    for img in images:
        collage.paste(img, (x, 0))
        x += img.width
    
    # Upload и обновить статус
    collage_key = f"collages/{product.brand}/{product.external_id}.jpg"
    s3.upload_file(collage, S3_BUCKET, collage_key)
    db.execute("UPDATE raw_products SET collage_url = ?, image_status = 'collage_ready' WHERE id = ?", ...)
```

---

## 6. STAGING DB SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | staging-db |
| **Private IP** | 10.1.1.3 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Изолированная база данных для сырых данных:
- Данные от Apify (метаданные товаров)
- Данные от Mobile API (наличие в магазинах)
- URLs фото в Object Storage
- Логи скраперов

### Схема базы данных

```sql
-- DATABASE: unde_staging

-- Сырые данные товаров
CREATE TABLE raw_products (
    id BIGSERIAL PRIMARY KEY,
    
    source VARCHAR(50) NOT NULL,
    external_id VARCHAR(100) NOT NULL,
    brand VARCHAR(50) NOT NULL,
    
    name TEXT,
    description TEXT,
    price DECIMAL(10,2),
    currency VARCHAR(10) DEFAULT 'KZT',
    category TEXT,
    colour VARCHAR(100),
    sizes JSONB,
    composition TEXT,
    
    original_image_urls JSONB,
    image_urls JSONB,
    collage_url TEXT,
    
    raw_data JSONB,
    scraped_at TIMESTAMPTZ NOT NULL,
    
    image_status VARCHAR(20) DEFAULT 'pending',
        -- pending → uploaded → collage_ready | error
    
    sync_status VARCHAR(20) DEFAULT 'pending',
        -- pending → synced | skipped | error
    
    ximilar_status VARCHAR(20) DEFAULT 'pending',
        -- pending → synced | error
    ximilar_synced_at TIMESTAMPTZ,
    
    synced_at TIMESTAMPTZ,
    error_message TEXT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(source, external_id)
);

-- Наличие в физических магазинах
CREATE TABLE raw_availability (
    id BIGSERIAL PRIMARY KEY,
    brand VARCHAR(50) NOT NULL,
    store_id INTEGER NOT NULL,
    product_id VARCHAR(100) NOT NULL,
    sizes_in_stock JSONB NOT NULL,
    fetched_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(brand, store_id, product_id, fetched_at::date)
);

-- Физические магазины Казахстана
CREATE TABLE raw_stores (
    id SERIAL PRIMARY KEY,
    brand VARCHAR(50) NOT NULL,
    store_id INTEGER NOT NULL,
    name TEXT,
    address TEXT,
    city VARCHAR(100) DEFAULT 'Almaty',
    country VARCHAR(10) DEFAULT 'KZ',
    mall_name TEXT,
    latitude DECIMAL(10,7),
    longitude DECIMAL(10,7),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(brand, store_id)
);

-- Логи скраперов
CREATE TABLE scraper_logs (
    id BIGSERIAL PRIMARY KEY,
    scraper_name VARCHAR(100) NOT NULL,
    run_id VARCHAR(100),
    status VARCHAR(20) NOT NULL,
    records_fetched INTEGER DEFAULT 0,
    records_new INTEGER DEFAULT 0,
    records_updated INTEGER DEFAULT 0,
    records_errors INTEGER DEFAULT 0,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    duration_seconds INTEGER,
    error_message TEXT,
    metadata JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ИНДЕКСЫ
CREATE INDEX idx_raw_products_brand ON raw_products(brand);
CREATE INDEX idx_raw_products_image_status ON raw_products(image_status);
CREATE INDEX idx_raw_products_sync_status ON raw_products(sync_status);
CREATE INDEX idx_raw_products_ximilar_status ON raw_products(ximilar_status);
CREATE INDEX idx_raw_products_external_id ON raw_products(external_id);
CREATE INDEX idx_raw_products_scraped_at ON raw_products(scraped_at);
CREATE INDEX idx_raw_availability_brand_store ON raw_availability(brand, store_id);
CREATE INDEX idx_raw_availability_product ON raw_availability(product_id);
CREATE INDEX idx_raw_availability_fetched ON raw_availability(fetched_at);
CREATE INDEX idx_scraper_logs_name ON scraper_logs(scraper_name);
CREATE INDEX idx_scraper_logs_started ON scraper_logs(started_at DESC);
```

### Конфигурация PostgreSQL

```ini
# /etc/postgresql/17/main/conf.d/staging.conf

shared_buffers = 1GB
effective_cache_size = 3GB
work_mem = 16MB
maintenance_work_mem = 256MB
listen_addresses = '127.0.0.1'
port = 5432
max_connections = 100
synchronous_commit = off
checkpoint_completion_target = 0.9
wal_level = minimal
max_wal_senders = 0
archive_mode = off
```

### Конфигурация PgBouncer

```ini
[databases]
unde_staging = host=127.0.0.1 port=5432 dbname=unde_staging

[pgbouncer]
listen_addr = 10.1.1.3
listen_port = 6432
auth_type = scram-sha-256
pool_mode = transaction
max_client_conn = 200
default_pool_size = 10
```

### Пользователи БД

| User | Доступ | Сервер |
|------|--------|--------|
| apify | READ/WRITE raw_products, scraper_logs | Apify Server |
| downloader | READ/WRITE raw_products (image_status, image_urls) | Photo Downloader |
| ximilar | READ/WRITE raw_products (ximilar_status) | Ximilar Sync Server |
| scraper | READ/WRITE all | Scraper Server |
| collage | READ/WRITE raw_products | Collage Server |

### Доступы

| Сервер | IP | Доступ |
|--------|-----|--------|
| Apify Server | 10.1.0.7 | ✅ |
| Photo Downloader | 10.1.0.13 | ✅ |
| Ximilar Sync | 10.1.0.14 | ✅ |
| Scraper Server | 10.1.0.3 | ✅ |
| Collage Server | 10.1.0.8 | ✅ |
| Production DB | 10.1.1.2 | ❌ |
| App Server | 10.1.0.2 | ❌ |

---

## 7. HETZNER OBJECT STORAGE

### Информация

| Параметр | Значение |
|----------|----------|
| **Bucket** | unde-images |
| **Endpoint** | https://hel1.your-objectstorage.com |
| **Region** | Helsinki (hel1) |

### Структура bucket

```
unde-images/
├── originals/
│   ├── zara/
│   │   ├── 495689099/
│   │   │   ├── 1.jpg  2.jpg  3.jpg  4.jpg  5.jpg
│   │   └── ...
│   ├── bershka/
│   ├── pullandbear/
│   ├── stradivarius/
│   ├── massimodutti/
│   └── oysho/
└── collages/
    ├── zara/
    │   ├── 495689099.jpg
    │   └── ...
    ├── bershka/
    └── ...
```

### URLs

```
Оригинал:  https://unde-images.hel1.your-objectstorage.com/originals/zara/495689099/1.jpg
Коллаж:    https://unde-images.hel1.your-objectstorage.com/collages/zara/495689099.jpg
```

### Расчёт объёма (MVP — KZ, Inditex)

| Бренд | Товаров | Оригиналы (5x300KB) | Коллажи (700KB) | Итого |
|-------|---------|---------------------|-----------------|-------|
| Zara | 15,000 | 22.5 GB | 10.5 GB | 33 GB |
| Bershka | 8,000 | 12 GB | 5.6 GB | 17.6 GB |
| Pull&Bear | 6,000 | 9 GB | 4.2 GB | 13.2 GB |
| Stradivarius | 8,000 | 12 GB | 5.6 GB | 17.6 GB |
| Massimo Dutti | 5,000 | 7.5 GB | 3.5 GB | 11 GB |
| Oysho | 5,000 | 7.5 GB | 3.5 GB | 11 GB |
| **Итого** | **47,000** | **70.5 GB** | **32.9 GB** | **~103 GB** |

### Object Storage доступы

| Bucket | GET (чтение) | PUT/DELETE (запись) | LIST (листинг) |
|--------|-------------|---------------------|----------------|
| **unde-images** (каталог) | Публичный | Только с Access Key | Отключен |
| **unde-user-media** (юзеры) | Только с Access Key (приватный) | Только с Access Key | Отключен |

### Bucket: unde-user-media (новый)

**Назначение:** хранение пользовательских медиа — фото юзера, результаты try-on, сохранённые образы. Приватный доступ (в отличие от каталожного bucket).

**Важно:** thumbnail (200px) генерируется на телефоне (Flutter) при upload. Оба файла (original + thumb) отправляются на сервер в одном запросе и кладутся в bucket. Ноль нагрузки на бэкенд для ресайза.

```
unde-user-media/
├── {user_id}/
│   ├── photos/
│   │   ├── {photo_id}/
│   │   │   ├── original.jpg    (~500KB-2MB)
│   │   │   └── thumb.jpg       (~10KB, 200px)
│   │   └── ...
│   ├── tryon/
│   │   ├── {tryon_id}/
│   │   │   ├── result.jpg      (~300KB-1MB)
│   │   │   └── thumb.jpg       (~10KB, 200px)
│   │   └── ...
│   └── saved/
│       ├── {outfit_id}/
│       │   ├── original.jpg
│       │   └── thumb.jpg
│       └── ...
```

### Расчёт объёма User Media (MVP)

| Данные | На юзера | 1K юзеров | 10K юзеров |
|--------|----------|-----------|------------|
| Фото (original + thumb) | ~10 MB | ~10 GB | ~100 GB |
| Try-on результаты | ~5 MB | ~5 GB | ~50 GB |
| Сохранённые образы | ~3 MB | ~3 GB | ~30 GB |
| **Итого** | **~18 MB** | **~18 GB** | **~180 GB** |

---

## 8. RECOGNITION ORCHESTRATOR (новый)

> **Задача:** юзер фотографирует outfit на улице → UNDE определяет каждую вещь → находит похожие SKU в каталоге ТЦ → показывает с ценой и магазином
>
> **Каталог:** готов. 5-7 фото/SKU парсятся с сайтов брендов, включая фото на моделях
>
> **Запуск:** 1 неделя (загрузка каталога в Ximilar + интеграция)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | recognition |
| **Private IP** | 10.1.0.9 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Координатор Fashion Recognition Pipeline:
- Принимает Celery task из Redis (от App Server)
- Вызывает Ximilar Gateway (10.1.0.15) и LLM Reranker (10.1.0.16) по HTTP
- Собирает результаты всех шагов
- Сохраняет лог в Production DB
- Отдаёт финальный результат

### Что НЕ делает

- ❌ Вызов внешних API напрямую (ни Ximilar, ни Gemini)
- ❌ Обработка изображений
- ❌ Тяжёлые вычисления

### Почему CPX11

Чистый оркестратор: принимает task, делает HTTP-запросы к двум внутренним серверам, собирает JSON, пишет в БД. Минимум CPU/RAM.

### Расположение в инфраструктуре

```
📱 Приложение: пользователь фотографирует outfit на улице
    │ 
    │ POST /api/v1/recognize (фото)
    ▼
┌─────────────────┐
│  App Server     │
│  (10.1.0.2)     │
│  API endpoint   │
└────────┬────────┘
         │ Celery task → Redis (10.1.0.4:6379/6)
         ▼
┌─────────────────┐         ┌───────────────────────────────┐
│  Push Server    │         │  RECOGNITION ORCHESTRATOR     │
│  10.1.0.4       │◄───────►│  10.1.0.9                     │
│  Redis Broker   │         │                               │
└─────────────────┘         │  2 Celery workers (I/O bound) │
                            └──┬─────────────────────┬──────┘
                               │                     │
                               ▼                     ▼
                    ┌─────────────────┐   ┌─────────────────┐
                    │ XIMILAR GATEWAY │   │ LLM RERANKER    │
                    │ 10.1.0.15       │   │ 10.1.0.16       │
                    │                 │   │                  │
                    │ HTTP :8001      │   │ HTTP :8002       │
                    │ • detect        │   │ • tag_context    │
                    │ • tag           │   │ • visual_rerank  │
                    │ • search        │   │                  │
                    └────────┬────────┘   └────────┬─────────┘
                             │                     │
                             ▼                     ▼
                     ┌──────────────┐       ┌──────────────┐
                     │ Ximilar API  │       │ Gemini API   │
                     │ (external)   │       │ (external)   │
                     └──────────────┘       └──────────────┘
                                    │
                                    ▼
                           ┌──────────────────┐
                           │  Production DB   │
                           │  10.1.1.2        │
                           │ • products (SKU) │
                           │ • recognition_   │
                           │   requests (лог) │
                           └──────────────────┘
```

### Pipeline: 4 шага обработки фото

```
Step 1: DETECTION & CROP → Ximilar Gateway
  Сервис: Ximilar Fashion Detection API
  Качество: 9.5/10. Специализирован на fashion. Отличает кардиган
    от жилетки, crop-top от обычного, шарф от палантина.
    Street-фото, углы, перекрытия — всё работает.
  Вход: street-фото
  Выход: bounding boxes + готовые crops каждой вещи + категория
    (top, bottom, shoes, bag, accessory...)
  Стоимость: входит в тариф Ximilar Business.
    Detection + Tagging + Search — всё в одних кредитах.
  Latency: 200-500ms
         │
         ▼
Step 2: TAGGING & DESCRIPTION → Ximilar Gateway + LLM Reranker (параллельно)
  Сервис 1: Ximilar Fashion Tagging (входит в тарифные кредиты — бесплатно)
    Что даёт: точные атрибуты: Pantone-уровень цвета (не 'зелёный'
      а 'хаки #BDB76B'), точный материал (нейлон ripstop vs полиэстер
      vs хлопок), принт (leopard vs camo vs stripe). 100+ обученных
      fashion tasks.
  Сервис 2: Gemini 2.5 Flash (vision)
    Что даёт: контекст, который Ximilar не умеет: стиль (streetwear
      vs preppy vs minimalist), occasion (office, date, casual),
      brand_style (oversized, cropped, fitted), сезон. Требует
      'понимания', а не классификации.
  Зачем два: 1) Pre-filter перед search (отсеять чёрные куртки если
    ищем хаки). 2) Усиливает visual rerank. 3) Формирует ответ юзеру.
    Combined: 9.5/10.
  Combined output: {type: "bomber_jacket", color: "khaki #BDB76B",
    material: "nylon ripstop", pattern: "solid",
    style: "streetwear", occasion: "casual/urban",
    brand_style: "oversized drop-shoulder", season: "autumn"}
  Стоимость: Ximilar: в тарифе. Gemini: отдельно.
         │
         ▼
Step 3: VISUAL SEARCH → Ximilar Gateway
  Сервис: Ximilar Fashion Search (Custom Collection)
  Качество: 9-9.5/10. Fashion-специализированный visual search.
    С on-model каталогом: матчит куртку на прохожей с курткой на
    модели из Zara. Pantone цвета, фактуры, силуэты.
  Каталог: загружаем ВСЕ 5-7 фото каждого SKU в Ximilar Collection
    с метаданными (SKU ID, бренд, цена, магазин, этаж). Ximilar
    индексирует все ракурсы и матчит по лучшему автоматически.
  Вход: crop каждой вещи → поиск по Ximilar Collection
  Выход: TOP-10 SKU с confidence score + метаданные (цена, магазин,
    наличие) для каждого
  Стоимость: входит в те же кредиты Ximilar Business.
    Detection + Tagging + Search = один тариф.
  Latency: 200-500ms на запрос
         │
         ▼
Step 4: VISUAL RERANK & RESPONSE → LLM Reranker
  Сервис: Gemini 2.5 Flash (vision) — visual rerank
  Как работает:
    1) TOP-10 кандидатов из Step 3
    2) Pre-filter по атрибутам из Step 2 (тип, цвет ±, стиль)
    3) VISUAL RERANK: Gemini получает 2 фото:
       [crop с улицы] + [лучшее фото SKU на модели из каталога]
       "Это одна и та же вещь? Сравни силуэт, цвет, фактуру, детали.
       Score 0-1."
    4) Combined score = 0.7 × visual + 0.3 × semantic → финальный ранк
  Latency: 1-2 сек на все 10 кандидатов (batch). Параллельные вызовы.
```

### Fallback: когда точного SKU нет в каталоге

Visual search ВСЕГДА возвращает TOP-N. Вопрос — насколько они похожи. Три уровня:

```
> 0.85   ✅ "Нашли! Это [SKU] в [магазин], [этаж]"
         Точный или почти точный матч.
         Фото + цена + кнопка "Где купить".

0.5-0.85 🔍 "Похожие варианты"
         Визуально близкие SKU. Тот же тип, похожий стиль,
         другой бренд/модель. Показываем TOP-3-5 с % сходства.

< 0.5    🎨 "В похожем стиле"
         Визуальный матч слабый. ATTRIBUTE FALLBACK: ищем в каталоге
         по атрибутам из Step 2 (type: bomber + color: khaki +
         style: streetwear). SQL-запрос по метаданным, не нужен
         отдельный сервис.

Принцип: юзер ВСЕГДА получает результат. Даже если точного совпадения
нет — показываем лучшее что есть. Юзер пришёл за решением, а не за
сообщением "не найдено".
```

### UX: Progressive Loading

```
0 сек     Фото загружается       → Анимация сканирования (пульсирующие линии)
0.5 сек   Detection результат    → Chips на фото: "бомбер", "джинсы", "кроссовки". Ximilar ответил.
1-2 сек   Skeleton cards         → "Ищем похожие..." shimmer-карточки пока идёт search + rerank
2-4 сек   Результаты             → Карточки SKU появляются. Фото + цена + магазин + confidence badge.

Суммарная latency: 2-4 сек (Ximilar 0.5s + Gemini tag 1s + Ximilar search 0.5s + Gemini rerank 1-2s).
Detection показывается мгновенно.
```

### Docker Compose

```yaml
# /opt/unde/recognition/docker-compose.yml

services:
  recognition-orchestrator:
    build: .
    container_name: recognition-orchestrator
    restart: unless-stopped
    env_file: .env
    command: celery -A app.celery_app worker -Q recognition_queue -c 2 --max-tasks-per-child=200
    deploy:
      resources:
        limits:
          memory: 1G

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.9:9100:9100"
```

**2 concurrent workers:** оркестратор только ждёт HTTP-ответов от Ximilar Gateway и LLM Reranker. Минимум CPU.

### Celery Task

`recognize_photo` координирует 4 шага через HTTP-вызовы к внутренним серверам. Промежуточные данные (кропы, теги, кандидаты) — это URL'ы и JSON, проходят через оркестратор.

```python
@celery_app.task(queue='recognition_queue', time_limit=30, soft_time_limit=25)
def recognize_photo(photo_url: str, user_id: str = None) -> dict:
    request_id = uuid4()
    t_start = time.time()
    
    # Step 1: Detection & Crop → Ximilar Gateway
    detected_items = ximilar_gw.detect(photo_url)
    
    # Step 2: Tagging (Ximilar GW + LLM Reranker параллельно)
    tags = []
    for item in detected_items:
        ximilar_tags, llm_tags = parallel(
            ximilar_gw.tag(item["crop_url"]),
            llm_reranker.tag_context(item["crop_url"])
        )
        tags.append({**ximilar_tags, **llm_tags})
    
    # Step 3: Visual Search → Ximilar Gateway
    search_results = []
    for i, item in enumerate(detected_items):
        candidates = ximilar_gw.search(
            crop_url=item["crop_url"],
            category=tags[i].get("type"),
            top_k=10
        )
        search_results.append(candidates)
    
    # Step 4: Visual Rerank → LLM Reranker
    final_matches = []
    for i, candidates in enumerate(search_results):
        ranked = llm_reranker.visual_rerank(
            crop_url=detected_items[i]["crop_url"],
            candidates=candidates[:10],
            tags=tags[i]
        )
        
        # Fallback по confidence (docx spec)
        top_score = ranked[0]["score"] if ranked else 0
        if top_score > 0.85:
            # ✅ Точный матч: "Нашли! Это [SKU] в [магазин], [этаж]"
            ranked = [{"match_type": "exact", **r} for r in ranked[:1]]
        elif top_score >= 0.5:
            # 🔍 Похожие: тот же тип, похожий стиль, другой бренд/модель
            ranked = [{"match_type": "similar", **r} for r in ranked[:5]]
        else:
            # 🎨 Attribute fallback: SQL-запрос по метаданным из Step 2
            ranked = attribute_fallback(tags[i])
            ranked = [{"match_type": "style", **r} for r in ranked]
        
        final_matches.append(ranked)
    
    total_ms = int((time.time() - t_start) * 1000)
    
    # Сохранить в Production DB
    save_recognition_request(request_id, user_id, photo_url,
        detected_items, tags, search_results, final_matches, total_ms)
    
    # Принцип: юзер ВСЕГДА получает результат. Даже если точного
    # совпадения нет — показываем лучшее что есть.
    return {
        "request_id": str(request_id),
        "items": format_response(detected_items, tags, final_matches),
        "total_ms": total_ms
    }


# HTTP клиенты для внутренних серверов
class XimilarGW:
    BASE = "http://10.1.0.15:8001"
    def detect(self, url): return post(f"{self.BASE}/detect", json={"url": url})
    def tag(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def search(self, **kw): return post(f"{self.BASE}/search", json=kw)

class LLMReranker:
    BASE = "http://10.1.0.16:8002"
    def tag_context(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def visual_rerank(self, **kw): return post(f"{self.BASE}/rerank", json=kw)
```

### Environment Variables

```bash
# /opt/unde/recognition/.env

# Внутренние серверы (private network)
XIMILAR_GW_URL=http://10.1.0.15:8001
LLM_RERANKER_URL=http://10.1.0.16:8002

# Celery (Redis на Push Server)
REDIS_PASSWORD=xxx
CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/6
CELERY_RESULT_BACKEND=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/6

# Production DB (SKU метаданные + логи)
DATABASE_URL=postgresql://undeuser:xxx@10.1.1.2:6432/unde_main

# Thresholds
CONFIDENCE_HIGH=0.85
CONFIDENCE_MEDIUM=0.50
```

### Структура директорий

```
/opt/unde/recognition/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py
│   ├── tasks.py                # recognize_photo orchestration
│   ├── clients/
│   │   ├── ximilar_gw.py      # HTTP client → 10.1.0.15
│   │   └── llm_reranker.py    # HTTP client → 10.1.0.16
│   ├── db.py
│   └── utils.py
├── scripts/
│   ├── health-check.sh
│   └── test-recognize.sh
└── deploy/
    ├── recognition.service
    └── init-db.sql             # Таблица recognition_requests
```

### Таблица в Production DB

```sql
-- На Production DB (10.1.1.2)

CREATE TABLE recognition_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    photo_url TEXT NOT NULL,
    
    -- Step 1: Detection (Ximilar Gateway)
    detected_items JSONB,
    detection_time_ms INTEGER,
    
    -- Step 2: Tagging (Ximilar Gateway + LLM Reranker)
    tags JSONB,
    tagging_time_ms INTEGER,
    
    -- Step 3: Visual Search (Ximilar Gateway)
    search_results JSONB,
    search_time_ms INTEGER,
    
    -- Step 4: Visual Rerank (LLM Reranker)
    final_matches JSONB,
    rerank_time_ms INTEGER,
    
    -- Totals
    total_time_ms INTEGER,
    items_detected INTEGER,
    items_matched INTEGER,
    
    user_feedback JSONB,
    
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_recognition_user ON recognition_requests(user_id);
CREATE INDEX idx_recognition_created ON recognition_requests(created_at DESC);
```

### Связь с каталогом (Ximilar Sync Server)

Recognition Pipeline зависит от актуальности каталога в Ximilar Collection:
- **Ximilar Sync Server (10.1.0.14)** выполняет `ximilar_sync` еженедельно после сбора каталога
- Новые/обновлённые SKU с фото автоматически загружаются в Ximilar Collection
- Ximilar Gateway использует ту же Collection для Visual Search (Step 3)

---

## 9. XIMILAR GATEWAY (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | ximilar-gw |
| **Private IP** | 10.1.0.15 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Единая точка для всех вызовов Ximilar API (всё в одном тарифе Ximilar Business):
- **POST /detect** — Fashion Detection: bounding boxes + готовые crops + категория. Качество 9.5/10. Специализирован на fashion — отличает кардиган от жилетки, crop-top от обычного, шарф от палантина. Street-фото, углы, перекрытия — всё работает.
- **POST /tag** — Fashion Tagging: Pantone-уровень цвета (не 'зелёный' а 'хаки #BDB76B'), точный материал (нейлон ripstop vs полиэстер vs хлопок), принт (leopard vs camo vs stripe). 100+ обученных fashion tasks. Входит в тарифные кредиты.
- **POST /search** — Fashion Search по Ximilar Collection: TOP-N похожих SKU. Качество 9-9.5/10 с on-model каталогом. Матчит куртку на прохожей с курткой на модели из Zara. Входит в те же кредиты.

### Почему отдельный сервер

- **Один внешний API:** все вызовы к Ximilar изолированы. Ximilar упал → проблема локализована, Gemini продолжает работать
- **Единый rate limiting:** Ximilar имеет свои лимиты — одна точка управления
- **Один API-ключ:** безопасность — ключ Ximilar только на этом сервере
- **Мониторинг:** latency, ошибки, rate limits Ximilar отслеживаются отдельно

### Почему CPX21

Detection + Search возвращают изображения (crop URL'ы). Сервер обрабатывает JSON и пересылает — I/O bound, но с некоторым объёмом данных в памяти (10 кандидатов × 5-7 фото каждый).

### HTTP API

```
POST /detect
  Body: {"url": "https://...photo.jpg"}
  Response: {"items": [{"crop_url": "...", "bbox": [...], "category": "jacket", "confidence": 0.94}]}
  Latency: 200-500ms

POST /tag
  Body: {"url": "https://...crop.jpg"}
  Response: {"type": "bomber_jacket", "color": "khaki", "color_hex": "#BDB76B",
    "material": "nylon ripstop", "pattern": "solid"}
  Latency: 200-400ms

POST /search
  Body: {"crop_url": "...", "category": "jacket", "top_k": 10}
  Response: {"candidates": [{"sku_id": "...", "score": 0.87, "image_urls": [...],
    "metadata": {"brand": "...", "price": ..., "store": "...", "floor": "..."}}]}
  Каталог: все 5-7 фото/SKU загружены с метаданными (SKU ID, бренд, цена, магазин, этаж).
    Ximilar индексирует все ракурсы и матчит по лучшему автоматически.
  Latency: 200-500ms
```

### Docker Compose

```yaml
services:
  ximilar-gw:
    build: .
    container_name: ximilar-gw
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.15:8001:8001"
    deploy:
      resources:
        limits:
          memory: 2G

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.15:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/ximilar-gw/.env

# Ximilar
XIMILAR_API_TOKEN=xxx
XIMILAR_COLLECTION_ID=xxx

# Server
HOST=0.0.0.0
PORT=8001
WORKERS=4
```

### Структура директорий

```
/opt/unde/ximilar-gw/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── main.py               # FastAPI app
│   ├── routes/
│   │   ├── detect.py          # POST /detect
│   │   ├── tag.py             # POST /tag
│   │   └── search.py          # POST /search
│   ├── ximilar_client.py      # Обёртка над Ximilar SDK
│   └── rate_limiter.py        # Rate limiting для Ximilar API
├── scripts/
│   ├── health-check.sh
│   └── test-detect.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 10. LLM RERANKER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | llm-reranker |
| **Private IP** | 10.1.0.16 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Единая точка для всех LLM-вызовов в Recognition Pipeline:
- **POST /tag** — контекстный тегинг через Gemini 2.5 Flash (vision): стиль (streetwear vs preppy vs minimalist), occasion (office, date, casual), brand_style (oversized, cropped, fitted), сезон. Контекст, который Ximilar не умеет — требует 'понимания', а не классификации.
- **POST /rerank** — визуальный реранкинг через Gemini 2.5 Flash (vision): получает 2 фото [crop с улицы] + [лучшее фото SKU на модели из каталога], сравнивает силуэт, цвет, фактуру, детали. Score 0-1. Combined score = 0.7 × visual + 0.3 × semantic.

### Почему отдельный сервер

- **Другой провайдер:** Gemini API — другие rate limits, другое downtime, другие ключи
- **Другая стоимость:** LLM-вызовы дороже Ximilar — отдельный мониторинг расходов
- **Изоляция отказов:** Gemini недоступен → Detection + Search продолжают работать, Orchestrator отдаёт результаты без реранкинга

### Почему CPX11

Сервер отправляет JSON/URL в Gemini API и ждёт ответ. Чистый I/O. Минимум CPU/RAM.

### HTTP API

```
POST /tag
  Body: {"url": "https://...crop.jpg"}
  Response: {"style": "streetwear", "occasion": "casual/urban",
    "brand_style": "oversized drop-shoulder", "season": "autumn"}
  Latency: ~1000ms

POST /rerank
  Body: {"crop_url": "...", "candidates": [...], "tags": {...}}
  Gemini получает: [crop с улицы] + [лучшее фото SKU на модели из каталога]
  Prompt: "Это одна и та же вещь? Сравни силуэт, цвет, фактуру, детали. Score 0-1."
  Response: {"ranked": [{"sku_id": "...", "score": 0.91, "reason": "..."}, ...]}
  Combined score = 0.7 × visual + 0.3 × semantic → финальный ранк
  Latency: 1-2 сек на все 10 кандидатов (batch, параллельные вызовы)
```

### Docker Compose

```yaml
services:
  llm-reranker:
    build: .
    container_name: llm-reranker
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.16:8002:8002"
    deploy:
      resources:
        limits:
          memory: 1G

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.16:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/llm-reranker/.env

# Gemini
GEMINI_API_KEY=xxx

# Server
HOST=0.0.0.0
PORT=8002
WORKERS=2
```

### Структура директорий

```
/opt/unde/llm-reranker/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── main.py               # FastAPI app
│   ├── routes/
│   │   ├── tag.py             # POST /tag (Gemini context tagging)
│   │   └── rerank.py          # POST /rerank (Gemini visual rerank)
│   ├── clients/
│   │   └── gemini_client.py
│   └── prompts/
│       ├── tag_prompt.py
│       └── rerank_prompt.py
├── scripts/
│   ├── health-check.sh
│   └── test-rerank.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 11. MOOD AGENT SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | mood-agent |
| **Private IP** | 10.1.0.11 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Эмоциональный регулятор диалога — «датчик состояния» разговора:
- Анализ эмоционального тона каждого сообщения пользователя (настроение, напряжение, фрустрация, срочность, уверенность)
- Сглаживание настроения (инерция) — аватар не «дёргается» при резких spike'ах
- Детекция резких разворотов (смена темы, эмоциональный разворот, «разрыв нити»)
- Выдача управляющих параметров для главной модели (стиль ответа) и для Rive-аватара (анимация)
- Выдача параметров для Voice Server (темп, теплота → ElevenLabs Expressive Mode)

### Почему CPX11

Mood Agent — это лёгкий классификатор, не generative LLM. Задача: принять текст (или частичный ASR), вернуть маленький JSON за миллисекунды. CPU и RAM минимальны. Если в будущем понадобится fine-tuned модель — масштабируется вертикально без смены архитектуры.

### Расположение в инфраструктуре

```
📱 Пользователь говорит / пишет
    │
    ▼
┌─────────────────┐
│  App Server     │
│  (10.1.0.2)     │
│  API endpoint   │
└────────┬────────┘
         │
         │  ПАРАЛЛЕЛЬНЫЙ запуск (не последовательный!)
         │
    ┌────┴──────────────────────────────────┐
    │                                       │
    ▼                                       ▼
┌───────────────────┐            ┌─────────────────────────┐
│  MOOD AGENT       │            │  LLM Orchestrator       │
│  10.1.0.11        │            │  (главная модель)       │
│                   │            │                         │
│  Вход:            │            │  Ожидает ContextPack    │
│  • текст/ASR      │            │  с параметрами от       │
│  • предыдущее     │            │  Mood Agent             │
│    состояние      │            │                         │
│                   │            └────────────┬────────────┘
│  Выход:           │                         │
│  mood_frame JSON  │                         ▼
│  (~50-200ms)      │─── mood_frame ──► ContextPack
└───────┬───────────┘                         │
        │                                     │
        │  mood_frame также идёт в:           ▼
        │                              ┌─────────────┐
        ├──────────────────────────────►│ VOICE SERVER│
        │  tempo, warmth, tension      │ 10.1.0.12   │
        │  → ElevenLabs Expressive     │ ElevenLabs  │
        │                              └─────────────┘
        │
        └──────────────────────────────► Rive Avatar
           warmth → мимика
           tension → поза
           topic_shift → жест переключения
```

### Формат mood_frame JSON

```json
{
  "mood_frame_id": "uuid",
  "timestamp": "2026-02-13T14:30:00Z",

  "emotion": {
    "valence": 0.6,
    "arousal": 0.4,
    "dominance": 0.5
  },

  "signals": {
    "frustration": 0.1,
    "urgency": 0.3,
    "confidence": 0.7,
    "fatigue": 0.2
  },

  "smoothed_baseline": {
    "valence": 0.55,
    "arousal": 0.35
  },

  "topic": {
    "shift_detected": false,
    "emotional_reversal": false,
    "thread_break": false,
    "action": "continue"
  },

  "style_params": {
    "warmth": 0.7,
    "tempo": "normal",
    "response_length": "medium",
    "ask_clarification": false,
    "defuse_first": false
  },

  "rive_params": {
    "warmth": 0.7,
    "tension": 0.2,
    "tempo": 1.0,
    "gesture": null
  },

  "voice_params": {
    "warmth": 0.7,
    "tempo": 1.0,
    "tension": 0.2,
    "expressiveness": "moderate"
  }
}
```

### Что Mood Agent НЕ делает

- ❌ Не пишет ответы пользователю
- ❌ Не принимает продуктовые решения
- ❌ Не сохраняет «память» как факты (это другой слой — Memory Agent)
- ❌ Не «играет психолога»
- Он — регулятор: как ABS/ESP в машине. Невидим, но делает езду гладкой.

### Docker Compose

```yaml
# /opt/unde/mood-agent/docker-compose.yml

services:
  mood-agent:
    build: .
    container_name: mood-agent
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.11:8080:8080"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.11:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/mood-agent/.env

# LLM для классификации (лёгкая модель, Haiku-класс)
MOOD_LLM_PROVIDER=deepseek
MOOD_LLM_MODEL=deepseek-chat
MOOD_LLM_API_KEY=xxx

# Fallback
MOOD_FALLBACK_PROVIDER=gemini
MOOD_FALLBACK_MODEL=gemini-2.0-flash-lite
MOOD_FALLBACK_API_KEY=xxx

# Server
MOOD_PORT=8080
MOOD_WORKERS=4

# Smoothing
MOOD_SMOOTHING_FACTOR=0.3
MOOD_SPIKE_THRESHOLD=0.5

# Redis (для кеширования предыдущего состояния)
REDIS_URL=redis://:xxx@10.1.0.4:6379/9
```

### API Endpoint

```
POST http://10.1.0.11:8080/analyze

Request:
{
  "user_id": "uuid",
  "text": "текст сообщения или partial ASR",
  "previous_mood_frame_id": "uuid или null"
}

Response:
{
  "mood_frame": { ... }  // см. формат выше
}

Latency target: < 200ms (p95)
```

### Структура директорий

```
/opt/unde/mood-agent/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── server.py              # FastAPI / uvicorn
│   ├── analyzer.py            # Основная логика анализа
│   ├── smoothing.py           # Инерция настроения, spike detection
│   ├── models.py              # Pydantic: MoodFrame, StyleParams, RiveParams
│   ├── clients/
│   │   ├── deepseek_client.py
│   │   └── gemini_client.py
│   └── prompts/
│       └── mood_system.txt    # System prompt для классификатора
├── scripts/
│   ├── health-check.sh
│   └── test-mood.sh
└── deploy/
    ├── netplan-private.yaml
    └── mood-agent.service
```

---

## 12. VOICE SERVER (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | voice |
| **Private IP** | 10.1.0.12 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Управление голосовым выводом UNDE-аватара:
- Проксирование вызовов к ElevenLabs Conversational TTS v3 (Expressive Mode)
- Приём текста от LLM Orchestrator + voice_params от Persona Agent (10.1.0.21) → синтез речи с правильной интонацией
- **Примечание:** voice_params формируются Persona Agent (а не Mood Agent напрямую). Persona Agent получает mood_frame и на его основе выбирает voice preset (6 пресетов: friendly_upbeat, friendly_warm, soft_calm, soft_empathetic, neutral_confident, energetic_happy)
- Стриминг аудио (chunked) в приложение через WebSocket
- Кеширование часто используемых фраз (приветствия, подтверждения)
- Логирование latency

### Почему CPX21

Voice Server — I/O bound: отправляет текст в ElevenLabs, стримит аудио обратно. CPU не нагружен. RAM нужен для буферизации аудио-стримов при нескольких одновременных пользователях. 4 GB достаточно для MVP.

### Почему отдельный сервер (а не контейнер на App Server)

- **Изоляция отладки:** проблемы с голосом не аффектят API каталога/рекомендаций
- **Масштабируемость:** при росте пользователей — горизонтальное масштабирование voice отдельно
- **WebSocket:** долгоживущие соединения для стриминга аудио — отдельная нагрузка от REST API
- **Принцип 1 сервер = 1 задача**

### Расположение в инфраструктуре

```
┌─────────────────┐
│  LLM            │  Сгенерированный текст ответа
│  Orchestrator   │
└────────┬────────┘
         │
         │  + voice_params от Mood Agent (10.1.0.11)
         ▼
┌────────────────────────────────────────────────────┐
│  VOICE SERVER (10.1.0.12)                          │
│                                                    │
│  1. Принять текст + voice_params (от Persona Agent) │
│  2. Маппинг voice_params → ElevenLabs settings:    │
│     warmth → stability, similarity_boost           │
│     tempo → speed                                  │
│     tension → style (authoritative/calm)           │
│     expressiveness → Expressive Mode context       │
│  3. POST → ElevenLabs TTS v3 (streaming)           │
│  4. Stream аудио chunks → App через WebSocket      │
│                                                    │
│  Cache: приветствия, подтверждения (Redis)          │
└────────┬───────────────────────────────────────────┘
         │ WebSocket (audio chunks)
         ▼
┌──────────────────┐
│ 📱 Приложение    │
│   • Аудио        │
│   • Lip sync     │
│     (Rive)       │
└──────────────────┘
```

### Интеграция с ElevenLabs Expressive Mode

```python
# Маппинг voice_params → ElevenLabs API

def map_voice_params(voice_params: dict) -> dict:
    """Конвертация mood_frame.voice_params в ElevenLabs settings."""
    return {
        "model_id": "eleven_v3_conversational",  # Expressive Mode
        "voice_settings": {
            "stability": 0.4 + (voice_params["warmth"] * 0.3),
            "similarity_boost": 0.7,
            "style": min(1.0, voice_params["tension"] + 0.3),
            "use_speaker_boost": True,
            "speed": voice_params["tempo"]
        },
        # Expressive Mode: контекст диалога для адаптации интонации
        "previous_text": "...",  # предыдущая фраза аватара
        "next_text": "..."       # начало следующей фразы (если known)
    }
```

### Docker Compose

```yaml
# /opt/unde/voice/docker-compose.yml

services:
  voice-server:
    build: .
    container_name: voice-server
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.12:8080:8080"
      - "10.1.0.12:8081:8081"   # WebSocket для audio streaming
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.12:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/voice/.env

# ElevenLabs
ELEVENLABS_API_KEY=xxx
ELEVENLABS_VOICE_ID=xxx
ELEVENLABS_MODEL=eleven_v3_conversational

# Server
VOICE_HTTP_PORT=8080
VOICE_WS_PORT=8081
VOICE_WORKERS=4

# Redis (кеш фраз + буфер)
REDIS_URL=redis://:xxx@10.1.0.4:6379/10

# Audio
AUDIO_FORMAT=mp3_44100_128
AUDIO_CHUNK_SIZE=4096
STREAM_BUFFER_MS=100

# Timeouts
ELEVENLABS_TIMEOUT=5
```

### API Endpoints

```
# Синхронный TTS (короткие фразы, кешируемые)
POST http://10.1.0.12:8080/synthesize
Request:
{
  "text": "Привет! Рада тебя видеть!",
  "voice_params": { "warmth": 0.8, "tempo": 1.0, "tension": 0.1, "expressiveness": "warm" },
  "cache_key": "greeting_default"  // опционально
}
Response: audio/mpeg binary

# Streaming TTS (основной режим для длинных ответов)
WebSocket ws://10.1.0.12:8081/stream
Message:
{
  "text": "Я нашла для тебя отличный образ...",
  "voice_params": { ... },
  "previous_text": "предыдущая фраза аватара",  // для Expressive Mode контекста
  "stream": true
}
Response: binary audio chunks
```

### Структура директорий

```
/opt/unde/voice/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── server.py              # FastAPI + WebSocket (uvicorn)
│   ├── tts.py                 # ElevenLabs client, streaming logic
│   ├── voice_mapping.py       # voice_params → ElevenLabs settings
│   ├── cache.py               # Redis: кеш часто используемых фраз
│   └── models.py              # Pydantic: SynthesizeRequest, VoiceParams
├── scripts/
│   ├── health-check.sh
│   └── test-voice.sh
└── deploy/
    ├── netplan-private.yaml
    └── voice.service
```

---

## 13. LLM ORCHESTRATOR (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | llm-orchestrator |
| **Private IP** | 10.1.0.17 |
| **Тип** | Hetzner CPX21 |
| **vCPU** | 3 |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Генерация ответов аватара-консультанта — «мозг» диалога UNDE:
- Сборка ContextPack из **трёх слоёв знания**:
  - **A. User Knowledge** (факты) — из Dubai Shard (User Knowledge, AES-256)
  - **B. Semantic Retrieval** (эпизоды) — Hybrid Search (vector + FTS) по Chat History с pgvector, тематический temporal decay, confidence-adjusted λ, precomputed memory_snippets
  - **C. Context Agent** (мир вокруг) — context_frame от Context Agent (10.1.0.19): геолокация, погода, культура, события
  - **+ mood_frame** от Mood Agent (10.1.0.11)
  - **+ persona_directive** от Persona Agent (10.1.0.21) — характер, тон, стиль, hard bans
  - **+ последние 10 сообщений** (поток диалога)
  - **+ Referenced Artifact** (если reply_to_id — реакция на артефакт)
  - **+ контекст каталога** из Production DB
- **Persona Agent client** (10.1.0.21): POST /persona (~15ms, параллельно с embedding) → persona_directive (system prompt), voice_params (→ Voice Server), avatar_state + render_hints (→ App)
- **Embedding client** (Cohere / выбранный по eval): embed запрос → vector (~50ms), embed сообщения при ingestion (async)
- Вызов основной LLM (DeepSeek / Gemini / Claude / Qwen) с полным контекстом
- **Генерация response_description** для артефактов консультанта (template-based, sync ~0.1ms)
- **Определение reply_to_id** для user-сообщений (серверная эвристика: последний артефакт за 10 мин; если 2+ артефакта за <60 сек — не ставить, LLM уточнит)
- Маршрутизация запросов к Intelistyle (fashion), Recognition Pipeline (распознавание)
- Передача сгенерированного текста + voice_params (от Persona Agent) в Voice Server для синтеза речи
- Передача avatar_state + render_hints (от Persona Agent) в App для анимации Rive-аватара
- Сохранение сообщений (user + assistant) в Chat History на Dubai Shard
- **ASYNC после ответа:** detect_behavioral_signals() → POST /persona/feedback (signal_id + exchange_id) → POST /persona/flush (exchange_id) — обратная связь для адаптации persona profile
- **Emotional filter** — mood_frame → exclude болезненные воспоминания
- **Memory Density Cap** — ≤3 episodes per response, ≤30% density в последних 10 ответах

### Что НЕ делает

- ❌ Recognition pipeline (это Recognition Orchestrator, 10.1.0.9)
- ❌ Эмоциональный анализ (это Mood Agent, 10.1.0.11)
- ❌ Синтез речи (это Voice Server, 10.1.0.12)
- ❌ Контекст реального мира (это Context Agent, 10.1.0.19)
- ❌ Fashion-рекомендации напрямую (это Intelistyle API, вызывается через структурированный запрос)
- ❌ Реранкинг/тегинг товаров (это LLM Reranker, 10.1.0.16)

### Почему CPX21

I/O bound: основная работа — собрать контекст из нескольких БД/сервисов, отправить в LLM API, дождаться ответа, распределить результат. CPU не нагружен. 4 GB RAM достаточно для буферизации контекста нескольких одновременных пользователей на MVP.

### Почему отдельный сервер (а не контейнер на App Server)

- **Принцип 1 сервер = 1 задача:** App Server — HTTP API + Nginx + Prometheus. LLM Orchestrator — диалоговая логика.
- **Разная нагрузка:** App Server обрабатывает быстрые REST-запросы (каталог, навигация). LLM Orchestrator — долгие запросы к LLM API (2-10 сек).
- **Изоляция отказов:** LLM API недоступен → каталог и навигация продолжают работать.
- **Масштабирование:** при росте пользователей — горизонтальное масштабирование диалоговой системы отдельно от API.
- **Мониторинг расходов:** LLM-вызовы — основная статья расходов. Отдельный сервер = отдельный мониторинг стоимости.

### Расположение в инфраструктуре

```
📱 Пользователь говорит / пишет
    │
    ▼
┌─────────────────┐
│  App Server     │
│  (10.1.0.2)     │
│  API endpoint   │
└────────┬────────┘
         │ Celery task → Redis (10.1.0.4:6379/11)
         │
         │  ПАРАЛЛЕЛЬНЫЙ запуск:
    ┌────┴──────────────────────────────────┐
    │                                       │
    ▼                                       ▼
┌───────────────────┐            ┌──────────────────────────────────┐
│  MOOD AGENT       │            │  LLM ORCHESTRATOR                │
│  10.1.0.11        │            │  10.1.0.17                       │
│                   │            │                                  │
│  mood_frame       │            │  Ожидает mood_frame, затем:      │
│  (~50-200ms)      │────────────│  1. Собрать ContextPack          │
└───────────────────┘            │  2. Вызвать LLM API              │
                                 │  3. Получить ответ               │
                                 │  4. → Voice Server (текст)       │
                                 │  5. → Chat History DB (сохранить)│
                                 └──┬───────────────┬───────────────┘
                                    │               │
              ┌─────────────────────┤               │
              │                     │               │
              ▼                     ▼               ▼
┌───────────────────┐  ┌───────────────┐  ┌──────────────────┐
│  VOICE SERVER     │  │ Dubai Shard   │  │ Dubai Shard      │
│  10.1.0.12        │  │ Chat History  │  │ User Knowledge   │
│  Текст → TTS      │  │ Сохранить msg │  │ Профиль юзера    │
│  → 📱 аудио       │  └───────────────┘  └──────────────────┘
└───────────────────┘
```

### ContextPack: три слоя знания + контекст

```
📱 "Хочу пойти в кино сегодня"
    │
    ▼
App Server (10.1.0.2)
    │
    ├──────────── ПАРАЛЛЕЛЬНО ────────────┐
    │                                      │
    ▼                                      ▼
┌──────────────┐              ┌────────────────────┐
│ MOOD AGENT   │              │ CONTEXT AGENT      │
│ (10.1.0.11)  │              │ (10.1.0.19)        │
│              │              │                    │
│ Анализ тона  │              │ GPS → mall_id      │
│ → mood_frame │              │ Weather API        │
│              │              │ Расписание ТЦ      │
│ ~100ms       │              │ Культ. календарь   │
│              │              │ Events + Prefs     │
│              │              │ → context_frame    │
│              │              │                    │
│              │              │ ~100ms             │
└──────┬───────┘              └─────────┬──────────┘
       │                                │
       └────────────┐   ┌───────────────┘
                    │   │
                    ▼   ▼
         ┌──────────────────────────────────────────┐
         │  LLM ORCHESTRATOR (10.1.0.17)            │
         │                                          │
         │  1. ПАРАЛЛЕЛЬНО (Фаза 2):                │
         │     a) Embed запрос → vector      (~50ms)│
         │     b) POST /persona (10.1.0.21)  (~15ms)│
         │        → persona_directive               │
         │        → voice_params                    │
         │        → avatar_state + render_hints     │
         │                                          │
         │  2. ПАРАЛЛЕЛЬНО (Фаза 3, после embed):   │
         │     a) Hybrid Search              (~10ms)│
         │        (vector + FTS по Chat History)    │
         │        + тематический temporal decay     │
         │        + confidence-adjusted λ           │
         │        + diversity filter                │
         │        + similarity threshold            │
         │        → TOP-15 с memory_snippets        │
         │                                          │
         │     b) User Knowledge              (~1ms)│
         │     c) Последние 10 сообщений      (~1ms)│
         │     d) IF reply_to_id IS NOT NULL: (~0.1ms)
         │        Artifact lookup по PK             │
         │                                          │
         │  3. Emotional filter              (~1ms)  │
         │     (mood_frame → exclude болезненное)    │
         │                                          │
         │  4. Memory Density Cap            (~1ms)  │
         │     (≤3 episodes, ≤30% density)          │
         │                                          │
         │  5. Сборка ContextPack                    │
         │     A. User Knowledge (факты)             │
         │     B. memory_snippets (precomputed)      │
         │     C. Последние сообщения (поток)        │
         │     D. mood_frame (настроение)            │
         │     E. context_frame (мир вокруг)         │
         │     F. Referenced Artifact (если reply_to)│
         │     G. persona_directive (от Persona)     │
         │                                          │
         │  6. → LLM API с полным контекстом        │
         │  7. voice_params → Voice Server           │
         │  8. avatar_state + render_hints → App     │
         │                                          │
         │  ASYNC после ответа:                     │
         │  9. detect_behavioral_signals()           │
         │ 10. POST /persona/feedback (signals)      │
         │ 11. POST /persona/flush (exchange_id)     │
         └──────────────────────────────────────────┘

Общая добавленная latency: ~65ms
(embedding 50ms ‖ persona 15ms + hybrid search 10ms + filters 5ms)
(mood_frame и context_frame параллельно, ~100ms, 
 перекрываются с embedding + persona)
```

### Пример ContextPack для LLM

```
[System Prompt]
Ты UNDE — персональный AI-стилист и друг. Ты знаешь юзера 
лично. Проявляй память естественно, без цитирования дат 
и источников. Используй контекст реального мира для 
актуальных рекомендаций. Не упоминай прошлое чаще 
чем в каждом третьем ответе. Максимум 2-3 воспоминания 
за раз. Если есть Referenced Artifact — учитывай его 
при ответе на реакцию юзера.

[User Knowledge — extracted facts]
Имя: Алия. Стиль: casual, smart-casual. Размер: M. 
Бюджет: средний (экономит). Бренды: Zara, Massimo Dutti. 
Цвета: earth tones, navy. Парень: Дима. Не ест глютен.
Cultural sensitivity: medium.

[Episode Cards — precomputed snippets]
- Дима предлагал пойти куда-нибудь вместе
- Обожает корейские триллеры (Паразиты, Олдбой)
- В IMAX было холодно от кондиционера → тёплый слой
- Дима любит когда в юбках, особенно плиссе
- Экономит на отпуск, бюджет ограничен

[Последние сообщения]
Алия: "привет!"
UNDE: "Привет, Алия! Как дела?"
Алия: "хочу пойти в кино сегодня"

[Mood: позитивное, энергия средняя, valence 0.7]

[Context — мир вокруг]
Локация: Dubai Hills Mall, 1 этаж, рядом с Zara
Погода: +28°C, ясно, закат 18:15
Время: пятница вечер, ТЦ закрывается через 4.5 часа
Рестораны открываются после 18:12
Возможности:
  - Reel Cinemas: новый корейский триллер (Алия любит)
  - Zara: скидка 30% (любимый бренд)
  - Food Court: фестиваль — есть безглютеновые опции
```

### Docker Compose

```yaml
# /opt/unde/llm-orchestrator/docker-compose.yml

services:
  llm-orchestrator:
    build: .
    container_name: llm-orchestrator
    restart: unless-stopped
    env_file: .env
    command: celery -A app.celery_app worker -Q dialogue_queue -c 4 --max-tasks-per-child=500
    deploy:
      resources:
        limits:
          memory: 2G
        reservations:
          memory: 512M
    healthcheck:
      test: ["CMD", "celery", "-A", "app.celery_app", "inspect", "ping"]
      interval: 30s
      timeout: 10s
      retries: 3

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.17:9100:9100"
```

**4 concurrent workers:** каждый worker ждёт ответ от LLM API (2-10 сек). 4 workers = до 4 одновременных диалогов. Масштабируется горизонтально.

### Celery Task

```python
@celery_app.task(queue='dialogue_queue', time_limit=30, soft_time_limit=25)
def generate_response(user_id: str, message: str, input_type: str = 'text',
                      explicit_reply_to: str = None) -> dict:
    t_start = time.time()
    
    # 0. Определить шард юзера (routing table в Production DB / Redis)
    shard_conn = get_shard_connection(user_id)
    
    # 1. Получить mood_frame и context_frame (уже запущены параллельно App Server'ом)
    mood_frame = redis.get(f"mood:{user_id}:latest") or default_mood_frame()
    context_frame = redis.get(f"context:{user_id}:latest")  # от Context Agent
    
    # 1a. Canonicalize persona_profile, read relationship_stage
    persona_profile = shard_conn.get_persona_profile(user_id)
    relationship_stage = shard_conn.get_relationship_stage(user_id)
    
    # 2. ПАРАЛЛЕЛЬНО: Embed запрос + Persona Agent
    query_embedding, persona_output = parallel(
        embedding_client.embed_query(message),                     # ~50ms
        persona_agent.get_persona(user_id, mood_frame, context_frame,  # ~15ms
                                  intent, persona_profile, relationship_stage,
                                  user_profile_compact)
    )
    
    # 3. ПАРАЛЛЕЛЬНО собрать ContextPack:
    #    a) Hybrid Search (vector + FTS) по Chat History на шарде
    episodes = hybrid_search(shard_conn, user_id, query_embedding, message, top_k=15)
    
    #    b) User Knowledge (расшифровка AES-256)
    user_profile = shard_conn.get_user_knowledge(user_id)
    
    #    c) Последние 10 сообщений
    recent_messages = shard_conn.get_recent_messages(user_id, limit=10)
    
    #    d) Каталог (Production DB)
    catalog_context = get_catalog_context(user_id, message)
    
    # 3a. Resolve reply_to_id (серверная эвристика для voice-first)
    reply_to_id = resolve_reply_to(shard_conn, user_id, explicit_reply_to)
    referenced_artifact = None
    if reply_to_id:
        referenced_artifact = shard_conn.get_response_description(user_id, reply_to_id)
    
    # 4. Emotional filter (mood_frame → exclude болезненные воспоминания)
    episodes = emotional_filter(episodes, mood_frame)
    
    # 5. Memory Density Cap (≤3 episodes, ≤30% density)
    episodes = apply_density_cap(episodes, recent_messages)
    
    # 6. Определить intent и маршрутизация
    context = build_context_pack(
        user_profile=user_profile,
        episodes=episodes,
        recent_messages=recent_messages,
        mood_frame=mood_frame,
        context_frame=context_frame,
        catalog_context=catalog_context,
        referenced_artifact=referenced_artifact,
    )
    intent = classify_intent(message, context)
    
    if intent.requires_stylist:
        stylist_result = intelistyle.get_recommendations(
            build_intelistyle_request(message, context)
        )
        context.add("stylist_result", stylist_result)
    
    if intent.requires_recognition:
        recognition_result = recognize_photo.delay(intent.photo_url, user_id).get(timeout=15)
        context.add("recognition_result", recognition_result)
    
    # 7. Вызвать основную LLM
    llm_response = call_llm(
        provider=select_provider(),
        system_prompt=build_system_prompt(context, mood_frame),
        messages=context.recent_messages + [{"role": "user", "content": message}],
    )
    
    total_ms = int((time.time() - t_start) * 1000)
    
    # 8. SYNC: генерация response_description для артефактов (template-based, ~0.1ms)
    #    Обязательные токены в description артефакта: SKU/item_id, brand, store (если есть).
    #    Правило только для артефактов — обычные текстовые ответы имеют response_description = NULL.
    response_description = None
    if intent.requires_stylist and stylist_result:
        response_description = build_response_description('stylist', stylist_result)
    
    # 9. Сохранить в Chat History на шарде юзера
    #    SYNC: salience_check, classify_memory, response_description, reply_to_id
    #    ASYNC: embedding, memory_snippet (не блокирует юзера)
    save_user_message(shard_conn, user_id, message, mood_frame, input_type, reply_to_id)
    save_assistant_message(shard_conn, user_id, llm_response.text, 
                           response_description=response_description,
                           model_used=llm_response.model, duration_ms=total_ms)
    
    # 10. Отправить текст в Voice Server (если голосовой режим)
    voice_params = persona_output.get("voice_params", default_voice_params())
    
    # 11. ASYNC: behavioral signals → Persona Agent feedback loop
    exchange_id = str(uuid4())
    response_meta = build_response_meta(llm_response, intent, persona_output)
    async_detect_and_send_signals(user_id, exchange_id, response_meta, mood_frame)
    
    return {
        "text": llm_response.text,
        "voice_params": voice_params,
        "avatar_state": persona_output.get("avatar_state"),
        "render_hints": persona_output.get("render_hints"),
        "intent": intent.type,
        "duration_ms": total_ms,
        "model_used": llm_response.model
    }


def select_provider() -> str:
    """Выбор LLM-провайдера. Стратегия: primary + fallback."""
    # Primary: DeepSeek (дешевле, быстрее)
    # Fallback 1: Gemini
    # Fallback 2: Claude
    # Fallback 3: Qwen
    ...
```

### Environment Variables

```bash
# /opt/unde/llm-orchestrator/.env

# LLM Providers
DEEPSEEK_API_KEY=xxx
DEEPSEEK_MODEL=deepseek-chat

GEMINI_API_KEY=xxx
GEMINI_MODEL=gemini-2.0-flash

CLAUDE_API_KEY=xxx
CLAUDE_MODEL=claude-sonnet-4-20250514

QWEN_API_KEY=xxx
QWEN_MODEL=qwen-plus

# Provider strategy
LLM_PRIMARY_PROVIDER=deepseek
LLM_FALLBACK_PROVIDERS=gemini,claude,qwen

# Embedding (для Semantic Retrieval)
EMBEDDING_PROVIDER=cohere
EMBEDDING_MODEL=embed-multilingual-v3
EMBEDDING_API_KEY=xxx
EMBEDDING_DIM=1024

# Celery (Redis на Push Server)
REDIS_PASSWORD=xxx
CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/11
CELERY_RESULT_BACKEND=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/11

# Dubai Shard (Chat History + User Knowledge — шардированный)
# Routing через Production DB или Redis: user_id → shard connection string
SHARD_ROUTING_REDIS_URL=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/12
# Или прямое подключение для одного шарда (MVP):
SHARD_0_DB_URL=postgresql://app_rw:xxx@dubai-shard-0:6432/unde_shard

# Master Encryption Key (для расшифровки User Knowledge)
MASTER_ENCRYPTION_KEY=base64_encoded_32_byte_key

# Production DB (каталог, товары, routing_table, tombstone_registry)
PRODUCTION_DB_URL=postgresql://undeuser:xxx@10.1.1.2:6432/unde_main

# Mood Agent
MOOD_AGENT_URL=http://10.1.0.11:8080

# Context Agent
CONTEXT_AGENT_URL=http://10.1.0.19:8080

# Persona Agent
PERSONA_AGENT_URL=http://10.1.0.21:8080

# Voice Server
VOICE_SERVER_URL=http://10.1.0.12:8080

# Intelistyle (fashion recommendations)
INTELISTYLE_API_KEY=xxx
INTELISTYLE_API_URL=https://api.intelistyle.com/v3

# Recognition Orchestrator (для фото-запросов)
RECOGNITION_QUEUE=recognition_queue

# Retrieval params
RETRIEVAL_TOP_K=15
SIMILARITY_THRESHOLD=0.5
MAX_EPISODES_PER_RESPONSE=3
MAX_MEMORY_DENSITY_ROLLING_10=0.3

# Timeouts
LLM_TIMEOUT=15
CONTEXT_PACK_TIMEOUT=3
EMBEDDING_TIMEOUT=3
```

### Структура директорий

```
/opt/unde/llm-orchestrator/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── celery_app.py
│   ├── tasks.py                # generate_response orchestration
│   ├── context/
│   │   ├── context_pack.py     # Сборка ContextPack (3 слоя знания)
│   │   ├── semantic_retrieval.py  # Hybrid Search (vector + FTS)
│   │   ├── user_knowledge.py   # Client → User Knowledge на шарде (decrypt AES-256)
│   │   ├── catalog.py          # Client → Production DB
│   │   └── shard_router.py     # user_id → shard connection
│   ├── embedding/
│   │   ├── client.py           # Embedding API client (Cohere / eval winner)
│   │   └── ingestion.py        # Async pipeline: salience_check, classify_memory,
│   │                           # embedding, snippet generation
│   ├── memory/
│   │   ├── emotional_filter.py # mood_frame → exclude болезненные воспоминания
│   │   ├── density_cap.py      # ≤3 episodes, ≤30% density
│   │   ├── classify.py         # memory_type + memory_confidence (intensifiers/softeners)
│   │   └── salience.py         # salience_check: >15 chars, not emoji, user role
│   ├── consultant/
│   │   ├── response_description.py  # Template-based response_description (~0.1ms)
│   │   └── reply_to.py         # resolve_reply_to (серверная эвристика, 10 мин)
│   ├── llm/
│   │   ├── router.py           # Выбор провайдера, fallback
│   │   ├── deepseek_client.py
│   │   ├── gemini_client.py
│   │   ├── claude_client.py
│   │   └── qwen_client.py
│   ├── intents/
│   │   ├── classifier.py       # Определение intent из сообщения
│   │   └── handlers.py         # Маршрутизация к Intelistyle, Recognition
│   ├── prompts/
│   │   ├── system_prompt.py    # Генерация system prompt с контекстом
│   │   └── templates/
│   │       ├── base.txt
│   │       ├── fashion.txt
│   │       └── navigation.txt
│   ├── clients/
│   │   ├── intelistyle.py      # Intelistyle API client
│   │   ├── mood_agent.py       # HTTP client → 10.1.0.11
│   │   ├── context_agent.py    # HTTP client → 10.1.0.19
│   │   ├── persona_agent.py    # HTTP client → 10.1.0.21 (persona + feedback + flush)
│   │   └── voice_server.py     # HTTP client → 10.1.0.12
│   ├── db.py
│   └── models.py               # Pydantic: ContextPack, LLMResponse, Intent, MoodFrame
├── scripts/
│   ├── health-check.sh
│   └── test-dialogue.sh
└── deploy/
    ├── netplan-private.yaml
    └── llm-orchestrator.service
```

---

## 14. DUBAI USER DATA SHARD (новый — заменяет отдельные Chat History DB и User Knowledge DB)

> **Архитектурное решение:** Chat History и User Knowledge объединены на одном шарде (Dubai bare metal primary). Hetzner AX102 — hot standby replica. Это решение из документов UNDE_Infrastructure_BD и UNDE_Smart_Context_Architecture.

### Информация (Primary — Dubai bare metal)

| Параметр | Значение |
|----------|----------|
| **Hostname** | dubai-shard-0 |
| **Локация** | Dubai (Tier 3-4 DC: AEserver / ASPGulf) |
| **Тип** | Bare metal dedicated server (аренда, Фаза 1) → colocation (Фаза 2+) |
| **CPU** | 2× EPYC 7413 (24c/48t) |
| **RAM** | 256 GB DDR4 ECC |
| **Disk** | 2× 2TB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Информация (Replica — Hetzner Helsinki)

| Параметр | Значение |
|----------|----------|
| **Hostname** | shard-replica-0 |
| **Private IP** | 10.1.1.10 |
| **Тип** | Hetzner AX102 |
| **RAM** | 128 GB |
| **Disk** | 2× 2TB NVMe |
| **Стоимость** | $128/мес |

### RAM Disk Architecture (Primary)

```
256 GB RAM распределение:
├── tmpfs /pgdata/base         — 140 GB  (таблицы + HNSW индексы)
├── NVMe  /pgdata/pg_wal       — на диске (WAL с fsync, durability)
├── PostgreSQL shared_buffers  — 32 GB   (internal caching)
├── work_mem × connections     — 8 GB    (200 conn × 40 MB)
├── OS + PostgreSQL processes  — 8 GB
├── Резерв для роста           — 68 GB
└── ИТОГО                      — 256 GB
```

**Почему не всё на tmpfs:** WAL на NVMe обеспечивает crash recovery. При сбое питания:
- Данные в tmpfs потеряны → восстанавливаются из WAL + replica
- WAL на NVMe сохранён → PostgreSQL применяет его автоматически при запуске
- Или pg_basebackup с Hetzner replica если WAL неполный

### Назначение

Единый шард хранит **все данные юзера** — Chat History и User Knowledge:

**Chat History:**
- Один непрерывный диалог на юзера (не обнуляется)
- Каждое сообщение: роль, текст, **embedding (pgvector)**, **memory_type**, **memory_confidence**, **memory_snippet**, **response_description**, **reply_to_id**
- **Semantic Retrieval** — Hybrid Search (vector + FTS) по всей истории диалога
- **64 hash-партиции** по conversation_id для partition pruning
- Используется для формирования ContextPack (эпизоды из прошлого)
- Используется пайплайном User Knowledge для извлечения фактов

**User Knowledge:**
- Структурированные факты о юзере (стиль, размеры, бюджет, бренды)
- Зашифрованы AES-256-GCM (application-level envelope encryption)
- Ключи шифрования (DEK) в таблице user_keys на том же шарде

### Почему bare metal в Dubai (а не Hetzner)

- **Latency:** <1ms для Dubai users (vs 120ms до Hetzner)
- **RAM disk:** tmpfs — sub-microsecond reads для HNSW index (vs 2-5ms NVMe)
- **Noisy neighbors:** нет (bare metal vs shared cloud)
- **Kernel tuning:** полный контроль (huge pages, tmpfs, swappiness)
- **Стоимость:** $400-600/мес dedicated vs $724 OCI Dubai vs $1,766 Azure UAE

### Почему Chat History + User Knowledge на одном шарде

- Один сервер на юзера — один запрос для ContextPack
- Нет cross-server joins при сборке контекста
- GDPR hard delete: каскад на шарде + tombstone в Production DB
- Application-level sharding: hash(user_id) % N → shard_id

### Схема базы данных — Chat History (обновлённая, pgvector + FTS + партиционирование)

```sql
-- DATABASE: unde_shard (содержит и Chat History, и User Knowledge)

-- Расширения
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    message_count INTEGER DEFAULT 0,
    UNIQUE(user_id)  -- один диалог на юзера
);

-- Партиционированная таблица сообщений
CREATE TABLE messages (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL,
    
    role VARCHAR(20) NOT NULL,       -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,
    
    -- Semantic search (pgvector)
    -- NB: dim (1024) соответствует Cohere/Voyage. При смене провайдера:
    -- ALTER TABLE messages ALTER COLUMN embedding TYPE vector(NEW_DIM) + re-embed all.
    embedding vector(1024),
    is_embeddable BOOLEAN DEFAULT FALSE,
    is_forgotten BOOLEAN DEFAULT FALSE,
    
    -- Memory classification (тип + уверенность → скорость затухания)
    memory_type VARCHAR(20) DEFAULT 'general',
        -- emotion | preference | fact | event | general
    memory_confidence FLOAT DEFAULT 0.5,
        -- 0.0..1.0, определяется по intensifiers/softeners
    
    -- Precomputed snippet (0ms в рантайме вместо 400ms LLM-компрессии)
    memory_snippet TEXT,
        -- "В IMAX было холодно от кондиционера → брать тёплый слой"
    
    -- Consultant Response Description Layer
    -- Backend-only текстовое описание артефакта консультанта.
    -- В UI не показывается. Генерируется SYNC template-based при INSERT (~0.1ms).
    -- NULL для обычных текстовых ответов без артефакта.
    response_description TEXT,
    
    -- Ссылка на assistant message, к которому относится реакция юзера.
    -- Заполняется у user-сообщений. Не FK (из-за партиционирования).
    -- Серверная эвристика: последний артефакт за 10 мин, если клиент не указал явно.
    -- Защита от неоднозначности: если 2+ артефакта за <60 сек — reply_to_id = NULL (LLM уточнит).
    reply_to_id UUID,
    
    -- Full-text search
    -- NB: 'simple' config = точные токены без морфологии.
    -- FTS отвечает за имена/бренды/цифры, семантика — через embeddings.
    -- Включает response_description для поиска по атрибутам артефактов.
    tsv tsvector GENERATED ALWAYS AS (
        to_tsvector('simple', content || ' ' || COALESCE(response_description, ''))
    ) STORED,
    
    -- Метаданные
    media_urls JSONB,
    mood_frame JSONB,
    input_type VARCHAR(20),          -- 'voice', 'text'
    duration_ms INTEGER,
    model_used VARCHAR(100),
    
    -- GDPR
    deleted_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (conversation_id, id)
) PARTITION BY HASH (conversation_id);

-- 64 партиции (достаточно для 800+ юзеров на шард)
DO $$
BEGIN
    FOR i IN 0..63 LOOP
        EXECUTE format(
            'CREATE TABLE messages_p%s PARTITION OF messages 
             FOR VALUES WITH (MODULUS 64, REMAINDER %s)',
            lpad(i::text, 2, '0'), i
        );
    END LOOP;
END $$;

-- HNSW: partial index только для embeddable, не-forgotten сообщений
CREATE INDEX idx_messages_embedding 
    ON messages USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE role = 'user' AND is_embeddable = TRUE 
      AND is_forgotten = FALSE AND embedding IS NOT NULL;

CREATE INDEX idx_messages_tsv 
    ON messages USING gin (tsv);

CREATE INDEX idx_messages_conversation_time 
    ON messages(conversation_id, created_at DESC);

CREATE INDEX idx_messages_retrieval
    ON messages(conversation_id, role, is_embeddable, is_forgotten)
    WHERE role = 'user' AND is_embeddable = TRUE AND is_forgotten = FALSE;

CREATE INDEX idx_conversations_user ON conversations(user_id);
```

**Результат:** при запросе с `WHERE conversation_id = $2` PostgreSQL автоматически обращается только к 1 из 64 партиций. HNSW-индекс в этой партиции содержит ~190K записей (12M / 64) вместо 12M — поиск на порядки быстрее.

**Идентификация сообщений:** PK = `(conversation_id, id)` — составной из-за партиционирования. Во всех системах — UI, tombstone registry, логи, API — оперируем **парой (conversation_id, message_id)**, не одним id.

### Схема базы данных — User Knowledge (на том же шарде)

```sql
-- Ключи шифрования юзеров
CREATE TABLE user_keys (
    user_id UUID PRIMARY KEY,
    encrypted_dek BYTEA NOT NULL,      -- DEK зашифрованный мастер-ключом
    created_at TIMESTAMPTZ DEFAULT NOW(),
    rotated_at TIMESTAMPTZ
);

-- Знания о юзере (зашифрованы AES-256-GCM)
CREATE TABLE user_knowledge (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_keys(user_id),
    
    -- Зашифрованные данные
    encrypted_data BYTEA NOT NULL,
    iv BYTEA NOT NULL,                  -- Initialization vector
    auth_tag BYTEA NOT NULL,            -- Authentication tag
    
    -- Метаданные (НЕ зашифрованы, для индексации)
    knowledge_type VARCHAR(50) NOT NULL,
        -- 'style_profile', 'body_params', 'brand_preferences',
        -- 'budget', 'life_events', 'behavior_patterns',
        -- 'emotional_patterns', 'color_preferences'
    
    -- Версионирование
    version INTEGER DEFAULT 1,
    extracted_from VARCHAR(50),          -- 'chat_pipeline', 'onboarding', 'explicit_input'
    source_message_id UUID,             -- для каскадного soft/hard forget
    confidence DECIMAL(3,2),
    is_active BOOLEAN DEFAULT TRUE,     -- для soft forget
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_knowledge_user_type ON user_knowledge(user_id, knowledge_type);
CREATE INDEX idx_knowledge_updated ON user_knowledge(updated_at DESC);

-- === Persona Agent: Relationship Stage (persisted state) ===
CREATE TABLE relationship_stage (
    user_id          UUID PRIMARY KEY,
    stage            INTEGER DEFAULT 0,         -- 0, 1, 2, 3
    stage_updated_at TIMESTAMPTZ DEFAULT NOW(),
    sessions_count   INTEGER DEFAULT 0,
    total_exchanges  INTEGER DEFAULT 0,
    positive_signals_count INTEGER DEFAULT 0,
    last_active_at   TIMESTAMPTZ DEFAULT NOW()
);
-- Stage upgrade: sessions + exchanges + positive signals
-- Stage downgrade: 45-90 дней без активности (stage-dependent)

-- === Persona Agent: Temp Blocks ===
CREATE TABLE persona_temp_blocks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL,
    key         VARCHAR(50) NOT NULL,           -- 'cultural_ref', 'humor', etc.
    until       TIMESTAMPTZ NOT NULL,
    reason      VARCHAR(100) NOT NULL,          -- 'cultural_ref_rejected'
    signal_id   UUID,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_temp_blocks_user ON persona_temp_blocks(user_id);
-- Max 20 per user, lazy + cron cleanup

-- === Persona Agent: Signal Daily Deltas (momentum tracking) ===
CREATE TABLE signal_daily_deltas (
    user_id     UUID NOT NULL,
    field       VARCHAR(50) NOT NULL,           -- canonical field name
    date        DATE NOT NULL DEFAULT CURRENT_DATE,
    total_delta FLOAT DEFAULT 0,
    PRIMARY KEY (user_id, field, date)
);
-- TTL: 7 дней (для отладки), cron cleanup
```

### Hybrid Search с тематическим Temporal Decay и Confidence

```sql
WITH vector_results AS (
    -- Vector search: только user-сообщения (эмбеддинги только у них)
    SELECT id, content, memory_snippet, memory_type, 
           memory_confidence, created_at, role,
           response_description,
           GREATEST(0, 1 - (embedding <=> $1)) AS vec_score
    FROM messages
    WHERE conversation_id = $2
      AND role = 'user'
      AND is_embeddable = TRUE
      AND is_forgotten = FALSE
      AND embedding IS NOT NULL
    ORDER BY embedding <=> $1
    LIMIT 20
),
fts_results AS (
    -- FTS: user + assistant (response_description в tsvector)
    -- Без фильтра role — ловим и юзерские сообщения, и описания артефактов
    SELECT id, content, memory_snippet, memory_type, 
           memory_confidence, created_at, role,
           response_description,
           LEAST(1.0, ts_rank(tsv, plainto_tsquery('simple', $3)) * 10) AS fts_score
    FROM messages
    WHERE conversation_id = $2
      AND is_forgotten = FALSE
      AND tsv @@ plainto_tsquery('simple', $3)
    ORDER BY fts_score DESC
    LIMIT 10
),
merged AS (
    SELECT 
        COALESCE(v.id, f.id) AS id,
        COALESCE(v.content, f.content) AS content,
        COALESCE(v.memory_snippet, f.memory_snippet) AS memory_snippet,
        COALESCE(v.memory_type, f.memory_type) AS memory_type,
        COALESCE(v.memory_confidence, f.memory_confidence) AS memory_confidence,
        COALESCE(v.created_at, f.created_at) AS created_at,
        COALESCE(v.role, f.role) AS role,
        COALESCE(v.response_description, f.response_description) AS response_description,
        COALESCE(v.vec_score, 0) AS vec_score,
        COALESCE(f.fts_score, 0) AS fts_score
    FROM vector_results v
    FULL OUTER JOIN fts_results f 
        ON v.id = f.id
)
SELECT 
    id,
    -- Для assistant-артефактов: response_description как episode_card
    -- Для user-сообщений: precomputed snippet или LEFT(content, 80)
    CASE 
        WHEN role = 'assistant' AND response_description IS NOT NULL 
            THEN response_description
        ELSE COALESCE(memory_snippet, LEFT(content, 80))
    END AS episode_card,
    created_at,
    role,
    -- Hybrid score + тематический temporal decay + confidence
    (0.7 * vec_score + 0.3 * fts_score) 
    * (1 + 0.3 * EXP(
        -1 * CASE memory_type
            WHEN 'emotion'    THEN 0.015
            WHEN 'event'      THEN 0.008
            WHEN 'general'    THEN 0.005
            WHEN 'preference' THEN 0.002
            WHEN 'fact'       THEN 0.001
            ELSE 0.005
        END
        * (1.3 - COALESCE(memory_confidence, 0.5))
        * EXTRACT(EPOCH FROM NOW() - created_at) / 86400
    )) AS final_score
FROM merged
WHERE vec_score > 0.5 OR fts_score > 0
ORDER BY final_score DESC
LIMIT 15;
```

**Асимметрия vector vs FTS:** vector branch ищет только `role='user'` (эмбеддинги только у юзерских сообщений). FTS branch ищет **все роли** — это позволяет находить assistant-артефакты по токенам из `response_description` (бренд, цвет, SKU). Для assistant-сообщений episode_card берётся из `response_description` (не из `content`, который содержит "Вот что я нашла!").

**Важно:** temporal decay — это recency boost, а не наказание за давность. Множитель ≥ 1.0. Свежие воспоминания получают бонус, старые не штрафуются.

**Diversity filter:** не более 3 сообщений из одного календарного дня (применяется в application layer).

### Скорости затухания по типу воспоминания

| Тип | base_λ | Базовый полураспад | Пример |
|-----|--------|-------------------|--------|
| emotion | 0.015 | ~46 дней | "устала после работы" |
| event | 0.008 | ~87 дней | "в прошлый раз в кино было холодно" |
| general | 0.005 | ~139 дней | "Дима предложил сходить куда-нибудь" |
| preference | 0.002 | ~347 дней | "обожаю корейские триллеры" |
| fact | 0.001 | ~693 дня | "не ем глютен" |

**Корректировка через confidence:** `effective_λ = base_λ(memory_type) × (1.3 - memory_confidence)`

### Soft / Hard Forget

**Soft Forget (кнопка "Забудь это"):**

```sql
UPDATE messages SET 
    is_forgotten = TRUE,
    embedding = NULL,
    memory_snippet = NULL
WHERE conversation_id = $1 AND id = $2;
-- + если факт был извлечён из этого сообщения:
UPDATE user_knowledge SET is_active = FALSE WHERE source_message_id = $2;
```

**Hard Delete (GDPR erase):**

```sql
DELETE FROM user_knowledge WHERE source_message_id = $2;
UPDATE messages SET 
    content = '[deleted]',
    embedding = NULL,
    memory_snippet = NULL,
    memory_confidence = NULL,
    response_description = NULL,
    reply_to_id = NULL,
    is_forgotten = TRUE,
    deleted_at = NOW()
WHERE conversation_id = $1 AND id = $2;

-- Регистрация в tombstone registry (Production DB)
INSERT INTO deleted_messages_registry (conversation_id, message_id, deleted_at)
VALUES ($1, $2, NOW());
```

**Tombstone Registry** хранится в Production DB (primary) + Object Storage (copy). После любого восстановления шарда — `apply_deletions.sql` на основе registry.

### Конфигурация PostgreSQL (Dubai Primary — RAM disk)

```ini
# postgresql.conf — оптимизация для tmpfs + NVMe WAL

# Пути
data_directory = '/pgdata'          # tmpfs mount
# pg_wal символическая ссылка на /nvme/pg_wal (NVMe)

# Durability: fsync только для WAL (на NVMe)
fsync = on                          # WAL на NVMe → fsync имеет смысл
synchronous_commit = local          # WAL flush на NVMe перед ack клиенту
full_page_writes = on               # Нужен для корректности WAL-цепочки на реплике

# Планировщик: всё в памяти
random_page_cost = 0.01             # random = sequential (нет диска)
seq_page_cost = 0.01
effective_cache_size = 140GB        # Размер tmpfs
effective_io_concurrency = 0        # Нет async I/O нужен

# Буферы
shared_buffers = 32GB               # PG internal caching (нужен даже с tmpfs)
work_mem = 40MB
maintenance_work_mem = 4GB          # Для REINDEX, VACUUM
wal_buffers = 64MB

# WAL
wal_level = replica                 # Нужен для streaming replication
max_wal_senders = 5
wal_keep_size = 8GB
max_replication_slots = 5
checkpoint_timeout = 15min
max_wal_size = 4GB

# Huge pages (bare metal only)
huge_pages = on                     # 2MB pages → меньше TLB misses

# Archiving (для PITR backup)
archive_mode = on
archive_command = 'test ! -f /nvme/wal_archive/%f && cp %p /nvme/wal_archive/%f'
```

### Системная конфигурация (Dubai Primary)

```bash
# /etc/fstab — tmpfs для PostgreSQL данных
tmpfs /pgdata tmpfs defaults,size=160G,noatime,mode=0700,uid=postgres,gid=postgres 0 0

# /etc/sysctl.conf — huge pages для shared_buffers
vm.nr_hugepages = 17000            # 32GB shared_buffers + overhead
vm.hugetlb_shm_group = 999         # postgres group ID
vm.swappiness = 1                   # Минимальный swap

# Символическая ссылка WAL на NVMe
ln -s /nvme/pg_wal /pgdata/pg_wal
```

### Streaming Replication: Dubai → Hetzner

```
Время 0.000s: Пользователь отправляет сообщение
Время 0.002s: PostgreSQL (Dubai, tmpfs) выполняет INSERT
              → WAL-запись создана
              → Данные записаны в tmpfs (мгновенно)
              → WAL пишется на NVMe (фоновый flush)
              → Клиенту возвращён ответ "OK"
Время 0.003s: WAL sender отправляет запись по сети в Hetzner
              ... 120ms через подводные кабели ...
Время 0.123s: PostgreSQL (Hetzner, NVMe) получает WAL
              → Записывает на NVMe (с fsync)
              → Применяет изменение (WAL replay)
```

**Async replication:** primary не ждёт подтверждения от replica → минимальная latency для клиента.

### Patroni + etcd: автоматический failover

**3 узла etcd:**

| Узел | Локация | Тип | Зачем |
|------|---------|-----|-------|
| etcd-1 | Dubai (dedicated server) | Lightweight VM / контейнер | Локальный голос для primary |
| etcd-2 | Hetzner Helsinki (AX102) | Контейнер на replica-сервере | Голос replica |
| etcd-3 | Hetzner Helsinki (CPX11) | Dedicated lightweight (~€4/мес) | Кворум: 2 из 3 в Hetzner |

**Логика кворума:**
- Dubai жив + любой Hetzner → кворум есть, Dubai = primary (норма)
- Dubai упал → 2 Hetzner из 3 = кворум, Hetzner promoted (failover)
- Hetzner-сеть упала → Dubai один, нет кворума → Patroni НЕ позволяет Dubai работать → fencing

```
Failover timeline:
00:00.000  — Сервер в Дубае погас
00:05.000  — Patroni на Hetzner: "Primary не отвечает 5 секунд"
00:10.000  — Patroni: "Подожду ещё 5 сек"
00:15.000  — Patroni: "Primary мёртв" → pg_ctl promote на Hetzner
00:15.500  — Patroni обновляет etcd → HAProxy/PgBouncer переключаются
00:16.000  — Система работает через Hetzner (latency 120ms вместо <1ms)

RTO (время простоя): ~15–30 секунд
RPO (потеря данных): 0 на уровне пар — client-side verify-and-replay
```

**Failback policy:** failover auto, failback — ТОЛЬКО вручную, после проверки: lag=0, health green ≥ 10 мин, инженер подтвердил.

### Client-Side Verify-and-Replay

При async replication последние 1–5 секунд WAL могут не доехать до Hetzner. Приложение хранит буфер последних пар «запрос юзера + ответ UNDE» и переотправляет при reconnect.

**Протокол:**

```
Нормальный режим:
  App → Dubai primary: message + UUID (client-generated)
  Dubai primary: INSERT → WAL flush на NVMe → ack
  App: status "confirmed"

Сбой (ack не дошёл):
  App: status остаётся "unconfirmed"
  ... 15-30 сек (Patroni failover) ...
  App → Hetzner (новый primary): POST /verify-and-replay
  {
    conversation_id: "conv-xyz",
    unconfirmed: [пары user+assistant],
    recent_confirmed_ids: [последние 3 confirmed пары (safety net)]
  }
  Hetzner:
    Если role=assistant и содержит артефакт → построить response_description (template-based)
    INSERT ... ON CONFLICT DO NOTHING + enrichment backfill
```

**Буфер в приложении:**
- Persistent storage (SQLite на iOS/Android, IndexedDB на web)
- 10 пар + confirmed пары ещё 60 сек после ack
- Rate-limit retry: 1 пара/сек/юзер, max 3 попытки

### Шардирование (application-level по user_id)

```
Routing (в Redis / Production DB):
  user_id → hash(user_id) % N_shards → shard_id → connection string

Вместимость одного шарда (256 GB RAM, 140 GB tmpfs):
  Год 1: ~2,500 users/шард (HNSW ~56 GB + heap ~60 GB = ~116 GB)
  Год 3: ~1,500 users/шард (HNSW ~101 GB + heap ~35 GB = ~136 GB)

Триггер для нового шарда:
  SELECT pg_relation_size('idx_embeddings_hnsw') > 80 GB
  (50% от available working set)
```

**Roadmap:**
- Месяц 1–6: 1 шард (до 5,000 users)
- Месяц 6–12: 2 шарда (до 10,000 users)
- Год 2: 4 шарда
- Год 3: 6–7 шардов

### Backup стратегия (4 уровня)

```
Уровень 1: WAL на NVMe (local crash recovery)
  → Защищает от: PostgreSQL process crash, OOM kill, soft failures
  → НЕ защищает от: reboot, сбой питания (tmpfs = пустой)

Уровень 2: Streaming replication на Hetzner (real-time)
  → RPO: 0 (client-side verify-and-replay)
  → RTO: 15–30 секунд (Patroni)

Уровень 3: WAL archive в Object Storage (continuous)
  → Point-in-Time Recovery на любой момент
  → RPO: до последнего archived WAL segment (~5 минут)

Уровень 4: pg_basebackup в Object Storage (periodic)
  → Полная копия каждые 6 часов
  → Хранение: 7 дней daily + 4 недели weekly + 3 месяца monthly
```

**Локальный snapshot на NVMe в Dubai:**
- pg_basebackup каждые 2 часа (cron, --compress=lz4)
- Restore с локального NVMe в 10–50× быстрее чем с Hetzner
- RTO: 5–10 минут вместо часов

### Восстановление primary после сбоя

```
1. DC починил питание / заменён компонент
2. Сервер загрузился, tmpfs пустой

3. Вариант A: Локальный snapshot (быстрый, рекомендуемый)
   → Копируем с NVMe в tmpfs: 50 GB за ~1 мин, 200 GB за ~4 мин
   → Догоняем по WAL с Hetzner (секунды)
   → RTO: 5–10 минут

   Вариант B: С Hetzner replica
   → pg_basebackup -h hetzner-ip -D /pgdata -Fp -Xs -P
   → 1 Gbps: 50 GB за ~7 мин, 200 GB за ~27 мин
   → RTO: 7 минут – 4 часа

4. Дубай запускается как replica, догоняет по WAL
5. Failback — ТОЛЬКО вручную: lag=0, health green ≥ 10 мин
```

### Модель безопасности данных на шарде

```
Chat History (messages):
  content, memory_snippet,       → plaintext в PostgreSQL
  response_description           → plaintext (backend-only)
  embedding, tsv                 → открыто (необходимо для search)
  Защита: private network + LUKS at-rest + strict PG roles + audit log

User Knowledge:
  Все поля → AES-256 app-level encryption
  Ключи → user_keys таблица на том же шарде
  Защита: AES-256 + private network + LUKS at-rest
```

**Почему content не зашифрован app-level:**
- FTS (tsvector) работает только с открытым текстом
- Rule-based snippets (`LEFT(content, 80)`) требуют plaintext
- App-level AES сделал бы FTS и tsvector бесполезными

### Расчёт объёма (с Semantic Retrieval)

| Компонент | Размер на сообщение | Комментарий |
|-----------|---------------------|-------------|
| Текст (content) | ~1 KB | Среднее сообщение |
| mood_frame JSON | ~200 B | Не для всех |
| Embedding (1024-dim, float32) | ~4 KB | Только embeddable (~50%) |
| HNSW индекс overhead | ~1.2 KB | ~30% от embedding |
| tsvector (FTS) | ~200 B | Включает response_description |
| memory_snippet | ~100 B | Только embeddable |
| memory_type + confidence | ~15 B | |
| response_description | ~150 B | Только assistant с артефактом (~20%) |
| Метаданные + индексы PG | ~500 B | |
| **Среднее на сообщение** | **~4.7 KB** | С учётом 50% embeddable, 20% артефактов |

| Период | Сообщений/юзер | Chat History | User Knowledge | Итого |
|--------|---------------|-------------|----------------|-------|
| 1 месяц | ~500 | ~2.3 MB | ~70 KB | ~2.4 MB |
| 1 год | ~6,000 | ~27 MB | ~200 KB | ~27 MB |
| 5 лет | ~30,000 | ~135 MB | ~1 MB | ~136 MB |

### Рост HNSW индекса (halfvec, 10K users)

| Период | Embeddings | HNSW индекс | Heap + прочие индексы | Working set |
|--------|-----------|-------------|----------------------|-------------|
| Месяц 6 | 7.5M | ~22 GB | ~40 GB | ~62 GB |
| Год 1 | 15M | ~45 GB | ~70 GB | ~115 GB |
| Год 2 | 30M | ~90 GB | ~140 GB | ~230 GB |
| Год 3 | 45M | ~135 GB | ~250 GB | ~385 GB |

**Один сервер 256 GB** вмещает 10K users комфортно **~8–10 месяцев.** После этого — шардирование.

### Производительность RAM disk vs alternatives

| Метрика | Cloud VM (OCI 128GB) | Bare Metal NVMe | Bare Metal + RAM disk |
|---------|---------------------|-----------------|----------------------|
| HNSW traversal (150 reads) | 2–5 ms (cached) / 50–100 ms (miss) | 1.5 ms | **~10 μs** |
| Heap fetch (20 reads) | 0.5–2 ms | 0.2 ms | **~1.4 μs** |
| Full hybrid search | 3–10 ms | 2–5 ms | **<100 μs** |
| 1,000 concurrent queries p95 | 30–80 ms | 10–25 ms | **<1 ms** |

### Пользователи БД

| User | Доступ | Сервер |
|------|--------|--------|
| app_rw | READ/WRITE all | App Server, LLM Orchestrator |
| knowledge_rw | READ/WRITE user_knowledge, user_keys | Knowledge Pipeline (локальный) |
| persona_rw | READ/WRITE relationship_stage, persona_temp_blocks, signal_daily_deltas; READ user_knowledge | Persona Agent (10.1.0.21) |
| replicator | REPLICATION | Hetzner AX102 replica |

---

## 15. CONTEXT AGENT (новый)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | context-agent |
| **Private IP** | 10.1.0.19 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Context Agent — сервер, который знает **что происходит вокруг юзера прямо сейчас**. Аналог Mood Agent, но для внешнего мира вместо внутреннего состояния.

```
Mood Agent    → как юзер СЕБЯ чувствует  (внутреннее)
Context Agent → что ВОКРУГ юзера сейчас  (внешнее)
```

### Что он знает

| Категория | Данные | Источник | Кеш |
|-----------|--------|----------|-----|
| Геолокация | В каком ТЦ, у какого магазина, район | App (GPS + indoor positioning) | Реальное время |
| Погода | Температура, влажность, условия, закат | Weather API | 30 мин |
| Время | День недели, часть дня, до закрытия ТЦ | Системные часы + расписание | 1 мин |
| События | Распродажи, премьеры, фестивали | Production DB + парсинг | 1 час |
| Культурный контекст | Рамадан, праздники, выходные | Календарь + API | 24 часа |
| Спутники | Одна или с кем-то (если шарит локацию) | App (опционально) | Реальное время |

### Cultural Sensitivity Level

| Уровень | Поведение | Пример |
|---------|----------|--------|
| `high` | Упоминать культурные события естественно | "До ифтара 45 мин — успеешь на сеанс 17:00" |
| `medium` | Учитывать в логике, но не называть явно | "Рестораны откроются после 18:12" |
| `low` | Не упоминать, но учитывать расписание | Просто не предлагать обед в дневное время Рамадана |

**По умолчанию:** `medium`. Определяется из диалога или Settings.

### HTTP API

```
POST http://10.1.0.19:8080/context

Request:
{
  "user_id": "uuid",
  "lat": 25.1025,
  "lng": 55.2438,
  "mall_id": "dubai-hills-mall",
  "compact_preferences": {
    "favorite_brands": ["Zara", "Massimo Dutti"],
    "allergies": ["gluten"],
    "interests": ["korean_thrillers"],
    "cultural_sensitivity_level": "medium"
  }
}

Response: context_frame JSON (см. ниже)

Latency target: < 100ms p95
```

### context_frame JSON

```json
{
  "context_frame_id": "uuid",
  "timestamp": "2026-02-13T19:30:00+04:00",

  "location": {
    "type": "mall",
    "mall_id": "dubai-hills-mall",
    "mall_name": "Dubai Hills Mall",
    "near_store": "zara-ground-floor",
    "floor": 1
  },

  "environment": {
    "weather": {
      "temp_c": 28,
      "feels_like_c": 31,
      "humidity": 65,
      "condition": "clear",
      "sunset": "18:15"
    },
    "time_context": {
      "day_of_week": "friday",
      "part_of_day": "evening",
      "mall_closes_in_hours": 4.5,
      "is_rush_hour": true
    }
  },

  "cultural": {
    "sensitivity_level": "medium",
    "active_period": "ramadan",
    "next_meal_break": "18:12",
    "is_pre_meal_break": true,
    "nearby_holidays": []
  },

  "opportunities": [
    {
      "store": "Zara",
      "type": "sale",
      "discount": "30%",
      "relevance_reason": "user_favorite_brand"
    },
    {
      "store": "Reel Cinemas",
      "type": "premiere",
      "title": "New Korean thriller",
      "relevance_reason": "user_loves_korean_thrillers"
    }
  ]
}
```

**При `sensitivity_level: medium`:** нейтральные формулировки — `next_meal_break` (не `iftar_time`).

### OpportunityMatcher

Context Agent пересекает события с compact_preferences из User Knowledge:

```
Production DB: "Zara — скидка 30%"
User Knowledge: "Любимый бренд: Zara"
→ opportunity с relevance_reason: "user_favorite_brand"
```

### Docker Compose

```yaml
services:
  context-agent:
    build: .
    container_name: context-agent
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.19:8080:8080"
    deploy:
      resources:
        limits:
          memory: 2G

  redis:
    image: redis:7-alpine
    container_name: context-redis
    restart: unless-stopped
    command: redis-server --maxmemory 256mb --maxmemory-policy allkeys-lru

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.19:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/context-agent/.env

# Weather API
WEATHER_API_KEY=xxx
WEATHER_API_URL=https://api.weatherapi.com/v1

# Production DB (events, stores)
PRODUCTION_DB_URL=postgresql://readonly:xxx@10.1.1.2:6432/unde_main

# Server
CONTEXT_PORT=8080
CONTEXT_WORKERS=4

# Cache TTLs
WEATHER_CACHE_TTL=1800       # 30 мин
EVENTS_CACHE_TTL=3600        # 1 час
CULTURAL_CACHE_TTL=86400     # 24 часа
```

### Внутренние модули

```
/opt/unde/context-agent/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── server.py              # FastAPI / uvicorn
│   ├── geo_resolver.py        # GPS/indoor → mall_id, nearest_store
│   ├── weather_client.py      # Weather API → temp, humidity, условия
│   ├── time_context.py        # Часы + расписание ТЦ → part_of_day
│   ├── event_scanner.py       # Production DB → акции, события рядом
│   ├── cultural_calendar.py   # Статичный JSON + API → Рамадан, праздники
│   ├── opportunity_matcher.py # Пересечение: events + compact_prefs
│   └── models.py              # Pydantic: ContextFrame
├── data/
│   └── cultural_calendar.json # Статичные культурные события
├── scripts/
│   ├── health-check.sh
│   └── test-context.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 16. PERSONA AGENT (новый)

> **Архитектурное решение:** Persona Agent — «актуатор» поведения аватара. Mood Agent и Context Agent — сенсоры (что чувствует юзер, что вокруг). Persona Agent определяет **как аватар ведёт себя**: характер, тон, стиль отношений, голос, визуальное поведение. Зависимость: Mood → Persona (сенсор → актуатор).
>
> Подробная спецификация: UNDE_Persona_Voice_Layer v0.7.0.

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | persona-agent |
| **Private IP** | 10.1.0.21 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Единый источник правды для поведения аватара — 4 выхода:
- **persona_directive** (как говорить) → LLM Orchestrator → system prompt
- **voice_params** (как звучать) → LLM Orchestrator → Voice Server → ElevenLabs
- **avatar_state** (как выглядеть) → App → Rive-аватар
- **render_hints** (контракт с UI) → App → анимации, listen_state, expression

Внутренние модули:
- **Canonicalizer** — нормализация полей профиля + legacy aliases
- **StageGate** — ограничения по relationship stage (0→3)
- **ToneAdapter** — выбор tone_mode (playful/warm/gentle/supportive/efficient/...)
- **SituationalRulesEngine** — бюджет, вес, время, future events
- **VoiceDirector** — маппинг tone_mode → voice presets (6 пресетов)
- **AvatarDirector** — expression, energy_level, listen_state, reactive gestures
- **SignalBuffer** — debouncing per exchange_id + conflict graph + conservative wins
- **FeedbackProcessor** — применение сигналов с momentum caps
- **AntiPatternGuard** — hard bans: anti-manipulation policy

### Что НЕ делает

- ❌ Не анализирует эмоции юзера (это Mood Agent, 10.1.0.11)
- ❌ Не знает что вокруг юзера (это Context Agent, 10.1.0.19)
- ❌ Не генерирует текст ответа (это LLM Orchestrator, 10.1.0.17)
- ❌ Не синтезирует речь (это Voice Server, 10.1.0.12)
- Он — актуатор: принимает mood_frame + context_frame + профиль, отдаёт поведенческие директивы

### Почему CPX11

Чистый rule-based engine: lookup профиля, применение правил, JSON-формирование. Ноль LLM-вызовов. Целевая latency: <15ms p95. Минимум CPU/RAM.

### Расположение в инфраструктуре

```
                Mood Agent (10.1.0.11)
                    │ mood_frame
                    ▼
┌──────────────────────────────────────────────────┐
│  LLM ORCHESTRATOR (10.1.0.17)                    │
│                                                  │
│  Фаза 2 (параллельно с embedding):              │
│  ├── Embed запрос (~50ms)                        │
│  └── POST /persona (~15ms)                       │
│       Input: mood_frame, context_frame,          │
│              persona_profile, stage,             │
│              user_intent, uk_compact             │
│       Output: persona_directive,                 │
│               voice_params,                      │
│               avatar_state,                      │
│               render_hints                       │
│                                                  │
│  persona_directive → system prompt для LLM       │
│  voice_params → Voice Server (10.1.0.12)         │
│  avatar_state + render_hints → App (📱)          │
└──────────────────────────────────────────────────┘
```

### HTTP API

```
POST http://10.1.0.21:8080/persona
  Input: { user_id, mood_frame, context_frame, user_intent,
           persona_profile, relationship_stage, user_knowledge_compact,
           last_n_response_meta }
  Output: { persona_directive, voice_params, avatar_state, render_hints, debug }
  Latency: < 15ms p95

POST http://10.1.0.21:8080/persona/feedback
  Input: { user_id, signal_id, exchange_id, signal_type, signal_data }
  Output: { buffered: true }
  Назначение: буферизация behavioral signals (14 типов)

POST http://10.1.0.21:8080/persona/flush
  Input: { user_id, exchange_id }
  Output: { resolved, discarded, applied, stale_flushed }
  Назначение: resolve_and_apply() после end-of-utterance

GET http://10.1.0.21:8080/persona/profile?user_id=...
  Output: { persona_profile, relationship_stage, temp_blocks }
  Назначение: дебаг / Settings UI
```

### Ключевые концепции

**Relationship Stage (0→3):** persisted state, не вычисляется с нуля. Stage gate ограничивает поведение — stage 0: нет юмора выше low, нет cultural refs, memory=subtle. Stage 2+: всё разблокировано.

**Signal Debouncing:** сигналы буферизуются per exchange_id (один обмен: ответ UNDE → реплика юзера). Конфликты разрешаются через conflict graph (connected components). Conservative wins: `humor_ignored` побеждает `humor_positive`.

**Momentum Caps:** safe fields ±0.10/exchange, ±0.30/day. Sensitive fields ±0.05/exchange, ±0.15/day. Предотвращает резкие скачки профиля.

**persona_contract:** версионируемый Python-пакет с canonical fields, legacy aliases, stage limits, signal effects, tone modes. Major version check на каждом запросе.

### Docker Compose

```yaml
# /opt/unde/persona-agent/docker-compose.yml

services:
  persona-agent:
    build: .
    container_name: persona-agent
    restart: unless-stopped
    env_file: .env
    ports:
      - "10.1.0.21:8080:8080"
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 256M
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 3s
      retries: 3

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.21:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/persona-agent/.env

# Dubai Shard (relationship_stage, persona_temp_blocks, signal_daily_deltas)
SHARD_ROUTING_REDIS_URL=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/12
SHARD_0_DB_URL=postgresql://app_rw:xxx@dubai-shard-0:6432/unde_shard

# Redis (idempotency store + signal buffer + distributed lock)
REDIS_URL=redis://:xxx@10.1.0.4:6379/13

# Server
PERSONA_PORT=8080
PERSONA_WORKERS=4

# Contract
PERSONA_CONTRACT_VERSION=0.7.0
```

### Структура директорий

```
/opt/unde/persona-agent/
├── docker-compose.yml
├── Dockerfile
├── .env
├── .env.example
├── requirements.txt
├── app/
│   ├── __init__.py
│   ├── server.py                 # FastAPI / uvicorn
│   ├── canonicalizer.py          # Canonical fields + legacy aliases
│   ├── stage_gate.py             # Relationship stage limits
│   ├── rule_priority.py          # RulePriorityResolver (hard bans > overrides > stage > profile > defaults)
│   ├── tone_adapter.py           # Tone mode resolution (8 modes)
│   ├── situational_rules.py      # Budget, weight, time, future events
│   ├── relationship_style.py     # RelationshipStyleBuilder
│   ├── cultural_references.py    # Cultural reference matcher (6 gates)
│   ├── voice_director.py         # Tone → voice presets (6 presets)
│   ├── avatar_director.py        # Expression, energy, gestures
│   ├── render_hints.py           # RenderHintsBuilder
│   ├── anti_pattern_guard.py     # Hard bans, anti-manipulation
│   ├── signal_buffer.py          # Per-exchange buffer + conflict graph
│   ├── feedback_processor.py     # Apply with momentum caps
│   ├── idempotency.py            # In-memory + Redis, TTL 72h
│   ├── concurrency.py            # Per-user asyncio.Lock
│   ├── directive_builder.py      # Build persona_directive (7 блоков)
│   ├── models.py                 # Pydantic: PersonaOutput, MoodFrame, etc.
│   └── db.py                     # PostgreSQL client (stage, blocks, deltas)
├── persona_contract/
│   ├── __init__.py               # CONTRACT_VERSION, assert_compatible()
│   ├── fields.py                 # CANONICAL_FIELDS, LEGACY_ALIASES
│   ├── stages.py                 # STAGE_LIMITS, STAGE_REQUIREMENTS
│   ├── signals.py                # SIGNAL_EFFECTS, CONSERVATIVE_SIGNALS
│   ├── tones.py                  # TONE_MODES, VOICE_PRESETS
│   └── momentum.py               # MOMENTUM_LIMITS, FIELD_THRESHOLD_GROUP
├── data/
│   └── cultural_references.json  # Статичный registry
├── tests/
│   └── test_golden.py            # 29 golden tests (блокируют деплой)
├── scripts/
│   ├── health-check.sh
│   └── test-persona.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 17. DATA FLOW

### 17.1 Сбор каталога (еженедельно, 3 сервера)

```
┌─────────────────┐
│  Apify.com      │
│  Резидентные    │
│  прокси         │
└────────┬────────┘
         │ ~15K товаров/бренд (JSON метаданные)
         ▼
┌────────────────────────────────────────────────────┐
│  APIFY SERVER (10.1.0.7)                           │
│                                                    │
│  1. Получить JSON от Apify                         │
│  2. INSERT метаданные в Staging DB                 │
│     (image_status='pending')                       │
│  НЕ скачивает фото, НЕ синхронизирует Ximilar     │
└─────────────────┬──────────────────────────────────┘
                  ▼
         ┌──────────────┐
         │  Staging DB  │  image_status = 'pending'
         │  raw_products│
         └──────┬───────┘
                │
    ┌───────────┴───────────┐
    ▼                       ▼ (после uploaded/collage_ready)
┌────────────────────┐  ┌────────────────────┐
│  PHOTO DOWNLOADER  │  │  XIMILAR SYNC      │
│  (10.1.0.13)       │  │  (10.1.0.14)       │
│                    │  │                    │
│  1. SELECT pending │  │  1. SELECT pending │
│  2. Скачать фото   │  │  2. POST → Ximilar │
│  3. Upload в OS    │  │     Collection     │
│  4. UPDATE →       │  │  3. UPDATE →       │
│     'uploaded'     │  │     'synced'       │
└────────┬───────────┘  └────────────────────┘
         │
         ▼
┌──────────────┐
│ Object       │
│ Storage      │
│ /originals/  │
└──────────────┘
```

### 17.2 Наличие в магазинах (каждый час, Scraper Server)

```
┌─────────────────┐
│  Mobile API     │
│  Zara, etc.     │
└────────┬────────┘
         │ 4 магазина × ~15K товаров
         ▼
┌────────────────────────────────────────────────────┐
│  SCRAPER SERVER (10.1.0.3)                         │
│                                                    │
│  1. GET /itxrest/.../physicalstore/{id}/product     │
│  2. INSERT INTO raw_availability                   │
└─────────────────┬──────────────────────────────────┘
                  ▼
         ┌──────────────┐
         │  Staging DB  │
         │  raw_availab.│
         └──────────────┘
```

### 17.3 Создание коллажей (каждые 15 мин, Collage Server)

```
┌──────────────┐
│  Staging DB  │  SELECT WHERE image_status = 'uploaded'
└──────┬───────┘
       ▼
┌────────────────────────────────────────────────────┐
│  COLLAGE SERVER (10.1.0.8)                         │
│                                                    │
│  1. Скачать оригиналы из /originals/               │
│  2. Склеить в один файл (горизонтально)            │
│  3. Upload в /collages/                            │
│  4. UPDATE image_status = 'collage_ready'          │
└─────────────────┬──────────────────────────────────┘
     ┌────────────┴────────────┐
     ▼                         ▼
┌──────────────┐      ┌──────────────────┐
│  Staging DB  │      │  Object Storage  │
│  collage_url │      │  /collages/      │
└──────────────┘      └──────────────────┘
```

### 17.4 Синхронизация в Production (каждый час, Scraper Server)

```
┌──────────────┐     ┌──────────────┐
│  Staging DB  │     │  Staging DB  │
│  raw_products│     │  raw_availab.│
└──────┬───────┘     └──────┬───────┘
       └────────┬───────────┘
                ▼
┌────────────────────────────────────────────────────┐
│  SCRAPER SERVER (10.1.0.3) — Sync Job              │
│                                                    │
│  SELECT p.*, a.sizes_in_stock                      │
│  FROM raw_products p                               │
│  JOIN raw_availability a                           │
│    ON p.external_id = a.product_id                 │
│  WHERE p.image_status = 'collage_ready'            │
│    AND p.sync_status = 'pending'                   │
│    AND a.fetched_at > NOW() - INTERVAL '2 hours'   │
│                                                    │
│  → Только товары с коллажом И в наличии в KZ       │
└─────────────────┬──────────────────────────────────┘
                  ▼
         ┌───────────────────┐
         │  Production DB    │
         │  (10.1.1.2)       │
         │  UPSERT products  │
         └───────────────────┘
```

### 17.5 Пользователь: каталог + try-on

```
┌──────────────┐
│ 📱 Приложение│
└──────┬───────┘
       │ GET /api/products
       ▼
┌──────────────┐     JSON: image_url, collage_url
│  App Server  │─────────────────────────────────┐
│  (10.1.0.2)  │                                 │
└──────┬───────┘                                 │
       ▼                                         ▼
┌──────────────┐                      ┌──────────────────┐
│ 📱 Каталог   │→ Object Storage      │ Try-on Service   │
│ 📱 Try-on    │→ fal.ai → результат  │ (10.1.0.6)       │
└──────────────┘                      └──────────────────┘
```

### 17.6 Пользователь: Fashion Recognition

```
┌──────────────┐
│ 📱 Приложение│  Фотографирует outfit на улице
└──────┬───────┘
       │ POST /api/v1/recognize (фото)
       ▼
┌──────────────┐
│  App Server  │  Celery task → Redis
│  (10.1.0.2)  │
└──────┬───────┘
       ▼
┌────────────────────────────────────────────────────┐
│  RECOGNITION ORCHESTRATOR (10.1.0.9)               │
│                                                    │
│  Step 1: → Ximilar GW /detect → crops + категории │
│     (200-500ms) → сразу показать chips на фото     │
│      ▼                                             │
│  Step 2: → Ximilar GW /tag + LLM Reranker /tag    │
│           (параллельно, ~1s)     → атрибуты        │
│      ▼                                             │
│  Step 3: → Ximilar GW /search → TOP-10 кандидатов │
│     (200-500ms)                                    │
│      ▼                                             │
│  Step 4: → LLM Reranker /rerank                    │
│     (1-2s, batch параллельно)                      │
│     > 0.85  → "Нашли! Это [SKU] в [магазин]"      │
│     0.5-0.85 → "Похожие варианты" TOP-3-5         │
│     < 0.5   → Attribute fallback (SQL по тегам)    │
│                                                    │
│  Суммарно: 2-4 сек                                 │
│  Результат → Redis → App Server → Приложение       │
└──┬────────────────────┬───────────────────────┬────┘
   │                    │                       │
   ▼                    ▼                       ▼
┌──────────────┐ ┌──────────────┐ ┌───────────────────┐
│ XIMILAR GW   │ │ LLM RERANKER │ │  Production DB    │
│ (10.1.0.15)  │ │ (10.1.0.16)  │ │  (10.1.1.2)       │
│ → Ximilar API│ │ → Gemini 2.5 │ │ recognition_      │
│              │ │   Flash      │ │ requests (лог)    │
└──────────────┘ └──────────────┘ └───────────────────┘
```

### 17.7 Пользователь: диалог с аватаром (обновлено — 3 слоя знания + Persona Agent)

```
┌──────────────┐
│ 📱 Приложение│  Говорит или пишет
└──────┬───────┘
       │ POST /api/v1/chat (текст/ASR + GPS + reply_to?)
       ▼
┌──────────────┐
│  App Server  │  Три параллельных запуска:
│  (10.1.0.2)  │  1. mood_analyze → Mood Agent
└──────┬───────┘  2. context_request → Context Agent
       │          3. generate_response → LLM Orchestrator
       │
  ┌────┴──────────────────┬─────────────────────┐
  │                       │                     │
  ▼                       ▼                     ▼
┌───────────────┐ ┌────────────────┐ ┌──────────────────────────────────────┐
│ MOOD AGENT    │ │ CONTEXT AGENT  │ │ LLM ORCHESTRATOR (10.1.0.17)         │
│ (10.1.0.11)   │ │ (10.1.0.19)    │ │                                      │
│               │ │                │ │ Ожидает mood_frame + context_frame,  │
│ → mood_frame  │ │ → context_frame│ │ затем:                               │
│ (~100ms)      │ │ (~100ms)       │ │                                      │
└──────┬────────┘ └──────┬─────────┘ │ Фаза 2 (ПАРАЛЛЕЛЬНО):               │
       │                 │           │ 1a. Embed запрос → vector    (~50ms) │
       └────────┐  ┌─────┘           │ 1b. POST /persona            (~15ms)│
                │  │                 │     (10.1.0.21)                      │
                ▼  ▼                 │     → persona_directive              │
         mood_frame +                │     → voice_params                   │
         context_frame ────────────► │     → avatar_state + render_hints   │
                                     │                                      │
                                     │ Фаза 3 (после embed):              │
                                     │ 2. ПАРАЛЛЕЛЬНО:                      │
                                     │    a) Hybrid Search (vector+FTS)     │
                                     │       + temporal decay + confidence  │
                                     │       → TOP-15 memory_snippets      │
                                     │    b) User Knowledge (AES-256)      │
                                     │    c) Последние 10 сообщений        │
                                     │    d) Artifact lookup (reply_to_id) │
                                     │                                      │
                                     │ 3. Emotional filter (mood_frame)     │
                                     │ 4. Memory Density Cap (≤3, ≤30%)     │
                                     │ 5. Сборка ContextPack (6 слоёв)     │
                                     │    (+ persona_directive)             │
                                     │ 6. → LLM API                        │
                                     │ 7. SYNC: response_description       │
                                     │ 8. voice_params → Voice Server      │
                                     │ 9. avatar+hints → App               │
                                     │ ASYNC: signals → /persona/feedback  │
                                     └──┬────────┬──────────┬────────┬────┘
                                        │        │          │        │
                                        ▼        ▼          ▼        ▼
                             ┌────────────┐ ┌────────┐ ┌──────┐ ┌────────┐
                             │Dubai Shard │ │ Voice  │ │📱 App│ │Persona │
                             │(bare metal)│ │ Server │ │текст+│ │Agent   │
                             │Chat History│ │10.1.0.12│ │аудио+│ │feedback│
                             │+ UK + Stage│ │voice→📱│ │avatar│ │+ flush │
                             │enrichment  │ └────────┘ └──────┘ └────────┘
                             └────────────┘

Общая добавленная latency от Semantic Retrieval + Persona: ~65ms
(embedding 50ms ‖ persona 15ms + hybrid search 10ms + filters 5ms)
(mood_frame и context_frame ~100ms, перекрываются с embedding+persona)
```

---

## 18. РАСПИСАНИЕ ЗАДАЧ

| Задача | Сервер | Частота | Время | Описание |
|--------|--------|---------|-------|----------|
| **availability_poll** | Scraper (10.1.0.3) | Каждый час | :00 | Mobile API → Staging DB |
| **sync_to_production** | Scraper (10.1.0.3) | Каждый час | :10 | Staging → Production DB |
| **process_collages** | Collage (10.1.0.8) | Каждые 15 мин | :00,:15,:30,:45 | Создание коллажей |
| **retry_failed** | Collage (10.1.0.8) | Каждый час | :30 | Повтор неудачных |
| **apify_zara** | Apify (10.1.0.7) | Еженедельно | Вс 02:00 | Метаданные Zara |
| **apify_bershka** | Apify (10.1.0.7) | Еженедельно | Вс 03:00 | Метаданные Bershka |
| **apify_pullandbear** | Apify (10.1.0.7) | Еженедельно | Вс 04:00 | Метаданные Pull&Bear |
| **apify_stradivarius** | Apify (10.1.0.7) | Еженедельно | Вс 05:00 | Метаданные Stradivarius |
| **apify_massimodutti** | Apify (10.1.0.7) | Еженедельно | Вс 06:00 | Метаданные Massimo Dutti |
| **apify_oysho** | Apify (10.1.0.7) | Еженедельно | Вс 07:00 | Метаданные Oysho |
| **download_pending** | Photo Downloader (10.1.0.13) | Каждые 15 мин | :00,:15,:30,:45 | Скачать фото pending |
| **download_retry** | Photo Downloader (10.1.0.13) | Каждый час | :30 | Повтор неудачных |
| **ximilar_sync** | Ximilar Sync (10.1.0.14) | Еженедельно | Вс 10:00 | Новые SKU → Ximilar Collection |
| **ximilar_retry** | Ximilar Sync (10.1.0.14) | Ежедневно | 12:00 | Повтор неудачных |
| **cleanup_old_data** | Staging DB | Ежедневно | 04:00 | DELETE > 30 дней |
| **cleanup_temp_files** | Photo Downloader, Collage | Ежедневно | 05:00 | rm /app/data/* |

**Recognition Orchestrator** — без расписания, обрабатывает запросы в реальном времени через Celery queue.

**Ximilar Gateway** — без расписания, обрабатывает HTTP-запросы от Orchestrator в реальном времени.

**LLM Reranker** — без расписания, обрабатывает HTTP-запросы от Orchestrator в реальном времени.

**Mood Agent Server** — без расписания, обрабатывает запросы в реальном времени через HTTP API (синхронный, < 200ms).

**Voice Server** — без расписания, обрабатывает запросы в реальном времени через HTTP API + WebSocket streaming.

**LLM Orchestrator** — без расписания, обрабатывает запросы в реальном времени через Celery queue (dialogue_queue). Latency target: < 10s p95.

**Context Agent** — без расписания, обрабатывает HTTP-запросы в реальном времени (< 100ms p95). Кеширование: погода 30 мин, события 1 час, культура 24 часа.

**Persona Agent** — без расписания, обрабатывает HTTP-запросы в реальном времени (< 15ms p95). POST /persona (directive), POST /persona/feedback (signals), POST /persona/flush (resolve). In-process LRU cache (100 профилей). Cron: cleanup persona_temp_blocks + signal_daily_deltas (ежедневно 04:00).

**Dubai Shard (Chat History + User Knowledge)** — без расписания, принимает INSERT при каждом сообщении, Hybrid Search для ContextPack, async enrichment (embedding, snippet). Streaming replication → Hetzner непрерывно.

### Бэкапы

| Компонент | Метод | Частота | Хранилище | Retention |
|-----------|-------|---------|-----------|-----------|
| Production DB (Hetzner) | pgBackRest | Full: Вс 02:00, Diff: Пн-Сб 03:00 | Storage Box BX11 (1TB) | 4 full + 7 diff |
| Staging DB (Hetzner) | pgBackRest | Full: Вс 03:00, Diff: Пн-Сб 04:00 | Storage Box | 4 full + 7 diff |
| Dubai Shard → Hetzner | Streaming replication | Непрерывно (async WAL) | AX102 replica | Real-time |
| Dubai Shard → Object Storage | pg_basebackup | Каждые 6 часов | Hetzner Object Storage | 7 daily + 4 weekly + 3 monthly |
| Dubai Shard → WAL archive | archive_command | Непрерывно | Object Storage + NVMe | Point-in-Time Recovery |
| Dubai Shard → локальный snapshot | pg_basebackup --compress=lz4 | Каждые 2 часа | NVMe отдельный раздел | 1 копия |

---

## 19. МОНИТОРИНГ

### Prometheus targets

```yaml
# /etc/prometheus/prometheus.yml на App Server

scrape_configs:
  # Существующие...
  
  # Новые:
  - job_name: 'node-apify'
    static_configs:
      - targets: ['10.1.0.7:9100']

  - job_name: 'node-photo-downloader'
    static_configs:
      - targets: ['10.1.0.13:9100']

  - job_name: 'node-ximilar-sync'
    static_configs:
      - targets: ['10.1.0.14:9100']

  - job_name: 'node-collage'
    static_configs:
      - targets: ['10.1.0.8:9100']

  - job_name: 'node-recognition'
    static_configs:
      - targets: ['10.1.0.9:9100']

  - job_name: 'node-ximilar-gw'
    static_configs:
      - targets: ['10.1.0.15:9100']

  - job_name: 'node-llm-reranker'
    static_configs:
      - targets: ['10.1.0.16:9100']

  - job_name: 'node-llm-orchestrator'
    static_configs:
      - targets: ['10.1.0.17:9100']

  - job_name: 'node-staging-db'
    static_configs:
      - targets: ['10.1.1.3:9100']

  - job_name: 'node-mood-agent'
    static_configs:
      - targets: ['10.1.0.11:9100']

  - job_name: 'node-voice'
    static_configs:
      - targets: ['10.1.0.12:9100']

  - job_name: 'node-context-agent'
    static_configs:
      - targets: ['10.1.0.19:9100']

  - job_name: 'node-persona-agent'
    static_configs:
      - targets: ['10.1.0.21:9100']

  - job_name: 'node-dubai-shard-0'
    static_configs:
      - targets: ['dubai-shard-0:9100']

  - job_name: 'postgres-dubai-shard-0'
    static_configs:
      - targets: ['dubai-shard-0:9187']

  - job_name: 'node-shard-replica-0'
    static_configs:
      - targets: ['10.1.1.10:9100']

  - job_name: 'postgres-shard-replica-0'
    static_configs:
      - targets: ['10.1.1.10:9187']

  - job_name: 'etcd-cluster'
    static_configs:
      - targets: ['dubai-shard-0:2379', '10.1.1.10:2379', '10.1.1.20:2379']

  - job_name: 'postgres-staging'
    static_configs:
      - targets: ['10.1.1.3:9187']
```

### Ключевые метрики

| Метрика | Источник | Алерт |
|---------|----------|-------|
| apify_scraper_duration | Apify Server | > 2 часов |
| apify_scraper_errors | Apify Server | > 10% |
| photo_download_errors | Photo Downloader | > 10% |
| photo_download_pending_count | Photo Downloader | > 5000 |
| photo_download_speed_mbps | Photo Downloader | < 1 |
| ximilar_sync_errors | Ximilar Sync | > 5% |
| ximilar_sync_pending_count | Ximilar Sync | > 5000 |
| collage_queue_size | Staging DB | > 1000 |
| collage_processing_errors | Collage Server | > 5% |
| availability_poll_success | Scraper | 0 (failed) |
| sync_job_success | Scraper | 0 (failed) |
| recognition_pipeline_duration_ms | Recognition Orchestrator | p95 > 10s |
| recognition_orchestrator_errors | Recognition Orchestrator | > 5% |
| recognition_queue_size | Redis (Push Server) | > 50 |
| ximilar_gw_detect_latency_ms | Ximilar Gateway | p95 > 1s |
| ximilar_gw_search_latency_ms | Ximilar Gateway | p95 > 1s |
| ximilar_gw_errors | Ximilar Gateway | > 5% |
| ximilar_gw_rate_limit_hits | Ximilar Gateway | > 0 |
| llm_reranker_latency_ms | LLM Reranker | p95 > 3s |
| llm_reranker_errors | LLM Reranker | > 5% |
| llm_reranker_cost_usd | LLM Reranker | threshold TBD |
| llm_orchestrator_response_time_ms | LLM Orchestrator | p95 > 10s |
| llm_orchestrator_errors | LLM Orchestrator | > 5% |
| llm_orchestrator_cost_usd | LLM Orchestrator | threshold TBD |
| llm_orchestrator_provider_fallbacks | LLM Orchestrator | > 10% |
| llm_orchestrator_queue_size | Redis (Push Server) | > 20 |
| llm_orchestrator_context_pack_time_ms | LLM Orchestrator | p95 > 3s |
| staging_db_disk_usage | Staging DB | > 80% |
| mood_agent_latency_ms | Mood Agent | p95 > 200ms |
| mood_agent_errors | Mood Agent | > 5% |
| voice_tts_latency_ms | Voice Server | p95 > 500ms |
| voice_elevenlabs_errors | Voice Server | > 5% |
| voice_ws_connections | Voice Server | > 100 |
| context_agent_latency_ms | Context Agent | p95 > 100ms |
| context_agent_errors | Context Agent | > 5% |
| context_agent_weather_cache_hit | Context Agent | < 50% |
| **Persona Agent** | | |
| persona_agent_latency_ms | Persona Agent | p95 > 15ms |
| persona_agent_errors | Persona Agent | > 5% |
| persona_feedback_signals_total | Persona Agent | — (info metric) |
| persona_signal_discard_rate | Persona Agent | > 50% (слишком много конфликтов) |
| persona_stage_upgrades_total | Persona Agent | — (info metric) |
| persona_temp_blocks_active | Dubai Shard | > 100 per user |
| **Dubai Shard (tmpfs + replication)** | | |
| tmpfs_usage_percent | Dubai Shard | > 85% — время добавлять шард |
| hnsw_index_size_bytes | Dubai Shard | > 80 GB — планировать новый шард |
| replication_lag_seconds | Dubai Shard → Hetzner | > 5 секунд |
| replica_up | Hetzner Replica | == 0 — failover скомпрометирован |
| replay_requests_total_rate | App Server | > 10/5m — недавний failover |
| enrichment_backfill_rate | LLM Orchestrator | > 5/5m — replayed без embedding |
| replication_slot_wal_bytes | Dubai Shard | > 20 GB — replica отстала, NVMe в опасности |
| etcd_server_has_leader | etcd cluster | == 0 — risk split-brain |
| hybrid_search_latency_ms | Dubai Shard | p95 > 50ms |
| embedding_ingestion_errors | LLM Orchestrator | > 5% |
| memory_snippet_null_rate | Dubai Shard | > 10% embeddable |
| user_knowledge_decrypt_errors | Dubai Shard | > 1% |
| user_knowledge_decrypt_latency_ms | Dubai Shard | p95 > 1ms |
| pgbackrest_last_full_age_hours | Production DB, Staging DB | > 192 (8 days) |
| basebackup_last_age_hours | Dubai Shard → Object Storage | > 12 (missed 2 cycles) |
| local_snapshot_age_hours | Dubai Shard → NVMe | > 4 (missed 2 cycles) |
| user_media_bucket_size | Hetzner | > 200 GB |
| object_storage_size | Hetzner | > 200 GB |

---

## 20. ПЛАН РАЗВЁРТЫВАНИЯ

### День 1: Object Storage

```bash
# Hetzner Console
1. Storage → Object Storage → Create Bucket
2. Bucket name: unde-images
3. Создать Access Key
4. Сохранить credentials

# Тест
aws s3 ls s3://unde-images --endpoint-url=https://hel1.your-objectstorage.com
```

### День 2: Staging DB

```bash
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.1.3

apt update && apt install -y postgresql-17 pgbouncer
sudo -u postgres createdb unde_staging
sudo -u postgres psql unde_staging < schema.sql

# Тест
psql -h 10.1.1.3 -p 6432 -U scraper -d unde_staging
```

### День 3: Apify Server (метаданные)

```bash
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.7

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/apify-collector.git /opt/unde/apify
cd /opt/unde/apify
cp .env.example .env  # Заполнить: Apify Token, Staging DB
docker-compose up -d

# Тест
docker-compose exec apify-collector python -c "from tasks import collect_brand; collect_brand('zara', limit=100)"
```

### День 3b: Photo Downloader

```bash
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.13

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/photo-downloader.git /opt/unde/photo-downloader
cd /opt/unde/photo-downloader
cp .env.example .env  # Заполнить: Staging DB, S3 credentials
docker-compose up -d

# Тест (после Apify собрал метаданные)
docker-compose exec photo-downloader python -c "from tasks import download_pending; download_pending(limit=10)"
```

### День 3c: Ximilar Sync Server

```bash
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.14

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/ximilar-sync.git /opt/unde/ximilar-sync
cd /opt/unde/ximilar-sync
cp .env.example .env  # Заполнить: Staging DB, Ximilar credentials
docker-compose up -d

# Тест (после Photo Downloader скачал фото)
docker-compose exec ximilar-sync python -c "from tasks import sync_to_ximilar; sync_to_ximilar(limit=10)"
```

### День 4: Collage Server

```bash
# Hetzner Console → Создать сервер CPX31 (Helsinki), Private: 10.1.0.8

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/collage-server.git /opt/unde/collage
cd /opt/unde/collage
cp .env.example .env
docker-compose up -d

# Тест
docker-compose exec collage-worker python -c "from tasks import process_product; process_product(1)"
```

### День 5: Recognition Orchestrator + Ximilar Gateway + LLM Reranker

```bash
# 1. Ximilar Gateway
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.15

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/ximilar-gw.git /opt/unde/ximilar-gw
cd /opt/unde/ximilar-gw
cp .env.example .env  # Заполнить: XIMILAR_API_TOKEN, XIMILAR_COLLECTION_ID
docker-compose up -d

# Тест
curl -X POST http://10.1.0.15:8001/detect -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/test-photo.jpg"}'

# 2. LLM Reranker
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.16

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/llm-reranker.git /opt/unde/llm-reranker
cd /opt/unde/llm-reranker
cp .env.example .env  # Заполнить: GEMINI_API_KEY, CLAUDE_API_KEY
docker-compose up -d

# Тест
curl -X POST http://10.1.0.16:8002/tag -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/test-crop.jpg"}'

# 3. Recognition Orchestrator
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.9

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/recognition.git /opt/unde/recognition
cd /opt/unde/recognition
cp .env.example .env  # Заполнить: Redis, DB, XIMILAR_GW_URL, LLM_RERANKER_URL

# Создать таблицу в Production DB
psql -h 10.1.1.2 -p 6432 -U undeuser -d unde_main < deploy/init-db.sql

# Запустить
docker-compose up -d

# Тест полного pipeline
./scripts/test-recognize.sh
```

### День 6: Интеграция

```bash
# 1. Обновить Scraper (10.1.0.3)
#    Добавить STAGING_DB_URL, обновить sync job, включить расписание

# 2. Загрузить каталог в Ximilar Collection
#    Ximilar Sync Server: запустить ximilar_sync для существующих товаров

# 3. Обновить Prometheus (App Server)
#    Добавить targets: recognition, ximilar-gw, llm-reranker, photo-downloader, ximilar-sync

# 4. Проверить полный flow
#    a. Apify: собрать 100 товаров Zara (метаданные)
#    b. Photo Downloader: скачать фото
#    c. Ximilar Sync: загрузить в Collection
#    d. Collage: обработать
#    e. Scraper: sync в Production
#    f. Recognition: тестовый запрос (Orchestrator → Ximilar GW + LLM Reranker)
#    g. App: проверить API /api/v1/recognize
```

### День 7: Mood Agent Server

```bash
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.11

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/mood-agent.git /opt/unde/mood-agent
cd /opt/unde/mood-agent
cp .env.example .env  # Заполнить: DeepSeek, Gemini (fallback), Redis
docker-compose up -d

# Тест
curl -X POST http://10.1.0.11:8080/analyze \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","text":"Привет, мне нужно красивое платье на свадьбу подруги","previous_mood_frame_id":null}'

# Проверить latency < 200ms
```

### День 8: Voice Server

```bash
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.12

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/voice.git /opt/unde/voice
cd /opt/unde/voice
cp .env.example .env  # Заполнить: ElevenLabs, Redis
docker-compose up -d

# Тест синхронного TTS
curl -X POST http://10.1.0.12:8080/synthesize \
  -H "Content-Type: application/json" \
  -d '{"text":"Привет! Рада тебя видеть!","voice_params":{"warmth":0.8,"tempo":1.0,"tension":0.1,"expressiveness":"warm"}}' \
  --output test.mp3

# Тест WebSocket streaming
./scripts/test-voice.sh

# Обновить Prometheus (App Server)
#    Добавить targets: mood-agent (10.1.0.11:9100), voice (10.1.0.12:9100)
```

### День 8b: User Media Bucket

```bash
# Hetzner Console → Object Storage → Create Bucket
#    Bucket name: unde-user-media
#    Access: PRIVATE (не публичный!)
#    Создать Access Key (или использовать существующий)

# Тест
aws s3 ls s3://unde-user-media --endpoint-url=https://hel1.your-objectstorage.com
```

### День 8c: LLM Orchestrator

```bash
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.17

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/llm-orchestrator.git /opt/unde/llm-orchestrator
cd /opt/unde/llm-orchestrator
cp .env.example .env  # Заполнить: LLM API ключи, DB URLs, Redis, Intelistyle, Master Key
docker-compose up -d

# Тест
docker-compose exec llm-orchestrator python -c "
from app.tasks import generate_response
result = generate_response('test-user', 'Привет, подбери мне образ на свидание', 'text')
print(result)
"

# Проверить: ответ приходит, контекст собирается, сообщения сохраняются в Chat History DB

# Обновить Prometheus (App Server)
#    Добавить target: llm-orchestrator (10.1.0.17:9100)
```

### День 9: Persona Agent

```bash
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.21

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/persona-agent.git /opt/unde/persona-agent
cd /opt/unde/persona-agent
cp .env.example .env  # Заполнить: Dubai Shard DB, Redis, CONTRACT_VERSION

# Создать таблицы в Dubai Shard
psql -h dubai-shard-0 -p 6432 -U app_rw -d unde_shard < deploy/init-persona-tables.sql

docker-compose up -d

# Тест
curl -X POST http://10.1.0.21:8080/persona \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","mood_frame":{"valence":0.7,"energy":0.6},"context_frame":{},"user_intent":"browse","persona_profile":{},"relationship_stage":0,"user_knowledge_compact":{},"last_n_response_meta":[]}'

# Проверить latency < 15ms
# Запустить golden tests
docker-compose exec persona-agent python -m pytest tests/test_golden.py -v

# Обновить Prometheus (App Server) → target: persona-agent (10.1.0.21:9100)
```

### День 9b: Context Agent

```bash
# Hetzner Console → Создать сервер CPX11 (Helsinki), Private: 10.1.0.19

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/context-agent.git /opt/unde/context-agent
cd /opt/unde/context-agent
cp .env.example .env  # Заполнить: Weather API, Production DB
docker-compose up -d

# Тест
curl -X POST http://10.1.0.19:8080/context \
  -H "Content-Type: application/json" \
  -d '{"user_id":"test","lat":25.1025,"lng":55.2438,"mall_id":"dubai-hills-mall","compact_preferences":{"favorite_brands":["Zara"],"cultural_sensitivity_level":"medium"}}'

# Проверить latency < 100ms
# Обновить Prometheus (App Server) → target: context-agent (10.1.0.19:9100)
```

### День 10: Dubai User Data Shard (bare metal Dubai + Hetzner replica)

```bash
# === ФАЗА 1: Аренда Dubai dedicated server ===

# 1. Арендовать dedicated server в Дубае (AEserver / ASPGulf)
#    Требования: 256 GB RAM, 2× NVMe 2TB, root access, private network, 1 Gbps
#    Стоимость: $400-600/мес, $0 CAPEX
#    Время: 1-3 дня

# 2. Заказать Hetzner AX102 (hot standby replica) — $128/мес
#    Private IP: 10.1.1.10

# 3. Заказать Hetzner CPX11 (etcd-3 node) — ~€4/мес
#    Private IP: 10.1.1.20

# === ФАЗА 2: Настройка Dubai Primary ===

# 4. Проверить сервер
fio --name=nvme-test --rw=write --bs=1M --size=10G --numjobs=1 --direct=1
stress-ng --vm 1 --vm-bytes 200G --verify --timeout 60s

# 5. Установить Ubuntu 24.04 + PostgreSQL 17 + pgvector
apt update && apt install -y postgresql-17 postgresql-17-pgvector

# 6. Настроить tmpfs + WAL на NVMe
echo 'tmpfs /pgdata tmpfs defaults,size=160G,noatime,mode=0700,uid=postgres,gid=postgres 0 0' >> /etc/fstab
mount /pgdata
mkdir -p /nvme/pg_wal /nvme/wal_archive /nvme/snapshots
chown postgres:postgres /nvme/pg_wal /nvme/wal_archive /nvme/snapshots
ln -s /nvme/pg_wal /pgdata/pg_wal

# 7. Настроить huge pages
echo 'vm.nr_hugepages = 17000' >> /etc/sysctl.conf
echo 'vm.swappiness = 1' >> /etc/sysctl.conf
sysctl -p

# 8. Создать базу с pgvector
sudo -u postgres createdb unde_shard
sudo -u postgres psql unde_shard -c "CREATE EXTENSION vector;"
sudo -u postgres psql unde_shard < schema_chat_history.sql
sudo -u postgres psql unde_shard < schema_user_knowledge.sql

# 9. Сгенерировать мастер-ключ для User Knowledge
python3 -c "import secrets, base64; print(base64.b64encode(secrets.token_bytes(32)).decode())"
# → записать в .env как MASTER_ENCRYPTION_KEY

# === ФАЗА 3: Настройка Hetzner Replica ===

# 10. На Hetzner AX102: установить PostgreSQL 17 + pgvector
# 11. Настроить streaming replication: Dubai → Hetzner
#     pg_basebackup -h dubai-primary -D /pgdata -U replicator -Fp -Xs -P

# === ФАЗА 4: Настройка Patroni + etcd ===

# 12. Установить etcd на 3 узла:
#     etcd-1: контейнер на Dubai app-сервере
#     etcd-2: контейнер на Hetzner AX102
#     etcd-3: Hetzner CPX11 (10.1.1.20)

# 13. Установить Patroni на Dubai primary и Hetzner replica
#     Dubai: failover_priority=2 (preferred primary)
#     Hetzner: failover_priority=1

# === ФАЗА 5: Бэкапы и мониторинг ===

# 14. Настроить cron: локальный snapshot каждые 2 часа
cat > /etc/cron.d/pg-snapshot << 'EOF'
0 */2 * * * postgres pg_basebackup -D /nvme/snapshots/latest -Fp -Xs --compress=lz4 --checkpoint=fast
EOF

# 15. Настроить pg_basebackup → Object Storage каждые 6 часов
# 16. Настроить WAL archiving → Object Storage

# === ФАЗА 6: Тестирование ===

# 17. Тест failover: kill primary → проверить Patroni promote на Hetzner
# 18. Тест verify-and-replay: burst 100 TPS + kill primary
# 19. Тест enrichment backfill: kill -9 postgres во время batch embedding
# 20. Тест failback: restore Dubai → switchover обратно

# Обновить Prometheus (App Server)
#    Добавить targets: dubai-shard-0, shard-replica-0, etcd-cluster
```

---

## 21. БЕЗОПАСНОСТЬ

### Сетевая изоляция

```
                    INTERNET
                        │
                        │ HTTPS (443) только
                        ▼
               ┌─────────────────┐
               │   App Server    │ ← Единственная точка входа (Hetzner)
               │   (10.1.0.2)    │
               └────────┬────────┘
                        │
                        │ Private Network (10.x.x.x)
                        │ Недоступно из интернета
                        ▼
┌───────────────────────────────────────────────────────────┐
│  HETZNER HELSINKI (private network):                        │
│  Apify (10.1.0.7)        — только private network         │
│  Photo Downloader (10.1.0.13) — только private network*   │
│  Ximilar Sync (10.1.0.14)    — только private network*    │
│  Scraper (10.1.0.3)      — только private network         │
│  Collage (10.1.0.8)      — только private network         │
│  Recognition (10.1.0.9)  — только private network         │
│  Ximilar GW (10.1.0.15) — только private network*         │
│  LLM Reranker (10.1.0.16) — только private network*       │
│  LLM Orchestrator (10.1.0.17) — только private network*   │
│  Mood Agent (10.1.0.11)  — только private network*        │
│  Voice (10.1.0.12)       — только private network*        │
│  Context Agent (10.1.0.19) — только private network*      │
│  Persona Agent (10.1.0.21) — только private network*      │
│  Staging DB (10.1.1.3)   — только private network         │
│  Production DB (10.1.1.2) — только private network        │
│  Shard Replica (10.1.1.10) — только private network       │
│  etcd-3 (10.1.1.20)      — только private network        │
│                                                            │
│  DUBAI (bare metal, private + VPN к Hetzner):              │
│  Dubai Shard Primary     — private network + VPN           │
│  etcd-1                  — на Dubai app-сервере            │
└───────────────────────────────────────────────────────────┘
```

**Dubai Shard Primary** — bare metal сервер в Dubai DC. Доступен только по private network (VPN tunnel к Hetzner). Нет публичного IP для PostgreSQL. SSH через VPN или dedicated management network.

**Модель безопасности User Data (3 уровня):**

```
Chat History (messages):
  content, memory_snippet, response_description → plaintext
  embedding, tsv                                → открыто
  Защита: private network + LUKS at-rest + strict PG roles + audit log

User Knowledge:
  Все чувствительные поля → AES-256 app-level encryption
  Защита: AES-256 + private network + LUKS at-rest

Tombstone Registry:
  Production DB (primary) + Object Storage (copy)
  Защита: Production DB на отдельном сервере от шардов
```

**Почему content не зашифрован app-level:** FTS (tsvector) работает только с открытым текстом. App-level AES сделал бы FTS и tsvector бесполезными. Компенсирующие меры: private network, LUKS, strict PG roles, audit log.

**Forget механика:**
- Soft forget: `is_forgotten = TRUE`, nullify embedding + snippet. Исключение из retrieval. `response_description` обнуляется только при явном "забудь этот образ".
- Hard delete: content → '[deleted]', nullify all + tombstone в Production DB. tsv пересчитывается автоматически.
- Post-restore: автоматический `apply_deletions.sql` из Production DB registry.

**Context Agent** имеет доступ к интернету для Weather API, но не принимает входящих из интернета.

Остальные серверы — правила те же, что в v5.

### Credentials

| Секрет | Где хранится | Кто использует |
|--------|--------------|----------------|
| S3 Access Key | .env | Photo Downloader, Collage |
| Staging DB passwords | .env | Apify, Photo Downloader, Ximilar Sync, Scraper, Collage |
| Production DB password | .env | Scraper, Recognition Orchestrator, LLM Orchestrator |
| Apify Token | .env | Apify Server |
| Ximilar API Token | .env | Ximilar Sync Server, Ximilar Gateway |
| Gemini API Key | .env | LLM Reranker |
| DeepSeek API Key | .env | Mood Agent Server |
| Gemini API Key (Mood fallback) | .env | Mood Agent Server |
| ElevenLabs API Key | .env | Voice Server |
| DeepSeek API Key (dialogue) | .env | LLM Orchestrator |
| Gemini API Key (dialogue) | .env | LLM Orchestrator |
| Claude API Key (dialogue) | .env | LLM Orchestrator |
| Qwen API Key (dialogue) | .env | LLM Orchestrator |
| Intelistyle API Key | .env | LLM Orchestrator |
| Embedding API Key (Cohere) | .env | LLM Orchestrator |
| Weather API Key | .env | Context Agent |
| Persona Agent Redis password | .env | Persona Agent (idempotency, buffer, locks) |
| Persona Agent Shard DB password | .env | Persona Agent (relationship_stage, blocks, deltas) |
| S3 Access Key (user-media) | .env | App Server |
| Dubai Shard DB password | .env | App Server, LLM Orchestrator |
| Master Encryption Key (AES-256, User Knowledge) | .env (RAM only) | Dubai Shard, LLM Orchestrator |
| Replication password | .env | Dubai Shard ↔ Hetzner Replica |
| Storage Box credentials (db01) | /root/.storagebox-creds | Production DB |
| LUKS passphrase (Dubai NVMe) | Offline (не на сервере) | Dubai Shard |
| etcd TLS certificates | /etc/etcd/ssl/ | etcd-1, etcd-2, etcd-3 |
| Patroni REST API password | .env | Patroni (Dubai + Hetzner) |

---

*Документ создан: 2026-02-01*
*Обновлено: 2026-02-16 — v6.2. Интеграция UNDE_Persona_Voice_Layer v0.7.0:*
*— Новый сервер: Persona Agent (10.1.0.21, CPX11) — единый источник правды для поведения аватара*
*— Persona Agent вызывается из LLM Orchestrator (Фаза 2, параллельно с embedding, ~15ms)*
*— 4 выхода: persona_directive → LLM, voice_params → Voice Server, avatar_state → Rive, render_hints → App*
*— voice_params теперь от Persona Agent (а не от Mood Agent напрямую). Зависимость: Mood → Persona (сенсор → актуатор)*
*— Новые таблицы на Dubai Shard: relationship_stage, persona_temp_blocks, signal_daily_deltas*
*— Async feedback loop: behavioral signals → SignalBuffer per exchange_id → conflict graph → conservative wins*
*— persona_contract: версионируемый Python-пакет (major version check), 29 golden tests*
*— Обновлены: LLM Orchestrator (pipeline, env, clients), Voice Server, Data Flow, мониторинг, деплой, безопасность*
*
*Обновлено: 2026-02-15 — v6.1. Интеграция решений из UNDE_Infrastructure_BD и UNDE_Smart_Context_Architecture:*
*— Chat History DB и User Knowledge DB объединены в Dubai User Data Shard (bare metal, 256 GB RAM, tmpfs primary + Hetzner AX102 replica)*
*— Streaming replication Dubai → Hetzner с Patroni + etcd для автоматического failover*
*— Client-side verify-and-replay для нулевой потери данных при failover (включая регенерацию response_description при replay)*
*— Application-level sharding по user_id*
*— Схема Chat History обновлена: pgvector (1024-dim embeddings), 64 hash-партиции, FTS (tsvector), memory_type + memory_confidence, precomputed memory_snippets, response_description (template-based), reply_to_id*
*— Hybrid Search: vector (role='user') + FTS (все роли, включая assistant-артефакты через response_description) с тематическим temporal decay и confidence-adjusted λ*
*— Добавлен Context Agent (10.1.0.19): геолокация, погода, культурный контекст, события, OpportunityMatcher*
*— Три слоя знания в ContextPack: User Knowledge (факты) + Semantic Retrieval (эпизоды) + Context Agent (мир вокруг)*
*— LLM Orchestrator обновлён: embedding client, Context Agent client, emotional filter, memory density cap, response_description (с обязательными токенами SKU/brand/store), reply_to_id (с защитой от неоднозначности)*
*— Soft/Hard Forget механика, Tombstone Registry в Production DB*
*Версия: 6.2*
