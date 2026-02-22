# UNDE — Knowledge Staging Pipeline

*Архитектурный фикс: надёжность создания базы знаний о клиенте*

*Дополнение к [TZ Infrastructure v6.2](README.md). Затрагивает: Dubai User Data Shard, LLM Orchestrator, Data Flow.*

Версия: 1.7 (final) | Февраль 2026

---

## Проблема

В текущей архитектуре (v6.2) описаны два слоя знаний — Chat History (сырые сообщения + Semantic Retrieval) и User Knowledge (структурированные факты, AES-256). Оба слоя собираются в ContextPack для LLM.

Но **pipeline извлечения фактов в User Knowledge не специфицирован**: нет алгоритма, кто вызывает extraction, когда, с каким промптом, как обрабатывает конфликты. Есть схема БД (куда писать) и retrieval (как читать), но между ними — пробел.

Без этого pipeline User Knowledge заполняется только из onboarding и explicit_input, и весь слой structured facts после онбординга становится stale.

Параллельно — ряд узких мест в Semantic Retrieval и enrichment, которые снижают качество «памяти» аватара.

Этот документ закрывает все выявленные проблемы конкретными решениями.

---

## Epistemic Contract

Три правила, которые не обсуждаются. Любое архитектурное решение проверяется на соответствие этим правилам. Если нарушает — решение отклоняется.

```
ПРАВИЛО 1: Правда живёт только в RAW (Chat History).
   Каждое сообщение — дословно, навсегда, с полным текстом.
   Это единственный источник правды. Всё остальное — производное.

ПРАВИЛО 2: User Knowledge — это кеш гарантированных фактов
   с указателями на доказательства (evidence), а не «профиль юзера».
   10-30 записей, не сотни. Только то, что нельзя пропустить,
   даже если Semantic Retrieval не найдёт.

ПРАВИЛО 3: Любой производный текст (snippet, profile label,
   extracted fact) — неавторитетен сам по себе.
   В ContextPack всегда сопровождается raw excerpt + message_ids.
   LLM доверяет сырому тексту, не сжатию.
```

Почему это важно: без Epistemic Contract команда через 2-3 итерации начнёт доверять «сжатым слоям» как истине — и UNDE превратится в ChatGPT/Claude с их «помню в общем, теряю важное». Эти правила предотвращают скатывание.

---

## Принцип: три уровня памяти

Философия бренда: «UNDE — это мой. Он меня знает.» Точность важнее полноты. Одна ошибочная память хуже десяти пропущенных.

```
1. RAW TRUTH — Chat History
   Каждое сообщение, дословно, навсегда.
   Embeddings, FTS, полный текст.
   Источник правды. Не трогаем. (Epistemic Contract, Правило 1)

2. STAGING — Knowledge Candidates (новый слой, Фаза 2)
   Кандидаты фактов из недавних сообщений.
   Анализируются кумулятивно, не по одной фразе.
   Временное хранение до промоута или отклонения.
   НИКОГДА не обобщает предпочтения — только hard facts
   с 2+ независимыми evidence.

3. VERIFIED FACTS — User Knowledge
   Кеш гарантированных фактов с evidence pointers.
   (Epistemic Contract, Правило 2)
   Размер, аллергии, бюджет, жёсткие запреты, onboarding.
   10-30 записей на юзера, не сотни.
```

---

## Фикс 1A: Instant Hard Facts (sync, при INSERT сообщения)

### Проблема

Юзер говорит «мой размер теперь M». Без instant extraction — User Knowledge хранит старый размер S до следующего обновления. Рекомендации ошибочны.

### Решение

```python
# Выполняется в LLM Orchestrator при сохранении user-сообщения.
# Не LLM — regex/rules. Latency: <1ms.
# Паттерны хранятся в конфигурационной таблице (не хардкод).
# Это позволяет: версионировать, катить без деплоя, A/B-тестировать.

# Таблица конфигурации (Production DB, не Dubai Shard):
# CREATE TABLE instant_patterns (
#     id SERIAL PRIMARY KEY,
#     knowledge_type VARCHAR(50) NOT NULL,
#     pattern TEXT NOT NULL,            -- regex
#     language VARCHAR(10) NOT NULL,    -- 'ru', 'en', 'ar', 'arabizi', 'mixed'
#     is_active BOOLEAN DEFAULT TRUE,
#     version INTEGER DEFAULT 1,
#     created_at TIMESTAMPTZ DEFAULT NOW()
# );
# Кешируется в LLM Orchestrator при старте, обновляется по SIGHUP/API.

# Начальный набор паттернов (MVP: ru + en + ar + Arabizi + code-switching):
CRITICAL_PATTERNS = {
    'body_params': [
        # Russian
        r"мой размер (?:теперь |стал )?([SMLX]{1,3}|\d{2,3})",
        r"я ношу (\d{2,3}|[SMLX]{1,3})",
        # English
        r"my size (?:is |now )?([SMLX]{1,3}|\d{2,3})",
        r"I (?:wear|'m)(?: a)? (?:size )?([SMLX]{1,3}|\d{2,3})",
        # Arabic (مقاس/حجم = size, ألبس = I wear)
        r"(?:مقاسي|حجمي|مقاس(?:ي)?)\s*(?:صار\s*|هو\s*)?([SMLX]{1,3}|\d{2,3})",
        r"(?:ألبس|أرتدي|لابس[ةه]?)\s*(?:مقاس\s*)?([SMLX]{1,3}|\d{2,3})",
        # Arabizi (Franco-Arabic: ma2asi/7ajmi = مقاسي/حجمي)
        r"(?:ma2as[iy]|7ajm[iy]|size[iy])\s*(?:sar\s*)?([SMLX]{1,3}|\d{2,3})",
        r"(?:albis|albas)\s*([SMLX]{1,3}|\d{2,3})",
        # Code-switching (mixed in one message)
        r"(?:أنا|ana)\s+size\s+([SMLX]{1,3}|\d{2,3})",
    ],
    'allergy': [
        # Russian
        r"аллерги[яю] на (.+?)(?:\.|,|$)",
        # English
        r"allerg(?:y|ic) to (.+?)(?:\.|,|$)",
        # Arabic (حساسية = allergy, عندي = I have)
        r"(?:عندي |أعاني من )?(?:حساسية|تحسس)\s*(?:من\s*|ل)(.+?)(?:\.|،|$)",
        # Arabizi
        r"(?:3indi |3ndi )?(?:7asasiya|ta7assos)\s*(?:min\s*|l)(.+?)(?:\.|,|$)",
    ],
    'hard_ban': [
        # Russian
        r"(?:никогда )?не предлагай (.+?)(?:\.|,|$)",
        r"(?:никогда )?не (?:хочу|буду|ношу) (.+?)(?:\.|,|$)",
        # English
        r"never suggest (.+?)(?:\.|,|$)",
        r"(?:I )?don'?t (?:want|wear|like) (.+?)(?:\.|,|$)",
        # Arabic (لا تقترح = don't suggest, ما أبي/مابي = I don't want - Gulf)
        r"(?:لا |ما\s*)?(?:تقتر[حع]|تعرض)\s*(?:علي[ّ]?\s*)?(.+?)(?:\.|،|$)",
        r"(?:ما\s*أبي|مابي|ما\s*أبغى|مابغى)\s*(.+?)(?:\.|،|$)",
        # Arabizi
        r"(?:la |ma\s*)?(?:t2tiri7|t3iri[dḍ])\s*(.+?)(?:\.|,|$)",
        r"(?:ma\s*abi|mabi|ma\s*abgha)\s*(.+?)(?:\.|,|$)",
    ],
    'budget': [
        # Russian
        r"бюджет (?:до |не больше )?(\d+)\s*(?:дирхам|aed|dhs)",
        # English
        r"budget (?:up to |max )?(\d+)\s*(?:aed|dhs|dirhams?)",
        # Arabic (ميزانية = budget, درهم = dirham)
        r"(?:ميزانيت[يه]|بجت)\s*(?:لا تتجاوز |حدود |ماكس )?(\d+)\s*(?:درهم|دراهم)",
        r"(?:ما\s*أبي\s*أصرف|مابي أصرف)\s*(?:أكثر من |فوق )?(\d+)\s*(?:درهم|دراهم|aed|dhs)",
        # Arabizi
        r"(?:budget|bajt)\s*(?:max |la )?(\d+)\s*(?:dirham|darham|aed|dhs)",
        # Code-switching
        r"(\d+)\s*(?:درهم|dhs|aed)\s*(?:max|ماكس|максимум|بس|only)",
    ],
    'life_event': [
        # Russian
        r"(?:через|в)\s+(\d+)\s+(?:дн[ейя]|недел[ьюи]|месяц[аев]?).+?(свадьб\w*|день рожден\w*|переез\w*|отпуск\w*|презентаци\w*|выпускн\w*|юбиле\w*)",
        r"(?:скоро|планирую|готовлюсь к?)\s+(свадьб\w*|день рожден\w*|переез\w*|отпуск\w*|поезд\w*|презентаци\w*|выпускн\w*|юбиле\w*)",
        # English
        r"(?:in|within)\s+(\d+)\s+(?:days?|weeks?|months?).+?(wedding|birthday|moving|vacation|trip|presentation|graduation|anniversary)",
        r"(?:soon|planning|preparing for)\s+(?:a\s+)?(wedding|birthday|move|vacation|trip|presentation|graduation|anniversary)",
        # Arabic (عرس = wedding, عيد ميلاد = birthday, سفر = travel, حفلة = party)
        r"(?:عندي|عندنا|بعد|خلال)\s+(?:\d+\s+(?:يوم|أسبوع|شهر)\s+)?(عرس|زواج|عيد ميلاد|سفر|حفلة|تخرج|انتقال)",
        r"(?:أجهز|أحضر|أستعد)\s+(?:ل|حق)\s*(عرس|زواج|عيد ميلاد|سفر|حفلة|تخرج)",
        # Arabizi
        r"(?:3indi|ba3d|5ilal)\s+(?:\d+\s+)?(?:3irs|zawaj|birthday|safar|7afla|ta5aruj)",
        r"(?:preparing|getting ready)\s+(?:for\s+)?(?:3irs|zawaj|7afla)",
    ],
}

# ВАЖНО: Дубай = multilingual mixing.
# Один юзер может написать: "مقاسي M بس mabi open shoulders يعني"
# Паттерны должны ловить факты В ЛЮБОМ ЯЗЫКЕ в одном сообщении.
# Стратегия: запускать ВСЕ паттерны (ru+en+ar+arabizi) на КАЖДОЕ сообщение.
# Overhead: ~0.5ms (regex precompiled), приемлемо.

# При срабатывании:
# 1. Создать/обновить запись в user_knowledge
# 2. extracted_from = 'instant_pattern'
# 3. confidence = 0.95 (для life_event: 0.85, т.к. дата может быть неточной)
# 4. evidence_message_ids = [message_id] + ±1 окно (см. Evidence Span)
# 5. Автоматический supersede (Фикс 2)
# 5a. Для life_event: knowledge_key = краткий идентификатор (wedding_sister, vacation_july)
#     expires_at = извлечённая дата ИЛИ NOW() + 30 дней если дата не указана
#     knowledge_key формируется: тип_события + контекст (sister, mom, work и т.д.)
# 6. Для body_params: размеры 36-54 принимать ТОЛЬКО если рядом
#    якорь контекста (размер/مقاس/size/одежд/ثوب), иначе может быть
#    обувь или возраст. Без якоря → не промоутить.
#    АНТИ-ЯКОРЬ: если рядом shoes/обувь/حذاء/كوتش/sneakers → reject
#    или записать в отдельный key 'shoe_size' (если понадобится).
```

