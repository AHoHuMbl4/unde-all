# UNDE Infrastructure — Server Layout v7.1

*Обновление архитектуры: Локальные серверы (hot path) + Hetzner Helsinki (core/batch). Масштаб: 10–50K MAU.*

---

## Принципы (обновлённые)

- **1 сервер = 1 задача** — изоляция для отладки и масштабирования
- **Локальные серверы для hot path** — всё, что на critical path диалога (юзер ждёт ответа), живёт локально рядом с юзерами
- **Helsinki для batch/core** — каталог, recognition, scraping, аналитика, реплики, бэкапы
- **Ограничение локальных серверов:** макс. 16 vCPU / 32 GB RAM на сервер
- **Голос на API (ElevenLabs)** — переход на свой TTS при появлении отдельного разработчика
- **Шардирование с первого дня** — 32 GB RAM/шард → раннее горизонтальное масштабирование
- **Failover: auto → Helsinki replica** — при падении локальных серверов, деградация с ростом latency

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
                       ▼                   ▼                   │
              ┌─────────────────────────────────────────────────────────┐
              │              HETZNER HELSINKI                           │
              │                                                        │
              │  Apify → Photo DL → Collage → Ximilar Sync            │
              │       ↘         ↘                                      │
              │     Staging DB    Object Storage                       │
              │         ↓                                              │
              │     Scraper → Production DB ←── Recognition pipeline   │
              │                    │                                    │
              │     Shard Replicas (hot standby × N)                   │
              │     PostHog (product analytics)                        │
              │     Monitoring (Prometheus + Grafana + Alertmanager)   │
              │     Helsinki GW (Debian + MikroTik CHR)               │
              │     etcd-2, etcd-3 (Patroni quorum)                   │
              └────────────────────┬───────────────────────────────────┘
                                   │
                                   │ ~120ms RTT
                                   │ WireGuard (каждый сервер — отдельный туннель)
                                   │
              ┌────────────────────┴───────────────────────────────────┐
              │              ЛОКАЛЬНЫЕ СЕРВЕРЫ                         │
              │              (рядом с юзерами, <5ms RTT)               │
              │                                                        │
              │  App Server ──→ LLM Orchestrator                       │
              │       │              │                                  │
              │       │         ┌────┼────┬────────┐                   │
              │       │         ▼    ▼    ▼        ▼                   │
              │       │       Mood Persona Context Redis               │
              │       │         │    │    │        │                    │
              │       │         └────┴────┴────────┘                   │
              │       │              │  <1ms                           │
              │       │              ▼                                  │
              │       │     User Data Shards (1..N)                    │
              │       │                                                │
              │       └──→ Voice Server ──→ ElevenLabs API             │
              │                                                        │
              │  etcd-1 (Patroni quorum)                               │
              └────────────────────────────────────────────────────────┘
                                   │
                                   │ <5ms
                                   ▼
                            ┌──────────────┐
                            │ 📱 ПРИЛОЖЕНИЕ│
                            └──────────────┘
