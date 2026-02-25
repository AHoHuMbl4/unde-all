# Отчёт: DB сервер db01.unde.life

## Железо

### Сервер Hetzner AX41-NVMe (Helsinki)

| Параметр | Значение |
|----------|----------|
| CPU | AMD Ryzen 5 3600, 6 cores / 12 threads |
| RAM | 64 GB ECC DDR4 |
| Домен | db01.unde.life |
| Private IP | 10.1.1.2 |
| OS | Debian 13 (Trixie) |

### Дисковая подсистема (Software RAID1)

```
┌─────────────────────────────────────────────────────────────────┐
│  NVMe 0 (476GB)          NVMe 1 (476GB)                         │
│  ├─ p1 (1GB)   ──RAID1──  p1 (1GB)   → md0  /boot    (ext4)     │
│  ├─ p2 (8GB)   ──RAID1──  p2 (8GB)   → md1  [SWAP]              │
│  ├─ p3 (100GB) ──RAID1──  p3 (100GB) → md2  /        (XFS)      │
│  └─ p5 (368GB) ──RAID1──  p5 (368GB) → md3  /pgwal   (XFS)      │
├─────────────────────────────────────────────────────────────────┤
│  NVMe 2 (2TB)            NVMe 3 (2TB)                           │
│  └─ full      ──RAID1──  full       → md4  /pgdata  (XFS)       │
└─────────────────────────────────────────────────────────────────┘
```

| Mount | RAID | Size | Назначение |
|-------|------|------|------------|
| `/` | md2 | 100 GB | Операционная система |
| `/pgwal` | md3 | 368 GB | PostgreSQL WAL + pgBackRest spool |
| `/pgdata` | md4 | 1.9 TB | PostgreSQL данные |

**Все диски на RAID1 — нет single point of failure.**

---

## Сетевая конфигурация

### Интерфейсы

| Интерфейс | IP адрес | Маска | Назначение |
|-----------|----------|-------|------------|
| `lo` | 127.0.0.1 | /8 | Loopback |
| `enp35s0` | 135.181.209.26 | /26 | Public (Hetzner) |
| `enp35s0` | 2a01:4f9:3a:2726::2 | /64 | Public IPv6 |
| `enp35s0.4000` | **10.1.1.2** | /24 | Private (vSwitch) |

### Топология сети

```
                            ┌─────────────────────────────────────┐
                            │           INTERNET                  │
                            └──────────────┬──────────────────────┘
                                           │
                                           ▼
                            ┌─────────────────────────────────────┐
                            │      Hetzner Network                │
                            │      Gateway: 135.181.209.1         │
                            └──────────────┬──────────────────────┘
                                           │
              ┌────────────────────────────┼────────────────────────────┐
              │                            │                            │
              ▼                            ▼                            ▼
    ┌─────────────────┐         ┌─────────────────┐         ┌─────────────────┐
    │  db01.unde.life │         │   Other hosts   │         │   GitLab etc    │
    │ 135.181.209.26  │         │   in vSwitch    │         │   10.0.0.x      │
    │   (Public)      │         │   10.1.x.x      │         │                 │
    └────────┬────────┘         └────────┬────────┘         └────────┬────────┘
             │                           │                           │
             └───────────────────────────┼───────────────────────────┘
                                         │
                            ┌────────────┴────────────┐
                            │   Hetzner vSwitch       │
                            │   Private Network       │
                            │   10.1.0.0/16           │
                            │   Gateway: 10.1.1.1     │
                            └─────────────────────────┘
```

### Маршрутизация

| Destination | Gateway | Interface | Примечание |
|-------------|---------|-----------|------------|
| default | 135.181.209.1 | enp35s0 | Интернет |
| 10.0.0.0/24 | 10.1.1.1 | enp35s0.4000 | GitLab, внутренние сервисы |
| 10.1.0.0/16 | 10.1.1.1 | enp35s0.4000 | Весь vSwitch |
| 10.1.1.0/24 | — | enp35s0.4000 | Локальная подсеть |

### DNS серверы

| IP | Тип |
|----|-----|
| 185.12.64.1 | Hetzner DNS (IPv4) |
| 185.12.64.2 | Hetzner DNS (IPv4) |
| 2a01:4ff:ff00::add:1 | Hetzner DNS (IPv6) |
| 2a01:4ff:ff00::add:2 | Hetzner DNS (IPv6) |

### Слушающие порты

| Порт | Bind Address | Сервис | Доступ |
|------|--------------|--------|--------|
| 22 | 0.0.0.0 | SSH | Public + Private |
| 5432 | 127.0.0.1 | PostgreSQL | **Только localhost** |
| 6432 | 10.1.1.2 | PgBouncer | **Только Private** |
| 9100 | 0.0.0.0 | node_exporter | Public + Private |
| 9187 | 0.0.0.0 | postgres_exporter | Public + Private |

