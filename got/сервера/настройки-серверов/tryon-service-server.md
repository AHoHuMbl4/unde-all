# Настройка сервера tryon-service

> Полная документация по настройке и работе сервера virtual try-on.
> 
> **Дата деплоя:** 2026-01-28  
> **Сервер:** tryon-service (CPX22)

---

## Содержание

1. [Информация о сервере](#информация-о-сервере)
2. [Сетевая конфигурация](#сетевая-конфигурация)
3. [Установленное ПО](#установленное-по)
4. [Структура проекта](#структура-проекта)
5. [Docker контейнеры](#docker-контейнеры)
6. [Celery workers](#celery-workers)
7. [Redis кэширование](#redis-кэширование)
8. [fal.ai интеграция](#falai-интеграция)
9. [Systemd автозапуск](#systemd-автозапуск)
10. [Мониторинг](#мониторинг)
11. [Переменные окружения](#переменные-окружения)
12. [Логика работы](#логика-работы)
13. [Команды управления](#команды-управления)
14. [Troubleshooting](#troubleshooting)

---

## Информация о сервере

| Параметр | Значение |
|----------|----------|
| **Hostname** | tryon-service |
| **Public IP** | 89.167.31.65 |
| **Private IP** | 10.1.0.6 |
| **OS** | Ubuntu 24.04.3 LTS |
| **Kernel** | 6.8.0-90-generic |
| **CPU** | 3 vCPU (AMD EPYC) |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **Provider** | Hetzner CPX22 |

### Расположение в инфраструктуре

```
┌─────────────────────────────────────────────────────────────────┐
│                        INFRASTRUCTURE                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   User App                                                       │
│      │                                                           │
│      ▼                                                           │
│   ┌─────────────────┐                                           │
│   │   App Server    │                                           │
│   │   10.1.0.2      │                                           │
│   └────────┬────────┘                                           │
│            │ Celery task                                         │
│            ▼                                                     │
│   ┌─────────────────┐      ┌─────────────────┐                  │
│   │  Push Server    │      │ tryon-service   │◄── ВЫ ЗДЕСЬ     │
│   │  10.1.0.4       │◄────►│ 10.1.0.6        │                  │
│   │  Redis Broker   │      │ 89.167.31.65    │                  │
│   └─────────────────┘      └────────┬────────┘                  │
│                                     │                            │
│                     ┌───────────────┼───────────────┐           │
│                     ▼               ▼               ▼           │
│               ┌──────────┐   ┌──────────┐   ┌──────────┐       │
│               │ Local    │   │ fal.ai   │   │ fal.ai   │       │
│               │ Redis    │   │ Flux     │   │ FASHN    │       │
│               │ Cache    │   │ PRIMARY  │   │ BACKUP   │       │
│               └──────────┘   └──────────┘   └──────────┘       │
│                                                                  │
│   ┌─────────────────┐                                           │
│   │   DB Server     │                                           │
│   │   10.1.1.2      │  (PostgreSQL, опционально для логов)      │
│   └─────────────────┘                                           │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Сетевая конфигурация

### Интерфейсы

| Interface | IP | Назначение |
|-----------|-----|------------|
| eth0 | 89.167.31.65 | Public (интернет, fal.ai API) |
| enp7s0 | 10.1.0.6 | Private (внутренняя сеть) |

### Netplan конфигурация

**Файл:** `/etc/netplan/60-private-network.yaml`

```yaml
network:
  version: 2
  ethernets:
    enp7s0:
      dhcp4: true
      routes:
        - to: "10.0.0.0/24"
          via: "10.1.0.1"
        - to: "10.1.0.0/16"
          via: "10.1.0.1"
```

### Маршрутизация

```
10.1.0.4 (Redis Broker)  → через 10.1.0.1 (gateway)
10.1.1.2 (PostgreSQL)    → через 10.1.0.1 (gateway)
0.0.0.0/0 (интернет)     → через public interface
```

### Проверка сети

```bash
# Redis broker
ping -c 1 10.1.0.4

# Database
ping -c 1 10.1.1.2

# Internet (fal.ai)
curl -I https://fal.ai
```

---

## Установленное ПО

### Системные пакеты

| Пакет | Версия | Назначение |
|-------|--------|------------|
| Docker CE | 29.2.0 | Контейнеризация |
| Docker Compose | 5.0.2 | Оркестрация контейнеров |
| containerd | 2.2.1 | Container runtime |
| curl | 8.5.0 | HTTP клиент |
| git | 2.43.0 | Version control |

### Docker images

| Image | Tag | Size | Назначение |
|-------|-----|------|------------|
| tryon-service-tryon-worker | latest | ~250MB | Celery worker |
| redis | 7-alpine | ~30MB | Локальный кэш |
| prom/node-exporter | v1.7.0 | ~20MB | Метрики |

### Python зависимости (в контейнере)

| Package | Version | Назначение |
|---------|---------|------------|
| celery | 5.3.6 | Task queue |
| redis | 5.0.1 | Redis клиент |
| fal-client | 0.5.6 | fal.ai SDK |
| requests | 2.31.0 | HTTP клиент |
| kombu | 5.6.2 | Messaging (Celery) |
| billiard | 4.2.4 | Multiprocessing (Celery) |

---

## Структура проекта

```
/opt/unde/tryon-service/
│
├── docker-compose.yml      # Конфигурация контейнеров
├── Dockerfile              # Сборка worker image
├── requirements.txt        # Python зависимости
│
├── .env                    # Секреты (НЕ в git!)
├── .env.example            # Шаблон переменных
├── .gitignore              # Исключения git
│
├── app/                    # Python приложение
│   ├── __init__.py         # Package init
│   ├── celery_app.py       # Celery конфигурация
│   ├── tasks.py            # Celery tasks (virtual_tryon)
│   ├── fal_client.py       # fal.ai wrapper (Flux + FASHN)
│   └── cache.py            # Redis cache logic
│
├── scripts/                # Утилиты
│   ├── deploy.sh           # Скрипт деплоя
│   ├── health-check.sh     # Проверка здоровья
│   └── test-tryon.sh       # Тестовый запрос
│
├── deploy/                 # Конфигурации деплоя
│   ├── netplan.yaml        # Сетевая конфигурация
│   ├── tryon.service       # Systemd unit
│   └── init-db.sql         # SQL для логов (опционально)
│
├── docs/                   # Документация
│   ├── README.md           # Общее описание
│   └── SERVER_SETUP.md     # ЭТО ЭТОТ ФАЙЛ
│
├── memory-bank/            # Project memory (для AI агентов)
│   ├── projectBrief.md
│   ├── productContext.md
│   ├── systemPatterns.md
│   ├── techContext.md
│   ├── activeContext.md
│   └── progress.md
│
├── .cursor/rules/          # Cursor AI rules
│   ├── memory-bank.mdc
│   └── git-backups.mdc
│
└── AGENTS.md               # Anchor для AI агентов
```

---

## Docker контейнеры

### Обзор

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose Stack                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐           │
│  │  worker-1   │ │  worker-2   │ │  worker-3   │           │
│  │  (Celery)   │ │  (Celery)   │ │  (Celery)   │           │
│  └──────┬──────┘ └──────┬──────┘ └──────┬──────┘           │
│         │               │               │                   │
│  ┌──────┴───────────────┴───────────────┴──────┐           │
│  │              tryon-network                   │           │
│  └──────┬───────────────────────────────┬──────┘           │
│         │                               │                   │
│  ┌──────▼──────┐                 ┌──────▼──────┐           │
│  │ redis-cache │                 │  worker-4   │           │
│  │  (Cache)    │                 │  (Celery)   │           │
│  └─────────────┘                 └─────────────┘           │
│                                                              │
│  ┌─────────────────────────────────────────────┐           │
│  │  node-exporter (10.1.0.6:9100)              │           │
│  └─────────────────────────────────────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Контейнеры

#### 1. tryon-worker (x4 реплики)

| Параметр | Значение |
|----------|----------|
| Image | tryon-service-tryon-worker:latest |
| Command | `celery -A app.celery_app worker -Q tryon_queue -c 1` |
| Memory limit | 512MB |
| Memory reservation | 256MB |
| Restart policy | unless-stopped |
| Stop grace period | 35s |

**Конфигурация:**
```yaml
deploy:
  replicas: 4
  resources:
    limits:
      memory: 512M
    reservations:
      memory: 256M
```

#### 2. redis-cache

| Параметр | Значение |
|----------|----------|
| Image | redis:7-alpine |
| Max memory | 512MB |
| Eviction policy | allkeys-lru |
| Persistence | AOF (appendonly yes) |
| Port | 6379 (internal only) |

**Конфигурация:**
```yaml
command: >
  redis-server
  --maxmemory 512mb
  --maxmemory-policy allkeys-lru
  --appendonly yes
  --appendfsync everysec
```

#### 3. node-exporter

| Параметр | Значение |
|----------|----------|
| Image | prom/node-exporter:v1.7.0 |
| Port | 10.1.0.6:9100 |
| Mount | / → /host (read-only) |

---

## Celery workers

### Конфигурация

**Файл:** `app/celery_app.py`

```python
celery_app = Celery(
    "tryon_service",
    broker="redis://:PASSWORD@10.1.0.4:6379/4",
    backend="redis://:PASSWORD@10.1.0.4:6379/5",
)

celery_app.conf.update(
    task_serializer="json",
    result_serializer="json",
    worker_prefetch_multiplier=1,      # Один task за раз
    worker_max_tasks_per_child=100,    # Рестарт после 100 tasks
    task_acks_late=True,               # ACK после выполнения
    task_reject_on_worker_lost=True,   # Requeue при падении
    result_expires=3600,               # Результаты живут 1 час
)
```

### Task routing

| Task | Queue |
|------|-------|
| app.tasks.virtual_tryon | tryon_queue |
| app.tasks.health_check | tryon_queue |

### Time limits

| Limit | Value | Описание |
|-------|-------|----------|
| time_limit | 30s | Hard limit (SIGKILL) |
| soft_time_limit | 25s | Soft limit (exception) |

### Retry policy

```python
@celery_app.task(
    autoretry_for=(Exception,),
    retry_kwargs={'max_retries': 1, 'countdown': 1}
)
```

- **max_retries:** 1 (одна повторная попытка)
- **countdown:** 1 секунда между попытками

---

## Redis кэширование

### Архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                      Redis Setup                             │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   EXTERNAL (Push Server 10.1.0.4)                           │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  Redis DB 4: Celery Broker (task queue)             │  │
│   │  Redis DB 5: Celery Results (task results)          │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                              │
│   LOCAL (redis-cache container)                             │
│   ┌─────────────────────────────────────────────────────┐  │
│   │  Redis DB 0: Try-on result cache                    │  │
│   │  - Max memory: 512MB                                │  │
│   │  - Policy: allkeys-lru                              │  │
│   │  - TTL: 24 hours                                    │  │
│   └─────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Cache key format

```
tryon:{sha256(person_url + "|" + garment_url)[:16]}
```

**Пример:**
```
person_url: https://example.com/person.jpg
garment_url: https://example.com/garment.jpg

Key: tryon:a1b2c3d4e5f67890
Value: https://fal.media/files/xxx/result.png
TTL: 86400 seconds (24 hours)
```

### Логика кэширования

```python
def get_cached_result(person_url, garment_url):
    key = f"tryon:{sha256(person_url + '|' + garment_url)[:16]}"
    return redis_client.get(key)

def set_cached_result(person_url, garment_url, result_url):
    key = f"tryon:{sha256(person_url + '|' + garment_url)[:16]}"
    redis_client.setex(key, 86400, result_url)  # TTL 24h
```

### Производительность

| Метрика | Значение |
|---------|----------|
| Cache hit latency | ~3ms |
| Cache miss + fal.ai | ~15-20s |
| Expected hit rate | >30% |

---

## fal.ai интеграция

### Endpoints

#### Primary: Flux 2 LoRA Virtual Try-On

| Параметр | Значение |
|----------|----------|
| Endpoint | `fal-ai/flux-2-lora-gallery/virtual-tryon` |
| Cost | ~$0.05/image |
| Latency | 10-20s |

**Request:**
```python
fal_client.subscribe(
    "fal-ai/flux-2-lora-gallery/virtual-tryon",
    arguments={
        "image_urls": [person_url, garment_url],
        "prompt": "A person wearing the garment, virtual try-on",
        "guidance_scale": 2.5,
        "num_inference_steps": 40,
    }
)
```

**Response:**
```json
{
  "images": [
    {"url": "https://v3b.fal.media/files/xxx/result.png"}
  ]
}
```

#### Backup: FASHN v1.6

| Параметр | Значение |
|----------|----------|
| Endpoint | `fal-ai/fashn/tryon/v1.6` |
| Cost | ~$0.075/image |
| Latency | 10-15s |

**Request:**
```python
fal_client.subscribe(
    "fal-ai/fashn/tryon/v1.6",
    arguments={
        "model_image": person_url,
        "garment_image": garment_url,
    }
)
```

### Fallback логика

```
┌─────────────────┐
│     Request     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐     HIT      ┌─────────────────┐
│   Check Cache   │─────────────►│  Return Cached  │
└────────┬────────┘              └─────────────────┘
         │ MISS
         ▼
┌─────────────────┐      OK      ┌─────────────────┐
│  Call Flux 2    │─────────────►│ Cache & Return  │
│    (Primary)    │              └─────────────────┘
└────────┬────────┘
         │ FAIL
         ▼
┌─────────────────┐      OK      ┌─────────────────┐
│  Call FASHN     │─────────────►│ Cache & Return  │
│    (Backup)     │              └─────────────────┘
└────────┬────────┘
         │ FAIL
         ▼
┌─────────────────┐
│  Return Error   │
│  (will retry)   │
└─────────────────┘
```

---

## Systemd автозапуск

### Unit file

**Файл:** `/etc/systemd/system/tryon.service`

```ini
[Unit]
Description=tryon-service Docker Compose
Documentation=http://gitlab-real.unde.life/unde/tryon-service
Requires=docker.service
After=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/unde/tryon-service
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
ExecReload=/usr/bin/docker compose restart
TimeoutStartSec=0
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
```

### Команды

```bash
# Статус
systemctl status tryon.service

# Запуск
systemctl start tryon.service

# Остановка
systemctl stop tryon.service

# Рестарт
systemctl restart tryon.service

# Включить автозапуск
systemctl enable tryon.service

# Отключить автозапуск
systemctl disable tryon.service
```

---

## Мониторинг

### Node Exporter

| Параметр | Значение |
|----------|----------|
| URL | http://10.1.0.6:9100/metrics |
| Format | Prometheus |

**Основные метрики:**
- `node_cpu_seconds_total` - CPU usage
- `node_memory_MemAvailable_bytes` - Available memory
- `node_disk_io_time_seconds_total` - Disk I/O
- `node_network_receive_bytes_total` - Network RX
- `node_network_transmit_bytes_total` - Network TX

### Docker logs

```bash
# Все логи
docker compose logs

# Только workers
docker compose logs tryon-worker

# Follow mode
docker compose logs -f tryon-worker

# Последние 100 строк
docker compose logs --tail=100 tryon-worker
```

### Health checks

```bash
# Скрипт проверки
/opt/unde/tryon-service/scripts/health-check.sh

# Ручная проверка Redis cache
docker compose exec redis-cache redis-cli ping

# Проверка Celery workers
docker compose exec tryon-service-tryon-worker-1 \
  celery -A app.celery_app inspect active
```

---

## Переменные окружения

### .env файл

**Расположение:** `/opt/unde/tryon-service/.env`

```bash
# fal.ai API
FAL_KEY=29389999-cd59-42b2-8000-4e2150bf1765:8d37872e0f607dbca85120054bb05853

# Celery (Redis на Push Server)
REDIS_PASSWORD=kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=
CELERY_BROKER_URL=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/4
CELERY_RESULT_BACKEND=redis://:${REDIS_PASSWORD}@10.1.0.4:6379/5

# Локальный Redis cache
REDIS_CACHE_URL=redis://redis-cache:6379/0

# PostgreSQL (опционально)
DATABASE_URL=postgresql://undeuser:X37nLbzPI2jeL@10.1.1.2:6432/unde_main
```

### Безопасность

- `.env` файл **НЕ** коммитится в git (в `.gitignore`)
- Токены передаются только через переменные окружения
- Redis password в URL-encoded формате

---

## Логика работы

### Полный flow запроса

```
1. App Server (10.1.0.2) создаёт Celery task
   │
   ▼
2. Task попадает в Redis queue (10.1.0.4:6379/4)
   │
   ▼
3. Один из 4 workers получает task
   │
   ▼
4. Worker проверяет локальный Redis cache
   │
   ├─► HIT: возвращает cached URL (3ms)
   │
   └─► MISS: продолжает
       │
       ▼
5. Worker вызывает fal.ai Flux
   │
   ├─► OK: кэширует результат, возвращает
   │
   └─► FAIL: пробует FASHN (backup)
       │
       ├─► OK: кэширует результат, возвращает
       │
       └─► FAIL: возвращает ошибку (retry)
   │
   ▼
6. Результат сохраняется в Redis backend (10.1.0.4:6379/5)
   │
   ▼
7. App Server получает результат через result.get()
```

### Временные характеристики

| Сценарий | Latency |
|----------|---------|
| Cache hit | ~3ms |
| Flux success | 10-20s |
| Flux fail → FASHN | 20-35s |
| All fail + retry | 40-60s |

### SLA

| Метрика | Target | Actual |
|---------|--------|--------|
| p50 latency | < 3s | ~15s (cold), ~3ms (cached) |
| p95 latency | < 5s | ~20s (cold) |
| Error rate | < 1% | TBD |

> **Note:** Cold requests (без кэша) превышают SLA из-за latency fal.ai API.
> При достаточном cache hit rate общая p50 будет в пределах SLA.

---

## Команды управления

### Основные операции

```bash
cd /opt/unde/tryon-service

# Статус контейнеров
docker compose ps

# Запуск
docker compose up -d

# Остановка
docker compose down

# Рестарт
docker compose restart

# Рестарт только workers
docker compose restart tryon-worker

# Пересборка и запуск
docker compose up -d --build
```

### Логи

```bash
# Все логи
docker compose logs

# Workers в реальном времени
docker compose logs -f tryon-worker

# Последние 50 строк
docker compose logs --tail=50
```

### Обновление

```bash
cd /opt/unde/tryon-service

# Получить обновления из GitLab
git pull

# Пересобрать и перезапустить
docker compose build
docker compose up -d
```

### Тестирование

```bash
# Health check
./scripts/health-check.sh

# Тестовый try-on запрос
./scripts/test-tryon.sh

# Ручной тест через Python
docker exec -it tryon-service-tryon-worker-1 python << 'EOF'
from app.tasks import virtual_tryon
result = virtual_tryon.delay(
    "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=512",
    "https://images.unsplash.com/photo-1434389677669-e08b4cac3105?w=512"
)
print(result.get(timeout=60))
EOF
```

### Кэш

```bash
# Проверить Redis cache
docker compose exec redis-cache redis-cli ping

# Статистика памяти
docker compose exec redis-cache redis-cli info memory

# Количество ключей
docker compose exec redis-cache redis-cli dbsize

# Очистить кэш
docker compose exec redis-cache redis-cli FLUSHDB
```

---

## Troubleshooting

### Workers не запускаются

```bash
# Проверить логи
docker compose logs tryon-worker

# Проверить подключение к Redis broker
docker compose exec tryon-service-tryon-worker-1 \
  python -c "import redis; r=redis.from_url('$CELERY_BROKER_URL'); print(r.ping())"
```

### Ошибка подключения к Redis broker

```bash
# Проверить сеть
ping 10.1.0.4

# Проверить Redis порт
nc -zv 10.1.0.4 6379

# Проверить пароль
redis-cli -h 10.1.0.4 -a 'PASSWORD' ping
```

### fal.ai ошибки

```bash
# Проверить FAL_KEY
docker compose exec tryon-service-tryon-worker-1 \
  python -c "import os; print('FAL_KEY set:', bool(os.environ.get('FAL_KEY')))"

# Тест API напрямую
docker compose exec tryon-service-tryon-worker-1 python << 'EOF'
import fal_client
result = fal_client.subscribe(
    "fal-ai/flux-2-lora-gallery/virtual-tryon",
    arguments={
        "image_urls": [
            "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=512",
            "https://images.unsplash.com/photo-1434389677669-e08b4cac3105?w=512"
        ],
        "prompt": "test"
    }
)
print(result)
EOF
```

### Высокая latency

1. Проверить cache hit rate
2. Проверить загрузку fal.ai
3. Проверить сетевые задержки до fal.ai
4. Увеличить количество workers

### Контейнер "unhealthy"

Health check в Dockerfile использует `celery inspect ping`, который может 
таймаутиться при высокой нагрузке. Это **не критично** — workers работают.

Для исправления можно увеличить timeout в Dockerfile:
```dockerfile
HEALTHCHECK --interval=30s --timeout=30s ...
```

---

## Ссылки

- **GitLab:** http://gitlab-real.unde.life/unde/tryon-service
- **fal.ai Docs:** https://fal.ai/docs
- **Celery Docs:** https://docs.celeryq.dev/
- **Redis Docs:** https://redis.io/docs/

---

*Документ создан: 2026-01-28*  
*Последнее обновление: 2026-01-28*
