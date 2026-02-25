# Server: llm-reranker

HTTP-шлюз к Google Gemini API для Fashion Recognition Pipeline проекта UNDE.
Выполняет контекстный тегинг одежды и визуальный реранкинг товаров-кандидатов.

---

## 1. Identity & Role

- **Name:** llm-reranker
- **Role:** HTTP-шлюз к Gemini API — принимает запросы от pipeline (fashion-recognition), отправляет изображения в Gemini для анализа и сравнения одежды
- **Почему отдельный сервер:** Изоляция LLM-вызовов от основного pipeline. Gemini API имеет rate limits и latency ~5-15 сек, отдельный сервер позволяет масштабировать независимо
- **Связь с другими серверами:** Принимает HTTP-запросы от fashion-recognition pipeline по private network (10.1.0.0/16). Ходит в Google Gemini API (generativelanguage.googleapis.com) через интернет

## 2. Hardware & Provider

- **Provider:** Hetzner Cloud
- **Plan/Model:** CX23 (shared vCPU)
- **Location / DC:** <!-- TODO: уточнить DC -->
- **CPU:** Intel Xeon (Skylake), 2 vCPU, 1 thread per core
- **RAM:** 3.7 GiB (4 GB nominal)
- **Storage:** 38.1 GB SSD (sda), single partition /dev/sda1 37.9G mounted as /
- **Network:** eth0 (public), enp7s0 (private Hetzner network, MTU 1450)
- **Swap:** отсутствует
- **Стоимость:** <!-- TODO: уточнить -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** 89.167.106.167 (eth0)
- **Private IP:** 10.1.0.13 (enp7s0, Hetzner private network 10.1.0.0/16)
- **IPv6:** не настроен

### 3.2 DNS
Домены к серверу не привязаны. Доступ только по IP через private network.

### 3.3 Firewall
Firewall НЕ настроен (будет настраиваться отдельно).

Текущие слушающие порты:

| Port | Protocol | Bind Address | Процесс | Назначение |
|---|---|---|---|---|
| 22 | TCP | 0.0.0.0 | sshd | SSH доступ |
| 8002 | TCP | 10.1.0.13 | docker-proxy (llm-reranker) | FastAPI app — только private network |
| 9100 | TCP | 0.0.0.0 | node_exporter | Prometheus metrics |
| 53 | TCP | 127.0.0.53/127.0.0.54 | systemd-resolved | DNS resolver (local only) |

### 3.4 SSH
- **Port:** 22 (стандартный)
- **User:** root
- **Auth:** SSH ключи
- **Конфиг:** /etc/ssh/sshd_config (дефолтный)

### 3.5 Routing

| Destination | Via | Interface | Notes |
|---|---|---|---|
| default | 172.31.1.1 | eth0 | Internet gateway |
| 10.1.0.0/16 | 10.1.0.1 | enp7s0 | Hetzner private network |
| 172.17.0.0/16 | — | docker0 | Docker default bridge |
| 172.18.0.0/16 | — | br-f3efe8e03c0c | llm-reranker_default network |

## 4. OS & System Configuration

### 4.1 Операционная система
- **OS:** Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel:** 6.8.0-71-generic
- **Timezone:** Etc/UTC
- **NTP:** systemd-timesyncd, synchronized
- **Locale:** default (C.UTF-8)

### 4.2 Системные настройки
Не изменены от дефолтных.

### 4.3 Установленные системные пакеты

| Пакет | Версия | Зачем установлен | Как используется |
|---|---|---|---|
| docker-ce | 29.2.1 | Контейнеризация сервисов | Запуск llm-reranker контейнера |
| docker-compose-plugin | 5.1.0 | Оркестрация контейнеров | `docker compose up -d` |
| docker-buildx-plugin | 0.31.1 | Сборка Docker образов | `docker compose build` |
| containerd.io | 2.2.1 | Container runtime | Используется Docker Engine |
| node_exporter | 1.8.2 | Системный мониторинг | Prometheus metrics на :9100 |
| git | 2.43.0 | Управление кодом | Клонирование и обновление репо |
| curl | 8.5.0 | HTTP клиент | Проверки и скрипты |
| python3 | 3.12.3 | Интерпретатор (host) | Используется для json.tool в скриптах |

