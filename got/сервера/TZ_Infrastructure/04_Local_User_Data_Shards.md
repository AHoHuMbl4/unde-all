# UNDE Infrastructure — Local User Data Shards

*Часть [TZ Infrastructure v7.2](07_Server_Layout_v7.md). Primary DB: Chat History + User Knowledge + Persona.*

---

## 14. LOCAL USER DATA SHARDS (обновлено v7.2 — локальные серверы вместо Dubai bare metal)

> **Архитектурное решение:** Chat History и User Knowledge объединены на одном шарде. Primary на локальном сервере (16 vCPU / 32 GB RAM, NVMe SSD). Dedicated (Xeon E3-1275V6, 64 GB RAM, 2×NVMe 512 GB) — hot standby replica. Связь через WireGuard туннели. Это решение из документов UNDE_Infrastructure_BD и UNDE_Smart_Context_Architecture.

### Информация (Primary — Локальный сервер)

| Параметр | Значение |
|----------|----------|
| **Hostname** | local-shard-0 |
| **WireGuard IP** | 10.2.0.10 |
| **Локация** | Локально (рядом с юзерами, <5ms RTT) |
| **Тип** | VPS / Cloud (провайдер определяется по локации) |
| **vCPU** | 16 |
| **RAM** | 32 GB |
| **Disk** | NVMe SSD |
| **OS** | Debian 12 / Ubuntu 24.04 LTS |

### Информация (Replica — Hetzner Helsinki)

| Параметр | Значение |
|----------|----------|
| **Hostname** | shard-replica-0 |
| **Private IP** | 10.1.1.10 |
| **Тип** | Dedicated (Xeon E3-1275V6, 64 GB, 2×NVMe 512 GB) |
| **vCPU** | 4 |
| **RAM** | 16 GB |
| **Стоимость** | €39/мес |

### RAM Architecture (Primary, 32 GB)

```
32 GB RAM распределение:
├── PostgreSQL shared_buffers  — 8 GB    (25% RAM)
├── OS page cache              — ~16 GB  (effective_cache_size 24 GB включая shared_buffers)
├── work_mem × connections     — 4 GB    (100 conn × 40 MB)
├── OS + PostgreSQL processes  — 4 GB
└── ИТОГО                      — 32 GB
```

**NVMe SSD вместо tmpfs:** Данные на NVMe, hot working set в OS page cache. При стабильной нагрузке (500–800 юзеров/шард) весь working set (~11–18 GB HNSW + heap) помещается в effective_cache_size + shared_buffers. Кеш тёплый — деградация только при cold start или spike.

### Назначение

Единый шард хранит **все данные юзера** — Chat History и User Knowledge:

**Chat History:**
- Один непрерывный диалог на юзера (не обнуляется)
- Каждое сообщение: роль, текст, **embedding (pgvector)**, **memory_type**, **memory_confidence**, **memory_snippet**, **response_description**, **reply_to_id**
- **Semantic Retrieval** — Hybrid Search (vector + FTS) по всей истории диалога
- **64 hash-партиции** по conversation_id для partition pruning
- Используется для формирования ContextPack (эпизоды из прошлого)
- Используется пайплайном User Knowledge для извлечения фактов

**User Knowledge:**
- Структурированные факты о юзере (стиль, размеры, бюджет, бренды)
- Зашифрованы AES-256-GCM (application-level envelope encryption)
- Ключи шифрования (DEK) в таблице user_keys на том же шарде

### Почему локальный сервер (а не Helsinki)

- **Latency:** <5ms для юзеров (vs 120ms до Helsinki)
- **1 сервер = 1 задача:** Шард изолирован на отдельном сервере
- **Масштабирование:** Добавить шард = добавить сервер 16 vCPU / 32 GB (~$50–80/мес)
- **NVMe SSD + page cache:** 2–5 ms hybrid search (hot cache) — достаточно для voice-first UX
- **Нет SPOF:** Падение одного шарда ≠ падение всего (vs всё на одном bare metal)

### Почему Chat History + User Knowledge на одном шарде

- Один сервер на юзера — один запрос для ContextPack
- Нет cross-server joins при сборке контекста
- GDPR hard delete: каскад на шарде + tombstone в Production DB
- Application-level sharding: hash(user_id) % N → shard_id

### Схема базы данных — Chat History (обновлённая, pgvector + FTS + партиционирование)