**Multilingual strategy (MVP, Дубай):**

1. **Все 4 языковых слоя с первого дня:** русский, английский, арабский (MSA + Gulf), Arabizi (Franco-Arabic).
2. **Code-switching:** Все паттерны запускаются на каждое сообщение. Юзер в Дубае может смешивать 2-3 языка в одной фразе.
3. **Arabizi** — арабский латиницей с цифрами (7=ح, 3=ع, 2=ء, 5=خ, 9=ص). Распространён среди молодёжи в GCC. Примеры: "7ajmi M", "ma2asi 38", "mabi leather".
4. **Gulf Arabic** отличается от MSA: مابي (mabi) = ما أريد (ma urid) = «не хочу». Паттерны покрывают оба варианта.
5. **Числовые размеры (36-54):** Принимать как body_params ТОЛЬКО при наличии контекстного якоря (размер/مقاس/size/одежд). «42» без контекста может быть обувь или возраст.

**Слэнг и неформальная речь (Dubai reality):**

Дубай — город где в одном сообщении могут быть 3 языка + слэнг. Принципы:

6. **Gulf slang не = факт.** «wallah 7ilu» (клянусь красивое), «يبيلي» (мне нужно), «وايد» (очень) — эмоциональные маркеры, НЕ записывать как предпочтения. Только если содержат explicit hard fact (размер, аллергию, запрет).
7. **Correction patterns на арабском** — юзер может поправить UNDE по-арабски или через Arabizi:

```python
# Добавить в CORRECTION_PATTERNS (Фикс 11):
CORRECTION_PATTERNS_AR = [
    r"لا[,،]?\s*(?:غلط|خطأ|مو كذا)",              # "Нет, неправильно"
    r"(?:من وين|منو قال|ليش)\s+(?:قلت|حطيت|كتبت)",  # "С чего ты взял?"
    r"(?:أنا )?(?:ما |مو |مش )(?:كذا|هيك|جذي)",      # "Я не такой"
    r"(?:ghalat|ghala6|msh kda|msh hek)",            # Arabizi corrections
    r"no[,]?\s*(?:msh|mub|mabi)\s+",                 # Mixed: "no msh..."
]
```

8. **Hinglish/Runglish готовность.** Архитектура (все паттерны на каждое сообщение) уже поддерживает добавление hindi/urdu паттернов без изменения кода — только INSERT в instant_patterns таблицу.

### Приоритет: До MVP

---

## Фикс 1B: Batch Knowledge Extraction (async, Celery)

### Проблема

Instant patterns ловят только явно декларированные hard facts. Более сложные факты (смена стиля, новый бренд при 2+ упоминаниях) требуют контекстного анализа.

### Решение

```python
# Триггеры запуска (любой из):
# - Сессия закрыта (gap >30 мин без сообщений)
# - Накопилось ≥15 непроанализированных сообщений
# - Cron: раз в 2 часа если есть pending сообщения
# - Ограничение: не чаще 1 раз/юзер/час
#
# CONCURRENCY: advisory lock по user_id на время extraction+apply.
# Два воркера не могут применять дельты одновременно.
# pg_advisory_xact_lock(user_id_hash) + knowledge_extraction_log
# как идемпотентный ключ (проверить: не было ли уже extraction для
# тех же messages в последние 5 минут).

# Вход для LLM (DeepSeek):
{
    "current_knowledge": "<compact JSON из user_knowledge, ~500 tokens>",
    "new_messages": "<все user + assistant сообщения с last_extraction_at, ~2-6K tokens>",
    #                  ^^^^^^^^^^^^^^^^^^^
    # ВАЖНО: включать assistant-ответы как контекст (не только user).
    # Без assistant-ответов LLM не понимает, почему юзер сказал X
    # после развёрнутого ответа UNDE. Пример:
    #   UNDE: "Вот три образа: минимализм, бохо, классика"
    #   User: "Второй!"
    # Без контекста assistant — "Второй!" бессмысленен.
    # Assistant messages передаются raw, не сжимаются.
    "instruction": "Проанализируй новые сообщения в контексте текущих знаний.
        Верни ТОЛЬКО дельту в формате JSON:
        - ADD: новый факт, которого нет в текущих знаниях
        - UPDATE: существующий факт изменился (укажи knowledge_id)
        - REMOVE: факт опровергнут (укажи knowledge_id)
        - CONFIRM: факт подтверждён (укажи knowledge_id)
        
        Для каждой операции укажи:
        - evidence_message_ids: список id сообщений-доказательств
        - subject: кто субъект высказывания (user / other / unknown)
        - confidence: 0.0-1.0
        
        ЖЁСТКИЕ ОГРАНИЧЕНИЯ:
        - Записывай ТОЛЬКО факты о самом юзере (subject = user)
        - НЕ обобщай предпочтения (это НЕ анкета, это кеш hard facts)
        - Сарказм и ирония = НЕ факт
        - При сомнении — НЕ записывай (лучше пропустить, чем ошибиться)
        
        Промоут ТОЛЬКО:
        (а) Критичные hard facts: body_params, budget, allergy, hard_ban
        (б) Явно декларированное юзером напрямую
        (в) Подтверждённое 2+ НЕЗАВИСИМЫМИ evidence_message_ids
            НЕЗАВИСИМЫЕ = из разных сессий (gap >30 мин между ними)
            ИЛИ из разных календарных дней
            ИЛИ разные формулировки одного факта
            НЕ независимые: 2 сообщения подряд в одном обмене
        (г) Всё остальное — НЕ промоутить, оставить в RAW Chat History
        
        НЕ промоутить (никогда):
        - Разовые реакции на конкретные вещи
        - Эмоциональные оценки
        - Контекстные замечания
        - Всё, где subject != user
        - Любые 'обобщения предпочтений'
        
        MULTILINGUAL:
        - Юзер может писать на ru, en, ar, Arabizi или смешивать языки.
        - Факт из ЛЮБОГО языка равноценен. «مقاسي M» = «мой размер M» = «my size M».
        - Code-switching — норма, не ошибка. Не теряй факт из-за смены языка.
        - Arabizi: 7=ح, 3=ع, 2=ء. «7asasiya» = حساسية = аллергия.
        - Цитируй raw user-input ДОСЛОВНО, не переводи.
        
        СЛЭНГ И ЭМОЦИИ ≠ ФАКТЫ:
        - Gulf slang (wallah, يبيلي, وايد, 7ilu, mashallah) — эмоциональные маркеры.
        - НЕ промоутить как предпочтения: «wallah 7ilu this dress» ≠ «любит это платье».
        - Промоутить ТОЛЬКО explicit hard facts внутри слэнговых фраз."
}
```

### Важное ограничение

Batch extraction **не имеет права «обобщать предпочтения»**. Это не создание анкеты юзера. Это точечное извлечение hard facts с доказательствами. Если LLM не уверен — факт остаётся в RAW. Semantic Retrieval найдёт его при необходимости.

Это принципиальное отличие от «памяти» ChatGPT/Claude: мы не создаём параллельный источник правды. User Knowledge — кеш с evidence pointers (Epistemic Contract, Правило 2).

### Validator Gate: LLM предлагает, валидатор применяет

LLM **не пишет факты напрямую**. LLM предлагает дельты, детерминированный валидатор проверяет и применяет. Это даёт «точность правил + понимание контекста LLM»:

```python
def validate_extraction_delta(delta: dict, messages: dict[UUID, str]) -> bool:
    """
    LLM предложил ADD/UPDATE. Валидатор проверяет:
    1. evidence_message_ids реально существуют
    2. evidence содержит якорные признаки для данного knowledge_type
    3. confidence >= 0.8 (ниже — auto-reject)
    """
    # Auto-reject low confidence
    if delta['confidence'] < 0.8:
        return False
    
    # Проверить что evidence существует
    for msg_id in delta['evidence_message_ids']:
        if msg_id not in messages:
            return False
    
    # Якорная валидация: evidence должен содержать паттерн
    evidence_text = ' '.join(messages[mid] for mid in delta['evidence_message_ids'])
    
    ANCHOR_PATTERNS = {
        'body_params': r"размер|size|ношу|wear|стал[аи]?\s|مقاس|حجم|ألبس|ma2as|7ajm|albis",
        'budget':      r"\d+\s*(?:дирхам|aed|dhs|руб|درهم|دراهم|dirham)",
        'allergy':     r"аллерг|allerg|не перенош|حساسية|تحسس|7asasiya",
        'hard_ban':    r"не предлагай|never|никогда|не хочу|не нужно|لا تقترح|مابي|ما أبي|mabi|la t2tiri7",
        'life_event':  r"свадьб|birthday|день рожден|переез|отпуск|travel|زواج|عرس|عيد ميلاد|سفر|3irs|zawaj",
    }
    
    ktype = delta['knowledge_type']
    if ktype in ANCHOR_PATTERNS:
        if not re.search(ANCHOR_PATTERNS[ktype], evidence_text, re.IGNORECASE):
            return False  # LLM «придумал» — evidence не содержит якоря
    
    return True
```

