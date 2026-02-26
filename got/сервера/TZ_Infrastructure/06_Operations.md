# UNDE Infrastructure — Операции: расписание, мониторинг, деплой, безопасность

*Часть [TZ Infrastructure v7.2](../TZ_Infrastructure_Final.md). Всё что нужно для эксплуатации.*

> **🔄 Обновлено под [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md)** — embedding batch schedule, новые Prometheus targets (embedder, embed-batch), метрики dual retrieval / availability / pgvector, feature flags для recognition, новые credentials.

---

## 18. РАСПИСАНИЕ ЗАДАЧ

| Задача | Сервер | Частота | Время | Описание |
|--------|--------|---------|-------|----------|
| **availability_poll** | Scraper (10.1.0.3) | Каждый час | :00 | Mobile API → Staging DB |
| **sync_to_production** | Scraper (10.1.0.3) | Каждый час | :10 | Staging → Production DB |
| **process_collages** | Collage (10.1.0.16) | Каждые 15 мин | :00,:15,:30,:45 | Создание коллажей |
| **retry_failed** | Collage (10.1.0.16) | Каждый час | :30 | Повтор неудачных |
| **apify_zara** | Apify (10.1.0.9) | Еженедельно | Вс 02:00 | Метаданные Zara |
| **apify_bershka** | Apify (10.1.0.9) | Еженедельно | Вс 03:00 | Метаданные Bershka |
| **apify_pullandbear** | Apify (10.1.0.9) | Еженедельно | Вс 04:00 | Метаданные Pull&Bear |
| **apify_stradivarius** | Apify (10.1.0.9) | Еженедельно | Вс 05:00 | Метаданные Stradivarius |
| **apify_massimodutti** | Apify (10.1.0.9) | Еженедельно | Вс 06:00 | Метаданные Massimo Dutti |
| **apify_oysho** | Apify (10.1.0.9) | Еженедельно | Вс 07:00 | Метаданные Oysho |
| **download_pending** | Photo Downloader (10.1.0.10) | Каждые 15 мин | :00,:15,:30,:45 | Скачать фото pending |
| **download_retry** | Photo Downloader (10.1.0.10) | Каждый час | :30 | Повтор неудачных |
| **ximilar_sync** | Ximilar Sync (10.1.0.11) | Еженедельно | Вс 10:00 | Новые SKU → Ximilar Collection |
| **ximilar_retry** | Ximilar Sync (10.1.0.11) | Ежедневно | 12:00 | Повтор неудачных |
| **cleanup_old_data** | Staging DB | Ежедневно | 04:00 | DELETE > 30 дней |
| **cleanup_temp_files** | Photo Downloader, Collage | Ежедневно | 05:00 | rm /app/data/* |
| **enrichment_ttl_recovery** | local-orchestrator (10.2.0.17) | Каждые 6 часов | :00 | Сообщения без embedding старше 1ч → force enrich (retry < 3, LIMIT 500). KSP Фикс 14 |
| **life_event_expiry** | Local Shard (cron) | Ежедневно | 03:00 | user_knowledge: life_event с expires_at < NOW() → is_active=FALSE. KSP Фикс 3 |
| **extraction_review_sample** | local-orchestrator (10.2.0.17) | Ежедневно | 06:00 | [Фаза 2] 1% random sample batch extractions → review. KSP Фикс 1B |
| **🔄 embedding_batch_sync** | embed-batch (10.1.0.17) | Еженедельно | Пн 02:00 | v5.1: Batch-индексация новых SKU в pgvector (FashionCLIP → sku_image_embeddings) |
| **🔄 embedding_progressive** | embed-batch (10.1.0.17) | Еженедельно | Ср 03:00 | v5.1: Progressive ingestion — догрузка фото для SKU с низким rerank score |

**Recognition Orchestrator** — без расписания, обрабатывает запросы в реальном времени через Celery queue (🔄 v5.1: 5-step pipeline с dual retrieval и availability filter).

**Ximilar Gateway** — без расписания, обрабатывает HTTP-запросы от Orchestrator в реальном времени (🔄 v5.1: dual retrieval — pgvector kNN через embedder + conditional Ximilar booster).

**🔄 v5.1: Embedder (10.1.0.15)** — без расписания, обрабатывает HTTP-запросы от ximilar-gw в реальном времени (`POST /embed`, FashionCLIP 2.0 ONNX, 100–250ms).

**🔄 v5.1: Embed-Batch (10.1.0.17)** — по расписанию (Пн 02:00 batch sync, Ср 03:00 progressive) + по событию (новые SKU). Batch-индексация каталога → pgvector (`POST /embed_batch`).

**LLM Reranker** — без расписания, обрабатывает HTTP-запросы от Orchestrator в реальном времени.

**Mood Agent Server** — без расписания, обрабатывает запросы в реальном времени через HTTP API (синхронный, < 200ms).

**Voice Server** — без расписания, обрабатывает запросы в реальном времени через HTTP API + WebSocket streaming.

**LLM Orchestrator** — без расписания, обрабатывает запросы в реальном времени через Celery queue (dialogue_queue). Latency target: < 10s p95.

**Context Agent** — без расписания, обрабатывает HTTP-запросы в реальном времени (< 100ms p95). Кеширование: погода 30 мин, события 1 час, культура 24 часа.

**Persona Agent** — без расписания, обрабатывает HTTP-запросы в реальном времени (< 15ms p95). POST /persona (directive), POST /persona/feedback (signals), POST /persona/flush (resolve). In-process LRU cache (100 профилей). Cron: cleanup persona_temp_blocks + signal_daily_deltas (ежедневно 04:00).

**Local Shard (Chat History + User Knowledge)** — без расписания, принимает INSERT при каждом сообщении, Hybrid Search для ContextPack, async enrichment (embedding, snippet). Streaming replication → Hetzner непрерывно.

### Бэкапы

| Компонент | Метод | Частота | Хранилище | Retention |
|-----------|-------|---------|-----------|-----------|
| Production DB (Hetzner) | pgBackRest | Full: Вс 02:00, Diff: Пн-Сб 03:00 | Storage Box BX11 (1TB) | 4 full + 7 diff |
| Staging DB (Hetzner) | pgBackRest | Full: Вс 03:00, Diff: Пн-Сб 04:00 | Storage Box | 4 full + 7 diff |
| Local Shard → Hetzner | Streaming replication | Непрерывно (async WAL) | AX102 replica | Real-time |
| Local Shard → Object Storage | pg_basebackup | Каждые 6 часов | Hetzner Object Storage | 7 daily + 4 weekly + 3 monthly |
| Local Shard → WAL archive | archive_command | Непрерывно | Object Storage + NVMe | Point-in-Time Recovery |
| Local Shard → локальный snapshot | pg_basebackup --compress=lz4 | Каждые 2 часа | NVMe отдельный раздел | 1 копия |

---

## 19. МОНИТОРИНГ

### Prometheus targets

```yaml
# /etc/prometheus/prometheus.yml на Monitoring Server (10.1.0.7)

scrape_configs:
  # Существующие...
  
  # Helsinki batch серверы:
  - job_name: 'node-apify'
    static_configs:
      - targets: ['10.1.0.9:9100']

  - job_name: 'node-photo-downloader'
    static_configs:
      - targets: ['10.1.0.10:9100']

  - job_name: 'node-ximilar-sync'
    static_configs:
      - targets: ['10.1.0.11:9100']

  - job_name: 'node-collage'
    static_configs:
      - targets: ['10.1.0.16:9100']

  - job_name: 'node-recognition'
    static_configs:
      - targets: ['10.1.0.14:9100']

  - job_name: 'node-ximilar-gw'
    static_configs:
      - targets: ['10.1.0.12:9100']

  - job_name: 'ximilar-gw-app'
    static_configs:
      - targets: ['10.1.0.12:8001']

  - job_name: 'node-llm-reranker'
    static_configs:
      - targets: ['10.1.0.13:9100']

  - job_name: 'llm-reranker-app'
    static_configs:
      - targets: ['10.1.0.13:8002']

  - job_name: 'node-staging-db'
    static_configs:
      - targets: ['10.1.0.8:9100']

  # Локальные серверы — мониторятся через VPN, см. 07_Server_Layout_v7.md

  # node-dubai-shard-0, postgres-dubai-shard-0 — теперь локальные, см. 07_Server_Layout_v7.md

  - job_name: 'node-shard-replica-0'
    static_configs:
      - targets: ['10.1.1.10:9100']

  - job_name: 'postgres-shard-replica-0'
    static_configs:
      - targets: ['10.1.1.10:9187']

  - job_name: 'etcd-cluster'
    static_configs:
      - targets: ['10.1.0.17:2379', '10.1.0.15:2379']
      # dubai-shard-0:2379 — теперь локальный, см. 07_Server_Layout_v7.md

  - job_name: 'postgres-staging'
    static_configs:
      - targets: ['10.1.0.8:9187']

  # 🔄 v5.1: Embedding серверы
  - job_name: 'node-embedder'
    static_configs:
      - targets: ['10.1.0.15:9100']

  - job_name: 'embedder-app'
    static_configs:
      - targets: ['10.1.0.15:8003']

  - job_name: 'node-embed-batch'
    static_configs:
      - targets: ['10.1.0.17:9100']

  - job_name: 'embed-batch-app'
    static_configs:
      - targets: ['10.1.0.17:8004']
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
| **🔄 v5.1: Dual Retrieval & Availability** | | |
| pgvector_knn_latency_ms | Ximilar Gateway | p95 > 50ms |
| pgvector_knn_results_count | Ximilar Gateway | < 10 → индекс проблема |
| embedder_inference_latency_ms | Embedder (10.1.0.15) | p95 > 300ms |
| embedder_errors | Embedder (10.1.0.15) | > 1% |
| embed_batch_throughput_imgs_sec | Embed-Batch (10.1.0.17) | < 3 → деградация |
| embed_batch_job_duration_sec | Embed-Batch (10.1.0.17) | > 86400 (> 24ч) |
| embed_batch_errors | Embed-Batch (10.1.0.17) | > 5% |
| ximilar_booster_rate | Ximilar Gateway | — (info, % запросов с Ximilar booster) |
| recognition_availability_filter_pass_rate | Recognition Orchestrator | < 20% → мало товаров в наличии |
| recognition_candidates_after_availability | Recognition Orchestrator | avg < 3 → TOP-50 недостаточно |
| recognition_used_ximilar_booster_rate | Recognition Orchestrator | — (info, калибровка CONFIDENCE_THRESHOLD) |
| recognition_used_ximilar_tagging_rate | Recognition Orchestrator | — (info, калибровка tagging budget) |
| sku_image_embeddings_count | Production DB | — (info, мониторинг размера индекса) |
| sku_image_embeddings_hnsw_size_bytes | Production DB | > 20 GB → мониторинг |
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
| persona_temp_blocks_active | Local Shard | > 100 per user |
| **Local Shard (disk + replication)** | | |
| disk_usage_percent | Local Shard | > 85% — время добавлять шард |
| hnsw_index_size_bytes | Local Shard | > 20 GB — планировать новый шард |
| replication_lag_seconds | Local Shard → Hetzner | > 5 секунд |
| replica_up | Hetzner Replica | == 0 — failover скомпрометирован |
| replay_requests_total_rate | App Server | > 10/5m — недавний failover |
| enrichment_backfill_rate | LLM Orchestrator | > 5/5m — replayed без embedding |
| replication_slot_wal_bytes | Local Shard | > 20 GB — replica отстала, NVMe в опасности |
| etcd_server_has_leader | etcd cluster | == 0 — risk split-brain |
| hybrid_search_latency_ms | Local Shard | p95 > 50ms |
| embedding_ingestion_errors | LLM Orchestrator | > 5% |
| memory_snippet_null_rate | Local Shard | > 10% embeddable |
| user_knowledge_decrypt_errors | Local Shard | > 1% |
| user_knowledge_decrypt_latency_ms | Local Shard | p95 > 1ms |
| **Knowledge Staging Pipeline (KSP)** | | |
| unde_instant_extraction_total{type,language} | LLM Orchestrator | — (info) |
| unde_instant_extraction_supersede_total | LLM Orchestrator | — (info) |
| unde_batch_extraction_duration_seconds | LLM Orchestrator | — (info, Фаза 2) |
| unde_batch_extraction_deltas_total{operation} | LLM Orchestrator | — (info, Фаза 2) |
| unde_batch_extraction_queue_size | LLM Orchestrator | > 1000 → scale workers |
| unde_batch_extraction_errors_total | LLM Orchestrator | > 5% |
| unde_snippet_cache_hit_ratio | Local Shard | — (info, Фаза 2) |
| unde_enrichment_queue_size{priority} | LLM Orchestrator | > 500 |
| unde_enrichment_latency_seconds{priority} | LLM Orchestrator | p95 > 5s |
| unde_orphan_messages_total | Local Shard | > 100 → enrichment pipeline проблема |
| unde_memory_correction_total{type,lang} | LLM Orchestrator | > 3%/week → batch prompt tuning |
| unde_memory_correction_uk_deactivated_total | LLM Orchestrator | > 1% → ложные факты; > 3% → auto-fallback |
| unde_memory_correction_uk_disputed_total | LLM Orchestrator | — (info) |
| unde_privacy_span_filtered_total | LLM Orchestrator | — (info, Фаза 2) |
| unde_forget_cascade_snippets_nullified_total | Local Shard | — (info) |
| unde_forget_cascade_knowledge_deactivated_total | Local Shard | > 5/day → alert |
| unde_user_repeated_info_count | LLM Orchestrator | > 5%/week → retrieval проблема |
| unde_retrieval_miss_rate | LLM Orchestrator | > 10% → рассмотреть Фикс 1B |
| unde_staging_fallback_triggered_total | LLM Orchestrator | > 100/hour → batch bottleneck |
| unde_extraction_review_error_rate | LLM Orchestrator | > 5% → остановить batch (Фаза 2) |
| unde_validator_gate_total{result} | LLM Orchestrator | — (info, Фаза 2) |
| unde_validator_rejection_rate | LLM Orchestrator | > 50% → prompt слишком широкий |
| pgbackrest_last_full_age_hours | Production DB, Staging DB | > 192 (8 days) |
| basebackup_last_age_hours | Local Shard → Object Storage | > 12 (missed 2 cycles) |
| local_snapshot_age_hours | Local Shard → NVMe | > 4 (missed 2 cycles) |
| user_media_bucket_size | Hetzner | > 200 GB |
| object_storage_size | Hetzner | > 200 GB |

---

## 19b. FEATURE FLAGS (🔄 v5.1)

> Из [Pipeline v5.1](../../UNDE_Fashion_Recognition_Pipeline_v5.1.md). Переключение режимов recognition pipeline без деплоя.

| Flag | Сервер | Значения | По умолчанию | Назначение |
|------|--------|----------|-------------|-----------|
| `SEARCH_BACKEND` | ximilar-gw (10.1.0.12) | `ximilar` / `pgvector` / `conditional` / `dual` | `conditional` | Режим поиска: Phase 1 = `ximilar`, Phase 2+ = `conditional` |
| `TAGGING_MODE` | recognition (10.1.0.14) | `always` / `on_demand` / `off` | `on_demand` | Вызов Ximilar /tag: `always` = каждый запрос, `on_demand` = только при неуверенном search |
| `CONFIDENCE_THRESHOLD` | ximilar-gw (10.1.0.12) | float 0–1 | `0.80` | Порог уверенности pgvector top-1 score для skip Ximilar booster |
| `MARGIN` | ximilar-gw (10.1.0.12) | float 0–1 | `0.10` | Минимальный gap top1 - top2 для уверенного pgvector |
| `AVAILABILITY_WINDOW` | recognition (10.1.0.14) | interval | `24 hours` | Окно свежести данных raw_availability |
| `MIN_CANDIDATES` | recognition (10.1.0.14) | int | `3` | Минимум кандидатов после availability filter (ниже → дозапрос Ximilar) |

**Emergency rollback**: `SEARCH_BACKEND=ximilar` + `TAGGING_MODE=always` → полный откат на Ximilar-only pipeline (Phase 1 поведение).

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
# Hetzner Console → Создать сервер CPX21 (Helsinki), Private: 10.1.0.8

apt update && apt install -y postgresql-17 pgbouncer
sudo -u postgres createdb unde_staging
sudo -u postgres psql unde_staging < schema.sql

# Тест
psql -h 10.1.0.8 -p 6432 -U scraper -d unde_staging
```

### День 3: Apify Server (метаданные)

```bash
# ✅ Развёрнут (CX23, 10.1.0.9, 89.167.110.186)
# Git: http://gitlab-real.unde.life/unde/apify.git
# Docker: apify-collector + apify-beat (running)
# node_exporter 1.8.2 (systemd)

# Тест
docker compose exec apify-collector python -c "from app.tasks import collect_brand; collect_brand.delay('zara')"
```

### День 3b: Photo Downloader

```bash
# ✅ Развёрнут (CX23, 10.1.0.10, 89.167.99.242)
# Git: http://gitlab-real.unde.life/unde/photo-downloader.git
# Docker: photo-downloader + downloader-beat (running)
# node_exporter 1.8.2 (systemd)
# Скачивание через Bright Data residential proxy

# Тест (после Apify собрал метаданные)
docker compose exec photo-downloader python -c "from app.tasks import download_pending; download_pending.delay()"
```

### День 3c: Ximilar Sync Server

```bash
# ✅ Развёрнут (CX23, 10.1.0.11, 89.167.93.187)
# Git: http://gitlab-real.unde.life/unde/ximilar-sync.git
# Docker: ximilar-sync (worker, concurrency=2, 1GB limit) + ximilar-beat (running)
# node_exporter 1.8.2 (systemd, 0.0.0.0:9100)
# Ximilar credentials: xxx (TODO: заполнить)

# Тест (после Photo Downloader скачал фото)
docker compose exec ximilar-sync celery -A app.celery_app call app.tasks.ximilar_sync
```

### День 4: Collage Server

```bash
# ✅ Развёрнут (CX33, 10.1.0.16, 65.109.172.52)
# Git: http://gitlab-real.unde.life/unde/collage.git
# Docker: collage-worker + collage-beat (running)
# node_exporter 1.8.2 (systemd)
# JPEG q=95, subsampling=0 (4:4:4), без уменьшения разрешения

# Тест
docker compose exec collage-worker celery -A app.celery_app call app.tasks.process_new
```

### День 5: Recognition Orchestrator + Ximilar Gateway + LLM Reranker

```bash
# 1. Ximilar Gateway
# ✅ Развёрнут (CX23, 10.1.0.12, 89.167.99.162)
# Git: http://gitlab-real.unde.life/unde/ximilar-gw.git
# Docker: ximilar-gw (FastAPI, 4 uvicorn workers, 2GB limit, bind 10.1.0.12:8001)
# node_exporter 1.8.2 (systemd, 0.0.0.0:9100)
# Prometheus app metrics: GET http://10.1.0.12:8001/metrics
# Ximilar credentials: xxx (TODO: заполнить)

# Тест
curl -s http://10.1.0.12:8001/health | python3 -m json.tool

# 2. LLM Reranker
# ✅ Развёрнут (CX23, 10.1.0.13, 89.167.106.167)
# Git: http://gitlab-real.unde.life/unde/llm-reranker.git
# Docker: llm-reranker (FastAPI, 2 uvicorn workers, 1GB limit, bind 10.1.0.13:8002)
# node_exporter 1.8.2 (systemd, 0.0.0.0:9100)
# Prometheus app metrics: GET http://10.1.0.13:8002/metrics
# Gemini model: gemini-2.5-flash

# Тест
curl -s http://10.1.0.13:8002/health | python3 -m json.tool

# 3. Recognition Orchestrator
# ✅ Развёрнут (CPX11, 10.1.0.14, 89.167.90.152)
# Git: http://gitlab-real.unde.life/unde/Recognition.git
# Docker: recognition-orchestrator (Celery worker, concurrency=2, 1GB limit)
# node_exporter 1.8.2 (systemd, 0.0.0.0:9100)
# DB table recognition_requests создана в Production DB (10.1.1.2)

# Тест
./scripts/health-check.sh
```

### День 5b: Embedding серверы (🔄 v5.1 — NEW)

```bash
# 1. Embedder (runtime inference)
# Hetzner Robot → Заказать dedicated i7-8700, 64 GB, 2×NVMe 512 GB (HEL1-DC2)
# Private IP: 10.1.0.15, ~€36.70/мес
# Git: http://gitlab-real.unde.life/unde/embedder.git
# Docker: embedder (FastAPI, ONNX Runtime, FashionCLIP 2.0, bind 0.0.0.0:8003)
# node_exporter 1.8.2 (systemd)

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/embedder.git /opt/unde/embedder
cd /opt/unde/embedder
cp .env.example .env  # Заполнить: MODEL_PATH, PORT=8003
docker-compose up -d

# Тест
curl -X POST http://10.1.0.15:8003/embed \
  -H "Content-Type: application/json" \
  -d '{"image_url":"https://hel1.your-objectstorage.com/unde-images/originals/zara/12345/0.jpg"}'
# Проверить latency < 300ms, возвращает vector(512)

# 2. Embed-Batch (фоновая индексация)
# Hetzner Robot → Заказать dedicated i7-8700, 64 GB, 2×SSD 512 GB (HEL1)
# Private IP: 10.1.0.17, ~€36.70/мес
# Git: http://gitlab-real.unde.life/unde/embed-batch.git
# Docker: embed-batch (FastAPI + Celery worker, ONNX Runtime, FashionCLIP 2.0, bind 0.0.0.0:8004)
# node_exporter 1.8.2 (systemd)

apt update && apt install -y docker.io docker-compose
git clone http://gitlab-real.unde.life/unde/embed-batch.git /opt/unde/embed-batch
cd /opt/unde/embed-batch
cp .env.example .env  # Заполнить: MODEL_PATH, PRODUCTION_DB_URL, S3_*, PORT=8004
docker-compose up -d

# 3. Создать таблицу sku_image_embeddings в Production DB (10.1.1.2)
psql -h 10.1.1.2 -p 6432 -U admin -d unde_ai < deploy/init-embeddings-table.sql
# Создаст: sku_image_embeddings + HNSW index + brand index + unique constraint

# 4. Initial load (запустить на ночь, 8–13 часов для 47K SKU × 5 фото)
curl -X POST http://10.1.0.17:8004/embed_batch \
  -H "Content-Type: application/json" \
  -d '{"scope":"all","batch_size":500}'

# Мониторинг progress:
curl http://10.1.0.17:8004/status
```

### День 6: Интеграция

```bash
# 1. Обновить Scraper (10.1.0.3)
#    Добавить STAGING_DB_URL, обновить sync job, включить расписание

# 2. Загрузить каталог в Ximilar Collection
#    Ximilar Sync Server: запустить ximilar_sync для существующих товаров

# 3. Обновить Prometheus (App Server)
#    Добавить targets: recognition, ximilar-gw, llm-reranker, photo-downloader, ximilar-sync
#    🔄 v5.1: + embedder (10.1.0.15:9100, 10.1.0.15:8003), embed-batch (10.1.0.17:9100, 10.1.0.17:8004)

# 4. Обновить ximilar-gw (10.1.0.12):
#    🔄 v5.1: Добавить EMBEDDER_URL=http://10.1.0.15:8003, PRODUCTION_DB_URL, SEARCH_BACKEND=conditional
#    Добавить CONFIDENCE_THRESHOLD=0.80, MARGIN=0.10

# 5. Обновить recognition (10.1.0.14):
#    🔄 v5.1: Добавить STAGING_DB_URL (для availability filter), TAGGING_MODE=on_demand
#    Добавить AVAILABILITY_WINDOW=24h, MIN_CANDIDATES=3

# 6. Проверить полный flow
#    a. Apify: собрать 100 товаров Zara (метаданные)
#    b. Photo Downloader: скачать фото
#    c. Ximilar Sync: загрузить в Collection
#    d. Collage: обработать
#    e. Scraper: sync в Production
#    f. 🔄 v5.1: Embed-Batch: проиндексировать тестовые SKU в pgvector
#    g. Recognition: тестовый запрос (dual retrieval + availability filter)
#    h. App: проверить API /api/v1/recognize
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
cp .env.example .env  # Заполнить: Local Shard DB, Redis, CONTRACT_VERSION

# Создать таблицы в Local Shard
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
#    Private IP: 10.1.0.15

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
#     etcd-2: Hetzner CX23 (10.1.0.17)
#     etcd-3: Hetzner CPX11 (10.1.0.15)

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
│  Apify (10.1.0.9)        — только private network         │
│  Photo Downloader (10.1.0.10) — только private network*   │
│  Ximilar Sync (10.1.0.11)    — только private network*    │
│  Scraper (10.1.0.3)      — только private network         │
│  Collage (10.1.0.16)      — только private network         │
│  Recognition (10.1.0.14)  — только private network         │
│  Ximilar GW (10.1.0.12) — только private network*         │
│  LLM Reranker (10.1.0.13) — только private network*       │
│  🔄 Embedder (10.1.0.15)  — только private network        │
│  🔄 Embed-Batch (10.1.0.17) — только private network      │
│  LLM Orchestrator (10.1.0.17) — только private network*   │
│  Mood Agent (10.1.0.11)  — только private network*        │
│  Voice (10.1.0.12)       — только private network*        │
│  Context Agent (10.1.0.19) — только private network*      │
│  Persona Agent (10.1.0.21) — только private network*      │
│  Staging DB (10.1.0.8)   — только private network         │
│  Production DB (10.1.1.2) — только private network        │
│  Shard Replica (10.1.1.10) — только private network       │
│  etcd-3 (10.1.0.15)      — только private network        │
│                                                            │
│  DUBAI (bare metal, private + VPN к Hetzner):              │
│  Local Shard Primary     — private network + VPN           │
│  etcd-1                  — на Dubai app-сервере            │
└───────────────────────────────────────────────────────────┘
```

**Local Shard Primary** — bare metal сервер в Dubai DC. Доступен только по private network (VPN tunnel к Hetzner). Нет публичного IP для PostgreSQL. SSH через VPN или dedicated management network.

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
| Local Shard DB password | .env | App Server, LLM Orchestrator |
| Master Encryption Key (AES-256, User Knowledge) | .env (RAM only) | Local Shard, LLM Orchestrator |
| Replication password | .env | Local Shard ↔ Hetzner Replica |
| 🔄 v5.1: Production DB password (embeddings) | .env | embed-batch (INSERT в unde_ai.sku_image_embeddings) |
| 🔄 v5.1: Production DB password (pgvector read) | .env | ximilar-gw (SELECT kNN из sku_image_embeddings) |
| 🔄 v5.1: S3 Access Key (originals read) | .env | embed-batch (скачка фото из /originals/ для embedding) |
| Storage Box credentials (db01) | /root/.storagebox-creds | Production DB |
| LUKS passphrase (Dubai NVMe) | Offline (не на сервере) | Local Shard |
| etcd TLS certificates | /etc/etcd/ssl/ | etcd-1, etcd-2, etcd-3 |
| Patroni REST API password | .env | Patroni (Dubai + Hetzner) |

---

*Версия: 7.2*
