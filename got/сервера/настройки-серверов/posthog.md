# Server: posthog

---

## 1. Identity & Role

- **Name:** posthog
- **Role:** Product analytics для команды UNDE — retention, funnels, session recording, feature flags, A/B tests
- **Почему отдельный сервер:** PostHog требует ClickHouse, Kafka, PostgreSQL, Redis — тяжёлый стек, изоляция от основных сервисов
- **Связь с другими серверами:** Принимает events из мобильного приложения через private network (10.1.1.0/24). Только структурные события, без персональных данных.

## 2. Hardware & Provider

- **Provider:** Hetzner Dedicated
- **Plan/Model:** Xeon E3-1275V6
- **Location / DC:** Helsinki
- **CPU:** Intel Xeon E3-1275V6, 4 cores / 8 threads
- **RAM:** 64 GB DDR4
- **Storage:** 2× SATA 480 GB (RAID1 md0, 439 GB usable)
- **Network:** Hetzner standard + vSwitch (10.1.1.0/24)
- **Стоимость:** <!-- TODO -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** 95.216.39.182
- **Private IP:** 10.1.1.30 (vSwitch, интерфейс enp0s31f6.4000)
- **IPv6:** <!-- TODO: если есть -->

### 3.2 DNS
| Domain | Тип записи | Куда указывает | Для чего |
|---|---|---|---|
| <!-- TODO --> | A | 95.216.39.182 | <!-- TODO: если будет домен --> |

### 3.3 Firewall
| Port | Protocol | Source | Назначение | Почему открыт |
|---|---|---|---|---|
| 22 | TCP | any | SSH | Администрирование |
| 80 | TCP | 0.0.0.0/0 | Caddy → PostHog web | HTTP доступ к PostHog |
| 9100 | TCP | 10.1.1.0/24 | node_exporter | Мониторинг (Prometheus) |
| 8081 | TCP | 0.0.0.0/0 | Temporal UI | Управление workflows |
| 19000-19001 | TCP | 0.0.0.0/0 | MinIO | Object storage UI/API |
| 7233 | TCP | 0.0.0.0/0 | Temporal gRPC | Temporal server |

<!-- TODO: Настроить UFW — ограничить доступ к 80, 8081, 19000 только из 10.1.1.0/24 -->

### 3.4 SSH
- **Port:** 22
- **User:** root
- **Auth:** <!-- TODO: ключи -->
- **Конфиг:** /etc/ssh/sshd_config (default)

## 4. OS & System Configuration

### 4.1 Операционная система
- **OS:** Ubuntu 24.04.4 LTS
- **Kernel:** 6.8.0-101-generic
- **Timezone:** CET (Europe/Berlin по умолчанию Hetzner)
- **Locale:** <!-- TODO -->

### 4.2 Системные настройки (sysctl, limits)
| Параметр | Значение | Зачем | Где настроено |
|---|---|---|---|
| (default) | — | Не изменены | — |

### 4.3 Установленные системные пакеты
| Пакет | Версия | Зачем установлен | Как используется |
|---|---|---|---|
| docker.io | 28.2.2 | Контейнеризация | Все сервисы PostHog |
| docker-compose-v2 | 2.37.1 | Оркестрация | `docker compose up -d` |
| git | system | Клонирование PostHog | /opt/unde/posthog/posthog |
| brotli | system | Декомпрессия GeoIP | Одноразово при установке |

### 4.4 Пользователи и права
| User | Роль | Группы | Зачем создан |
|---|---|---|---|
| root | Администратор | — | Системный |
| node_exporter | Сервисный | node_exporter | Запуск node_exporter |

### 4.5 Cron jobs & systemd timers
| Schedule | Команда | Назначение | Конфиг |
|---|---|---|---|
| — | node_exporter | Метрики | /etc/systemd/system/node_exporter.service |

## 5. Docker & Containers — ДЕТАЛЬНО

### 5.1 Docker конфигурация
- **Docker version:** 28.2.2
- **Compose version:** 2.37.1
- **Storage driver:** overlay2
- **Data root:** /var/lib/docker
- **Docker networks:** posthog_default (bridge, 172.18.0.0/16)

### 5.2 Docker Compose files
| Файл | Путь | Что описывает | Как запускать |
|---|---|---|---|
| docker-compose.yml | /opt/unde/posthog/ | PostHog hobby (модифицированный для HTTP) | `cd /opt/unde/posthog && docker compose up -d` |
| docker-compose.base.yml | /opt/unde/posthog/ | Базовые определения сервисов | Используется через extends |

### 5.3 Контейнеры

