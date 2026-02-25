# Server: etcd-2
<!-- Этот файл — ПОЛНАЯ карта сервера.
     Обновляй при ЛЮБЫХ изменениях. -->

---

## 1. Identity & Role

- **Name:** etcd-2
- **Role:** etcd quorum node 2 — участник etcd-кластера (3 узла) для Patroni (PostgreSQL HA failover). 2 из 3 узлов в Hetzner = кворум для promote replica при падении локального primary.
- **Почему отдельный сервер:** etcd требует нечётное число узлов для кворума. Выделенный сервер гарантирует стабильный latency и изоляцию от рабочих нагрузок PostgreSQL.
- **Связь с другими серверами:**
  - etcd-1 (10.2.0.50) — peer, локальный узел в Dubai (ещё не создан)
  - etcd-3 (10.1.0.15) — peer, Hetzner (настроен, ожидает старта)
  - Patroni-ноды (shard-replica-0, local-shard-0) будут подключаться к etcd client URL для leader election

## 2. Hardware & Provider

- **Provider:** Hetzner Cloud
- **Plan/Model:** CX23 (shared vCPU)
- **Location / DC:** <!-- TODO: конкретный DC (Falkenstein / Nuremberg / Helsinki) -->
- **CPU:** AMD EPYC-Rome, 2 vCPU, 1 thread per core
- **RAM:** 4 GB
- **Storage:** 40 GB SSD, mounted as /
- **Network:** <!-- TODO: bandwidth -->
- **Стоимость:** <!-- TODO: сколько платим в месяц -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** 65.109.162.92
- **Private IP:** 10.1.0.17 (Hetzner private network / WireGuard)
- **IPv6:** <!-- TODO: если есть -->

### 3.2 DNS
Не привязаны домены — сервер работает по IP, доступен только через private network.

### 3.3 Firewall
<!-- TODO: Настройка firewall делается отдельно -->
| Port | Protocol | Source | Назначение | Почему открыт |
|---|---|---|---|---|
| 22 | TCP | <!-- TODO --> | SSH | Администрирование |
| 2379 | TCP | 10.0.0.0/8 | etcd client | Patroni-ноды подключаются для leader election |
| 2380 | TCP | 10.0.0.0/8 | etcd peer | Коммуникация между etcd-узлами кластера |
| 9100 | TCP | 10.0.0.0/8 | node_exporter | Prometheus scraping метрик |

<!-- Firewall ещё не настроен — будет делаться отдельно -->

### 3.4 SSH
- **Port:** 22 (стандартный)
- **User:** root
- **Auth:** <!-- TODO: ключи / пароль -->
- **Конфиг:** /etc/ssh/sshd_config
- **Ключи:** /root/.ssh/authorized_keys

## 4. OS & System Configuration

### 4.1 Операционная система
- **OS:** Ubuntu 24.04.3 LTS (Noble Numbat)
- **Kernel:** 6.8.0-90-generic
- **Timezone:** UTC
- **Locale:** en_US.UTF-8

### 4.2 Системные настройки (sysctl, limits)
| Параметр | Значение | Зачем | Где настроено |
|---|---|---|---|
| vm.swappiness | 1 | Минимизировать swap для etcd latency | /etc/sysctl.conf |
| net.core.somaxconn | 32768 | Увеличить backlog для соединений | /etc/sysctl.conf |
| net.ipv4.tcp_max_syn_backlog | 16384 | Увеличить SYN backlog | /etc/sysctl.conf |

### 4.3 Установленные системные пакеты
Docker НЕ используется на этом сервере. Все сервисы работают как systemd units.

| Пакет/бинарник | Версия | Зачем установлен | Как используется |
|---|---|---|---|
| etcd | v3.5.17 | Distributed KV store для Patroni | systemd service, /usr/local/bin/etcd |
| etcdctl | v3.5.17 | CLI для управления etcd | /usr/local/bin/etcdctl |
| etcdutl | v3.5.17 | Утилиты для etcd (backup/restore) | /usr/local/bin/etcdutl |
| node_exporter | 1.8.2 | Метрики сервера для Prometheus | systemd service, :9100 |

### 4.4 Пользователи и права
| User | Роль | Группы | Зачем создан |
|---|---|---|---|
| root | Администратор | — | Системный |
| etcd | Service account | etcd | Запуск etcd daemon |
| node_exporter | Service account | node_exporter | Запуск node_exporter |

