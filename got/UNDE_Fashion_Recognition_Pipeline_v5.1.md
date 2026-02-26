# UNDE — Fashion Recognition Pipeline v5.1

## Street Photo → Detection → Tagging → Search → Availability → Rerank → SKU Match

**Quality-First Edition с оптимизацией масштабирования**

| Параметр | Значение |
|----------|----------|
| Задача | Юзер фотографирует outfit на улице → UNDE определяет каждую вещь → находит похожие SKU в каталоге ТЦ → показывает с ценой, магазином и навигацией |
| Объём | Phase 1: 1 000 юзеров, ~5–10K фото/мес, ~3–5 items/фото |
| Бюджет | Phase 1: €150–200/мес (Ximilar) + $50–150/мес (Gemini) |
| Latency | 3–6 сек полный pipeline (progressive loading) |
| Accuracy | Phase 1: 85–90% TOP-3 (Ximilar search only). Phase 2+: 90–95% TOP-3 (conditional dual retrieval + visual rerank) |
| Масштабирование | Новый ТЦ с существующими брендами = $0 |

Февраль 2026 | Версия 5.1

---

## Ключевые изменения v5.1

| Было (v1.0) | Стало (v5.1) | Эффект |
|-------------|-------------|--------|
| Индексация per-ТЦ | Глобальная индексация per-бренд | Новый ТЦ = $0 если бренды есть |
| Ximilar Search only | Dual retrieval: pgvector + Ximilar | Ансамбль 9.5+/10, новые бренды $0 |
| Tag-all всегда (60 cr/фото) | Tagging on-demand (40–60% запросов) | −40–60% tagging credits |
| 5–7 фото/SKU в Ximilar | 2 фото/SKU в Ximilar + все 5–7 в pgvector | −60% insert credits |
| TOP-10 search | TOP-50 search → availability filter → TOP-10 rerank | Корректная выдача per-ТЦ |
| Нет фильтра наличия | Post-filter по raw_availability (новый Step 3.5) | Только товары в наличии |
| 13.15M credits/мес | 2.9–5.0M credits/мес (10K юзеров) | Экономия 60–80% |

---

## Архитектура данных: почему масштабирование = $0

### Существующая структура Staging DB (10.1.0.8)

Три таблицы уже обеспечивают глобальную дедупликацию SKU:

```
raw_products (глобальный каталог)          raw_stores (справочник магазинов)
┌─────────────────────────────┐            ┌──────────────────────────────┐
│ id, source, external_id     │            │ id, brand, store_id          │
│ brand, name, price, currency│            │ name, address, city, country │
│ category, colour, sizes     │            │ mall_name                    │
│ image_urls (JSONB)          │            │ latitude, longitude          │
│ collage_url                 │            └──────────────────────────────┘
│ ximilar_status              │
│ UNIQUE(source, external_id) │            raw_availability (наличие per-day)
└─────────────────────────────┘            ┌──────────────────────────────────┐
                                           │ brand, store_id, product_id      │
                                           │ sizes_in_stock (JSONB)           │
                                           │ fetched_at                       │
                                           │ UNIQUE(brand, store_id,          │
                                           │   product_id, date)              │
                                           └──────────────────────────────────┘
```

**Принцип**: SKU (Zara артикул 12345) существует в `raw_products` **один раз**, независимо от количества ТЦ. Наличие в конкретном магазине — отдельная таблица `raw_availability`. Магазин привязан к ТЦ через `raw_stores.mall_name`.

**Следствие**: Подключение нового ТЦ = добавить строки в `raw_stores` + начать poll `raw_availability`. Если бренды уже проиндексированы — **никакого повторного insert** в Ximilar или pgvector.

### Стоимость подключения нового ТЦ

| Сценарий | Действие | Ximilar credits | Стоимость |
|----------|---------|----------------|-----------|
| ТЦ с теми же 6 брендами (Inditex) | `raw_stores` + availability poll | 0 | **$0** |
| ТЦ с 5 новыми брендами | Парсинг + photo download + ximilar-sync новых | ~50K img × 10 = 500K | **~€150** |
| ТЦ со 100% новыми брендами | Полная индексация | ~100K img × 10 = 1M | **~€300** |
| 5-й ТЦ (90% overlap брендов) | Только уникальные бренды | ~5K img × 10 = 50K | **~€15** |

### Текущие пилотные бренды (6 шт, все Inditex)

| Бренд | ~SKU | Источник |
|-------|------|----------|
| Zara | ~15K | Apify + Mobile API |
| Bershka | ~8K | Apify + Mobile API |
| Pull&Bear | ~6K | Apify + Mobile API |
| Stradivarius | ~8K | Apify + Mobile API |
| Massimo Dutti | ~5K | Apify + Mobile API |
| Oysho | ~5K | Apify + Mobile API |
| **Итого** | **~47K SKU** | |

Фото: 5–7 на SKU, парсятся с сайтов брендов. Включают фото на моделях — критично для quality (минимальный cross-domain gap со street-фото).

---

## Pipeline Overview

```
📸 Street Photo
    │
    ▼
Step 1: Detection & Crop (Ximilar)              200–500ms
    │   Bounding boxes + crops + категории
    ▼
Step 2: Tagging (ON-DEMAND)                      0–1000ms
    │   Ximilar атрибуты (если search неуверенный)
    │   + Gemini контекст (стиль, occasion)
    ▼
Step 3: Visual Search (DUAL RETRIEVAL)           200–500ms
    │   pgvector kNN (primary, бесплатно)
    │   + Ximilar Search (booster, credits)
    │   → TOP-50 кандидатов
    ▼
Step 3.5: Availability Filter (NEW)              <10ms
    │   Post-filter по raw_availability
    │   Только товары в наличии в ТЦ юзера
    │   → TOP-10–20 кандидатов
    ▼
Step 4: Visual Rerank (Gemini Vision)            1–2s
    │   Crop vs catalog photo → score 0–1
    │   Combined: 0.7 × visual + 0.3 × semantic
    ▼
🛍️ Результат: TOP-5 SKU + магазин + этаж + цена + наличие
```

Суммарная latency: 3–6 сек. Detection показывается мгновенно (~0.5 сек), результаты подгружаются асинхронно с progressive loading.

---

## Step 0: Каталог — глобальный индекс

### Что уже готово

| Параметр | Статус |
|----------|--------|
| Фото на SKU | 5–7 фото/SKU (фронт, спина, детали, на модели) |
| Фото на моделях | Есть. Ключевое преимущество: street → on-model = минимальный cross-domain gap |
| Источник | Парсинг с официальных сайтов брендов (Apify) |
| Хранилище | S3 Object Storage: `originals/{brand}/{external_id}/{N}.jpg` |
| Collage | Горизонтальная склейка всех фото для try-on: `collages/{brand}/{external_id}.jpg` |

