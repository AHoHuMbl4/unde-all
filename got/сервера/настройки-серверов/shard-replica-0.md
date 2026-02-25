# Server: shard-replica-0

---

## 1. Identity & Role

- **Name:** shard-replica-0
- **Role:** Hot standby реплика PostgreSQL для User Data Shard 0. Хранит личные данные пользователей (история чата, база знаний, персональные факты). При падении primary — Patroni автоматически промоутит эту реплику.
- **Почему отдельный сервер:** Географическая избыточность — primary в Dubai, реплика в Helsinki. Изоляция данных пользователей на выделенном шифрованном хранилище.
- **Связь с другими серверами:** Принимает streaming replication от локального primary (Dubai) через WireGuard. Подключения приложений через 10.1.1.10:5432.

## 2. Hardware & Provider

- **Provider:** Hetzner
- **Plan/Model:** Dedicated (custom)
- **Location / DC:** Helsinki
- **CPU:** Intel Xeon E3-1275 v6 @ 3.80GHz, 4 cores / 8 threads
- **RAM:** 64 GB DDR4
- **Storage:** 2× NVMe 512 GB в RAID1
  - md0 = RAID1 (2×80G) → ext4 → / (OS)
  - md1 = RAID1 (2×397G) → LUKS2 → ext4 → /pgdata (данные PostgreSQL)
- **Network:** <!-- TODO: bandwidth -->
- **Стоимость:** <!-- TODO -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** <!-- TODO -->
- **Private IP:** 10.1.1.10 (vSwitch)
- **IPv6:** <!-- TODO -->

### 3.2 DNS
<!-- TODO -->

### 3.3 Firewall
<!-- TODO: НЕ настраивается в этом этапе -->

### 3.4 SSH
- **Port:** 22
- **User:** root
- **Auth:** <!-- TODO: ключи -->

## 4. OS & System Configuration

### 4.1 Операционная система
- **OS:** Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel:** 6.8.0-90-generic
- **Timezone:** Europe/Berlin
- **Locale:** en_US.UTF-8

### 4.2 Системные настройки (sysctl)
| Параметр | Значение | Зачем | Где настроено |
|---|---|---|---|
| vm.nr_hugepages | 8400 | 16GB shared_buffers / 2MB per page + headroom | /etc/sysctl.conf |
| vm.swappiness | 1 | Минимизировать swap для PG | /etc/sysctl.conf |
| vm.dirty_background_ratio | 5 | Оптимизация записи на диск | /etc/sysctl.conf |
| vm.dirty_ratio | 10 | Оптимизация записи на диск | /etc/sysctl.conf |

### 4.3 Установленные системные пакеты
| Пакет | Версия | Зачем |
|---|---|---|
| postgresql-17 | 17.8 | Основная СУБД |
| postgresql-17-pgvector | 0.8.1 | Векторный поиск (embeddings) |
| node_exporter | 1.8.2 | Метрики хоста для Prometheus |
| postgres_exporter | 0.15.0 | Метрики PostgreSQL для Prometheus |

### 4.4 Пользователи
| User | Роль |
|---|---|
| root | Администратор |
| postgres | PostgreSQL superuser |
| postgres_exporter | systemd-сервис postgres_exporter |
| node_exporter | systemd-сервис node_exporter |

### 4.5 Cron jobs & systemd timers
<!-- TODO -->

## 5. Docker & Containers

Docker НЕ используется на этом сервере. Все сервисы работают как systemd services.

## 6. Storage & LUKS Encryption

### 6.1 Диски (RAID)
```
md0 = RAID1 (nvme0n1p1 + nvme1n1p1, 2×80G) → ext4 → /
md1 = RAID1 (nvme0n1p2 + nvme1n1p2, 2×397G) → LUKS2 → ext4 → /pgdata
```

