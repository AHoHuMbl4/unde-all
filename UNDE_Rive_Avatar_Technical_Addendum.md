# UNDE — Rive Avatar: технические доработки

*Дополнение к «Rive Avatar: полная карта состояний v1.0»*
*Версия 2.0 / 2026-02-21*

---

## Зачем этот документ

Карта состояний (v1.0) описывает **что** аватар делает. Этот документ описывает **как** это работает технически: связь с сервером (Mood Agent, Persona Agent, LLM Orchestrator), архитектура State Machine в Rive, формат данных, требования к «живости» анимаций.

Документ предназначен для Rive-дизайнера и Flutter-разработчика.

---

## 1. Contract v2: единые имена, типы, диапазоны

Все компоненты (Rive, Flutter, сервер, аналитика) используют **только эти имена**. Никаких синонимов.

### 1.1. Continuous inputs (интерполируются через Input Driver)

| Имя | Тип | Диапазон | Default | Описание |
|-----|-----|----------|---------|----------|
| `warmth` | float | 0.0–1.0 | 0.6 | Теплота мимики |
| `tension` | float | 0.0–1.0 | 0.2 | Напряжённость позы |
| `energy` | float | 0.0–1.0 | 0.5 | Амплитуда движений |
| `tempo` | float | 0.5–1.5 | 1.0 | Скорость анимаций |
| `audio_level` | float | 0.0–1.0 | 0.0 | Уровень аудио (с envelope) |
| `friendly_w` | float | 0.0–1.0 | 1.0 | Вес expression friendly |
| `caring_w` | float | 0.0–1.0 | 0.0 | Вес expression caring |
| `focused_w` | float | 0.0–1.0 | 0.0 | Вес expression focused |

> **MVP:** 3 expression weights. **v2:** добавить `cheerful_w`, `empathetic_w`, `thoughtful_w`, `excited_w`. Дизайнер: заложить placeholder inputs для v2 (default=0.0), чтобы не пересобирать .riv.
> **Сумма всех weights = 1.0 всегда.** Нормализация на стороне Flutter (см. раздел 5). В исходных таблицах маппинга суммы могут быть < 1.0 — это нормально, `normalizeWeights()` приведёт к 1.0.

### 1.2. Discrete inputs (применяются ступенькой, БЕЗ интерполяции)

| Имя | Тип | Values | Default | Описание |
|-----|-----|--------|---------|----------|
| `listen_state` | float | 0=idle, 1=listening, 2=thinking, 3=speaking | 0 | Текущее состояние |
| `pace` | float | 0=slow, 1=normal, 2=fast | 1 | Темп речи |
| `look_at` | float | 0=user, 1=content, 2=thinking_up | 0 | Направление взгляда |
| `viseme` | float | 0-6 (rest=0, A_I=1, E=2, O_U=3, M_B_P=4, L=5, F_V=6) | 0 | Форма рта |

> **КРИТИЧНО:** эти inputs передаются в Rive **мгновенно** (set), не через lerp. Интерполяция даст дробные значения (listen_state=2.6), что сломает transitions. Плавность для viseme и listen_state обеспечивается **внутри Rive** через blend duration на transitions (50ms для viseme, 300ms для listen_state).

> **Для дизайнера:** transitions в Rive строить **по диапазонам**, не через `==`. Это защищает от edge-кейсов кастинга (2.999 вместо 3):

**listen_state:**

| State | Условие в Rive |
|-------|---------------|
| idle | `< 0.5` |
| listening | `>= 0.5 && < 1.5` |
| thinking | `>= 1.5 && < 2.5` |
| speaking | `>= 2.5` |

**pace:**

| State | Условие в Rive |
|-------|---------------|
| slow | `< 0.5` |
| normal | `>= 0.5 && < 1.5` |
| fast | `>= 1.5` |

**look_at:**

| State | Условие в Rive |
|-------|---------------|
| user | `< 0.5` |
| content | `>= 0.5 && < 1.5` |
| thinking_up | `>= 1.5` |

**viseme:**

| State | Условие в Rive |
|-------|---------------|
| rest | `< 0.5` |
| A_I | `>= 0.5 && < 1.5` |
| E | `>= 1.5 && < 2.5` |
| O_U | `>= 2.5 && < 3.5` |
| M_B_P | `>= 3.5 && < 4.5` |
| L | `>= 4.5 && < 5.5` |
| F_V | `>= 5.5` |

### 1.3. Boolean inputs

| Имя | Default | Описание |
|-----|---------|----------|
| `is_speaking` | false | TTS играет |

### 1.4. Trigger inputs (Rive trigger name → серверный gesture_event)

Единый реестр. Колонка «Серверное имя» — значение `gesture_event` из `render_hints`. Колонка «Rive trigger» — имя input в State Machine.

| Rive trigger | Серверное имя в `gesture_event` | Описание |
|---|---|---|
| `gesture_session_start` | `session_start` | Начало сессии |
| `gesture_user_laughed` | `user_laughed` | Юзер засмеялся |
| `gesture_outfit_saved` | `outfit_saved` | Сохранение образа |
| `gesture_outfit_rejected` | `outfit_rejected` | Отклонение образа |
| `gesture_goal_achieved` | `goal_achieved` | Найден идеальный вариант |
| `gesture_self_correction` | `self_correction` | Аватар исправляет ошибку |
| `gesture_opinion_given` | `opinion_given` | Высказывает мнение |
| `gesture_empathy_moment` | `empathy_moment` | Момент поддержки |
| `gesture_topic_shift` | `topic_shift` | Смена темы |
| `nod` | *(клиентский)* | Кивок (idle, listening) |
| `reset` | *(клиентский)* | Полный сброс в idle (app resume) |
| `timeout_extended` | *(клиентский)* | LLM не ответил >5с |

Flutter-константы для маппинга:

```dart
const gestureEventToTrigger = <String, String>{
  'session_start':    'gesture_session_start',
  'user_laughed':     'gesture_user_laughed',
  'outfit_saved':     'gesture_outfit_saved',
  'outfit_rejected':  'gesture_outfit_rejected',
  'goal_achieved':    'gesture_goal_achieved',
  'self_correction':  'gesture_self_correction',
  'opinion_given':    'gesture_opinion_given',
  'empathy_moment':   'gesture_empathy_moment',
  'topic_shift':      'gesture_topic_shift',
};
```

### 1.5. Contract validation (Flutter)