```

---

## Карта серверов

### ЛОКАЛЬНЫЕ серверы (hot path — dialogue critical path)

> Ограничение: макс. 16 vCPU / 32 GB RAM на сервер. Провайдер определяется по локации юзеров.

| # | Сервер | Конфиг | Задача | Статус |
|---|--------|--------|--------|--------|
| L1 | **local-app** | 4 vCPU / 8 GB | API gateway (Nginx + FastAPI). Единственная точка входа для юзеров | 🆕 Создать |
| L2 | **local-orchestrator** | 8 vCPU / 16 GB | LLM Orchestrator: ContextPack (3 слоя знания), embedding client, двухстадийная генерация (Consultant + Voice), instant pattern extract, correction detect | 🆕 Создать |
| L3 | **local-redis** | 2 vCPU / 4 GB | Redis: hot cache (mood, context, catalog), rate limit, debounce, shard routing cache | 🆕 Создать |
| L4 | **local-mood** | 2 vCPU / 4 GB | Mood Agent: signal mood (<50ms) + context mood (<200ms), voice-text mismatch detection | 🆕 Создать |
| L5 | **local-persona** | 2 vCPU / 4 GB | Persona Agent: relationship stage, 22 communication fields, tone modes, voice presets, avatar state, render hints | 🆕 Создать |
| L6 | **local-context** | 2 vCPU / 4 GB | Context Agent: гео, погода (30 мин кеш), время, события (1 ч кеш), культура (24 ч кеш), OpportunityMatcher | 🆕 Создать |
| L7 | **local-voice** | 2 vCPU / 4 GB | Voice Server: ElevenLabs proxy, WebSocket streaming для lip-sync, кеш частых фраз | 🆕 Создать |
| L8 | **local-shard-0** | **16 vCPU / 32 GB** | User Data Shard 0: PostgreSQL 17 + pgvector. Chat History (64 партиции) + User Knowledge (AES-256) + Persona tables | 🆕 Создать |
| L9 | **local-etcd-1** | 1 vCPU / 2 GB | etcd node для Patroni (локальный голос primary) | 🆕 Создать |

**Масштабирование шардов (по мере роста):**

| Этап | MAU | Шарды | Доп. серверы |
|------|-----|-------|-------------|
| Старт | 0–800 | 1 (local-shard-0) | — |
| 5K | ~800–2,000 | 2 | + local-shard-1 (16 vCPU / 32 GB) |
| 10K | ~2,000–4,000 | 4 | + local-shard-2, local-shard-3 |
| 25K | ~4,000–10,000 | 8 | + local-shard-4..7 |
| 50K | ~10,000–20,000 | 16 | + local-shard-8..15 |

> **Расчёт:** 32 GB RAM → shared_buffers 8 GB, effective_cache_size ~24 GB. HNSW индекс на 500 юзеров = ~11 GB (через 1 год). Комфортная ёмкость: **~500–800 юзеров/шард** (1 год данных). Триггер: `pg_relation_size('idx_messages_embedding') > 20 GB`.

**Масштабирование stateless сервисов (при 25K+ MAU):**

| Сервис | Когда масштабировать | Как |
|--------|---------------------|-----|
| App Server | p95 response > 200ms | + local-app-2 + балансировщик |
| LLM Orchestrator | queue > 20, p95 > 10s | + local-orchestrator-2 |
| Redis | memory > 80% | Redis Sentinel (2 ноды) |
| Агенты (Mood/Persona/Context) | p95 > 2x target | + replica сервер |

---

### HETZNER HELSINKI — существующие серверы

| # | Сервер | IP (private) | IP (public) | Тип | Статус |
|---|--------|-------------|-------------|-----|--------|
| H1 | **helsinki-gw** | 10.1.0.2 | 46.62.233.30 | CX23 | ✅ Установлен (бывший unde-app, переназначен как router) |
| H2 | scraper | 10.1.0.3 | 46.62.255.184 | CPX22 | ✅ Работает |
| H3 | push | 10.1.0.4 | 77.42.30.44 | CPX32 | ✅ Работает |
| H4 | model-generator | 10.1.0.5 | 89.167.20.60 | CPX22 | ✅ Работает |
| H5 | tryon-service | 10.1.0.6 | 89.167.31.65 | CPX22 | ✅ Работает |
| H6 | Production DB | 10.1.1.2 | — | AX41 (dedicated) | ✅ Работает |
| — | GitLab | — | gitlab-real.unde.life | — | ✅ Работает |

**Изменение ролей существующих серверов:**

| Сервер | Старая роль | Новая роль |
|--------|-------------|-----------|
| **unde-app (H1)** | API gateway (единственная точка входа) | **helsinki-gw** — Debian 12 + MikroTik CHR. WireGuard endpoint, routing, firewall |
| **push (H3)** | Redis + Celery broker | **Batch Redis + Celery broker** — для recognition queue, catalog pipeline, enrichment TTL recovery. Hot path Redis → local-redis |

---

### HETZNER HELSINKI — новые серверы

| # | Сервер | IP (private) | Тип | €/мес | Задача | Статус |
|---|--------|-------------|-----|-------|--------|--------|
| H7 | **apify** | 10.1.0.9 | CX23 | €12 | Сбор метаданных каталога (Apify.com, 6 брендов) | ✅ Создан |
| H8 | **collage** | 10.1.0.16 | CX33 | €25 | Склейка фото (горизонтальные коллажи для try-on) | ✅ Создан |
| H9 | **recognition** | 10.1.0.14 | CX23 | €6 | Recognition Orchestrator (координация 4-step pipeline) | ✅ Создан |
| H10 | **photo-downloader** | 10.1.0.10 | CX23 | €12 | Скачивание фото брендов → Object Storage | ✅ Создан |
| H11 | **ximilar-sync** | 10.1.0.11 | CX23 | €6 | Синхронизация каталога → Ximilar Collection | ✅ Создан |
| H12 | **ximilar-gw** | 10.1.0.12 | CX23 | €12 | Ximilar Gateway (/detect, /tag, /search) | ✅ Создан |
| H13 | **llm-reranker** | 10.1.0.13 | CX23 | €6 | LLM Reranker (Gemini visual comparison) | ✅ Создан |
| H14 | **staging-db** | 10.1.0.8 | CPX22 | €12 | PostgreSQL staging (raw_products, raw_availability) | ✅ Создан |
| H15 | **shard-replica-0** | 10.1.1.10 | CCX23 (4 vCPU / 16 GB) | €39 | Hot standby replica шарда 0 (Patroni + streaming replication) | 🆕 Создать |
| H16 | **etcd-2** | на shard-replica-0 | контейнер | €0 | etcd quorum node 2 (на сервере реплики) | 🆕 Создать |
| H17 | **etcd-3** | 10.1.0.15 | CX23 | €4 | etcd quorum node 3 (tiebreaker) | ✅ Создан |
| H18 | **posthog** | 10.1.0.30 | CCX33 (8 vCPU / 32 GB) | €74 | PostHog self-hosted: product analytics (ClickHouse + PG + Redis + Kafka) | 🆕 Создать |
| H19 | **monitoring** | 10.1.0.7 | CX33 | €25 | Prometheus + Grafana + Alertmanager. Единый центр мониторинга обеих площадок | ✅ Создан |
| ~~H20~~ | ~~helsinki-gw~~ | — | — | — | Перенесён на H1 (бывший unde-app, CX23, 10.1.0.2 / 46.62.233.30) | ✅ Установлен |
| — | **Object Storage** | — | S3-compatible | ~€10 | unde-images (/originals/, /collages/), unde-user-media, backups | 🆕 Создать |

**Масштабирование реплик (при добавлении шардов):**

| Шарды | Реплики в Helsinki | Доп. стоимость |
|-------|-------------------|----------------|
| 1 | shard-replica-0 (CCX23, 16 GB) | €39/мес |
| 2 | + shard-replica-1 (CCX23) | +€39/мес |
| 4 | + shard-replica-2, 3 (CCX23) | +€78/мес |
| 8+ | CCX33 (32 GB) для реплик при росте данных | +€74/шт |

> **Почему CCX23 (16 GB) для реплик, а не 32 GB как primary:** Реплика не держит HNSW в RAM постоянно — она нужна для failover и бэкапов. При failover поднимается как primary с деградацией производительности до восстановления основного шарда.

---

## Стоимость

### Стартовая конфигурация (1 шард, 0–800 MAU)

| Компонент | Серверов | Стоимость/мес |
|-----------|---------|---------------|
| **Локальные (hot path)** | 9 | Зависит от провайдера* |
| **Helsinki существующие** | 6 | Уже оплачены |
| **Helsinki новые** | 10 + storage | ~€218/мес |
| **PostHog** | 1 | €74/мес |
| **Monitoring** | 1 | €25/мес |
| **Helsinki GW (router)** | 1 | €12/мес |
| **Итого Helsinki новые** | | **~€329/мес** |

*Ориентировочная стоимость локальных серверов (суммарно ~37 vCPU, 76 GB RAM):*

| Провайдер | Оценка/мес | Примечание |
|-----------|-----------|-----------|
| Dubai local (cloud) | $300–600 | Зависит от провайдера |
| Hetzner Singapore | ~€176 | CPX/CCX серия |
| Другой local DC | $200–500 | Зависит от региона |

### Масштаб 10K MAU (~4 шарда)

| Компонент | Стоимость/мес |
|-----------|---------------|
| Локальные: 9 base + 3 доп. шарда | ~$500–900 |
| Helsinki: существующие + новые | ~€329 |
| Helsinki: 3 доп. реплики (CCX23) | €117 |
| **Итого** | **~€740–1,140/мес** |

### Масштаб 50K MAU (~16 шардов + stateless scaling)

| Компонент | Стоимость/мес |
|-----------|---------------|
| Локальные: ~25 серверов (16 шардов + 9 stateless) | ~$2,000–3,500 |
| Helsinki: существующие + новые | ~€329 |
| Helsinki: 16 реплик (CCX23/CCX33) | €600–1,200 |
| Helsinki: PostHog upgrade (отдельный ClickHouse) | €150 |
| **Итого** | **~€2,500–4,500/мес** |

---

## Конфигурация шарда (32 GB RAM, без tmpfs)

### PostgreSQL на локальном сервере (NVMe SSD)

```ini
# postgresql.conf — оптимизация для 32 GB RAM, NVMe SSD

