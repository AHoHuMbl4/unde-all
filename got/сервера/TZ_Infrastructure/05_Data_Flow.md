# UNDE Infrastructure — Data Flow

*Часть [TZ Infrastructure v7.2](../TZ_Infrastructure_Final.md). Диаграммы потоков данных.*

> **🔄 Обновлено под [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md)** — 17.6 Fashion Recognition (dual retrieval, availability filter, TOP-50), новый 17.11 Embedding Batch Indexing.

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
│  APIFY SERVER (10.1.0.9)                           │
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
│  (10.1.0.10)       │  │  (10.1.0.11)       │
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
│  COLLAGE SERVER (10.1.0.16)                        │
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
│  → Только товары с коллажом И в наличии в Dubai     │
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

### 17.6 Пользователь: Fashion Recognition (🔄 v5.1)

```
┌──────────────┐
│ 📱 Приложение│  Фотографирует outfit на улице
└──────┬───────┘
       │ POST /api/v1/recognize (фото, user_mall)
       ▼
┌──────────────┐
│  App Server  │  Celery task → Redis
│  (10.1.0.2)  │
└──────┬───────┘
       ▼
┌────────────────────────────────────────────────────────────┐
│  RECOGNITION ORCHESTRATOR (10.1.0.14)                      │
│                                                            │
│  Step 1: → Ximilar GW /detect → crops + категории          │
│     (200-500ms) → сразу показать chips на фото              │
│      ▼                                                     │
│  Step 3: → Ximilar GW /search (🔄 DUAL RETRIEVAL)          │
│     pgvector kNN (embedder 10.1.0.15 → Production DB)      │
│     + conditional Ximilar booster (40-60% запросов)        │
│     → TOP-50 глобальных кандидатов (5-500ms)               │
│      ▼                                                     │
│  Step 2: CONDITIONAL TAGGING (🔄 ON-DEMAND)                 │
│     Gemini /tag — ВСЕГДА, параллельно с search              │
│     Ximilar /tag — ТОЛЬКО если search неуверенный (40-60%) │
│      ▼                                                     │
│  Step 3.5: AVAILABILITY POST-FILTER (🔄 NEW)               │
│     SQL к Staging DB: raw_availability + raw_stores         │
│     → только товары в наличии в ТЦ юзера (<10ms)           │
│     → TOP-10-20 кандидатов                                  │
│      ▼                                                     │
│  Step 4: → LLM Reranker /rerank                            │
│     (1-2s, batch параллельно)                               │
│     > 0.85  → "Нашли! Это [SKU] в [магазин], [этаж]"      │
│     0.5-0.85 → "Похожие варианты" TOP-3-5                  │
│     < 0.5   → Attribute fallback (SQL + availability)       │
│                                                            │
│  Суммарно: 3-6 сек (progressive loading)                   │
│  Результат → Redis → App Server → Приложение               │
└──┬──────────────┬──────────────┬──────────────┬────────────┘
   │              │              │              │
   ▼              ▼              ▼              ▼
┌────────────┐ ┌────────────┐ ┌────────────┐ ┌───────────────────┐
│ XIMILAR GW │ │ EMBEDDER   │ │ LLM        │ │  Production DB    │
│ (10.1.0.12)│ │ (10.1.0.15)│ │ RERANKER   │ │  (10.1.1.2)       │
│ →Ximilar   │ │ FashionCLIP│ │ (10.1.0.13)│ │ recognition_      │
│  API       │ │ →pgvector  │ │ →Gemini 2.5│ │ requests (лог)    │
│ +pgvector  │ │ ONNX CPU   │ │  Flash     │ │ sku_image_        │
│  kNN       │ └────────────┘ └────────────┘ │ embeddings        │
└────────────┘                               └───────────────────┘
       │
       ▼
┌──────────────┐
│ Staging DB   │  🔄 v5.1: raw_availability + raw_stores
│ (10.1.0.8)   │  → availability post-filter (Step 3.5)
└──────────────┘
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
│  (10.2.0.2)  │  1. mood_analyze → Mood Agent
└──────┬───────┘  2. context_request → Context Agent
       │          3. generate_response → LLM Orchestrator
       │
  ┌────┴──────────────────┬─────────────────────┐
  │                       │                     │
  ▼                       ▼                     ▼
┌───────────────┐ ┌────────────────┐ ┌──────────────────────────────────────┐
│ MOOD AGENT    │ │ CONTEXT AGENT  │ │ LLM ORCHESTRATOR (10.2.0.17)         │
│ (10.2.0.11)   │ │ (10.2.0.19)    │ │                                      │
│               │ │                │ │ Ожидает mood_frame + context_frame,  │
│ → mood_frame  │ │ → context_frame│ │ затем:                               │
│ (~100ms)      │ │ (~100ms)       │ │                                      │
└──────┬────────┘ └──────┬─────────┘ │ Фаза 2 (ПАРАЛЛЕЛЬНО):               │
       │                 │           │ 1a. Embed запрос → vector    (~50ms) │
       └────────┐  ┌─────┘           │ 1b. POST /persona            (~15ms)│
                │  │                 │     (10.2.0.21)                      │
                ▼  ▼                 │     → persona_directive              │
         mood_frame +                │     → voice_params                   │
         context_frame ────────────► │     → avatar_state + render_hints   │
                                     │                                      │
                                     │ Фаза 3 (после embed):              │
                                     │ 2. ПАРАЛЛЕЛЬНО:                      │
                                     │    a) Hybrid Search (vector+FTS)     │
                                     │       + temporal decay + confidence  │
                                     │       → TOP-15 (snippet + raw_excerpt│
                                     │         + message_id)               │
                                     │    b) User Knowledge (AES-256)      │
                                     │    c) Последние 10 сообщений        │
                                     │    d) Artifact lookup (reply_to_id) │
                                     │                                      │
                                     │ 3. Span enrichment (KSP Фикс 5)     │
                                     │    NEEDS_SPAN (<50 chars / указат.) │
                                     │    → подтянуть ±1 сообщение         │
                                     │ 4. Privacy Guard (KSP Фикс 12)      │
                                     │    cosine filter на span-соседей    │
                                     │    (threshold: 0.3 ru/en, 0.25 ar) │
                                     │ 5. Emotional filter (mood_frame)     │
                                     │    мягкий: score ×0.8, не удаление │
                                     │ 6. Memory Density Cap (адаптивный)  │
                                     │ 7. Сборка ContextPack (6 слоёв)     │
                                     │    (+ persona_directive)             │
                                     │ 8. → LLM API                        │
                                     │ SYNC при INSERT:                     │
                                     │ 9. Instant Pattern Extract (Фикс 1A)│
                                     │ 10. Correction Detect (Фикс 11)     │
                                     │ 11. response_description             │
                                     │ 12. voice_params → Voice Server      │
                                     │ 13. avatar+hints → App               │
                                     │ ASYNC: signals → /persona/feedback  │
                                     └──┬────────┬──────────┬────────┬────┘
                                        │        │          │        │
                                        ▼        ▼          ▼        ▼
                             ┌────────────┐ ┌────────┐ ┌──────┐ ┌────────┐
                             │Local Shard │ │ Voice  │ │📱 App│ │Persona │
                             │(NVMe SSD)  │ │ Server │ │текст+│ │Agent   │
                             │Chat History│ │10.2.0.12│ │аудио+│ │feedback│
                             │+ UK + Stage│ │voice→📱│ │avatar│ │+ flush │
                             │enrichment  │ └────────┘ └──────┘ └────────┘
                             └────────────┘

Общая добавленная latency от Semantic Retrieval + Persona: ~65ms
(embedding 50ms ‖ persona 15ms + hybrid search 10ms + filters 5ms)
(mood_frame и context_frame ~100ms, перекрываются с embedding+persona)
```