Input Driver **валидирует** все данные перед записью в Rive:

```dart
void validate(Map<String, double> inputs) {
  for (final name in _continuousInputs) {
    inputs[name] = inputs[name]!.clamp(_ranges[name]!.min, _ranges[name]!.max);
  }
  final weights = normalizeWeights({
    'friendly_w': inputs['friendly_w']!,
    'caring_w':   inputs['caring_w']!,
    'focused_w':  inputs['focused_w']!,
  });
  inputs.addAll(weights);
  if (_hasViolations) {
    analytics.log('rive_contract_violation', details);
  }
}
```

Нарушение контракта:
- **Debug/dev сборка:** `assert` / `throw` на любое нарушение
- **Production:** fallback на default + лог в аналитику (Sentry)

Rive **никогда** не получает невалидные данные.

---

## 2. Серверные данные → Rive inputs

Сервер отдаёт **строки и объекты**. Rive принимает **числа и триггеры**. Маппинг — на стороне Flutter.

### 2.1. Что приходит от сервера

С каждым ответом LLM Orchestrator отдаёт два объекта:

```json
{
  "avatar_state": {
    "expression": "cheerful",
    "energy_level": 0.7
  },
  "render_hints": {
    "expression": "cheerful",
    "energy_level": 0.7,
    "listen_state": "speaking",
    "pace": "normal",
    "gesture_event": "goal_achieved",
    "look_at": "user"
  }
}
```

Параллельно (быстрее, ~100ms), от Mood Agent через `mood_frame`:

```json
{
  "emotion": { "valence": 0.6, "arousal": 0.4, "dominance": 0.5 },
  "mood_confidence": 0.8,
  "signals": {
    "frustration": 0.1,
    "urgency": 0.3,
    "confidence": 0.7,
    "fatigue": 0.2,
    "sarcasm_detected": false
  },
  "context_pattern": {
    "trajectory": "stable",
    "disengagement_score": 0.1
  },
  "topic": {
    "shift_detected": false,
    "thread_break": false
  },
  "rive_params": {
    "warmth": 0.7,
    "tension": 0.2,
    "tempo": 1.0,
    "gesture": null
  }
}
```

### 2.2. Маппинг string → number (Flutter enums)

```dart
abstract class RiveEnums {
  // listen_state
  static const double lsIdle      = 0;
  static const double lsListening = 1;
  static const double lsThinking  = 2;
  static const double lsSpeaking  = 3;

  static double listenStateFromString(String s) => switch (s) {
    'idle'      => lsIdle,
    'listening' => lsListening,
    'thinking'  => lsThinking,
    'speaking'  => lsSpeaking,
    _           => lsIdle,
  };

  // pace
  static const double paceSlow   = 0;
  static const double paceNormal = 1;
  static const double paceFast   = 2;

  static double paceFromString(String s) => switch (s) {
    'slow'   => paceSlow,
    'normal' => paceNormal,
    'fast'   => paceFast,
    _        => paceNormal,
  };

  // look_at
  static const double laUser       = 0;
  static const double laContent    = 1;
  static const double laThinkingUp = 2;

  static double lookAtFromString(String s) => switch (s) {
    'user'        => laUser,
    'content'     => laContent,
    'thinking_up' => laThinkingUp,
    _             => laUser,
  };
}
```

### 2.3. Маппинг server expression → weights

Сервер отправляет expression как строку. Flutter конвертирует в weights:

```dart
const expressionToWeights = <String, Map<String, double>>{
  'friendly':    {'friendly_w': 1.0, 'caring_w': 0.0, 'focused_w': 0.0},
  'cheerful':    {'friendly_w': 1.0, 'caring_w': 0.0, 'focused_w': 0.0},  // MVP: cheerful → friendly
  'caring':      {'friendly_w': 0.0, 'caring_w': 1.0, 'focused_w': 0.0},
  'empathetic':  {'friendly_w': 0.0, 'caring_w': 1.0, 'focused_w': 0.0},  // MVP: empathetic → caring
  'focused':     {'friendly_w': 0.0, 'caring_w': 0.0, 'focused_w': 1.0},
  'thoughtful':  {'friendly_w': 0.0, 'caring_w': 0.0, 'focused_w': 1.0},  // MVP: thoughtful → focused
  'excited':     {'friendly_w': 1.0, 'caring_w': 0.0, 'focused_w': 0.0},  // MVP: excited → friendly + high energy
};

// v2: когда добавятся cheerful_w, empathetic_w и т.д.,
// каждый expression получит свой вес напрямую.
```

### 2.4. Полный маппинг render_hints (Flutter)

```dart
void applyRenderHints(Map<String, dynamic> hints) {
  // Discrete: string → number (мгновенно)
  if (hints['listen_state'] != null) {
    _targetListenState = RiveEnums.listenStateFromString(hints['listen_state']);
  }
  if (hints['pace'] != null) {
    _targetPace = RiveEnums.paceFromString(hints['pace']);
  }
  if (hints['look_at'] != null) {
    _targetLookAt = RiveEnums.lookAtFromString(hints['look_at']);
  }

  // Expression: string → weights (через интерполяцию)
  if (hints['expression'] != null) {
    final weights = expressionToWeights[hints['expression']];
    if (weights != null) _applyExpressionOverride(weights);
  }

  // Energy: float (через интерполяцию)
  if (hints['energy_level'] != null) {
    _targetEnergy = (hints['energy_level'] as num).toDouble();
  }

  // Gesture: string → trigger (через queue)
  if (hints['gesture_event'] != null) {
    final triggerName = gestureEventToTrigger[hints['gesture_event']];
    if (triggerName != null) {
      _gestureQueue.enqueue(_triggers[triggerName]!);
    }
  }
}
```

---

## 3. Архитектура

Три источника → Input Driver (единая точка) → Rive.

