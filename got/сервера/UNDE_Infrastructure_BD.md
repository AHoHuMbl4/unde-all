# UNDE Infrastructure: Scaling to 10,000 Users
## Dedicated Server → Colocation + RAM Disk + Sharding + Streaming Replication

**Дата:** Февраль 2026  
**Контекст:** Smart Context Architecture v0.4.0, PostgreSQL 17 + pgvector, 1024-dim embeddings  
**Целевая география:** Dubai (primary), Hetzner Helsinki (replicas + backups)

---

## 1. Проблема: RAM — единственный bottleneck

### Почему не CPU, не диск, не сеть

При 10,000 пользователях (10% онлайн = 1,000 concurrent) нагрузка распределяется так:

| Ресурс | Нагрузка | Лимит | Утилизация |
|---|---|---|---|
| CPU (HNSW search) | 100 TPS × 3.5ms = 0.35 ядра | 24 ядра (EPYC 7413) | 1.5% |
| WAL write (NVMe) | 100 TPS × ~11–14 KB = ~1.1–1.4 MB/s | 3,000 MB/s (NVMe seq write) | 0.04% |
| WAL streaming (сеть) | ~1.1–1.4 MB/s = ~9–11 Mbps | 1 Gbps | ~1% |
| **RAM (HNSW index)** | **Растёт линейно, не сбрасывается** | **256 GB** | **Bottleneck** |

### Рост working set (halfvec, 10K users)

| Период | Embeddings | HNSW индекс | Heap + прочие индексы | Working set |
|---|---|---|---|---|
| Месяц 6 | 7.5M | ~22 GB | ~40 GB | ~62 GB |
| Год 1 | 15M | ~45 GB | ~70 GB | ~115 GB |
| Год 2 | 30M | ~90 GB | ~140 GB | ~230 GB |
| Год 3 | 45M | ~135 GB | ~250 GB | ~385 GB |
| Год 5 | 75M | ~225 GB | ~400 GB | ~625 GB |

**Формула:** ~500 msg/мес × 25% embeddable × 3 KB/embedding (halfvec) = ~375 KB HNSW/user/мес

**Один сервер 256 GB** вмещает 10K users комфортно **~8–10 месяцев.** После этого — шардирование.

---

## 2. Решение: Bare Metal в Дубае + RAM Disk

### Стратегия: dedicated server → colocation

**Фаза старта (0–6 мес):** Аренда dedicated server в Дубае. Без CAPEX, быстрый запуск, полный контроль над железом (tmpfs, huge pages, kernel tuning). При сбое — провайдер меняет компонент.

**Фаза масштабирования (6+ мес):** Переход на colocation (собственное железо в DC). Дешевле при 2+ серверах, полный контроль над hardware lifecycle, горячие запчасти.

### Почему bare metal (dedicated/colo), а не cloud

| | Dedicated/Colo (256 GB) | OCI Dubai (256 GB) | Azure UAE North (256 GB) |
|---|---|---|---|
| Стоимость/мес | ~$400–600 (dedicated) / ~$325 (colo) | $724 | $1,766 |
| CAPEX | $0 (dedicated) / ~$2,500 (colo) | $0 | $0 |
| Тип | Bare metal | Virtual (shared) | Virtual (shared) |
| Noisy neighbors | Нет | Возможны | Возможны |
| Kernel tuning | Полный контроль | Ограничен | Ограничен |
| Huge pages | Да | Нет | Нет |
| RAM disk (tmpfs) | Полный контроль | Ограничен | Нет |
| Latency от Dubai users | <1 ms | <5 ms | <5 ms |
| Замена hardware | Провайдер (dedicated) / remote hands (colo) | Автоматически | Автоматически |

### Вариант A: Dedicated server (старт, первые 6 месяцев)

Аренда bare metal сервера у Dubai-провайдера. Ключевое требование: **256 GB RAM, NVMe, root access, private network**.

| Провайдер | Конфигурация | Стоимость/мес | Плюсы |
|---|---|---|---|
| AEserver (Dubai Production City) | 2× EPYC, 256 GB RAM, 2× 2TB NVMe | ~$400–600 | Tier 4 DC, поддержка 24/7 |
| ASPGulf (Dubai) | Аналогичная | ~$400–600 | 25+ лет в Dubai, мониторинг |
| GulfHost / Serverwala | Бюджетные варианты | ~$300–500 | Если подтверждают 256 GB RAM |

**Плюсы dedicated на старте:**
- $0 CAPEX (не покупаем сервер за $2,500)
- При hardware failure — провайдер меняет компонент (SLA 4–24 ч)
- Быстрый запуск: сервер готов за 1–3 дня
- Полный root access: tmpfs, huge pages, kernel tuning — всё работает
- Можно уйти в любой момент (месячный контракт)

**Минусы:**
- Дороже на $75–275/мес vs colocation (но нет CAPEX)
- Ограниченный выбор конфигураций (что есть у провайдера)
- Нет полного контроля над hardware lifecycle

### Вариант B: Colocation (масштабирование, 6+ месяцев)

Переход на собственное железо в DC. Оправдан при 2+ серверах, когда экономия покрывает CAPEX.

**Оптимальный вариант: Refurbished Dell PowerEdge R6525 (1U, dual-socket EPYC)**

| Компонент | Спецификация | Цена (USD) |
|---|---|---|
| Сервер (refurb) | Dell R6525, 2× EPYC 7413 (24c/48t), 128 GB DDR4 | ~$1,500 |
| Апгрейд RAM | +4× 32GB DDR4-3200 ECC RDIMM → 256 GB total | +$300–600 |
| NVMe SSD | 2× 2TB enterprise NVMe | +$300–600 |
| Запасной PSU | Redundant hot-swap 1400W | +$50–100 |
| **Итого** | **2× EPYC 7413, 256 GB DDR4, 4 TB NVMe** | **~$2,150–2,800** |

