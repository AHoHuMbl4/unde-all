# UNDE Infrastructure — Fashion Recognition Pipeline

*Серверы распознавания одежды.*

> **🔄 Обновлено под [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md)** — dual retrieval (pgvector + Ximilar), conditional tagging, availability post-filter, embedding серверы.

---

## 8. RECOGNITION ORCHESTRATOR (✅ Работает)

> **Задача:** юзер фотографирует outfit на улице → UNDE определяет каждую вещь → находит похожие SKU в каталоге ТЦ → показывает с ценой, магазином и наличием
>
> **Каталог:** готов. 5-7 фото/SKU парсятся с сайтов брендов, включая фото на моделях. Индексация: 2 фото в Ximilar (пилотные бренды) + все 5-7 в pgvector (все бренды)
>
> **🔄 v5.1:** координирует 5 шагов (+ Step 3.5 Availability Filter), управляет feature flags (`SEARCH_BACKEND`, `TAGGING_MODE`, `AVAILABILITY_WINDOW`)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | recognition |
| **Private IP** | 10.1.0.14 |
| **Public IP** | 89.167.90.152 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04.3 LTS |
| **Git** | http://gitlab-real.unde.life/unde/Recognition.git |
| **Статус** | ✅ Развёрнут, контейнер running |

### Назначение

Координатор Fashion Recognition Pipeline:
- Принимает Celery task из Redis (от App Server)
- Вызывает Ximilar Gateway (10.1.0.12) и LLM Reranker (10.1.0.13) по HTTP
- **🔄 v5.1:** Выполняет Step 3.5 — availability post-filter (SQL к Staging DB)
- Собирает результаты всех шагов
- Сохраняет лог в Production DB (включая новые поля калибровки)
- Отдаёт финальный результат

### Что НЕ делает

- ❌ Вызов внешних API напрямую (ни Ximilar, ни Gemini)
- ❌ Обработка изображений
- ❌ Тяжёлые вычисления
- ❌ Embedding inference (это делает embedder через ximilar-gw)

### Почему CPX11

Чистый оркестратор: принимает task, делает HTTP-запросы к внутренним серверам, собирает JSON, выполняет SQL-запрос availability filter, пишет в БД. Минимум CPU/RAM.

### Расположение в инфраструктуре

> **🔄 v5.1:** добавлены embedder (10.1.0.15), Staging DB (availability), pgvector path в ximilar-gw

```
📱 Приложение: пользователь фотографирует outfit на улице
    │
    │ POST /api/v1/recognize (фото, user_mall)
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
│  10.1.0.4       │◄───────►│  10.1.0.14                    │
│  Redis Broker   │         │                               │
└─────────────────┘         │  2 Celery workers (I/O bound) │
                            └──┬──────────┬──────────┬──────┘
                               │          │          │
                               ▼          ▼          ▼
                    ┌─────────────────┐ ┌──────────────┐ ┌──────────────┐
                    │ XIMILAR GATEWAY │ │ LLM RERANKER │ │ Staging DB   │
                    │ 10.1.0.12       │ │ 10.1.0.13    │ │ 10.1.0.8     │
                    │                 │ │              │ │              │
                    │ HTTP :8001      │ │ HTTP :8002   │ │ SQL :6432    │
                    │ • detect        │ │ • tag_context│ │ • availability│
                    │ • tag           │ │ • visual_    │ │   post-filter│
                    │ • search (dual) │ │   rerank     │ │ • raw_stores │
                    └──┬──────────┬──┘ └──────┬───────┘ └──────────────┘
                       │          │           │
                       ▼          ▼           ▼
                ┌──────────┐ ┌──────────┐ ┌──────────────┐
                │Ximilar   │ │embedder  │ │Gemini API    │
                │API       │ │10.1.0.15 │ │(external)    │
                │(external)│ │→pgvector │ │              │
                └──────────┘ │ (Prod DB)│ └──────────────┘
                             └──────────┘
                                   │
                                   ▼
                          ┌──────────────────┐
                          │  Production DB   │
                          │  10.1.1.2        │
                          │ • products (SKU) │
                          │ • recognition_   │
                          │   requests (лог) │
                          │ • sku_image_     │
                          │   embeddings     │
                          └──────────────────┘
```

### Pipeline: 5 шагов обработки фото (🔄 v5.1)