```
┌──────────────────────────────────────────────────────────────────────┐
│                         APP (Flutter)                                │
│                                                                      │
│  ┌───────────────┐  ┌───────────────┐  ┌──────────────────────────┐ │
│  │ Voice Pipeline │  │ Server Data   │  │  LLM Orchestrator        │ │
│  │ (realtime)     │  │ (Mood Agent   │  │  (per response)          │ │
│  │               │  │  + rive_params)│  │  avatar_state +          │ │
│  │               │  │               │  │  render_hints             │ │
│  └───────┬───────┘  └───────┬───────┘  └────────────┬─────────────┘ │
│          │ ~16ms            │ ~100ms                 │ ~2-5s         │
│          │                  │                        │               │
│          ▼                  ▼                        ▼               │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                    INPUT DRIVER                               │   │
│  │                                                               │   │
│  │  • Единая точка записи в Rive (через кэшированные SMI)       │   │
│  │  • Server Mapper: string→number, expression→weights           │   │
│  │  • Continuous: интерполяция @60fps                            │   │
│  │  • Discrete: мгновенный set (без lerp)                       │   │
│  │  • Envelope filter для audio_level                            │   │
│  │  • Authority rules + LLM override TTL                        │   │
│  │  • Гистерезис + нормализация weights                         │   │
│  │  • Contract validation + logging                              │   │
│  │  • Gesture queue (max 1 pending)                              │   │
│  └──────────────────────────┬───────────────────────────────────┘   │
│                              │                                       │
│                              ▼                                       │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │                   RIVE STATE MACHINE                          │   │
│  │                                                               │   │
│  │  Layer 1: Body (breathing, idle)        ← energy, tempo      │   │
│  │  Layer 2: Face/Expressions              ← friendly_w,        │   │
│  │                                           caring_w, focused_w│   │
│  │  Layer 3: Eyes (blink, gaze)            ← look_at, state     │   │
│  │  Layer 4: Mouth (lip-sync)              ← viseme, audio_level│   │
│  │  Layer 5: Gestures (one-shot overlays)  ← triggers           │   │
│  └──────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
```

### Источник 1: Voice Pipeline (реалтайм, ~16ms)

```
ElevenLabs TTS (WebSocket)
    │
    ├── audio chunk → speaker
    └── audio analysis → viseme mapper
            │
            ├── viseme (0-6)      → Input Driver (discrete, instant set)
            ├── raw_audio_level   → envelope filter → Input Driver (continuous)
            └── is_speaking       → Input Driver (boolean, instant set)
```

Viseme set (MVP — 7 поз):

| Value | Viseme | Звуки (RU/EN) | Звуки (AR) | Форма рта |
|-------|--------|---------------|------------|-----------|
| 0 | rest | тишина | тишина | закрыт |
| 1 | A_I | а, и, a, i | ا، ي | широко открыт |
| 2 | E | э, е, e | — | средне, горизонтально |
| 3 | O_U | о, у, o, u | و | округлён |
| 4 | M_B_P | м, б, п, m, b, p | م، ب | сжаты |
| 5 | L | л, l | ل | приоткрыт, язык вверх |
| 6 | F_V | ф, в, f, v | ف | нижняя губа к зубам |

> **v2 (арабский):** AIN (7) для ع/ح/خ — глоточные; задействует Jaw + лёгкое сужение. SH_ZH (8) для ش/ж/sh. TH (9) для ث/ذ/th. W_OO (10) для واو. Приоритет арабских виземов — после launch в Дубае, по реальному фидбеку.

### Источник 2: Mood Agent (rive_params, ~100ms)

Mood Agent анализирует эмоции юзера и отдаёт `rive_params` — **готовые числовые значения** для аватара. Flutter берёт их напрямую, без пересчёта:

```dart
void applyMoodFrame(Map<String, dynamic> moodFrame) {
  final riveParams = moodFrame['rive_params'] as Map<String, dynamic>?;
  if (riveParams == null) return;

  _targetWarmth  = (riveParams['warmth']  as num?)?.toDouble() ?? 0.6;
  _targetTension = (riveParams['tension'] as num?)?.toDouble() ?? 0.2;
  _targetTempo   = (riveParams['tempo']   as num?)?.toDouble() ?? 1.0;

  // Gesture от Mood Agent (topic_shift и т.п.)
  final gesture = riveParams['gesture'] as String?;
  if (gesture != null) {
    final triggerName = gestureEventToTrigger[gesture];
    if (triggerName != null) _gestureQueue.enqueue(_triggers[triggerName]!);
  }

  // Дополнительно: urgency модификатор
  final urgency = (moodFrame['signals']?['urgency'] as num?)?.toDouble() ?? 0.0;
  _targetTempo  += urgency * 0.3;
  _targetEnergy += urgency * 0.2;

  // Topic shift → gesture
  if (moodFrame['topic']?['shift_detected'] == true) {
    _gestureQueue.enqueue(_triggers['gesture_topic_shift']!);
  }

  // Disengagement detection
  final disengagement = (moodFrame['context_pattern']?['disengagement_score'] as num?)?.toDouble() ?? 0.0;
  if (disengagement > 0.7) {
    _targetEnergy = (_targetEnergy * 0.7).clamp(0.2, 1.0);
  }

  // Trajectory-based expression override
  final trajectory = moodFrame['context_pattern']?['trajectory'] as String?;
  final valence = (moodFrame['emotion']?['valence'] as num?)?.toDouble() ?? 0.5;

  _updateExpressionFromMood(valence, trajectory);
}
```

**Кто за что отвечает:**

| Параметр | Источник | Логика |
|---|---|---|
| `warmth`, `tension`, `tempo` | **Mood Agent → `rive_params`** | Сервер вычисляет baseline, клиент применяет urgency-модификатор поверх |
| `energy_level` | **Persona Agent → `avatar_state`** | Через render_hints |
| Expression weights | **Persona Agent → `render_hints.expression`** (основной) + **Mood valence** (baseline) | LLM override > Mood baseline |
| `listen_state`, `pace`, `look_at` | **Клиент** (VAD, TTS state) + **LLM → `render_hints`** | Клиент управляет, LLM подсказывает |
| Gestures | **LLM → `render_hints.gesture_event`** + **Mood → `rive_params.gesture`** | Через gesture queue |

Fallback при Mood Agent timeout (>200ms): предыдущий mood_frame с decay:

```dart
void onMoodTimeout() {
  _targetWarmth  = _targetWarmth  * 0.95 + 0.6 * 0.05;  // decay к default
  _targetTension = _targetTension * 0.95 + 0.2 * 0.05;
  _targetTempo   = _targetTempo   * 0.95 + 1.0 * 0.05;
}
```

### Источник 3: LLM Orchestrator (~2-5s)

Отдаёт `avatar_state` + `render_hints` (раздел 2.1). Маппинг через `applyRenderHints()` (раздел 2.4).

Если LLM не ответил за 5с → trigger `timeout_extended`.

---

## 4. Authority rules

### Порядок приоритетов (от высшего к низшему)