**Colocation в Дубае (1U, Tier 3–4 DC):**

| Провайдер | Стоимость/мес | Включено |
|---|---|---|
| AEserver (Tier 4, Dubai Production City) | ~$218–327 | Power, cooling, 1 Gbps, remote hands |
| ASPGulf (25+ лет в Dubai) | ~$245–408 | Power, cooling, monitoring, support |
| Equinix DX1/DX3 (premium) | ~$408–680 | Carrier-neutral, UAE-IX peering |

**Базовый расчёт colo: $250/мес colo + $75/мес cross-connect = ~$325/мес OPEX на сервер.**

**Когда переходить на colocation:**
- 2+ сервера (экономия OPEX покрывает CAPEX за 6–10 мес)
- Нужен полный контроль над hardware (горячие запчасти, специфичные конфигурации)
- Экономия: $75–275/мес на сервер vs dedicated rental

---

## 3. RAM Disk Architecture

### Гибридная схема: данные на tmpfs, WAL на NVMe

```
256 GB RAM распределение:
├── tmpfs /pgdata/base         — 140 GB  (таблицы + HNSW индексы)
├── NVMe  /pgdata/pg_wal       — на диске (WAL с fsync, durability)
├── PostgreSQL shared_buffers  — 32 GB   (internal caching)
├── work_mem × connections     — 8 GB    (200 conn × 40 MB)
├── OS + PostgreSQL processes  — 8 GB
├── Резерв для роста           — 68 GB
└── ИТОГО                      — 256 GB
```

**Почему не всё на tmpfs:** WAL на NVMe обеспечивает crash recovery. При сбое питания:
- Данные в tmpfs потеряны → восстанавливаются из WAL + replica
- WAL на NVMe сохранён → PostgreSQL применяет его автоматически при запуске
- Или pg_basebackup с Hetzner replica если WAL неполный

**Почему WAL на NVMe не bottleneck:** WAL — это sequential write. При 10K users генерируется ~1.1–1.4 MB/s WAL (зависит от длины response_description в артефактах). NVMe пишет последовательно на 3,000 MB/s. Утилизация <0.05%. Даже при bulk operations (REINDEX, массовый INSERT каталога) WAL throughput не превысит десятков MB/s.

### PostgreSQL конфигурация для RAM disk

```ini
# postgresql.conf — оптимизация для tmpfs + NVMe WAL

# Пути
data_directory = '/pgdata'          # tmpfs mount
# pg_wal символическая ссылка на /nvme/pg_wal (NVMe)

# Durability: fsync только для WAL (на NVMe)
fsync = on                          # WAL на NVMe → fsync имеет смысл
synchronous_commit = local          # WAL flush на NVMe перед ack клиенту
                                    # "local" = WAL записан на локальный NVMe (не ждёт replica)
                                    # Гарантирует: ack = данные на NVMe. Без этого возможен
                                    # сценарий: ack дошёл → app убрал из буфера → primary упал
                                    # до flush → пара потеряна и не replay'ится.
                                    # Для Tier C (embeddings/snippets) — SET LOCAL sync_commit=off
                                    # в транзакции async enrichment (не блокирует UX).
full_page_writes = on               # Нужен для корректности WAL-цепочки на реплике.
                                    # tmpfs не нуждается в защите от partial writes,
                                    # но реплика на Hetzner (NVMe) — нуждается.
                                    # full_page_writes пишутся в WAL на primary →
                                    # реплика их переигрывает. Без них: риск corrupted
                                    # pages при partial write на NVMe реплики.
                                    # Overhead минимален: WAL throughput 1.1 MB/s vs 3000 MB/s.

# Планировщик: всё в памяти
random_page_cost = 0.01             # random = sequential (нет диска)
seq_page_cost = 0.01
effective_cache_size = 140GB        # Размер tmpfs
effective_io_concurrency = 0        # Нет async I/O нужен

# Буферы
shared_buffers = 32GB               # PG internal caching (нужен даже с tmpfs)
work_mem = 40MB
maintenance_work_mem = 4GB          # Для REINDEX, VACUUM
wal_buffers = 64MB

# WAL
wal_level = replica                 # Нужен для streaming replication
max_wal_senders = 5                 # Primary → replica connections
wal_keep_size = 8GB                 # Запас: p95 WAL rate (10 MB/s burst) × max_outage (15 мин) = ~9 GB
                                    # 8 GB покрывает нормальный режим с запасом;
                                    # replication slots — основная защита от потери WAL
max_replication_slots = 5           # Слоты гарантируют что WAL не удалится пока replica не получила
                                    # Мониторить: pg_replication_slots → restart_lsn,
                                    # alert если WAL retention > 20 GB (NVMe не забился)
checkpoint_timeout = 15min
max_wal_size = 4GB

# Huge pages (bare metal only)
huge_pages = on                     # 2MB pages → меньше TLB misses

# Archiving (для PITR backup)
archive_mode = on
archive_command = 'test ! -f /nvme/wal_archive/%f && cp %p /nvme/wal_archive/%f'
# NB: локальный archive — staging/буфер. В production добавить upload
# в Object Storage (см. раздел 8 Backup стратегия):
# archive_command = 'cp %p /nvme/wal_archive/%f && aws s3 cp %p s3://...'
```

### Системная конфигурация

```bash
# /etc/fstab — tmpfs для PostgreSQL данных
tmpfs /pgdata tmpfs defaults,size=160G,noatime,mode=0700,uid=postgres,gid=postgres 0 0

# /etc/sysctl.conf — huge pages для shared_buffers
vm.nr_hugepages = 17000            # 32GB shared_buffers + overhead
vm.hugetlb_shm_group = 999         # postgres group ID
vm.swappiness = 1                   # Минимальный swap

# Символическая ссылка WAL на NVMe
# (делается при initdb или после)
ln -s /nvme/pg_wal /pgdata/pg_wal
```