Это критически важная защита: даже если LLM ошибётся в интерпретации, валидатор не пропустит факт без якоря в evidence. «Точность как у правил + понимание контекста как у LLM».

### Human-in-loop валидация (Фаза 2)

On startup Фикса 1B — 1% random sample batch extractions на ручной review. Adaptive sampling: если error_rate стабильно < 2% в течение 2 недель → снизить до 0.1%. Если error_rate > 5% → пауза batch, пересмотр prompt. Это дёшево (при 50K MAU, 1%: ~125/мес на review, ~1 час/день; при 0.1%: ~12/мес) и даёт ground truth:

- Правильно ли определён subject (user vs other)?
- Пропущен ли сарказм/ирония?
- Созданы ли ложные факты?

Результаты → golden tests + fine-tune extraction prompt. После стабилизации (error rate < 2%) — снизить sample до 0.1%.

### Staging queue fallback (защита от bottleneck)

При пиковых нагрузках (Dubai, час пик) batch extraction может отстать — pending_extraction_count растёт, а User Knowledge stale. Защита:

```python
# В LLM Orchestrator при сборке ContextPack:
if pending_extraction_count > 10:
    # Подтянуть последние pending сообщения как raw context
    pending_messages = db.execute("""
        SELECT LEFT(content, 300), created_at
        FROM messages
        WHERE conversation_id = %s
          AND created_at > %s  -- last_extraction_at
          AND role = 'user'
        ORDER BY created_at DESC
        LIMIT 5
    """, conversation_id, last_extraction_at)
    
    # Добавить в ContextPack как отдельный блок:
    # "[PENDING — ещё не проанализировано, но юзер это говорил:]"
    context_pack.add_layer('pending_raw', pending_messages)
```

Это не замена batch extraction — это страховка. LLM видит свежие raw сообщения и может их учесть, даже если User Knowledge ещё не обновлён. После отработки batch — pending_raw уходит из ContextPack.

### Приоритет: Фаза 2 (не MVP)

**Обоснование:** На MVP достаточно Фикса 1A (instant hard facts) + Semantic Retrieval по сырой истории. Batch extraction добавляет ценность, но создаёт риск «двух источников правды» если сделан неаккуратно. Лучше запустить MVP на чистой архитектуре (RAW + instant hard facts) и добавить batch после валидации на реальных данных.

---

## Фикс 2: Supersede механизм для User Knowledge

### Проблема

В схеме user_knowledge есть `version` и `is_active`, но нет автоматического supersede. Два факта одного типа могут сосуществовать (size S и size M), и LLM получает противоречие.

### Решение

Добавить `knowledge_key` — ключ конкретного факта внутри типа. Supersede работает по `(knowledge_type, knowledge_key)`, не по `knowledge_type` целиком.

```sql
-- Добавить ключ факта
-- Добавить ключ факта (NOT NULL — без ключа supersede/unique не работают)
ALTER TABLE user_knowledge ADD COLUMN knowledge_key VARCHAR(100) NOT NULL;
-- Дефолты по типу (enforce в сервисе):
--   body_params → 'size' (один на тип)
--   budget → 'general' (один на тип)  
--   allergy → extracted value ('nickel', 'wool')
--   hard_ban → extracted value ('open_shoulders', 'leather')
--   life_event → краткий идентификатор ('wedding_sister', 'vacation_july')

CREATE OR REPLACE FUNCTION supersede_knowledge()
RETURNS TRIGGER AS $$
BEGIN
    -- BEFORE INSERT: деактивировать предыдущие записи с тем же типом И ключом
    -- ПЕРЕД вставкой, иначе UNIQUE partial index
    -- idx_knowledge_active_unique отклонит INSERT
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
```

**Что это меняет:**
- `body_params` (key='size'): supersede — юзер может иметь только один текущий размер
- `budget` (key='general'): supersede — один актуальный бюджет
- `allergy` (key='nickel', key='wool'): **несколько** аллергий сосуществуют, каждая supersede отдельно
- `life_event` (key='wedding_sister', key='vacation_july'): **несколько** событий параллельно
- `hard_ban` (key='open_shoulders', key='leather'): **несколько** запретов параллельно

**Устойчивые предпочтения → hard_ban.** «Не кожа», «не шерсть», «не high heels» — это предпочтения, но по сути запреты. Правило: все устойчивые негативные предпочтения выражаются как `hard_ban` (с evidence), не как soft profile. Это держит их в guaranteed layer.

### Приоритет: До MVP

---

## Фикс 3: Сужение scope User Knowledge

### Проблема

Текущие knowledge_type включают 'emotional_patterns', 'behavior_patterns', 'color_preferences' — категории, которые эволюционируют и плохо поддаются точному extraction. Их наличие создаёт «параллельную правду» рядом с сырыми данными.

### Решение: разделить на guaranteed и soft

```
GUARANTEED (попадают в User Knowledge):
  - body_params        → размер, рост, вес
  - budget             → бюджетный диапазон
  - allergy            → аллергии на материалы
  - hard_ban           → жёсткие запреты ("никогда не предлагай X")
  - onboarding_style   → начальный профиль стиля из онбординга
  - life_event         → предстоящие события + expires_at (см. ниже)

SOFT (НЕ попадают в User Knowledge, остаются в Chat History):
  - emotional_patterns → "устала после работы"
  - behavior_patterns  → "обычно покупает в пятницу"
  - color_preferences  → "нравится бежевый" (кроме onboarding)
  - brand_preferences  → "обожает Zara" (кроме 2+ подтверждений в Фазе 2)
```

**life_event: expires_at.** События стареют. «Свадьба сестры в марте» после марта — не факт, а эпизод. Добавить:

```sql
ALTER TABLE user_knowledge ADD COLUMN expires_at TIMESTAMPTZ;
-- Для life_event: обязательно. Для остальных типов: NULL.
```

Правило: просроченные life_event → `is_active = FALSE` (cron, ежедневно). Данные не теряются — source message в Chat History, Semantic Retrieval может найти как эпизод.

**TTL для событий без конкретной даты:** Если юзер упоминает событие без даты («скоро свадьба сестры», «планирую переезд»), `expires_at` = NOW() + 30 дней. Иначе такие события копятся как «вечные факты». При повторном упоминании — TTL обновляется.

**Миграция:** существующие записи soft-типов → `is_active = FALSE`.

### Приоритет: До MVP

---

## Фикс 4A: Episode Card = raw excerpt + message_id (MVP)

### Проблема

Fix 10 (арбитраж в промпте, MVP) предполагает, что `raw_excerpt` уже есть в ContextPack. Без этого LLM видит только LEFT(content, 80) — обрезку без контекста. Epistemic Contract Правило 3 нарушено.

### Решение: raw_excerpt + message_id всегда, snippet = ''

На MVP episode card содержит raw_excerpt (head+tail) и message_id. Snippet не генерируется — пустая строка. Этого достаточно для арбитража и Epistemic Contract.

```python
# Формат episode_card на MVP:
{
    "message_id": "uuid",
    "created_at": "2026-01-15T10:30:00Z",
    "snippet": "",  # пустая — snippet генерация в Фазе 2
    "raw": "Сегодня ходила с Лейлой по моллу, она обожает Zara...",  # head+tail или полный
}
```

**Head+tail excerpt:**

Отрицание, уточнение, ключевое «но» часто в конце сообщения:
- «Сегодня ходила с Лейлой, она обожает Zara, а мне **не очень**»
- «Примерила платье, красивое, **но не мой размер**»
- «Нравится всё **кроме открытых плечей**»

```python
def head_tail_excerpt(content: str, max_chars: int = 500) -> str:
    """Первые 280 + последние 220 символов. Сохраняет начало И конец."""
    if len(content) <= max_chars:
        return content  # короткое — целиком
    head = content[:280]
    tail = content[-220:]
    return f"{head} [...] {tail}"
```

```sql
-- В Hybrid Search SQL (raw_excerpt):
CASE
    WHEN LENGTH(content) <= 500 THEN content
    WHEN memory_type IN ('fact', 'event') AND LENGTH(content) <= 1500 THEN content
    WHEN memory_type IN ('fact', 'event') THEN LEFT(content, 800) || ' [...] ' || RIGHT(content, 400)
    ELSE LEFT(content, 280) || ' [...] ' || RIGHT(content, 220)
END AS raw_excerpt
```

**Обновлённый Hybrid Search SQL — episode_card (MVP):**

```sql
SELECT
    id,
    -- snippet = '' на MVP (lazy gen в Фазе 2)
    CASE 
        WHEN role = 'assistant' AND response_description IS NOT NULL 
            THEN response_description
        ELSE COALESCE(memory_snippet, '')
    END AS snippet,
    -- raw excerpt (первоисточник, авторитетен) — head+tail
    CASE
        WHEN LENGTH(content) <= 500 THEN content
        WHEN memory_type IN ('fact', 'event') AND LENGTH(content) <= 1500 THEN content
        WHEN memory_type IN ('fact', 'event') THEN LEFT(content, 800) || ' [...] ' || RIGHT(content, 400)
        ELSE LEFT(content, 280) || ' [...] ' || RIGHT(content, 220)
    END AS raw_excerpt,
    created_at,
    role,
    final_score
FROM merged
...
```

### Приоритет: До MVP ($0, SQL change)

---

## Фикс 4B: Lazy Snippet Generation (Фаза 2)

### Проблема

На MVP snippet = '' — episode_card содержит только raw_excerpt. Для навигации по большим контекстам (300+ сообщений) полезны короткие индексы.

### Решение: Lazy snippet generation + кеширование

```
Шаг 1: При INSERT → memory_snippet = NULL
Шаг 2: При Hybrid Search → snippet = COALESCE(memory_snippet, '')
Шаг 3: ASYNC после ответа: для TOP-N результатов где snippet IS NULL →
        LLM-генерация → UPDATE memory_snippet
Шаг 4: Следующий retrieval → snippet из кеша
```