1. **Voice Pipeline** (`is_speaking`, `viseme`, `audio_level`) — реалтайм, не ждёт
2. **Listen state locks** (thinking min 1.5s, user interrupt rules)
3. **LLM render_hints** — expression override, gesture, pace, look_at
4. **Mood Agent rive_params** — baseline для warmth, tension, tempo + mood expression
5. **Idle / auto-behaviors** — blink, gaze drift, breathing

### Таблица конфликтов

| Конфликт | Правило |
|----------|---------|
| `is_speaking=true`, но `listen_state` ≠ speaking | `is_speaking` **форсит** `listen_state=3` |
| VAD: юзер говорит, но thinking_lock активен (1.5с) | thinking_lock имеет приоритет. После lock → listening |
| **Юзер перебивает** (VAD=true во время speaking) | Немедленно: `is_speaking=false`, TTS stop, `listen_state=1` (listening). Fade: audio_level decay 100ms → 0. Без thinking — сразу слушаем. |
| Gesture перехватывает кости рта при `is_speaking=true` | Gesture **не анимирует** Jaw, Lip_Upper, Lip_Lower |
| Mood Agent и LLM дают разный expression | LLM override (приоритет 3) > Mood baseline (приоритет 4). LLM override действует с TTL. |
| App background → resume | trigger `reset` → idle + friendly weights |
| App inactive / low battery | `energy` decay to 0.2, minimal idle (breathing only) |
| TTS заканчивается, VAD=true | `listen_state=listening` (юзер уже говорит, без thinking) |
| TTS заканчивается, VAD=false | `listen_state=idle` |

### LLM Expression Override (с TTL)

Mood Agent задаёт **baseline** expression через valence/trajectory. LLM может **переопределить** на время (например, аватар должен выглядеть excited при показе образа, даже если юзер нейтрален).

Override приходит через `render_hints.expression` и применяется как TTL:

```dart
void _applyExpressionOverride(Map<String, double> weights, {int ttlMs = 6000}) {
  _overrideWeights = weights;
  _overrideExpiry = DateTime.now().add(Duration(milliseconds: ttlMs));
}

Map<String, double> _resolveExpressionWeights() {
  if (_overrideWeights != null && DateTime.now().isBefore(_overrideExpiry!)) {
    return _overrideWeights!;
  }
  _overrideWeights = null;
  return _moodBaselineWeights;  // возврат к Mood baseline
}
```

Правила:
- Override применяется **мгновенно** (через Input Driver, с интерполяцией)
- Через `ttl_ms` — плавный возврат к текущему mood baseline (500ms blend)
- Если за время TTL пришёл новый mood_frame — override сохраняется до истечения TTL

---

## 5. Input Driver (Flutter)

Единая точка управления Rive. Никто не пишет в Rive напрямую.

### Кэширование SMI (критично для производительности)

```dart
class RiveInputDriver {
  late final SMINumber _warmth;
  late final SMINumber _tension;
  late final SMINumber _energy;
  late final SMINumber _tempo;
  late final SMINumber _audioLevel;
  late final SMINumber _friendlyW;
  late final SMINumber _caringW;
  late final SMINumber _focusedW;
  late final SMINumber _listenState;  // discrete
  late final SMINumber _pace;          // discrete
  late final SMINumber _lookAt;        // discrete
  late final SMINumber _viseme;        // discrete
  late final SMIBool   _isSpeaking;
  late final Map<String, SMITrigger> _triggers;

  void init(StateMachineController controller) {
    _warmth = controller.findInput<double>('warmth') as SMINumber;
    _tension = controller.findInput<double>('tension') as SMINumber;
    _energy = controller.findInput<double>('energy') as SMINumber;
    _tempo = controller.findInput<double>('tempo') as SMINumber;
    _audioLevel = controller.findInput<double>('audio_level') as SMINumber;
    _friendlyW = controller.findInput<double>('friendly_w') as SMINumber;
    _caringW = controller.findInput<double>('caring_w') as SMINumber;
    _focusedW = controller.findInput<double>('focused_w') as SMINumber;
    _listenState = controller.findInput<double>('listen_state') as SMINumber;
    _pace = controller.findInput<double>('pace') as SMINumber;
    _lookAt = controller.findInput<double>('look_at') as SMINumber;
    _viseme = controller.findInput<double>('viseme') as SMINumber;
    _isSpeaking = controller.findInput<bool>('is_speaking') as SMIBool;

    _triggers = {
      for (final name in [
        'gesture_session_start', 'gesture_user_laughed', 'gesture_outfit_saved',
        'gesture_outfit_rejected', 'gesture_goal_achieved', 'gesture_self_correction',
        'gesture_opinion_given', 'gesture_empathy_moment', 'gesture_topic_shift',
        'nod', 'reset', 'timeout_extended',
      ])
        name: controller.findInput<bool>(name) as SMITrigger,
    };
  }
}
```

> `findInput` вызывается **только при init**. Запись в Rive **только если значение реально изменилось** (epsilon = 0.001 для continuous).

### Tick (каждый кадр, 60fps)

```dart
void tick(double dt) {
  // 1. Continuous: интерполяция к целевым
  _updateContinuous(_warmth, _targetWarmth, 1.5, dt);
  _updateContinuous(_tension, _targetTension, 1.5, dt);
  _updateContinuous(_energy, _targetEnergy, 2.5, dt);
  _updateContinuous(_tempo, _targetTempo, 2.5, dt);
  _updateContinuous(_audioLevel, _envelopedAudioLevel, 20.0, dt);

  // Expression weights: resolve override vs mood baseline, then lerp
  final resolved = _resolveExpressionWeights();
  final normalized = normalizeWeights(resolved);
  _updateContinuous(_friendlyW, normalized['friendly_w']!, 2.0, dt);
  _updateContinuous(_caringW, normalized['caring_w']!, 2.0, dt);
  _updateContinuous(_focusedW, normalized['focused_w']!, 2.0, dt);

  // 2. Discrete: мгновенный set, без lerp
  _setDiscrete(_listenState, _targetListenState);
  _setDiscrete(_pace, _targetPace);
  _setDiscrete(_lookAt, _targetLookAt);
  _setViseme(_viseme, _targetViseme);

  // 3. Boolean
  _setBool(_isSpeaking, _targetIsSpeaking);

  // 4. Gesture queue
  _gestureQueue.process();
}

void _updateContinuous(SMINumber input, double target, double speed, double dt) {
  final current = input.value;
  if ((target - current).abs() < 0.001) return;
  input.value = _moveToward(current, target, speed * dt);
}

void _setDiscrete(SMINumber input, double target) {
  if (input.value != target) input.value = target;
}

static const _visemeHoldMs = 70;
DateTime _lastVisemeChange = DateTime(0);

void _setViseme(SMINumber input, double target) {
  if (input.value == target) return;
  final now = DateTime.now();
  if (now.difference(_lastVisemeChange).inMilliseconds < _visemeHoldMs) return;
  input.value = target;
  _lastVisemeChange = now;
}
```

