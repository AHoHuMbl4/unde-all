# Push Server — Полная конфигурация

> Документация сервера push-уведомлений в инфраструктуре UNDE.  
> Последнее обновление: 2026-01-20

---

## 1. Общая информация

| Параметр | Значение |
|----------|----------|
| **Hostname** | `push` |
| **Назначение** | Push-уведомления (Celery workers + Redis queue) |
| **Провайдер** | Hetzner Cloud |
| **Тип** | CPX32 |
| **Локация** | Helsinki (eu-north) |

---

## 2. Спецификации оборудования

| Ресурс | Значение |
|--------|----------|
| **vCPU** | 4 |
| **RAM** | 7.6 GB (8 GB nominal) |
| **Disk** | 150 GB NVMe (`/dev/sda1`) |
| **Использовано** | ~2.2 GB (2%) |

---

## 3. Операционная система

| Параметр | Значение |
|----------|----------|
| **OS** | Ubuntu 24.04.3 LTS (Noble Numbat) |
| **Kernel** | 6.8.0-90-generic |
| **Architecture** | x86_64 / amd64 |

---

## 4. Сетевые интерфейсы

### 4.1 Интерфейсы

| Интерфейс | IP адрес | Тип | Назначение |
|-----------|----------|-----|------------|
| `eth0` | 77.42.30.44/32 | Public | Доступ из интернета |
| `enp7s0` | 10.1.0.4/32 | Private | Внутренняя сеть UNDE |
| `docker0` | 172.17.0.1/16 | Docker | Default bridge (не используется) |
| `br-5073d4f903bb` | 172.18.0.1/16 | Docker | push-network bridge |

### 4.2 MAC адреса

| Интерфейс | MAC |
|-----------|-----|
| `eth0` | 92:00:07:07:d1:ce |
| `enp7s0` | 86:00:00:81:a6:dc |

---

## 5. Маршрутизация

### 5.1 Таблица маршрутов

| Destination | Gateway | Interface | Назначение |
|-------------|---------|-----------|------------|
| `default` | 172.31.1.1 | eth0 | Интернет |
| `10.0.0.0/24` | 10.1.0.1 | enp7s0 | GitLab network |
| `10.1.0.0/16` | 10.1.0.1 | enp7s0 | Private network (App, DB) |
| `172.17.0.0/16` | — | docker0 | Docker default |
| `172.18.0.0/16` | — | br-* | Docker push-network |

### 5.2 Netplan конфигурация

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

**Применение:** `sudo netplan apply`

---

## 6. Связанные серверы

| Сервер | IP | Порт | Назначение |
|--------|-----|------|------------|
| **App Server** | 10.1.0.2 | — | API Gateway, Prometheus |
| **DB Server** | 10.1.1.2 | 6432 | PostgreSQL через PgBouncer |
| **GitLab** | 10.0.0.3 | 80 | Git репозиторий |
| **Network Gateway** | 10.1.0.1 | — | Роутер приватной сети |

### Проверка связности

```bash
ping -c 1 10.1.0.2   # App Server
ping -c 1 10.1.1.2   # DB Server
ping -c 1 10.0.0.3   # GitLab
nc -zv 10.1.1.2 6432 # PgBouncer
```

---

## 7. Установленное ПО

### 7.1 Docker

| Компонент | Версия |
|-----------|--------|
| Docker Engine | 29.1.5 |
| Docker Compose | 5.0.1 |
| containerd | 2.2.1 |
| Docker Buildx | 0.30.1 |