### Индексация: два хранилища

| Хранилище | Что индексируем | Фото/SKU | Стоимость | Назначение |
|-----------|----------------|----------|-----------|------------|
| **Ximilar Collection** | Пилотные бренды | 2 (on-model + front) | 10 credits/фото | Quality booster для search |
| **pgvector (unde_ai)** | ВСЕ бренды | 5–7 (все ракурсы) | $0 | Primary search + новые бренды |

**Ключевое**: в pgvector кладём **все фото** (это бесплатно), что обеспечивает матчинг по лучшему ракурсу — аналогично тому, как это делает Ximilar.

### Метаданные в индексе (глобальные, без mall/store)

```json
{
  "brand": "zara",
  "external_id": "12345",
  "name": "Oversized Bomber Jacket",
  "category": "outerwear",
  "price": 399.00,
  "currency": "AED",
  "colour": "khaki",
  "composition": "100% nylon"
}
```

> **SKU key**: `(brand, external_id)` — единый составной ключ по всему pipeline. Совпадает с `UNIQUE(source, external_id)` в `raw_products` (source ≈ brand).
>
> **Каноникализация brand**: `brand` хранится в lowercase canonical form (`zara`, `bershka`, `pull_bear`). Правило применяется при парсинге (Apify/scraper) и проверяется constraint'ом или trigger'ом. Иначе `"Zara" != "zara"` тихо ломает JOIN'ы по availability и дедупликацию в pgvector.

**Нет** `store`, `floor`, `mall_name` — это бизнес-логика, подтягивается после поиска из `raw_availability` + `raw_stores`.

### ximilar-sync (10.1.0.11): логика синхронизации

```
SELECT FROM raw_products
WHERE ximilar_status IN ('pending', 'partial')  -- partial: target повышен, нужна догрузка
  AND image_status IN ('uploaded', 'collage_ready')
  AND index_scope = 'pilot'              -- NEW: фильтр по scope
→ Для каждого product:
    images = image_urls[:ximilar_target_count]   -- NEW: 2 по умолчанию
    to_send = images - ximilar_synced_urls       -- NEW: не переотправлять
    → POST /recognition/v2/collectImage (to_send + metadata)
    → synced_count = len(ximilar_synced_urls + to_send)
    → UPDATE ximilar_status = CASE
          WHEN synced_count >= ximilar_target_count THEN 'synced'
          ELSE 'partial'
        END,
        ximilar_synced_urls += to_send
```

### Новые поля в raw_products (миграция P0)

```sql
ALTER TABLE raw_products ADD COLUMN index_scope text DEFAULT 'off';
ALTER TABLE raw_products ADD COLUMN ximilar_synced_urls jsonb DEFAULT '[]';
ALTER TABLE raw_products ADD COLUMN ximilar_target_count smallint DEFAULT 2;
```

- `index_scope`: `'pilot'` — грузить в Ximilar; `'pgvector'` — только pgvector; `'off'` — не индексировать
- `ximilar_status`: `'pending'` → `'partial'` (отправлено < всех фото) → `'synced'` (все target фото отправлены). Progressive ingestion повышает target → статус снова `'partial'` до догрузки
- `ximilar_synced_urls`: список URL, уже отправленных в Ximilar (idempotency)
- `ximilar_target_count`: сколько фото грузить (2 по умолчанию, повышается progressive ingestion)

---

## Step 1: Detection & Crop

**Задача**: найти все предметы одежды на фото, вырезать каждый отдельно.

| Параметр | Значение |
|----------|----------|
| Сервис | Ximilar Fashion Detection API |
| Gateway | ximilar-gw (10.1.0.12), endpoint `POST /detect` |
| Качество | 9.5/10. Специализирован на fashion. Отличает кардиган от жилетки, crop-top от обычного |
| Output | Bounding boxes + готовые crops + категория (top, bottom, shoes, bag, accessory...) |
| Стоимость | 5 credits/фото. Входит в Ximilar Business тариф |
| Latency | 200–500ms |

**Не меняется в v5.1.** Detection — фундамент pipeline, Ximilar даёт лучшее качество на рынке.

### Phase 3 (Scale): YOLOv8 + DeepFashion2

При масштабе >10K юзеров можно заменить на self-hosted YOLOv8 fine-tuned на DeepFashion2:
- Качество: 9/10 (mAP 94.6%)
- Стоимость: $30–50/мес (Hetzner GPU), модель open-source
- Latency: 50–200ms (в 5x быстрее Ximilar)
- Нужен ML-инженер на 1–2 недели для fine-tune

---

## Step 2: Tagging & Description (ON-DEMAND)

**Задача**: для каждого crop — тип, цвет, материал, паттерн, стиль, сезон, occasion.

### Стратегия v5.1: Conditional Tagging

Вместо вызова `/tag` на каждый запрос — вызываем **только когда search неуверенный**:

```
1. /detect → crops
2. Для каждого crop → /search (pgvector ± Ximilar booster) → TOP-50 кандидатов
3. ПРОВЕРКА уверенности по ИТОГОВОМУ топу:
   - Если pgvector уверен (Ximilar НЕ вызывался): проверяем pgvector scores
   - Если Ximilar вызывался: проверяем normalized combined scores
   top1_score ≥ CONFIDENCE_THRESHOLD И margin ≥ MARGIN?
   → ДА (уверенный): tagging не нужен, сразу на availability filter + rerank
   → НЕТ (неуверенный): вызываем Ximilar /tag + Gemini /tag → pre-filter + rerank
```

> **Score normalization — два этапа**:
>
> **Этап 1 — Gating (пороги ДО смешивания)**: каждый retrieval оценивается по своей шкале:
> - pgvector: cosine similarity 0–1, `CONFIDENCE_THRESHOLD = 0.80`, `MARGIN = 0.10`
> - Ximilar: score 0–100, `CONFIDENCE_THRESHOLD = 80`, `MARGIN = 10`
> - Gating решает: вызывать ли Ximilar booster, нужен ли tagging
>
> **Этап 2 — Merge (combined score для сортировки ПОСЛЕ смешивания)**: если оба retrieval вызывались:
> - `normalized_score = pgvector_score × 0.5 + ximilar_score/100 × 0.5`
> - Используется ТОЛЬКО для итоговой сортировки и дедупликации TOP-50, НЕ для gating
>
> **Важно**: пороги калибруются на реальных данных A/B теста (Phase 2e). Начальные значения — гипотеза.

По опыту: 40–60% запросов будут "уверенными". Tagging credits сокращаются вдвое.

