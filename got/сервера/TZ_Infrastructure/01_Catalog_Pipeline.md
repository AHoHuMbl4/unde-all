# UNDE Infrastructure — Каталог: сбор, фото, хранение

*Серверы каталожного pipeline.*

> **🔄 Обновлено под [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md)** — 2 фото/SKU в Ximilar, новые поля в raw_products (index_scope, ximilar_synced_urls, ximilar_target_count), новые индексы availability.

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
| **availability_poll** | Каждый час (:00) | Mobile API → Staging DB (наличие в магазинах Dubai) |
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

# Dubai stores
DUBAI_ZARA_STORES=PLACEHOLDER_STORE_IDS
```

---

## 2. APIFY SERVER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | apify |
| **Private IP** | 10.1.0.9 |
| **Public IP** | 89.167.110.186 |
| **Тип** | Hetzner CX23 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/apify.git |
| **Статус** | ✅ Развёрнут, контейнеры running |

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
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file: .env
    deploy:
      resources:
        limits:
          memory: 2G

  apify-beat:
    build: .
    container_name: apify-beat
    restart: unless-stopped
    command: celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule
    env_file: .env
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.

### Environment Variables

```bash
# /opt/unde/apify/.env

APIFY_TOKEN=<Apify PAT token>
STAGING_DB_URL=postgresql://apify:<password>@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:<password>@10.1.0.4:6379/7
```

### Интеграция с Apify

**Паттерн:** Используем Apify Tasks (не актор напрямую). Task — преднастроенный запуск актора
с зафиксированными параметрами (URL, maxItems, region). Создаётся через UI Apify.

**Актор:** `datasaurus/zara` (и аналогичные для других брендов).

```python
# celery_app.py — маппинг бренд → Apify Task ID
BRAND_TASKS = {
    "zara": "z1psVOTyIKFdU5N9n",
    # "bershka": "TASK_ID_HERE",       # TODO: создать Task в Apify UI
    # "pullandbear": "TASK_ID_HERE",
    # "stradivarius": "TASK_ID_HERE",
    # "massimodutti": "TASK_ID_HERE",
    # "oysho": "TASK_ID_HERE",
}
```

### Формат данных от Apify (datasaurus/zara)

```json
{
  "id": 512913640,
  "reference": "02086797-V2026",
  "brand": "Zara",
  "name": "ZW COLLECTION ASYMMETRIC BLAZER",
  "description": "Blazer with a notched lapel collar...",
  "price": 69900,                    // ← в филсах! AED = price / 100 → 699.00
  "category": "woman-outerwear-padded",
  "colors": "Black",
  "sizes": "XS, S, M, L",
  "detailedComposition": { "parts": [...] },
  "colorsSizesImagesJSON": [         // ← массив по цветам
    {
      "id": "800",                   // color ID
      "name": "Black",
      "productId": 512918856,
      "xmedia": [                    // ← URL фото с {width} плейсхолдером
        "https://static.zara.net/.../02086797800-p.jpg?w={width}",
        "https://static.zara.net/.../02086797800-e1.jpg?w={width}",
        "https://static.zara.net/.../02086797800-e2.jpg?w={width}",
        "https://static.zara.net/.../02086797800-e3.jpg?w={width}"
      ],
      "sizes": [
        { "name": "XS", "sku": 512913641, "availability": "in_stock", "price": 69900 },
        { "name": "S",  "sku": 512913642, "availability": "in_stock", "price": 69900 }
      ]
    }
  ]
}
```

### Процесс сбора данных

```python
from apify_client import ApifyClient