```sql
-- DATABASE: unde_shard (содержит и Chat History, и User Knowledge)

-- Расширения
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    message_count INTEGER DEFAULT 0,
    -- Knowledge Staging Pipeline: трекинг batch extraction
    last_extraction_at TIMESTAMPTZ,
    pending_extraction_count INTEGER DEFAULT 0,
    UNIQUE(user_id)  -- один диалог на юзера
);

-- Партиционированная таблица сообщений
CREATE TABLE messages (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL,
    
    role VARCHAR(20) NOT NULL,       -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,
    
    -- Semantic search (pgvector)
    -- NB: dim (1024) соответствует Cohere/Voyage. При смене провайдера:
    -- ALTER TABLE messages ALTER COLUMN embedding TYPE vector(NEW_DIM) + re-embed all.
    embedding vector(1024),
    is_embeddable BOOLEAN DEFAULT FALSE,
    is_forgotten BOOLEAN DEFAULT FALSE,
    
    -- Memory classification (тип + уверенность → скорость затухания)
    memory_type VARCHAR(20) DEFAULT 'general',
        -- emotion | preference | fact | event | general
    memory_confidence FLOAT DEFAULT 0.5,
        -- 0.0..1.0, определяется по intensifiers/softeners
    
    -- Precomputed snippet (0ms в рантайме вместо 400ms LLM-компрессии)
    memory_snippet TEXT,
        -- "В IMAX было холодно от кондиционера → брать тёплый слой"
    
    -- Consultant Response Description Layer
    -- Backend-only текстовое описание артефакта консультанта.
    -- В UI не показывается. Генерируется SYNC template-based при INSERT (~0.1ms).
    -- NULL для обычных текстовых ответов без артефакта.
    response_description TEXT,
    
    -- Ссылка на assistant message, к которому относится реакция юзера.
    -- Заполняется у user-сообщений. Не FK (из-за партиционирования).
    -- Серверная эвристика: последний артефакт за 10 мин, если клиент не указал явно.
    -- Защита от неоднозначности: если 2+ артефакта за <60 сек — reply_to_id = NULL (LLM уточнит).
    reply_to_id UUID,
    
    -- Full-text search
    -- NB: 'simple' config = точные токены без морфологии.
    -- FTS отвечает за имена/бренды/цифры, семантика — через embeddings.
    -- Включает response_description для поиска по атрибутам артефактов.
    tsv tsvector GENERATED ALWAYS AS (
        to_tsvector('simple', content || ' ' || COALESCE(response_description, ''))
    ) STORED,
    
    -- Метаданные
    media_urls JSONB,
    mood_frame JSONB,
    input_type VARCHAR(20),          -- 'voice', 'text'
    duration_ms INTEGER,
    model_used VARCHAR(100),
    
    -- Enrichment retry tracking (Фикс 14: Enrichment TTL Guarantee)
    -- При сбое embedding → retry_count += 1; после 3 неудач → orphan alert
    enrichment_retry_count INTEGER DEFAULT 0,
    
    -- GDPR
    deleted_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    PRIMARY KEY (conversation_id, id)
) PARTITION BY HASH (conversation_id);

-- 64 партиции (достаточно для 800+ юзеров на шард)
DO $$
BEGIN
    FOR i IN 0..63 LOOP
        EXECUTE format(
            'CREATE TABLE messages_p%s PARTITION OF messages 
             FOR VALUES WITH (MODULUS 64, REMAINDER %s)',
            lpad(i::text, 2, '0'), i
        );
    END LOOP;
END $$;

-- HNSW: partial index только для embeddable, не-forgotten сообщений
CREATE INDEX idx_messages_embedding 
    ON messages USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64)
    WHERE role = 'user' AND is_embeddable = TRUE 
      AND is_forgotten = FALSE AND embedding IS NOT NULL;

CREATE INDEX idx_messages_tsv 
    ON messages USING gin (tsv);

CREATE INDEX idx_messages_conversation_time 
    ON messages(conversation_id, created_at DESC);

CREATE INDEX idx_messages_retrieval
    ON messages(conversation_id, role, is_embeddable, is_forgotten)
    WHERE role = 'user' AND is_embeddable = TRUE AND is_forgotten = FALSE;

CREATE INDEX idx_conversations_user ON conversations(user_id);
```

**Результат:** при запросе с `WHERE conversation_id = $2` PostgreSQL автоматически обращается только к 1 из 64 партиций. HNSW-индекс в этой партиции содержит ~190K записей (12M / 64) вместо 12M — поиск на порядки быстрее.

**Идентификация сообщений:** PK = `(conversation_id, id)` — составной из-за партиционирования. Во всех системах — UI, tombstone registry, логи, API — оперируем **парой (conversation_id, message_id)**, не одним id.

### Схема базы данных — User Knowledge (на том же шарде)

