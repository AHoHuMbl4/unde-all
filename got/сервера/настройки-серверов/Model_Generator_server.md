# Model Generator Server Setup

Полная документация по настройке и работе сервера model-generator.

## Информация о сервере

| Параметр | Значение |
|----------|----------|
| **Hostname** | model-generator |
| **Public IP** | 89.167.20.60 |
| **Private IP** | 10.1.0.5 |
| **OS** | Ubuntu 24.04.3 LTS (Noble Numbat) |
| **Kernel** | 6.8.0-90-generic |
| **CPU** | 3 vCPU (CPX22) |
| **RAM** | 4 GB |
| **Disk** | 80 GB NVMe |
| **Provider** | Hetzner Cloud |

## Роль в инфраструктуре UNDE

```
                    ┌─────────────────┐
                    │   App Server    │
                    │   10.1.0.2      │
                    │   (API, Nginx)  │
                    └────────┬────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│  Push Server  │   │model-generator│   │ tryon-service │
│   10.1.0.4    │   │   10.1.0.5    │   │   10.1.0.6    │
│ Redis Queue   │   │  ◀── ЭТО МЫ  │   │  (другой)     │
│ Celery broker │   │               │   │               │
└───────────────┘   └───────────────┘   └───────────────┘
        │                    │                    │
        └────────────────────┼────────────────────┘
                             │
                    ┌────────▼────────┐
                    │   DB Server     │
                    │   10.1.1.2      │
                    │   PostgreSQL    │
                    └─────────────────┘
```

**Назначение:** Batch-генерация библиотеки AI-моделей (аватаров) через fal.ai API для демонстрации одежды в приложении UNDE.

## Текущий статус

| Компонент | Статус | Примечание |
|-----------|--------|------------|
| Docker | ✅ Установлен | v29.2.0 |
| generator-worker-1 | ✅ Healthy | Celery worker |
| generator-worker-2 | ✅ Healthy | Celery worker |
| node-exporter | ✅ Running | Метрики на 10.1.0.5:9100 |
| Redis connection | ✅ Connected | 10.1.0.4:6379 |
| fal.ai API | ✅ Working | Endpoint: fal-ai/flux/dev |
| Systemd service | ✅ Enabled | Автозапуск при boot |
| Private network | ✅ Configured | 10.1.0.0/16 |

## Установленное ПО

### Системные пакеты
- Docker CE 29.2.0
- Docker Compose Plugin 5.0.2
- Docker Buildx Plugin 0.30.1
- curl, wget, git, htop, vim, jq

### Docker образы
- `model-generator-generator-worker-1` — Python 3.12 + Celery worker
- `model-generator-generator-worker-2` — Python 3.12 + Celery worker  
- `prom/node-exporter:v1.7.0` — Prometheus metrics exporter

### Python зависимости (в контейнерах)
- celery==5.3.6
- redis==5.0.1
- kombu==5.3.4
- fal-client==0.4.1
- sqlalchemy==2.0.25
- psycopg2-binary==2.9.9
- python-dotenv==1.0.0

## Структура файлов на сервере

```
/opt/unde/model-generator/
├── docker-compose.yml          # Docker Compose конфигурация
├── Dockerfile                  # Образ для workers
├── .env                        # Credentials (chmod 600, НЕ в git)
├── .env.example                # Шаблон credentials
├── requirements.txt            # Python зависимости
├── app/
│   ├── __init__.py
│   ├── celery_app.py          # Celery конфигурация
│   ├── tasks.py               # Celery tasks
│   ├── fal_client.py          # fal.ai API wrapper
│   └── models.py              # SQLAlchemy модели
├── scripts/
│   ├── health-check.sh        # Проверка здоровья
│   ├── generate-batch.sh      # Batch генерация
│   └── test-task.sh           # Тестовый task
├── deploy/
│   ├── setup-server.sh        # Скрипт установки
│   ├── netplan-private.yaml   # Конфиг сети
│   └── model-generator.service # Systemd unit
├── docs/
│   ├── README.md              # Основная документация
│   └── SERVER_SETUP.md        # Этот файл
├── memory-bank/               # Project memory
└── .cursor/rules/             # Cursor agent rules

/etc/systemd/system/
└── model-generator.service    # Systemd unit (копия)

~/.git-credentials             # Git credentials для GitLab
```

## Сетевая конфигурация

### Private Network (Hetzner vSwitch)