### Производительность RAM disk vs alternatives

| Метрика | Cloud VM (OCI 128GB) | Bare Metal NVMe | Bare Metal + RAM disk |
|---|---|---|---|
| HNSW traversal (150 reads) | 2–5 ms (cached) / 50–100 ms (miss) | 1.5 ms | **~10 μs** |
| Heap fetch (20 reads) | 0.5–2 ms | 0.2 ms | **~1.4 μs** |
| Full hybrid search | 3–10 ms | 2–5 ms | **<100 μs** |
| 1,000 concurrent queries p95 | 30–80 ms | 10–25 ms | **<1 ms** |
| Noisy neighbor risk | Да | Нет | Нет |
| Virtualization overhead | ~5–15% | 0% | 0% |

---

## 4. Streaming Replication: как работает

### Нормальный режим

PostgreSQL записывает каждое изменение в WAL (Write-Ahead Log) перед применением к данным. Streaming replication непрерывно отправляет WAL-поток на replica-сервер:

```
Время 0.000s: Пользователь отправляет сообщение
Время 0.002s: PostgreSQL (Dubai, tmpfs) выполняет INSERT
              → WAL-запись создана
              → Данные записаны в tmpfs (мгновенно)
              → WAL пишется на NVMe (фоновый flush)
              → Клиенту возвращён ответ "OK"
Время 0.003s: WAL sender отправляет запись по сети в Hetzner
              ... 120ms через подводные кабели ...
Время 0.123s: PostgreSQL (Hetzner, NVMe) получает WAL
              → Записывает на NVMe (с fsync)
              → Применяет изменение (WAL replay)
```

**Async replication:** primary не ждёт подтверждения от replica → минимальная latency для клиента. Replica отстаёт на ~120ms (сетевая задержка Dubai → Helsinki).

### Replication lag: почему НЕ накапливается

Replication lag = сетевая задержка + очередь WAL + время apply.

Критическое наблюдение: **WAL replay на replica обычно быстрее чем исходная операция на primary.** Replica не выполняет логическую операцию (INSERT с перестройкой HNSW), а применяет готовые физические изменения страниц данных — sequential write на NVMe.

```
Primary (tmpfs): INSERT embedding → HNSW index update
  → Обход графа, вычисление расстояний, обновление связей
  → ~0.5–2ms на вставку

Replica (NVMe): применяет WAL
  → Получает готовые изменённые страницы
  → Sequential write на NVMe: ~0.01–0.1ms
  → Обычно быстрее primary для apply
```

**Когда lag может расти (условия, при которых «обычно быстрее» не работает):**
1. Пропускная способность сети: WAL 1.1 MB/s vs сеть 1 Gbps → запас 100× → не проблема при нормальной нагрузке
2. Тяжёлые запросы на replica конкурируют с WAL apply → не запускать аналитику на hot standby
3. Длинные транзакции на replica блокируют apply → настроить `max_standby_streaming_delay = 30s`
4. **Burst WAL** (REINDEX, массовый enrichment backfill, VACUUM FULL): кратковременный всплеск WAL может превысить IO capacity replica → lag растёт, но догоняет после burst
5. **Checkpoint на replica**: fsync dirty pages может замедлить apply → мониторить checkpoint_write_time
6. **NVMe throttling**: при длительной нагрузке (sustained writes > 1 GB) некоторые NVMe снижают скорость → тестировать sustained throughput при выборе дисков

**Мониторинг:**
```sql
-- На primary: текущий lag каждой replica
SELECT client_addr, state, replay_lag,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- Алерт если replay_lag > 5 секунд
```

### Failover при сбое primary

**Автоматический (Patroni + etcd):**

```
00:00.000  — Сервер в Дубае погас (сбой питания, hardware failure)
00:05.000  — Patroni на Hetzner: "Primary не отвечает 5 секунд"
00:10.000  — Patroni: "Подожду ещё 5 сек (может сеть моргнула)"
00:15.000  — Patroni: "Primary мёртв" → pg_ctl promote на Hetzner
00:15.500  — Patroni обновляет etcd → HAProxy/PgBouncer переключаются
00:16.000  — Система работает через Hetzner (latency 120ms вместо <1ms)

RTO (время простоя): ~15–30 секунд
RPO (потеря данных): 0 на уровне сообщений/пар — client-side verify-and-replay
                     восстанавливает потерянные пары (см. раздел 4.1).
                     Unconfirmed пары replay'ятся. Confirmed пары проверяются (safety net).
                     NB: RPO=0 для пар user+assistant в рамках буфера (10 пар, 60 сек confirmed).
                     Side-effects (async enrichment: embedding, snippet, memory_type) могут
                     отставать — backfill догоняет после restore.
```

**Ручной failover:**

```
00:00  — Monitoring обнаруживает: primary не отвечает
00:15  — Алерт в Telegram
01:00  — SSH на Hetzner: pg_ctl promote + DNS update
02:00  — Система работает

RTO: ~2 минуты
```

### Failback policy: failover auto, failback controlled

**Правило:** Failover — автоматический (Patroni). Failback на Dubai — **только вручную**, после проверки:

```
Условия для failback (все должны быть true):
  ✅ Dubai primary восстановлен и работает как replica
  ✅ replication_lag = 0 (полностью догнал)
  ✅ Health check green >= 10 минут непрерывно
  ✅ Нет degraded компонентов (RAM, NVMe, сеть)
  ✅ Инженер подтвердил вручную

Patroni config:
  failover_mode: automatic
  switchover_mode: manual    # Failback = switchover, всегда ручной
```