```sql
-- Ключи шифрования юзеров
CREATE TABLE user_keys (
    user_id UUID PRIMARY KEY,
    encrypted_dek BYTEA NOT NULL,      -- DEK зашифрованный мастер-ключом
    created_at TIMESTAMPTZ DEFAULT NOW(),
    rotated_at TIMESTAMPTZ
);

-- Знания о юзере (зашифрованы AES-256-GCM)
-- Обновлено: новые колонки из UNDE_Knowledge_Staging_Pipeline.md (Фиксы 2, 3, 5, 11, 15)
CREATE TABLE user_knowledge (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES user_keys(user_id),
    
    -- Зашифрованные данные
    encrypted_data BYTEA NOT NULL,
    iv BYTEA NOT NULL,                  -- Initialization vector
    auth_tag BYTEA NOT NULL,            -- Authentication tag
    
    -- Метаданные (НЕ зашифрованы, для индексации)
    knowledge_type VARCHAR(50) NOT NULL,
        -- GUARANTEED (попадают в User Knowledge):
        -- 'body_params', 'budget', 'allergy', 'hard_ban',
        -- 'onboarding_style', 'life_event'
        -- SOFT (НЕ попадают, остаются в Chat History):
        -- 'emotional_patterns', 'behavior_patterns',
        -- 'color_preferences', 'brand_preferences'
    
    -- Ключ факта внутри типа (Фикс 2: supersede по (type, key))
    -- body_params → 'size'; budget → 'general';
    -- allergy → extracted value ('nickel', 'wool');
    -- hard_ban → extracted value ('open_shoulders', 'leather');
    -- life_event → идентификатор ('wedding_sister', 'vacation_july')
    knowledge_key VARCHAR(100) NOT NULL,
    
    -- Версионирование
    version INTEGER DEFAULT 1,
    extracted_from VARCHAR(50),          -- 'instant_pattern', 'batch_extraction', 'onboarding', 'explicit_input'
    confidence DECIMAL(3,2),
    is_active BOOLEAN DEFAULT TRUE,     -- для soft forget
    
    -- Evidence pointers (Epistemic Contract, Правило 2):
    -- Каждый факт указывает на сообщения-доказательства (±1 span)
    evidence_message_ids UUID[] NOT NULL DEFAULT '{}',
    
    -- Спорный статус (Фикс 11: Memory Correction Loop)
    -- TRUE = юзер выразил неоднозначное несогласие ("с чего ты взял?")
    -- Промпт: "если факт disputed — мягко уточни, не утверждай"
    is_disputed BOOLEAN DEFAULT FALSE,
    
    -- TTL для life_event (Фикс 3: expires_at)
    -- Просроченные → is_active = FALSE (cron, ежедневно)
    expires_at TIMESTAMPTZ,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_knowledge_user_type ON user_knowledge(user_id, knowledge_type);
CREATE INDEX idx_knowledge_updated ON user_knowledge(updated_at DESC);

-- GIN индекс для быстрого поиска по evidence (cascade forget, Фикс 15)
CREATE INDEX idx_knowledge_evidence_gin 
    ON user_knowledge USING GIN (evidence_message_ids);

-- Уникальность: один активный факт на (user, type, key) — Фикс 2
CREATE UNIQUE INDEX idx_knowledge_active_unique 
    ON user_knowledge(user_id, knowledge_type, knowledge_key) 
    WHERE is_active = TRUE;

-- Enforce Epistemic Contract Правило 2:
-- Каждый факт должен иметь evidence, кроме onboarding
ALTER TABLE user_knowledge ADD CONSTRAINT chk_evidence_required
    CHECK (
        cardinality(evidence_message_ids) > 0
        OR extracted_from = 'onboarding'
    );

-- === Knowledge Staging Pipeline: Supersede Trigger (Фикс 2) ===
-- BEFORE INSERT: деактивировать предыдущие записи с тем же (type, key)
-- ПЕРЕД вставкой новой строки, иначе UNIQUE partial index
-- idx_knowledge_active_unique отклонит INSERT
CREATE OR REPLACE FUNCTION supersede_knowledge()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE user_knowledge
    SET is_active = FALSE,
        updated_at = NOW()
    WHERE user_id = NEW.user_id
      AND knowledge_type = NEW.knowledge_type
      AND knowledge_key = NEW.knowledge_key
      AND is_active = TRUE;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_supersede_knowledge
    BEFORE INSERT ON user_knowledge
    FOR EACH ROW
    EXECUTE FUNCTION supersede_knowledge();

-- === Knowledge Staging Pipeline: Memory Correction Log (Фикс 11) ===
CREATE TABLE memory_correction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    trigger_message_id UUID NOT NULL,       -- user: "нет, я не люблю Zara"
    corrected_message_id UUID,              -- assistant: "Ты же любишь Zara" (обязательно при "с чего ты взял")
    deactivated_knowledge_id UUID,          -- если факт в UK → deactivated
    disputed_knowledge_id UUID,             -- если факт → disputed (не deactivated)
    correction_type VARCHAR(30),            -- 'user_denied', 'wrong_subject', 'outdated', 'ambiguous'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_correction_user ON memory_correction_log(user_id, created_at DESC);

-- === Knowledge Staging Pipeline: Extraction Log (Фаза 2) ===
CREATE TABLE knowledge_extraction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    triggered_by VARCHAR(30) NOT NULL,      -- 'session_gap', 'pending_threshold', 'cron'
    messages_analyzed INTEGER NOT NULL,
    deltas_applied INTEGER DEFAULT 0,
    llm_model VARCHAR(50),
    input_tokens INTEGER,
    output_tokens INTEGER,
    duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_extraction_user ON knowledge_extraction_log(user_id, created_at DESC);

-- === Persona Agent: Relationship Stage (persisted state) ===
CREATE TABLE relationship_stage (
    user_id          UUID PRIMARY KEY,
    stage            INTEGER DEFAULT 0,         -- 0, 1, 2, 3
    stage_updated_at TIMESTAMPTZ DEFAULT NOW(),
    sessions_count   INTEGER DEFAULT 0,
    total_exchanges  INTEGER DEFAULT 0,
    positive_signals_count INTEGER DEFAULT 0,
    last_active_at   TIMESTAMPTZ DEFAULT NOW()
);
-- Stage upgrade: sessions + exchanges + positive signals
-- Stage downgrade: 45-90 дней без активности (stage-dependent)

-- === Persona Agent: Temp Blocks ===
CREATE TABLE persona_temp_blocks (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID NOT NULL,
    key         VARCHAR(50) NOT NULL,           -- 'cultural_ref', 'humor', etc.
    until       TIMESTAMPTZ NOT NULL,
    reason      VARCHAR(100) NOT NULL,          -- 'cultural_ref_rejected'
    signal_id   UUID,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_temp_blocks_user ON persona_temp_blocks(user_id);
-- Max 20 per user, lazy + cron cleanup

-- === Persona Agent: Signal Daily Deltas (momentum tracking) ===
CREATE TABLE signal_daily_deltas (
    user_id     UUID NOT NULL,
    field       VARCHAR(50) NOT NULL,           -- canonical field name
    date        DATE NOT NULL DEFAULT CURRENT_DATE,
    total_delta FLOAT DEFAULT 0,
    PRIMARY KEY (user_id, field, date)
);
-- TTL: 7 дней (для отладки), cron cleanup
```