# Буферы
shared_buffers = 8GB                # 25% RAM
effective_cache_size = 24GB         # 75% RAM (OS page cache)
work_mem = 40MB
maintenance_work_mem = 2GB
wal_buffers = 64MB

# Планировщик: NVMe SSD
random_page_cost = 1.1              # NVMe ≈ sequential
seq_page_cost = 1.0
effective_io_concurrency = 200      # NVMe parallel IO

# Durability
fsync = on
synchronous_commit = local          # WAL flush перед ack
full_page_writes = on               # Для корректности WAL на реплике

# WAL
wal_level = replica
max_wal_senders = 5
wal_keep_size = 4GB
max_replication_slots = 5
checkpoint_timeout = 10min
max_wal_size = 2GB

# Connections (через PgBouncer)
max_connections = 100

# Archive (для PITR backup)
archive_mode = on
archive_command = 'pgbackrest --stanza=shard0 archive-push %p'
```

### Производительность: 32 GB NVMe vs 256 GB tmpfs

| Метрика | 32 GB NVMe (local) | 256 GB tmpfs (bare metal) |
|---------|-------------------|--------------------------|
| HNSW traversal (150 reads) | 1.5–3 ms (hot cache) / 5–10 ms (cold) | ~10 μs |
| Heap fetch (20 reads) | 0.2–0.5 ms | ~1.4 μs |
| Full hybrid search | 2–5 ms (hot) / 10–20 ms (cold) | <100 μs |
| 1,000 concurrent queries p95 | 10–30 ms | <1 ms |

> **Компенсация:** При 500–800 юзерах/шард весь working set (~11–18 GB HNSW + ~15–25 GB heap) помещается в effective_cache_size (24 GB) + shared_buffers (8 GB). Кеш будет тёплым при стабильной нагрузке. Деградация заметна только при cold start или spike нагрузки.

---

## Latency Budget

### После миграции (hot path локально)

```
User → local-app:                     <5ms
App → Orchestrator:                    <1ms
Orchestrator → Mood (параллельно):     <1ms + 50-200ms compute
Orchestrator → Persona (параллельно):  <1ms + 15ms compute
Orchestrator → Context (параллельно):  <1ms + 100ms compute (cached)
Orchestrator → Redis (cache):          <1ms
Orchestrator → Shard (hybrid search):  <1ms + 2-5ms query
Orchestrator → Shard (UK, recent):     <1ms + 1-2ms query
Orchestrator → LLM API:                800-1200ms (внешний, основной bottleneck)
Voice → ElevenLabs:                    200-500ms (внешний)
───────────────────────────────────────
Сетевой overhead (локальный):          ~10ms
Итого с LLM + TTS:                    ~1.5–2.5s до первого audio chunk
```

### Для сравнения: всё в Helsinki

```
Сетевой overhead:                      ~500-600ms (120ms × 4-5 hops)
Итого с LLM + TTS:                    ~2.5–3.5s до первого audio chunk
```

### Выигрыш: ~500ms на КАЖДЫЙ запрос

Для voice-first UX:
- **<300ms** — ощущается как живой диалог
- **300–500ms** — заметная пауза
- **>500ms** — "тупит"

Экономия 500ms переводит UX из зоны "тупит" в зону "заметная пауза → живой диалог".

### Обращения к Helsinki (не на critical path)

| Запрос | Когда | Latency | Частота |
|--------|-------|---------|---------|
| Catalog lookup (Production DB) | Cache miss в Redis | ~120ms | Редко (кеш тёплый) |
| Fashion Recognition | Юзер загрузил фото | ~120ms + 2-4s pipeline | Async, юзер видит progressive loading |
| Catalog sync | Scraper cron | ~120ms | Каждый час, batch |
| Shard replica streaming | Continuous WAL | ~120ms | Фоновый поток |

---

## Redis Topology

### Два инстанса Redis (разделение hot path и batch)

```
ЛОКАЛЬНО: local-redis (2 vCPU / 4 GB)
├── Shard routing cache (user_id → shard connection)
├── Catalog cache (top products, hot SKUs)
├── Mood/Context frames (TTL 5 min)
├── Rate limiting (per-user)
├── Debounce (pending messages)
├── Persona LRU cache (100 profiles)
└── Session metadata