### 4.5 Cron jobs & systemd timers
Нет cron jobs. Все сервисы управляются через systemd.

## 5. Services (systemd, НЕ Docker)

Docker не установлен и не нужен на этом сервере.

### 5.1 etcd
- **Binary:** /usr/local/bin/etcd v3.5.17
- **Unit:** /etc/systemd/system/etcd.service
- **User:** etcd
- **Data dir:** /var/lib/etcd (права 700, owner etcd:etcd)
- **Status:** enabled, **НЕ запущен** (ожидает одновременного старта всех 3 узлов)

**Конфигурация (из systemd unit):**
| Параметр | Значение | Зачем |
|---|---|---|
| --name | etcd-2 | Имя узла в кластере |
| --listen-peer-urls | http://10.1.0.17:2380 | Порт для peer-коммуникации |
| --listen-client-urls | http://10.1.0.17:2379,http://127.0.0.1:2379 | Порт для клиентов + localhost |
| --advertise-client-urls | http://10.1.0.17:2379 | URL для клиентов |
| --initial-advertise-peer-urls | http://10.1.0.17:2380 | URL для peer |
| --initial-cluster | etcd-1=http://10.2.0.50:2380,etcd-2=http://10.1.0.17:2380,etcd-3=http://10.1.0.15:2380 | Все 3 узла кластера |
| --initial-cluster-token | unde-patroni-cluster | Токен кластера |
| --initial-cluster-state | new | Новый кластер |
| --heartbeat-interval | 1000ms | Увеличен для cross-DC latency (~120ms RTT WireGuard) |
| --election-timeout | 5000ms | Увеличен для cross-DC latency |
| --auto-compaction-retention | 1 hour | Автоматическая компакция |
| --max-request-bytes | 1572864 (1.5 MB) | Макс размер запроса |
| --quota-backend-bytes | 2147483648 (2 GB) | Лимит БД (Patroni хранит мало данных) |

**Restart policy:** on-failure, RestartSec=5
**LimitNOFILE:** 65536

**Логи:**
```bash
journalctl -u etcd -f
journalctl -u etcd --since "1 hour ago"
```

### 5.2 node_exporter
- **Binary:** /usr/local/bin/node_exporter v1.8.2
- **Unit:** /etc/systemd/system/node_exporter.service
- **User:** node_exporter
- **Listen:** 0.0.0.0:9100
- **Status:** enabled, running

**Логи:**
```bash
journalctl -u node_exporter -f
```

## 6. Volumes & Persistent Data

### 6.1 Данные etcd
| Путь | Что хранит | Размер | Бэкапится? |
|---|---|---|---|
| /var/lib/etcd | etcd data (WAL + snapshots) | Minimal (Patroni хранит мало) | Нет необходимости — данные реплицируются между узлами |

### 6.2 Бэкапы данных
- etcd данные автоматически реплицируются между 3 узлами кластера
- При потере одного узла — кластер продолжает работать (кворум 2 из 3)
- Для полного восстановления: `etcdutl snapshot save` / `etcdutl snapshot restore`

## 7. Environment Files & Secrets

Нет .env файлов. Вся конфигурация в systemd unit files.

## 8. Reverse Proxy & Routing

Не используется. etcd работает напрямую по private IP.

## 9. Database(s)

### 9.1 — etcd (embedded)
- **Engine:** etcd v3.5.17 (bbolt backend)
- **Назначение:** Distributed KV store для Patroni leader election и конфигурации
- **Client port:** 2379
- **Peer port:** 2380
- **Data directory:** /var/lib/etcd
- **Backend quota:** 2 GB
- **Auto-compaction:** каждый час

## 10. Monitoring & Observability

### 10.1 Metrics
| Exporter | Port | Что собирает | Конфиг |
|---|---|---|---|
| node_exporter | 9100 | CPU, RAM, disk, network, filesystem | /etc/systemd/system/node_exporter.service |

etcd сам экспортирует метрики на :2379/metrics (после запуска).

### 10.2 Dashboards
- **Grafana:** <!-- TODO: URL, дашборды для etcd -->

### 10.3 Alerts
<!-- TODO: Настроить алерты для etcd cluster health -->

