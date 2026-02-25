# Server: ximilar-gw
<!-- Этот файл — полная карта сервера. Обновляй при ЛЮБЫХ инфра-изменениях. -->

## Назначение

**ximilar-gw** — выделенный HTTP-шлюз (gateway) к Ximilar API в составе **UNDE Fashion Recognition Pipeline**.

Пользователь фотографирует outfit → App Server → Celery task → Recognition Orchestrator (10.1.0.14) →
последовательно вызывает ximilar-gw по HTTP:

1. `POST /detect` — найти все предметы одежды на фото
2. `POST /tag` — определить атрибуты каждого предмета (цвет, материал, паттерн)
3. `POST /search` — найти похожие SKU в каталоге магазинов

ximilar-gw — **единственный** сервер с Ximilar API ключом. Не обрабатывает изображения, не хранит данные — чистый JSON-прокси с retry-логикой.

```
Recognition Orchestrator (10.1.0.14)
        │
        ▼  HTTP (private network)
┌─────────────────────────────────┐
│  ximilar-gw  (10.1.0.12:8001)  │
│  FastAPI, 4 uvicorn workers     │
│  Docker container, 2 GB limit   │
└───────────────┬─────────────────┘
                │  HTTPS
                ▼
        Ximilar API (api.ximilar.com)
        - /recognition/v2/detect
        - /recognition/v2/classify
        - /recognition/v2/visualSearch
```

---

## Identity

- **Name:** ximilar-gw
- **Role:** HTTP gateway to Ximilar API for Fashion Recognition Pipeline
- **Provider:** Hetzner Cloud
- **Plan/Model:** CX23 (shared vCPU)
- **Location:** <!-- TODO: datacenter location -->

---

## Hardware

- **CPU:** AMD EPYC-Rome, 2 vCPU, 1 thread/core, 2.0 GHz
- **CPU cache:** L1d 64 KiB (×2), L1i 64 KiB (×2), L2 1 MiB (×2), L3 16 MiB
- **RAM:** 4 GB (нет swap)
- **Storage:** SSD 40 GB (ext4), использовано ~2.5 GB (7%)
- **Network:** <!-- TODO: bandwidth -->

---

## Network

- **Public IP:** 89.167.99.162 (eth0, /32)
- **Private IP:** 10.1.0.12 (enp7s0, /32, Hetzner private network, MTU 1450)
- **Domain/DNS:** нет (доступ только по IP из private сети)
- **Firewall rules:** НЕ настроен (управляется отдельно)
- **SSH access:** порт 22, пользователь root

### Interfaces

| Interface | IP               | MTU  | Назначение                    |
|-----------|------------------|------|-------------------------------|
| eth0      | 89.167.99.162/32 | 1500 | Public internet (Hetzner)     |
| enp7s0    | 10.1.0.12/32     | 1450 | Private network (UNDE infra)  |
| docker0   | 172.17.0.1/16    | 1500 | Docker default bridge (unused)|
| br-1329…  | 172.18.0.1/16    | 1500 | ximilar-gw_default network    |

### Routing

| Destination   | Via        | Interface | Описание                |
|---------------|------------|-----------|-------------------------|
| default       | 172.31.1.1 | eth0      | Internet через Hetzner  |
| 10.1.0.0/16   | 10.1.0.1   | enp7s0    | Private сеть UNDE       |
| 172.17.0.0/16 | direct     | docker0   | Docker default bridge   |
| 172.18.0.0/16 | direct     | br-1329…  | Docker compose network  |

### DNS

- systemd-resolved → 185.12.64.1, 185.12.64.2 (Hetzner DNS)

### Listening Ports

| Port | Bind          | Процесс        | Протокол | Описание                              |
|------|---------------|-----------------|----------|---------------------------------------|
| 22   | 0.0.0.0 + [::]| sshd            | TCP      | SSH доступ                            |
| 8001 | 10.1.0.12     | docker-proxy    | TCP/HTTP | ximilar-gw (только private network!) |
| 9100 | 0.0.0.0 + [::]| node_exporter   | TCP/HTTP | Prometheus system metrics             |