HELSINKI: push (10.1.0.4) — существующий
├── Celery broker (recognition queue, enrichment queue)
├── Recognition results (async → App)
├── Batch pipeline coordination
└── Catalog pipeline status
```

> **Batch в Helsinki** не обращается к local-redis. Разделение полное — нет cross-DC Redis трафика.

---

## Failover сценарии

### Сценарий 1: Падение одного локального шарда

```
00:00  — local-shard-0 недоступен
00:05  — Patroni: "Primary не отвечает 5 сек"
00:15  — Patroni promotes shard-replica-0 в Helsinki
00:16  — local-redis обновляет routing: shard-0 → Helsinki IP
         Юзеры шарда 0: +120ms на каждый запрос к DB
         Остальные шарды: без изменений

RTO: ~15-30 сек
RPO: 0 (client-side verify-and-replay)
Деградация: +120ms для ~1/N юзеров (N = кол-во шардов)
```

### Сценарий 2: Падение всех локальных серверов (DC down)

```
00:00  — Вся локальная площадка недоступна
00:15  — Patroni promotes все реплики в Helsinki
         und-app (H1) принимает юзерский трафик (DNS failover)
         LLM Orchestrator работает на Helsinki (нужен warm standby или поднять)

RTO: 1-5 мин (зависит от readiness Helsinki Orchestrator)
Деградация: +500ms для всех юзеров (как до миграции)
```

> **Helsinki warm standby:** LLM Orchestrator и агенты УЖЕ были в Helsinki (H1 / существующие). При DC failover — переключить трафик обратно на Helsinki серверы. Это требует:
> - DNS failover (или Cloudflare load balancer)
> - Helsinki Orchestrator (H1 или поднять новый контейнер)
> - Helsinki Redis (push/H3 уже есть)

### Сценарий 3: Падение Helsinki

```
00:00  — Hetzner Helsinki недоступен
         Локальные серверы продолжают работать (шарды primary)
         Каталог: из Redis cache (тёплый)
         Recognition: недоступен (graceful degradation: "Функция временно недоступна")
         Реплики: недоступны (accumulating WAL на primary)
         Бэкапы: приостановлены