**Зачем:** защита от флаппинга. Если сеть между Dubai и Hetzner нестабильна, автоматический failback вызовет цикл promote/demote → corrupted state, потеря данных, split-brain.

### DCS: etcd quorum и защита от split-brain

**Проблема:** Patroni без кворума etcd = возможен split-brain (два primary одновременно). Это единственный реальный путь к corruption данных.

**Размещение 3 узлов etcd:**

| Узел | Локация | Тип | Зачем |
|------|---------|-----|-------|
| etcd-1 | Dubai (dedicated server) | Lightweight VM / контейнер на app-сервере | Локальный голос для primary |
| etcd-2 | Hetzner Helsinki (AX102) | Контейнер на replica-сервере | Голос replica |
| etcd-3 | Hetzner Helsinki (отдельный CPX11) | Dedicated lightweight | Кворум: 2 из 3 в Hetzner → при потере Dubai кворум сохраняется |

**Логика кворума:**
- Dubai жив + любой Hetzner → кворум есть, Dubai = primary (норма)
- Dubai упал → 2 Hetzner из 3 = кворум, Hetzner promoted (failover)
- Hetzner-сеть упала → Dubai один, нет кворума → **Patroni НЕ позволяет Dubai работать как primary** → fencing, система останавливается до восстановления связи
- Это правильное поведение: лучше остановка, чем split-brain

**Fencing:**
- Patroni использует leader key в etcd с TTL (default 30 сек)
- Если primary не может обновить leader key (потеря связи с etcd) → self-demote
- Watchdog (Linux hardware watchdog) как последняя линия: если Patroni завис — ребут сервера

**Приоритет:**
```yaml
# patroni.yml (Dubai)
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
  failover_priority: 2     # Высший приоритет — Dubai всегда preferred primary

# patroni.yml (Hetzner)  
tags:
  failover_priority: 1     # Ниже — только при DC-level outage Dubai
```

**Стоимость:** etcd-3 на CPX11 = ~€4/мес. Защита от split-brain — бесценна.

### 4.1. Client-Side Verify-and-Replay: нулевая потеря данных при failover

**Проблема:** при async replication последние 1–5 секунд WAL могут не доехать до Hetzner. Это 1–3 сообщения, которые юзер только что отправил/получил.

**Решение:** приложение хранит локальный буфер последних пар «запрос юзера + ответ UNDE» и переотправляет неподтверждённые пары после reconnect на новый primary.

**Почему пары, а не только сообщения юзера:**
Если переотправить только user message → LLM сгенерирует **другой** ответ (другие карточки, тон). Юзер видел одни рекомендации, а в истории будут другие. «Покажи второй вариант» сломается.

**Протокол:**

```
Нормальный режим:
  App → Dubai primary: message + UUID (client-generated)
  Dubai primary: INSERT → WAL flush на NVMe (synchronous_commit=local) → ack
  App: status "confirmed"

  Важно: ack означает "WAL на NVMe зафлашен" (synchronous_commit=local).
  Это гарантирует: если ack дошёл — данные на NVMe, и при soft crash
  (process crash без потери RAM) PostgreSQL восстановится сам.

Сбой (ack не дошёл):
  App → Dubai primary: message + UUID
  Dubai primary: INSERT... и упал (ack не дошёл)
  App: status остаётся "unconfirmed"

  ... 15-30 сек (Patroni failover) ...

  App → Hetzner (новый primary): POST /verify-and-replay
  {
    conversation_id: "conv-xyz",
    // Все unconfirmed пары
    unconfirmed: [
      { id: "uuid-user-3", role: "user", content: "..." },
      { id: "uuid-asst-3", role: "assistant", content: "...", cards: [...] }
    ],
    // Последние 3 confirmed пары (safety net)
    recent_confirmed_ids: ["uuid-user-1", "uuid-asst-1",
                           "uuid-user-2", "uuid-asst-2"]
  }

  Hetzner:
  1. Проверить recent_confirmed_ids:
     SELECT id FROM messages
     WHERE conversation_id=$1 AND id IN ($confirmed_ids)
     → Если какой-то confirmed id отсутствует — запросить полную пару от app

  2. Для unconfirmed пар:
     INSERT ... ON CONFLICT (conversation_id, id) DO NOTHING
     → Если role=assistant и message содержит consultant artifact (cards/structured payload)
       → построить response_description (template-based, тот же build_response_description)
       → включить в INSERT (sync, чтобы tsvector был корректен)
     → Если INSERT успешен: запустить async enrichment (embedding, snippet)
     → Если conflict: проверить embedding IS NOT NULL, дозапустить если нужно

  3. Ack → App: status "confirmed" для всех восстановленных пар
```

**Зачем проверять confirmed пары (safety net):**
Даже с `synchronous_commit=local`, при hard crash (reboot/питание) WAL на NVMe
может не успеть реплицироваться на Hetzner. Сценарий: ack дошёл → app пометил
"confirmed" → primary упал → WAL не долетел до Hetzner. Без проверки — пара
потеряна навсегда. Проверка последних 2–3 confirmed пар стоит один SELECT и
полностью закрывает эту дыру.

**Буфер в приложении:**
- Хранится в persistent storage (SQLite на iOS/Android, IndexedDB на web)
- Размер: последние 10 пар (покрывает 15–30 сек failover с запасом)
- **Confirmed пары хранятся ещё 60 секунд** после ack (для safety net при reconnect)
- Retry: ordered по timestamp, rate-limit 1 пара/сек/юзер, max 3 попытки
- После 3 неудачных попыток → voice-friendly: «Повторите, пожалуйста»