### Audio Level Envelope Filter

```dart
class AudioEnvelope {
  double _smoothed = 0.0;
  static const attackRate  = 0.6;
  static const releaseRate = 0.15;
  static const floor       = 0.02;

  double process(double raw, bool isSpeaking) {
    if (!isSpeaking) {
      _smoothed = 0.0;
      return 0.0;
    }
    if (raw > _smoothed) {
      _smoothed += (raw - _smoothed) * attackRate;
    } else {
      _smoothed += (raw - _smoothed) * releaseRate;
    }
    return max(_smoothed, floor);
  }
}
```

> **Критично:** `floor` применяется **только когда `is_speaking=true`**. Иначе рот будет шевелиться в тишине.

### Decay при переходе is_speaking → false

```dart
void onSpeakingEnd() {
  _targetIsSpeaking = false;
  _audioDecayActive = true;
  _audioDecayTarget = 0.0;
  _audioDecaySpeed = 10.0;  // 100ms decay

  if (_vadActive) {
    _targetListenState = RiveEnums.lsListening;
  } else {
    _targetListenState = RiveEnums.lsIdle;
  }
}
```

### Weight нормализация

```dart
Map<String, double> normalizeWeights(Map<String, double> raw) {
  final f  = raw['friendly_w'] ?? 0.0;
  final c  = raw['caring_w']   ?? 0.0;
  final fo = raw['focused_w']  ?? 0.0;
  final sum = f + c + fo;
  if (sum <= 1e-6) return {'friendly_w': 1.0, 'caring_w': 0.0, 'focused_w': 0.0};
  return {
    'friendly_w': f / sum,
    'caring_w':   c / sum,
    'focused_w':  fo / sum,
  };
}
```

### Гистерезис (на доминирующем expression)

```dart
void updateExpressionTargets(Map<String, double> newWeights) {
  final currentDominant = _getDominant(_currentTargets);
  final newDominant = _getDominant(newWeights);

  if (currentDominant == newDominant) {
    _applyNormalized(newWeights);
  } else {
    final dominantDelta = newWeights[newDominant]! - (_currentTargets[newDominant] ?? 0.0);
    if (dominantDelta > 0.15) {
      _applyNormalized(newWeights);
    }
  }
}
```

> Предотвращает "дёрганье" между expressions при пограничных значениях.

### Gesture Queue

```dart
class GestureQueue {
  SMITrigger? _pending;
  bool _isPlaying = false;
  static const cooldown = Duration(milliseconds: 800);
  static const maxDuration = Duration(milliseconds: 2000);
  DateTime _lastFired = DateTime(0);
  Timer? _fallbackTimer;

  void enqueue(SMITrigger gesture) {
    if (_isPlaying) {
      _pending = gesture;
      return;
    }
    _fire(gesture);
  }

  void _fire(SMITrigger gesture) {
    final now = DateTime.now();
    if (now.difference(_lastFired) < cooldown) {
      _pending = gesture;
      return;
    }
    gesture.fire();
    _isPlaying = true;
    _lastFired = now;
    _fallbackTimer = Timer(maxDuration, () => onGestureComplete(null));
  }

  void onGestureComplete(String? gestureId) {
    _fallbackTimer?.cancel();
    _isPlaying = false;
    if (_pending != null) {
      final next = _pending!;
      _pending = null;
      _fire(next);
    }
  }

  void cancelAll() {
    _fallbackTimer?.cancel();
    _isPlaying = false;
    _pending = null;
  }
}
```

### Mood → Expression baseline (valence-based)

Mood Agent не отдаёт expression напрямую — он отдаёт `emotion.valence` и `context_pattern.trajectory`. Flutter вычисляет **baseline** expression из этих данных:

```dart
void _updateExpressionFromMood(double valence, String? trajectory) {
  Map<String, double> weights;

  if (valence >= 0.7) {
    weights = {'friendly_w': 1.0, 'caring_w': 0.0, 'focused_w': 0.0};
  } else if (valence >= 0.4) {
    weights = {'friendly_w': 0.7, 'caring_w': 0.0, 'focused_w': 0.3};
  } else {
    weights = {'friendly_w': 0.0, 'caring_w': 1.0, 'focused_w': 0.0};
  }

  // Escalating frustration (valence падает) → усилить caring
  if (trajectory == 'escalating' && valence < 0.4) {
    weights = {'friendly_w': 0.0, 'caring_w': 1.0, 'focused_w': 0.0};
  }

  _moodBaselineWeights = weights;

  // Если нет LLM override — применяем
  if (_overrideWeights == null || DateTime.now().isAfter(_overrideExpiry!)) {
    updateExpressionTargets(weights);
  }
}
```

### Маппинг JSON-конфиг (для тюнинга без ребилда)

```json
{
  "valence_thresholds": { "high": 0.7, "mid": 0.4 },
  "expression_to_weights": {
    "friendly": { "friendly_w": 1.0, "caring_w": 0.0, "focused_w": 0.0 },
    "caring":   { "friendly_w": 0.0, "caring_w": 1.0, "focused_w": 0.0 },
    "focused":  { "friendly_w": 0.0, "caring_w": 0.0, "focused_w": 1.0 }
  },
  "hysteresis_threshold": 0.15,
  "urgency_tempo_factor": 0.3,
  "urgency_energy_factor": 0.2,
  "override_default_ttl_ms": 6000,
  "viseme_hold_ms": 70
}
```

---

## 6. Rive State Machine: архитектура

### Решение по рукам: MVP без рук

Жесты реализуются через голову + выражение. Руки — v2 (+10 костей, +30% сложности).

### Bone Tree (MVP, ~18 костей)