Действие: мониторинг WAL accumulation, при >20GB — alert
```

---

## Сетевая связность

### Архитектура: каждый локальный сервер — отдельный WireGuard туннель

**Почему не один шлюз на локальной стороне:**
- У каждого локального сервера своё ограничение по трафику
- Отдельные туннели распределяют трафик по квотам каждого сервера
- Нет единого bottleneck — если один сервер упал, остальные туннели работают
- Проще масштабировать — добавил сервер, добавил туннель

### Helsinki Router/Firewall: Debian + MikroTik CHR

На стороне Helsinki — выделенный сервер-роутер. Debian как хост, MikroTik CHR как VM (KVM). CHR принимает все входящие WireGuard туннели и маршрутизирует трафик в private network Helsinki.

```
ЛОКАЛЬНЫЕ СЕРВЕРЫ                            HETZNER HELSINKI

local-app ──────── WG tunnel ──────┐
  (10.2.0.2)                       │
                                   │
local-orchestrator ─ WG tunnel ────┤
  (10.2.0.17)                      │
                                   │
local-redis ──────── WG tunnel ────┤
  (10.2.0.4)                       │
                                   │     ┌──────────────────────┐
local-mood ───────── WG tunnel ────┤     │  HELSINKI-GW (H20)   │
  (10.2.0.11)                      ├────►│  10.1.0.2           │
                                   │     │  Debian 12 + KVM     │
local-persona ────── WG tunnel ────┤     │  MikroTik CHR (VM)   │
  (10.2.0.21)                      │     │                      │
                                   │     │  Роли:               │
local-context ────── WG tunnel ────┤     │  • WireGuard endpoint│
  (10.2.0.19)                      │     │    (N туннелей)      │
                                   │     │  • Routing            │
local-voice ──────── WG tunnel ────┤     │    10.2.0.0/24 ↔     │
  (10.2.0.12)                      │     │    10.1.0.0/16       │
                                   │     │  • Firewall           │
local-shard-0 ────── WG tunnel ────┤     │  • NAT (если нужен)  │
  (10.2.0.10)                      │     │  • Traffic monitoring │
                                   │     └──────────┬───────────┘
local-etcd-1 ─────── WG tunnel ────┘               │
  (10.2.0.50)                               Private network
                                            10.1.0.0/16
                                                │
                                   ┌────────────┼────────────┐
                                   │            │            │
                                   ▼            ▼            ▼
                             Production DB  Shard Replica  Все Helsinki
                              (10.1.1.2)   (10.1.1.10)    серверы
```

### Helsinki Router — конфигурация

| Параметр | Значение |
|----------|----------|
| **Hostname** | helsinki-gw |
| **IP (private)** | 10.1.0.2 |
| **IP (public)** | Назначается Hetzner |
| **Тип** | CPX22 (2 vCPU / 4 GB / 80 GB) |
| **Стоимость** | €12/мес |
| **ОС хоста** | Debian 12 (Bookworm) |
| **Router VM** | MikroTik CHR (RouterOS v7, KVM) |
| **Лицензия CHR** | P1 ($45 разово, unlimited speed) |

**Почему Debian + MikroTik CHR (а не RouterOS напрямую):**
- Debian хост даёт доступ к Linux-инструментам (мониторинг, обновления, диагностика)
- CHR в KVM — изолированный роутер с полным RouterOS функционалом
- Winbox GUI для управления правилами
- При необходимости — можно поставить второй CHR VM (hot standby)

### WireGuard туннели

| Локальный сервер | WG interface | Tunnel IP (local) | Tunnel IP (Helsinki) | Назначение |
|------------------|--------------|--------------------|----------------------|-----------|
| local-app | wg-app | 10.3.0.1/32 | 10.3.0.100/32 | API → Recognition, PostHog events |
| local-orchestrator | wg-orch | 10.3.1.1/32 | 10.3.1.100/32 | → Recognition, Production DB (cache miss) |
| local-redis | wg-redis | 10.3.2.1/32 | 10.3.2.100/32 | Минимальный (routing sync) |
| local-mood | wg-mood | 10.3.3.1/32 | 10.3.3.100/32 | Минимальный |
| local-persona | wg-persona | 10.3.4.1/32 | 10.3.4.100/32 | Минимальный |
| local-context | wg-context | 10.3.5.1/32 | 10.3.5.100/32 | → Weather API (если через Helsinki) |
| local-voice | wg-voice | 10.3.6.1/32 | 10.3.6.100/32 | Минимальный |
| local-shard-0 | wg-shard0 | 10.3.10.1/32 | 10.3.10.100/32 | **Главный:** streaming replication → replica |
| local-etcd-1 | wg-etcd | 10.3.50.1/32 | 10.3.50.100/32 | etcd cluster heartbeat |

**Трафик по туннелям (оценка):**

| Туннель | Направление | Объём | Примечание |
|---------|-------------|-------|-----------|
| **wg-shard0** | → Helsinki | **Основной:** WAL streaming | Непрерывный, зависит от write load. ~1-10 GB/день |
| wg-orch | → Helsinki | Catalog cache miss, Recognition requests | Спорадический, ~0.5-2 GB/день |
| wg-app | → Helsinki | PostHog events, batch API | Лёгкий, <0.5 GB/день |
| wg-etcd | ↔ Helsinki | etcd heartbeat | Минимальный, <10 MB/день |
| Остальные | → Helsinki | Monitoring scrape (от Helsinki) | Минимальный, <100 MB/день |

> **Основной потребитель трафика — local-shard-0** (WAL streaming replication). При выборе провайдера для шарда убедиться, что квота трафика покрывает ~10-30 GB/день (с запасом на peak и REINDEX).

---

## PostHog (Helsinki)

### Назначение

Product analytics для команды: retention, funnels, session recording, feature flags, A/B tests.

### Конфигурация: CCX33 (8 vCPU / 32 GB)

```
PostHog self-hosted (Docker Compose):
├── ClickHouse — event storage (основной потребитель RAM)
├── PostgreSQL — metadata, users, dashboards
├── Redis — cache, sessions
├── Kafka — event ingestion queue
├── PostHog web — UI + API
└── PostHog worker — async jobs
```

### Интеграция

```
local-app → PostHog (10.1.0.30):
  POST /capture — events (через VPN, ~120ms, async fire-and-forget)