### Два источника атрибутов

| Источник | Что даёт | Когда вызывается | Стоимость |
|----------|---------|-----------------|-----------|
| **Ximilar Tagging** | Pantone цвет (#BDB76B), точный материал (нейлон ripstop vs полиэстер), принт (leopard vs camo) | On-demand: 40–60% запросов | 15 credits/item (Tag single) |
| **Gemini 2.5 Flash** | Стиль (streetwear vs preppy), occasion (office, date), brand_style (oversized, cropped), сезон | Всегда (параллельно с search) | $50–150/мес фикс |

### Combined output (для неуверенных запросов)

```json
{
  "type": "bomber_jacket",
  "color": "khaki #BDB76B",
  "material": "nylon ripstop",
  "pattern": "solid",
  "style": "streetwear",
  "occasion": "casual/urban",
  "brand_style": "oversized drop-shoulder",
  "season": "autumn/spring"
}
```

### Зачем два источника

1. Ximilar атрибуты → точный **pre-filter** перед rerank (отсеять чёрные куртки если ищем хаки)
2. Gemini контекст → усиливает **visual rerank** на Step 4
3. Полное описание для **ответа пользователю**

### Серверы

| Сервис | Сервер | IP | Endpoint |
|--------|--------|-----|---------|
| Ximilar Tagging | ximilar-gw | 10.1.0.12 | `POST /tag` |
| Gemini Tagging | llm-reranker | 10.1.0.13 | `POST /tag` |

---

## Step 3: Visual Search — Dual Retrieval

**Задача**: для каждого crop → найти TOP-50 визуально похожих SKU из глобального каталога.

### Архитектура: pgvector primary + conditional Ximilar booster

```
crop → pgvector kNN (primary, всегда)      → TOP-50   (бесплатно, 5–20ms)
    │
    ├── GATING: pgvector_confident?
    │   Условие: top1_score ≥ CONFIDENCE_THRESHOLD (0.80)
    │            И (top1_score - top2_score) ≥ MARGIN (0.10)
    │
    │   → ДА (уверенный): сразу на Step 3.5 (Ximilar НЕ вызываем, экономия 10 cr)
    │   → НЕТ (плотный топ или низкий score):
    │          + Ximilar Fashion Search   → TOP-30   (credits, 200–500ms)
    │          → Объединение → дедупликация по (brand, external_id) → TOP-50
    │
    ├── После Step 3.5 осталось < MIN_CANDIDATES (напр. 3)?
    │   → ДА и Ximilar ещё НЕ вызывался: полный запрос Ximilar Search (TOP-50)
    │   → ДА и Ximilar уже вызывался: взять следующие кандидаты из его ответа
    │                                  или повторить с увеличенным лимитом (TOP-100)
    │
    → Step 3.5: Availability filter
```

> **Условный booster**: Ximilar Search вызывается только при неуверенном pgvector (низкий score ИЛИ плотный топ — margin < 0.10) ИЛИ после availability filter, если осталось мало кандидатов. Экономия 40–60% search credits по сравнению с always-dual.
>
> **Дозапрос после availability**: если Ximilar уже вызывался на предыдущем шаге — повторный запрос с теми же параметрами не даст новых результатов. Нужно либо расширить лимит, либо использовать уже полученные, но не вошедшие в TOP-50 результаты.

### pgvector (Primary) — Phase 2.5

| Параметр | Значение |
|----------|----------|
| Модель | FashionCLIP 2.0 (512-dim), ONNX Runtime |
| Сервер inference | vmi1150256 (12 ядер AMD EPYC, 47GB RAM, AVX2, CPU) |
| Сервер БД | Production DB (10.1.1.2), база `unde_ai`, pgvector 0.8.1 |
| Фото/SKU в индексе | **Все 5–7** (per-image, не усреднённые) — бесплатно |
| Latency (inference) | 100–300ms на CPU с ONNX |
| Latency (kNN) | 5–20ms |
| Стоимость | $0 (собственное железо) |
| Качество | 8.5–9/10 (с on-model каталогом, без fine-tune) |
| Новый бренд | Batch embed на CPU: ~2–4 часа для 47K SKU, **$0** |

### Таблица embeddings

```sql
-- Production DB (10.1.1.2), база unde_ai

CREATE TABLE sku_image_embeddings (
    id bigserial PRIMARY KEY,
    sku_id text NOT NULL,            -- raw_products.external_id
    brand text NOT NULL,             -- raw_products.brand (составной ключ с sku_id)
    image_url text NOT NULL,
    image_rank smallint NOT NULL,    -- 0..6 (порядок фото)
    image_hash text NOT NULL,        -- SHA256 содержимого, для idempotency
    embedding vector(512),           -- FashionCLIP dimension
    model_version text NOT NULL DEFAULT 'fashionclip-2.0',
    metadata jsonb,                  -- price, category, colour
    created_at timestamptz DEFAULT now(),

    -- Idempotency: повторный batch-прогон НЕ создаёт дубликаты
    UNIQUE (brand, sku_id, image_hash, model_version)
);

CREATE INDEX sku_image_embeddings_hnsw
    ON sku_image_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE INDEX sku_image_embeddings_brand
    ON sku_image_embeddings (brand);

-- Runtime:
-- SET hnsw.ef_search = 40;  (95% recall, 5–20ms)

-- Brand pre-filter: kNN только по брендам, присутствующим в ТЦ юзера
-- НЕ фильтр availability (это post-filter), а фильтр ассортимента ТЦ — recall не страдает
-- SELECT ... FROM sku_image_embeddings
-- WHERE brand IN (SELECT DISTINCT brand FROM raw_stores WHERE mall_name = :user_mall)
-- ORDER BY embedding <=> :query_embedding LIMIT 50;

-- Batch upsert (idempotent):
-- INSERT INTO sku_image_embeddings (brand, sku_id, image_url, image_rank, image_hash, embedding, model_version, metadata)
-- VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
-- ON CONFLICT (brand, sku_id, image_hash, model_version)
-- DO UPDATE SET embedding = EXCLUDED.embedding, image_url = EXCLUDED.image_url, metadata = EXCLUDED.metadata;
```

**Per-image, не per-SKU**: каждое фото — отдельная строка. pgvector вернёт лучший ракурс автоматически (как Ximilar). При 47K SKU × 5 фото = ~235K строк, ~10–15 GB индекса. Production DB (64 GB RAM) — легко.

> **Мониторинг размера индекса** (после batch P2c и регулярно):
> ```sql
> -- Размер HNSW индекса
> SELECT pg_size_pretty(pg_relation_size('sku_image_embeddings_hnsw')) AS hnsw_size;
>
> -- Размер таблицы + все индексы
> SELECT pg_size_pretty(pg_total_relation_size('sku_image_embeddings')) AS total_size;
>
> -- Проверка latency kNN (должно быть <20ms)
> EXPLAIN ANALYZE
> SELECT sku_id, brand, 1 - (embedding <=> $1::vector) AS score
> FROM sku_image_embeddings
> ORDER BY embedding <=> $1::vector
> LIMIT 50;
> ```
> При >500K строк: мониторить latency, при деградации — рассмотреть partitioning по brand.

> **Initial load (P2c)**: для первой загрузки ~235K строк — создать таблицу БЕЗ HNSW индекса, сделать bulk insert (батчами по 1000–2000 строк через `execute_values` / `COPY`), затем `CREATE INDEX ... USING hnsw`. Это в ~10x быстрее, чем вставлять при существующем индексе. После: `VACUUM ANALYZE sku_image_embeddings`.

### Ximilar Fashion Search (Booster)

| Параметр | Значение |
|----------|----------|
| Сервис | Ximilar Fashion Search API |
| Gateway | ximilar-gw (10.1.0.12), endpoint `POST /search` |
| Качество | 9–9.5/10 |
| Фото/SKU в Collection | 2 (on-model + front) — оптимизация credits |
| Стоимость | 10 credits/запрос |
| Latency | 200–500ms |

### Error handling в ximilar-gw

```python
# Pseudo: /search endpoint в gw
async def search(crop_embedding, mode=SEARCH_BACKEND):
    pgvector_results = await pgvector_knn(crop_embedding, limit=50)

    if mode == "conditional" and not pgvector_confident(pgvector_results):
        try:
            ximilar_results = await ximilar_search(crop_image, limit=100)
        except (XimilarTimeout, XimilarError) as e:
            log_to_posthog("ximilar_search_error", error=str(e))  # PostHog 10.1.1.30
            ximilar_results = []  # graceful fallback → pgvector only

    return merge_and_deduplicate(pgvector_results, ximilar_results)
```

> **Принцип**: Ximilar outage НЕ должен ронять search. pgvector — self-hosted, всегда доступен. Ошибки Ximilar логируются в PostHog (10.1.1.30) для мониторинга.

### Feature flag в ximilar-gw

```
Переменная: SEARCH_BACKEND = ximilar | pgvector | conditional | dual

- ximilar:      только Ximilar API (Phase 1, MVP)
- pgvector:     только pgvector kNN (Phase 3, экономия credits)
- conditional:  pgvector primary + Ximilar on-demand booster (Phase 2, РЕКОМЕНДУЕМЫЙ)
- dual:         оба ВСЕГДА параллельно → объединение (max quality, max credits)
```

> **По умолчанию Phase 2+: `conditional`** — это основной режим, описанный выше. Режим `dual` (always-parallel) доступен для A/B тестов и edge-cases, но НЕ является рабочим режимом из-за расхода credits на каждый запрос.

Формат ответа `/search` не меняется — Recognition Orchestrator (10.1.0.14) не трогаем.

### Conditional booster: почему это лучше always-dual

- 40–60% запросов pgvector уверен (top1 > threshold) → Ximilar не нужен, экономия 10 cr/запрос
- Для оставшихся 40–60% — Ximilar дополняет слепые пятна pgvector
- После availability filter мало кандидатов → дозапрос Ximilar расширяет пул
- Для новых брендов (ещё не в Ximilar): pgvector — единственный источник
- Ансамбль (когда активен) даёт +5–10% к точности vs каждый по отдельности

---

## Step 3.5: Availability Post-Filter (NEW)

**Задача**: из TOP-50 глобальных кандидатов оставить только товары, которые реально есть в наличии в ТЦ юзера.

### Почему post-filter, а не pre-filter

- Search-индекс (Ximilar/pgvector) **не знает** про наличие — metadata не содержит store/mall
- Фильтрация по наличию в индексе убила бы recall
- Availability меняется ежечасно — перестраивать индекс невозможно
- Post-filter: <10ms, никакого влияния на latency

### SQL-запрос (один batch для всех кандидатов)

```sql
-- DISTINCT ON гарантирует последнюю запись per (brand, store_id, product_id)
-- Hourly poll может дать несколько строк за сутки — берём самую свежую
WITH latest AS (
    SELECT DISTINCT ON (brand, store_id, product_id)
        brand, store_id, product_id, sizes_in_stock, fetched_at
    FROM raw_availability
    WHERE fetched_at > now() - interval '24 hours'
    ORDER BY brand, store_id, product_id, fetched_at DESC
)
SELECT
    l.product_id,
    l.brand,
    rs.name AS store_name,
    rs.address,
    rs.mall_name,
    l.sizes_in_stock
FROM (VALUES
    ('zara', '12345'), ('hm', '67890')   -- TOP-50 из search
) AS c(brand, product_id)
JOIN latest l
    ON l.brand = c.brand AND l.product_id = c.product_id
JOIN raw_stores rs
    ON rs.brand = l.brand AND rs.store_id = l.store_id
WHERE rs.mall_name = :user_mall            -- ТЦ юзера
  AND l.sizes_in_stock != '[]'::jsonb      -- что-то в наличии
```

> **Почему DISTINCT ON**: hourly poll записывает несколько строк на `(brand, store_id, product_id)` в сутки (daily UNIQUE — по дате, не по часу). Без DISTINCT ON можно получить дубли кандидатов или устаревший `sizes_in_stock`. CTE `latest` гарантирует ровно одну (самую свежую) запись на комбинацию.
>
> **Scale optimization (Phase 3)**: при росте данных (много магазинов × hourly poll) CTE `DISTINCT ON` может замедлиться. Fast path — отдельная таблица `availability_latest` с upsert по `(brand, store_id, product_id)` при каждом poll. Тогда Step 3.5 = простой JOIN без CTE, гарантированно <5ms. `raw_availability` остаётся как history/аудит.

> **Рекомендуемые индексы** (проверить на staging-db и production):
> ```sql
> -- Для DISTINCT ON + ORDER BY fetched_at DESC в CTE latest
> CREATE INDEX IF NOT EXISTS idx_raw_availability_lookup
>     ON raw_availability (brand, store_id, product_id, fetched_at DESC);
>
> -- Для JOIN из VALUES по (brand, product_id)
> CREATE INDEX IF NOT EXISTS idx_raw_availability_brand_product
>     ON raw_availability (brand, product_id);
> ```
> Первый индекс покрывает `DISTINCT ON` без дополнительной сортировки. Второй — для быстрого JOIN.

Latency: <10ms (с обоими индексами — <5ms).

### Логика фильтрации

```
TOP-50 кандидатов из search
    │
    ▼
Batch-запрос к raw_availability + raw_stores
    │
    ├── Есть в наличии в ТЦ юзера → в пул для rerank (с данными магазина)
    ├── Нет в этом ТЦ, но есть в другом → пометить "доступно в [другой ТЦ]"
    └── Нет нигде → убрать из выдачи (или показать "нет в наличии")
    │
    ▼
TOP-10–20 → Step 4: Rerank
```

### Почему TOP-50 в search, а не TOP-10

Если искать TOP-10 глобально, а потом фильтровать по наличию в конкретном ТЦ — может остаться 2–3 результата. TOP-50 гарантирует достаточно кандидатов после фильтрации.

---

## Step 4: Visual Rerank & Response

**Задача**: визуально проверить TOP-10–20 кандидатов, отранжировать, сформировать ответ.

| Параметр | Значение |
|----------|----------|
| Сервис | Gemini 2.5 Flash (vision) |
| Сервер | llm-reranker (10.1.0.13), endpoint `POST /rerank` |
| Как работает | Gemini получает 2 фото: [crop с улицы] + [лучшее фото SKU на модели из каталога]. "Это одна и та же вещь? Сравни силуэт, цвет, фактуру, детали. Score 0–1." |
| Combined score | 0.7 × visual + 0.3 × semantic (semantic = совпадение атрибутов из Step 2: цвет, тип, стиль между crop и SKU) |
| Стоимость | $30–80/мес. ~$0.003/сравнение |
| Latency | 1–2 сек на batch 10 кандидатов (параллельные вызовы) |

### Ключевое: VISUAL rerank, не текстовый

С каталогом 5–7 фото/SKU на моделях — у LLM есть фото в том же контексте что и street-фото. Визуальное сравнение "куртка на модели vs куртка на прохожей" даёт 9.5/10. Текстовый rerank — только 8.5/10.

### UX логика (Confidence levels)

| Confidence | UX | Что показываем |
|------------|-----|---------------|
| > 0.85 | "Нашли! Это [SKU] в [магазин], [этаж]" | Фото + цена + размеры в наличии + кнопка "Где купить" |
| 0.5–0.85 | "Похожие варианты" | TOP-3–5 с % сходства + магазин |
| < 0.5 | "В похожем стиле" | Attribute fallback: SQL по метаданным (type + color + style) |

### Attribute fallback (confidence < 0.5)

```sql
SELECT rp.external_id, rp.brand, rp.name, rp.price, rp.image_urls
FROM raw_products rp
JOIN raw_availability ra ON ra.brand = rp.brand AND ra.product_id = rp.external_id
JOIN raw_stores rs ON rs.brand = ra.brand AND rs.store_id = ra.store_id
WHERE rp.category = :detected_type      -- 'bomber_jacket'
  AND rp.colour ILIKE :detected_color    -- '%khaki%'
  AND rs.mall_name = :user_mall
  AND ra.fetched_at > now() - interval '24 hours'
  AND ra.sizes_in_stock != '[]'
ORDER BY rp.price
LIMIT 10
```

### Phase 2: LLM Council

Gemini + Claude Sonnet перепроверка. Если 2 модели согласны → высокий confidence. Если нет → conservative оценка. +$20–40/мес, +3–5% точности.

---

## UX: Progressive Loading

| Время | Юзер видит | Что происходит |
|-------|-----------|---------------|
| 0 сек | Фото загружается | Анимация сканирования (пульсирующие линии) |
| 0.5 сек | Detection результат | Chips на фото: "бомбер", "джинсы", "кроссовки". Ximilar ответил |
| 1–2 сек | Skeleton cards | "Ищем похожие..." shimmer-карточки |
| 2–4 сек | Результаты | Карточки SKU: фото + цена + магазин + confidence badge |
| 4–6 сек | Полный ответ | Styling advice от аватара |

---

## Инфраструктура: маппинг серверов

### Catalog Pipeline (Staging)

| Сервер | IP | Роль |
|--------|----|------|
| apify | 10.1.0.9 | Парсинг метаданных (6 брендов Inditex) |
| scraper | 10.1.0.3 | Mobile API polling: availability каждый час |
| photo-downloader | 10.1.0.10 | Скачка фото → S3 (Bright Data proxy) |
| collage | 10.1.0.16 | Горизонтальная склейка фото для try-on |
| staging-db | 10.1.0.8 | PostgreSQL 17: raw_products, raw_availability, raw_stores |
| ximilar-sync | 10.1.0.11 | Staging DB → Ximilar Collection (только пилотные бренды) |

### Recognition Pipeline (Runtime)

| Сервер | IP | Роль |
|--------|----|------|
| recognition | 10.1.0.14 | Orchestrator: координирует 4 шага + availability filter |
| ximilar-gw | 10.1.0.12 | FastAPI gateway: /detect, /tag, /search (Ximilar + pgvector) |
| llm-reranker | 10.1.0.13 | FastAPI gateway: Gemini /tag, /rerank |

> **Нужно ли разделять ximilar-gw?** Нет на Phase 1–2. ximilar-gw выполняет три endpoint'а (/detect, /tag, /search), но все три — **async IO-bound**: прокси к Ximilar API и/или network call к embed-rt + pgvector. CPU работа (нормализация, merge, dedup) — микросекунды. FastAPI + asyncio легко держит 100+ concurrent requests. При 1K–5K юзерах это ~1–3 req/sec в пике. Разделение оправдано только на Phase 3 (20K+), и то по operational isolation, а не по нагрузке.

### Data Layer

| Сервер | IP | Роль |
|--------|----|------|
| Production DB | 10.1.1.2 | PostgreSQL 17 + pgvector 0.8.1: `unde_ai.sku_image_embeddings` |
| Staging DB | 10.1.0.8 | PostgreSQL 17: raw_products, raw_availability, raw_stores |
| S3 Object Storage | hel1 | `unde-images`: originals/{brand}/{id}/{N}.jpg, collages/ |

### Embedding Service (Phase 2.5) — два сервера, полная изоляция

| Сервер | IP | Роль | Hardware | €/мес |
|--------|----|------|----------|-------|
| **embedder** | 10.1.0.15 | Runtime: `POST /embed` (live запросы от юзеров) | i7-8700, 64GB, 2×512GB NVMe SSD (HEL1-DC2) | €36.70 |
| **embed-batch** | 10.1.0.17 | Batch: `POST /embed_batch` (индексация, progressive) | i7-8700, 64GB, 2×512GB SSD (HEL1) | ~€36.70 |
| | | | **Итого** | **~€73.40** |

> **Принцип**: batch работает фоново, сколько нужно — хоть сутки. Live не затрагивается **вообще** — разные серверы, разные процессы, нулевое влияние на latency. Одинаковые CPU и диски = одинаковый config, полностью взаимозаменяемы при необходимости.

#### embedder (10.1.0.15): runtime inference

| Параметр | Значение |
|----------|----------|
| CPU | Intel Core i7-8700 (Coffee Lake 2018, 6c/12t) |
| RAM | 64 GB DDR4 |
| Disk | 2×512 GB NVMe SSD |
| Endpoint | `POST /embed` — принимает crop image, возвращает vector(512) |
| Latency | 100–250ms |
| Throughput | 5–10 img/sec (достаточно для 5K+ юзеров) |
| Вызывается из | ximilar-gw (10.1.0.12) при `/search` |

```python
import onnxruntime as ort
# embedder: latency-optimized, все ресурсы под runtime
opts = ort.SessionOptions()
opts.intra_op_num_threads = 4
opts.inter_op_num_threads = 1
opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
```

#### embed-batch (10.1.0.17): фоновая индексация

| Параметр | Значение |
|----------|----------|
| CPU | Intel Core i7-8700 (Coffee Lake 2018, 6c/12t) |
| RAM | 64 GB DDR4 |
| Disk | 2×512 GB SSD |
| Endpoint | `POST /embed_batch` — batch embed из S3, insert в pgvector |
| Throughput | 5–10 img/sec (все ресурсы под batch, без конкуренции с runtime) |
| Вызывается из | Celery worker `embedding-sync` (cron / по событию) |

```python
# embed-batch: throughput-optimized, весь CPU под batch
opts = ort.SessionOptions()
opts.intra_op_num_threads = 4
opts.inter_op_num_threads = 2
# 1–2 worker процесса × 6 threads = 6–12 ≤ 12 HW threads
```

#### Оценки времени batch (embed-batch, i7-8700, 5–10 img/sec)

| Операция | Объём | Время |
|----------|-------|-------|
| Initial load (все 6 брендов) | 47K SKU × 5 фото = 235K img | **8–13 часов** (запустить на ночь) |
| Новый бренд (средний) | ~8K SKU × 5 = 40K img | **1–2 часа** |
| Новая коллекция (малая) | 1K SKU × 5 = 5K img | **10–20 мин** |
| Progressive ingestion (недельная) | 100–500 фото | **1–3 мин** |

> **Initial load**: создать таблицу БЕЗ HNSW, bulk insert (execute_values, 1000 строк), THEN `CREATE INDEX ... USING hnsw` → `VACUUM ANALYZE`. В ~10x быстрее, чем вставлять при существующем индексе. Pipeline: скачать пачку 500 фото с S3 в RAM → embed → bulk INSERT → следующая пачка.

---

## Phases: План развития

### Phase 1: MVP (запуск за 1–2 недели)

| Step | Инструмент | Стоимость | Качество |
|------|-----------|-----------|----------|
| 0: Каталог | В Ximilar Collection (2 фото/SKU, пилотные бренды) | В тарифе | Отлично |
| 1: Detection | Ximilar Fashion Detection | 5 cr/фото | 9.5/10 |
| 2: Tagging | Gemini Flash (контекст) + Ximilar on-demand | $50–150/мес | 9.5/10 |
| 3: Search | Ximilar Fashion Search | 10 cr/запрос | 9–9.5/10 |
| 3.5: Availability | Post-filter по raw_availability | $0 | - |
| 4: Rerank | Gemini Flash Vision | $30–80/мес | 9.5/10 |
| **ИТОГО** | | **€150–200 + $80–230/мес** | **85–90% TOP-3** |

### Phase 2: Quality + Hybrid (через 1–2 месяца)

| Step | Изменение | Стоимость | Качество |
|------|----------|-----------|----------|
| 2: Tagging | On-demand (40–60% запросов) | −40–60% tagging credits | 9.5/10 |
| 3: Search | **Conditional retrieval**: pgvector primary + Ximilar booster | +$0 (pgvector бесплатен) | 9.5+/10 |
| 4: Rerank | + LLM Council (Gemini + Claude) | +$20–40/мес | 9.5+/10 |
| **ИТОГО** | | **€200–350 + $100–270/мес** | **90–95% TOP-3** |

Новые бренды/ТЦ: **$0** через pgvector. Ximilar Search как quality booster.

### Phase 3: Scale (через 3–6 месяцев)

| Step | Изменение | Стоимость | Качество |
|------|----------|-----------|----------|
| 1: Detection | YOLOv8 + DeepFashion2 (self-hosted GPU) | $30–50/мес | 9/10 |
| 3: Search | pgvector only (Ximilar Search отключён) | $0 | 8.5–9/10 |
| 2+4: Tag+Rerank | Gemini Flash | $50–100/мес | 9/10 |
| **ИТОГО** | | **$80–150/мес фикс** | **85%+ TOP-3** |

Нет vendor lock-in. Предсказуемая стоимость при любом масштабе.

---

## Логирование для калибровки (recognition_requests)

Для A/B тестов и оптимизации порогов — в каждый запрос `recognition_requests` добавить:

| Поле | Тип | Зачем |
|------|-----|-------|
| `used_ximilar_booster` | bool | Понять % запросов, где pgvector неуверен → калибровка CONFIDENCE_THRESHOLD |
| `used_ximilar_tagging` | bool | Понять реальный T (долю on-demand tagging) → калибровка бюджета |
| `pgvector_top1_score` | float | Распределение скоров → подобрать оптимальный порог |
| `pgvector_margin` | float | top1 - top2, распределение gap'ов → подобрать MARGIN |
| `ximilar_top1_score` | float (nullable) | Если booster вызывался — его скор для сравнения с pgvector |
| `candidates_after_availability` | int | Сколько осталось после post-filter → понять, достаточно ли TOP-50 |

```sql
-- Миграция (Production DB, таблица recognition_requests)
ALTER TABLE recognition_requests
    ADD COLUMN used_ximilar_booster boolean DEFAULT false,
    ADD COLUMN used_ximilar_tagging boolean DEFAULT false,
    ADD COLUMN pgvector_top1_score float,
    ADD COLUMN pgvector_margin float,
    ADD COLUMN ximilar_top1_score float,
    ADD COLUMN candidates_after_availability smallint;
```

> Без этих полей A/B тест (Phase 2e) и оптимизация порогов будут "на ощупь". Добавить в P2a вместе с `sku_image_embeddings`.

---

## Progressive Ingestion: data-driven качество

### Принцип

Не грузить все 5–7 фото/SKU сразу. Начинать с 2, догружать по данным runtime.

### Триггеры догрузки

Из таблицы `recognition_requests` (Production DB):

```sql
-- SKU, которые часто в top-k но плохо ранжатся
-- ВАЖНО: search_results/final_matches должны хранить (brand, external_id), а не "zara_12345"
SELECT
    sr->>'brand' AS brand,
    sr->>'external_id' AS external_id,
    COUNT(*) AS appearances,
    AVG((fm->>'score')::float) AS avg_rerank_score
FROM recognition_requests,
    jsonb_array_elements(search_results) sr,
    jsonb_array_elements(final_matches) fm
WHERE fm->>'brand' = sr->>'brand'
  AND fm->>'external_id' = sr->>'external_id'
  AND created_at > now() - interval '7 days'
GROUP BY sr->>'brand', sr->>'external_id'
HAVING AVG((fm->>'score')::float) < 0.7
   AND COUNT(*) > 5
ORDER BY appearances DESC;
```

> **Контракт**: `recognition_requests.search_results` и `final_matches` хранят SKU как `{"brand": "zara", "external_id": "12345", ...}` — тот же составной ключ `(brand, external_id)` что и везде в pipeline.

### Процесс

1. Скрипт находит SKU с низким rerank score но высокой частотой появления
2. `UPDATE raw_products SET ximilar_target_count = 5 WHERE brand = :brand AND external_id = :external_id`
3. `ximilar-sync` подхватит: `to_send = images[:5] - ximilar_synced_urls` → отправит недостающие 3 фото
4. Для pgvector: отдельный Celery-воркер `embedding-sync` (на vmi1150256, batch-пул) находит SKU, где `COUNT(embeddings) < ximilar_target_count`, генерирует недостающие embeddings и вставляет через upsert

### Эффект

Тратим credits на индексацию **только там, где это реально влияет на UX**. Качество растёт data-driven, без переплат.

---

## Стоимость: Ximilar Calculator

### Формула

```
R = users × 8                         (фото/мес, среднее 5–10)
K = 3                                 (вещей на фото)

Detect:      R × 5 credits
Tag single:  R × K × T × 15 credits   (T = доля on-demand: 0 — бюджетный baseline, 0.3–0.5 — quality-first рекомендация)
Search:      R × K × 10 credits
Insert:      images × 10 credits       (только новые бренды)
```

### Что вводить в калькулятор (обычный месяц, без onboarding)

**Solution 1 — Fashion Tagging:**

| Поле | 1K юз | 5K | 10K | 20K |
|------|-------|-----|------|------|
| Detect all fashion items | 8 000 | 40 000 | 80 000 | 160 000 |
| Tag all fashion items | 0 | 0 | 0 | 0 |
| Tag a single-product photo | 0 | 0 | 0 | 0 |

**Solution 2 — Fashion Search & Recommendation:**

| Поле | 1K юз | 5K | 10K | 20K |
|------|-------|-----|------|------|
| Visual search (external query) | 24 000 | 120 000 | 240 000 | 480 000 |
| Insert an image (to be processed) | 10 000 | 10 000 | 10 000 | 10 000 |

### Credits/мес (T=0, бюджетный baseline — без Ximilar tagging)

| | 1K | 5K | 10K | 20K |
|---|---|---|---|---|
| Detect (×5) | 40K | 200K | 400K | 800K |
| Search (×10) | 240K | 1.2M | 2.4M | 4.8M |
| Insert (×10) | 100K | 100K | 100K | 100K |
| **Итого credits** | **380K** | **1.5M** | **2.9M** | **5.7M** |
| **~Стоимость €** | **€100–150** | **€285–400** | **€500–700** | **€900–1200** |

### С tagging on-demand (T=0.5, quality-first рекомендация)

| | 1K | 5K | 10K | 20K |
|---|---|---|---|---|
| + Tag single (50%, ×15) | +180K | +900K | +1.8M | +3.6M |
| **Итого credits** | **560K** | **2.4M** | **4.7M** | **9.3M** |
| **~Стоимость €** | **€150–200** | **€400–500** | **€700–900** | **€1500–1800** |

### Дополнительно: Gemini (отдельно от Ximilar)

| Компонент | 1K юз | 5K | 10K | 20K |
|-----------|-------|-----|------|------|
| Gemini tagging (контекст) | $20–50 | $50–100 | $80–150 | $150–250 |
| Gemini rerank (visual) | $10–30 | $30–60 | $50–100 | $100–200 |
| **Итого Gemini** | **$30–80** | **$80–160** | **$130–250** | **$250–450** |

### Onboarding нового ТЦ (разово, Insert)

| Сценарий | Images | Credits | € |
|----------|--------|---------|---|
| ТЦ, все бренды уже есть | 0 | 0 | **€0** |
| +5 новых брендов (~25K SKU × 2) | 50K | 500K | ~€150 |
| +20 новых брендов (~100K SKU × 2) | 200K | 2M | ~€500 |
| Первый ТЦ (47K SKU × 2) | 94K | 940K | ~€300 |

### Экономия с dual retrieval (Phase 2.5)

Когда pgvector станет primary, Ximilar Search можно отключать постепенно:

| Переход | Search credits | Экономия |
|---------|---------------|----------|
| 100% Ximilar (Phase 1) | R×K×10 | — |
| 50% pgvector / 50% Ximilar | R×K×5 | −50% search |
| 100% pgvector (Phase 3) | 0 | −100% search |

---

## Оценка размера нового ТЦ (по данным из системы)

После добавления магазинов ТЦ в `raw_stores` и запуска availability poll:

```sql
-- Сколько уникальных брендов в ТЦ
SELECT COUNT(DISTINCT brand)
FROM raw_stores
WHERE mall_name = 'Ibn Battuta Mall';

-- Сколько SKU реально в наличии сегодня
SELECT COUNT(DISTINCT (ra.brand, ra.product_id))
FROM raw_availability ra
JOIN raw_stores rs ON rs.brand = ra.brand AND rs.store_id = ra.store_id
WHERE rs.mall_name = 'Ibn Battuta Mall'
  AND ra.fetched_at > now() - interval '24 hours'
  AND ra.sizes_in_stock != '[]'::jsonb;

-- Сколько из них УЖЕ проиндексированы (не нужен insert)
SELECT COUNT(DISTINCT rp.id)
FROM raw_products rp
WHERE rp.brand IN (SELECT DISTINCT brand FROM raw_stores WHERE mall_name = 'Ibn Battuta Mall')
  AND rp.ximilar_status = 'synced';
```

---

## Мониторинг качества (daily cron / Grafana)

```sql
-- Daily quality dashboard (Production DB)
SELECT
    DATE(created_at) AS date,
    COUNT(*) AS total_queries,
    AVG(pgvector_top1_score) AS avg_pgvector_score,
    AVG(pgvector_margin) AS avg_margin,
    COUNT(*) FILTER (WHERE used_ximilar_booster) * 100.0 / COUNT(*) AS ximilar_booster_pct,
    COUNT(*) FILTER (WHERE used_ximilar_tagging) * 100.0 / COUNT(*) AS ximilar_tagging_pct,
    AVG(candidates_after_availability) AS avg_candidates_after_filter,
    AVG((final_matches->0->>'score')::float) AS avg_top1_confidence,
    COUNT(*) FILTER (WHERE (final_matches->0->>'score')::float < 0.5) * 100.0 / COUNT(*) AS fallback_rate_pct
FROM recognition_requests
WHERE created_at > now() - interval '30 days'
GROUP BY DATE(created_at)
ORDER BY date DESC;
```

### Алерты (настроить в PostHog / Grafana)

| Метрика | Порог | Действие |
|---------|-------|---------|
| `fallback_rate_pct` > 15% | Красный | Проверить качество pgvector, рассмотреть `SEARCH_BACKEND=ximilar` |
| `avg_pgvector_score` < 0.65 | Жёлтый | Проверить модель / индекс, рассмотреть понижение CONFIDENCE_THRESHOLD |
| `ximilar_booster_pct` > 70% | Жёлтый | pgvector слишком неуверен — калибровать пороги или улучшить embeddings |
| `avg_candidates_after_filter` < 3 | Жёлтый | Расширить TOP-N в search или `AVAILABILITY_WINDOW` |

---

## Emergency Rollback

Если после запуска Phase 2 pgvector показывает точность <80% или latency >1s:

| Сценарий | Env-переменная (ximilar-gw) | Значение | Время | Деплой |
|----------|------------------------------|----------|-------|--------|
| pgvector accuracy <80% | `SEARCH_BACKEND` | `ximilar` (откат на Phase 1) | 1 мин | env only |
| pgvector latency >1s | `SEARCH_BACKEND` | `ximilar` | 1 мин | env only |
| Ximilar API down | `SEARCH_BACKEND` | `pgvector` | 1 мин | env only |
| Tagging просадка >5% | `TAGGING_MODE` | `always` (вместо `on_demand`) | 1 мин | env only |
| Availability = 0 results | `AVAILABILITY_WINDOW` | `48h` (вместо `24h`) | 1 мин | env only |
| Availability = 0 results | `MIN_CANDIDATES` | увеличить (напр. 5 → 10) | 1 мин | env only |

> **Принцип**: все ключевые решения pipeline управляются feature flags / env-переменными. Откат не требует деплоя кода.
>
> **Где читаются**: `SEARCH_BACKEND`, `TAGGING_MODE`, `CONFIDENCE_THRESHOLD`, `MARGIN` — в **ximilar-gw** (10.1.0.12). `AVAILABILITY_WINDOW`, `MIN_CANDIDATES` — в **Recognition Orchestrator** (10.1.0.14). Все через `os.environ` с fallback на defaults.

---

## Rejected Solutions

| Решение | Причина отказа | Когда пересмотреть |
|---------|---------------|-------------------|
| Gemini для detection | 7/10 quality. Bounding boxes нестабильные, теряет аксессуары | Никогда для detection |
| Google Vision (primary search) | 7.5/10 — general purpose, не fashion-специализированный | Phase 2 как третий движок в ансамбле |
| Tag-all всегда | 60 credits/фото, +7.2M credits/мес. Gemini компенсирует для 60% запросов | Если A/B покажет просадку >5% |
| 5–7 фото/SKU в Ximilar | ×3 insert credits. 2 фото + progressive ingestion дешевле | Для отдельных "важных" SKU по данным runtime |
| Pre-filter по availability | Убивает recall. SKU может быть визуально точным но временно out of stock | Никогда |
| Индексация per-ТЦ | Дубликаты SKU. Zara в 10 ТЦ = 10× insert | Никогда. Глобальная индексация per-бренд |
| Новые таблицы raw_brands / raw_mall_brands | Функциональность уже есть в raw_products + raw_stores + raw_availability | Никогда |
| ViSenze / Syte | Enterprise pricing $500–2000+/мес | При масштабе 10K+ юзеров |
| Только FashionCLIP (без Ximilar) | 8.5/10 из коробки. С dual retrieval = 9.5+/10 | Phase 3: после fine-tune на своих данных |

---

## Приоритеты внедрения

| Приоритет | Действие | Где | Эффект | Срок |
|-----------|---------|-----|--------|------|
| **P0.1** | Tagging on-demand (не вызывать /tag всегда) | Recognition Orchestrator / ximilar-gw | −40–60% tagging credits | 1 день |
| **P0.2** | 2 фото/SKU в ximilar-sync (`images[:2]`) | ximilar-sync (10.1.0.11) | −60% insert credits | 1 день |
| **P0.3** | `index_scope` + `ximilar_synced_urls` + `target_count` в Staging DB | staging-db (10.1.0.8) | Контроль бюджета | 1 день |
| **P1** | Availability post-filter (Step 3.5) | Recognition Orchestrator (10.1.0.14) | Корректная выдача per-ТЦ | 2–3 дня |
| **P2a** | Таблица `sku_image_embeddings` в unde_ai | Production DB (10.1.1.2) | Готовность к pgvector search | 1 день |
| **P2b.1** | Заказать 2× i7-8700 из аукциона Hetzner HEL1 (~€73.40/мес): embedder + embed-batch (оба SSD). embedder **заказан**. | Hetzner auction | Изолированные серверы для embedding | 1 день |
| **P2b.2** | Deploy FashionCLIP + ONNX + FastAPI на embedder (10.1.0.15) и embed-batch (10.1.0.17) | embedder / embed-batch | Runtime /embed + фоновый /embed_batch | 3–5 дней |
| **P2c** | Batch-индексация каталога на embed-batch (ночью): bulk insert → `CREATE INDEX hnsw` → `VACUUM ANALYZE` | embed-batch (10.1.0.17) → Production DB | Заполнение pgvector индекса | 8–13 часов |
| **P2d** | Feature flag `SEARCH_BACKEND` + dual retrieval в ximilar-gw | ximilar-gw (10.1.0.12) | Dual search без изменений Orchestrator | 3–5 дней |
| **P2e** | A/B тест 100 фото: pgvector vs Ximilar | Recognition Orchestrator | Валидация качества | 2–3 дня |
| **P2f** | Переключение на dual / pgvector primary | ximilar-gw | Снижение Ximilar Search credits | 1 день |
| **P3** | Progressive ingestion pipeline | ximilar-sync + cron | Data-driven улучшение качества | Ongoing |
