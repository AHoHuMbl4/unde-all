# Monitoring Server — Deployment Report

## Сервер
| Параметр | Значение |
|----------|----------|
| Hostname | monitoring |
| Private IP | 10.1.0.7 |
| Public IP | 89.167.83.72 |
| Тип | CPX32 (4 vCPU / 8 GB RAM / 80 GB SSD) |
| OS | Ubuntu 24.04.4 LTS |

## Установленные сервисы
- Prometheus v2.54.1 (systemd, :9090, retention 30d)
- Alertmanager v0.27.0 (systemd, :9093, Telegram receiver)
- Grafana v12.3.3 (systemd, :3000, datasource: Prometheus)
- node_exporter v1.8.2 (systemd, :9100)

## Prometheus targets

### UP (18)
| Job | Target |
|-----|--------|
| prometheus | localhost:9090 |
| node-monitoring | localhost:9100 |
| node-push | 10.1.0.4:9100 |
| redis-push | 10.1.0.4:9121 |
| node-model-generator | 10.1.0.5:9100 |
| node-tryon-service | 10.1.0.6:9100 |
| node-production-db | 10.1.1.2:9100 |
| postgres-production-db | 10.1.1.2:9187 |
| node-apify | 10.1.0.9:9100 |
| node-photo-downloader | 10.1.0.10:9100 |
| node-ximilar-sync | 10.1.0.11:9100 |
| node-collage | 10.1.0.16:9100 |
| node-staging-db | 10.1.0.8:9100 |
| node-recognition | 10.1.0.14:9100 |
| node-ximilar-gw | 10.1.0.12:9100 |
| ximilar-gw-app | 10.1.0.12:8001 |
| node-llm-reranker | 10.1.0.13:9100 |
| llm-reranker-app | 10.1.0.13:8002 |

### DOWN (8, ожидаемо)
| Job | Target | Причина |
|-----|--------|---------|
| node-helsinki-gw | 10.1.0.2:9100 | MikroTik, нет node_exporter |
| node-scraper | 10.1.0.3:9100 | node_exporter не установлен |
| postgres-staging | 10.1.0.8:9187 | postgres_exporter не установлен |
| node-shard-replica-0 | 10.1.1.10:9100 | сервер не настроен |
| postgres-shard-replica-0 | 10.1.1.10:9187 | сервер не настроен |
| etcd-cluster | 10.1.1.10:2379 | сервер не настроен |
| etcd-cluster | 10.1.0.15:2379 | сервер не настроен |
| node-posthog | 10.1.1.30:9100 | сервер не настроен |

## Alert rules
| Alert | Expression | For | Severity |
|-------|-----------|-----|----------|
| NodeDown | up == 0 | 1m | critical |
| HighCPU | CPU > 85% | 5m | warning |
| HighMemory | RAM > 85% | 5m | warning |
| DiskAlmostFull | Disk > 80% | 5m | warning |
| DiskFull | Disk > 95% | 1m | critical |

## Конфиги
| Файл | Путь |
|------|------|
| Prometheus config | /etc/prometheus/prometheus.yml |
| Alert rules | /etc/prometheus/rules/unde_alerts.yml |
| Prometheus data | /var/lib/prometheus/data |
| Alertmanager config | /etc/alertmanager/alertmanager.yml |
| Alertmanager data | /var/lib/alertmanager/data |
| Grafana config | /etc/grafana/grafana.ini |
| Grafana provisioning | /etc/grafana/provisioning/ |

## Network
- Private subnet: 10.1.0.0/16 (Helsinki cloud)
- Route to local servers: 10.2.0.0/24 via 10.1.0.2 (helsinki-gw) — persistent
- Firewall (ufw): отключён, управляется отдельно

## Git
- Repo: http://gitlab-real.unde.life/unde/Monitoring
- Clone: `git clone http://gitlab-real.unde.life/unde/Monitoring.git`
- Deploy: `sudo bash setup.sh`

## TODO
- [ ] Заменить PLACEHOLDER_BOT_TOKEN в alertmanager.yml
- [ ] Заменить chat_id: -1 на реальный Telegram chat ID
- [ ] Заменить PLACEHOLDER_PASSWORD в grafana.ini
- [ ] Установить node_exporter на scraper (10.1.0.3)
- [ ] Установить postgres_exporter на staging-db (10.1.0.8)
- [ ] Настроить shard-replica-0 (10.1.1.10)
- [ ] Настроить etcd nodes (10.1.1.10, 10.1.0.15)
- [ ] Настроить posthog (10.1.1.30)
- [ ] Создать Grafana дашборды

## Changelog
| Date | Change |
|------|--------|
| 2026-02-23 | Initial setup — Prometheus, Alertmanager, Grafana, node_exporter |
| 2026-02-25 | Updated prometheus.yml — added all deployed targets (model-generator, tryon-service, apify, photo-downloader, ximilar-sync, collage, staging-db, recognition, ximilar-gw, llm-reranker with app metrics, shard-replica, etcd, posthog). Result: 18 UP, 8 DOWN |