### Network Topology

```
                      Public Internet
                            │
                    89.167.99.162 (eth0)
                            │
                ┌───────────┴───────────┐
                │      ximilar-gw       │
                │  :22   SSH            │
                │  :9100 node_exporter  │
                │  :8001 FastAPI ←──────│── привязан к 10.1.0.12 only
                └───────────┬───────────┘
                            │
                     10.1.0.12 (enp7s0)
                            │
            ┌───────────────┼──────────────────────┐
            │        Private Network 10.1.0.0/16    │
            │  10.1.0.14  Recognition Orchestrator  │ → POST :8001/*
            │  10.1.0.xx  Monitoring (Prometheus)   │ → scrape :8001/metrics, :9100/metrics
            │  ...        другие серверы UNDE        │
            └───────────────────────────────────────┘
```

---

## OS & base setup

- **OS:** Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel:** 6.8.0-90-generic (x86_64, PREEMPT_DYNAMIC)
- **Hostname:** ximilar-gw
- **Timezone:** UTC (Etc/UTC)
- **NTP:** systemd-timesyncd, clock synchronized
- **Init system:** systemd 255
- **Docker version:** 29.2.1
- **Docker Compose version:** 5.0.2
- **containerd:** 2.2.1

### Installed Software

| Component                | Version | Как установлен                      | Бинарь / Unit                    | Статус  |
|--------------------------|---------|-------------------------------------|----------------------------------|---------|
| Docker Engine            | 29.2.1  | apt: docker-ce                      | `dockerd`, docker.service        | running |
| containerd               | 2.2.1   | apt: containerd.io                  | `containerd`, containerd.service | running |
| Docker Compose           | 5.0.2   | apt: docker-compose-plugin          | `docker compose` (plugin)        | —       |
| Docker Buildx            | —       | apt: docker-buildx-plugin           | `docker buildx` (plugin)         | —       |
| node_exporter            | 1.8.2   | binary с GitHub + systemd unit      | `/usr/local/bin/node_exporter`   | running |
| OpenSSH Server           | 9.6p1   | apt: openssh-server (предустановлен)| `sshd`, ssh.service              | running |
| Python                   | 3.12.3  | system (Ubuntu 24.04 default)       | `/usr/bin/python3`               | —       |
| Git                      | 2.43.0  | apt: git (предустановлен)           | `/usr/bin/git`                   | —       |
| curl                     | 8.5.0   | apt: curl                           | `/usr/bin/curl`                  | —       |

### Python-пакеты внутри Docker-контейнера

| Package                            | Version | Назначение                                   |
|------------------------------------|---------|----------------------------------------------|
| fastapi                           | 0.115.6 | HTTP framework (async, Pydantic валидация)    |
| uvicorn                           | 0.34.0  | ASGI сервер, 4 worker-процесса               |
| httpx                             | 0.28.1  | Async HTTP клиент для вызовов к Ximilar API   |
| pydantic-settings                 | 2.7.1   | Загрузка конфига из .env файла                |
| pydantic                          | 2.12.5  | Валидация данных (request/response models)     |
| prometheus-fastapi-instrumentator | 7.0.2   | Автоматические Prometheus метрики для FastAPI  |

### Systemd services (running)

| Service                      | Описание                             |
|------------------------------|--------------------------------------|
| docker.service               | Docker Engine daemon                 |
| containerd.service           | Container runtime                    |
| node_exporter.service        | Prometheus node metrics (:9100)      |
| ssh.service                  | OpenSSH server                       |
| systemd-networkd.service     | Network configuration                |
| systemd-resolved.service     | DNS resolution                       |
| systemd-timesyncd.service    | NTP time sync                        |
| qemu-guest-agent.service     | Hetzner Cloud guest agent            |
| unattended-upgrades.service  | Автоматические security-обновления   |

---

## Running containers & services