### Файл конфигурации сети

`/etc/network/interfaces`:
```bash
# Public interface
auto enp35s0
iface enp35s0 inet static
  address 135.181.209.26
  netmask 255.255.255.192
  gateway 135.181.209.1

iface enp35s0 inet6 static
  address 2a01:4f9:3a:2726::2
  netmask 64
  gateway fe80::1

# vSwitch private network (VLAN 4000)
auto enp35s0.4000
iface enp35s0.4000 inet static
    address 10.1.1.2/24
    vlan-raw-device enp35s0
    mtu 1400
    post-up ip route add 10.1.0.0/16 via 10.1.1.1
    post-up ip route add 10.0.0.0/24 via 10.1.1.1
```

### Важные адреса

| Сервис | Адрес | Порт |
|--------|-------|------|
| **PostgreSQL** | 127.0.0.1 | 5432 |
| **PgBouncer** | 10.1.1.2 | 6432 |
| **GitLab** | 10.0.0.3 | 80 |
| **Storage Box** | 37.27.234.71 | 445 (SMB) |
| **node_exporter** | 10.1.1.2 | 9100 |
| **postgres_exporter** | 10.1.1.2 | 9187 |

---

## Установленное ПО

### 1. PostgreSQL 17.7

**Расположение данных:**
```
/pgdata/postgresql/17/main/     ← Data directory (RAID1 1.9TB)
    └── pg_wal → /pgwal/pg_wal  ← WAL через symlink (RAID1 368GB)
```

**Конфигурация памяти** (оптимизировано под 64GB RAM):
```ini
shared_buffers = 16GB           # 25% RAM
effective_cache_size = 48GB     # 75% RAM  
work_mem = 32MB                 # Для сортировок
maintenance_work_mem = 2GB      # Для VACUUM, CREATE INDEX
huge_pages = try
```

**Конфигурация WAL:**
```ini
wal_level = replica             # Готовность к репликации
max_wal_size = 16GB
min_wal_size = 1GB
wal_compression = zstd          # Сжатие WAL
checkpoint_completion_target = 0.9
checkpoint_timeout = 15min
```

**Конфигурация соединений:**
```ini
listen_addresses = '127.0.0.1'  # Только localhost!
port = 5432
max_connections = 200           # Запас для PgBouncer
```

**Готовность к репликации:**
```ini
max_wal_senders = 10            # Для будущих реплик
max_replication_slots = 10      # Для будущих реплик
```

**Архивация:**
```ini
archive_mode = on
archive_command = 'pgbackrest --stanza=unde archive-push %p'
```

**Расширения:**
- `pgvector 0.8.1` — векторный поиск для AI/ML
- `pg_stat_statements` — статистика запросов

**Базы данных:**

| База | Назначение | Кто пишет | Кто читает | Расширения |
|------|------------|-----------|------------|------------|
| unde_main | Пользователи, каталог, образы, история | Pipeline Server, App Server | App Server | pgvector, pg_stat_statements |
| unde_ai | Embeddings, ML данные | Pipeline Server | App Server | pgvector, pg_stat_statements |
| unde_jobs | Очередь push-уведомлений | App Server | Push Server | pg_stat_statements |

**Пользователь:**
- `undeuser` с паролем `<DB_PASSWORD_FROM_VAULT>`

---

### 2. PgBouncer 1.25

**Зачем:** Connection pooling — PostgreSQL создаёт процесс на каждое соединение, что дорого. PgBouncer держит пул готовых соединений.

**Архитектура:**
```
Приложения ──► PgBouncer (10.1.1.2:6432) ──► PostgreSQL (127.0.0.1:5432)
                    │
                    ├── Transaction mode (по умолчанию)
                    │   └── Соединение возвращается в пул после каждой транзакции
                    │   └── Для API, workers
                    │
                    └── Session mode (для аналитики)
                        └── Соединение держится всю сессию
                        └── Для prepared statements
```

**Пулы:**

| Имя БД | Режим | Для чего |
|--------|-------|----------|
| unde_main | transaction | API, workers |
| unde_ai | transaction | API, workers |
| unde_jobs | transaction | Background jobs |
| unde_main_session | session | Аналитика |
| unde_ai_session | session | Аналитика |

**Лимиты:**
```ini
max_client_conn = 500      # Макс клиентов к PgBouncer
default_pool_size = 20     # Соединений к PostgreSQL на пул
```

---

### 3. pgBackRest 2.57

**Зачем:** Enterprise-grade бэкапы PostgreSQL с инкрементальным копированием и WAL архивацией.

