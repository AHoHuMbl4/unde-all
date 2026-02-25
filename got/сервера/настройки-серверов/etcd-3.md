# Server: etcd-3
<!-- Этот файл — ПОЛНАЯ карта сервера. Обновляй при ЛЮБЫХ изменениях. -->

---

## 1. Identity & Role

- **Name:** etcd-3
- **Role:** etcd quorum node 3 (tiebreaker) для Patroni PostgreSQL failover-кластера
- **Почему отдельный сервер:** Tiebreaker-нода в Hetzner — 2 из 3 etcd-узлов в Hetzner = кворум для автоматического promote replica при падении локального (Dubai) primary. Отдельный сервер для изоляции etcd от других нагрузок и минимизации failure domain.
- **Связь с другими серверами:**
  - etcd-1 (10.2.0.50, Dubai, локальный) — peer через WireGuard, ~120ms RTT
  - etcd-2 (10.1.0.17, Hetzner, отдельный сервер) — peer, низкая latency внутри Hetzner
  - Patroni-ноды будут подключаться к etcd-кластеру как клиенты

## 2. Hardware & Provider

- **Provider:** Hetzner Cloud
- **Plan/Model:** CX23 (shared vCPU)
- **Location / DC:** <!-- TODO: конкретный DC (Falkenstein / Nuremberg / Helsinki) -->
- **CPU:** 2 vCPU (shared, Intel/AMD)
- **RAM:** 4 GB
- **Storage:** 40 GB SSD (/dev/sda1, 38G usable, 6% used)
- **Network:** <!-- TODO: bandwidth -->
- **Стоимость:** <!-- TODO: сколько платим в месяц -->

## 3. Network Configuration

### 3.1 IP-адреса
- **Public IP:** 89.167.98.219
- **Private IP:** 10.1.0.15 (WireGuard / Hetzner private network)
- **IPv6:** fe80::9000:7ff:fe43:227f/64 (link-local only)

### 3.2 DNS
Нет привязанных доменов — сервер работает по IP.

### 3.3 Firewall
<!-- TODO: Настраивается отдельно, НЕ на этом этапе -->
Ожидаемые порты:
| Port | Protocol | Source | Назначение | Почему открыт |
|---|---|---|---|---|
| 22 | TCP | Admin IPs | SSH | Управление |
| 2379 | TCP | 10.0.0.0/8 | etcd client | Patroni-ноды подключаются сюда |
| 2380 | TCP | 10.0.0.0/8 | etcd peer | Репликация между etcd-нодами |
| 9100 | TCP | 10.0.0.0/8 | node_exporter | Prometheus scraping |

### 3.4 SSH
- **Port:** 22 (стандартный)
- **User:** root
- **Auth:** По умолчанию (ключи Hetzner при создании)
- **Конфиг:** /etc/ssh/sshd_config (дефолтный)
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
| vm.swappiness | 1 | Минимизация swap для etcd (latency-sensitive) | /etc/sysctl.conf |
| net.core.somaxconn | 32768 | Увеличение очереди соединений для etcd | /etc/sysctl.conf |
| net.ipv4.tcp_max_syn_backlog | 16384 | Увеличение SYN backlog для etcd | /etc/sysctl.conf |

### 4.3 Установленные системные пакеты
Docker НЕ установлен и НЕ нужен — etcd работает как systemd service.

| Пакет/Binary | Версия | Зачем установлен | Как используется |
|---|---|---|---|
| etcd | 3.5.17 | Distributed KV store для Patroni | systemd service |
| etcdctl | 3.5.17 | CLI для управления etcd | Диагностика, member list |
| etcdutl | 3.5.17 | Утилиты для обслуживания etcd | Snapshot, defrag |
| node_exporter | 1.8.2 | Метрики сервера для Prometheus | systemd service, :9100 |

### 4.4 Пользователи и права
| User | Роль | Группы | Зачем создан |
|---|---|---|---|
| root | Администратор | — | Системный |
| etcd | Service account для etcd | etcd | Безопасный запуск etcd (nologin) |
| node_exporter | Service account для node_exporter | node_exporter | Безопасный запуск node_exporter (nologin) |