**Установка:**
```bash
# Official Docker repository
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 7.2 Системные пакеты

- `ca-certificates`
- `curl`
- `netcat-openbsd` (nc)

---

## 8. Docker контейнеры

### 8.1 Запущенные сервисы

| Container | Image | Status | Ports |
|-----------|-------|--------|-------|
| `redis-queue` | redis:7-alpine | Up (healthy) | 10.1.0.4:6379 |
| `node-exporter` | prom/node-exporter:v1.7.0 | Up | 10.1.0.4:9100 |
| `redis-exporter` | oliver006/redis_exporter:v1.55.0 | Up | 10.1.0.4:9121 |

### 8.2 Ожидающие сервисы (profile: push)

| Container | Image | Replicas | Назначение |
|-----------|-------|----------|------------|
| `celery-worker` | ghcr.io/unde/push:latest | 4 | Push task workers |
| `celery-beat` | ghcr.io/unde/push:latest | 1 | Scheduler |

**Запуск Celery (когда image готов):**
```bash
docker compose --profile push up -d
```

### 8.3 Docker networks

| Network | Subnet | Driver |
|---------|--------|--------|
| `1_push-network` | 172.18.0.0/16 | bridge |

### 8.4 Docker volumes

| Volume | Назначение |
|--------|------------|
| `1_redis-data` | Redis persistence (AOF + RDB) |
| `1_celerybeat-schedule` | Celery beat schedule |

---

## 9. Порты и сервисы

### 9.1 Открытые порты (private network)

| Порт | Сервис | Bind IP | Протокол |
|------|--------|---------|----------|
| 6379 | Redis Queue | 10.1.0.4 | TCP |
| 9100 | Node Exporter | 10.1.0.4 | TCP/HTTP |
| 9121 | Redis Exporter | 10.1.0.4 | TCP/HTTP |

### 9.2 Внешние подключения

| Destination | Порт | Протокол | Назначение |
|-------------|------|----------|------------|
| 10.1.1.2 | 6432 | PostgreSQL | База данных |
| 10.0.0.3 | 80 | HTTP | GitLab |
| fcm.googleapis.com | 443 | HTTPS | Firebase (будущее) |
| api.push.apple.com | 443 | HTTPS | APNs (будущее) |

---

## 10. Конфигурационные файлы

### 10.1 Структура репозитория

```
/root/cursor/1/
├── AGENTS.md                 # Agent rules
├── README.md                 # Quick start
├── docker-compose.yml        # Docker services
├── .env                      # Environment (secrets)
├── .env.example              # Environment template
├── .gitignore                # Git ignore rules
├── certs/                    # APNs certificates
│   └── .gitkeep
├── docs/                     # Documentation
│   └── push-server.md        # This file
├── memory-bank/              # Project memory
│   ├── activeContext.md
│   ├── productContext.md
│   ├── progress.md
│   ├── projectBrief.md
│   ├── systemPatterns.md
│   └── techContext.md
├── monitoring/
│   └── prometheus-snippet.yml
├── redis/
│   └── redis-queue.conf
├── scripts/
│   ├── deploy.sh
│   ├── health-check.sh
│   └── setup-network.sh
└── .cursor/rules/
    ├── git-backups.mdc
    └── memory-bank.mdc
```

### 10.2 Redis конфигурация

**Файл:** `redis/redis-queue.conf`

| Параметр | Значение | Описание |
|----------|----------|----------|
| `bind` | 0.0.0.0 | Все интерфейсы |
| `port` | 6379 | Стандартный порт |
| `maxmemory` | 1gb | Лимит памяти |
| `maxmemory-policy` | noeviction | НЕ терять задачи |
| `appendonly` | yes | AOF persistence |
| `appendfsync` | everysec | Fsync каждую секунду |

### 10.3 Environment variables

**Файл:** `.env`

| Variable | Значение | Статус |
|----------|----------|--------|
| `DATABASE_URL` | postgresql://undeuser:***@10.1.1.2:6432/unde_jobs | ✓ Настроен |
| `REDIS_PASSWORD` | kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ= | ✓ Сгенерирован |
| `CELERY_BROKER_URL` | redis://:***@redis-queue:6379/0 | ✓ Настроен |
| `CELERY_RESULT_BACKEND` | redis://:***@redis-queue:6379/1 | ✓ Настроен |
| `FCM_SERVER_KEY` | [KEY] | ⏳ Плейсхолдер |
| `APNS_KEY_ID` | [KEY] | ⏳ Плейсхолдер |
| `APNS_TEAM_ID` | [KEY] | ⏳ Плейсхолдер |
| `APP_ENV` | production | ✓ |
| `LOG_LEVEL` | info | ✓ |

---

## 11. Мониторинг

### 11.1 Prometheus targets

На **App Server** (10.1.0.2) в `/etc/prometheus/prometheus.yml`:

```yaml
- job_name: 'node-push'
  static_configs:
    - targets: ['10.1.0.4:9100']