### 10.4 Логи
- **Где:** journald
- **Ротация:** systemd journal default
- **Как смотреть:**
```bash
# etcd
journalctl -u etcd -f
journalctl -u etcd --since "1 hour ago" --no-pager

# node_exporter
journalctl -u node_exporter -f

# Все сервисы
journalctl -f
```

## 11. Deploy Procedure

### 11.1 Обновление etcd
```bash
# 1. Остановить etcd (координировать с кластером — rolling update)
systemctl stop etcd

# 2. Заменить бинарники
ETCD_VER=v3.5.XX  # новая версия
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp --strip-components=1
mv /tmp/etcd /usr/local/bin/
mv /tmp/etcdctl /usr/local/bin/
mv /tmp/etcdutl /usr/local/bin/

# 3. Запустить
systemctl start etcd

# 4. Проверить
etcdctl member list
etcdctl endpoint health
```

### 11.2 Rollback
```bash
# Если новая версия не работает — скачать предыдущую и заменить бинарники
systemctl stop etcd
# ... установить предыдущую версию ...
systemctl start etcd
```

## 12. Recovery — Rebuild from Scratch

### 12.1 Подготовка сервера
```bash
# Ubuntu 24.04 на Hetzner CX23
# SSH доступ root
```

### 12.2 Установка etcd
```bash
ETCD_VER=v3.5.17
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp --strip-components=1
mv /tmp/etcd /tmp/etcdctl /tmp/etcdutl /usr/local/bin/

useradd --system --no-create-home --shell /usr/sbin/nologin etcd
mkdir -p /var/lib/etcd && chown etcd:etcd /var/lib/etcd && chmod 700 /var/lib/etcd
```

### 12.3 Клонирование и настройка
```bash
git clone http://root:TOKEN@gitlab-real.unde.life/unde/etcd-2.git /root/cursor/1
# systemd unit уже в репо — скопировать:
cp /etc/systemd/system/etcd.service  # или взять из репо
systemctl daemon-reload
systemctl enable etcd
```

### 12.4 Присоединение к существующему кластеру
```bash
# Если кластер уже работает — нужно добавить member:
# На рабочем узле:
etcdctl member add etcd-2 --peer-urls=http://10.1.0.17:2380

# Затем запустить etcd-2 с --initial-cluster-state=existing
```

### 12.5 Проверка
- [ ] etcd --version возвращает v3.5.17
- [ ] etcdctl version возвращает v3.5.17
- [ ] systemctl is-enabled etcd = enabled
- [ ] node_exporter работает (curl localhost:9100/metrics)
- [ ] Порты 2379/2380 слушают (после запуска кластера)
- [ ] etcdctl member list показывает 3 узла
- [ ] etcdctl endpoint health = healthy

## 13. Notes, Quirks & Known Issues

- **НЕ запускать etcd в одиночку** — без кворума (2 из 3) он зависнет на election. Все 3 узла должны стартовать одновременно.
- **Heartbeat/election timeout увеличены** (1000ms/5000ms) — стандартные 100ms/1000ms не подходят для cross-DC через WireGuard (~120ms RTT).
- **etcd-3 (10.1.0.15)** — IP etcd-2 обновлён с 10.1.1.10 на 10.1.0.17 (2026-02-25).
- **Docker не используется** на этом сервере — etcd работает как native systemd service для минимального latency.

## 14. etcd Cluster Status

| Узел | IP | Peer URL | Статус |
|---|---|---|---|
| etcd-1 | 10.2.0.50 | http://10.2.0.50:2380 | Не создан (Dubai, фаза 2) |
| **etcd-2** | **10.1.0.17** | **http://10.1.0.17:2380** | **Готов к запуску** |
| etcd-3 | 10.1.0.15 | http://10.1.0.15:2380 | Настроен, готов к запуску |

### Следующие шаги
1. Настроить etcd-1 на локальном сервере (10.2.0.50)
2. Запустить все 3 узла одновременно: `systemctl start etcd`
4. Проверить: `etcdctl member list`, `etcdctl endpoint health`
5. Настроить Patroni на shard-replica-0 и local-shard-0

## 15. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial setup | etcd v3.5.17 installed, systemd unit created, node_exporter 1.8.2 installed, sysctl tuned. etcd enabled but NOT started. |
| 2026-02-25 | etcd-3 IP fix | Updated etcd-2 IP from 10.1.1.10 → 10.1.0.17 in etcd-3 systemd unit |