### 4.5 Cron jobs & systemd timers
Нет настроенных cron jobs.

## 5. Docker & Containers — НЕ ИСПОЛЬЗУЕТСЯ

Docker НЕ установлен на этом сервере. Все сервисы работают как systemd units.
etcd намеренно запускается без Docker для минимизации overhead и failure domain.

## 6. Volumes & Persistent Data

### 6.1 Директории с данными
| Path | Что хранит | Owner | Permissions | Бэкап |
|---|---|---|---|---|
| /var/lib/etcd | etcd data directory (WAL, snapshots, member data) | etcd:etcd | 700 | <!-- TODO: стратегия бэкапа --> |

### 6.2 Бэкапы данных
- **Что бэкапится:** /var/lib/etcd (или через `etcdctl snapshot save`)
- **Куда:** <!-- TODO -->
- **Расписание:** <!-- TODO -->
- **Как восстановить:** `etcdctl snapshot restore <file> --data-dir /var/lib/etcd`

## 7. Environment Files & Secrets

Нет .env файлов. Конфигурация etcd задана через аргументы ExecStart в systemd unit.

## 8. Reverse Proxy & Routing

НЕ используется — etcd принимает запросы напрямую по HTTP на портах 2379/2380.

## 9. Database(s)

### 9.1 — etcd (key-value store)
- **Engine:** etcd 3.5.17 (bbolt backend)
- **Назначение:** Distributed consensus для Patroni — хранит leader lock, cluster state, конфиг PostgreSQL
- **Client port:** 2379 (http://10.1.0.15:2379, http://127.0.0.1:2379)
- **Peer port:** 2380 (http://10.1.0.15:2380)
- **Data directory:** /var/lib/etcd
- **Конфигурация:**
  - Cluster token: `unde-patroni-cluster`
  - Heartbeat interval: 1000ms (увеличен для cross-DC latency ~120ms RTT)
  - Election timeout: 5000ms (увеличен для cross-DC latency)
  - Auto-compaction: 1 hour
  - Max request bytes: 1.5 MB
  - Backend quota: 2 GB
  - Initial cluster state: new
- **Cluster members:**
  - etcd-1: http://10.2.0.50:2380 (Dubai, ещё не создан)
  - etcd-2: http://10.1.0.17:2380 (Hetzner, отдельный сервер, ещё не запущен)
  - etcd-3: http://10.1.0.15:2380 (этот сервер, готов)
- **Бэкап:** `etcdctl snapshot save /tmp/etcd-backup.db`
- **Восстановление:** `etcdctl snapshot restore <file> --data-dir /var/lib/etcd`

## 10. Monitoring & Observability

### 10.1 Metrics
- **Exporters:**
| Exporter | Port | Что собирает | Конфиг |
|---|---|---|---|
| node_exporter | 9100 | CPU/RAM/disk/network | /etc/systemd/system/node_exporter.service |
| etcd built-in | 2379 | etcd metrics (/metrics endpoint) | Встроен в etcd (доступен после старта) |

### 10.2 Dashboards
- **Grafana:** <!-- TODO: URL, дашборд для etcd -->

### 10.3 Alerts
<!-- TODO: Настроить алерты -->

### 10.4 Логи
- **Где:** journald
- **Как смотреть:**
```bash
# etcd логи
journalctl -u etcd -f

# node_exporter логи
journalctl -u node_exporter -f

# Все логи
journalctl -f
```

## 11. Deploy Procedure

### 11.1 Обычный деплой (обновление etcd)
```bash
# 1. Скачать новую версию
ETCD_VER=v3.5.XX
curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd.tar.gz
tar xzf /tmp/etcd.tar.gz -C /tmp/ --strip-components=1

# 2. Остановить etcd
systemctl stop etcd

# 3. Заменить бинарники
mv /tmp/etcd /usr/local/bin/
mv /tmp/etcdctl /usr/local/bin/
mv /tmp/etcdutl /usr/local/bin/

# 4. Запустить
systemctl start etcd

# 5. Проверить
etcdctl member list
etcdctl endpoint health
```

### 11.2 Rollback
```bash
# Если обновление сломало etcd:
# 1. Остановить
systemctl stop etcd

# 2. Восстановить предыдущую версию бинарников (из бэкапа/скачать)
# 3. Если данные повреждены — восстановить из snapshot
etcdctl snapshot restore /path/to/backup.db --data-dir /var/lib/etcd
chown -R etcd:etcd /var/lib/etcd

# 4. Запустить
systemctl start etcd
```

## 12. Recovery — Rebuild from Scratch

### 12.1 Подготовка сервера
```bash
# На чистом Ubuntu 24.04:
# 1. Обновить систему
apt update && apt upgrade -y

# 2. Клонировать репо
git clone http://root:TOKEN@gitlab-real.unde.life/unde/etcd-3.git /root/cursor/1
```

### 12.2 Установка etcd
```bash
ETCD_VER=v3.5.17
DOWNLOAD_URL=https://github.com/etcd-io/etcd/releases/download
mkdir -p /tmp/etcd-download
curl -L ${DOWNLOAD_URL}/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-download/etcd.tar.gz
tar xzf /tmp/etcd-download/etcd.tar.gz -C /tmp/etcd-download --strip-components=1
mv /tmp/etcd-download/etcd /usr/local/bin/
mv /tmp/etcd-download/etcdctl /usr/local/bin/
mv /tmp/etcd-download/etcdutl /usr/local/bin/
rm -rf /tmp/etcd-download
```

### 12.3 Настройка сервисов
```bash
# Пользователи
useradd --system --no-create-home --shell /usr/sbin/nologin etcd
useradd --system --no-create-home --shell /usr/sbin/nologin node_exporter

# Директории
mkdir -p /var/lib/etcd
chown etcd:etcd /var/lib/etcd
chmod 700 /var/lib/etcd

# Скопировать systemd units из репо (или создать по документации выше)
# cp /path/to/etcd.service /etc/systemd/system/
# cp /path/to/node_exporter.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable etcd node_exporter
systemctl start node_exporter
# etcd — стартовать только когда все 3 ноды готовы
```

### 12.4 Восстановление данных
```bash
# Если есть snapshot:
etcdctl snapshot restore /path/to/backup.db \
  --name etcd-3 \
  --data-dir /var/lib/etcd \
  --initial-cluster etcd-1=http://10.2.0.50:2380,etcd-2=http://10.1.0.17:2380,etcd-3=http://10.1.0.15:2380 \
  --initial-cluster-token unde-patroni-cluster \
  --initial-advertise-peer-urls http://10.1.0.15:2380
chown -R etcd:etcd /var/lib/etcd

# Если новый кластер — просто запустить все 3 ноды одновременно
```

### 12.5 Проверка
- [ ] etcd --version → 3.5.17
- [ ] node_exporter running → curl http://localhost:9100/metrics
- [ ] sysctl applied → sysctl vm.swappiness (should be 1)
- [ ] etcd enabled → systemctl is-enabled etcd
- [ ] Ports 2379/2380 free (до старта кластера)
- [ ] После старта кластера: etcdctl member list, etcdctl endpoint health

## 13. Notes, Quirks & Known Issues

- **НЕ запускать etcd в одиночку** — без кворума (2 из 3) он не стартует / зависнет в election loop
- **Heartbeat/election timeouts увеличены** (1000/5000ms vs default 100/1000ms) из-за cross-DC latency через WireGuard (~120ms RTT Dubai↔Hetzner)
- **Docker НЕ нужен** — etcd как systemd service для минимизации overhead
- **initial-cluster-state=new** — при первом старте. Если нода перезапускается после join — etcd сам определяет что это existing member по данным в /var/lib/etcd
- **Порядок первого старта:** все 3 ноды должны стартовать примерно одновременно (в пределах election-timeout)

## 14. Changelog

| Date | Change | Details |
|---|---|---|
| 2026-02-25 | Initial setup | etcd 3.5.17 installed, systemd unit created, node_exporter 1.8.2 running, sysctl tuned. Waiting for etcd-1/etcd-2 to start cluster. |