**Edge-cases:**
- Сбой ДО генерации ответа (есть user msg, нет assistant msg) → retry как обычный запрос, LLM генерирует новый ответ. Естественно — юзер и так ждал ответа.
- Юзер закрыл приложение до ack → буфер в persistent storage, проверка при следующем запуске.
- Медиа в ответах → URL на статические объекты (не временные ссылки), чтобы replay не ломал ссылки.

**Стоимость:** $0 инфраструктурно, ~80 строк кода в приложении + `/verify-and-replay` endpoint на сервере.

### Восстановление primary после сбоя

```
1. Дата-центр починил питание / заменён компонент
2. Сервер загрузился, tmpfs пустой

3. Restore — два варианта:

   Вариант A: Локальный snapshot (быстрый, рекомендуемый)
     → pg_basebackup snapshot хранится на NVMe в Dubai (отдельный раздел)
     → Копируем с локального NVMe в tmpfs: 50 GB за ~1 мин, 200 GB за ~4 мин
     → Догоняем по WAL с Hetzner (секунды, если snapshot свежий)
     → RTO: 5–10 минут

   Вариант B: С Hetzner replica (если локальный snapshot недоступен)
     → pg_basebackup -h hetzner-ip -D /pgdata -Fp -Xs -P
     → 1 Gbps: 50 GB за ~7 мин, 200 GB за ~27 мин
     → 100 Mbps (worst case): 50 GB за ~1 час, 200 GB за ~4 часа
     → RTO: 7 минут – 4 часа (зависит от канала)

4. Дубай запускается как replica, догоняет по WAL

5. Обратный switchover (failback — ТОЛЬКО вручную, см. Failback policy):
   → Проверить: lag = 0, health green >= 10 мин
   → Дубай снова primary, Hetzner снова replica
   → Latency возвращается к <1ms
```

**Локальный snapshot на NVMe в Dubai:**
- Автоматический `pg_basebackup` каждые 2 часа (cron на primary)
- Хранится на отдельном NVMe partition (не tmpfs, не WAL partition)
- Размер: 1 копия + сжатие (`--compress=lz4`) → ~30–50% от working set
- При 200 GB working set: ~60–100 GB на NVMe → стоимость: $0 (уже есть NVMe)
- **Выигрыш:** restore с локального NVMe в 10–50× быстрее чем с Hetzner

---

## 5. Горизонтальное шардирование

### Принцип: application-level sharding по user_id

Все запросы в Smart Context Architecture уже содержат `WHERE conversation_id = $X` (привязан к user). Один пользователь ВСЕГДА ходит на один шард:

```
Routing (в app server / Redis):
  user_id → hash(user_id) % N_shards → shard_id → connection string

Пример:
  User 1    → shard 0 → dubai-db-0.unde.internal
  User 2    → shard 1 → dubai-db-1.unde.internal
  User 3    → shard 0 → dubai-db-0.unde.internal
  User 4    → shard 3 → dubai-db-3.unde.internal
```

Routing-таблица в Redis. Простой application-level sharding, не Citus, не distributed SQL.

### Вместимость одного шарда

```
Сервер: 256 GB RAM, 140 GB available для tmpfs working set

Год 1: 2,500 users/шард
  HNSW: 2,500 × 7,500 emb × 3 KB = ~56 GB
  Heap + indexes: ~60 GB
  Total: ~116 GB ✓ (вписывается в 140 GB)

Год 3 (кумулятивно): ~1,500 users/шард
  HNSW: 1,500 × 22,500 emb × 3 KB = ~101 GB
  Heap + indexes: ~35 GB
  Total: ~136 GB ✓ (впритык)

→ Для 3-летнего горизонта: ~1,500–2,500 users на шард
→ Добавлять шарды по мере роста
```

### Roadmap шардирования

```
МЕСЯЦ 1–6:   1 шард  (до 5,000 users)
МЕСЯЦ 6–12:  2 шарда (до 10,000 users)
ГОД 2:       4 шарда (данные растут кумулятивно)
ГОД 3:       6–7 шардов
ГОД 5:       8–10 шардов (или апгрейд до 512 GB RAM → 5–6 шардов)

Триггер для нового шарда:
  SELECT pg_relation_size('idx_embeddings_hnsw') > 80 GB
  (50% от available working set)
```

### Ребалансировка при добавлении шарда

```
1. Подготовить новый сервер (пустой, dedicated или colocation)
2. Выбрать ~30% пользователей для переноса (новые, с меньшим объёмом данных)
3. Для каждого пользователя:
   a. Флаг в routing table: user_id → "migrating" (запросы в очередь)
   b. pg_dump данных пользователя → psql на новый шард
   c. Обновить routing: user_id → new_shard
   d. Удалить данные со старого шарда
   
   Время на пользователя: ~1–5 секунд (при ~24 MB данных)
   1,000 пользователей: ~1–2 часа

4. REINDEX на старом шарде (HNSW уменьшится, освободится RAM)
```

---

## 6. Полная архитектура

