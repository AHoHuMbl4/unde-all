# Server Description

## General
- **Hostname**: monitoring
- **Role**: Centralized monitoring server for UNDE infrastructure
- **Provider**: Hetzner, Helsinki datacenter
- **Plan**: CPX32 (4 vCPU / 8 GB RAM / 80 GB SSD)
- **OS**: Ubuntu 24.04.4 LTS, kernel 6.8.0-90-generic

## Network
- **Public IP**: 89.167.83.72 (eth0)
- **Private IP**: 10.1.0.7 (enp7s0, Hetzner private network)
- **Private subnet**: 10.1.0.0/16 (Helsinki cloud)
- **Route to local servers**: 10.2.0.0/24 via 10.1.0.2 (helsinki-gw) — настроен, persistent
- **Firewall (ufw)**: отключён, управляется отдельно

## Installed Services

### Prometheus
- **Version**: 2.54.1
- **Binary**: /usr/local/bin/prometheus, /usr/local/bin/promtool
- **Config**: /etc/prometheus/prometheus.yml
- **Alert rules**: /etc/prometheus/rules/unde_alerts.yml
- **Data**: /var/lib/prometheus/data (retention: 30 days)
- **Listen**: 0.0.0.0:9090
- **User**: prometheus (systemd, Restart=always)
- **Reload**: `curl -X POST http://localhost:9090/-/reload`
- **Health**: `curl http://localhost:9090/-/healthy`

### Alertmanager
- **Version**: 0.27.0
- **Binary**: /usr/local/bin/alertmanager, /usr/local/bin/amtool
- **Config**: /etc/alertmanager/alertmanager.yml
- **Data**: /var/lib/alertmanager/data
- **Listen**: 0.0.0.0:9093
- **User**: alertmanager (systemd, Restart=always)
- **Receiver**: Telegram (bot_token и chat_id — заменить вручную)
- **Health**: `curl http://localhost:9093/-/healthy`

### Grafana
- **Version**: 12.3.3 (OSS, из APT-репозитория Grafana)
- **Config**: /etc/grafana/grafana.ini
- **Provisioning**: /etc/grafana/provisioning/datasources/prometheus.yml
- **Listen**: 0.0.0.0:3000
- **Admin**: admin / PLACEHOLDER_PASSWORD (заменить вручную)
- **Datasource**: Prometheus (http://localhost:9090), auto-provisioned
- **Health**: `curl http://localhost:3000/api/health`

### node_exporter
- **Version**: 1.8.2
- **Binary**: /usr/local/bin/node_exporter
- **Listen**: 0.0.0.0:9100
- **User**: node_exporter (systemd, Restart=always)
- **Metrics**: `curl http://localhost:9100/metrics`

## Prometheus Targets (active scrape configs)

### UP
| Job | Target | Exporters |
|-----|--------|-----------|
| prometheus | localhost:9090 | self-monitoring |
| monitoring-node | localhost:9100 | node_exporter |
| helsinki-push | 10.1.0.4:9100, 10.1.0.4:9121 | node + redis_exporter |
| helsinki-production-db | 10.1.1.2:9100, 10.1.1.2:9187 | node + postgres_exporter |

### DOWN (ожидаемо — нет node_exporter на этих серверах)
| Job | Target | Причина |
|-----|--------|---------|
| helsinki-gw | 10.1.0.2:9100 | node_exporter не установлен |
| helsinki-scraper | 10.1.0.3:9100 | node_exporter не установлен |

### Закомментированы (раскомментировать по мере создания серверов)
- helsinki-staging-db (10.1.1.3)
- helsinki-apify (10.1.0.7)
- helsinki-collage (10.1.0.8)
- helsinki-recognition (10.1.0.9)
- helsinki-photo-downloader (10.1.0.13)
- helsinki-ximilar-sync (10.1.0.14)
- helsinki-ximilar-gw (10.1.0.15)
- helsinki-llm-reranker (10.1.0.16)
- helsinki-posthog (10.1.0.30)
- helsinki-shard-replica (10.1.1.10)
- helsinki-etcd (10.1.1.10, 10.1.1.20)
- local-* (10.2.0.x) — после Phase 2 VPN

## Alert Rules (5 правил)
| Alert | Expression | For | Severity |
|-------|-----------|-----|----------|
| NodeDown | `up == 0` | 1m | critical |
| HighCPU | CPU > 85% | 5m | warning |
| HighMemory | RAM > 85% | 5m | warning |
| DiskAlmostFull | Disk > 80% | 5m | warning |
| DiskFull | Disk > 95% | 1m | critical |

## Systemd Units
```
node_exporter.service   — enabled, active
prometheus.service      — enabled, active
alertmanager.service    — enabled, active
grafana-server.service  — enabled, active
```

## File Locations (on server)
| Что | Путь |
|-----|------|
| Prometheus config | /etc/prometheus/prometheus.yml |
| Alert rules | /etc/prometheus/rules/unde_alerts.yml |
| Prometheus data | /var/lib/prometheus/data |
| Alertmanager config | /etc/alertmanager/alertmanager.yml |
| Alertmanager data | /var/lib/alertmanager/data |
| Grafana config | /etc/grafana/grafana.ini |
| Grafana provisioning | /etc/grafana/provisioning/ |
| node_exporter systemd | /etc/systemd/system/node_exporter.service |
| prometheus systemd | /etc/systemd/system/prometheus.service |
| alertmanager systemd | /etc/systemd/system/alertmanager.service |
| Persistent route | /etc/network/interfaces.d/local-route |

## Repo (source of truth)
- **GitLab**: http://gitlab-real.unde.life/unde/Monitoring
- **Clone**: `git clone http://gitlab-real.unde.life/unde/Monitoring.git`
- **Deploy**: `sudo bash setup.sh`
- setup.sh идемпотентен — безопасно запускать повторно

## TODO (ручные действия после деплоя)
- [ ] Заменить `PLACEHOLDER_BOT_TOKEN` в /etc/alertmanager/alertmanager.yml
- [ ] Заменить `chat_id: -1` на реальный Telegram chat ID
- [ ] Заменить `PLACEHOLDER_PASSWORD` в /etc/grafana/grafana.ini
- [ ] Перезапустить: `sudo systemctl restart alertmanager grafana-server`
- [ ] Установить node_exporter на helsinki-gw (10.1.0.2) и helsinki-scraper (10.1.0.3)
- [ ] Создать Grafana дашборды