Events:
  • user_message_sent (без content!)
  • recommendation_shown
  • recommendation_clicked
  • store_visited (attribution)
  • try_on_used
  • avatar_interaction
  • session_start / session_end
  • onboarding_step
```

> **Privacy:** В PostHog НЕ отправляется содержимое сообщений, персональные данные или User Knowledge. Только структурные events с анонимизированными user_id.

### Масштабирование PostHog

| MAU | Примерно events/день | Сервер | Стоимость |
|-----|---------------------|--------|-----------|
| 0–10K | <100K | CCX33 (32 GB) | €74/мес |
| 10K–50K | 100K–500K | CCX33 + отдельный ClickHouse (CCX33) | €148/мес |
| 50K+ | >500K | Dedicated ClickHouse cluster | €300+/мес |

---

## Миграция с текущей архитектуры

### Что переносится из Helsinki в Локальные

| Сервис | Было (Helsinki) | Стало (Локально) |
|--------|----------------|-----------------|
| App Server (юзерский API) | unde-app (10.1.0.2) | local-app (10.2.0.2) |
| LLM Orchestrator | 10.1.0.17 (планировался) | local-orchestrator (10.2.0.17) |
| Redis (hot path) | push (10.1.0.4) | local-redis (10.2.0.4) |
| Mood Agent | 10.1.0.11 (планировался) | local-mood (10.2.0.11) |
| Persona Agent | 10.1.0.21 (планировался) | local-persona (10.2.0.21) |
| Context Agent | 10.1.0.19 (планировался) | local-context (10.2.0.19) |
| Voice Server | 10.1.0.12 (планировался) | local-voice (10.2.0.12) |
| User Data Shard | Dubai bare metal (планировался) | local-shard-0 (10.2.0.10) |

### Что остаётся в Helsinki

| Сервис | Статус | Роль |
|--------|--------|------|
| unde-app (H1) | ✅ Работает | Batch API, admin, failover entry point |
| scraper (H2) | ✅ Работает | Без изменений |
| push (H3) | ✅ Работает | Batch Redis + Celery broker (recognition, enrichment) |
| model-generator (H4) | ✅ Работает | Без изменений |
| tryon-service (H5) | ✅ Работает | Без изменений |
| Production DB (H6) | ✅ Работает | Каталог + routing_table + tombstone_registry |
| Все новые batch серверы | 🆕 | Recognition, Catalog pipeline, PostHog, Monitoring |

### Порядок развёртывания

```
Фаза 1: Helsinki batch (можно начинать сейчас)
  День 1:  Object Storage + Helsinki GW (Debian + MikroTik CHR) + Monitoring
  День 2:  Staging DB
  День 3:  Apify + Photo Downloader + Ximilar Sync
  День 4:  Collage Server
  День 5:  Recognition pipeline (Ximilar GW + LLM Reranker + Orchestrator)
  День 6:  Интеграция + тесты pipeline
  День 7:  PostHog

Фаза 2: Локальные серверы (hot path)
  День 8:  WireGuard туннели: каждый локальный сервер → helsinki-gw
  День 9:  local-redis + local-shard-0
  День 10: Streaming replication → shard-replica-0
  День 11: Patroni + etcd (3 ноды)
  День 12: local-orchestrator + local-mood + local-persona + local-context
  День 13: local-voice
  День 14: local-app (DNS switch)
  День 15: Тесты failover, verify-and-replay, latency measurement