Python-пакеты внутри Docker контейнера:

| Package | Version | Purpose |
|---|---|---|
| fastapi | 0.115.6 | HTTP framework |
| uvicorn | 0.34.0 | ASGI server |
| httpx | 0.28.1 | Async HTTP client for Gemini API |
| pydantic | 2.12.5 | Data validation |
| pydantic-settings | 2.7.1 | Settings from .env |
| prometheus-fastapi-instrumentator | 7.0.2 | Prometheus metrics middleware |

### 4.4 Пользователи и права

| User | Роль | Группы | Зачем создан |
|---|---|---|---|
| root | Администратор | — | Системный |
| node_exporter | Сервисный | node_exporter | Запуск node_exporter без root привилегий |

### 4.5 Cron jobs & systemd timers

Нет cron jobs. Systemd сервисы:

| Unit | Status | Description |
|---|---|---|
| docker.service | active (running) | Docker Engine |
| containerd.service | active (running) | Container runtime |
| node_exporter.service | active (running) | Prometheus Node Exporter |
| ssh.service | active (running) | OpenSSH server |

## 5. Docker & Containers — ДЕТАЛЬНО

### 5.1 Docker конфигурация
- **Docker version:** 29.2.1
- **Storage driver:** overlay2
- **Data root:** /var/lib/docker
- **Logging driver:** json-file (default)
- **Конфиг daemon:** /etc/docker/daemon.json (дефолтный)

Docker networks:

| Network | Driver | Subnet | Purpose |
|---|---|---|---|
| bridge | bridge | 172.17.0.0/16 | Default Docker bridge |
| llm-reranker_default | bridge | 172.18.0.0/16 | Compose project network |

### 5.2 Docker Compose files

| Файл | Путь | Что описывает | Как запускать |
|---|---|---|---|
| docker-compose.yml | /opt/unde/llm-reranker/docker-compose.yml | llm-reranker FastAPI service | `cd /opt/unde/llm-reranker && docker compose up -d` |

### 5.3 Контейнеры

#### 5.3.1 — llm-reranker
- **Image:** llm-reranker-llm-reranker:latest (build from local Dockerfile)
- **Назначение:** FastAPI HTTP-шлюз к Gemini API для тегинга и реранкинга одежды
- **Почему нужен:** Единственный сервис на сервере — без него сервер бесполезен
- **Ports:** 10.1.0.13:8002 → 8002 (привязан к private IP, недоступен извне)
- **Volumes:** нет (stateless)
- **Environment variables:** из .env (GEMINI_API_KEY, GEMINI_MODEL, GEMINI_API_URL, HOST, PORT, WORKERS)
- **Зависимости:** нет (standalone, ходит только в Gemini API через интернет)
- **Command:** `uvicorn app.main:app --host 0.0.0.0 --port 8002 --workers 2`
- **Ресурсы:** memory limit 1G
- **Healthcheck:** `curl -sf http://10.1.0.13:8002/health`
- **Логи:** `docker logs -f llm-reranker`
- **Restart policy:** unless-stopped
- **Известные проблемы:** нет

## 6. Volumes & Persistent Data

Сервис **stateless** — нет volumes, нет persistent data.
Код копируется в образ при сборке. Конфигурация через .env.

### 6.3 Бэкапы данных
- **Что бэкапится:** только код (через git push в GitLab)
- **Куда:** http://gitlab-real.unde.life/unde/llm-reranker.git
- **Расписание:** при каждом изменении (git push)
- **Восстановление:** git clone + docker compose up

## 7. Environment Files & Secrets

### 7.1 — /opt/unde/llm-reranker/.env