```
                            ┌──────────────┐
                            │   USERS      │
                            │   (Dubai)    │
                            └──────┬───────┘
                                   │
                            ┌──────▼───────┐
                            │  App Server   │
                            │  + Redis      │
                            │  (routing     │
                            │   table)      │
                            └──┬──┬──┬──┬──┘
                               │  │  │  │
             ┌─────────────────┘  │  │  └─────────────────┐
             │                    │  │                      │
  ┌──────────▼────┐   ┌──────────▼──▼──┐      ┌───────────▼────┐
  │ DUBAI SHARD 0  │   │ DUBAI SHARD 1  │      │ DUBAI SHARD N  │
  │ 256GB RAM      │   │ 256GB RAM      │ ...  │ 256GB RAM      │
  │ tmpfs data     │   │ tmpfs data     │      │ tmpfs data     │
  │ NVMe WAL       │   │ NVMe WAL       │      │ NVMe WAL       │
  │ ~2,500 users   │   │ ~2,500 users   │      │ ~2,500 users   │
  │ $325/мес colo  │   │ $325/мес colo  │      │ $325/мес colo  │
  └──────┬─────────┘   └──────┬─────────┘      └──────┬─────────┘
         │                    │                        │
         │   async WAL streaming (120ms)               │
         │                    │                        │
  ┌──────▼────────────────────▼────────────────────────▼──────────┐
  │                    HETZNER HELSINKI                             │
  │                                                                │
  │  ┌──────────────┐  ┌──────────────┐      ┌──────────────┐    │
  │  │ REPLICA S0    │  │ REPLICA S1    │ ...  │ REPLICA SN    │    │
  │  │ AX102 128GB   │  │ AX102 128GB   │      │ AX102 128GB   │    │
  │  │ NVMe, fsync   │  │ NVMe, fsync   │      │ NVMe, fsync   │    │
  │  │ Hot standby   │  │ Hot standby   │      │ Hot standby   │    │
  │  │ $128/мес      │  │ $128/мес      │      │ $128/мес      │    │
  │  └───────────────┘  └───────────────┘      └───────────────┘    │
  │                                                                │
  │  ┌──────────────────────────────────────────────────────┐     │
  │  │ ANALYTICS REPLICA                                     │     │
  │  │ AX162-R: 256GB DDR5, EPYC 48 cores, $245/мес        │     │
  │  │ Cascading replication от всех шардов                   │     │
  │  │ B2B отчёты, ML, поведенческий анализ                  │     │
  │  │ FDW/dblink для cross-shard запросов                   │     │
  │  └──────────────────────────────────────────────────────┘     │
  │                                                                │
  │  ┌──────────────────────────────────────────────────────┐     │
  │  │ OBJECT STORAGE (S3-compatible)                        │     │
  │  │ pg_basebackup каждые 6 часов от каждого шарда        │     │
  │  │ WAL archive (непрерывный) — Point-in-Time Recovery   │     │
  │  │ Tombstone registry (GDPR soft/hard deletes)           │     │
  │  │ $20–40/мес                                            │     │
  │  └──────────────────────────────────────────────────────┘     │
  └────────────────────────────────────────────────────────────────┘
```

---

## 7. Стоимость по фазам

### Фаза 1: 0–5,000 users (месяц 1–6) — Dedicated server

| Компонент | Стоимость/мес |
|---|---|
| Dubai: 1 dedicated server (256 GB RAM, аренда) | $400–600 |
| Hetzner: 1 hot standby replica (AX102) | $128 |
| Hetzner: etcd-3 (CPX11) | €4 |
| Hetzner Object Storage | $10 |
| **ИТОГО** | **$542–742/мес** |
| CAPEX | **$0** |

### Фаза 2: 5,000–10,000 users (месяц 6–12) — Переход на colocation

Экономика: 2 dedicated сервера = $800–1200/мес. 2 colo сервера = $650/мес + $5,000 CAPEX.
Payback period: 3–9 месяцев. **При уверенности в росте — переходить.**

| Компонент | Стоимость/мес |
|---|---|
| Dubai: 2 сервера colocation × $325 | $650 |
| Hetzner: 2 replicas × $128 | $256 |
| Hetzner: Analytics replica (AX162-R) | $245 |
| Hetzner Object Storage | $20 |
| **ИТОГО** | **$1,171/мес** |
| CAPEX: 2 сервера | ~$5,000 (разово) |

*Альтернатива: остаться на dedicated ($800–1200/мес, $0 CAPEX) если рост неопределённый.*

### Фаза 3: 10,000 users, год 2 (кумулятивный рост данных)

| Компонент | Стоимость/мес |
|---|---|
| Dubai: 4 сервера colocation × $325 | $1,300 |
| Hetzner: 4 replicas × $128 | $512 |
| Hetzner: Analytics replica | $245 |
| Hetzner Object Storage | $30 |
| **ИТОГО** | **$2,087/мес** |
| CAPEX: 3-й и 4-й серверы | ~$5,000 (разово) |

### Фаза 4: 10,000 users, год 3–5

| Компонент | Стоимость/мес |
|---|---|
| Dubai: 6–7 серверов × $325 | $2,275 |
| Hetzner: 6–7 replicas × $128 | $896 |
| Hetzner: Analytics replica | $245 |
| Hetzner Object Storage | $40 |
| **ИТОГО** | **$3,456/мес** |

### Сравнение альтернатив (Фаза 3, год 2, 4 сервера)

| | Colocation | Dedicated rental | OCI Dubai | Azure UAE North |
|---|---|---|---|---|
| Primary серверы | $1,300 | $1,600–2,400 | $2,896 | $7,064 |
| Replicas | $512 | $512 | $2,896 | $7,064 |
| Analytics | $245 | $245 | $724 | $1,766 |
| Storage/backup | $30 | $30 | $100 | $200 |
| **ИТОГО/мес** | **$2,087** | **$2,387–3,187** | **$6,616** | **$16,094** |
| **ИТОГО/год** | **$25,044** | **$28,644–38,244** | **$79,392** | **$193,128** |
| CAPEX | $10,000 | $0 | $0 | $0 |

**Экономия bare metal vs cloud: $41K–168K в год** (на фазе 3). Colocation дешевле dedicated на $3,600–13,200/год, но требует $10K CAPEX.

---

## 8. Backup стратегия

### Уровни защиты данных