```
Root
└── Spine
    ├── Shoulder_L
    ├── Shoulder_R
    └── Neck
        └── Head
            ├── Jaw
            ├── Brow_L
            ├── Brow_R
            ├── Eye_L
            │   ├── Pupil_L
            │   └── Eyelid_L
            ├── Eye_R
            │   ├── Pupil_R
            │   └── Eyelid_R
            ├── Lip_Upper
            ├── Lip_Lower
            ├── Cheek_L
            └── Cheek_R
```

### Layer 1: Body (всегда активен)

Inputs: `energy`, `tempo`

- **breathing**: цикл ~4.5с при tempo=1.0. Spine ↑↓, плечи. Амплитуда: `energy × 3px`.
- **idle_sway**: drift тела, 6-10с (рандом), `energy × 2px`.
- **Output: `breath_phase`** (0.0–1.0) — доступна Layer 4 для синхронизации губ с дыханием.

### Layer 2: Face/Expressions (всегда активен)

Inputs: `friendly_w`, `caring_w`, `focused_w`, `warmth`, `tension`

Blend State с weights. Каждый expression — поза, Rive микширует по весам.

`warmth` > 0.7 → уголки рта чуть вверх, глаза мягче.
`tension` > 0.5 → сжатие челюсти, натяжение бровей.

### Layer 3: Eyes (всегда активен)

Inputs: `look_at`, `listen_state`

**Auto-blink:** 3-7с (рандом). Закрытие ~100ms, открытие ~200ms. 15% двойной. Если рандом в Rive неудобен — Flutter BlinkScheduler + trigger `blink`.

**Gaze drift:** idle → ±3% ширины глаза, 4-8с. listening → зафиксирован на центр. thinking → вверх-вправо ~15°.

### Layer 4: Mouth (активен при speaking)

Inputs: `is_speaking`, `viseme`, `audio_level`

- `is_speaking=false`: рот rest + микро от `breath_phase` (1-2% высоты рта, синхронно с Layer 1)
- `is_speaking=true`: viseme blend (50ms внутри Rive), audio_level масштабирует амплитуду

### Layer 5: Gestures (по событиям)

Triggers → one-shot (0.8-1.5с): blend in 200ms, анимация, blend out 300ms.

**Для дизайнера:** в конец каждой gesture-анимации ставить **Rive event `gesture_done`** с payload `gesture_id` (строка, совпадает с trigger name). Flutter использует event + id для определения завершения.

| Event name | Payload | Когда |
|-----------|---------|-------|
| `gesture_done` | `gesture_id` (e.g. `"gesture_empathy_moment"`) | Конец каждой gesture-анимации |

Без event — fallback на таймер 2с.

**Кости на gesture:**

| Gesture trigger | Кости | Длительность |
|---|---|---|
| `gesture_session_start` | Head, Neck, Brow_L/R, Cheek_L/R | 1.2s |
| `gesture_user_laughed` | Jaw, Eyelid_L/R, Cheek_L/R | 0.8s |
| `gesture_outfit_saved` | Head, Neck | 0.8s |
| `gesture_outfit_rejected` | Head, Shoulder_L/R | 0.8s |
| `gesture_goal_achieved` | Head, Brow_L/R, Cheek_L/R | 1.0s |
| `gesture_self_correction` | Head, Brow_L/R | 1.0s |
| `gesture_opinion_given` | Head, Neck | 1.0s |
| `gesture_empathy_moment` | Head, Neck, Eyelid_L/R | 1.2s |
| `gesture_topic_shift` | Head, Neck, Shoulder_L/R | 0.8s |
| `nod` | Head, Neck | 0.5s |
| `timeout_extended` | Head | 0.6s |
| `reset` | Все | 0.5s |

**Правило:** при `is_speaking=true` gesture **не трогает** Jaw, Lip_Upper, Lip_Lower.

---

## 7. Thinking state

- Зрачки вверх-вправо (~15°). Веки прищурены 15-20%.
- Голова: наклон 2-3°. Рот нейтральный. Дыхание: tempo × 0.7.
- **Lock:** минимум 1.5с. Даже если ответ быстрее.
- **>5с:** trigger `timeout_extended` (кивок «почти»).
- Вход: 300ms blend. Выход: 400ms blend.
- Без руки к лицу, без закатывания глаз, без пожимания плеч.

---

## 8. Idle

### Базовый (< 7с молчания)

Layer 1 (дыхание) + Layer 3 (blink + gaze) + Layer 4 (micro-lips от breath_phase) + микро-повороты головы.

**Рандомизация:** `actual = base × (0.7 + random() × 0.6)`

| Элемент | Base | Range |
|---------|------|-------|
| Моргание | 4.5s | 3.15–5.85s |
| Поворот головы | 6.5s | 4.55–8.45s |
| Смена позы плеч | 12s | 8.4–15.6s |
| Gaze drift | 6s | 4.2–7.8s |

Рандомизация: preferably внутри Rive. Fallback: Flutter BlinkScheduler/IdleScheduler.

### Idle invite (> 7с молчания)

Наклон головы 3-4° (500ms) → warmth +0.15 (400ms) → зрачки к центру → через 5с возврат.

Cooldown: 30с **от момента последнего invite**.

```dart
bool shouldInvite(Duration silence, DateTime? lastInvite) {
  if (silence < Duration(seconds: 7)) return false;
  if (lastInvite == null) return true;
  return DateTime.now().difference(lastInvite) > Duration(seconds: 30);
}
```

---

## 9. User Interrupt (юзер перебивает аватар)

Критично для voice-first. Будет происходить часто.

**Когда:** VAD=true (с debounce 50ms для фильтрации шума), а `listen_state=speaking`.

**Что происходит (атомарно, в одном тике Input Driver):**
1. `is_speaking = false`
2. TTS stop (убить поток ElevenLabs)
3. `audio_level` → decay 100ms → 0
4. `listen_state = listening` (мгновенно, без thinking)
5. Expression **не сбрасывается**
6. Gesture queue: `cancelAll()` — сброс playing + pending
7. Timeout: отменить `timeout_extended`, если был запланирован

> **Атомарность критична:** шаги 1-2-4-6-7 применяются **в одном тике**. Иначе 1-2 кадра рот будет "говорить" без звука.

**VAD debounce:** 50ms задержка перед срабатыванием interrupt. Защита от ложных срабатываний (фоновый шум, кашель).

