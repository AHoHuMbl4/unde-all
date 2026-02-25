# Server: Recognition
<!-- Этот файл — ПОЛНАЯ карта сервера. Обновляй при ЛЮБЫХ изменениях. -->

---

## 1. Identity & Role

- **Name:** Recognition
- **Role:** Координатор Fashion Recognition Pipeline — принимает Celery-задачи, оркестрирует вызовы Ximilar Gateway и LLM Reranker, собирает результаты 4 шагов, сохраняет лог в Production DB
- **Почему отдельный сервер:** I/O-bound оркестрация изолирована от App Server (10.1.0.2) и ML-серверов (10.1.0.12, 10.1.0.13) для независимого масштабирования и мониторинга
- **Связь с другими серверами:**
  - Redis (10.1.0.4:6379/6) — получает задачи из очереди `recognition_queue`, отдаёт результаты
  - Ximilar Gateway (10.1.0.12:8001) — HTTP: /detect, /tag, /search
  - LLM Reranker (10.1.0.13:8002) — HTTP: /tag, /rerank
  - Production DB (10.1.1.2:6432) — PostgreSQL: запись логов в `recognition_requests`

## 2. Hardware & Provider

- **Provider:** Hetzner
- **Plan/Model:** CPX11
- **Location / DC:** <!-- TODO: уточнить DC -->
- **CPU:** 2 vCPU (shared)
- **RAM:** 2 GB
- **Storage:** 40 GB NVMe SSD
- **Network:** private network 10.1.0.0/16
- **Стоимость:** <!-- TODO: уточнить -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** 89.167.90.152
- **Private IP:** 10.1.0.14/32 (enp7s0)
- **IPv6:** <!-- TODO: проверить -->

### 3.2 DNS
| Domain | Тип записи | Куда указывает | Для чего |
|---|---|---|---|
| <!-- TODO --> | — | — | Внешнего домена не требует (внутренний сервис) |

### 3.3 Firewall
| Port | Protocol | Source | Назначение | Почему открыт |
|---|---|---|---|---|
| 22 | TCP | <!-- TODO --> | SSH | Управление сервером |
| 9100 | TCP | 10.1.0.0/16 | node_exporter | Prometheus scraping |

<!-- TODO: проверить ufw / iptables -->

### 3.4 SSH
- **Port:** 22
- **User:** root
- **Auth:** <!-- TODO: ключи -->
- **Конфиг:** /etc/ssh/sshd_config

## 4. OS & System Configuration

### 4.1 Операционная система
- **OS:** Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel:** 6.8.0-71-generic
- **Timezone:** UTC
- **Locale:** <!-- TODO -->

### 4.2 Системные настройки (sysctl, limits)
| Параметр | Значение | Зачем | Где настроено |
|---|---|---|---|
| — | — | Дефолтные | — |

### 4.3 Установленные системные пакеты
| Пакет | Версия | Зачем установлен | Как используется |
|---|---|---|---|
| docker.io | 28.2.2 | Контейнеризация сервисов | recognition-orchestrator контейнер |
| docker-compose-v2 | 2.37.1 | Оркестрация контейнеров | `docker compose up -d` |
| postgresql-client | — | Инициализация таблиц в Production DB | `psql -f init-db.sql` |
| node_exporter | 1.8.2 | Мониторинг системных метрик | systemd, 0.0.0.0:9100 |

### 4.4 Пользователи и права
| User | Роль | Группы | Зачем создан |
|---|---|---|---|
| root | Администратор | — | Системный |
| node_exporter | Service account | node_exporter | Запуск node_exporter без привилегий |

### 4.5 Cron jobs & systemd timers
| Schedule | Команда | Назначение | Конфиг |
|---|---|---|---|
| — | — | Нет запланированных задач | — |

## 5. Docker & Containers — ДЕТАЛЬНО

### 5.1 Docker конфигурация
- **Docker version:** 28.2.2
- **Storage driver:** overlay2
- **Data root:** /var/lib/docker
- **Logging driver:** json-file (default)
- **Docker networks:** recognition_default (bridge)

### 5.2 Docker Compose files
| Файл | Путь | Что описывает | Как запускать |
|---|---|---|---|
| docker-compose.yml | /opt/unde/recognition/docker-compose.yml | Recognition Orchestrator (Celery worker) | `cd /opt/unde/recognition && docker compose up -d` |

### 5.3 Каждый контейнер / сервис — ПОДРОБНО

#### 5.3.1 — recognition-orchestrator
- **Image:** recognition-recognition-orchestrator (local build)
- **Base:** python:3.12-slim
- **Назначение:** Celery worker, оркестрирует 4-шаговый Fashion Recognition Pipeline
- **Почему нужен:** Без него задачи из очереди recognition_queue не обрабатываются — pipeline стоит
- **Ports:** нет (работает через Redis, исходящие HTTP)
- **Volumes:** нет (stateless worker)
- **Environment variables:** из .env — CELERY_BROKER_URL, CELERY_RESULT_BACKEND, DATABASE_URL, XIMILAR_GW_URL, LLM_RERANKER_URL, CONFIDENCE_HIGH, CONFIDENCE_MEDIUM
- **Зависимости:** Redis (10.1.0.4:6379/6), Ximilar GW (10.1.0.12:8001), LLM Reranker (10.1.0.13:8002), Production DB (10.1.1.2:6432)
- **Конфигурация:** /opt/unde/recognition/.env
- **Ресурсы:** memory limit 1G
- **Healthcheck:** `scripts/health-check.sh` (celery inspect ping)
- **Логи:** `docker logs recognition-orchestrator`
- **Restart policy:** unless-stopped
- **CMD:** `celery -A app.celery_app worker -Q recognition_queue -c 2 --max-tasks-per-child=200`
- **Известные проблемы:** нет