### Hybrid Search с тематическим Temporal Decay и Confidence

```sql
WITH vector_results AS (
    -- Vector search: только user-сообщения (эмбеддинги только у них)
    SELECT id, content, memory_snippet, memory_type, 
           memory_confidence, created_at, role,
           response_description,
           GREATEST(0, 1 - (embedding <=> $1)) AS vec_score
    FROM messages
    WHERE conversation_id = $2
      AND role = 'user'
      AND is_embeddable = TRUE
      AND is_forgotten = FALSE
      AND embedding IS NOT NULL
    ORDER BY embedding <=> $1
    LIMIT 20
),
fts_results AS (
    -- FTS: user + assistant (response_description в tsvector)
    -- Без фильтра role — ловим и юзерские сообщения, и описания артефактов
    SELECT id, content, memory_snippet, memory_type, 
           memory_confidence, created_at, role,
           response_description,
           LEAST(1.0, ts_rank(tsv, plainto_tsquery('simple', $3)) * 10) AS fts_score
    FROM messages
    WHERE conversation_id = $2
      AND is_forgotten = FALSE
      AND tsv @@ plainto_tsquery('simple', $3)
    ORDER BY fts_score DESC
    LIMIT 10
),
merged AS (
    SELECT 
        COALESCE(v.id, f.id) AS id,
        COALESCE(v.content, f.content) AS content,
        COALESCE(v.memory_snippet, f.memory_snippet) AS memory_snippet,
        COALESCE(v.memory_type, f.memory_type) AS memory_type,
        COALESCE(v.memory_confidence, f.memory_confidence) AS memory_confidence,
        COALESCE(v.created_at, f.created_at) AS created_at,
        COALESCE(v.role, f.role) AS role,
        COALESCE(v.response_description, f.response_description) AS response_description,
        COALESCE(v.vec_score, 0) AS vec_score,
        COALESCE(f.fts_score, 0) AS fts_score
    FROM vector_results v
    FULL OUTER JOIN fts_results f 
        ON v.id = f.id
)
SELECT 
    id,
    -- snippet (индекс, неавторитетен — для навигации, не для доверия)
    -- Fallback = '' (пустая строка), НЕ LEFT(content, N) — обрезка создаёт
    -- псевдо-резюме, которое LLM может принять за факт (Epistemic Contract, Правило 3)
    -- См. UNDE_Knowledge_Staging_Pipeline.md, Фикс 4A
    CASE 
        WHEN role = 'assistant' AND response_description IS NOT NULL 
            THEN response_description
        ELSE COALESCE(memory_snippet, '')
    END AS snippet,
    -- raw excerpt (первоисточник, авторитетен) — head+tail
    -- Сохраняет начало И конец сообщения (отрицания/уточнения часто в конце)
    CASE
        WHEN LENGTH(content) <= 500 THEN content
        WHEN memory_type IN ('fact', 'event') AND LENGTH(content) <= 1500 THEN content
        WHEN memory_type IN ('fact', 'event') THEN LEFT(content, 800) || ' [...] ' || RIGHT(content, 400)
        ELSE LEFT(content, 280) || ' [...] ' || RIGHT(content, 220)
    END AS raw_excerpt,
    created_at,
    role,
    -- Hybrid score + тематический temporal decay + confidence
    (0.7 * vec_score + 0.3 * fts_score) 
    * (1 + 0.3 * EXP(
        -1 * CASE memory_type
            WHEN 'emotion'    THEN 0.015
            WHEN 'event'      THEN 0.008
            WHEN 'general'    THEN 0.005
            WHEN 'preference' THEN 0.002
            WHEN 'fact'       THEN 0.001
            ELSE 0.005
        END
        * (1.3 - COALESCE(memory_confidence, 0.5))
        * EXTRACT(EPOCH FROM NOW() - created_at) / 86400
    )) AS final_score
FROM merged
WHERE vec_score > 0.5 OR fts_score > 0
ORDER BY final_score DESC
LIMIT 15;
```