Фаза 3: Масштабирование (по метрикам)
  Триггер: pg_relation_size(HNSW) > 20 GB
  → Добавить local-shard-N + shard-replica-N
```

---

## Мониторинг (обновлённый)

### Выделенный сервер: monitoring (H19, 10.1.0.7)

**Почему отдельный сервер:**
- **1 сервис = 1 сервер** — мониторинг не должен конкурировать за ресурсы с API или batch
- **Независимость от сбоев** — если App Server (local или Helsinki) падает, мониторинг продолжает работать и алертит
- **Единый центр** — одна Grafana, один Alertmanager для обеих площадок
- **Retention** — Prometheus с 30-дневным retention на ~30 серверов потребляет 4-6 GB RAM + растущий диск

### Архитектура мониторинга

```
ЛОКАЛЬНЫЕ СЕРВЕРЫ                         HETZNER HELSINKI

local-app         ──┐                     ┌── Все Helsinki серверы
local-orchestrator ──┤                     ├── Production DB
local-redis        ──┤                     ├── Staging DB
local-mood         ──┤  node_exporter      ├── Recognition pipeline
local-persona      ──┤  :9100             ├── Catalog pipeline
local-context      ──┤                     ├── PostHog
local-voice        ──┤  postgres_exporter  ├── Shard Replicas
local-shard-*      ──┤  :9187             │
local-etcd-1       ──┤  redis_exporter    │
                     │  :9121             │
                     │                     │
                     └───── VPN ──────────┐│
                                          ▼▼
                                 ┌──────────────────┐
                                 │  MONITORING       │
                                 │  (10.1.0.7)       │
                                 │  CX33             │
                                 │                   │
                                 │  Prometheus       │
                                 │  ├── scrape all   │
                                 │  ├── local (VPN)  │
                                 │  └── retention 30d│
                                 │                   │
                                 │  Grafana          │
                                 │  ├── dashboards   │
                                 │  └── auth (team)  │
                                 │                   │
                                 │  Alertmanager     │
                                 │  ├── Telegram     │
                                 │  └── Slack        │
                                 └──────────────────┘
```

### Prometheus scrape config

```yaml
# /etc/prometheus/prometheus.yml на monitoring (10.1.0.7)

global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['localhost:9093']

scrape_configs:
  # === ЛОКАЛЬНЫЕ СЕРВЕРЫ (через VPN) ===
  - job_name: 'local-app'
    static_configs:
      - targets: ['10.2.0.2:9100']
  - job_name: 'local-orchestrator'
    static_configs:
      - targets: ['10.2.0.17:9100']
  - job_name: 'local-redis'
    static_configs:
      - targets: ['10.2.0.4:9100', '10.2.0.4:9121']
  - job_name: 'local-mood'
    static_configs:
      - targets: ['10.2.0.11:9100']
  - job_name: 'local-persona'
    static_configs:
      - targets: ['10.2.0.21:9100']
  - job_name: 'local-context'
    static_configs:
      - targets: ['10.2.0.19:9100']
  - job_name: 'local-voice'
    static_configs:
      - targets: ['10.2.0.12:9100']
  - job_name: 'local-shard'
    static_configs:
      - targets: ['10.2.0.10:9100', '10.2.0.10:9187']
  - job_name: 'local-etcd'
    static_configs:
      - targets: ['10.2.0.50:2379']

  # === HELSINKI СЕРВЕРЫ ===
  - job_name: 'helsinki-app'
    static_configs:
      - targets: ['10.1.0.2:9100']
  - job_name: 'helsinki-scraper'
    static_configs:
      - targets: ['10.1.0.3:9100']
  - job_name: 'helsinki-push'
    static_configs:
      - targets: ['10.1.0.4:9100', '10.1.0.4:9121']
  - job_name: 'helsinki-production-db'
    static_configs:
      - targets: ['10.1.1.2:9100', '10.1.1.2:9187']
  - job_name: 'helsinki-staging-db'
    static_configs:
      - targets: ['10.1.0.8:9100', '10.1.0.8:9187']
  - job_name: 'helsinki-shard-replica'
    static_configs:
      - targets: ['10.1.1.10:9100', '10.1.1.10:9187']
  - job_name: 'helsinki-etcd'
    static_configs:
      - targets: ['10.1.1.10:2379', '10.1.0.15:2379']
  - job_name: 'helsinki-recognition'
    static_configs:
      - targets: ['10.1.0.14:9100']
  - job_name: 'helsinki-ximilar-gw'
    static_configs:
      - targets: ['10.1.0.12:9100']
  - job_name: 'helsinki-llm-reranker'
    static_configs:
      - targets: ['10.1.0.13:9100']
  - job_name: 'helsinki-apify'
    static_configs:
      - targets: ['10.1.0.9:9100']
  - job_name: 'helsinki-photo-downloader'
    static_configs:
      - targets: ['10.1.0.10:9100']
  - job_name: 'helsinki-collage'
    static_configs:
      - targets: ['10.1.0.16:9100']
  - job_name: 'helsinki-ximilar-sync'
    static_configs:
      - targets: ['10.1.0.11:9100']
  - job_name: 'helsinki-posthog'
    static_configs:
      - targets: ['10.1.0.30:9100']