**Промпт для snippet (DeepSeek):**

```
Сожми сообщение в индекс (макс 120 символов).
Сохрани: субъект (кто говорит о ком), ключевой факт, отрицания.
НЕ интерпретируй — только рефразинг.
НЕ теряй: кто субъект (юзер или другой человек), слова отрицания.

Пример:
Вход: "Сегодня ходила с Лейлой по моллу, она обожает Zara, каждый раз туда тащит"
Выход: "С подругой Лейлой в молле. Лейла (не юзер) любит Zara"
```

**Обновлённый Hybrid Search SQL — episode_card:**

```sql
SELECT
    id,
    -- snippet (индекс, неавторитетен)
    -- Если snippet не сгенерирован — пустая строка, НЕ обрезка контента.
    -- LEFT(content, N) создаёт псевдо-резюме, которое LLM может принять за факт.
    CASE 
        WHEN role = 'assistant' AND response_description IS NOT NULL 
            THEN response_description
        ELSE COALESCE(memory_snippet, '')
    END AS snippet,
    -- raw excerpt (первоисточник, авторитетен) — head+tail
    CASE
        WHEN LENGTH(content) <= 400 THEN content
        ELSE LEFT(content, 220) || ' [...] ' || RIGHT(content, 180)
    END AS raw_excerpt,
    created_at,
    role,
    final_score
FROM merged
...
```

**Правила snippet (Фаза 2):**
- Макс 120 символов. Для навигации, не для доверия.
- Для fact/event — **не генерировать snippet**, полный raw.
- Для коротких (<200 chars) — **не генерировать snippet**, полный raw.
- Snippet fallback = '' (пустая строка), НЕ LEFT(content, N).

### Приоритет: Фаза 2 (~$80/мес за DeepSeek lazy gen)

---

## Фикс 5: Evidence Span ±1 (User Knowledge + Retrieval)

### Проблема

evidence_message_ids хранит одиночные id. Но одно сообщение без соседей теряет контекст (сарказм, отрицание, «это про подругу»). Та же проблема в Semantic Retrieval: эпизод «Второй!» или «Да, беру» бессмысленен без предыдущего assistant-ответа.

### Решение: ±1 span везде

**A) User Knowledge evidence** — при записи факта автоматически расширять окно. Evidence может приходить из разных сессий/дней, поэтому span работает по message_id → lookup conversation_id, не требует единый conversation_id:

```python
def expand_evidence_span(message_ids: list[UUID]) -> list[UUID]:
    """Расширить evidence до span: ±1 сообщение вокруг каждого evidence.
    Работает через lookup — evidence могут быть из разных дней/сессий."""
    expanded = set()
    for msg_id in message_ids:
        neighbors = db.execute("""
            WITH target AS (
                SELECT conversation_id, created_at 
                FROM messages WHERE id = %s
            )
            SELECT id FROM (
                (SELECT id FROM messages m, target t
                 WHERE m.conversation_id = t.conversation_id
                   AND m.created_at < t.created_at
                 ORDER BY m.created_at DESC LIMIT 1)
                UNION ALL
                (SELECT %s AS id)
                UNION ALL
                (SELECT id FROM messages m, target t
                 WHERE m.conversation_id = t.conversation_id
                   AND m.created_at > t.created_at
                 ORDER BY m.created_at ASC LIMIT 1)
            ) AS span
        """, msg_id, msg_id)
        expanded.update(neighbors)
    return list(expanded)
```

**B) Semantic Retrieval episodes** — при сборке ContextPack, если top-N эпизод короткий или указательный, автоматически подгружать ±1:

**Исключение для очень коротких запросов:** Если ТЕКУЩИЙ ЗАПРОС юзера < 30 символов ("ок", "да", "этот"), cosine similarity к query будет шумным → не расширять span, включать только core_evidence.

**Исключение для NEEDS_SPAN эпизодов:** Если эпизод в retrieval помечен как короткий/указательный (< 50 chars), assistant-before считается core_context и НЕ фильтруется cosine в Privacy Guard. Без этого голосовые ответы ("второй!") теряют смысл.

```python
def enrich_episode_with_span(episode: dict, conversation_id: UUID) -> dict:
    """
    Для коротких/указательных эпизодов — добавить соседей.
    Особенно: "да", "нет", "второй", "беру", "этот", <50 символов.
    """
    NEEDS_SPAN = (
        len(episode['raw_excerpt']) < 50
        or re.match(r'^(да|нет|ага|этот|тот|первый|второй|третий|беру|ок)\b', 
                    episode['raw_excerpt'], re.IGNORECASE)
    )
    
    if NEEDS_SPAN:
        # Подтянуть предыдущий assistant + user перед этим сообщением
        context = db.execute("""
            SELECT role, LEFT(content, 200) AS text
            FROM messages
            WHERE conversation_id = %s
              AND created_at < %s
            ORDER BY created_at DESC
            LIMIT 2
        """, conversation_id, episode['created_at'])
        episode['span_context'] = context  # assistant: "Вот 3 образа..." + user context
    
    return episode
```

**Стоимость:** +2 сообщения × ~50 токенов = ~100 токенов на эпизод. При 5-7 эпизодах в ContextPack — пренебрежимо.

### Приоритет

**A) User Knowledge evidence span** — Фаза 2 (вместе с Фикс 1B).

**B) NEEDS_SPAN для Semantic Retrieval** — **до MVP**. Без span-контекста короткие голосовые эпизоды (<50 символов: «Второй!», «Да, беру», «Не, цвет не мой») попадают в ContextPack без контекста предыдущего assistant-ответа и становятся бессмысленными для LLM. Это критично для voice-first UX, где 30-40% ответов юзера — короткие реакции. На MVP реализовать `enrich_episode_with_span` (B) **без Privacy Guard** (Фикс 12) — Privacy Guard добавляется в Фазе 2.

**C) Полный span + Privacy Guard** — Фаза 2.

---

## Фикс 6: Memory Density Cap — адаптивный лимит

### Проблема

Cap ≤3 snippet, ≤30% контекста — фиксированный. При зрелом профиле (6+ месяцев, ~700 сообщений) 3 эпизода покрывают максимум 3 темы.

### Решение

```python
def get_memory_density_cap(stage: int, total_messages: int) -> tuple[int, float]:
    """Возвращает (max_snippets, max_context_pct)"""
    if total_messages < 50:     # новый юзер
        return (3, 0.30)
    elif total_messages < 300:  # активный 1-3 мес
        return (5, 0.35)
    else:                       # зрелый профиль
        return (7, 0.40)
```

**Примечание:** С Фиксом 4 каждый эпизод содержит snippet + raw_excerpt (~300 символов = ~75 токенов). 7 эпизодов × 75 = ~525 токенов. При контексте 3-5K — в рамках 40%.

### Приоритет: Фаза 3

---

## Фикс 7: Emotional Filter — мягкий, не бинарный

### Проблема

Emotional filter может убрать эпизоды с негативной эмоцией, даже если они содержат критически важный факт.

### Решение

```python
def emotional_filter(candidates: list, mood_frame: dict) -> list:
    """
    Не удалять кандидатов. Переранжировать.
    fact/preference/event — не трогать (информационно ценны).
    emotion при несовпадении mood — понизить score на 20%.
    """
    for c in candidates:
        if c.memory_type == 'emotion' and mood_mismatch(c.mood_frame, mood_frame):
            c.final_score *= 0.8
    return sorted(candidates, key=lambda x: x.final_score, reverse=True)
```

### Приоритет: Фаза 2

---

## Фикс 8: FTS — multilingual morphology

### Проблема

`tsvector` с 'simple' = точные токены. «Платье» ≠ «платья». Арабский ещё сложнее: «فساتين» (платья) ≠ «فستان» (платье), корневая морфология (3-буквенные корни).

### Решение

```sql
-- Фаза 2: dual-config для русского + английского
tsv tsvector GENERATED ALWAYS AS (
    setweight(to_tsvector('simple', COALESCE(response_description, '')), 'A')
    ||
    setweight(to_tsvector('russian', content), 'B')
    ||
    setweight(to_tsvector('english', content), 'C')
) STORED;

-- Для арабского: PostgreSQL не имеет встроенной 'arabic' конфигурации.
-- Опции:
-- 1. hunspell-ar extension (если доступно)
-- 2. pg_arabic_stemmer (custom dictionary)
-- 3. На MVP: 'simple' для арабского + усиленный vector search (Cohere multilingual)
-- 4. Arabizi: 'simple' достаточно (латиница без морфологии)
-- Рекомендация MVP: vector search компенсирует отсутствие арабского FTS.
-- Phase 2: добавить stemmer или custom dictionary.
```

### Приоритет: Фаза 2 (русский+английский); Arabic stemmer — Фаза 3

---

## Фикс 9: Async enrichment — приоритетная очередь

### Проблема

Embedding ASYNC → в быстрых обменах свежие сообщения не в vector search.

### Решение

Приоритетная очередь (high/normal) + fallback в Hybrid Search для сообщений без embedding:

```sql
-- Свежие сообщения без embedding (ещё в очереди)
UNION ALL
SELECT id, content, memory_snippet, memory_type,
       memory_confidence, created_at, role, response_description,
       0.6 AS vec_score, 0 AS fts_score
FROM messages
WHERE conversation_id = $2
  AND role = 'user'
  AND is_embeddable = TRUE
  AND is_forgotten = FALSE
  AND embedding IS NULL
  AND created_at > NOW() - INTERVAL '5 minutes'
```

### Приоритет: Фаза 2

---

## Фикс 10: Арбитраж между слоями — в промпте

### Проблема

User Knowledge и Chat History эпизоды могут противоречить. Нет арбитра.

### Решение

Добавить в system prompt LLM Orchestrator:

```
ПРАВИЛА ПРИОРИТЕТА ЗНАНИЙ:

1. Последние 10 сообщений > всё остальное (текущий контекст)

2. Свежие эпизоды из Semantic Retrieval > старые факты из User Knowledge
   Если эпизод последних 30 дней противоречит факту старше 90 дней —
   доверяй эпизоду, мягко уточни у юзера.

3. User Knowledge с extracted_from='instant_pattern' или 'onboarding'
   и confidence ≥0.9 → высшая надёжность (размер, аллергия, бюджет)

4. В каждом эпизоде есть snippet и raw_excerpt.
   Snippet — ТОЛЬКО для навигации, НЕ для доверия.
   Смысл извлекай ТОЛЬКО из raw_excerpt.
   При конфликте snippet vs raw_excerpt — ИГНОРИРУЙ snippet полностью.

5. Если эпизод содержит span_context (соседние сообщения) —
   используй их для понимания контекста (сарказм, отсылки, субъект).

6. При любом противоречии — лучше уточнить у юзера, чем угадывать.
   Пример: «Вижу, ты стала интересоваться принтами — это новое направление?»

7. Если в контексте есть личная/чувствительная информация, не связанная
   с текущим запросом — НЕ упоминай её. Друг знает, когда молчать.

8. Если факт в User Knowledge помечен is_disputed — НЕ утверждай его.
   Мягко уточни: «Кажется, я ошибся раньше — помоги разобраться?»
```

### Приоритет: До MVP

---

## Фикс 11: Memory Correction Loop

### Проблема (риск 1.2, 6.2)

UNDE говорит «Ты же любишь Zara», юзер отвечает «Нет, с чего ты взял?». Сейчас нет механизма, который:
- исправит ошибочный факт в User Knowledge
- научит batch extraction не повторять эту ошибку
- зафиксирует негативный feedback для мониторинга

Без этого UNDE будет повторять ошибку — разрушение доверия.

### Решение: Instant Correction Patterns + Feedback

```python
# Уровень 1: Instant correction patterns (sync, при INSERT user-сообщения)
CORRECTION_PATTERNS = [
    r"нет,?\s+(?:я\s+)?не\s+(?:люблю|ношу|хочу)\s+(.+?)(?:\.|,|$)",
    r"(?:с чего|откуда)\s+(?:ты\s+)?(?:взял[аи]?|решил[аи]?)",
    r"no,?\s+I\s+(?:don'?t|never)\s+(?:like|wear|want)\s+(.+?)(?:\.|,|$)",
    r"ты\s+(?:путаешь|ошибаешься|неправильно)",
]

# При срабатывании:
# 1. Пометить ПРЕДЫДУЩИЙ assistant-ответ как correction_trigger
# 2. Определить режим коррекции:
#    a) Если denial ЯВНЫЙ и привязан к конкретному knowledge_key
#       ("нет, мой размер не M") → is_active = FALSE
#    b) Если denial НЕОДНОЗНАЧНЫЙ ("с чего ты взял?", "ты путаешь")
#       → is_disputed = TRUE на ПОСЛЕДНЕЙ АКТИВНОЙ записи по (type, key)
#       Новая запись НЕ вставляется (иначе нарушится UNIQUE INDEX).
#       Правило в промпте: "если факт disputed — мягко уточни, не утверждай"
#       Если юзер подтверждает факт → is_disputed = FALSE (факт восстановлен)
#       Если юзер опровергает → is_active = FALSE (факт убит)
# 3. Записать в correction log с corrected_message_id (обязательно при "с чего ты взял")
#    corrected_message_id = ОБЯЗАТЕЛЬНО для паттернов "с чего ты взял / ты путаешь"
#    Без него невозможно строить golden tests, привязанные к конкретному claim.
# 4. LLM в текущем ответе: извиниться и уточнить правду

# Уровень 2: Feedback loop для batch extraction
# correction events → golden tests → prompt tuning
```

```sql
CREATE TABLE memory_correction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    trigger_message_id UUID NOT NULL,       -- user: "нет, я не люблю Zara"
    corrected_message_id UUID,              -- assistant: "Ты же любишь Zara" (обязательно при "с чего ты взял")
    deactivated_knowledge_id UUID,          -- если был факт в UK → deactivated
    disputed_knowledge_id UUID,             -- если было → disputed (не deactivated)
    correction_type VARCHAR(30),            -- 'user_denied', 'wrong_subject', 'outdated', 'ambiguous'
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

**Два уровня метрик:**
- `unde_memory_correction_total{type}` — все коррекции (включая disputed). Алерт: > 3% → batch prompt tuning.
- `unde_memory_correction_uk_deactivated_total` — только те, где факт реально деактивирован. Это серьёзнее: если > 1% → batch extraction создаёт ложные факты.

**Auto-fallback:** Если `correction_uk_deactivated_rate > 3%` → временно отключить batch extraction, полагаться на instant + RAW до тюнинга промпта.

### Приоритет: Фаза 2

---

## Фикс 12: Privacy Guard на Evidence Span

### Проблема (риск 2.2)

Evidence span ±1 подтягивает соседние сообщения. Эти соседи могут содержать приватную информацию, не относящуюся к текущему запросу. Пример: юзер обсуждал одежду → рядом сообщение про личные проблемы → span подтянул → LLM неуклюже упомянул.

Эффект «сталкера» вместо «близкого друга».

### Решение

```python
def privacy_filter_span(span_messages: list, current_query_embedding, lang_code: str = 'en') -> list:
    """
    Фильтровать span-соседей по релевантности к текущему запросу.
    Adaptive threshold по языку: арабские embeddings менее точны.
    """
    THRESHOLDS = {'ru': 0.3, 'en': 0.3, 'ar': 0.25, 'arabizi': 0.25, 'mixed': 0.25}
    threshold = THRESHOLDS.get(lang_code, 0.28)
    
    filtered = []
    for msg in span_messages:
        if msg['is_core_evidence']:
            filtered.append(msg)  # core evidence — всегда включать
        elif msg.get('is_needs_span_context'):
            filtered.append(msg)  # assistant-before для коротких эпизодов — включать
        elif msg.get('embedding') is None:
            # Embedding ещё не готов (race condition) — включать только если core
            # НЕ включать соседей без embedding (слепой фильтр опаснее включения)
            continue
        else:
            sim = cosine_similarity(msg['embedding'], current_query_embedding)
            if sim >= threshold:
                filtered.append(msg)
    return filtered
```

**Дополнительно:** В system prompt (Фикс 10) добавить правило:

```
7. Если в контексте есть личная/чувствительная информация, не связанная
   с текущим запросом — НЕ упоминай её. Друг знает, когда молчать.
```

### Приоритет: Фаза 2

---

## Фикс 13: Naturalness Directive

### Проблема (риск 3.1)

Precomputed snippets и response_description (template-based: «burgundy midi cotton skirt Zara Dubai Hills Mall») могут попасть в ContextPack в техническом формате. Если LLM скопирует их в ответ — «робот», не «друг».

### Решение

Добавить в system prompt (блок persona_directive):

```
ПРАВИЛА ЕСТЕСТВЕННОСТИ ПАМЯТИ:

- НИКОГДА не цитируй snippet, response_description или episode_card дословно.
- Переформулируй воспоминание естественным языком:
  ✗ «В эпизоде от 15.01 ты говорила про burgundy midi cotton skirt в Zara Dubai Hills Mall»
  ✓ «Помнишь, ты присматривала бордовую юбку в Zara? Как тебе такой вариант?»
- Не указывай даты, message_id, score — юзер не знает о внутренней механике.
- Если не уверен, что воспоминание уместно в текущем контексте — не упоминай его.
  Лучше пропустить, чем вставить неестественно.
- Если память звучит слишком конкретно или неожиданно — переформулируй как
  вопрос-уточнение, а не как утверждение:
  ✗ «Ты носишь размер M» (утверждение)
  ✓ «Тебе ведь M подходит, верно?» (уточнение)
  Это бренд: «рядом, не сверху».
- МУЛЬТИЯЗЫЧНОСТЬ: отвечай на языке юзера. Если юзер пишет на арабском —
  отвечай на арабском. Если смешивает — подстраивайся под доминирующий язык.
  НЕ переводи воспоминания: если юзер сказал «مابي leather», вспоминай
  «помнишь, ты не хотела кожу?» на его языке, не цитируй raw дословно.
```

### Приоритет: До MVP (текстовое изменение, ноль кода)

---

## Фикс 14: Enrichment TTL Guarantee

### Проблема (риск 4.1)

Priority enrichment queue может переполниться. Сообщения без embedding после сбоя могут остаться «невидимыми» для vector branch навсегда. UNDE «забудет» часть разговора.

### Решение

```python
# Cron job: каждые 6 часов
# Найти сообщения старше 1 часа без embedding → force enrich

SELECT id FROM messages
WHERE embedding IS NULL
  AND is_embeddable = TRUE
  AND is_forgotten = FALSE
  AND created_at < NOW() - INTERVAL '1 hour'
  AND created_at > NOW() - INTERVAL '7 days'  -- не трогать ancient
  AND (enrichment_retry_count IS NULL OR enrichment_retry_count < 3)  -- защита от вечного ретрая
ORDER BY created_at DESC
LIMIT 500;