def collect_brand(brand: str, task_id: str):
    client = ApifyClient(os.environ["APIFY_TOKEN"])

    # 1. Запустить преднастроенный Task (не actor.call!)
    task_client = client.task(task_id)
    run = task_client.call()  # блокирующий вызов, ждёт завершения

    # 2. Получить результаты
    dataset = client.dataset(run["defaultDatasetId"])

    for item in dataset.iterate_items():
        # 3. Извлечь фото URL'ы из всех цветов
        photo_urls = []
        for color in item.get("colorsSizesImagesJSON", []):
            for url in color.get("xmedia", [])[:5]:
                # Заменить {width} на конкретный размер
                photo_urls.append(url.replace("{width}", "1920"))

        # 4. Цена: fils → AED (÷100)
        price_aed = item["price"] / 100 if item.get("price") else None

        # 5. Записать в Staging DB (фото НЕ скачиваем, только URL'ы)
        db.execute("""
            INSERT INTO raw_products (source, external_id, brand, name, price,
                                      currency, category, colour, sizes,
                                      composition, description,
                                      original_image_urls, image_status,
                                      raw_data, scraped_at)
            VALUES (%s, %s, %s, %s, %s,
                    'AED', %s, %s, %s,
                    %s, %s,
                    %s, 'pending',
                    %s, NOW())
            ON CONFLICT (source, external_id) DO UPDATE SET
                name = EXCLUDED.name,
                price = EXCLUDED.price,
                original_image_urls = EXCLUDED.original_image_urls,
                raw_data = EXCLUDED.raw_data,
                scraped_at = EXCLUDED.scraped_at,
                updated_at = NOW()
        """, f"apify_{brand}", str(item["id"]), brand, item["name"],
             price_aed, item.get("category"), item.get("colors"),
             json.dumps(item.get("sizes", "")),
             json.dumps(item.get("detailedComposition")),
             item.get("description"),
             json.dumps(photo_urls), json.dumps(item))
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

## 3. PHOTO DOWNLOADER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | photo-downloader |
| **Private IP** | 10.1.0.10 |
| **Public IP** | 89.167.99.242 |
| **Тип** | Hetzner CX23 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/photo-downloader.git |
| **Статус** | ✅ Развёрнут, контейнеры running |

### Назначение

Скачивание фото товаров с сайтов брендов **через Bright Data residential proxy** и upload в Object Storage:
- Мониторит Staging DB на записи с `image_status='pending'`
- Скачивает фото по URL из метаданных через прокси (до 5 фото на товар)
- Загружает в Object Storage (`/originals/`) напрямую (без прокси)
- Обновляет статус на `image_status='uploaded'`

### Почему отдельный сервер

- **Самая хрупкая часть pipeline:** бренды блокируют IP, таймауты, rate limits, капчи
- **Самая тяжёлая по трафику:** ~47K товаров × 5 фото × 300KB = ~70 GB за один цикл
- **Разная частота отказов:** Apify API может работать, а скачивание фото — нет (и наоборот)
- **Residential proxy:** Bright Data — каждый запрос с нового residential IP, автоматическая ротация

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

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.

### Environment Variables

```bash
# /opt/unde/photo-downloader/.env

STAGING_DB_URL=postgresql://downloader:<password>@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:<password>@10.1.0.4:6379/7
PROXY_URL=http://brd-customer-hl_b9a99adf-zone-zara:<password>@brd.superproxy.io:33335
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=<access_key>
S3_SECRET_KEY=<secret_key>
S3_BUCKET=unde-images
DOWNLOAD_TIMEOUT=30
MAX_RETRIES=3
BATCH_SIZE=200
CONCURRENT_DOWNLOADS=10
```

### Bright Data Proxy

Все запросы на скачивание фото идут через Bright Data residential proxy.
Upload в S3 идёт напрямую (без прокси).

| Механизм | Описание |
|----------|----------|
| Провайдер | Bright Data (brd.superproxy.io:33335) |
| Тип | Residential — каждый запрос с нового IP |
| User-Agent | Ротация из 8 реальных браузерных строк |
| Rate limiting | Max 10 concurrent |
| Delay | 0.5–2 сек между запросами |
| Backoff | При 429/503: 5s → 15s → 45s → error |
| Timeout | 30 сек на фото, 120 сек на товар |

### Процесс скачивания