```
Уровень 1: WAL на NVMe (local, ограниченный crash recovery)
  → Защищает от: PostgreSQL process crash, OOM kill, soft failures БЕЗ потери RAM
  → НЕ защищает от: reboot, сбой питания, hardware failure (tmpfs = пустой диск)
  → При потере RAM: WAL без pgdata бесполезен → failover на Hetzner (уровень 2)
  → RPO: 0 только для soft crashes; для hard crashes — см. уровень 2

Уровень 2: Streaming replication на Hetzner (real-time)
  → Защищает от: полный отказ сервера, сбой питания, hardware failure
  → RPO: 0 (client-side verify-and-replay: unconfirmed replay + confirmed проверка)
  → RTO: 15–30 секунд (Patroni) или ~2 минуты (ручной)

Уровень 3: WAL archive в Object Storage (continuous)
  → Защищает от: потеря и primary И replica одновременно
  → Позволяет: Point-in-Time Recovery на любой момент
  → RPO: до последнего archived WAL segment (~5 минут)

Уровень 4: pg_basebackup в Object Storage (periodic)
  → Полная копия базы каждые 6 часов
  → Защищает от: catastrophic loss всех серверов
  → RPO: до 6 часов (между бэкапами)
  → Хранение: 7 дней daily + 4 недели weekly + 3 месяца monthly
```

### Скрипты бэкапа

```bash
# На Hetzner hot standby replica — crontab

# Каждые 6 часов: full basebackup → Object Storage
0 */6 * * * pg_basebackup -D - -Ft -z | \
  aws s3 cp - s3://unde-backups/shard-0/base/$(date +\%Y\%m\%d_\%H\%M).tar.gz \
  --endpoint-url https://fsn1.your-objectstorage.com

# Непрерывно: WAL archiving (в postgresql.conf)
# archive_command = 'aws s3 cp %p s3://unde-backups/shard-0/wal/%f --endpoint-url ...'

# Еженедельно: cleanup старых бэкапов
0 3 * * 0 python3 /opt/scripts/cleanup_old_backups.py --keep-daily=7 --keep-weekly=4
```

### GDPR: Tombstone registry

```
Tombstone registry хранится в:
  1. Production DB (primary) — в отдельной таблице tombstone_registry
  2. Object Storage — копия для post-restore применения

После восстановления из бэкапа:
  → Запустить apply_deletions.sql
  → Применяет soft/hard deletes из tombstone_registry
  → Гарантирует GDPR compliance даже при restore из старого бэкапа
```

---

## 9. Мониторинг

### Ключевые метрики (Prometheus + Grafana)

```yaml
# Критические алерты:

# RAM disk utilization
- alert: TmpfsUsageHigh
  expr: (node_filesystem_size_bytes{mountpoint="/pgdata"} - node_filesystem_avail_bytes{mountpoint="/pgdata"}) / node_filesystem_size_bytes{mountpoint="/pgdata"} > 0.85
  for: 5m
  annotations:
    summary: "tmpfs usage > 85% — время добавлять шард"

# HNSW index size (триггер для шардирования)
- alert: HnswIndexLarge
  expr: pg_relation_size_bytes{relname=~".*hnsw.*"} > 85899345920  # 80 GB
  annotations:
    summary: "HNSW index > 80 GB — планировать новый шард"

# Replication lag
- alert: ReplicationLagHigh
  expr: pg_replication_lag_seconds > 5
  for: 2m
  annotations:
    summary: "Replication lag > 5s — возможен снежный ком"

# Replica down
- alert: ReplicaDown
  expr: pg_up{instance=~"hetzner.*"} == 0
  for: 1m
  annotations:
    summary: "Hetzner replica недоступна — failover скомпрометирован"

# Client replay rate (spike = recent failover)
- alert: ReplayRateHigh
  expr: rate(replay_requests_total[5m]) > 10
  for: 2m
  annotations:
    summary: "Высокий поток replay-запросов — проверить failover status"

# Enrichment backfill (replayed messages missing embeddings)
- alert: EnrichmentBackfillHigh
  expr: rate(replay_enrichment_backfill_total[5m]) > 5
  for: 5m
  annotations:
    summary: "Много replayed сообщений без enrichment — проверить async pipeline"

# Replication slot WAL retention (NVMe не забился)
- alert: ReplicationSlotWalHigh
  expr: pg_replication_slots_pg_wal_lsn_diff > 21474836480  # 20 GB
  for: 5m
  annotations:
    summary: "Replication slot удерживает > 20 GB WAL — replica отстала или отключена, NVMe в опасности"

# etcd health
- alert: EtcdUnhealthy
  expr: etcd_server_has_leader == 0
  for: 30s
  annotations:
    summary: "etcd потерял leader — Patroni не может делать failover, risk split-brain"
```

### SQL мониторинг replication

```sql
-- На primary: статус всех реплик
SELECT client_addr, state, 
       sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
       replay_lag
FROM pg_stat_replication;

-- Replication slots: WAL retention (не забить NVMe)
SELECT slot_name, active,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_wal_bytes,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
-- Alert если retained_wal > 20 GB → replica отключена слишком долго → DROP SLOT или починить

-- Размер HNSW индексов (триггер для шардирования)
SELECT schemaname, indexname, 
       pg_size_pretty(pg_relation_size(indexname::regclass)) AS size
FROM pg_indexes 
WHERE indexdef LIKE '%hnsw%'
ORDER BY pg_relation_size(indexname::regclass) DESC;

-- Использование tmpfs
-- (через pg_stat_file или системный мониторинг)
```

---

## 10. Пошаговый план запуска

### Месяц 1: Аренда и подготовка

1. Арендовать dedicated server в Дубае (256 GB RAM, 2× NVMe) — $400–600/мес
   - Требования: root access, private network, 1 Gbps uplink
   - Провайдеры: AEserver, ASPGulf, GulfHost
2. Заказать Hetzner AX102 (hot standby replica) — $128/мес
3. Подготовить Ansible playbooks для bootstrap серверов