**Асимметрия vector vs FTS:** vector branch ищет только `role='user'` (эмбеддинги только у юзерских сообщений). FTS branch ищет **все роли** — это позволяет находить assistant-артефакты по токенам из `response_description` (бренд, цвет, SKU). Для assistant-сообщений episode_card берётся из `response_description` (не из `content`, который содержит "Вот что я нашла!").

**Важно:** temporal decay — это recency boost, а не наказание за давность. Множитель ≥ 1.0. Свежие воспоминания получают бонус, старые не штрафуются.

**Diversity filter:** не более 3 сообщений из одного календарного дня (применяется в application layer).

### Скорости затухания по типу воспоминания

| Тип | base_λ | Базовый полураспад | Пример |
|-----|--------|-------------------|--------|
| emotion | 0.015 | ~46 дней | "устала после работы" |
| event | 0.008 | ~87 дней | "в прошлый раз в кино было холодно" |
| general | 0.005 | ~139 дней | "Дима предложил сходить куда-нибудь" |
| preference | 0.002 | ~347 дней | "обожаю корейские триллеры" |
| fact | 0.001 | ~693 дня | "не ем глютен" |

**Корректировка через confidence:** `effective_λ = base_λ(memory_type) × (1.3 - memory_confidence)`

### Soft / Hard Forget

**Soft Forget (кнопка "Забудь это"):**

> Обновлено: cascade forget по evidence_message_ids + защита onboarding facts.
> См. UNDE_Knowledge_Staging_Pipeline.md, Фикс 15.

```sql
-- 1. Стандартный soft forget самого сообщения
UPDATE messages SET 
    is_forgotten = TRUE,
    embedding = NULL,
    memory_snippet = NULL
WHERE conversation_id = $1 AND id = $2;

-- 2. Обнулить snippets соседей (±1 сообщение) — предотвращает утечку через соседние snippets
UPDATE messages SET memory_snippet = NULL
WHERE id IN (
    (SELECT id FROM messages
     WHERE conversation_id = $1
       AND created_at < (SELECT created_at FROM messages WHERE conversation_id = $1 AND id = $2)
     ORDER BY created_at DESC LIMIT 1)
    UNION
    (SELECT id FROM messages
     WHERE conversation_id = $1
       AND created_at > (SELECT created_at FROM messages WHERE conversation_id = $1 AND id = $2)
     ORDER BY created_at ASC LIMIT 1)
);

-- 3. Обнулить response_description у связанных assistant-ответов
UPDATE messages SET response_description = NULL
WHERE role = 'assistant'
  AND conversation_id = $1
  AND (
      reply_to_id = $2
      OR id = (
          SELECT id FROM messages
          WHERE conversation_id = $1
            AND role = 'assistant'
            AND created_at > (SELECT created_at FROM messages WHERE conversation_id = $1 AND id = $2)
          ORDER BY created_at ASC LIMIT 1
      )
  );

-- 4. Деактивировать User Knowledge, где evidence включает этот message
--    ИСКЛЮЧЕНИЕ: onboarding facts (extracted_from = 'onboarding') не деактивируются
--    через cascade — только если юзер явно поправил через instant/correction.
UPDATE user_knowledge SET is_active = FALSE
WHERE $2 = ANY(evidence_message_ids)
  AND extracted_from != 'onboarding';
```