#### 5.3.1 — db (PostgreSQL)
- **Image:** postgres:15.12-alpine
- **Назначение:** Метаданные PostHog (users, orgs, projects, feature flags, etc.)
- **Ports:** 5432 (internal only)
- **Volumes:** posthog_postgres-data:/var/lib/postgresql/data
- **Healthcheck:** pg_isready -U posthog
- **Restart:** on-failure

#### 5.3.2 — redis7
- **Image:** redis:7.2-alpine
- **Назначение:** Кеш, сессии, очереди задач
- **Ports:** 6379 (internal only)
- **Volumes:** posthog_redis7-data:/data
- **Config:** maxmemory 200mb, allkeys-lru
- **Healthcheck:** redis-cli ping
- **Restart:** on-failure

#### 5.3.3 — clickhouse
- **Image:** clickhouse/clickhouse-server:25.12.5.44
- **Назначение:** Аналитическая БД — хранит все события, запросы funnels/retention
- **Ports:** 8123, 9000, 9009 (internal)
- **Volumes:** posthog_clickhouse-data:/var/lib/clickhouse + config из ./posthog/docker/clickhouse/
- **Healthcheck:** wget http://localhost:8123/ping
- **Depends on:** kafka, zookeeper

#### 5.3.4 — kafka (Redpanda)
- **Image:** redpandadata/redpanda:v25.1.9
- **Назначение:** Стриминг событий между сервисами PostHog
- **Ports:** 9092 (internal Kafka), 8082 (Pandaproxy)
- **Volumes:** posthog_kafka-data:/bitnami/kafka
- **Config:** --smp 2 --memory 3G --mode dev-container
- **Healthcheck:** curl http://localhost:9644/v1/status/ready
- **Depends on:** zookeeper

#### 5.3.5 — zookeeper
- **Image:** zookeeper:3.7.0
- **Назначение:** Координация Kafka/ClickHouse
- **Volumes:** posthog_zookeeper-data, posthog_zookeeper-datalog, posthog_zookeeper-logs

#### 5.3.6 — web
- **Image:** posthog/posthog:latest
- **Назначение:** PostHog web UI + API (Granian ASGI server, 2 workers)
- **Command:** /compose/start (migrate → docker-server → granian :8000)
- **Ports:** 8000 (internal, проксируется через Caddy)
- **Env:** SITE_URL=http://10.1.1.30, USE_GRANIAN=true, GRANIAN_WORKERS=2
- **Depends on:** db, redis7, clickhouse, kafka, objectstorage, seaweedfs

#### 5.3.7 — worker
- **Image:** posthog/posthog:latest
- **Назначение:** Celery worker — фоновые задачи (экспорт, вычисления когорт, etc.)
- **Depends on:** db, redis7, clickhouse, kafka, web

#### 5.3.8 — plugins
- **Image:** posthog/posthog-node:latest
- **Назначение:** Node.js plugin engine + CDP (Customer Data Platform)
- **Ports:** 6738 (internal)
- **Depends on:** db, redis7, clickhouse, kafka, objectstorage, seaweedfs

#### 5.3.9 — proxy (Caddy)
- **Image:** caddy:latest
- **Назначение:** Reverse proxy — HTTP routing к web, capture, replay-capture, feature-flags, livestream
- **Ports:** 0.0.0.0:80 → 80
- **Volumes:** posthog_caddy-data, posthog_caddy-config
- **Config:** HTTP-only (без TLS), CADDY_HOST='http://10.1.1.30, http://'

#### 5.3.10 — capture
- **Image:** ghcr.io/posthog/posthog/capture:master
- **Назначение:** Rust event capture service — приём событий /e, /i/v0, /batch, /capture
- **Ports:** 3000 (internal)