### Месяц 2: Развёртывание

4. Проверить сервер (fio для NVMe, stress-ng для RAM, network latency test)
5. Установить Ubuntu 24.04 + PostgreSQL 17 + pgvector
6. Настроить tmpfs + WAL на NVMe + streaming replication
7. Настроить Patroni + etcd для автоматического failover:
   - etcd-1: контейнер на Dubai app-сервере
   - etcd-2: контейнер на Hetzner AX102
   - etcd-3: отдельный CPX11 Hetzner (~€4/мес)
   - Patroni: failover_priority=2 (Dubai), 1 (Hetzner)
   - Replication slot: создать, мониторить WAL retention
8. Настроить Prometheus/Grafana мониторинг (включая etcd_server_has_leader)

### Месяц 3: Миграция и запуск

9. Перенести данные с текущего Hetzner
10. Переключить production трафик на Dubai primary
11. Мониторинг 2 недели: latency, RAM usage, replication lag
12. **Тестирование failover + client verify-and-replay:** симулировать kill primary при burst 100 TPS, проверить: unconfirmed пары replayed, confirmed пары verified (safety net), enrichment backfill отработал, контекст («покажи второй вариант») не сломан
13. **Тестирование kill -9 во время batch enrichment:** kill -9 postgres процесс во время массового enrichment → failover → replay → проверить: embedding/snippet не остаются NULL (backfill догоняет). Самый tricky участок.
14. Настроить cron для локального basebackup на NVMe (каждые 2 часа, --compress=lz4)

### Месяц 6: Масштабирование (при достижении 5,000 users)

14. **Решение: остаться на dedicated или перейти на colocation**
    - При уверенном росте (5K+ users, 2+ сервера нужны) → покупка серверов + colocation
    - При неопределённости → второй dedicated server (дороже, но $0 CAPEX)
15. Добавить 2-й сервер для Dubai + 2-й AX102 для Hetzner
16. Добавить Analytics replica (AX162-R)
17. Ребалансировать пользователей между шардами

### Далее: по мере роста

17. Добавлять шарды при HNSW index > 80 GB на шарде
18. Рассмотреть апгрейд до 512 GB RAM серверов (год 2–3)
19. При выходе за 10K users — пересмотреть архитектуру

### Runbook: плановое обслуживание и failover

**Плановые ребуты** (kernel update, firmware, замена компонента):
- Всегда через failover на Hetzner → maintenance → rebuild → switchover обратно
- Окно: 02:00–04:00 GST (минимальный трафик Dubai)
- Уведомление юзерам: «техническое обслуживание, возможна пауза 30 сек»
- После switchover обратно: проверить replay_requests_total = 0, replication_lag < 1s

**Тестирование failover (ежемесячно в staging):**
- Burst 100 TPS (locust) + kill primary
- Проверить: RTO < 30 сек, все unconfirmed пары replayed, confirmed safety net отработал
- Проверить enrichment backfill: embedding и snippet не NULL для replayed сообщений
- Проверить контекстную целостность: «покажи второй вариант» работает после replay
- **kill -9 postgres во время batch enrichment** → failover → verify backfill догоняет (embedding/snippet не NULL)
- **Проверить etcd:** после failover — etcd leader есть, нет split-brain, Patroni state consistent
- **Проверить replication slots:** после restore Dubai — slot recreated, WAL retention < 1 GB

---

## 11. Ключевые принципы

1. **RAM — единственный bottleneck.** CPU, диск, сеть — всего с запасом 50–100×. Масштабирование = добавление RAM через новые шарды.

2. **Данные на tmpfs, WAL на NVMe.** Максимальная скорость чтения (наносекунды), durability через WAL и replication.

3. **Каждый шард автономен.** Свой primary в Дубае, своя replica в Hetzner, свой бэкап. Отказ одного шарда не влияет на остальных.

4. **Hetzner — дешёвый "страховочный" слой.** $128/мес за 128 GB replica с full durability. Failover за 15–30 секунд.

5. **Application-level sharding.** Простой hash(user_id) % N в Redis. Никакой магии distributed SQL.

6. **Шардирование инкрементальное.** Начинаем с 1 шарда, добавляем по мере необходимости. Триггер: HNSW index > 80 GB.

7. **Dedicated → colocation по мере роста.** Старт на арендованном dedicated ($400–600/мес, $0 CAPEX). Переход на colocation при 2+ серверах ($325/мес + CAPEX). Экономия bare metal vs cloud: $41K–168K/год на фазе 3.

8. **Client-side verify-and-replay для нулевой потери данных.** Приложение хранит буфер последних пар (запрос + ответ) в persistent storage. При failover — проверяет наличие последних confirmed пар (safety net) + идемпотентный replay unconfirmed. RPO = 0 на уровне пар без дополнительных серверов. `synchronous_commit=local` для ack (WAL на NVMe), `off` для async enrichment. Решай на уровне приложения то, что не требует решения на уровне инфраструктуры.

9. **Failover auto, failback manual.** Patroni переключает на Hetzner автоматически. Возврат на Dubai — только вручную, после подтверждения здоровья (lag=0, health green ≥ 10 мин). Защита от флаппинга при нестабильной сети.

10. **etcd quorum = защита от split-brain.** 3 узла etcd (1 Dubai + 2 Hetzner), кворум 2/3. При потере Dubai — Hetzner имеет кворум для failover. При потере Hetzner-сети — Dubai без кворума, self-demote. Лучше остановка, чем два primary.

11. **Локальный snapshot на NVMe для быстрого restore.** basebackup каждые 2 часа на отдельный NVMe partition. Restore с локального диска в 10–50× быстрее чем с Hetzner. RTO: 5–10 минут вместо часов.
