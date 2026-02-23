# UNDE Infrastructure — Каталог: сбор, фото, хранение

*Часть [TZ Infrastructure v6.2](../TZ_Infrastructure_Final.md). Серверы каталожного pipeline.*

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
STAGING_DB_URL=postgresql://scraper:xxx@10.1.0.8:6432/unde_staging

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
| **Private IP** | 10.1.0.9 |
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

- ❌ Скачивание фото (это Photo Downloader, 10.1.0.10)
- ❌ Upload фото в Object Storage (это Photo Downloader)
- ❌ Синхронизация с Ximilar (это Ximilar Sync, 10.1.0.11)

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
      - "10.1.0.9:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/apify/.env

# Apify
APIFY_TOKEN=apify_api_xxx

# Staging DB
STAGING_DB_URL=postgresql://apify:xxx@10.1.0.8:6432/unde_staging

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
| **Private IP** | 10.1.0.10 |
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
      - "10.1.0.10:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/photo-downloader/.env

# Staging DB
STAGING_DB_URL=postgresql://downloader:xxx@10.1.0.8:6432/unde_staging

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
| **Private IP** | 10.1.0.11 |
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
      - "10.1.0.11:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/ximilar-sync/.env

# Staging DB
STAGING_DB_URL=postgresql://ximilar:xxx@10.1.0.8:6432/unde_staging

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
| **Private IP** | 10.1.0.16 |
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
      - "10.1.0.16:9100:9100"
```

### Environment Variables

```bash
# /opt/unde/collage/.env

STAGING_DB_URL=postgresql://collage:xxx@10.1.0.8:6432/unde_staging
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
| **Private IP** | 10.1.0.8 |
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
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Expression UNIQUE: PG не поддерживает cast в UNIQUE constraint напрямую
CREATE FUNCTION to_date_immutable(ts TIMESTAMPTZ) RETURNS DATE AS $$
    SELECT (ts AT TIME ZONE 'UTC')::date;
$$ LANGUAGE SQL IMMUTABLE;

CREATE UNIQUE INDEX idx_raw_availability_unique_daily
    ON raw_availability(brand, store_id, product_id, to_date_immutable(fetched_at));

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
listen_addr = 10.1.0.8
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
| Apify Server | 10.1.0.9 | ✅ |
| Photo Downloader | 10.1.0.10 | ✅ |
| Ximilar Sync | 10.1.0.11 | ✅ |
| Scraper Server | 10.1.0.3 | ✅ |
| Collage Server | 10.1.0.16 | ✅ |
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

### Bucket: unde-user-media ✅

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