Файл: `/etc/netplan/60-private-network.yaml`
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

### Доступные хосты
| Хост | IP | Порт | Назначение |
|------|-----|------|------------|
| Redis (Push Server) | 10.1.0.4 | 6379 | Celery broker |
| PostgreSQL (DB Server) | 10.1.1.2 | 6432 | База данных (через PgBouncer) |
| App Server | 10.1.0.2 | - | API сервер |
| GitLab | 10.0.0.3 | 80 | Репозиторий |

### Открытые порты
| Порт | Bind | Назначение |
|------|------|------------|
| 22 | 0.0.0.0 | SSH |
| 9100 | 10.1.0.5 | Node Exporter (только private) |

## Docker Compose конфигурация

```yaml
services:
  generator-worker-1:
    image: model-generator-generator-worker-1
    container_name: generator-worker-1
    restart: unless-stopped
    env_file: .env
    resources:
      limits: { memory: 1536M }
      reservations: { memory: 512M }
    stop_grace_period: 120s

  generator-worker-2:
    image: model-generator-generator-worker-2
    container_name: generator-worker-2
    restart: unless-stopped
    env_file: .env
    resources:
      limits: { memory: 1536M }
      reservations: { memory: 512M }
    stop_grace_period: 120s

  node-exporter:
    image: prom/node-exporter:v1.7.0
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "10.1.0.5:9100:9100"
    volumes:
      - '/:/host:ro,rslave'
```

## Celery конфигурация

### Queues
| Queue | Exchange | Routing Key |
|-------|----------|-------------|
| generator_queue | generator_queue | generator_queue |

### Worker настройки
| Параметр | Значение | Причина |
|----------|----------|---------|
| concurrency | 1 | fal.ai rate limits |
| max-tasks-per-child | 50 | Предотвращение memory leaks |
| prefetch_multiplier | 1 | Один task за раз |
| task_time_limit | 300s | Max 5 минут на task |
| task_soft_time_limit | 240s | Soft limit 4 минуты |

### Доступные tasks
| Task | Описание |
|------|----------|
| `generate_model` | Генерация одной AI-модели |
| `batch_generate` | Batch-генерация нескольких моделей |
| `edit_model` | Редактирование существующей модели |
| `health_check` | Проверка здоровья worker'а |

## Credentials (переменные окружения)

Файл: `/opt/unde/model-generator/.env` (chmod 600)