#### 5.3.11 — replay-capture
- **Image:** ghcr.io/posthog/posthog/capture:master
- **Назначение:** Session recording capture — приём /s/* запросов
- **Ports:** 3000 (internal)

#### 5.3.12 — feature-flags
- **Image:** ghcr.io/posthog/posthog/feature-flags:master
- **Назначение:** Rust feature flag evaluation service — /flags/*
- **Ports:** 3001 (internal)
- **Healthcheck:** curl http://localhost:3001/_readiness

#### 5.3.13 — objectstorage (MinIO)
- **Image:** minio/minio:RELEASE.2025-04-22T22-12-26Z
- **Назначение:** S3-совместимое хранилище для PostHog
- **Ports:** 0.0.0.0:19000 (API), 0.0.0.0:19001 (Console)
- **Volumes:** posthog_objectstorage:/data
- **Credentials:** object_storage_root_user / object_storage_root_password

#### 5.3.14 — seaweedfs
- **Image:** chrislusf/seaweedfs:4.03
- **Назначение:** S3 storage для session recordings
- **Ports:** 127.0.0.1:8333 (S3 API), 127.0.0.1:9333 (Master)
- **Volumes:** posthog_seaweedfs:/data
- **Healthcheck:** weed shell s3.bucket.list | grep posthog

#### 5.3.15 — temporal
- **Image:** temporalio/auto-setup:1.20.0
- **Назначение:** Workflow engine для PostHog
- **Ports:** 0.0.0.0:7233 (gRPC)
- **Depends on:** db (healthy), elasticsearch
- **Healthcheck:** nc -z hostname 7233

#### 5.3.16 — temporal-ui
- **Image:** temporalio/ui:2.31.2
- **Назначение:** Web UI для Temporal
- **Ports:** 0.0.0.0:8081 → 8080

#### 5.3.17 — temporal-admin-tools
- **Image:** temporalio/admin-tools:1.20.0
- **Назначение:** CLI утилиты для Temporal

#### 5.3.18 — temporal-django-worker
- **Image:** posthog/posthog:latest
- **Назначение:** Django worker для Temporal workflows

#### 5.3.19 — elasticsearch
- **Image:** elasticsearch:7.17.28
- **Назначение:** Поиск для Temporal (ES_JAVA_OPTS=-Xms256m -Xmx256m)

#### 5.3.20 — cyclotron-janitor
- **Image:** ghcr.io/posthog/posthog/cyclotron-janitor:master
- **Назначение:** Очистка данных cyclotron

#### 5.3.21 — cymbal
- **Image:** ghcr.io/posthog/posthog/cymbal:master
- **Назначение:** Exception ingestion processor

#### 5.3.22 — property-defs-rs
- **Image:** ghcr.io/posthog/posthog/property-defs-rs:master
- **Назначение:** Property definitions sync service

#### 5.3.23 — livestream
- **Image:** ghcr.io/posthog/posthog/livestream:master
- **Назначение:** Live event streaming WebSocket

#### 5.3.24 — kafka-init (одноразовый)
- **Image:** redpandadata/redpanda:v25.1.9
- **Назначение:** Создание Kafka topics (exceptions_ingestion, clickhouse_events_json)

## 6. Volumes & Persistent Data

### 6.1 Docker volumes
| Volume name | Что хранит | Критичность |
|---|---|---|
| posthog_postgres-data | PostgreSQL данные (users, orgs, flags) | Высокая |
| posthog_clickhouse-data | ClickHouse данные (все events) | Высокая |
| posthog_redis7-data | Redis persistence | Средняя |
| posthog_kafka-data | Kafka/Redpanda data | Средняя |
| posthog_objectstorage | MinIO objects | Средняя |
| posthog_seaweedfs | Session recordings | Средняя |
| posthog_caddy-data | Caddy state | Низкая |
| posthog_caddy-config | Caddy config | Низкая |
| posthog_zookeeper-* | ZK data/logs | Низкая |
| posthog_redpanda-data | Redpanda internal | Низкая |

### 6.2 Host-mounted директории
| Host path | Mount в контейнере | Что хранит |
|---|---|---|
| /opt/unde/posthog/compose | /compose | Startup scripts (start, wait, temporal-django-worker) |
| /opt/unde/posthog/share | /share | GeoLite2-City.mmdb (GeoIP) |
| /opt/unde/posthog/posthog/docker/clickhouse | /etc/clickhouse-server/ | ClickHouse config |
| /opt/unde/posthog/posthog/docker/temporal/dynamicconfig | /etc/temporal/config/dynamicconfig | Temporal config |
| /opt/unde/posthog/posthog/docker/livestream/configs-hobby.yml | /configs/configs.yml | Livestream config |

### 6.3 Бэкапы данных
- **Что бэкапится:** <!-- TODO: настроить бэкап postgres, clickhouse -->
- **Куда:** <!-- TODO -->
- **Расписание:** <!-- TODO -->

## 7. Environment Files & Secrets

### 7.1 — /opt/unde/posthog/.env
| Variable | Назначение |
|---|---|
| POSTHOG_SECRET | Django SECRET_KEY |
| ENCRYPTION_SALT_KEYS | Шифрование данных |
| DOMAIN | 10.1.1.30 (internal) |
| CADDY_HOST | http://10.1.1.30, http:// |
| REGISTRY_URL | posthog/posthog |
| POSTHOG_APP_TAG | latest |
| OPT_OUT_CAPTURE | true (не отправляем telemetry в PostHog Inc.) |

## 8. Reverse Proxy & Routing

### 8.1 Reverse proxy
- **Софт:** Caddy (latest)
- **Конфиг:** Inline Caddyfile через env var (docker-compose.base.yml)
- **Режим:** HTTP-only (без TLS)

### 8.2 SSL/TLS
- **Не используется** — внутренний сервис, доступ только из private network

### 8.3 Маршруты
| Входящий URL | → Куда | Назначение |
|---|---|---|
| /e, /e/*, /i/v0*, /batch*, /capture* | capture:3000 | Event ingestion |
| /s, /s/* | replay-capture:3000 | Session recording |
| /flags, /flags/* | feature-flags:3001 | Feature flag evaluation |
| /livestream, /livestream/* | livestream:8080 | Live events WebSocket |
| /public/webhooks* | plugins:6738 | Webhooks |
| /* (default) | web:8000 | PostHog UI + API |

## 9. Database(s)

### 9.1 — PostgreSQL 15
- **Engine:** PostgreSQL 15.12-alpine
- **Назначение:** Метаданные PostHog (users, orgs, projects, feature flags, dashboards)
- **Port:** 5432 (internal only)
- **Credentials:** posthog/posthog
- **Data:** posthog_postgres-data volume

### 9.2 — ClickHouse 25.12
- **Engine:** ClickHouse 25.12.5.44
- **Назначение:** Аналитическая БД — все events, session data
- **Port:** 8123 (HTTP), 9000 (Native) — internal only
- **Users:** DEFAULT, API (apipass), APP (apppass)
- **Data:** posthog_clickhouse-data volume

### 9.3 — Redis 7.2
- **Engine:** Redis 7.2-alpine
- **Назначение:** Кеш, Celery broker, сессии
- **Port:** 6379 (internal)
- **Config:** maxmemory 200mb, allkeys-lru

## 10. Monitoring & Observability

### 10.1 Metrics
| Exporter | Port | Что собирает | Конфиг |
|---|---|---|---|
| node_exporter 1.8.2 | 0.0.0.0:9100 | CPU/RAM/disk/network | /etc/systemd/system/node_exporter.service |

### 10.2 Логи
```bash
# PostHog web
cd /opt/unde/posthog && docker compose logs -f web
# All services
cd /opt/unde/posthog && docker compose logs -f
# Specific service
cd /opt/unde/posthog && docker compose logs -f worker
```

## 11. Deploy Procedure

### 11.1 Обычный деплой (обновление PostHog)
```bash
cd /opt/unde/posthog
docker compose pull
docker compose up -d
# Подождать ~5 мин на миграции
curl -s http://10.1.1.30/_health
```

### 11.2 Restart конкретного сервиса
```bash
cd /opt/unde/posthog && docker compose restart web
```

### 11.3 Rollback
```bash
# В .env поменять POSTHOG_APP_TAG на конкретную версию
cd /opt/unde/posthog && docker compose up -d web worker plugins temporal-django-worker asyncmigrationscheck
```

## 12. Recovery — Rebuild from Scratch

### 12.1 Подготовка
```bash
apt update && apt upgrade -y
hostnamectl set-hostname posthog
# Настроить vSwitch интерфейс 10.1.1.30/24
```

### 12.2 Docker
```bash
apt install -y docker.io docker-compose-v2 git curl wget brotli
systemctl enable --now docker
```

### 12.3 node_exporter
```bash
useradd --no-create-home --shell /bin/false node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
# Создать /etc/systemd/system/node_exporter.service
systemctl daemon-reload && systemctl enable --now node_exporter
```

### 12.4 PostHog
```bash
cd /opt/unde/posthog
# Файлы уже в git: docker-compose.yml, docker-compose.base.yml, .env, compose/, share/
docker compose up -d
# Подождать ~5-10 мин на первый запуск (миграции)
```

### 12.5 Проверка
- [ ] docker compose ps — все контейнеры up
- [ ] curl http://10.1.1.30/ — HTTP 200
- [ ] curl http://10.1.1.30:9100/metrics — node_exporter
- [ ] ClickHouse SELECT 1
- [ ] PostgreSQL SELECT 1

## 13. Notes, Quirks & Known Issues

- **Первый запуск:** ~5-10 мин на миграции (Django + ClickHouse + async migrations check). Granian стартует только после всех миграций.
- **Image size:** posthog/posthog:latest = ~10 GB, весь стек ~16 GB images
- **IS_BEHIND_PROXY warning:** В base compose IS_BEHIND_PROXY=true, но trusted proxies не настроены. Безвредно для internal use.
- **OPT_OUT_CAPTURE=true:** Telemetry в PostHog Inc. отключена
- **Kafka retention:** 1 час (KAFKA_LOG_RETENTION_HOURS=1) — hobby default
- **MinIO ports:** 19000-19001 открыты наружу — TODO: ограничить через firewall

## 14. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial deploy | PostHog self-hosted hobby, node_exporter 1.8.2, HTTP-only на 10.1.1.30 |