**Архитектура:**
```
PostgreSQL ──► archive_command ──► pgBackRest (async) ──► /mnt/storagebox
                                         │                       │
                                         ▼                       ▼ (SMB/CIFS)
                                   /pgwal/spool          Hetzner Storage Box (1TB)
                                   (async queue)         u534401.your-storagebox.de
```

**Как работает:**
1. PostgreSQL генерирует WAL файлы
2. `archive_command` вызывает pgBackRest
3. **Async mode:** WAL сначала копируется в spool (`/pgwal/spool`), затем асинхронно отправляется на Storage Box — это предотвращает блокировку PostgreSQL при медленном storage
4. По расписанию делаются full/diff бэкапы
5. Всё хранится на удалённом Storage Box

**Ключевые настройки:**
```ini
# Async archiving - критично для стабильности!
archive-async = y
spool-path = /pgwal/spool

# Repository
repo1-path = /mnt/storagebox/backups/db01

# Retention
repo1-retention-full = 4
repo1-retention-diff = 7

# Compression
compress-type = zst
compress-level = 3
```

**Хранилище:**
- Host: `u534401.your-storagebox.de`
- Протокол: **SMB/CIFS** (порт 445)
- Mount point: `/mnt/storagebox`
- IP: `37.27.234.71`
- Доступно: 1 TB
- Credentials: `/root/.storagebox-creds`

**Расписание (cron):**

| День | Время | Тип |
|------|-------|-----|
| Воскресенье | 02:00 | Full backup |
| Пн-Сб | 03:00 | Differential backup |

**Retention:**
- 4 полных бэкапа
- 7 дифференциальных

**Команды:**
```bash
# Статус бэкапов
pgbackrest info --stanza=unde

# Проверка конфигурации
pgbackrest --stanza=unde check

# Ручной полный бэкап
pgbackrest --stanza=unde --type=full backup

# Ручной дифференциальный бэкап
pgbackrest --stanza=unde --type=diff backup

# Восстановление
pgbackrest --stanza=unde restore
```

---

### 4. Мониторинг

**node_exporter (порт 9100)**
- Системные метрики: CPU, RAM, диски, сеть
- URL: `http://10.1.1.2:9100/metrics`

**postgres_exporter (порт 9187)**
- PostgreSQL метрики: соединения, транзакции, блокировки, репликация
- URL: `http://10.1.1.2:9187/metrics`

Prometheus скрейпит эти endpoint'ы для сбора метрик.

---

## Архитектура соединений

```
                                    ┌─────────────────────────────────────┐
                                    │      db01.unde.life (10.1.1.2)      │
                                    │                                     │
┌──────────────────┐               │   ┌─────────────────────────────┐   │
│    App Server    │───────────────┼──►│  PgBouncer (10.1.1.2:6432)  │   │
│  (unde-api)      │               │   │  - max 500 clients          │   │
│  ЧИТАЕТ данные   │               │   │  - pool size 20             │   │
└──────────────────┘               │   └──────────────┬──────────────┘   │
                                    │                  │                   │
┌──────────────────┐               │                  │                   │
│ Pipeline Server  │───────────────┼──►               │                   │
│  ПИШЕТ каталог   │               │                  ▼                   │
│  (отдельный)     │               │   ┌─────────────────────────────┐   │
└──────────────────┘               │   │ PostgreSQL (127.0.0.1:5432) │   │
                                    │   │ - shared_buffers 16GB       │   │
┌──────────────────┐               │   │ - max_connections 200       │   │
│   Push Server    │───────────────┼──►│ - wal_level replica         │   │
│  (отдельный)     │               │   └──────────────┬──────────────┘   │
└──────────────────┘               │                  │                   │
                                    │                  │                   │
┌──────────────────┐               │   ┌─────────────────────────────┐   │
│   Prometheus     │───────────────┼──►│  Exporters                  │   │
│  (App Server)    │               │   │  :9100 node, :9187 postgres │   │
└──────────────────┘               │   └─────────────────────────────┘   │
                                    └─────────────────────────────────────┘
                                                       │
                                                       │ pgBackRest (async)
                                                       ▼
                                    ┌─────────────────────────────────────┐
                                    │     Hetzner Storage Box (1TB)       │
                                    │     //37.27.234.71/backup (SMB)     │
                                    └─────────────────────────────────────┘
```

### Кто подключается к БД

| Сервер | Операции | База | Режим PgBouncer |
|--------|----------|------|-----------------|
| **App Server** (unde-api) | Читает профили, историю, рекомендации | unde_main | transaction |
| **Pipeline Server** | Пишет каталог, образы, embeddings | unde_main, unde_ai | transaction |
| **Push Server** | Читает очередь уведомлений | unde_jobs | transaction |
| **Analytics** (будущее) | Аналитические запросы | unde_main_session | session |