# → отправить в enrichment queue с priority='recovery'
# При каждой попытке: enrichment_retry_count += 1, last_retry_at = NOW()
# После 3 неудач — сообщение помечается как orphan, алерт в мониторинг
```

**Мониторинг:** `unde_orphan_messages_total` — сообщения без embedding старше 1 часа. Алерт: > 100 → enrichment pipeline проблема.

### Приоритет: Фаза 2

---

## Фикс 15: Snippet Cascade при Soft Forget

### Проблема (риск 2.2, 2.3)

Soft forget обнуляет embedding и snippet САМОГО сообщения. Но если другие сообщения имеют snippet, который ССЫЛАЕТСЯ на забытое (например, snippet соседа содержит контекст забытого), — утечка.

### Решение

```python
def cascade_forget(message_id: UUID):
    """При soft forget — проверить, не ссылаются ли другие snippets на этот контекст."""
    # 1. Стандартный soft forget
    db.execute("""
        UPDATE messages 
        SET is_forgotten = TRUE, embedding = NULL, memory_snippet = NULL
        WHERE id = %s
    """, message_id)
    
    # 2. Обнулить snippets соседей (±1 сообщение, не ±1 мин — надёжнее)
    db.execute("""
        UPDATE messages SET memory_snippet = NULL
        WHERE id IN (
            -- предыдущее сообщение
            (SELECT id FROM messages
             WHERE conversation_id = (SELECT conversation_id FROM messages WHERE id = %s)
               AND created_at < (SELECT created_at FROM messages WHERE id = %s)
             ORDER BY created_at DESC LIMIT 1)
            UNION
            -- следующее сообщение
            (SELECT id FROM messages
             WHERE conversation_id = (SELECT conversation_id FROM messages WHERE id = %s)
               AND created_at > (SELECT created_at FROM messages WHERE id = %s)
             ORDER BY created_at ASC LIMIT 1)
        )
    """, message_id, message_id, message_id, message_id)
    # Snippets будут перегенерированы при следующем retrieval (lazy gen)
    
    # 3. Обнулить response_description у assistant-ответов в цепочке
    #    Два пути: reply_to_id ИЛИ следующий assistant-ответ по времени
    #    (не все пары связаны через reply_to_id на практике)
    db.execute("""
        UPDATE messages SET response_description = NULL
        WHERE role = 'assistant'
          AND conversation_id = (SELECT conversation_id FROM messages WHERE id = %s)
          AND (
              reply_to_id = %s
              OR id = (
                  SELECT id FROM messages
                  WHERE conversation_id = (SELECT conversation_id FROM messages WHERE id = %s)
                    AND role = 'assistant'
                    AND created_at > (SELECT created_at FROM messages WHERE id = %s)
                  ORDER BY created_at ASC LIMIT 1
              )
          )
    """, message_id, message_id, message_id, message_id)
    
    # 4. Деактивировать User Knowledge, где evidence включает этот message
    #    ИСКЛЮЧЕНИЕ: onboarding facts (evidence_message_ids = '{}') не деактивируются
    #    через cascade — только если юзер явно поправил через instant/correction.
    db.execute("""
        UPDATE user_knowledge SET is_active = FALSE
        WHERE %s = ANY(evidence_message_ids)
          AND extracted_from != 'onboarding'
    """, message_id)
```

### Приоритет: До MVP (критично для доверия)

---

## Схема БД — дополнения к Dubai Shard

```sql
-- Поля в user_knowledge
ALTER TABLE user_knowledge ADD COLUMN evidence_message_ids UUID[] NOT NULL DEFAULT '{}';
ALTER TABLE user_knowledge ADD COLUMN expires_at TIMESTAMPTZ;
ALTER TABLE user_knowledge ADD COLUMN knowledge_key VARCHAR(100) NOT NULL;
ALTER TABLE user_knowledge ADD COLUMN is_disputed BOOLEAN DEFAULT FALSE;

-- Enforce Epistemic Contract Правило 2
ALTER TABLE user_knowledge ADD CONSTRAINT chk_evidence_required
    CHECK (
        cardinality(evidence_message_ids) > 0
        OR extracted_from = 'onboarding'
    );

-- GIN индекс для быстрого поиска по evidence (Фикс 15: cascade forget)
CREATE INDEX idx_knowledge_evidence_gin 
    ON user_knowledge USING GIN (evidence_message_ids);

-- Уникальность: один активный факт на (user, type, key)
CREATE UNIQUE INDEX idx_knowledge_active_unique 
    ON user_knowledge(user_id, knowledge_type, knowledge_key) 
    WHERE is_active = TRUE;

-- Memory correction log (Фикс 11)
CREATE TABLE memory_correction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    trigger_message_id UUID NOT NULL,
    corrected_message_id UUID,
    deactivated_knowledge_id UUID,
    disputed_knowledge_id UUID,
    correction_type VARCHAR(30),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_correction_user ON memory_correction_log(user_id, created_at DESC);

-- Трекинг extraction runs (для Фазы 2)
CREATE TABLE knowledge_extraction_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    triggered_by VARCHAR(30) NOT NULL,
    messages_analyzed INTEGER NOT NULL,
    deltas_applied INTEGER DEFAULT 0,
    llm_model VARCHAR(50),
    input_tokens INTEGER,
    output_tokens INTEGER,
    duration_ms INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_extraction_user ON knowledge_extraction_log(user_id, created_at DESC);

-- Поля в conversations для трекинга
ALTER TABLE conversations ADD COLUMN last_extraction_at TIMESTAMPTZ;
ALTER TABLE conversations ADD COLUMN pending_extraction_count INTEGER DEFAULT 0;
```

---

## Обновлённый Data Flow

```
📱 → App Server → LLM Orchestrator
                         │
                    ┌─────┴──────────────────────────────┐
                    │ Фаза 1: SYNC при INSERT             │
                    │                                      │
                    │ 1. Сохранить message в Chat History  │
                    │    (tsvector SYNC, embedding ASYNC)  │
                    │                                      │
                    │ 2. Instant Pattern Match (Фикс 1A)  │
                    │    regex → body_params, allergy,     │
                    │    budget, hard_ban                  │
                    │    → INSERT/supersede user_knowledge │
                    │    → evidence_message_ids с ±1 span  │
                    │                                      │
                    │ 3. pending_extraction_count += 1     │
                    └─────┬──────────────────────────────┘
                          │
                    ┌─────┴──────────────────────────────┐
                    │ Фаза 2-3: ContextPack               │
                    │                                      │
                    │ Hybrid Search → TOP-N эпизодов      │
                    │ (snippet + raw_excerpt + msg_id)     │
                    │ + User Knowledge (guaranteed facts)  │
                    │ + последние 10 сообщений             │
                    │ + emotional filter (мягкий)          │
                    │ + Memory Density Cap (адаптивный)    │
                    │ + арбитраж в промпте (Фикс 10)      │
                    │ → LLM API → response                 │
                    └─────┬──────────────────────────────┘
                          │
                    ┌─────┴──────────────────────────────┐
                    │ ASYNC:                               │
                    │                                      │
                    │ 1. Embedding (priority queue, Ф.9)   │
                    │ 2. Lazy snippet gen (Фикс 4B)       │
                    │ 3. Persona feedback                  │
                    │ 4. [Фаза 2] Batch Extraction (1B)   │
                    │    если pending ≥ 15 или gap > 30m   │
                    └──────────────────────────────────────┘