```dart
class InterruptHandler {
  Timer? _debounce;

  void onVADDetected(bool speaking) {
    if (speaking && _driver.listenState == RiveEnums.lsSpeaking) {
      _debounce ??= Timer(Duration(milliseconds: 50), _executeInterrupt);
    } else {
      _debounce?.cancel();
      _debounce = null;
    }
  }

  void _executeInterrupt() {
    _debounce = null;
    _driver.setDiscrete('listen_state', RiveEnums.lsListening);
    _driver.setBool('is_speaking', false);
    _ttsController.stop();
    _driver.gestureQueue.cancelAll();
    _driver.cancelTimeout();
  }
}
```

**Чего НЕ делать:**
- Не показывать thinking (перебил → слушаем, не думаем)
- Не менять expression
- Не воспроизводить остаток TTS

**Тайминг:** 50ms debounce + < 50ms execution = **< 100ms** от голоса юзера до listening.

---

## 10. Data flow: полная цепочка

```
Юзер говорит: "Мне грустно, ничего не хочется выбирать"
│
│  ① VAD: юзер говорит
│     → Input Driver: listen_state=1 (discrete, instant)
│     → Rive: listening (blend 300ms внутри Rive)
│
│  ② STT → текст
│
│  ③ Параллельно:
│     ├── Mood Agent (~100ms):
│     │   mood_frame:
│     │     emotion.valence=0.25, context_pattern.trajectory=escalating
│     │     rive_params: { warmth: 0.9, tension: 0.1, tempo: 0.7, gesture: null }
│     │     signals.urgency: 0.1
│     │   └── Input Driver:
│     │       warmth→0.9, tension→0.1, tempo→0.7 (из rive_params)
│     │       valence 0.25 + escalating → caring baseline
│     │       → normalizeWeights: caring_w=1.0, friendly_w=0.0, focused_w=0.0
│     │       → morph к caring (continuous, 500ms)
│     │       ★ Выражение меняется ДО ответа LLM
│     │
│     └── LLM Orchestrator (~3s):
│         avatar_state: { expression: "caring", energy_level: 0.3 }
│         render_hints: { expression: "caring", listen_state: "speaking",
│                         pace: "slow", gesture_event: "empathy_moment",
│                         look_at: "user" }
│         └── Input Driver:
│             expression "caring" → weights (совпадает с mood baseline)
│             energy_level → 0.3
│             pace → 0 (slow), look_at → 0 (user)
│
│  ④ listen_state=2 (thinking, discrete, instant) — lock 1.5s
│     Expression caring сохраняется
│
│  ⑤ Lock прошёл + ответ есть:
│     → GestureQueue: enqueue gesture_empathy_moment
│     → listen_state=3 (speaking), pace=0 (slow)
│     → TTS → lip-sync (viseme discrete, audio_level continuous)
│
│  ⑥ Речь кончилась:
│     → onSpeakingEnd(): audio_level decay 100ms → 0
│     → is_speaking=false
│     → if VAD=true → listen_state=1 (listening)
│       else → listen_state=0 (idle)
│     → caring expression сохраняется
│
│  ⑦ [User interrupt] Юзер перебивает на шаге ⑤:
│     → debounce 50ms → atomic interrupt:
│       is_speaking=false, TTS stop, listen_state=1
│       gestureQueue.cancelAll(), cancelTimeout()
│     → audio_level decay 100ms → 0
│
│  ⑧ Тишина > 7с + cooldown → idle_invite
│  ⑨ LLM timeout > 5с → trigger timeout_extended
│  ⑩ Mood Agent timeout > 200ms → decay к defaults
│  ⑪ Network lost → idle, expression не меняется, дыхание + blink работают
```

---

## 11. Файловая архитектура .riv

### skeleton.riv + skin.riv **не работает**

Кости из одного .riv файла **не могут деформировать** арт из другого .riv. Это ограничение Rive runtime.

### Правильная архитектура: один .riv + Data Binding / asset swapping

```
avatar.riv (один файл)
├── Bones (skeleton) — фиксированные, не меняются
├── State Machine — фиксированная
├── Slot: hair        → image asset (подменяемый)
├── Slot: eyes_style  → image asset (подменяемый)
├── Slot: skin_color  → color property (подменяемый)
├── Slot: clothing    → image asset (подменяемый)
└── ... другие слоты кастомизации
```

**Требования к slot-ассетам (для дизайнера):**
- **Единый canvas/bounding box** для каждого slot: все варианты одного слота должны иметь одинаковый размер и pivot point.
- **Safe margins:** 5-10% отступ внутри bounding box.
- **Naming convention:** `slot_hair_01.png`, `slot_eyes_02.png` — для автоматизации загрузки.

---

## 12. Приоритет реализации

### Must have (MVP)

| # | Что | Примечание |
|---|-----|------------|
| 1 | 4 listen states | discrete input, transitions в Rive |
| 2 | 3 expressions (weights) | Blend State, нормализация на Flutter |
| 3 | Lip-sync | viseme discrete + audio_level с envelope |
| 4 | Idle: дыхание + моргание | Рандомизированные интервалы |
| 5 | Server Mapper | string→number, expression→weights, rive_params |
| 6 | Input Driver | SMI cache, continuous/discrete split, 60fps |
| 7 | Thinking lock 1.5s | Антимелькание |
| 8 | Authority rules | is_speaking форсит, gestures не трогают рот |
| 9 | User interrupt | < 100ms реакция |
| 10 | Contract validation | Clamp + normalize + log |

### Should have

| # | Что |
|---|-----|
| 11 | +4 expression weights (cheerful, empathetic, thoughtful, excited) |
| 12 | tension, tempo params |
| 13 | look_at (3 направления) |
| 14 | pace |
| 15 | 3 gestures: session_start, user_laughed, empathy_moment |
| 16 | Gesture queue (max 1 pending) |
| 17 | idle_invite (7с + 30с cooldown) |
| 18 | Гистерезис на доминанте |
| 19 | LLM expression override с TTL |
| 20 | timeout_extended (5с) |
| 21 | Audio decay при speaking end (100ms) |

### Nice to have

| # | Что |
|---|-----|
| 22 | Остальные gestures |
| 23 | Кости рук (+10 костей) |
| 24 | Расширенный viseme: арабские фарингальные (AIN), SH_ZH, TH, W_OO |
| 25 | Adaptive idle (energy-dependent позы) |
| 26 | Cultural gesture overrides |
| 27 | Debug overlay / tracing log |

---

## 13. Требования к .riv