### 17.8 Enrichment TTL Recovery (cron, каждые 6 часов)

> Из UNDE_Knowledge_Staging_Pipeline.md, Фикс 14.

```
┌─────────────────────────────────────────────────────┐
│  CRON JOB: Enrichment TTL Recovery                   │
│  (LLM Orchestrator или dedicated worker)             │
│  Частота: каждые 6 часов                             │
│                                                      │
│  1. SELECT messages WHERE embedding IS NULL           │
│     AND is_embeddable = TRUE AND is_forgotten = FALSE│
│     AND created_at < NOW() - INTERVAL '1 hour'       │
│     AND created_at > NOW() - INTERVAL '7 days'       │
│     AND enrichment_retry_count < 3                   │
│     ORDER BY created_at DESC LIMIT 500               │
│                                                      │
│  2. Отправить в enrichment queue                     │
│     priority = 'recovery'                            │
│                                                      │
│  3. enrichment_retry_count += 1                      │
│     При каждой попытке: last_retry_at = NOW()        │
│                                                      │
│  4. После 3 неудач → orphan alert                    │
│     (unde_orphan_messages_total)                     │
└─────────────────┬───────────────────────────────────┘
                  │
                  ▼
         ┌──────────────┐
         │ Local Shard   │  UPDATE embedding = ...
         │ (NVMe SSD)    │
         └──────────────┘
```

### 17.9 Memory Correction Loop (sync при INSERT user-сообщения)

> Из UNDE_Knowledge_Staging_Pipeline.md, Фикс 11.