| Переменная | Назначение |
|------------|------------|
| `FAL_KEY` | API ключ fal.ai |
| `REDIS_PASSWORD` | Пароль Redis |
| `CELERY_BROKER_URL` | URL брокера (redis://...@10.1.0.4:6379/4) |
| `CELERY_RESULT_BACKEND` | URL backend (redis://...@10.1.0.4:6379/5) |
| `DATABASE_URL` | PostgreSQL connection string |

**ВАЖНО:** Credentials НЕ хранятся в git репозитории!

## Systemd сервис

Файл: `/etc/systemd/system/model-generator.service`

```ini
[Unit]
Description=Model Generator - AI Model Library Generator
After=docker.service network-online.target
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/unde/model-generator
ExecStart=/usr/bin/docker compose up -d --remove-orphans
ExecStop=/usr/bin/docker compose down --timeout 120
ExecReload=/usr/bin/docker compose restart

[Install]
WantedBy=multi-user.target
```

### Команды управления
```bash
# Статус
systemctl status model-generator

# Запуск
systemctl start model-generator

# Остановка
systemctl stop model-generator

# Перезапуск
systemctl restart model-generator

# Логи
journalctl -u model-generator -f
```

## Мониторинг

### Node Exporter
- **URL:** http://10.1.0.5:9100/metrics
- **Scrape interval:** 15s (настроено на Prometheus App Server)

### Метрики
- CPU usage
- Memory usage
- Disk I/O
- Network traffic
- Filesystem usage

### Проверка здоровья
```bash
# Полная проверка
/opt/unde/model-generator/scripts/health-check.sh

# Docker статус
docker compose ps

# Celery workers
docker compose exec generator-worker-1 celery -A app.celery_app inspect ping
```

## Как работает генерация

### Процесс генерации модели

```
1. App Server ставит задачу в Redis queue (generator_queue)
                    │
                    ▼
2. Celery worker забирает задачу из queue
                    │
                    ▼
3. Worker вызывает fal.ai API (fal-ai/flux/dev)
   - Формирует prompt из параметров
   - Отправляет запрос на генерацию
                    │
                    ▼
4. fal.ai возвращает URL сгенерированного изображения
                    │
                    ▼
5. Worker сохраняет результат в PostgreSQL (model_library)
   - image_url
   - metadata (gender, pose, style, etc.)
   - processing_time
                    │
                    ▼
6. Результат возвращается через Redis result backend
```

### Параметры генерации

| Параметр | Значения | Описание |
|----------|----------|----------|
| gender | male, female | Пол модели |
| age_range | 20-30, 30-40, 40-50 | Возрастной диапазон |
| body_type | slim, average, athletic, plus-size | Телосложение |
| pose | front standing, side, walking, sitting | Поза |
| style | professional, casual, editorial | Стиль съёмки |

### Пример prompt
```
Fashion model, female, 25-35 years old, body type: average, 
pose: front standing, style: professional photo, full body shot, 
neutral white/gray background, professional studio lighting, 
high quality, 8k, detailed, clean composition
```

## База данных

### Таблица model_library

```sql
CREATE TABLE model_library (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id VARCHAR(100) NOT NULL,
    version INTEGER DEFAULT 1,
    image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    gender VARCHAR(20),
    age_range VARCHAR(20),
    body_type VARCHAR(20),
    pose VARCHAR(50),
    style VARCHAR(50),
    prompt TEXT,
    metadata JSONB,
    fal_request_id VARCHAR(100),
    processing_time_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(template_id, version)
);

CREATE INDEX idx_model_library_gender ON model_library(gender);
CREATE INDEX idx_model_library_style ON model_library(style);
```

**Статус:** Таблица НЕ создана. Требуется выполнить SQL на DB Server.

## Git репозиторий

| Параметр | Значение |
|----------|----------|
| URL | http://gitlab-real.unde.life/unde/model-generator |
| Branch | master |
| Commits | 3 |

### История коммитов
| Дата | Сообщение |
|------|-----------|
| 2026-01-28 | backup: baseline - add memory bank and rules |
| 2026-01-28 | backup: checkpoint - full project structure |
| 2026-01-28 | fix: correct fal.ai endpoint and SQLAlchemy model |

### Tags
- `backup/2026-01-28_1330_baseline`
- `backup/2026-01-28_1335_pre`
- `backup/2026-01-28_1340_post`
- `backup/2026-01-28_1410_post`

## Тестирование

### Результаты тестов (2026-01-28)

| Тест | Статус | Время |
|------|--------|-------|
| Health check task | ✅ Pass | <1s |
| Model generation | ✅ Pass | ~2000ms |
| Redis connection | ✅ Pass | - |
| Node exporter | ✅ Pass | - |

### Команды тестирования
```bash
# Health check
docker compose exec generator-worker-1 python3 -c "
from app.tasks import health_check
result = health_check.delay()
print(result.get(timeout=30))
"

# Генерация (без сохранения в БД)
/opt/unde/model-generator/scripts/test-task.sh --no-save

# Batch генерация (dry run)
/opt/unde/model-generator/scripts/generate-batch.sh --count 5 --dry-run
```

## Развёртывание на новом сервере

### Быстрый способ
```bash
# На новом сервере Ubuntu 24.04
curl -sSL http://gitlab-real.unde.life/unde/model-generator/-/raw/master/deploy/setup-server.sh | sudo bash

# Затем создать .env
cp /opt/unde/model-generator/.env.example /opt/unde/model-generator/.env
vim /opt/unde/model-generator/.env  # Заполнить credentials

# Запустить
systemctl start model-generator
```

### Ручной способ
1. Установить Docker
2. Клонировать репозиторий
3. Создать .env с credentials
4. `docker compose up -d`
5. Установить systemd service

## Известные ограничения

1. **fal.ai rate limits** — concurrency=1 на worker
2. **RAM 4GB** — максимум 2 workers
3. **Нет таблицы в БД** — сохранение отключено до создания
4. **Нет автоматических тестов** — только ручное тестирование
5. **Нет retry backoff** — фиксированный retry delay

## Контакты и ссылки

- **GitLab:** http://gitlab-real.unde.life/unde/model-generator
- **fal.ai Docs:** https://fal.ai/docs
- **Celery Docs:** https://docs.celeryq.dev/

---

*Документ создан: 2026-01-28*  
*Последнее обновление: 2026-01-28*