```

### Ключевые метрики (дополнение к существующим)

| Метрика | Источник | Алерт |
|---------|----------|-------|
| vpn_tunnel_rtt_ms | local-app → Helsinki | > 200ms |
| vpn_tunnel_up | WireGuard | == 0 |
| local_shard_disk_usage_percent | local-shard-* | > 80% |
| local_shard_cache_hit_ratio | pg_stat_user_tables | < 90% (cold cache!) |
| shard_routing_cache_miss_rate | local-redis | > 5% |
| catalog_cache_hit_ratio | local-redis | < 80% → warm cache strategy |
| posthog_events_ingested_total | PostHog | — (info) |
| posthog_clickhouse_disk_usage | PostHog | > 80% |
| posthog_query_latency_p95 | PostHog | > 10s |
| prometheus_tsdb_head_series | Monitoring | > 500K (memory pressure) |
| prometheus_tsdb_storage_blocks_bytes | Monitoring | > 80% disk |
| alertmanager_notifications_failed_total | Monitoring | > 0 |

---

## Безопасность (обновлённая)

### Сетевая изоляция

```
                    INTERNET
                        │
                        │ HTTPS (443)
                        │
           ┌────────────┴────────────┐
           ▼                         ▼
   ┌──────────────┐         ┌──────────────┐
   │  local-app   │         │  unde-app    │
   │  (10.2.0.2)  │         │  (10.1.0.2)  │
   │  Юзерский    │         │  Admin/batch │
   │  трафик      │         │  endpoints   │
   └──────┬───────┘         └──────┬───────┘
          │                        │
          │ Private 10.2.0.0/24    │ Private 10.1.0.0/16
          │                        │
   Каждый локальный сервер         │
   имеет свой WireGuard     ┌──────┴───────┐
   туннель напрямую ────────►│ helsinki-gw  │
   до helsinki-gw            │ (10.1.0.2)  │
                             │ MikroTik CHR │
                             │ Routing +    │
                             │ Firewall     │
                             └──────────────┘
```

### Credentials (дополнение)

| Секрет | Где хранится | Кто использует |
|--------|-------------|----------------|
| WireGuard private keys | /etc/wireguard/ | Каждый локальный сервер (клиент) + helsinki-gw (сервер) |
| MikroTik CHR license | RouterOS | helsinki-gw (P1, $45 разово) |
| PostHog API key | .env | local-app (event capture) |
| PostHog DB password | .env | PostHog server |
| Local shard DB passwords | .env | local-orchestrator, local-persona |
| Master Encryption Key | .env (RAM only) | local-shard-*, local-orchestrator |
| Grafana admin password | .env | Monitoring server |
| Alertmanager Telegram bot token | .env | Monitoring server |
| Alertmanager Slack webhook URL | .env | Monitoring server |

---

## Ключевые отличия от v6.2

| Аспект | v6.2 (старый план) | v7.0 (новый план) |
|--------|-------------------|-------------------|
| **Primary DB** | Dubai bare metal, 256 GB RAM, tmpfs | Локальные серверы, 32 GB RAM, NVMe SSD |
| **Кол-во шардов на старте** | 1 (до 2,500 юзеров) | 1 (до 500–800 юзеров) |
| **Hybrid search latency** | <100 μs (tmpfs) | 2–5 ms (NVMe, hot cache) |
| **Hot path серверы** | Dubai bare metal (все на одной машине) | Отдельные серверы (1 сервис = 1 сервер) |
| **SPOF** | Один bare metal = всё | Изолированные серверы, падение одного ≠ падение всего |
| **Стоимость старта** | $400-600 bare metal + $128 replica | ~$300-600 (локальные) + ~€292 (Helsinki) |
| **Масштабирование** | Добавить bare metal 256 GB (~$500/мес) | Добавить 16 vCPU/32 GB сервер (~$50-80/мес) |
| **PostHog** | Не было | CCX33, €74/мес |
| **Monitoring** | На App Server (смешан с API) | Отдельный CX33, €25/мес |
| **Сеть** | Один VPN туннель между площадками | Каждый сервер — свой WireGuard туннель → helsinki-gw |
| **Router/Firewall** | Не было | Debian + MikroTik CHR (CPX22, €12/мес) |
| **Принцип 1=1** | Нарушался (все на одном BM) | Соблюдается полностью |

---

*Документ создан: 2026-02-23*
*Версия: 7.2*
*Основание: переход с Dubai bare metal на локальные серверы (макс. 32 GB RAM) + PostHog + Monitoring + Helsinki GW (Debian + MikroTik CHR)*