```python
import aiohttp, asyncio

async def download_pending():
    products = db.query("""
        SELECT id, external_id, brand, original_image_urls
        FROM raw_products
        WHERE image_status = 'pending'
        LIMIT 200
    """)

    proxy = os.environ["PROXY_URL"]

    async with aiohttp.ClientSession() as session:
        for product in products:
            try:
                uploaded_urls = []
                for i, url in enumerate(product.original_image_urls[:5]):
                    # Заменить {width} плейсхолдер
                    url = url.replace("{width}", "1920")

                    # Скачать через Bright Data residential proxy
                    async with session.get(url, proxy=proxy, ssl=False,
                                           timeout=aiohttp.ClientTimeout(total=30),
                                           headers={"User-Agent": random_ua()}) as resp:
                        data = await resp.read()

                    # Валидация (Pillow)
                    Image.open(io.BytesIO(data)).verify()

                    # Upload в S3 напрямую (без proxy)
                    key = f"originals/{product.brand}/{product.external_id}/{i+1}.jpg"
                    s3.upload_fileobj(io.BytesIO(data), S3_BUCKET, key)
                    uploaded_urls.append(
                        f"https://unde-images.hel1.your-objectstorage.com/{key}")

                db.execute("""
                    UPDATE raw_products
                    SET image_urls = %s, image_status = 'uploaded', updated_at = NOW()
                    WHERE id = %s
                """, json.dumps(uploaded_urls), product.id)
            except Exception as e:
                db.execute("""
                    UPDATE raw_products
                    SET image_status = 'error', error_message = %s, updated_at = NOW()
                    WHERE id = %s
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

## 4. XIMILAR SYNC SERVER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | ximilar-sync |
| **Private IP** | 10.1.0.11 |
| **Public IP** | 89.167.93.187 |
| **Тип** | Hetzner CX23 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/ximilar-sync.git |
| **Статус** | ✅ Развёрнут, контейнеры running |

### Назначение (🔄 v5.1: selective sync)

Синхронизация каталога товаров в Ximilar Collection (для Fashion Recognition Pipeline):
- Мониторит Staging DB на записи с `ximilar_status IN ('pending', 'partial')` и `image_status` IN ('uploaded', 'collage_ready')
- **🔄 v5.1:** Загружает только **2 фото/SKU** (on-model + front) вместо всех 5-7. Экономия -60% insert credits
- **🔄 v5.1:** Фильтрует по `index_scope = 'pilot'` — только пилотные бренды грузятся в Ximilar
- **🔄 v5.1:** Idempotent — отслеживает `ximilar_synced_urls`, не переотправляет уже загруженные фото
- Обновляет статус: `'pending'` → `'partial'` → `'synced'`

### Почему отдельный сервер

- **Другой внешний API:** Ximilar имеет свои rate limits, своё downtime — не связано с Apify или скачиванием фото
- **Другая частота:** может работать чаще или реже, независимо от сбора каталога
- **Изоляция:** проблемы с Ximilar не блокируют сбор данных и скачивание фото

### Почему CX23

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
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 1G

  ximilar-beat:
    build: .
    container_name: ximilar-beat
    restart: unless-stopped
    command: celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.

### Environment Variables

```bash
# /opt/unde/ximilar-sync/.env

# Staging DB
STAGING_DB_URL=postgresql://ximilar:<password>@10.1.0.8:6432/unde_staging

# Ximilar
XIMILAR_API_TOKEN=xxx                    # TODO: заполнить когда получим от Ximilar
XIMILAR_COLLECTION_ID=xxx               # TODO: заполнить когда получим от Ximilar
XIMILAR_API_URL=https://api.ximilar.com
XIMILAR_RATE_LIMIT=10

# Redis (Push Server)
REDIS_URL=redis://:<password>@10.1.0.4:6379/7

# Application
BATCH_SIZE=1000
```

### Процесс синхронизации (🔄 v5.1: selective, idempotent)

```python
# Псевдокод (🔄 v5.1: 2 фото/SKU, index_scope filter, idempotency)