| Container/Service | Port(s)        | Image/Build                         | Purpose                       | Status  |
|-------------------|----------------|-------------------------------------|-------------------------------|---------|
| ximilar-gw       | 10.1.0.12:8001 | ximilar-gw-ximilar-gw:latest (~216 MB, local build) | FastAPI Ximilar API gateway | running |
| node_exporter    | 0.0.0.0:9100   | binary (systemd)                    | Prometheus system metrics     | running |

---

## Docker details

### Container: ximilar-gw

| Параметр         | Значение                                                       |
|------------------|----------------------------------------------------------------|
| **Name**         | ximilar-gw                                                     |
| **Image**        | ximilar-gw-ximilar-gw:latest (~216 MB, local build)           |
| **Base image**   | python:3.12-slim                                               |
| **Command**      | `uvicorn app.main:app --host 0.0.0.0 --port 8001 --workers 4` |
| **Ports**        | 10.1.0.12:8001 → container:8001                               |
| **Memory limit** | 2 GB                                                           |
| **Restart**      | unless-stopped                                                 |
| **Env file**     | .env                                                           |
| **Network**      | ximilar-gw_default (bridge, 172.18.0.0/16)                    |

### Docker Compose file

Файл: `/opt/unde/ximilar-gw/docker-compose.yml`

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

### Dockerfile

Файл: `/opt/unde/ximilar-gw/Dockerfile`

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/ ./app/
EXPOSE 8001
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "4"]
```

### Docker Networks

| Network            | Driver | Subnet        | Используется          |
|--------------------|--------|---------------|-----------------------|
| ximilar-gw_default | bridge | 172.18.0.0/16 | контейнер ximilar-gw  |
| bridge             | bridge | 172.17.0.0/16 | default (не используется) |

---

## Volumes & persistent data

| Volume/Path | Mount point | Content | Backup? |
|---|---|---|---|
| нет | — | Stateless сервис, данных на диске нет | — |

---

## Application Architecture

### Как работает

ximilar-gw — **тонкая HTTP-обёртка** над Ximilar REST API:

1. Принимает JSON-запрос от Recognition Orchestrator (10.1.0.14)
2. Формирует запрос к Ximilar API, добавляя `Authorization: Token` header
3. Отправляет в Ximilar, ждёт ответ (timeout 30s)
4. Если 429 (rate limit) — retry с exponential backoff (до 3 раз)
5. Парсит ответ Ximilar → преобразует в упрощённый формат
6. Возвращает результат вызывающей стороне

### Внутренняя архитектура

```
HTTP Request ──→ FastAPI Router ──→ ximilar_client.ximilar_request() ──→ Ximilar API
                   │                         │
                   │ Pydantic models          │ httpx.AsyncClient
                   │ (валидация in/out)       │ Auth header
                   │                          │ Retry on 429
                   ▼                          │ Exp. backoff
HTTP Response ←── Pydantic → JSON            │ 30s timeout
                                              │
                 Prometheus /metrics           │
                 (auto-instrumented)           ▼
                                        Ximilar REST API