### 6.2 LUKS шифрование
- **Device:** /dev/md1
- **Mapper:** /dev/mapper/pgdata → /pgdata
- **Type:** LUKS2
- **Cipher:** aes-xts-plain64
- **Key size:** 512 bits
- **LUKS password:** `ejJyDBJpN92Q7BniB15pMC0IMjbvoEVTTDr6LZi1sao=`
- **crypttab:** `pgdata /dev/md1 none luks`
- **fstab:** `/dev/mapper/pgdata /pgdata ext4 defaults 0 2`

При перезагрузке сервер запрашивает LUKS-пароль через консоль. Без пароля /pgdata не монтируется, PostgreSQL не стартует.

### 6.3 Размер
- Общий: 390 GB
- Использовано: ~49 MB (пустая БД)

## 7. PostgreSQL

### 7.1 Версия и расположение
- **Version:** PostgreSQL 17.8
- **Data directory:** /pgdata/main (LUKS-encrypted)
- **Config:** /etc/postgresql/17/main/postgresql.conf
- **Custom config:** /etc/postgresql/17/main/conf.d/custom.conf
- **HBA:** /etc/postgresql/17/main/pg_hba.conf
- **pgvector:** 0.8.1

### 7.2 Ключевые параметры (conf.d/custom.conf)
| Параметр | Значение | Зачем |
|---|---|---|
| data_directory | /pgdata/main | LUKS-encrypted storage |
| listen_addresses | 10.1.1.10,127.0.0.1 | vSwitch + localhost |
| max_connections | 100 | — |
| shared_buffers | 16GB | 25% от 64GB RAM |
| effective_cache_size | 48GB | 75% от 64GB RAM |
| work_mem | 64MB | — |
| maintenance_work_mem | 4GB | — |
| wal_buffers | 64MB | — |
| huge_pages | try | Используем HugePages (8400 pages) |
| random_page_cost | 1.1 | NVMe SSD |
| effective_io_concurrency | 200 | NVMe SSD |
| wal_level | replica | Для streaming replication |
| max_wal_senders | 5 | — |
| wal_keep_size | 8GB | — |
| max_replication_slots | 5 | — |
| hot_standby | on | Разрешить read queries на реплике |
| hot_standby_feedback | on | Предотвращение конфликтов |
| log_min_duration_statement | 1000ms | Логировать медленные запросы |

### 7.3 pg_hba.conf — доступы
| Тип | БД | Пользователь | Адрес | Метод |
|---|---|---|---|---|
| local | all | postgres | — | peer |
| local | all | all | — | peer |
| host | all | all | 127.0.0.1/32 | scram-sha-256 |
| host | all | all | 10.1.0.0/16 | scram-sha-256 |
| host | all | all | 10.1.1.0/24 | scram-sha-256 |
| host | all | all | 10.2.0.0/24 | scram-sha-256 |
| host | replication | replicator | 10.2.0.0/24 | scram-sha-256 |
| host | replication | replicator | 10.1.0.0/16 | scram-sha-256 |
| host | replication | replicator | 10.1.1.0/24 | scram-sha-256 |

### 7.4 База данных: unde_shard

#### Таблицы (9 таблиц + 64 партиции = 73 объекта)

**Chat History:**
- `conversations` — одна запись на пользователя, метаданные диалога
- `messages` — partitioned table (HASH by conversation_id, 64 партиции messages_p00..p63). Содержит: текст, embedding vector(1024), tsvector для полнотекстового поиска, metadata

**User Knowledge (E2E-encrypted):**
- `user_keys` — зашифрованные DEK-ключи пользователей
- `user_knowledge` — зашифрованные факты о пользователе (encrypted_data + iv + auth_tag)

**Logs:**
- `memory_correction_log` — лог исправлений памяти
- `knowledge_extraction_log` — лог извлечения знаний (LLM usage)

**Persona Agent:**
- `relationship_stage` — стадия отношений с пользователем
- `persona_temp_blocks` — временные блокировки поведения
- `signal_daily_deltas` — дневные дельты сигналов