```
┌──────────────┐
│ 📱 Юзер:     │  "Нет, мой размер не M, а S"
│ "с чего ты   │  или "ты путаешь"
│  взял?"      │
└──────┬───────┘
       │
       ▼
┌────────────────────────────────────────────────────┐
│  LLM ORCHESTRATOR (10.2.0.17) — при INSERT          │
│                                                      │
│  1. CORRECTION_PATTERNS regex (ru/en/ar/Arabizi)     │
│     Срабатывание?                                    │
│     │                                                │
│     ├── Denial ЯВНЫЙ ("мой размер не M"):            │
│     │   → user_knowledge: is_active = FALSE          │
│     │                                                │
│     ├── Denial НЕОДНОЗНАЧНЫЙ ("с чего ты взял?"):    │
│     │   → user_knowledge: is_disputed = TRUE         │
│     │   → промпт: "мягко уточни, не утверждай"       │
│     │                                                │
│     └── 2. INSERT memory_correction_log              │
│            trigger_message_id, corrected_message_id   │
│            correction_type                            │
│                                                      │
│  3. LLM: извиниться и уточнить правду               │
│                                                      │
│  4. [Фаза 2] correction events → golden tests        │
│     → batch extraction prompt tuning                 │
└──────────────────────────────────────────────────────┘
```

### 17.11 Embedding Batch Indexing (🔄 v5.1 — NEW)

> Из [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md). Фоновая индексация каталога в pgvector.

```
┌──────────────────────────────────────────────────────────────┐
│  CELERY WORKER: embedding-sync                                │
│  Триггеры:                                                   │
│  • Новые SKU: ximilar-sync завершил batch → событие           │
│  • Progressive ingestion: weekly cron                         │
│  • Manual: initial load / новый бренд                        │
│                                                              │
│  1. SELECT raw_products                                       │
│     WHERE index_scope IN ('pilot', 'pgvector')                │
│       AND image_status IN ('uploaded', 'collage_ready')       │
│     — все SKU, подлежащие индексации                          │
│                                                              │
│  2. Для каждого batch (500 фото):                            │
│     a) Скачать изображения из Object Storage                  │
│        GET /originals/{brand}/{external_id}/{N}.jpg           │
│     b) POST /embed_batch → embed-batch (10.1.0.17)           │
│        FashionCLIP 2.0, ONNX Runtime, vector(512)            │
│        5–10 img/sec (все CPU под batch)                       │
│     c) Bulk INSERT → Production DB (10.1.1.2)                │
│        unde_ai.sku_image_embeddings                           │
│        ON CONFLICT (brand, sku_id, image_hash, model_version)│
│        DO UPDATE (idempotent upsert)                          │
│                                                              │
│  3. После завершения: VACUUM ANALYZE sku_image_embeddings     │
│                                                              │
│  Initial load: 47K SKU × 5 фото = 235K img → 8–13 часов     │
│  Новый бренд: ~8K SKU → 1–2 часа                            │
│  Weekly progressive: 100–500 фото → 1–3 мин                  │
└──┬──────────────────┬────────────────────┬───────────────────┘
   │                  │                    │
   ▼                  ▼                    ▼
┌──────────────┐ ┌────────────┐  ┌───────────────────┐
│ Object       │ │ EMBED-BATCH│  │  Production DB    │
│ Storage      │ │ (10.1.0.17)│  │  (10.1.1.2)       │
│ /originals/  │ │ i7-8700    │  │  unde_ai.          │
│              │ │ 64GB, NVMe │  │  sku_image_        │
│              │ │ ONNX CPU   │  │  embeddings        │
│              │ │ FashionCLIP│  │  HNSW index        │
│              │ │ 2.0 (512d) │  │  (vector_cosine)   │
└──────────────┘ └────────────┘  └───────────────────┘
```

---

### 17.10 Batch Knowledge Extraction (async, Фаза 2)

> Из UNDE_Knowledge_Staging_Pipeline.md, Фикс 1B. Запускается после валидации на реальных данных.

```
┌─────────────────────────────────────────────────────┐
│  CELERY WORKER: Batch Knowledge Extraction            │
│  Триггеры:                                           │
│  • Сессия закрыта (gap > 30 мин)                     │
│  • pending_extraction_count ≥ 15                     │
│  • Cron: раз в 2 часа если есть pending              │
│  Ограничение: не чаще 1 раз/юзер/час                │
│  Concurrency: pg_advisory_xact_lock(user_id_hash)   │
│                                                      │
│  1. Собрать current_knowledge + new_messages         │
│     (user + assistant с last_extraction_at)          │
│                                                      │
│  2. → DeepSeek: "верни дельту (ADD/UPDATE/REMOVE)"   │
│     ЖЁСТКИЕ ОГРАНИЧЕНИЯ:                            │
│     • Только факты о самом юзере (subject = user)    │
│     • НЕ обобщать предпочтения                       │
│     • Сарказм = НЕ факт                             │
│     • Gulf slang ≠ факт                              │
│                                                      │
│  3. Validator Gate (детерминированный):               │
│     confidence ≥ 0.8 + якорная валидация             │
│     → APPLY или REJECT                               │
│                                                      │
│  4. UPDATE user_knowledge + extraction_log           │
│  5. pending_extraction_count = 0                     │
└─────────────────────────────────────────────────────┘
```

---