```

---

## Стоимость всех фиксов (при 50K MAU, модель v3)

| Фикс | Фаза | Доп. стоимость/мес | Примечание |
|------|------|--------------------|------------|
| 1A: Instant patterns | MVP | $0 | Regex |
| 2: Supersede trigger | MVP | $0 | SQL trigger |
| 3: Сужение scope + expires_at | MVP | $0 | Миграция |
| 4A: Episode card (raw excerpt) | MVP | $0 | SQL change |
| 10: Арбитраж в промпте | MVP | $0 | Текст |
| 13: Naturalness directive | MVP | $0 | Текст в промпте |
| 15: Snippet cascade при forget | MVP | $0 | Python |
| 5B: NEEDS_SPAN для retrieval | MVP | $0 | Python + SQL |
| 1B: Batch extraction | Фаза 2 | ~$440 | DeepSeek |
| 4B: Lazy snippet gen | Фаза 2 | ~$80 | DeepSeek |
| 5A+C: Evidence span UK + Privacy Guard | Фаза 2 | $0 | SQL + Python |
| 7: Мягкий emotional filter | Фаза 2 | $0 | Логика |
| 9: Priority enrichment | Фаза 2 | $0 | Celery |
| 11: Memory correction loop | Фаза 2 | $0 | Regex + SQL |
| 12: Privacy guard на span | Фаза 2 | $0 | Python |
| 14: Enrichment TTL guarantee | Фаза 2 | $0 | Cron |
| 6: Адаптивный Cap | Фаза 3 | $0 | Логика |
| 8: FTS morphology (ru+en) | Фаза 2 | $0 | SQL |
| 8b: FTS Arabic stemmer | Фаза 3 | $0 | Extension |
| **Итого** | | **~$520/мес** | **+1.6% к бюджету v3** |

---

## Приоритеты реализации

### До MVP (8 фиксов, все бесплатные)

| # | Фикс | Что делать | Effort |
|---|------|-----------|--------|
| 1 | **Фикс 1A** | Regex patterns в LLM Orchestrator | 1 день |
| 2 | **Фикс 2** | SQL trigger supersede_knowledge() с knowledge_key | 0.5 дня |
| 3 | **Фикс 3** | ALTER TABLE + миграция soft→inactive | 0.5 дня |
| 4 | **Фикс 4A** | raw_excerpt (head+tail) в Hybrid Search SQL | 0.5 дня |
| 5 | **Фикс 5B** | NEEDS_SPAN для Semantic Retrieval (без Privacy Guard) | 0.5 дня |
| 6 | **Фикс 10** | Арбитраж + privacy + disputed rules в system prompt | 0.5 дня |
| 7 | **Фикс 13** | Naturalness directive в persona_directive | 0.5 дня |
| 8 | **Фикс 15** | Snippet cascade при soft forget | 0.5 дня |

**Итого MVP: ~4.5 дня, $0 доп. расходов.**

На MVP система работает так: User Knowledge содержит только hard facts (из onboarding + instant patterns). Всё остальное — в сырой Chat History, извлекается Semantic Retrieval в момент запроса. LLM интерпретирует сырые эпизоды с полным контекстом. Это чистая архитектура с одним источником правды.

### Фаза 2 (первые 1-3 месяца, по данным с реальных юзеров)

| # | Фикс | Зависимость |
|---|------|-------------|
| 5 | **Фикс 1B** | Валидация на реальных данных: действительно ли Semantic Retrieval пропускает факты? |
| 6 | **Фикс 4B** | Lazy snippet generation + кеширование |
| 7 | **Фикс 5A+C** | Evidence span для User Knowledge + Privacy Guard на span (NEEDS_SPAN уже в MVP) |
| 8 | **Фикс 7** | Мягкий emotional filter |
| 9 | **Фикс 9** | Priority enrichment |
| 10 | **Фикс 11** | Memory correction loop |
| 11 | **Фикс 12** | Privacy guard на span |
| 12 | **Фикс 14** | Enrichment TTL guarantee |
| 13 | **Фикс 8** | FTS morphology (русский + английский) |

**Критерий запуска Фикса 1B:** если мониторинг покажет, что Semantic Retrieval стабильно пропускает факты, которые должны быть в ContextPack (метрика: юзер повторяет информацию, которую уже говорил) — тогда batch extraction оправдан. Если retrieval справляется — 1B не нужен.

### Фаза 3 (3-6 месяцев)

| # | Фикс | Условие |
|---|------|---------|
| 10 | **Фикс 6** | Когда средний total_messages > 300 |
| 11 | **Фикс 8b** | Arabic stemmer, когда аудитория подтверждена |

### Post-MVP бэклог — бренд-механики (отдельные спецификации)

Следующие механики описаны в [UNDE_Brand_Platform.md](../UNDE_Brand_Platform.md), но НЕ входят в MVP и текущие технические документы. Требуют отдельных спецификаций.

| Механика | Бренд-раздел | Что нужно специфицировать | Зависимости |
|---|---|---|---|
| **Зеркало физического мира** (прокачка аватара) | 6.1 | Activity tracking (GPS, шагомер, calendar), skill/XP система, маппинг активностей → визуал аватара, хранение «уровней прокачки», Rive-эволюция | App SDK (HealthKit/Google Fit), Dubai Shard, Rive asset pipeline |
| **Тайная комната** | 6.2 | Data model (приватные заметки, файлы, скрытые наряды), UI спецификация, шифрование, access control | Dubai Shard (encrypted storage), App UI, Object Storage |
| **The Blink** (ритуал разблокировки) | 6.5 | Face tracking SDK, blink pattern recognition, хранение паттерна, fallback (PIN), интеграция с Тайной комнатой | App SDK (ARKit/ARCore), on-device ML |
| **Поэтапное открытие функций** | 6.3 | Триггеры разблокировки, UI «исключительного клуба», premium-стилист | Gamification engine, Persona Agent (stage расширение) |

**Принцип:** MVP запускается на чистой архитектуре (3 слоя знания + Epistemic Contract). Бренд-механики добавляются итеративно после валидации базовой модели на реальных юзерах.

---

## Golden Tests

| # | Тест | Ожидание | Фаза |
|---|------|----------|------|
| K1 | «Мой размер теперь M» | Instant: body_params = M, supersede S, evidence span ±1 | MVP |
| K2 | «Аллергия на никель» | Instant: allergy = nickel, confidence 0.95 | MVP |
| K3 | «Бюджет до 500 дирхам» | Instant: budget = 500 AED | MVP |
| K4 | «Никогда не предлагай открытые плечи» | Instant: hard_ban | MVP |
| K5 | UK: minimalist; Chat: 5× запросы про принты | LLM уточняет (арбитраж, Фикс 10) | MVP |
| K6 | life_event: «свадьба сестры в марте» → апрель | expires_at → is_active=FALSE | MVP |
| **K6b** | **«Через 2 недели свадьба сестры»** | **Instant: life_event, key=wedding_sister, expires_at=NOW()+14d** | **MVP** |
| **K6c** | **«عندي عرس أختي بعد شهر»** | **Instant: life_event, key=wedding_sister (Arabic)** | **MVP** |
| **K6d** | **«Скоро переезд»** | **Instant: life_event, key=move, expires_at=NOW()+30d (нет даты)** | **MVP** |
| K7 | «Подруга обожает Zara, мне больше MD» | Batch: Zara НЕ записано (subject=other) | Фаза 2 |
| K8 | Сарказм после 3 минималист-ответов | Batch: НЕ записывать | Фаза 2 |
| K9 | «Поел хорошо» → [новая сессия] → «было плохо» | Batch кумулятивный: негативный опыт | Фаза 2 |
| K10 | 4 сообщения за 20 секунд | Все в Hybrid Search (priority queue) | Фаза 2 |
| K11 | Episode card в ContextPack | Содержит snippet + raw_excerpt + id | Фаза 2 |
| K12 | UNDE: «Ты же любишь Zara» → User: «Нет!» | Correction: факт deactivated, извинение | Фаза 2 |
| K12b | UNDE: «Ты же любишь Zara» → User: «С чего ты взял?» | Correction: факт DISPUTED (не deactivated), уточнение | Фаза 2 |
| K13 | Эпизод про одежду, сосед — личные проблемы | Privacy guard: сосед НЕ попадает в ContextPack | Фаза 2 |
| K14 | LLM ответ содержит episode_card формулировку | Naturalness: ответ переформулирован, нет дат/id/score | MVP |
| K15 | User нажал «забудь» на сообщение | Cascade: snippet соседей обнулён, UK с этим evidence деактивирован | MVP |
| K16 | Сообщение без embedding через 2 часа | Enrichment TTL: force enrich, orphan metric | Фаза 2 |
| K17 | allergy='nickel' + allergy='wool' | Обе активны, supersede по key не убивает вторую | MVP |
| **K18** | **«مقاسي M بس مابي open shoulders»** | **Instant: body_params=M + hard_ban=open_shoulders (code-switching, один msg)** | **MVP** |
| **K19** | **«7asasiya min nickel»** | **Instant: allergy=nickel (Arabizi)** | **MVP** |
| **K20** | **«مابغى جلد ولا صوف»** | **Instant: hard_ban=leather + hard_ban=wool (Gulf Arabic, 2 bans в одном msg)** | **MVP** |
| **K21** | **«bajt 2000 dhs max يعني mabi أصرف more»** | **Instant: budget=2000 AED (3 языка в одной фразе)** | **MVP** |
| **K22** | **User пишет на ar, UNDE отвечает на en, user: «لا غلط، مو M، أنا S»** | **Correction: body_params supersede M→S (correction на арабском)** | **MVP** |
| **K23** | **«wallah this dress 7ilu بس overpriced شوي»** | **Batch: НЕ записывать (эмоциональная реакция, слэнг)** | **Фаза 2** |
| **K24** | **Gulf slang: «يبيلي شي casual مو formal وايد»** | **Batch: НЕ обобщать «предпочитает casual» — разовая реакция** | **Фаза 2** |
| K25 | «42» без контекста | НЕ промоутить (может быть обувь/возраст) | MVP |
| K26 | «مقاسي 42 في الملابس» (с якорем «одежда/الملابس») | Instant: body_params = 42 | MVP |
| **K27** | **Юзер 3 мес писал по-русски, перешёл на арабский. Episode cards на ru, запрос на ar: «أبي شي حق الويكند»** | **LLM отвечает на арабском. Воспоминания из русских episodes переформулированы на ar. Не цитирует русский raw дословно.** | **MVP** |
| **K28** | **NEEDS_SPAN: «Второй!» (эпизод <50 chars) попадает в ContextPack** | **Episode card содержит span_context: предыдущий assistant-ответ с вариантами** | **MVP** |

---

## Мониторинг

```yaml
# Instant extraction
unde_instant_extraction_total{type="body_params|allergy|budget|hard_ban", language="ru|en|ar|arabizi|mixed"}
unde_instant_extraction_supersede_total

# Batch extraction (Фаза 2)
unde_batch_extraction_duration_seconds
unde_batch_extraction_deltas_total{operation="add|update|remove|confirm"}
unde_batch_extraction_queue_size
unde_batch_extraction_errors_total

# Snippet generation
unde_snippet_cache_hit_ratio

# Enrichment queue
unde_enrichment_queue_size{priority="high|normal|recovery"}
unde_enrichment_latency_seconds{priority="high|normal"}
unde_orphan_messages_total  # messages без embedding старше 1 часа (Фикс 14)

# Memory corrections (Фикс 11)
unde_memory_correction_total{type="user_denied|wrong_subject|outdated|ambiguous", lang="ru|en|ar|arabizi|mixed"}
unde_memory_correction_uk_deactivated_total{lang="ru|en|ar"}
unde_memory_correction_uk_disputed_total
# Алерт: correction_uk_deactivated > 1% → batch создаёт ложные факты
# Алерт: correction_uk_deactivated > 3% → AUTO-FALLBACK: отключить batch
# Алерт: ar_correction_rate > en_correction_rate * 1.5 → арабские паттерны слабые

# Privacy guard (Фикс 12)
unde_privacy_span_filtered_total  # span-соседей отфильтровано по нерелевантности

# Forget cascade (Фикс 15)
unde_forget_cascade_snippets_nullified_total
unde_forget_cascade_knowledge_deactivated_total

# Качество retrieval (ключевая метрика для решения о Фикс 1B)
#
# ФОРМУЛЫ:
# retrieval_miss_rate = (кол-во exchanges где факт есть в RAW Chat History
#   но НЕ попал в ContextPack через Semantic Retrieval, при этом факт
#   был релевантен текущему запросу) / общее кол-во exchanges
#   Измеряется: offline анализом — сравнение ContextPack vs полная история
#   Порог: > 10% → рассмотреть Фикс 1B
#
# user_repeated_info = (кол-во exchanges где юзер повторяет факт,
#   который уже есть в RAW за последние 90 дней, но не был
#   использован системой в 2+ последних релевантных запросах)
#   / общее кол-во exchanges за неделю
#   Измеряется: детекция повторов через embedding similarity > 0.85
#   между текущим user-сообщением и историей
#   Порог: > 5%/week → Semantic Retrieval не справляется
#
unde_user_repeated_info_count
unde_retrieval_miss_rate

# Staging fallback (v1.2)
unde_staging_fallback_triggered_total  # сколько раз pending_raw попал в ContextPack
unde_pending_extraction_count_p95      # насколько часто batch отстаёт

# Human-in-loop (v1.2, Фаза 2)
unde_extraction_review_error_rate
unde_extraction_review_total{verdict="correct|wrong_subject|false_fact|missed_sarcasm"}
unde_extraction_review_total{language="ru|en|ar|arabizi|mixed"}  # сегментация по языку
# Алерт: если ar_error_rate > en_error_rate на 15% → patterns/prompt нужна доработка
# "mixed" = code-switching (2+ языка в одном сообщении)

# Validator Gate (v1.3, Фаза 2)
unde_validator_gate_total{result="accepted|rejected_low_confidence|rejected_no_anchor"}
unde_validator_rejection_rate          # % отклонённых LLM-предложений