**Hard Delete (GDPR erase):**

```sql
DELETE FROM user_knowledge WHERE $2 = ANY(evidence_message_ids);
UPDATE messages SET 
    content = '[deleted]',
    embedding = NULL,
    memory_snippet = NULL,
    memory_confidence = NULL,
    response_description = NULL,
    reply_to_id = NULL,
    is_forgotten = TRUE,
    deleted_at = NOW()
WHERE conversation_id = $1 AND id = $2;

-- Регистрация в tombstone registry (Production DB)
INSERT INTO deleted_messages_registry (conversation_id, message_id, deleted_at)
VALUES ($1, $2, NOW());
```

**Tombstone Registry** хранится в Production DB (primary) + Object Storage (copy). После любого восстановления шарда — `apply_deletions.sql` на основе registry.

### Конфигурация PostgreSQL (Local Primary — NVMe SSD, 32 GB RAM)

```ini
# postgresql.conf — оптимизация для 32 GB RAM, NVMe SSD

# Буферы
shared_buffers = 8GB                # 25% RAM
effective_cache_size = 24GB         # 75% RAM (OS page cache)
work_mem = 40MB
maintenance_work_mem = 2GB
wal_buffers = 64MB

# Планировщик: NVMe SSD
random_page_cost = 1.1              # NVMe ≈ sequential
seq_page_cost = 1.0
effective_io_concurrency = 200      # NVMe parallel IO

# Durability
fsync = on
synchronous_commit = local          # WAL flush перед ack
full_page_writes = on               # Для корректности WAL на реплике

# WAL
wal_level = replica
max_wal_senders = 5
wal_keep_size = 4GB
max_replication_slots = 5
checkpoint_timeout = 10min
max_wal_size = 2GB

# Connections (через PgBouncer)
max_connections = 100

# Archive (для PITR backup)
archive_mode = on
archive_command = 'pgbackrest --stanza=shard0 archive-push %p'
```

### Системная конфигурация (Local Primary)

```bash
# /etc/sysctl.conf
vm.swappiness = 1                   # Минимальный swap
vm.dirty_background_ratio = 5       # Фоновая запись при 5% dirty pages
vm.dirty_ratio = 10                 # Синхронная запись при 10% dirty pages
```

### Streaming Replication: Local → Hetzner (через WireGuard)

```
Время 0.000s: Пользователь отправляет сообщение
Время 0.002s: PostgreSQL (local-shard-0, NVMe) выполняет INSERT
              → WAL-запись создана
              → Данные записаны на NVMe (fsync)
              → Клиенту возвращён ответ "OK"
Время 0.003s: WAL sender отправляет запись через WireGuard туннель (wg-shard0)
              ... ~120ms через зашифрованный туннель ...
Время 0.123s: PostgreSQL (shard-replica-0, Hetzner) получает WAL
              → Записывает на NVMe (с fsync)
              → Применяет изменение (WAL replay)
```

**Async replication:** primary не ждёт подтверждения от replica → минимальная latency для клиента.

**WireGuard туннель:** Каждый шард имеет свой WireGuard туннель до helsinki-gw (10.1.0.40). WAL streaming — основной потребитель трафика (~1–10 GB/день).

### Patroni + etcd: автоматический failover

**3 узла etcd:**

| Узел | Локация | Тип | IP | Зачем |
|------|---------|-----|-----|-------|
| etcd-1 | Локально (local-etcd-1) | 1 vCPU / 2 GB | 10.2.0.50 | Локальный голос для primary |
| etcd-2 | Hetzner Helsinki (на shard-replica-0) | Контейнер | 10.1.1.10 | Голос replica |
| etcd-3 | Hetzner Helsinki (CPX11) | Dedicated (~€4/мес) | 10.1.0.15 | Кворум: 2 из 3 в Hetzner |

**Логика кворума:**
- Локальный сервер жив + любой Hetzner → кворум есть, local = primary (норма)
- Локальный упал → 2 Hetzner из 3 = кворум, Hetzner promoted (failover)
- Hetzner-сеть упала → локальный один, нет кворума → Patroni НЕ позволяет local работать → fencing