#### Индексы
- `idx_messages_embedding` — HNSW (vector_cosine_ops, m=16, ef_construction=64), partial: role='user', is_embeddable=TRUE, is_forgotten=FALSE
- `idx_messages_tsv` — GIN на tsvector для полнотекстового поиска
- `idx_messages_conversation_time` — conversation_id, created_at DESC
- `idx_messages_retrieval` — partial index для быстрого retrieval
- `idx_conversations_user` — user_id
- `idx_knowledge_user_type` — user_id, knowledge_type
- `idx_knowledge_updated` — updated_at DESC
- `idx_knowledge_evidence_gin` — GIN на evidence_message_ids[]
- `idx_knowledge_active_unique` — unique partial (user_id, type, key) WHERE is_active
- `idx_correction_user`, `idx_extraction_user`, `idx_temp_blocks_user` — user lookups

#### Триггеры
- `trg_supersede_knowledge` — BEFORE INSERT на user_knowledge: деактивирует старые факты с тем же (user_id, type, key)

#### Constraints
- `chk_evidence_required` — evidence_message_ids обязательны (кроме onboarding)

### 7.5 Пользователи БД

| Role | Password | Назначение | Права |
|---|---|---|---|
| app_rw | `L4h9PdcAba99uTFH8ALDSu5Y7UDLghPK` | Основное приложение | ALL на все таблицы и sequences |
| knowledge_rw | `JoqXKwo+cPsIfTBxwF9hRGroNiLs+gRl` | Сервис знаний | ALL на user_knowledge, user_keys, логи |
| persona_rw | `Px/GguJP6QJYlvbxQy7j0Rqu3ip2eYpG` | Persona agent | ALL на persona-таблицы, SELECT на user_knowledge |
| replicator | `tOoue+JVwLYe3CnlJh4WuwIg3SmnxMDE` | Streaming replication | REPLICATION privilege |
| monitoring | `hiRU89R+C77qiHm4naTEaNUJNyN7S4b+` | postgres_exporter | pg_monitor role |

## 8. Reverse Proxy & Routing

Не используется — прямой доступ по 10.1.1.10:5432.

## 9. Monitoring & Observability

### 9.1 Exporters
| Exporter | Version | Port | Systemd unit |
|---|---|---|---|
| node_exporter | 1.8.2 | 9100 | node_exporter.service |
| postgres_exporter | 0.15.0 | 9187 | postgres_exporter.service |

### 9.2 Логи PostgreSQL
```bash
# Логи PG
tail -f /var/log/postgresql/postgresql-17-main.log

# Systemd
journalctl -u postgresql@17-main -f
```

## 10. Deploy / Recovery

### Rebuild from scratch
```bash
# 1. OS уже установлена (Ubuntu 24.04 LTS), md0/md1 RAID1 собраны
# 2. LUKS
cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 /dev/md1
cryptsetup open /dev/md1 pgdata
mkfs.ext4 -L pgdata /dev/mapper/pgdata
mkdir -p /pgdata && mount /dev/mapper/pgdata /pgdata

# 3. crypttab + fstab
echo "pgdata /dev/md1 none luks" >> /etc/crypttab
echo "/dev/mapper/pgdata /pgdata ext4 defaults 0 2" >> /etc/fstab

# 4. PostgreSQL 17 + pgvector
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
apt update && apt install -y postgresql-17 postgresql-17-pgvector

# 5. Move data dir
systemctl stop postgresql
rsync -av /var/lib/postgresql/17/main/ /pgdata/main/
chown -R postgres:postgres /pgdata

# 6. Apply configs (postgresql.conf, conf.d/custom.conf, pg_hba.conf)
# 7. Sysctl (hugepages, swappiness, dirty ratios)
# 8. Start PG, create DB, schema, users
# 9. Install exporters
```

## 11. NOT configured (by design)

- Firewall — настраивается отдельно
- Streaming replication — primary ещё не создан
- Patroni — нужен etcd-кластер и primary
- Docker — не используется, всё systemd

## 12. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial setup | LUKS encryption, PG 17.8, pgvector 0.8.1, schema (9 tables + 64 partitions), 5 DB users, node_exporter 1.8.2, postgres_exporter 0.15.0, huge pages, sysctl tuning |