# Алерты:
# - batch_queue > 1000 → scale workers
# - enrichment_latency_p95 > 5s → investigate  
# - retrieval_miss_rate > 10% → рассмотреть запуск Фикс 1B
# - user_repeated_info > 5%/week → Semantic Retrieval не справляется
# - staging_fallback_triggered > 100/hour → batch extraction bottleneck
# - extraction_review_error_rate > 5% → пересмотреть prompt / остановить 1B
# - validator_rejection_rate > 50% → LLM extraction prompt слишком широкий
# - memory_correction_total > 3%/week → batch extraction создаёт ложные факты
# - orphan_messages > 100 → enrichment pipeline проблема
# - forget_cascade_knowledge_deactivated → alert если > 5/day (массовая потеря фактов)
```

---

## Карта рисков и покрытие

Полный анализ рисков выявил 18 угроз в 6 категориях. ID рисков стабильные (R1.1a, R2.2 и т.д.) — используйте как якоря для cross-reference в других документах.

| ID | Риск | Кат. | Покрытие в KSP | Где ещё |
|---|------|------|----------------|---------|
| R1.1a | Ложные срабатывания retrieval | Точность | Фикс 4A (raw excerpt), Фикс 5 (span ±1) | — |
| R1.1b | FTS без морфологии | Точность | Фикс 8 (ru+en Фаза 2; Arabic stemmer Фаза 3) | — |
| R1.1c | Temporal decay bias | Точность | — (дизайн: boost, не penalty) | 04_Shard: λ tuning |
| R1.1d | Diversity filter loss | Точность | — (3/day — осознанный tradeoff) | Мониторинг |
| R1.2 | Ошибки batch extraction | Точность | Validator Gate + confidence <0.8 + human-in-loop | — |
| R1.3 | Противоречия UK vs эпизоды | Точность | Фикс 10 (арбитраж), Фикс 2 (supersede) | — |
| R2.1 | Нежелательные напоминания | Приватн. | Фикс 7 (мягкий filter) | Persona: suppress rules |
| **R2.2** | **Ощущение сталкера** | **Приватн.** | **Фикс 12 + Фикс 13** | — |
| **R2.3** | **Неполное забывание** | **Приватн.** | **Фикс 15 (cascade forget)** | 06_Ops: Forget |
| **R3.1** | **Шаблонные отсылки** | **Естеств.** | **Фикс 13 (naturalness)** | Persona |
| R3.2 | Культурная нечувствительность | Естеств. | Instant patterns (ar+arabizi MVP), multilingual strategy | Context Agent |
| R3.3 | Избыточная проактивность | Естеств. | Memory Density Cap | Context Agent |
| **R4.1** | **Потеря данных (orphan msgs)** | Целостн. | **Фикс 14 (enrichment TTL)** | 04_Shard |
| R4.2 | Неконсистентность шардов | Целостн. | — | 06_Ops: Patroni |
| R4.3 | UK vs RAW расхождение | Целостн. | Epistemic Contract + evidence ptrs | — |
| R5.1 | «Робкая» память | Философия | Memory Density Cap (адаптивный) | Persona |
| R5.2 | Ошибки Mood Agent | Философия | — | Persona Agent |
| R5.3 | Нюансы не в UK | Философия | Фикс 3 (by design: retrieval > extraction) | — |
| R6.1 | Случайное забывание | Forget | — | App UX: confirm + undo |
| **R6.2** | **Нет feedback при ошибке** | **Forget** | **Фикс 11 (correction + DISPUTED)** | — |

**Жирным** = закрыто новыми фиксами v1.6. Остальное — либо уже в v1.5, либо вне scope KSP.

**Вне scope KSP (закрывается в других документах):**
- Mood Agent ошибки → Persona Agent + golden tests
- Persona/voice тон → UNDE_Persona_Voice_Layer (будущий документ)
- OpportunityMatcher частота → Context Agent config
- Forget UX (подтверждение, undo) → App UX specification
- Культурные сценарии (Рамадан, ифтар) → Context Agent + локальные эксперты
- Shard consistency → 06_Operations: Patroni + tombstone registry

---

## Changelog v1.0 → ... → v1.7 (final)

| Изменение | Источник | Версия |
|-----------|----------|--------|
| Epistemic Contract — 3 правила | Ревью 2 | v1.1 |
| Фикс 1B → Фаза 2 с критерием запуска | Ревью 3 | v1.1 |
| Episode card = snippet + raw_excerpt + message_id | Ревью 2 | v1.1 |
| Evidence span ±1 | Ревью 2 | v1.1 |
| life_event: expires_at | Ревью 2 | v1.1 |
| Batch: «не обобщать предпочтения» | Ревью 2 | v1.1 |
| Multilingual note для instant patterns | Ревью 1 | v1.1 |
| Метрика retrieval_miss_rate | Ревью 3 | v1.1 |
| Snippet prompt: «НЕ интерпретируй» | Ревью 1 | v1.1 |
| fact/event → полный raw | Ревью 1 | v1.1 |
| Council context в batch prompt | Ревью 4 | v1.2 |
| Human-in-loop 1% sample | Ревью 4 | v1.2 |
| Staging queue fallback | Ревью 4 | v1.2 |
| raw_excerpt: head+tail (220+180) | Ревью 5 | v1.3 |
| Validator Gate | Ревью 5 | v1.3 |
| Auto-reject confidence < 0.8 | Ревью 4, 5 | v1.3 |
| Retrieval span ±1 для коротких | Ревью 5 | v1.3 |
| life_event без даты → TTL 30 дней | Ревью 5 | v1.3 |
| Snippet subordination в prompt | Ревью 5 | v1.3 |
| Короткие (<200) → полный raw | Ревью 4 | v1.3 |
| Формальное определение «независимые evidence» | Ревью 8 | v1.4 |
| fact/event → полный raw в excerpt (cap 1500) | Ревью 7 | v1.4 |
| Instant patterns → конфигурируемая таблица | Ревью 8 | v1.4 |
| evidence_message_ids NOT NULL + CHECK | Ревью 8 | v1.4 |
| Формулы метрик | Ревью 8 | v1.4 |
| Language-segmented review metrics | Ревью 7 | v1.4 |
| knowledge_key: supersede по (type, key) | Ревью 11 | v1.5 |
| Устойчивые предпочтения → hard_ban | Ревью 11 | v1.5 |
| Full raw cap: 1500 + head+tail (800+400) | Ревью 11 | v1.5 |
| Snippet fallback = '' | Ревью 11 | v1.5 |
| Evidence span lookup по message_id | Ревью 11 | v1.5 |
| Adaptive human-in-loop 1% → 0.1% | Ревью 10 | v1.5 |
| Full raw для ВСЕХ типов < 500 chars | Ревью 10 | v1.5 |
| UNIQUE INDEX (user, type, key) | Ревью 11 | v1.5 |
| **Фикс 11: Memory Correction Loop** | Риск 1.2, 6.2 | v1.6 |
| **Фикс 12: Privacy Guard на span** | Риск 2.2 | v1.6 |
| **Фикс 13: Naturalness Directive** | Риск 3.1 | v1.6 |
| **Фикс 14: Enrichment TTL Guarantee** | Риск 4.1 | v1.6 |
| **Фикс 15: Snippet Cascade при Forget** | Риск 2.2, 2.3 | v1.6 |
| **Карта рисков** — 20 угроз с покрытием | Риск-анализ | v1.6 |
| Фикс 11: DISPUTED state — не деактивировать при неоднозначном denial | Ревью 15 | v1.7 |
| Фикс 11: Auto-fallback — отключить batch при correction_rate > 3% | Ревью 14 | v1.7 |
| Фикс 11: Dual metric — corrections total vs UK deactivated | Ревью 15 | v1.7 |
| Фикс 13: «Переформулируй как вопрос, а не утверждение» | Ревью 15 | v1.7 |
| Фикс 15: ±1 сообщение вместо ±1 минута (надёжнее) | Ревью 15 | v1.7 |
| Фикс 15: Каскад чистит response_description у reply_to | Ревью 15 | v1.7 |
| Карта рисков: стабильные ID (R1.1a, R2.2, ...) | Ревью 15 | v1.7 |
| is_disputed колонка в user_knowledge | Ревью 15 | v1.7 |
| Privacy Guard: adaptive cosine threshold по языку (0.25 ar) | Ревью 13, 15 | v1.7 |
| Privacy Guard: skip соседей без embedding (race condition) | Ревью 15 | v1.7 |
| Enrichment TTL: retry_count < 3, защита от вечного ретрая | Ревью 15 | v1.7 |
| Фикс 4 → 4A (MVP) + 4B (Фаза 2): raw_excerpt в MVP, snippet gen в Phase 2 | Ревью 17 | v1.7 |
| Fix 12: skip span для коротких запросов (<30 chars) | Ревью 17 | v1.7 |
| Fix 11: corrected_message_id обязателен для "с чего ты взял" | Ревью 17 | v1.7 |
| **Arabic golden tests K18-K24** (code-switching, Arabizi, Gulf slang, ar correction) | Ревью 18 | v1.7 |
| **Slang strategy**: Gulf slang ≠ факт, correction patterns на ar/Arabizi | Ревью 18 | v1.7 |
| **GIN index** на evidence_message_ids (Fix 15 perf) | Ревью 17 | v1.7 |
| **Fix 15**: cascade response_description по reply_to ИЛИ next assistant | Ревью 17 | v1.7 |
| **Batch prompt**: «СЛЭНГ И ЭМОЦИИ ≠ ФАКТЫ» rule | Ревью 18 | v1.7 |
| knowledge_key NOT NULL + дефолты по типу | Ревью 19 | v1.7 |
| DISPUTED: помечает последнюю активную запись, не вставляет новую | Ревью 19 | v1.7 |
| body_params: анти-якорь shoes/обувь/حذاء → reject | Ревью 19 | v1.7 |
| Privacy Guard: NEEDS_SPAN эпизоды → assistant-before = core_context | Ревью 19 | v1.7 |
| Forget cascade: onboarding facts защищены от cascade deactivation | Ревью 19 | v1.7 |
| Batch extraction: advisory lock per user_id (concurrency) | Ревью 19 | v1.7 |

---

*Документ создан: 2026-02-19*
*Обновлён: 2026-02-19 — v1.7 (final)*
*Связанные документы: 04_Dubai_User_Data_Shard.md, 03_Dialogue_Pipeline.md, 05_Data_Flow.md, 06_Operations.md, UNDE_Brand_Platform.md*