| Параметр | MVP | Полный |
|----------|-----|--------|
| Размер | < 200KB | < 350KB |
| Формат | Vector-only | Vector-only |
| Кости | ~18 | ~28 (с руками) |
| Layers | 5 | 5 |
| Compression | Включить | Включить |
| Кастомизация | Data Binding slots | — |

Тестировать:
- iPhone 12 mini (мин iOS), Android mid (Snapdragon 695+, Android 8+)
- FPS: ≥ 30 low-end, ≥ 60 mid+
- Memory: < 10MB runtime
- 10-минутная сессия: avg FPS drop < 5%, memory < 15MB

---

## 14. Rive SDK: совместимость

### Целевые версии

| Компонент | Версия | Примечание |
|---|---|---|
| Rive Editor | 0.8+ (2025+) | State Machine v2, blend states |
| `rive-flutter` | ≥ 0.13.x | Data Binding, StateMachineController, Rive events |
| Rive runtime format | .riv v7+ | Совместимость с текущим runtime |

### Критичные API, на которых строится архитектура

| API | Используется для | Статус в rive-flutter 0.13 |
|---|---|---|
| `StateMachineController` | Все inputs | ✅ Стабильный |
| `SMINumber`, `SMIBool`, `SMITrigger` | Typed input access | ✅ Стабильный |
| `findInput<T>(name)` | SMI кэширование | ✅ Стабильный |
| Rive Events (listener) | `gesture_done` callback | ✅ Добавлен в 0.12+ |
| Data Binding (text/image) | Slot asset swapping | ⚠️ Проверить конкретный тип binding. Image property swap через `RiveFile.asset` — ОК. Runtime image injection — зависит от версии. |
| Blend States (weighted) | Expression weights | ✅ Стабильный |

> **Перед началом работы:** собрать минимальный тестовый .riv (2 blend state + 1 trigger + 1 Rive event) и проверить на целевой версии rive-flutter, что:
> 1. Blend States корректно микшируются по float weights
> 2. Rive Events доходят до Flutter listener с payload
> 3. Image asset swap работает через выбранный API

---

## 15. Тест-кейсы (критические правила)

### Unit tests (Flutter)

| ID | Тест | Ожидаемый результат | DoD |
|---|---|---|---|
| UT-01 | `normalizeWeights({'friendly_w': 0.3, 'caring_w': 0.0, 'focused_w': 0.0})` | `{1.0, 0.0, 0.0}` | Сумма = 1.0 |
| UT-02 | `normalizeWeights({'friendly_w': 0.0, 'caring_w': 0.0, 'focused_w': 0.0})` | `{1.0, 0.0, 0.0}` (fallback friendly) | Не NaN, не деление на 0 |
| UT-03 | `normalizeWeights({'friendly_w': 0.5, 'caring_w': 0.3, 'focused_w': 0.2})` | `{0.5, 0.3, 0.2}` | Сумма = 1.0 |
| UT-04 | `AudioEnvelope.process(0.8, false)` | `0.0` | Floor не применяется когда !speaking |
| UT-05 | `AudioEnvelope.process(0.8, true)` | `> 0.02` (floor) | Атака |
| UT-06 | Clamp `warmth = 1.5` | `1.0` | Contract validation |
| UT-07 | Clamp `tempo = -0.1` | `0.5` | Contract validation |
| UT-08 | Гистерезис: dominant=friendly, new caring_w=0.1 | Не переключает | Порог 0.15 |
| UT-09 | Гистерезис: dominant=friendly, new caring_w=0.9 | Переключает на caring | Порог 0.15 |
| UT-10 | `RiveEnums.listenStateFromString('unknown')` | `0.0` (idle) | Fallback на default |
| UT-11 | `expressionToWeights['excited']` на MVP | Маппится на friendly + energy | Не null, не crash |

### Integration tests

| ID | Тест | Метрика | DoD |
|---|---|---|---|
| IT-01 | User interrupt: VAD=true во время speaking | Время от VAD до listen_state=listening | **< 100ms** |
| IT-02 | Thinking lock: ответ пришёл за 200ms | thinking показан минимум 1.5с | lock не обходится |
| IT-03 | Gesture queue: 3 gesture за 500ms | Первый играет, второй pending, третий дропает второй | Нет наложения |
| IT-04 | Gesture queue: interrupt во время gesture | cancelAll(), gesture не доигрывает | Чистый сброс |
| IT-05 | Viseme anti-flicker: 20 viseme за 100ms | Не более 1-2 реально применённых | Hold 70ms работает |
| IT-06 | Mood timeout: Mood Agent не отвечает 300ms | warmth/tension/tempo плавно decay к default | Нет скачков |
| IT-07 | LLM expression override → TTL expire | Плавный возврат к mood baseline за 500ms | Нет щелчка |
| IT-08 | Post-speaking: TTS end + VAD=true | listen_state → listening (без thinking) | Без промежуточного idle |
| IT-09 | Post-speaking: TTS end + VAD=false | listen_state → idle | Без промежуточного listening |
| IT-10 | App background → resume | trigger reset, все params → defaults | Нет застрявших состояний |

---

## 16. Acceptance-метрики «живости»

Количественные критерии для QA и приёмки.

| Метрика | Порог | Как измерять |
|---|---|---|
| Задержка listen_state при VAD | < 50ms (клиент) + 300ms blend (Rive) | Timestamp VAD event → SMI write |
| Задержка user interrupt end-to-end | < 100ms от VAD до тишины | Профайлер + аудио запись |
| Viseme jitter | ≤ 2 смены за 100ms | Лог viseme writes за сессию |
| Thinking min duration | ≥ 1500ms, всегда | Лог listen_state transitions |
| Gesture drop rate | < 10% за сессию | Enqueued vs fired counters |
| Gesture overlap | 0% (никогда) | Лог concurrent _isPlaying |
| Weight sum deviation | < 0.001 от 1.0 после normalize | Assert в validate() |
| FPS на low-end (iPhone 12 mini) | ≥ 30 avg за 10 мин | Rive profiler |
| FPS на mid+ | ≥ 55 avg за 10 мин | Rive profiler |
| Memory (runtime, .riv loaded) | < 10MB | Xcode Instruments / Android Profiler |
| Idle blink interval | 3-7с, не периодичный | Визуальная проверка + лог |
| Expression transition | 200-500ms (не мгновенный, не медленнее) | Визуальная проверка |
| Lip-sync perceived quality | Рот шевелится в такт речи, нет «рыбы» | Субъективный тест, 3 человека, ≥ 4/5 оценка |