```
Failover timeline:
00:00.000  — Локальный шард недоступен
00:05.000  — Patroni на Hetzner: "Primary не отвечает 5 секунд"
00:10.000  — Patroni: "Подожду ещё 5 сек"
00:15.000  — Patroni: "Primary мёртв" → pg_ctl promote на Hetzner
00:15.500  — Patroni обновляет etcd → local-redis обновляет routing
00:16.000  — Система работает через Hetzner (latency +120ms для юзеров шарда)

RTO (время простоя): ~15–30 секунд
RPO (потеря данных): 0 на уровне пар — client-side verify-and-replay
```

**Failback policy:** failover auto, failback — ТОЛЬКО вручную, после проверки: lag=0, health green ≥ 10 мин, инженер подтвердил.

> **Подробнее о failover сценариях** — см. [07_Server_Layout_v7.md](07_Server_Layout_v7.md#failover-сценарии)

### Client-Side Verify-and-Replay

При async replication последние 1–5 секунд WAL могут не доехать до Hetzner. Приложение хранит буфер последних пар «запрос юзера + ответ UNDE» и переотправляет при reconnect.

**Протокол:**

```
Нормальный режим:
  App → local-shard primary: message + UUID (client-generated)
  local-shard primary: INSERT → WAL flush на NVMe → ack
  App: status "confirmed"

Сбой (ack не дошёл):
  App: status остаётся "unconfirmed"
  ... 15-30 сек (Patroni failover) ...
  App → Hetzner (новый primary): POST /verify-and-replay
  {
    conversation_id: "conv-xyz",
    unconfirmed: [пары user+assistant],
    recent_confirmed_ids: [последние 3 confirmed пары (safety net)]
  }
  Hetzner:
    Если role=assistant и содержит артефакт → построить response_description (template-based)
    INSERT ... ON CONFLICT DO NOTHING + enrichment backfill
```

**Буфер в приложении:**
- Persistent storage (SQLite на iOS/Android, IndexedDB на web)
- 10 пар + confirmed пары ещё 60 сек после ack
- Rate-limit retry: 1 пара/сек/юзер, max 3 попытки

### Шардирование (application-level по user_id)

```
Routing (в Redis / Production DB):
  user_id → hash(user_id) % N_shards → shard_id → connection string

Вместимость одного шарда (32 GB RAM, NVMe SSD):
  shared_buffers = 8 GB, effective_cache_size = 24 GB
  Комфортная ёмкость: ~500–800 юзеров/шард (1 год данных)
  HNSW индекс на 500 юзеров ≈ ~11 GB (через 1 год)

Триггер для нового шарда:
  SELECT pg_relation_size('idx_messages_embedding') > 20 GB
```

**Roadmap масштабирования:**

| Этап | MAU | Шарды | Доп. серверы |
|------|-----|-------|-------------|
| Старт | 0–800 | 1 (local-shard-0) | — |
| 5K | ~800–2,000 | 2 | + local-shard-1 |
| 10K | ~2,000–4,000 | 4 | + local-shard-2, 3 |
| 25K | ~4,000–10,000 | 8 | + local-shard-4..7 |
| 50K | ~10,000–20,000 | 16 | + local-shard-8..15 |

### Backup стратегия (4 уровня)

```
Уровень 1: WAL на NVMe (local crash recovery)
  → Защищает от: PostgreSQL process crash, OOM kill, soft failures
  → Данные на NVMe сохранены при reboot

Уровень 2: Streaming replication на Hetzner (real-time, через WireGuard)
  → RPO: 0 (client-side verify-and-replay)
  → RTO: 15–30 секунд (Patroni)

Уровень 3: WAL archive в Object Storage (continuous)
  → Point-in-Time Recovery на любой момент
  → RPO: до последнего archived WAL segment (~5 минут)

Уровень 4: pg_basebackup в Object Storage (periodic)
  → Полная копия каждые 6 часов
  → Хранение: 7 дней daily + 4 недели weekly + 3 месяца monthly
```

### Восстановление primary после сбоя

```
1. Локальный сервер восстановлен / заменён
2. Данные на NVMe сохранены (в отличие от tmpfs)

3. Вариант A: Локальные данные на месте (рекомендуемый)
   → PostgreSQL стартует, применяет WAL
   → Догоняет по WAL с Hetzner через WireGuard (секунды)
   → RTO: 1–5 минут

   Вариант B: С Hetzner replica (если NVMe повреждён)
   → pg_basebackup -h 10.1.1.10 -D /var/lib/postgresql/17/main -Fp -Xs -P
   → Через WireGuard: скорость зависит от tunnel bandwidth
   → RTO: 10–60 минут (зависит от объёма данных)

4. Локальный сервер запускается как replica, догоняет по WAL
5. Failback — ТОЛЬКО вручную: lag=0, health green ≥ 10 мин
```

### Модель безопасности данных на шарде

```
Chat History (messages):
  content, memory_snippet,       → plaintext в PostgreSQL
  response_description           → plaintext (backend-only)
  embedding, tsv                 → открыто (необходимо для search)
  Защита: private network + LUKS at-rest + strict PG roles + audit log

User Knowledge:
  Все поля → AES-256 app-level encryption
  Ключи → user_keys таблица на том же шарде
  Защита: AES-256 + private network + LUKS at-rest
```

**Почему content не зашифрован app-level:**
- FTS (tsvector) работает только с открытым текстом
- raw_excerpt (head+tail) и snippet fallback требуют открытого текста
- App-level AES сделал бы FTS и tsvector бесполезными

### Расчёт объёма (с Semantic Retrieval)

| Компонент | Размер на сообщение | Комментарий |
|-----------|---------------------|-------------|
| Текст (content) | ~1 KB | Среднее сообщение |
| mood_frame JSON | ~200 B | Не для всех |
| Embedding (1024-dim, float32) | ~4 KB | Только embeddable (~50%) |
| HNSW индекс overhead | ~1.2 KB | ~30% от embedding |
| tsvector (FTS) | ~200 B | Включает response_description |
| memory_snippet | ~100 B | Только embeddable |
| memory_type + confidence | ~15 B | |
| response_description | ~150 B | Только assistant с артефактом (~20%) |
| Метаданные + индексы PG | ~500 B | |
| **Среднее на сообщение** | **~4.7 KB** | С учётом 50% embeddable, 20% артефактов |

| Период | Сообщений/юзер | Chat History | User Knowledge | Итого |
|--------|---------------|-------------|----------------|-------|
| 1 месяц | ~500 | ~2.3 MB | ~70 KB | ~2.4 MB |
| 1 год | ~6,000 | ~27 MB | ~200 KB | ~27 MB |
| 5 лет | ~30,000 | ~135 MB | ~1 MB | ~136 MB |

### Рост HNSW индекса (halfvec, на один шард ~500–800 users)

| Период | Embeddings/шард | HNSW индекс | Heap + прочие | Working set |
|--------|----------------|-------------|---------------|-------------|
| Месяц 6 | ~750K | ~2.2 GB | ~4 GB | ~6 GB |
| Год 1 | ~1.5M | ~4.5 GB | ~7 GB | ~11.5 GB |
| Год 2 | ~3M | ~9 GB | ~14 GB | ~23 GB |
| Год 3 | ~4.5M | ~13.5 GB | ~25 GB | ~38.5 GB |

**Один шард 32 GB** вмещает ~500–800 юзеров комфортно **~1–1.5 года.** Триггер: `pg_relation_size('idx_messages_embedding') > 20 GB` → добавить новый шард.

### Производительность NVMe SSD (32 GB RAM)

| Метрика | 32 GB NVMe (local) | Комментарий |
|---------|-------------------|-------------|
| HNSW traversal (150 reads) | 1.5–3 ms (hot cache) / 5–10 ms (cold) | Working set в page cache при 500–800 юзерах |
| Heap fetch (20 reads) | 0.2–0.5 ms | — |
| Full hybrid search | 2–5 ms (hot) / 10–20 ms (cold) | — |
| 1,000 concurrent queries p95 | 10–30 ms | — |

> **Компенсация:** При 500–800 юзерах/шард весь working set помещается в effective_cache_size (24 GB) + shared_buffers (8 GB). Кеш тёплый при стабильной нагрузке. Деградация заметна только при cold start или spike.

### Пользователи БД

| User | Доступ | Сервер |
|------|--------|--------|
| app_rw | READ/WRITE all | local-app (10.2.0.2), local-orchestrator (10.2.0.17) |
| knowledge_rw | READ/WRITE user_knowledge, user_keys | Knowledge Pipeline (на local-orchestrator) |
| persona_rw | READ/WRITE relationship_stage, persona_temp_blocks, signal_daily_deltas; READ user_knowledge | local-persona (10.2.0.21) |
| replicator | REPLICATION | shard-replica-0 (10.1.1.10, через WireGuard) |

> **Связанный документ:** [UNDE_Knowledge_Staging_Pipeline.md](../UNDE_Knowledge_Staging_Pipeline.md) — детальная спецификация pipeline извлечения знаний, Epistemic Contract, supersede-механизм, cascade forget, memory correction loop, enrichment TTL guarantee. Все изменения схемы БД в этом файле согласованы с KSP v1.7.

---