def sync_to_ximilar():
    """Загрузить 2 фото/SKU (on-model + front) в Ximilar Collection.
    🔄 v5.1: только пилотные бренды (index_scope='pilot'),
    idempotent через ximilar_synced_urls, progressive ingestion."""
    products = db.query("""
        SELECT id, external_id, brand, name, category, price,
               image_urls, ximilar_synced_urls, ximilar_target_count
        FROM raw_products
        WHERE image_status IN ('uploaded', 'collage_ready')
          AND ximilar_status IN ('pending', 'partial')
          AND index_scope = 'pilot'                    -- 🔄 v5.1: только пилотные
        LIMIT 1000
    """)

    for product in products:
        try:
            # 🔄 v5.1: отправляем только target_count фото (default: 2)
            target = product.ximilar_target_count or 2
            images = product.image_urls[:target]
            synced = set(product.ximilar_synced_urls or [])

            # 🔄 v5.1: idempotency — не переотправлять уже загруженные
            to_send = [url for url in images if url not in synced]

            if to_send:
                ximilar.add_images(
                    collection_id=XIMILAR_COLLECTION_ID,
                    images=[{"url": url} for url in to_send],
                    metadata={
                        "sku_id": product.external_id,
                        "brand": product.brand,
                        "name": product.name,
                        "category": product.category,
                        "price": str(product.price)
                        # 🔄 v5.1: НЕТ store/floor — глобальные метаданные
                    }
                )

            new_synced = list(synced | set(to_send))
            synced_count = len(new_synced)

            # 🔄 v5.1: partial (отправлено < target) или synced (все target фото)
            new_status = 'synced' if synced_count >= target else 'partial'

            db.execute("""
                UPDATE raw_products
                SET ximilar_status = %s,
                    ximilar_synced_urls = %s,
                    ximilar_synced_at = NOW()
                WHERE id = %s
            """, new_status, json.dumps(new_synced), product.id)

        except Exception as e:
            db.execute("""
                UPDATE raw_products
                SET ximilar_status = 'error', error_message = %s
                WHERE id = %s
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

## 5. COLLAGE SERVER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | collage |
| **Private IP** | 10.1.0.16 |
| **Public IP** | 65.109.172.52 |
| **Тип** | Hetzner CX33 |
| **vCPU** | 4 |
| **RAM** | 8 GB |
| **Disk** | 80 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/collage.git |
| **Статус** | ✅ Развёрнут, контейнеры running |

### Назначение

Подготовка фото для virtual try-on — один коллаж на SKU:
- Скачивание **всех** оригиналов конкретного SKU из Object Storage
- Склейка в горизонтальный коллаж (оригинальное разрешение, JPEG q=95, 4:4:4)
- Upload коллажа в Object Storage
- Обновление collage_url в Staging DB

### Что такое коллаж

```
Все фото одного SKU (image_urls из raw_products):
┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐
│  1  │ │  2  │ │  3  │ │  4  │  ... сколько есть
│перед│ │ зад │ │ бок │ │детал│
└─────┘ └─────┘ └─────┘ └─────┘
                    │
                    ▼ Горизонтальная склейка (без уменьшения!)
    ┌───────────────────────────────┐
    │ ┌───┐ ┌───┐ ┌───┐ ┌───┐     │
    │ │ 1 │ │ 2 │ │ 3 │ │ 4 │ ... │
    │ └───┘ └───┘ └───┘ └───┘     │
    │  JPEG q=95, оригинальное     │
    │  разрешение, 4:4:4           │
    └───────────────────────────────┘
                    │
                    ▼
            fal.ai try-on получает
            все ракурсы SKU в одном файле

ВАЖНО: разрешение НЕ уменьшается. Качество коллажа
напрямую влияет на качество virtual try-on.
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
    command: celery -A app.celery_app worker --loglevel=info --concurrency=2
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
    deploy:
      resources:
        limits:
          memory: 4G
        reservations:
          memory: 1G

  collage-beat:
    build: .
    container_name: collage-beat
    restart: unless-stopped
    command: celery -A app.celery_app beat --loglevel=info --schedule=/app/data/celerybeat-schedule
    env_file: .env
    volumes:
      - ./app:/app/app
      - ./data:/app/data
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.

### Environment Variables

```bash
# /opt/unde/collage/.env

STAGING_DB_URL=postgresql://collage:<password>@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:<password>@10.1.0.4:6379/8
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=<access_key>
S3_SECRET_KEY=<secret_key>
S3_BUCKET=unde-images
BATCH_SIZE=100
COLLAGE_QUALITY=95
```

### Процесс обработки

```python
def process_sku(product_id: int):
    """Склеить все фото одного SKU в горизонтальный коллаж."""
    product = db.query(
        "SELECT id, external_id, brand, image_urls FROM raw_products "
        "WHERE id = %s AND image_status = 'uploaded'", product_id)

    # Скачать ВСЕ оригиналы этого SKU из S3
    images = [Image.open(s3.download(url)) for url in product.image_urls]

    # Привести к одной высоте (max), сохраняя пропорции
    target_height = max(img.height for img in images)
    resized = []
    for img in images:
        ratio = target_height / img.height
        resized.append(img.resize((int(img.width * ratio), target_height), Image.LANCZOS))

    # Склеить по горизонтали
    total_width = sum(r.width for r in resized)
    collage = Image.new('RGB', (total_width, target_height), (255, 255, 255))
    x = 0
    for r in resized:
        collage.paste(r, (x, 0))
        x += r.width

    # JPEG q=95, subsampling=0 (4:4:4) — максимальное качество
    buf = BytesIO()
    collage.save(buf, format='JPEG', quality=95, subsampling=0)

    # Upload и обновить статус
    key = f"collages/{product.brand}/{product.external_id}.jpg"
    s3.upload_fileobj(buf, S3_BUCKET, key)
    collage_url = f"https://unde-images.hel1.your-objectstorage.com/{key}"
    db.execute(
        "UPDATE raw_products SET collage_url = %s, image_status = 'collage_ready', "
        "updated_at = NOW() WHERE id = %s", collage_url, product.id)
```

---

## 6. STAGING DB SERVER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | staging-db |
| **Private IP** | 10.1.0.8 |
| **Public IP** | 89.167.91.76 |
| **Тип** | Hetzner CPX22 |
| **vCPU** | 4 |
| **RAM** | 8 GB |
| **Disk** | 80 GB SSD |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/Staging-DB.git |
| **Статус** | ✅ Развёрнут, PG17 + PgBouncer running |

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
    currency VARCHAR(10) DEFAULT 'AED',
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
        -- pending → partial → synced | error
        -- 🔄 v5.1: partial = отправлено < target фото (progressive ingestion)
    ximilar_synced_at TIMESTAMPTZ,

    -- 🔄 v5.1: новые поля для selective sync и progressive ingestion
    index_scope TEXT DEFAULT 'off',
        -- 'pilot' = грузить в Ximilar, 'pgvector' = только pgvector, 'off' = не индексировать
    ximilar_synced_urls JSONB DEFAULT '[]',
        -- URL'ы уже отправленные в Ximilar (idempotency)
    ximilar_target_count SMALLINT DEFAULT 2,
        -- сколько фото грузить (2 по умолчанию, повышается progressive ingestion)
    
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

-- Физические магазины Dubai
CREATE TABLE raw_stores (
    id SERIAL PRIMARY KEY,
    brand VARCHAR(50) NOT NULL,
    store_id INTEGER NOT NULL,
    name TEXT,
    address TEXT,
    city VARCHAR(100) DEFAULT 'Dubai',
    country VARCHAR(10) DEFAULT 'AE',
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

-- 🔄 v5.1: индексы для availability post-filter (Step 3.5 Recognition Pipeline)
CREATE INDEX IF NOT EXISTS idx_raw_availability_lookup
    ON raw_availability (brand, store_id, product_id, fetched_at DESC);
CREATE INDEX IF NOT EXISTS idx_raw_availability_brand_product
    ON raw_availability (brand, product_id);
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

### Расчёт объёма (MVP — Dubai, Inditex)

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
