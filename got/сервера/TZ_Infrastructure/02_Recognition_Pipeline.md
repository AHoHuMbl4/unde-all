# UNDE Infrastructure — Fashion Recognition Pipeline

*Серверы распознавания одежды.*

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
| **Private IP** | 10.1.0.14 |
| **Тип** | Hetzner CPX11 |
| **vCPU** | 2 |
| **RAM** | 2 GB |
| **Disk** | 40 GB NVMe |
| **OS** | Ubuntu 24.04 LTS |

### Назначение

Координатор Fashion Recognition Pipeline:
- Принимает Celery task из Redis (от App Server)
- Вызывает Ximilar Gateway (10.1.0.12) и LLM Reranker (10.1.0.13) по HTTP
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
│  10.1.0.4       │◄───────►│  10.1.0.14                    │
│  Redis Broker   │         │                               │
└─────────────────┘         │  2 Celery workers (I/O bound) │
                            └──┬─────────────────────┬──────┘
                               │                     │
                               ▼                     ▼
                    ┌─────────────────┐   ┌─────────────────┐
                    │ XIMILAR GATEWAY │   │ LLM RERANKER    │
                    │ 10.1.0.12       │   │ 10.1.0.13       │
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
      - "10.1.0.14:9100:9100"
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
    BASE = "http://10.1.0.12:8001"
    def detect(self, url): return post(f"{self.BASE}/detect", json={"url": url})
    def tag(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def search(self, **kw): return post(f"{self.BASE}/search", json=kw)

class LLMReranker:
    BASE = "http://10.1.0.13:8002"
    def tag_context(self, url): return post(f"{self.BASE}/tag", json={"url": url})
    def visual_rerank(self, **kw): return post(f"{self.BASE}/rerank", json=kw)
```

### Environment Variables

```bash
# /opt/unde/recognition/.env

# Внутренние серверы (private network)
XIMILAR_GW_URL=http://10.1.0.12:8001
LLM_RERANKER_URL=http://10.1.0.13:8002

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
│   │   ├── ximilar_gw.py      # HTTP client → 10.1.0.12
│   │   └── llm_reranker.py    # HTTP client → 10.1.0.13
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
- **Ximilar Sync Server (10.1.0.11)** выполняет `ximilar_sync` еженедельно после сбора каталога
- Новые/обновлённые SKU с фото автоматически загружаются в Ximilar Collection
- Ximilar Gateway использует ту же Collection для Visual Search (Step 3)

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

### Почему CX23

Лёгкий JSON-прокси: пересылает запросы в Ximilar API и возвращает ответы. I/O bound, минимум CPU/RAM. FastAPI + 4 uvicorn workers.

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

### Environment Variables

```bash
# /opt/unde/ximilar-gw/.env

# Ximilar
XIMILAR_API_TOKEN=xxx                    # TODO: заполнить когда получим от Ximilar
XIMILAR_COLLECTION_ID=xxx               # TODO: заполнить когда получим от Ximilar
XIMILAR_API_URL=https://api.ximilar.com

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
- **POST /tag** — контекстный тегинг через Gemini 2.5 Flash (vision): стиль (streetwear vs preppy vs minimalist), occasion (office, date, casual), brand_style (oversized, cropped, fitted), сезон. Контекст, который Ximilar не умеет — требует 'понимания', а не классификации.
- **POST /rerank** — визуальный реранкинг через Gemini 2.5 Flash (vision): получает 2 фото [crop с улицы] + [лучшее фото SKU на модели из каталога], сравнивает силуэт, цвет, фактуру, детали. Score 0-1. Combined score = 0.7 × visual + 0.3 × semantic.

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
  Latency: 1-2 сек на все 10 кандидатов (batch, параллельные вызовы)
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