> **Ключевые изменения v5.1:**
> - Step 2 (Tagging) — on-demand: вызывается только при неуверенном search
> - Step 3 (Search) — dual retrieval: pgvector primary + Ximilar conditional booster
> - Step 3.5 (NEW) — Availability post-filter по `raw_availability`
> - TOP-50 search → availability filter → TOP-10-20 → rerank
> - Feature flags управляют всеми ключевыми решениями

```
Step 1: DETECTION & CROP → Ximilar Gateway
  Сервис: Ximilar Fashion Detection API
  Качество: 9.5/10. Специализирован на fashion. Отличает кардиган
    от жилетки, crop-top от обычного, шарф от палантина.
  Вход: street-фото
  Выход: bounding boxes + готовые crops + категория
  Стоимость: 5 credits/фото
  Latency: 200-500ms
  🔄 v5.1: не меняется — фундамент pipeline
         │
         ▼
Step 2: TAGGING & DESCRIPTION (🔄 v5.1: ON-DEMAND)
  Стратегия: conditional tagging — вызываем ТОЛЬКО при неуверенном search

  Gemini Flash (контекст): вызывается ВСЕГДА, параллельно с search
    Что даёт: стиль, occasion, brand_style, сезон
    Стоимость: $50-150/мес фикс

  Ximilar Tagging: вызывается ON-DEMAND (40-60% запросов)
    Когда: search неуверенный (top1_score < CONFIDENCE_THRESHOLD
           или margin < MARGIN)
    Что даёт: Pantone цвет, точный материал, принт
    Стоимость: 15 credits/item (экономия 40-60% vs always)

  🔄 v5.1: управляется TAGGING_MODE (always | on_demand)
         │
         ▼
Step 3: VISUAL SEARCH — DUAL RETRIEVAL (🔄 v5.1: NEW)
  Архитектура: pgvector primary + conditional Ximilar booster

  1) pgvector kNN (ВСЕГДА, бесплатно, 5-20ms):
     crop → embedder (10.1.0.15) → vector(512)
     → pgvector kNN по sku_image_embeddings (Production DB)
     → TOP-50 кандидатов

  2) GATING: pgvector уверен?
     top1_score ≥ 0.80 И margin ≥ 0.10?
     → ДА: сразу на Step 3.5 (экономия 10 credits)
     → НЕТ: + Ximilar Fashion Search → TOP-30
            → объединение + дедупликация → TOP-50

  Стоимость: pgvector = $0, Ximilar = 10 credits/запрос (40-60%)
  Latency: pgvector 5-20ms + Ximilar 200-500ms (conditional)

  🔄 v5.1: управляется SEARCH_BACKEND (ximilar | pgvector | conditional | dual)
         │
         ▼
Step 3.5: AVAILABILITY POST-FILTER (🔄 v5.1: NEW)
  Задача: из TOP-50 оставить только товары в наличии в ТЦ юзера
  SQL: batch-запрос к raw_availability + raw_stores (Staging DB)
  Latency: <10ms
  Результат: TOP-10-20 кандидатов с данными магазина

  Если после фильтра < MIN_CANDIDATES (3):
    → Дозапрос Ximilar Search (если ещё не вызывался)
    → Или расширить лимит

  🔄 v5.1: управляется AVAILABILITY_WINDOW (24h), MIN_CANDIDATES (3)
         │
         ▼
Step 4: VISUAL RERANK & RESPONSE → LLM Reranker
  Сервис: Gemini 2.5 Flash (vision)
  Вход: TOP-10-20 кандидатов после availability filter
  Combined score = 0.7 × visual + 0.3 × semantic
  Latency: 1-2 сек (batch, параллельные вызовы)
```

### Fallback: когда точного SKU нет в каталоге

Visual search ВСЕГДА возвращает TOP-N. Вопрос — насколько они похожи. Три уровня:

```
> 0.85   ✅ "Нашли! Это [SKU] в [магазин], [этаж]"
         Точный или почти точный матч.
         Фото + цена + размеры в наличии + кнопка "Где купить".

0.5-0.85 🔍 "Похожие варианты"
         Визуально близкие SKU. Тот же тип, похожий стиль.
         Показываем TOP-3-5 с % сходства + магазин.

< 0.5    🎨 "В похожем стиле"
         Визуальный матч слабый. ATTRIBUTE FALLBACK: SQL-запрос
         по метаданным из Step 2 (type + color + style)
         + availability filter по ТЦ юзера.

Принцип: юзер ВСЕГДА получает результат. Даже если точного совпадения
нет — показываем лучшее что есть.
```

### 🔄 v5.1: Attribute fallback с availability