```

### Project Structure

```
/opt/unde/ximilar-gw/
├── docker-compose.yml          # Определение Docker сервиса
├── Dockerfile                  # Сборка образа (python:3.12-slim)
├── .env                        # Конфигурация (API токены, порт, workers)
├── .env.example                # Шаблон .env
├── requirements.txt            # Python зависимости (5 пакетов)
│
├── app/
│   ├── __init__.py
│   ├── main.py                 # FastAPI app:
│   │                           #   - Prometheus instrumentation
│   │                           #   - подключение роутеров detect/tag/search
│   │                           #   - GET /health
│   │                           #   - shutdown hook (закрытие httpx)
│   │
│   ├── config.py               # Pydantic Settings:
│   │                           #   - загрузка из .env
│   │                           #   - XIMILAR_API_TOKEN, COLLECTION_ID, API_URL,
│   │                           #     HOST, PORT, WORKERS
│   │
│   ├── ximilar_client.py       # HTTP-клиент к Ximilar:
│   │                           #   - singleton httpx.AsyncClient
│   │                           #   - Authorization: Token header
│   │                           #   - retry на 429 (exp backoff, max 3)
│   │                           #   - timeout 30s
│   │                           #   - check_ximilar_reachable() для /health
│   │
│   └── routes/
│       ├── __init__.py
│       ├── detect.py           # POST /detect → Ximilar /recognition/v2/detect
│       ├── tag.py              # POST /tag    → Ximilar /recognition/v2/classify
│       └── search.py           # POST /search → Ximilar /recognition/v2/visualSearch
│
├── scripts/
│   ├── health-check.sh         # curl health endpoint
│   └── test-detect.sh          # тестовый вызов /detect
│
└── data/                       # Зарезервировано (пусто)
```

### Ключевые решения

| Решение | Почему | Последствия |
|---------|--------|-------------|
| httpx async (не requests sync) | FastAPI async, нативная поддержка | Лучшая concurrency, нет thread pool |
| Один контейнер, без reverse proxy | Внутренний сервис, private сеть, SSL не нужен | Проще деплой |
| Bind на 10.1.0.12 only | Только для private сети | Недоступен из интернета |
| 4 uvicorn workers | 2 vCPU, параллельная обработка | Несколько запросов одновременно |
| Memory limit 2 GB | Лёгкий JSON-прокси, оставить RAM для ОС | OOM-kill при утечке |
| Retry на 429, exp backoff | Ximilar rate limit | Автоматическое восстановление |

---

## HTTP API

### POST /detect — Найти предметы одежды на фото

**Ximilar API:** `POST /recognition/v2/detect`

```bash
curl -X POST http://10.1.0.12:8001/detect \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/outfit-photo.jpg"}'
```

Ответ:
```json
{
  "items": [
    {"crop_url": "https://cdn.ximilar.com/crops/abc.jpg", "bbox": [120,50,380,420], "category": "jacket", "confidence": 0.94},
    {"crop_url": "https://cdn.ximilar.com/crops/def.jpg", "bbox": [100,400,350,750], "category": "jeans", "confidence": 0.91}
  ]
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| crop_url | string | URL обрезанного изображения вещи |
| bbox | array | Bounding box [x1, y1, x2, y2] |
| category | string | Категория (jacket, jeans, shoes…) |
| confidence | float | Уверенность 0.0–1.0 |

Latency: 200–500ms

### POST /tag — Атрибуты предмета одежды

**Ximilar API:** `POST /recognition/v2/classify`

```bash
curl -X POST http://10.1.0.12:8001/tag \
  -H "Content-Type: application/json" \
  -d '{"url": "https://cdn.ximilar.com/crops/abc.jpg"}'
```

Ответ:
```json
{
  "type": "bomber_jacket",
  "color": "khaki",
  "color_hex": "#BDB76B",
  "material": "nylon ripstop",
  "pattern": "solid"
}
```

Latency: 200–400ms

### POST /search — Поиск похожих SKU

**Ximilar API:** `POST /recognition/v2/visualSearch`

```bash
curl -X POST http://10.1.0.12:8001/search \
  -H "Content-Type: application/json" \
  -d '{"crop_url": "https://cdn.ximilar.com/crops/abc.jpg", "category": "jacket", "top_k": 10}'
```

Ответ:
```json
{
  "candidates": [
    {
      "sku_id": "sku_8f3a2c",
      "score": 0.87,
      "image_urls": ["https://store.example.com/img/jacket-1.jpg"],
      "metadata": {"brand": "Nike", "price": 129.99, "store": "Mall of Dubai", "floor": "2F"}
    }
  ]
}
```

Latency: 200–500ms

### GET /health — Проверка работоспособности

```bash
curl http://10.1.0.12:8001/health
```

Ответ: `{"status": "ok", "ximilar_reachable": true}`

### GET /metrics — Prometheus метрики

```bash
curl http://10.1.0.12:8001/metrics
```

Метрики: `http_request_duration_seconds` (histogram), `http_requests_total` (counter), `http_requests_in_progress` (gauge), стандартные Python/process метрики.

---

## External Dependencies

### Ximilar API

| Параметр       | Значение                                   |
|----------------|--------------------------------------------|
| Base URL       | https://api.ximilar.com                    |
| Auth           | `Authorization: Token {XIMILAR_API_TOKEN}` |
| Rate limits    | Business tier                              |
| Retry policy   | Exp backoff на 429, max 3 retries          |
| Timeout        | 30s на запрос                              |

| Наш endpoint | Ximilar endpoint                  | Тело запроса к Ximilar                                           |
|--------------|-----------------------------------|------------------------------------------------------------------|
| POST /detect | POST /recognition/v2/detect       | `{"records": [{"_url": "..."}]}`                                 |
| POST /tag    | POST /recognition/v2/classify     | `{"records": [{"_url": "..."}]}`                                 |
| POST /search | POST /recognition/v2/visualSearch | `{"records": [{"_url": "..."}], "collection_id": "...", "k": N}` |

### Recognition Orchestrator

| Параметр | Значение |
|----------|----------|
| IP       | 10.1.0.14 |
| Роль     | Единственный клиент ximilar-gw |
| Вызовы   | POST /detect → /tag → /search (последовательно) |
| Сеть     | Private network 10.1.0.0/16 |

---

## Environment & secrets

Файл: `/opt/unde/ximilar-gw/.env`

```env
XIMILAR_API_TOKEN=xxx
XIMILAR_COLLECTION_ID=xxx
XIMILAR_API_URL=https://api.ximilar.com
HOST=0.0.0.0
PORT=8001
WORKERS=4
```

| Variable              | Обязательна | Описание                              | Текущее значение         |
|-----------------------|-------------|----------------------------------------|--------------------------|
| XIMILAR_API_TOKEN     | **Да**      | Токен аутентификации Ximilar API       | `xxx` (**заполнить!**)   |
| XIMILAR_COLLECTION_ID | **Да**      | ID коллекции для visual search         | `xxx` (**заполнить!**)   |
| XIMILAR_API_URL       | Нет         | Base URL Ximilar API                   | https://api.ximilar.com |
| HOST                  | Нет         | Bind host uvicorn внутри контейнера    | 0.0.0.0                  |
| PORT                  | Нет         | Bind port uvicorn внутри контейнера    | 8001                     |
| WORKERS               | Нет         | Количество uvicorn worker-процессов    | 4                        |

---

## Networking & routing

- **Reverse proxy:** нет (прямой доступ)
- **SSL:** нет (внутренний сервис, private сеть)

| Route          | → Target                | Notes                          |
|----------------|-------------------------|--------------------------------|
| 10.1.0.12:8001 | ximilar-gw container    | Docker port mapping (private!) |
| 0.0.0.0:9100   | node_exporter           | System metrics (all interfaces)|

---

## Database(s) on this server

Нет. Сервис stateless — не хранит данные.

---

## Monitoring & logs

### Application Metrics
- **URL:** http://10.1.0.12:8001/metrics
- **Формат:** Prometheus
- **Библиотека:** prometheus-fastapi-instrumentator 7.0.2
- **Содержит:** latency histogram по endpoint, request count по status code, in-progress gauge

### System Metrics
- **URL:** http://10.1.0.12:9100/metrics
- **Формат:** Prometheus
- **Источник:** node_exporter 1.8.2
- **Содержит:** CPU, RAM, disk I/O, disk space, network traffic, load average, uptime

### Логи
```bash
# Логи приложения
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml logs -f
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml logs --tail=100

# node_exporter
journalctl -u node_exporter -f

# Docker daemon
journalctl -u docker -f
```

### Alerts
<!-- TODO: настроить в Prometheus/Alertmanager -->

---

## node_exporter

### Установка
```bash
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz \
  -o /tmp/node_exporter.tar.gz
tar xzf /tmp/node_exporter.tar.gz -C /tmp/
mv /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
useradd --no-create-home --shell /bin/false node_exporter
```

### systemd unit

Файл: `/etc/systemd/system/node_exporter.service`

```ini
[Unit]
Description=Prometheus Node Exporter
Documentation=https://prometheus.io/docs/guides/node-exporter/
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --web.listen-address=0.0.0.0:9100
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### Управление
```bash
systemctl status node_exporter
systemctl restart node_exporter
journalctl -u node_exporter -f
curl localhost:9100/metrics | head
```

---

## Deploy procedure

```bash
ssh root@10.1.0.12
cd /opt/unde/ximilar-gw
git pull
docker compose build
docker compose up -d
docker compose ps
curl http://10.1.0.12:8001/health
```

---

## Recovery / rebuild from scratch

Полное восстановление с нуля (~5 минут):

```bash
# 1. Docker
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 2. node_exporter
curl -fsSL https://github.com/prometheus/node_exporter/releases/download/v1.8.2/node_exporter-1.8.2.linux-amd64.tar.gz \
  -o /tmp/node_exporter.tar.gz
tar xzf /tmp/node_exporter.tar.gz -C /tmp/
mv /tmp/node_exporter-1.8.2.linux-amd64/node_exporter /usr/local/bin/
chmod +x /usr/local/bin/node_exporter
useradd --no-create-home --shell /bin/false node_exporter
# Создать /etc/systemd/system/node_exporter.service (см. секцию выше)
systemctl daemon-reload && systemctl enable --now node_exporter

# 3. Приложение
mkdir -p /opt/unde
git clone http://root:<TOKEN>@gitlab-real.unde.life/unde/ximilar-gw.git /opt/unde/ximilar-gw
cd /opt/unde/ximilar-gw

# 4. Заполнить .env реальными XIMILAR_API_TOKEN и XIMILAR_COLLECTION_ID
nano .env

# 5. Build + start
docker compose build
docker compose up -d

# 6. Verify
docker compose ps
curl http://10.1.0.12:8001/health
curl localhost:9100/metrics | head
```

---

## Useful Commands

```bash
# === ПРИЛОЖЕНИЕ ===
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml ps          # статус
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml logs -f      # логи
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml restart      # перезапуск
docker compose -f /opt/unde/ximilar-gw/docker-compose.yml down         # остановка
cd /opt/unde/ximilar-gw && docker compose build && docker compose up -d # rebuild
docker exec -it ximilar-gw bash                                        # shell в контейнер
docker stats ximilar-gw --no-stream                                    # CPU/RAM usage

# === ПРОВЕРКИ ===
curl -s http://10.1.0.12:8001/health | python3 -m json.tool
curl -s http://10.1.0.12:8001/metrics | grep http_request
curl -s localhost:9100/metrics | head

# === СИСТЕМА ===
ss -tlnp                          # listening ports
free -h                           # RAM
df -h /                           # disk
uptime                            # load average
systemctl status node_exporter    # node_exporter
```

---

## Notes & quirks

| # | Проблема | Статус | Описание |
|---|----------|--------|----------|
| 1 | XIMILAR_API_TOKEN = xxx | **Заполнить!** | Без токена /detect, /tag, /search → 502 |
| 2 | XIMILAR_COLLECTION_ID = xxx | **Заполнить!** | Без ID коллекции /search не работает |
| 3 | node_exporter на 0.0.0.0 | Ждёт firewall | :9100 доступен из интернета |
| 4 | Нет caching | Backlog | Повторные запросы не кешируются |
| 5 | Нет auth на входе | By design | Полагаемся на private network |
| 6 | Нет XIMILAR_TASK_ID | Уточнить | Для /tag может потребоваться task_id |

---

## Changelog

| Date       | Change        | Details                                                          |
|------------|---------------|------------------------------------------------------------------|
| 2026-02-24 | Initial setup | Docker 29.2.1, Compose 5.0.2, node_exporter 1.8.2, FastAPI app  |