- job_name: 'redis-push-queue'
  static_configs:
    - targets: ['10.1.0.4:9121']
```

### 11.2 Метрики

| Endpoint | URL | Тип |
|----------|-----|-----|
| Node Exporter | http://10.1.0.4:9100/metrics | Host metrics |
| Redis Exporter | http://10.1.0.4:9121/metrics | Redis metrics |

### 11.3 Health checks

```bash
# Запуск проверки
./scripts/health-check.sh

# Ручные проверки
docker compose ps
docker compose exec redis-queue redis-cli -a $REDIS_PASSWORD ping
curl -s http://10.1.0.4:9100/metrics | head
curl -s http://10.1.0.4:9121/metrics | head
```

---

## 12. Git репозиторий

| Параметр | Значение |
|----------|----------|
| **Remote** | http://10.0.0.3/unde/push.git |
| **Branch** | master |
| **Path** | /root/cursor/1 |

### Git операции

```bash
# Pull
git pull origin master

# Commit (с backup tag)
git add -A
git commit -m "backup: checkpoint YYYY-MM-DD HH:MM - description"
git tag backup/YYYY-MM-DD_HHMM_post
git push origin HEAD
git push origin --tags
```

---

## 13. Команды управления

### 13.1 Docker

```bash
# Статус
docker compose ps

# Логи
docker compose logs -f
docker compose logs -f redis-queue

# Перезапуск
docker compose restart redis-queue

# Остановка
docker compose down

# Запуск с Celery (когда image готов)
docker compose --profile push up -d
```

### 13.2 Сеть

```bash
# Проверить маршруты
ip route show

# Применить netplan
sudo netplan apply

# Тест связности
ping -c 1 10.0.0.3 && echo "GitLab OK"
ping -c 1 10.1.1.2 && echo "DB OK"
ping -c 1 10.1.0.2 && echo "App OK"
```

### 13.3 Система

```bash
# Ресурсы
free -h
df -h
htop

# Docker ресурсы
docker stats
```

---

## 14. Деплой на новом сервере

### Полная последовательность:

```bash
# 1. Clone репозитория
git clone http://10.0.0.3/unde/push.git
cd push

# 2. Настройка сети
sudo ./scripts/setup-network.sh

# 3. Установка Docker (если не установлен)
curl -fsSL https://get.docker.com | sh

# 4. Копирование .env
cp .env.example .env
# Отредактировать если нужно

# 5. APNs сертификат (когда будет)
cp /path/to/apns.p8 certs/

# 6. Запуск инфраструктуры
docker compose up -d

# 7. Запуск Celery (когда image готов)
docker compose --profile push up -d

# 8. Проверка
./scripts/health-check.sh
```

---

## 15. Troubleshooting

### Redis не отвечает

```bash
docker compose logs redis-queue
docker compose restart redis-queue
```

### Нет связи с DB Server

```bash
ping 10.1.1.2
nc -zv 10.1.1.2 6432
ip route show | grep 10.1
# Если маршрута нет:
sudo ip route add 10.1.0.0/16 via 10.1.0.1
```

### Exporters не отдают метрики

```bash
curl -v http://10.1.0.4:9100/metrics
docker compose logs node-exporter
docker compose restart node-exporter redis-exporter
```

### Git push не работает

```bash
ping 10.0.0.3
# Использовать токен:
git push "http://oauth2:$GITLAB_TOKEN@10.0.0.3/unde/push.git" HEAD:master
```

---

## 16. Контакты и ресурсы

| Ресурс | URL |
|--------|-----|
| GitLab | http://10.0.0.3/unde/push |
| Prometheus (App Server) | http://10.1.0.2:9090 |
| Memory Bank | `/root/cursor/1/memory-bank/` |

---

*Документ создан автоматически. Для обновления — отредактируйте и запушьте в GitLab.*