| Variable | Значение | Зачем | Какой сервис использует |
|---|---|---|---|
| GEMINI_API_KEY | AIzaSyBQB2jKFgBDLeBIiqeHFVC_8q5INAvr9D0 | API ключ Google Gemini | llm-reranker (gemini_client.py) |
| GEMINI_MODEL | gemini-2.5-flash | Модель Gemini для запросов | llm-reranker (gemini_client.py) |
| GEMINI_API_URL | https://generativelanguage.googleapis.com/v1beta | Base URL Gemini API | llm-reranker (gemini_client.py) |
| HOST | 0.0.0.0 | Bind address сервера | uvicorn |
| PORT | 8002 | Порт сервера | uvicorn |
| WORKERS | 2 | Количество uvicorn workers | uvicorn |

## 8. Reverse Proxy & Routing

На этом сервере **нет reverse proxy**. Приложение слушает напрямую на 10.1.0.13:8002.
Доступ только из private network (10.1.0.0/16).

## 9. Database(s)

На этом сервере **нет баз данных**. Сервис stateless.

## 10. Monitoring & Observability

### 10.1 Metrics

| Exporter/Endpoint | Port | URL | Что собирает |
|---|---|---|---|
| node_exporter | 9100 | http://10.1.0.13:9100/metrics | CPU, RAM, disk, network (системные метрики) |
| prometheus-fastapi-instrumentator | 8002 | http://10.1.0.13:8002/metrics | HTTP request count, latency, status codes |

node_exporter systemd unit: `/etc/systemd/system/node_exporter.service`

### 10.2 Dashboards
<!-- TODO: Настроить Grafana dashboard для этого сервера -->

### 10.3 Alerts
<!-- TODO: Настроить алерты -->

### 10.4 Логи
- **Приложение:** `docker logs -f llm-reranker` (json-file driver)
- **node_exporter:** `journalctl -u node_exporter -f`
- **Docker daemon:** `journalctl -u docker -f`
- **Ротация:** Docker json-file (дефолт — без ротации, рекомендуется настроить)

```bash
# Логи приложения
docker logs -f llm-reranker
docker logs --tail=100 llm-reranker

# Логи node_exporter
journalctl -u node_exporter -f

# Логи Docker
journalctl -u docker -f
```

## 11. Deploy Procedure

### 11.1 Обычный деплой (обновление кода)
```bash
cd /opt/unde/llm-reranker
git pull origin main
docker compose build
docker compose up -d
docker compose logs --tail=20
```

### 11.2 Только перезапуск (без изменения кода)
```bash
cd /opt/unde/llm-reranker
docker compose restart
```

### 11.3 Rollback
```bash
cd /opt/unde/llm-reranker
git log --oneline -10          # найти нужный коммит
git checkout <commit-hash>     # откатиться
docker compose build
docker compose up -d
```

## 12. Recovery — Rebuild from Scratch

Полная последовательность для восстановления на чистом сервере Ubuntu 24.04:

### 12.1 Подготовка сервера
```bash
hostnamectl set-hostname llm-reranker
apt-get update && apt-get install -y ca-certificates curl gnupg git
```

### 12.2 Установка Docker
```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 12.3 Установка node_exporter
```bash
useradd --no-create-home --shell /bin/false node_exporter
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz -o /tmp/ne.tar.gz
tar xzf /tmp/ne.tar.gz -C /tmp
cp /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
rm -rf /tmp/ne.tar.gz /tmp/node_exporter-*

cat > /etc/systemd/system/node_exporter.service << 'EOF'
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now node_exporter
```

### 12.4 Клонирование и запуск
```bash
mkdir -p /opt/unde
git clone http://root:glpat-DubSAfGWeEkHd4-D-suZtm86MQp1OjEH.01.0w1eeq22u@gitlab-real.unde.life/unde/llm-reranker.git /opt/unde/llm-reranker
cd /opt/unde/llm-reranker
docker compose build
docker compose up -d
```

### 12.5 Проверка
- [ ] `curl -s http://10.1.0.13:8002/health` → `{"status":"ok"}`
- [ ] `curl -s http://10.1.0.13:8002/metrics | head` → Prometheus metrics
- [ ] `curl -s http://10.1.0.13:9100/metrics | head` → node_exporter metrics
- [ ] `docker compose ps` → llm-reranker running
- [ ] `systemctl status node_exporter` → active (running)