---

## Строки подключения

```bash
# App Server (unde-api) — transaction mode
postgresql://undeuser:<DB_PASSWORD_FROM_VAULT>@10.1.1.2:6432/unde_main?prepared_statement_cache_size=0

# Pipeline Server — transaction mode  
postgresql://undeuser:<DB_PASSWORD_FROM_VAULT>@10.1.1.2:6432/unde_main?prepared_statement_cache_size=0
postgresql://undeuser:<DB_PASSWORD_FROM_VAULT>@10.1.1.2:6432/unde_ai?prepared_statement_cache_size=0

# Push Server — transaction mode
postgresql://undeuser:<DB_PASSWORD_FROM_VAULT>@10.1.1.2:6432/unde_jobs?prepared_statement_cache_size=0

# Analytics — session mode (для prepared statements)
postgresql://undeuser:<DB_PASSWORD_FROM_VAULT>@10.1.1.2:6432/unde_main_session
```

---

## Systemd сервисы

| Сервис | Назначение | Автозапуск |
|--------|------------|------------|
| postgresql@17-main | PostgreSQL 17 | enabled |
| pgbouncer | Connection pooler | enabled |
| prometheus-node-exporter | Системные метрики | enabled |
| prometheus-postgres-exporter | PG метрики | enabled |
| mnt-storagebox.mount | SMB mount Storage Box | enabled |

---

## Ключевые файлы конфигурации

| Файл | Назначение |
|------|------------|
| `/etc/postgresql/17/main/postgresql.conf` | Основной конфиг PG |
| `/etc/postgresql/17/main/conf.d/unde.conf` | Кастомные настройки UNDE |
| `/etc/pgbouncer/pgbouncer.ini` | Конфиг PgBouncer |
| `/etc/pgbouncer/userlist.txt` | Пользователи PgBouncer (SCRAM hash) |
| `/etc/pgbackrest/pgbackrest.conf` | Конфиг бэкапов |
| `/etc/cron.d/pgbackrest` | Расписание бэкапов |
| `/root/.storagebox-creds` | Credentials для SMB mount |
| `/etc/systemd/system/mnt-storagebox.mount` | Systemd unit для Storage Box |

---

## Ключевые директории

| Путь | Назначение |
|------|------------|
| `/pgdata/postgresql/17/main` | Data directory PostgreSQL |
| `/pgwal/pg_wal` | WAL файлы (symlink) |
| `/pgwal/spool` | pgBackRest async spool |
| `/mnt/storagebox` | Storage Box mount point |
| `/mnt/storagebox/backups/db01` | pgBackRest repository |

---

## Безопасность

1. **PostgreSQL изолирован** — слушает только 127.0.0.1:5432
2. **Внешний доступ только через PgBouncer** — единая точка входа на 10.1.1.2:6432
3. **SCRAM-SHA-256** — современная аутентификация паролей
4. **Credentials в отдельном файле** — `/root/.storagebox-creds` с правами 600
5. **RAID1 везде** — защита от отказа диска

---

## Готовность к масштабированию

| Функция | Статус | Примечание |
|---------|--------|------------|
| Streaming replication | Готов | `wal_level=replica`, `max_wal_senders=10` |
| Replication slots | Готов | `max_replication_slots=10` |
| Point-in-time recovery | Готов | WAL архивируется в Storage Box |
| Connection pooling | Активен | PgBouncer до 500 клиентов |

---

## Проверка здоровья системы

```bash
# Статус всех сервисов
systemctl status postgresql@17-main pgbouncer prometheus-node-exporter prometheus-postgres-exporter mnt-storagebox.mount

# Параметры PostgreSQL
sudo -u postgres psql -c "
SELECT name, setting FROM pg_settings 
WHERE name IN ('max_connections', 'wal_level', 'max_wal_senders', 
               'max_replication_slots', 'archive_mode', 'wal_compression');
"

# Статус pgBackRest
pgbackrest --stanza=unde info
pgbackrest --stanza=unde check

# Тест PgBouncer
PGPASSWORD=<DB_PASSWORD_FROM_VAULT> psql -h 10.1.1.2 -p 6432 -U undeuser -d unde_main -c "SELECT 1;"

# Проверка mount
df -h /mnt/storagebox
```

---

## Дата настройки

**2026-01-19** | Настроено для проекта UNDE (AI-агент для офлайн-ритейла)

**Изменения:**
- Начальная установка PostgreSQL 17 + PgBouncer + pgBackRest
- Переход с sshfs на SMB/CIFS (стабильнее)
- Включение async archiving
- Подготовка к репликации