```sql
SELECT rp.external_id, rp.brand, rp.name, rp.price, rp.image_urls
FROM raw_products rp
JOIN raw_availability ra ON ra.brand = rp.brand AND ra.product_id = rp.external_id
JOIN raw_stores rs ON rs.brand = ra.brand AND rs.store_id = ra.store_id
WHERE rp.category = :detected_type      -- 'bomber_jacket'
  AND rp.colour ILIKE :detected_color   -- '%khaki%'
  AND rs.mall_name = :user_mall
  AND ra.fetched_at > now() - interval '24 hours'
  AND ra.sizes_in_stock != '[]'
ORDER BY rp.price
LIMIT 10
```

### UX: Progressive Loading

```
0 сек     Фото загружается       → Анимация сканирования (пульсирующие линии)
0.5 сек   Detection результат    → Chips на фото: "бомбер", "джинсы", "кроссовки". Ximilar ответил.
1-2 сек   Skeleton cards         → "Ищем похожие..." shimmer-карточки
2-4 сек   Результаты             → Карточки SKU: фото + цена + магазин + confidence badge
4-6 сек   Полный ответ           → Styling advice от аватара

🔄 v5.1: суммарная latency 3-6 сек. Detection мгновенно (~0.5с), результаты progressive.
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
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.

**2 concurrent workers:** оркестратор только ждёт HTTP-ответов от Ximilar Gateway и LLM Reranker. Минимум CPU.

### Celery Task (🔄 v5.1)

`recognize_photo` координирует 5 шагов (включая новый Step 3.5). Ключевые изменения: dual retrieval, conditional tagging, availability post-filter, расширенное логирование для калибровки.

```python
@celery_app.task(queue='recognition_queue', time_limit=30, soft_time_limit=25)
def recognize_photo(photo_url: str, user_id: str = None,
                    user_mall: str = None) -> dict:  # 🔄 v5.1: user_mall
    request_id = uuid4()
    t_start = time.time()

    # Step 1: Detection & Crop → Ximilar Gateway
    detected_items = ximilar_gw.detect(photo_url)

    # 🔄 v5.1: Gemini tagging запускается параллельно с search (всегда)
    # Ximilar tagging — on-demand (после оценки confidence search)

    final_matches = []
    for item in detected_items:
        # Step 3: Dual Retrieval → Ximilar Gateway (🔄 v5.1)
        # ximilar-gw внутри решает: pgvector only или pgvector + Ximilar booster
        search_result = ximilar_gw.search(
            crop_url=item["crop_url"],
            category=item.get("category"),
            top_k=50,                    # 🔄 v5.1: TOP-50 вместо TOP-10
            user_mall=user_mall          # 🔄 v5.1: для brand pre-filter
        )

        # Gemini context tagging (параллельно с search, результат уже готов)
        llm_tags = llm_reranker.tag_context(item["crop_url"])

        # 🔄 v5.1: Conditional Ximilar tagging
        used_ximilar_tagging = False
        if TAGGING_MODE == "on_demand":
            if not search_result["pgvector_confident"]:
                ximilar_tags = ximilar_gw.tag(item["crop_url"])
                used_ximilar_tagging = True
                tags = {**ximilar_tags, **llm_tags}
            else:
                tags = llm_tags
        else:  # always
            ximilar_tags = ximilar_gw.tag(item["crop_url"])
            used_ximilar_tagging = True
            tags = {**ximilar_tags, **llm_tags}

        # Step 3.5: Availability Post-Filter (🔄 v5.1: NEW)
        candidates = search_result["candidates"]  # TOP-50 global
        if user_mall:
            available = availability_filter(
                candidates=candidates,
                user_mall=user_mall,
                window=AVAILABILITY_WINDOW       # default: 24h
            )

            # Дозапрос если мало кандидатов
            if len(available) < MIN_CANDIDATES and not search_result["used_ximilar"]:
                extra = ximilar_gw.search(
                    crop_url=item["crop_url"],
                    top_k=50,
                    force_ximilar=True
                )
                available = availability_filter(
                    candidates=extra["candidates"],
                    user_mall=user_mall,
                    window=AVAILABILITY_WINDOW
                )
        else:
            available = candidates[:20]

        candidates_after_availability = len(available)

        # Step 4: Visual Rerank → LLM Reranker
        ranked = llm_reranker.visual_rerank(
            crop_url=item["crop_url"],
            candidates=available[:20],           # 🔄 v5.1: TOP-10-20
            tags=tags
        )

        # Fallback по confidence
        top_score = ranked[0]["score"] if ranked else 0
        if top_score > 0.85:
            ranked = [{"match_type": "exact", **r} for r in ranked[:1]]
        elif top_score >= 0.5:
            ranked = [{"match_type": "similar", **r} for r in ranked[:5]]
        else:
            ranked = attribute_fallback(tags, user_mall)  # 🔄 v5.1: + mall
            ranked = [{"match_type": "style", **r} for r in ranked]

        final_matches.append(ranked)

    total_ms = int((time.time() - t_start) * 1000)

    # Сохранить в Production DB (🔄 v5.1: расширенные поля калибровки)
    save_recognition_request(
        request_id, user_id, photo_url,
        detected_items, tags, search_result, final_matches, total_ms,
        # 🔄 v5.1: новые поля для A/B тестов и калибровки
        used_ximilar_booster=search_result.get("used_ximilar", False),
        used_ximilar_tagging=used_ximilar_tagging,
        pgvector_top1_score=search_result.get("pgvector_top1_score"),
        pgvector_margin=search_result.get("pgvector_margin"),
        ximilar_top1_score=search_result.get("ximilar_top1_score"),
        candidates_after_availability=candidates_after_availability
    )

    return {
        "request_id": str(request_id),
        "items": format_response(detected_items, tags, final_matches),
        "total_ms": total_ms
    }