## 13. Application Architecture

### Project file structure
```
/opt/unde/llm-reranker/
├── docker-compose.yml          # Docker Compose (1 service)
├── Dockerfile                  # Python 3.12-slim + pip install
├── .env                        # Gemini API key + server config
├── .env.example                # Template without real secrets
├── requirements.txt            # Python dependencies (6 packages)
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app + Prometheus + /health
│   ├── config.py               # Pydantic Settings from .env
│   ├── gemini_client.py        # Async httpx client → Gemini API
│   └── routes/
│       ├── __init__.py
│       ├── tag.py              # POST /tag — contextual tagging
│       └── rerank.py           # POST /rerank — visual reranking
├── scripts/
│   ├── health-check.sh
│   └── test-tag.sh
└── data/                       # Empty, for future use
```

### Data flow
```
Fashion Pipeline → POST /tag (image URL)
                      ↓
                 Gemini API (analyze clothing → JSON tags)
                      ↓
                 Return {style, occasion, brand_style, season}

Fashion Pipeline → POST /rerank (crop + candidates)
                      ↓
                 Gemini API × N candidates (parallel, asyncio.gather)
                      ↓
                 Score: 0.7×visual + 0.3×semantic
                      ↓
                 Return ranked candidates
```

### HTTP API

| Method | URL | Request | Response | Latency |
|---|---|---|---|---|
| GET | /health | — | `{"status": "ok"}` | <10ms |
| GET | /metrics | — | Prometheus text format | <10ms |
| POST | /tag | `{"url": "image_url"}` | `{"style": "...", "occasion": "...", "brand_style": "...", "season": "..."}` | 5-15s (Gemini) |
| POST | /rerank | `{"crop_url": "...", "candidates": [...], "tags": {...}}` | `{"ranked": [{"sku_id": "...", "score": 0.91, ...}]}` | 5-30s (N × Gemini, parallel) |

## 14. External Dependencies

| Service | Host | Port | Protocol | Auth | Purpose |
|---|---|---|---|---|---|
| Google Gemini API | generativelanguage.googleapis.com | 443 | HTTPS | API Key | LLM vision — tagging & visual comparison |
| GitLab (UNDE) | gitlab-real.unde.life | 80 | HTTP | Token | Code repository + backups |

## 15. Useful Commands

```bash
# Status
docker compose ps
docker compose logs --tail=50
systemctl status node_exporter

# Restart
docker compose restart
systemctl restart node_exporter

# Rebuild & deploy
cd /opt/unde/llm-reranker && git pull && docker compose build && docker compose up -d

# Health checks
curl -s http://10.1.0.13:8002/health
curl -s http://10.1.0.13:8002/metrics | head
curl -s http://10.1.0.13:9100/metrics | head

# Test /tag endpoint
./scripts/test-tag.sh

# View resource usage
docker stats llm-reranker --no-stream
```

## 16. Notes, Quirks & Known Issues

| Issue | Details | Status |
|---|---|---|
| No log rotation | Docker json-file driver без лимитов. Логи будут расти | TODO: настроить max-size в daemon.json |
| No firewall | Firewall будет настраиваться отдельно. node_exporter на 0.0.0.0:9100 открыт | TODO |
| Gemini rate limits | При большом количестве параллельных запросов возможны 429. Retry с exp backoff (max 3) | Handled |
| Kernel update pending | Running 6.8.0-71 but 6.8.0-100 available | Requires reboot |
| No swap | Сервер без swap. При memory pressure OOM killer сработает сразу | By design (Hetzner CX) |

## 17. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial setup | Hostname, Docker 29.2.1, node_exporter 1.8.2, FastAPI app deployed |
| 2026-02-25 | App deployed | llm-reranker container running on 10.1.0.13:8002, /health + /metrics OK |