## 6. Volumes & Persistent Data

### 6.1 Docker volumes
Нет — stateless worker, данные не хранятся локально.

### 6.2 Host-mounted директории
Нет.

### 6.3 Бэкапы данных
Не требуется — сервер stateless. Код в GitLab, данные в Production DB.

## 7. Environment Files & Secrets

### 7.1 — /opt/unde/recognition/.env
| Variable | Описание | Какой сервис использует |
|---|---|---|
| XIMILAR_GW_URL | URL Ximilar Gateway (http://10.1.0.12:8001) | app/clients/ximilar_gw.py |
| LLM_RERANKER_URL | URL LLM Reranker (http://10.1.0.13:8002) | app/clients/llm_reranker.py |
| CELERY_BROKER_URL | Redis broker с паролем (10.1.0.4:6379/6) | app/celery_app.py |
| CELERY_RESULT_BACKEND | Redis result backend (10.1.0.4:6379/6) | app/celery_app.py |
| DATABASE_URL | PostgreSQL Production DB (10.1.1.2:6432/unde_main) | app/db.py |
| CONFIDENCE_HIGH | Порог exact match (0.85) | app/tasks.py |
| CONFIDENCE_MEDIUM | Порог similar match (0.50) | app/tasks.py |

## 8. Reverse Proxy & Routing

Не требуется — сервер не принимает входящих HTTP-запросов. Работает как Celery worker через Redis.

## 9. Database(s)

Локальных БД нет. Подключается к:

### 9.1 — unde_main (remote)
- **Engine:** PostgreSQL (через PgBouncer)
- **Host:** 10.1.1.2:6432
- **Database:** unde_main
- **User:** undeuser
- **Таблица:** `recognition_requests` — логи pipeline (items detected, tags, search results, final matches, timing)
- **Индексы:** idx_recognition_user (user_id), idx_recognition_created (created_at DESC)

## 10. Monitoring & Observability

### 10.1 Metrics
| Exporter | Port | Что собирает | Конфиг |
|---|---|---|---|
| node_exporter | 9100 | CPU/RAM/disk/network | /etc/systemd/system/node_exporter.service |

### 10.2 Dashboards
- **Grafana:** <!-- TODO: добавить Recognition в Grafana -->

### 10.3 Alerts
<!-- TODO: настроить алерты на Celery queue backlog, container restart, high latency -->

### 10.4 Логи
- **Celery worker:** `docker logs -f recognition-orchestrator`
- **node_exporter:** `journalctl -u node_exporter -f`
- **Ротация:** Docker default json-file (без ограничений — TODO: настроить max-size)

## 11. Deploy Procedure

### 11.1 Обычный деплой (обновление)
```bash
cd /opt/unde/recognition
docker compose build
docker compose up -d
docker logs recognition-orchestrator --tail 20
```

### 11.2 Деплой с пересозданием
```bash
cd /opt/unde/recognition
docker compose down
docker compose build --no-cache
docker compose up -d
```

### 11.3 Rollback
```bash
# Docker хранит предыдущий образ
docker compose down
docker compose up -d  # с предыдущим образом если не делали build
# Или откатить код из git и пересобрать
```

## 12. Recovery — Rebuild from Scratch

### 12.1 Подготовка сервера
```bash
apt update && apt upgrade -y
hostnamectl set-hostname recognition
apt install -y docker.io docker-compose-v2 postgresql-client
systemctl enable docker
```

### 12.2 node_exporter
```bash
useradd --no-create-home --shell /bin/false node_exporter
wget https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz
tar xzf node_exporter-1.8.2.linux-amd64.tar.gz
cp node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chown node_exporter:node_exporter /usr/local/bin/node_exporter
rm -rf node_exporter-1.8.2.linux-amd64*
# Создать /etc/systemd/system/node_exporter.service (см. секцию 10)
systemctl daemon-reload && systemctl enable --now node_exporter
```

### 12.3 Клонирование и запуск
```bash
mkdir -p /opt/unde
git clone http://root:TOKEN@gitlab-real.unde.life/unde/Recognition.git /opt/unde/recognition
cd /opt/unde/recognition
# .env уже в репо
docker compose build && docker compose up -d
```

### 12.4 Инициализация таблицы (если нужно)
```bash
psql "postgresql://undeuser:X37nLbzPI2jeL@10.1.1.2:6432/unde_main" -f /opt/unde/recognition/deploy/init-db.sql
```

### 12.5 Проверка
- [x] `docker ps` — recognition-orchestrator running
- [x] `curl http://10.1.0.14:9100/metrics` — node_exporter отвечает
- [x] `scripts/health-check.sh` — Celery pong
- [x] init-db.sql — таблица создана

## 13. Notes, Quirks & Known Issues

- Сервер stateless — всё состояние в Redis и Production DB
- max-tasks-per-child=200 — worker перезапускается после 200 задач для предотвращения утечек памяти
- Memory limit 1G для контейнера при 2GB RAM сервера — оставляет место для ОС и node_exporter
- Celery concurrency=2 — оптимально для I/O-bound задач на 2 vCPU

## 14. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial deployment | Docker, node_exporter, Recognition Orchestrator deployed. DB table created. |