# 🔄 v5.1: Availability post-filter (Step 3.5)
def availability_filter(candidates, user_mall, window="24 hours"):
    """Batch-запрос к Staging DB: оставить только товары в наличии в ТЦ юзера."""
    brand_product_pairs = [(c["brand"], c["external_id"]) for c in candidates]
    return staging_db.query("""
        WITH latest AS (
            SELECT DISTINCT ON (brand, store_id, product_id)
                brand, store_id, product_id, sizes_in_stock, fetched_at
            FROM raw_availability
            WHERE fetched_at > now() - interval :window
            ORDER BY brand, store_id, product_id, fetched_at DESC
        )
        SELECT l.product_id, l.brand, rs.name AS store_name,
               rs.address, rs.mall_name, l.sizes_in_stock
        FROM unnest(:pairs) AS c(brand, product_id)
        JOIN latest l ON l.brand = c.brand AND l.product_id = c.product_id
        JOIN raw_stores rs ON rs.brand = l.brand AND rs.store_id = l.store_id
        WHERE rs.mall_name = :user_mall
          AND l.sizes_in_stock != '[]'::jsonb
    """, window=window, pairs=brand_product_pairs, user_mall=user_mall)


# HTTP клиенты для внутренних серверов
class XimilarGW:
    BASE = "http://10.1.0.12:8001"
    def detect(self, url): return post(f"{self.BASE}/detect", json={"url": url})
    def tag(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def search(self, **kw): return post(f"{self.BASE}/search", json=kw)

class LLMReranker:
    BASE = "http://10.1.0.13:8002"
    def tag_context(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def visual_rerank(self, **kw): return post(f"{self.BASE}/rerank", json=kw)
```

### Environment Variables (🔄 v5.1: feature flags)

```bash
# /opt/unde/recognition/.env

# Внутренние серверы (private network)
XIMILAR_GW_URL=http://10.1.0.12:8001
LLM_RERANKER_URL=http://10.1.0.13:8002

# 🔄 v5.1: Staging DB для availability post-filter (Step 3.5)
STAGING_DB_URL=postgresql://recognition:<password>@10.1.0.8:6432/unde_staging

# Celery (Redis на Push Server, db 6 для recognition)
CELERY_BROKER_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/6
CELERY_RESULT_BACKEND=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/6

# Production DB (SKU метаданные + логи)
DATABASE_URL=postgresql://undeuser:X37nLbzPI2jeL@10.1.1.2:6432/unde_main

# Thresholds
CONFIDENCE_HIGH=0.85
CONFIDENCE_MEDIUM=0.50

# 🔄 v5.1: Feature flags (все ключевые решения — env, откат без деплоя)
TAGGING_MODE=on_demand              # always | on_demand
AVAILABILITY_WINDOW=24h             # 24h | 48h
MIN_CANDIDATES=3                    # минимум кандидатов после availability filter
```

### Структура директорий (🔄 v5.1)

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
│   ├── tasks.py                # recognize_photo orchestration (5 шагов)
│   ├── availability.py         # 🔄 v5.1: Step 3.5 availability filter
│   ├── clients/
│   │   ├── ximilar_gw.py      # HTTP client → 10.1.0.12
│   │   ├── llm_reranker.py    # HTTP client → 10.1.0.13
│   │   └── staging_db.py      # 🔄 v5.1: SQL client → 10.1.0.8
│   ├── db.py
│   └── utils.py
├── scripts/
│   ├── health-check.sh
│   └── test-recognize.sh
└── deploy/
    ├── recognition.service
    └── init-db.sql             # Таблица recognition_requests (v5.1)
```

### Таблица в Production DB (🔄 v5.1: новые поля калибровки)

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

    -- Step 3: Visual Search (Ximilar Gateway — dual retrieval)
    search_results JSONB,
    search_time_ms INTEGER,

    -- 🔄 v5.1: Step 3.5 Availability Filter
    availability_time_ms INTEGER,

    -- Step 4: Visual Rerank (LLM Reranker)
    final_matches JSONB,
    rerank_time_ms INTEGER,

    -- Totals
    total_time_ms INTEGER,
    items_detected INTEGER,
    items_matched INTEGER,

    user_feedback JSONB,

    -- 🔄 v5.1: Поля для калибровки порогов и A/B тестов
    used_ximilar_booster BOOLEAN DEFAULT FALSE,     -- pgvector неуверен → вызвали Ximilar
    used_ximilar_tagging BOOLEAN DEFAULT FALSE,     -- search неуверен → вызвали Ximilar /tag
    pgvector_top1_score FLOAT,                      -- распределение скоров pgvector
    pgvector_margin FLOAT,                          -- top1 - top2, gap
    ximilar_top1_score FLOAT,                       -- скор Ximilar (если вызывался)
    candidates_after_availability SMALLINT,          -- сколько осталось после post-filter

    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_recognition_user ON recognition_requests(user_id);
CREATE INDEX idx_recognition_created ON recognition_requests(created_at DESC);
```

### 🔄 v5.1: Emergency Rollback (feature flags)

Все ключевые решения pipeline управляются env-переменными. Откат не требует деплоя кода.

| Сценарий | Env (на каком сервере) | Значение | Время |
|----------|------------------------|----------|-------|
| pgvector accuracy <80% | `SEARCH_BACKEND` (ximilar-gw) | `ximilar` | 1 мин |
| pgvector latency >1s | `SEARCH_BACKEND` (ximilar-gw) | `ximilar` | 1 мин |
| Ximilar API down | `SEARCH_BACKEND` (ximilar-gw) | `pgvector` | 1 мин |
| Tagging просадка >5% | `TAGGING_MODE` (recognition) | `always` | 1 мин |
| Availability = 0 results | `AVAILABILITY_WINDOW` (recognition) | `48h` | 1 мин |
| Availability = 0 results | `MIN_CANDIDATES` (recognition) | увеличить | 1 мин |

### Связь с каталогом

Recognition Pipeline зависит от актуальности каталога в двух хранилищах:
- **Ximilar Sync Server (10.1.0.11)** — 2 фото/SKU в Ximilar Collection (пилотные бренды)
- **embed-batch (10.1.0.17)** — 🔄 v5.1: все 5-7 фото/SKU в pgvector (`sku_image_embeddings`)
- **Staging DB (10.1.0.8)** — 🔄 v5.1: `raw_availability` для post-filter (Step 3.5)

---

## 9. XIMILAR GATEWAY (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | ximilar-gw |
| **Private IP** | 10.1.0.12 |
| **Public IP** | 89.167.99.162 |
| **Тип** | Hetzner CX23 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |
| **Git** | http://gitlab-real.unde.life/unde/ximilar-gw.git |
| **Статус** | ✅ Развёрнут, контейнер running |

### Назначение (🔄 v5.1: расширено)

Единая точка для visual search (dual retrieval) и Ximilar API:
- **POST /detect** — Fashion Detection: bounding boxes + готовые crops + категория. Качество 9.5/10.
- **POST /tag** — Fashion Tagging: Pantone цвет, материал, принт. **🔄 v5.1: вызывается on-demand** (40-60% запросов).
- **POST /search** — **🔄 v5.1: Dual Retrieval** — pgvector kNN (primary, через embedder 10.1.0.15 → Production DB) + conditional Ximilar booster. Управляется `SEARCH_BACKEND`.

### Почему отдельный сервер

- **Один внешний API:** все вызовы к Ximilar изолированы. Ximilar упал → pgvector продолжает работать
- **🔄 v5.1: Dual retrieval:** ximilar-gw координирует pgvector + Ximilar, merge + deduplicate
- **Единый rate limiting:** Ximilar имеет свои лимиты — одна точка управления
- **Один API-ключ:** безопасность — ключ Ximilar только на этом сервере
- **Мониторинг:** latency, ошибки, rate limits Ximilar отслеживаются отдельно

### Почему CX23

Лёгкий JSON-прокси: пересылает запросы в Ximilar API и/или embedder + pgvector. Все операции async I/O bound. CPU работа (нормализация, merge, dedup) — микросекунды. FastAPI + asyncio легко держит 100+ concurrent requests.

### HTTP API (🔄 v5.1: обновлённый /search)

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
  🔄 v5.1: вызывается on-demand (TAGGING_MODE=on_demand)

POST /search (🔄 v5.1: dual retrieval)
  Body: {
    "crop_url": "...",
    "category": "jacket",
    "top_k": 50,                          # 🔄 v5.1: TOP-50 вместо TOP-10
    "user_mall": "Dubai Hills Mall"        # 🔄 v5.1: для brand pre-filter в pgvector
  }
  Response: {
    "candidates": [{"brand": "zara", "external_id": "12345", "score": 0.87,
      "image_urls": [...], "metadata": {"name": "...", "price": ..., "category": "..."}}],
    "pgvector_confident": true,            # 🔄 v5.1
    "used_ximilar": false,                 # 🔄 v5.1
    "pgvector_top1_score": 0.89,           # 🔄 v5.1
    "pgvector_margin": 0.15,               # 🔄 v5.1
    "ximilar_top1_score": null             # 🔄 v5.1 (null если не вызывался)
  }
  Метаданные: глобальные (brand, external_id, name, price, category, colour).
    БЕЗ store/floor/mall — это подтягивается в Step 3.5 из raw_availability.
  Latency: 5-500ms (5-20ms pgvector only, +200-500ms если Ximilar booster)
```

### 🔄 v5.1: Dual Retrieval логика в ximilar-gw

```python
# Pseudo: /search endpoint
async def search(crop_url, category, top_k, user_mall):
    # 1. pgvector kNN (ВСЕГДА)
    crop_embedding = await embedder.embed(crop_url)  # → 10.1.0.15, 100-250ms

    # Brand pre-filter: только бренды, присутствующие в ТЦ юзера
    mall_brands = await get_mall_brands(user_mall)    # кеш из raw_stores
    pgvector_results = await pgvector_knn(
        crop_embedding, limit=top_k, brands=mall_brands  # Production DB
    )

    # 2. GATING
    pgvector_confident = (
        pgvector_results[0].score >= CONFIDENCE_THRESHOLD  # 0.80
        and (pgvector_results[0].score - pgvector_results[1].score) >= MARGIN  # 0.10
    )

    used_ximilar = False
    ximilar_results = []

    if SEARCH_BACKEND == "conditional" and not pgvector_confident:
        try:
            ximilar_results = await ximilar_search(crop_url, limit=100)
            used_ximilar = True
        except (XimilarTimeout, XimilarError) as e:
            log_to_posthog("ximilar_search_error", error=str(e))
            ximilar_results = []  # graceful fallback → pgvector only
    elif SEARCH_BACKEND == "dual":
        ximilar_results = await ximilar_search(crop_url, limit=100)
        used_ximilar = True
    elif SEARCH_BACKEND == "ximilar":
        ximilar_results = await ximilar_search(crop_url, limit=top_k)
        used_ximilar = True
        pgvector_results = []  # Phase 1 fallback

    return merge_and_deduplicate(pgvector_results, ximilar_results)
```

### 🔄 v5.1: Feature flag

```
SEARCH_BACKEND = ximilar | pgvector | conditional | dual

- ximilar:      только Ximilar API (Phase 1, MVP)
- pgvector:     только pgvector kNN (Phase 3, экономия credits)
- conditional:  pgvector primary + Ximilar on-demand booster (Phase 2, РЕКОМЕНДУЕМЫЙ)
- dual:         оба ВСЕГДА параллельно → объединение (max quality, max credits)
```

### Docker Compose

```yaml
services:
  ximilar-gw:
    build: .
    container_name: ximilar-gw
    restart: unless-stopped
    command: uvicorn app.main:app --host 0.0.0.0 --port 8001 --workers 4
    env_file: .env
    ports:
      - "10.1.0.12:8001:8001"
    deploy:
      resources:
        limits:
          memory: 2G
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.
> Prometheus app metrics: `GET http://10.1.0.12:8001/metrics` (prometheus-fastapi-instrumentator).

### Environment Variables (🔄 v5.1: dual retrieval)

```bash
# /opt/unde/ximilar-gw/.env

# Ximilar
XIMILAR_API_TOKEN=xxx                    # TODO: заполнить когда получим от Ximilar
XIMILAR_COLLECTION_ID=xxx               # TODO: заполнить когда получим от Ximilar
XIMILAR_API_URL=https://api.ximilar.com

# 🔄 v5.1: Embedding + pgvector
EMBEDDER_URL=http://10.1.0.15:8003      # Runtime embedding server
PRODUCTION_DB_URL=postgresql://undeuser:<password>@10.1.1.2:6432/unde_ai  # pgvector

# 🔄 v5.1: Feature flags
SEARCH_BACKEND=conditional               # ximilar | pgvector | conditional | dual
CONFIDENCE_THRESHOLD=0.80                # pgvector gating
MARGIN=0.10                              # top1 - top2 minimum gap

# Server
HOST=0.0.0.0
PORT=8001
WORKERS=4
```

### Структура директорий (🔄 v5.1)

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
│   │   └── search.py          # POST /search (🔄 v5.1: dual retrieval)
│   ├── ximilar_client.py      # Обёртка над Ximilar SDK
│   ├── pgvector_client.py     # 🔄 v5.1: kNN query к Production DB
│   ├── embedder_client.py     # 🔄 v5.1: HTTP client → embedder (10.1.0.15)
│   ├── merge.py               # 🔄 v5.1: merge + deduplicate results
│   └── rate_limiter.py        # Rate limiting для Ximilar API
├── scripts/
│   ├── health-check.sh
│   └── test-detect.sh
└── deploy/
    └── netplan-private.yaml
```

---

## 10. LLM RERANKER (✅ Работает)

### Информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | llm-reranker |
| **Private IP** | 10.1.0.13 |
| **Public IP** | 89.167.106.167 |
| **Тип** | Hetzner CX23 |
| **vCPU** | 2 |
| **RAM** | 4 GB |
| **Disk** | 40 GB SSD |
| **OS** | Ubuntu 24.04.3 LTS |
| **Git** | http://gitlab-real.unde.life/unde/llm-reranker.git |
| **Статус** | ✅ Развёрнут, контейнер running |

### Назначение

Единая точка для всех LLM-вызовов в Recognition Pipeline:
- **POST /tag** — контекстный тегинг через Gemini 2.5 Flash (vision): стиль, occasion, brand_style, сезон. **🔄 v5.1:** вызывается ВСЕГДА (параллельно с search), это бесплатный контекст для rerank.
- **POST /rerank** — визуальный реранкинг через Gemini 2.5 Flash (vision): [crop с улицы] + [лучшее фото SKU на модели]. Score 0-1. Combined score = 0.7 × visual + 0.3 × semantic. **🔄 v5.1:** получает TOP-10-20 после availability filter (вместо TOP-10 напрямую из search).

### Почему отдельный сервер

- **Другой провайдер:** Gemini API — другие rate limits, другое downtime, другие ключи
- **Другая стоимость:** LLM-вызовы дороже Ximilar — отдельный мониторинг расходов
- **Изоляция отказов:** Gemini недоступен → Detection + Search продолжают работать, Orchestrator отдаёт результаты без реранкинга

### Почему CX23

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
  Latency: 1-2 сек на все 10-20 кандидатов (batch, параллельные вызовы)
```

### Docker Compose

```yaml
services:
  llm-reranker:
    build: .
    container_name: llm-reranker
    restart: unless-stopped
    command: uvicorn app.main:app --host 0.0.0.0 --port 8002 --workers 2
    env_file: .env
    ports:
      - "10.1.0.13:8002:8002"
    deploy:
      resources:
        limits:
          memory: 1G
```

> node_exporter v1.8.2 установлен как systemd сервис (0.0.0.0:9100), не в Docker.
> Prometheus app metrics: `GET http://10.1.0.13:8002/metrics` (prometheus-fastapi-instrumentator).

### Environment Variables

```bash
# /opt/unde/llm-reranker/.env

# Gemini
GEMINI_API_KEY=AIzaSyBQB2jKFgBDLeBIiqeHFVC_8q5INAvr9D0
GEMINI_MODEL=gemini-2.5-flash
GEMINI_API_URL=https://generativelanguage.googleapis.com/v1beta

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
│   ├── main.py               # FastAPI app + Prometheus + /health
│   ├── config.py              # Pydantic Settings from .env
│   ├── gemini_client.py       # Async httpx client → Gemini API
│   └── routes/
│       ├── __init__.py
│       ├── tag.py             # POST /tag (Gemini context tagging)
│       └── rerank.py          # POST /rerank (Gemini visual rerank)
├── scripts/
│   ├── health-check.sh
│   └── test-tag.sh
└── data/                      # Empty, for future use
```

---

## 🔄 v5.1: EMBEDDING СЕРВЕРЫ (Phase 2.5 — NEW)

> **Два сервера, полная изоляция:** runtime inference (embedder) и фоновая индексация (embed-batch) — разные физические серверы, нулевое влияние batch на latency.

### 11. EMBEDDER — Runtime Inference (Phase 2.5)

| Параметр | Значение |
|----------|----------|
| **Hostname** | embedder |
| **Private IP** | 10.1.0.15 |
| **Тип** | Hetzner Auction (i7-8700, 64 GB RAM, 2×512 GB NVMe SSD, HEL1-DC2) |
| **€/мес** | ~€36.70 |
| **Endpoint** | `POST /embed` — принимает crop image, возвращает vector(512) |
| **Модель** | FashionCLIP 2.0 (512-dim), ONNX Runtime |
| **Latency** | 100-250ms |
| **Throughput** | 5-10 img/sec (достаточно для 5K+ юзеров) |
| **Вызывается из** | ximilar-gw (10.1.0.12) при `/search` |
| **Статус** | 🆕 Заказан |

```python
# embedder: latency-optimized
import onnxruntime as ort
opts = ort.SessionOptions()
opts.intra_op_num_threads = 4
opts.inter_op_num_threads = 1
opts.graph_optimization_level = ort.GraphOptimizationLevel.ORT_ENABLE_ALL
```

### 12. EMBED-BATCH — Фоновая индексация (Phase 2.5)

| Параметр | Значение |
|----------|----------|
| **Hostname** | embed-batch |
| **Private IP** | 10.1.0.17 |
| **Тип** | Hetzner Auction (i7-8700, 64 GB RAM, 2×512 GB SSD, HEL1) |
| **€/мес** | ~€36.70 |
| **Endpoint** | `POST /embed_batch` — batch embed из S3, insert в pgvector |
| **Throughput** | 5-10 img/sec (все ресурсы под batch) |
| **Вызывается из** | Celery worker `embedding-sync` (cron / по событию) |
| **Статус** | 🆕 Создать |

```python
# embed-batch: throughput-optimized
opts = ort.SessionOptions()
opts.intra_op_num_threads = 4
opts.inter_op_num_threads = 2
# 1-2 worker процесса × 6 threads = 6-12 ≤ 12 HW threads
```

### Таблица embeddings (Production DB)

```sql
-- Production DB (10.1.1.2), база unde_ai

CREATE TABLE sku_image_embeddings (
    id bigserial PRIMARY KEY,
    sku_id text NOT NULL,            -- raw_products.external_id
    brand text NOT NULL,             -- raw_products.brand (составной ключ с sku_id)
    image_url text NOT NULL,
    image_rank smallint NOT NULL,    -- 0..6 (порядок фото)
    image_hash text NOT NULL,        -- SHA256, для idempotency
    embedding vector(512),           -- FashionCLIP dimension
    model_version text NOT NULL DEFAULT 'fashionclip-2.0',
    metadata jsonb,                  -- price, category, colour
    created_at timestamptz DEFAULT now(),

    UNIQUE (brand, sku_id, image_hash, model_version)
);

CREATE INDEX sku_image_embeddings_hnsw
    ON sku_image_embeddings
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

CREATE INDEX sku_image_embeddings_brand
    ON sku_image_embeddings (brand);
```

**Per-image, не per-SKU**: каждое фото — отдельная строка. 47K SKU × 5 фото = ~235K строк, ~10-15 GB индекса. Production DB (64 GB RAM) — легко.

### Оценки времени batch

| Операция | Объём | Время |
|----------|-------|-------|
| Initial load (все 6 брендов) | 47K SKU × 5 фото = 235K img | 8-13 часов (на ночь) |
| Новый бренд (средний) | ~8K SKU × 5 = 40K img | 1-2 часа |
| Новая коллекция (малая) | 1K SKU × 5 = 5K img | 10-20 мин |
| Progressive ingestion (недельная) | 100-500 фото | 1-3 мин |

---
