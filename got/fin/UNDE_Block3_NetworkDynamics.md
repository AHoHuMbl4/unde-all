# UNDE Block 3 — Network Dynamics
## k-factor моделирование, маховики роста, 36-месячная траектория
### Ibn Battuta Mall (Local Seed #1) | v1.0

---

## 0. Назначение

Формализация сетевых эффектов UNDE: декомпозиция k_user и k_provider, помесячная динамика до Фазы 3, формализация трёх маховиков из Конституции §8. Все inputs наследуются из Block 1 Steps 1–2. Арифметика верифицирована.

**Зависимости:**
- Inputs: UNDE_Block1_Step1_Inputs_v1.0, UNDE_Block1_Step2_ConversionChain_v1.0
- Протокол: UNDE_Model_Constitution_v1.2

---

## A. FRAMEWORK: K-FACTOR ОПРЕДЕЛЕНИЯ

### A.1. Формулы из Конституции (§3.1)

```
k_user(t)     = New_Activated_from_User_Viral(t)     / Existing_Onsite_MAU(t)   [per month]
k_provider(t) = New_Activated_from_Provider_Channels(t) / Existing_Onsite_MAU(t) [per month]
k_combined(t) = k_user(t) + k_provider(t)
```

**Порог Local Seed:** k_combined > 1.0 [H]

**Activated** = совершил Onsite Active Visit (не просто установил app). Антифрод: фейковые установки без визита не считаются.

### A.2. Структурное ограничение k_combined

В steady-state модели k_combined имеет математический потолок.

```
MAU = N_total / (1 − r)           где r = monthly return rate
k_combined = N_earned / MAU
           = N_earned / (N_total / (1 − r))
           = (N_earned / N_total) × (1 − r)
```

При r > 0 → k_combined < 1.0 **всегда**. При r = 0.15: max k_combined = 0.85. При r = 0.40: max k_combined = 0.60.

**Вывод:** k_combined > 1.0 по Конституции невозможен в steady-state при r > 0. Это математическое свойство, не ограничение бизнеса.

### A.3. Три метрики сетевого здоровья

| Метрика | Формула | Что измеряет | Порог |
|---------|---------|--------------|-------|
| **k_combined** | N_earned / MAU | Конституция §3.1: акселерация per user | Теор. max = (1−r) |
| **OIR** | N_earned / N_organic | Органическая независимость: заработанные каналы vs холодный старт | > 1.0 [H] |
| **Growth Rate (g)** | (MAU(t) − MAU(t−1)) / MAU(t−1) | Фактический рост сети | > 0 sustained |

**Рекомендация для Конституции v1.3:** Заменить порог k_combined > 1.0 на **OIR > 1.0**.

**Почему не r(t) + k_combined(t) > 1.0:**
В steady-state `MAU = N_total / (1−r)` и `k_combined = N_earned/MAU = (N_earned/N_total) × (1−r)`. Отсюда:

```
r + k_combined = r + (N_earned/N_total) × (1−r)
```

При N_earned = N_total (все каналы earned, 0 organic): `r + k = r + (1−r) = 1.0`. Это математический предел, не превышаемый в steady-state. `r + k > 1.0` невозможно → непригоден как порог.

**OIR > 1.0** измеряет то же самое содержательно (earned > organic), но без математического потолка. Достижимо к ~M24 (base case).

### A.4. Декомпозиция New Activated

```
N_total(t) = N_organic(t) + N_provider(t) + N_viral(t)
N_earned(t) = N_provider(t) + N_viral(t)
```

| Источник | Определение | Драйвер роста |
|----------|------------|---------------|
| **N_organic** | N_total − N_provider − N_viral | Residual: неатрибутированные установки из mall footfall |
| **N_provider** | PP × act/PP + NP × act/NP | Число Providers × эффективность промо |
| **N_viral** | MAU × viral_yield (сумма 3 петель) | MAU base × качество продукта × инструменты шеринга |

**N_organic derivation (M12 baseline):**

```
N_provider (Block 3, §C) = 1,200 / мес   [D] (300 from PP + 900 from NP)
N_viral (Block 3, §B)    =    91 / мес   [D] (sharing + referral + WOM)
N_organic                 = 2,940 / мес   [H] (residual: mall footfall discovery)
─────────────────────────────────────────
N_total                   = 4,231 / мес   [D] (сумма трёх каналов)
MAU = N_total / (1 − r)  = 4,231 / 0.85  = 4,978 [D]
```

*N_organic = 2,940 — базовая гипотеза [H], калиброванная по Step 1 (Fashion Footfall 525K × discovery × activation). В Block 3 держится константой. N_total и MAU — производные (derived), не вводные.*

### A.5. Retention drivers

> **Терминология:** `r(t)` = Monthly Return Rate proxy [H] — приближение steady-state, не строгая когортная D30. `D30 retention` — продуктовая метрика (% пользователей с Onsite Active Visit на день 30). Связь: при стабильном притоке `r ≈ D30`, но в фазе роста `r` может отставать от D30 из-за разбавления новыми когортами. В порогах Конституции используется D30, в формулах модели — r(t).

Рост r(t) от 15% (M1) до 45% (M36) — ключевой рычаг MAU. Драйверы retention заложены в допущение роста r, но не моделируются как отдельные acquisition каналы:

| Драйвер | Тип влияния | Вклад в рост r [H] |
|---------|-------------|-------------------|
| Рост качества рекомендаций (больше данных → точнее) | Utility retention | ~35% |
| Аватар + прокачка (sunk cost, эмоциональная привязка) | Investment retention | ~25% |
| Тайная комната, ритуалы, The Blink | Emotional retention | ~25% |
| Social proof (подруги тоже используют) | Network retention | ~15% |

---

## B. k_user DECOMPOSITION: 3 ВИРАЛЬНЫЕ ПЕТЛИ

### B.1. Loop 1: Social Outfit Sharing

Пользователь делится собранным образом в Instagram / Pinterest / WhatsApp.

```
N_share = MAU × share_rate × reach × install_conv × activate_conv
```

| Параметр | Определение | Тип | Эволюция (M6 → M36) |
|----------|------------|-----|---------------------|
| share_rate | % MAU, шерящих ≥1 образ/мес | [H] | 8% → 25% |
| reach | Уникальная релевантная аудитория на 1 шер | [H] | 5 → 8 |
| install_conv | Конверсия из просмотра в установку | [H] | 2% → 5% |
| activate_conv | Конверсия установки в Onsite Active Visit | [H] | 35% → 45% |

**Reach calculation [H]:**
Avg story/post views: 200. Dubai relevance filter: ~15%. Fashion interest: ~50%. Effective reach per share: 200 × 15% × 50% = 15, дедупликация → ~5–8 уникальных.

| Milestone | MAU | share_rate | reach | inst_conv | act_conv | **N_share** |
|-----------|-----|-----------|-------|----------|---------|------------|
| M6 | 4,055 | 8% | 5 | 2.0% | 35% | **11** |
| M12 | 4,978 | 12% | 6 | 2.5% | 38% | **34** |
| M18 | 6,438 | 16% | 6 | 3.0% | 40% | **74** |
| M24 | 8,633 | 20% | 7 | 3.5% | 42% | **178** |
| M36 | 15,918 | 25% | 8 | 5.0% | 45% | **717** |

### B.2. Loop 2: Direct Referral

Пользователь лично приглашает подругу / коллегу.

```
N_referral = MAU × referral_rate × invites × accept_conv × activate_conv
```

| Параметр | Определение | Тип | Эволюция (M6 → M36) |
|----------|------------|-----|---------------------|
| referral_rate | % MAU, приглашающих кого-то | [H] | 3% → 12% |
| invites | Среднее число приглашений | [H] | 1.2 → 1.8 |
| accept_conv | Конверсия приглашения в установку | [H] | 20% → 30% |
| activate_conv | Активация (выше для рефералов — личная рекомендация) | [H] | 45% → 55% |

| Milestone | MAU | ref_rate | invites | accept | activate | **N_referral** |
|-----------|-----|---------|---------|--------|---------|---------------|
| M6 | 4,055 | 3% | 1.2 | 20% | 45% | **13** |
| M12 | 4,978 | 5% | 1.3 | 22% | 48% | **34** |
| M18 | 6,438 | 7% | 1.4 | 25% | 50% | **79** |
| M24 | 8,633 | 9% | 1.5 | 27% | 52% | **163** |
| M36 | 15,918 | 12% | 1.8 | 30% | 55% | **569** |

### B.3. Loop 3: Ambient Word-of-Mouth (WOM)

Накопительный эффект узнаваемости: «я слышал про UNDE» → при следующем визите в молл ищет приложение. Не attributable к конкретному действию.

```
N_wom = Fashion_footfall × WOM_awareness_lift × install_conv × activate_conv
```

| Milestone | Fashion FF | WOM lift [H] | Install conv [H] | Activate [H] | **N_wom** |
|-----------|-----------|----------|-------------|---------|----------|
| M6 | 525,000 | 0.02% | 15% | 40% | **6** |
| M12 | 525,000 | 0.06% | 18% | 40% | **23** |
| M18 | 525,000 | 0.12% | 20% | 42% | **53** |
| M24 | 525,000 | 0.20% | 22% | 44% | **102** |
| M36 | 525,000 | 0.35% | 25% | 45% | **413** |

### B.4. k_user Summary

| Milestone | N_share | N_referral | N_wom | **N_viral** | MAU | **k_user** |
|-----------|---------|-----------|-------|-----------|-----|-----------|
| M3 | 3 | 4 | 2 | **9** | 3,530 | **0.003** |
| M6 | 11 | 13 | 6 | **30** | 4,055 | **0.007** |
| M9 | 21 | 22 | 13 | **56** | 4,540 | **0.012** |
| M12 | 34 | 34 | 23 | **91** | 4,978 | **0.018** |
| M18 | 74 | 79 | 53 | **206** | 6,438 | **0.032** |
| M24 | 178 | 163 | 102 | **443** | 8,633 | **0.051** |
| M30 | 400 | 350 | 230 | **980** | 11,589 | **0.085** |
| M36 | 717 | 569 | 413 | **1,699** | 15,918 | **0.107** |

**Доминирующая петля:** Social Sharing (42% к M36). Direct Referral — 34%. WOM — 24%.

---

## C. k_provider DECOMPOSITION

### C.1. Provider-driven acquisition: два канала

**Канал 1: Paying Providers (PP)**

Активно тратят Credits → мотивированы приводить пользователей для заработка Credits.

| Параметр | M3 | M6 | M12 | M18 | M24 | M36 | Тип |
|----------|----|----|-----|-----|-----|-----|-----|
| Paying Providers | 3 | 8 | 15 | 25 | 35 | 55 | [H] |
| Activated per PP / мес | 12 | 16 | 20 | 28 | 32 | 42 | [H] |
| **N from PP** | **36** | **128** | **300** | **700** | **1,120** | **2,310** | [D] |

**Рост Activated/PP:** Providers учатся лучшим практикам (QR-размещения, обучение продавцов). Credits incentive усиливается с ростом K.

**Канал 2: Connected Non-Paying Providers (NP)**

Загрузили каталог, не покупают Credits. Приводят через пассивные каналы (стикеры, соцсети).

| Параметр | M3 | M6 | M12 | M18 | M24 | M36 | Тип |
|----------|----|----|-----|-----|-----|-----|-----|
| Non-Paying Connected | 32 | 47 | 60 | 65 | 70 | 60 | [H] |
| Activated per NP / мес | 6 | 10 | 15 | 18 | 22 | 30 | [H] |
| **N from NP** | **192** | **470** | **900** | **1,170** | **1,540** | **1,800** | [D] |

NP count снижается к M36: часть переходит в PP. Total Connected растёт.

### C.2. k_provider Summary

| Milestone | N_PP | N_NP | **N_provider** | MAU | **k_provider** |
|-----------|------|------|---------------|-----|---------------|
| M3 | 36 | 192 | **228** | 3,530 | **0.065** |
| M6 | 128 | 470 | **598** | 4,055 | **0.148** |
| M9 | 216 | 696 | **912** | 4,540 | **0.201** |
| M12 | 300 | 900 | **1,200** | 4,978 | **0.241** |
| M18 | 700 | 1,170 | **1,870** | 6,438 | **0.290** |
| M24 | 1,120 | 1,540 | **2,660** | 8,633 | **0.308** |
| M30 | 1,575 | 1,690 | **3,265** | 11,589 | **0.282** |
| M36 | 2,310 | 1,800 | **4,110** | 15,918 | **0.258** |

### C.3. Provider share от total activated

| Milestone | N_provider | N_total | **Provider share** | Таргет Конституции |
|-----------|-----------|---------|-------------------|-------------------|
| M12 | 1,200 | 4,231 | **28%** | 30–40% [H] |
| M18 | 1,870 | 5,016 | **37%** | ✓ в диапазоне |
| M24 | 2,660 | 6,043 | **44%** | ✓ выше таргета |
| M36 | 4,110 | 8,749 | **47%** | ✓ стабильно |

Provider-driven acquisition выходит на таргет 30–40% к M18 и стабилизируется ~44–47%.

### C.4. Почему k_provider (per MAU) снижается при росте

N_provider растёт, но k_provider = N_provider/MAU снижается после M24. Причина: MAU растёт быстрее (через retention improvement), чем provider acquisition. Это **здоровый** сигнал — рост всё больше self-sustaining через retention, а не provider-dependent.

---

## D. 36-MONTH TRAJECTORY

### D.1. Сводная таблица

| Milestone | CP | PP | r | N_org | N_prov | N_viral | N_total | MAU | k_user | k_prov | k_comb | **OIR** |
|-----------|----|----|---|-------|--------|---------|---------|-----|--------|--------|--------|---------|
| **M3** | 35 | 3 | 10% | 2,940 | 228 | 9 | 3,177 | 3,530 | 0.003 | 0.065 | 0.068 | **0.08** |
| **M6** | 55 | 8 | 12% | 2,940 | 598 | 30 | 3,568 | 4,055 | 0.007 | 0.148 | 0.155 | **0.21** |
| **M9** | 70 | 12 | 14% | 2,940 | 912 | 56 | 3,908 | 4,540 | 0.012 | 0.201 | 0.213 | **0.33** |
| **M12** | 75 | 15 | 15% | 2,940 | 1,200 | 91 | 4,231 | 4,978 | 0.018 | 0.241 | 0.259 | **0.44** |
| **M18** | 90 | 25 | 22% | 2,940 | 1,870 | 206 | 5,016 | 6,438 | 0.032 | 0.290 | 0.323 | **0.71** |
| **M24** | 105 | 35 | 30% | 2,940 | 2,660 | 443 | 6,043 | 8,633 | 0.051 | 0.308 | 0.359 | **1.06** |
| **M30** | 110 | 45 | 38% | 2,940 | 3,265 | 980 | 7,185 | 11,589 | 0.085 | 0.282 | 0.366 | **1.44** |
| **M36** | 115 | 55 | 45% | 2,940 | 4,110 | 1,699 | 8,749 | 15,907 | 0.107 | 0.258 | 0.365 | **1.98** |

**CP** = Connected Providers (total). **PP** = Paying Providers.

### D.2. Ключевые переломные точки

| Событие | Когда | Метрика | Значение |
|---------|-------|---------|----------|
| MAU > 500 (Seed threshold) | **M1** | Onsite MAU | 500+ |
| Active Providers > 10 | **M7** | PP | 10+ |
| Покрытие > 50% fashion | **~M8** | CP / 120 | 50%+ |
| Provider share > 30% | **~M16** | N_provider / N_total | 30%+ |
| **OIR > 1.0** | **~M24** | N_earned / N_organic | **Earned > Organic** |
| D30 retention > 40% | **~M33** | r proxy | 40%+ |

**OIR > 1.0 crossing (~M24):** Момент, когда UNDE больше не зависит от холодного трафика молла. Earned каналы (Providers + Viral) приводят больше пользователей, чем случайное обнаружение.

### D.3. OIR Trajectory

```
OIR (Organic Independence Ratio)

  2.0 |                                                    *  M36
      |                                              
  1.5 |                                        *  M30
      |                                  
  1.0 |------------------------*------ OIR = 1.0 THRESHOLD ----
      |                  *        M24
  0.5 |            *
      |      *
  0.0 |*  *
      +--+--+--+--+--+--+--+--+--+--+--+--→ months
         3  6  9  12 15 18 21 24 27 30 33 36
```

---

## E. LOCAL SEED THRESHOLD ANALYSIS

### E.1. Пороги Конституции — статус по milestone

| Порог | Threshold | M6 | M12 | M18 | M24 | M30 | M36 |
|-------|-----------|-----|------|------|------|------|------|
| Onsite MAU > 500 | 500 [H] | ✓ 4,055 | ✓ 4,978 | ✓ 6,438 | ✓ 8,633 | ✓ 11,589 | ✓ 15,907 |
| Active Providers > 10 | 10 [H] | ✗ 8 PP | ✓ 15 PP | ✓ 25 PP | ✓ 35 PP | ✓ 45 PP | ✓ 55 PP |
| OIR > 1.0 | 1.0 [H*] | ✗ 0.21 | ✗ 0.44 | ✗ 0.71 | ✓ 1.06 | ✓ 1.44 | ✓ 1.98 |
| D30 retention > 40% | 40% [H] | ✗ 12% | ✗ 15% | ✗ 22% | ✗ 30% | ✗ 38% | ✓ 45% |
| Покрытие > 50% | 50% [H] | ✗ 46% | ✓ 63% | ✓ 75% | ✓ 88% | ✓ 92% | ✓ 96% |

*[H*] — предложенная замена k_combined > 1.0 на OIR > 1.0 (§A.3). r + k_combined > 1.0 математически недостижим в steady-state.*

### E.2. Binding constraint: D30 Retention

> **D30 retention — последний порог, который выполняется.** Он определяет момент достижения Local Seed.

Все остальные пороги достигаются к M7–M24. D30 > 40% — к ~M33–36.

**Local Seed по всем критериям: ~M33–36** (base case).

Retention drivers (заложены в рост r, §A.5):
- Рост качества рекомендаций с объёмом данных
- Аватар investment (sunk cost, эмоциональная привязка)
- Тайная комната, The Blink (emotional rituals)
- Network effect (подруги тоже пользуются)

**Сценарий-акселератор:** Если r = 40% к M24 (сильный PMF) → Local Seed к **~M24–27**.

### E.3. Два режима роста

```
M1–M24: Acquisition-driven growth
  └── MAU растёт через N_total growth (больше providers, первая виральность)
  └── Retention ещё низкая → MAU = N/(1-r) с малым множителем

M24+: Retention-driven growth
  └── N_total стабилизируется (organic footfall ≈ const)
  └── Retention растёт → множитель 1/(1-r) увеличивается
  └── MAU ускоряется даже при стабильном N_total
```

---

## F. ТРИ МАХОВИКА (Конституция §8) — ФОРМАЛИЗАЦИЯ

### F.1. Маховик доверия (Trust Flywheel)

```
Better recs → More trust → More queries → More signals → Even better recs
```

| Этап | Метрика | M12 baseline | M36 target | Cycle time |
|------|---------|-------------|-----------|-----------|
| Recs quality | % рекомендаций с click-through | 25% [H] | 50% [H] | — |
| Trust score | Sessions per returning user / мес | 3.0 | 5.0 [H] | — |
| Query volume | Total Recs / month | 13,957 | ~50,000 [D] | — |
| Signal density | Data points per user | ~15 [H] | ~200 [H] | — |
| **Full cycle** | Recs → Trust → Queries → Signals → Recs | — | — | **~3 мес** [H] |

**Bottleneck:** Signal density. На старте мало данных → рекомендации generic → медленное формирование доверия. Inflection point: ~50 data points per user.

### F.2. Маховик покрытия (Coverage Flywheel)

```
More Providers → Fuller Feed → Better recs → Higher conversion → Competitors must join
```

| Этап | Метрика | M12 baseline | M36 target | Cycle time |
|------|---------|-------------|-----------|-----------|
| Provider count | Connected Providers | 75 | 115 | — |
| Feed completeness | % SKU покрыто в молле | 40% [H] | 85% [H] | — |
| Rec accuracy | % рекомендаций с товаром в наличии | 80% [H] | 97% [H] | — |
| Conversion | Visit → Verified Action | 5% [H] | 15% [H] | — |
| Competitive pressure | % fashion stores connected | 63% | 96% | — |
| **Full cycle** | Provider → Feed → Recs → Conv → More Providers | — | — | **~6 мес** [H] |

**Bottleneck:** Onboarding speed. Каждый Provider = каталог + интеграция.

### F.3. Маховик Earn-to-Spend (Growth + Revenue Flywheel)

```
Provider brings users → Earns Credits → Spends on priority → Sees ROI → Brings more users
```

| Этап | Метрика | M12 baseline | M36 target | Cycle time |
|------|---------|-------------|-----------|-----------|
| Users brought | Activated per PP / мес | 20 | 42 | — |
| Credits earned | Earned / PP / мес | 4,200 | 10,000 [H] | — |
| Credits purchased | Purchased / PP / мес | 2,100 | 7,000 [H] | — |
| ROI observed | Verified Actions attributable to UNDE | 4 [H] | 20 [H] | — |
| Reinvestment | Increase in promotion effort | +10% [H] | +20% [H] | — |
| **Full cycle** | Bring → Earn → Spend → ROI → Bring more | — | — | **~2 мес** [H] |

**Bottleneck (Фаза 1):** No ROI (Credits нельзя тратить). Provider motivation = только data access и будущее позиционирование.
**Bottleneck (Фаза 2+):** K-cap. Providers хотят тратить больше, чем K позволяет → стимулирует приводить больше пользователей.

### F.4. Взаимодействие маховиков

```
                    ┌─── Trust ───┐
                    │  (retention) │
                    │  3-мес цикл  │
                    └──────┬───────┘
                           │ retention ↑ → MAU ↑ → viral ↑
                           ▼
┌─── Coverage ───┐  ← feeds →  ┌─── Earn-to-Spend ───┐
│  (data quality) │              │    (k_provider)      │
│  6-мес цикл     │              │    2-мес цикл        │
└────────┬────────┘              └─────────┬────────────┘
         │ more providers                  │ more users
         └──────────── reinforces ─────────┘
```

**Самый быстрый маховик:** Earn-to-Spend (2 мес). Запускается первым, создаёт базу.
**Самый мощный маховик:** Trust (3 мес). Определяет retention долгосрочно.
**Самый широкий маховик:** Coverage (6 мес). Определяет потолок качества рекомендаций.

---

## G. REVENUE CONNECTION (Link to Step 2)

### G.0. Phase Alignment

> **Критическое правило:** По Конституции §4.2 (Фаза 1: Earn-only) покупка Credits запрещена до достижения Local Seed. Revenue = $0 до триггера Фазы 2.

| Фаза | Период (base case) | Revenue | Основание |
|------|-------------------|---------|-----------|
| **Phase 1 (Earn-only)** | M1 – ~M33 | **$0** | Конституция §4.2: «нет платной монетизации» |
| **Phase 1 WTP pilots** | M12+ (при 10+ PP, 500+ MAU) | Ограниченная | Конституция §4.2: «допускаются пилотные willingness-to-pay эксперименты» |
| **Phase 2 (Earn-to-Buy)** | ~M33+ | Full Credits Economy | Триггер: Local Seed достигнут (все пороги §3.1) |

Ниже представлены **два сценария:**
- **Scenario S (Strict):** Revenue = $0 до Local Seed (~M33). Показывает реальный размер pre-revenue инвестиции.
- **Scenario P (Pilot):** WTP-пилоты с M12 генерируют ограниченную выручку (30% от полной Phase 2 ставки [H]). Показывает economics при раннем тестировании монетизации.

### G.1. Revenue Capacity at Milestones (Phase 2 rates)

Таблица показывает **потенциальную** revenue capacity при полной Credits Economy. Применяется только с момента Phase 2 trigger.

```
Revenue_Seed = PP × MIN(Earned × K, Desired_Spend) × Price_per_Credit
Opex_Seed = AI_cost(MAU) + Ops + Onboarding + Server
```

**AI cost/MAU decline [H]:** $0.70 (M6) → $0.65 (M18) → $0.55 (M24) → $0.50 (M30) → $0.45 (M36). Оптимизация: кэширование, батчинг, дешёвые модели для простых запросов.

**Trigger rules (не произвольные изменения):**
- **Price per Credit:** $0.10 [H] — базовая ставка Phase 2. Повышение до $0.12 только после WTP-test success (статистически значимое подтверждение willingness-to-pay на пилоте ≥3 месяца). Price sensitivity — см. Step 2 §D.2.
- **K coefficient:** Увеличивается по tier thresholds Конституции §2.3 (Rolling 90d Earned: 1K→K=0.3, 5K→K=0.5, 20K→K=0.7, 50K+→K=1.0). Не по решению UNDE, а автоматически по накоплению Credits.

| Milestone | PP | Earned/PP [H] | K [H] | Max Purch | Price [H] | **Rev capacity** | AI cost | Other Opex [D] | **Total Opex** |
|-----------|----|----|---|------|-----|---------|------|------|------|
| M6 | 8 | 3,000 | 0.3 | 900 | $0.10 | $720 | $2,839 | $2,567 | $5,406 |
| M12 | 15 | 4,200 | 0.5 | 2,100 | $0.10 | $3,150 | $3,485 | $2,800 | $6,285 |
| M18 | 25 | 5,500 | 0.5 | 2,750 | $0.10 | $6,875 | $4,185 | $3,183 | $7,368 |
| M24 | 35 | 7,000 | 0.7 | 4,900 | $0.12 | $20,580 | $4,748 | $4,067 | $8,815 |
| M30 | 45 | 8,500 | 0.7 | 5,950 | $0.12 | $32,130 | $5,795 | $4,450 | $10,245 |
| M36 | 55 | 10,000 | 1.0 | 10,000 | $0.12 | $66,000 | $7,163 | $5,333 | $12,496 |

**Earned/PP derivation [H]:** Earned/PP — функция acquisition и retention:

```
Earned/PP(t) = Activated_per_PP(t) × Cr_per_activated
             + Retained_D7(t) × Cr_D7
             + Retained_D30(t) × Cr_D30
             + Shares(t) × Cr_share
             + Verified_Actions(t) × Cr_VA
```

Рост Earned/PP с 3,000 (M6) до 10,000 (M36) — следствие: (a) рост Activated/PP (12→42), (b) рост retention привлечённых (больше D7/D30 returns), (c) рост Verified Actions с улучшением рекомендаций. Полная декомпозиция — Step 1 §D.1.

**Other Opex breakdown [D]:**

| Компонент | Формула | M6 | M12 | M18 | M24 | M30 | M36 |
|-----------|---------|-----|------|------|------|------|------|
| Ops team | FTE allocation × rate | $2,000 | $2,000 | $2,000 | $2,500 | $2,500 | $3,000 |
| Onboarding (amortized) | PP × $1,000 ÷ 30 | $267 | $500 | $833 | $1,167 | $1,500 | $1,833 |
| Server / infra | Scale with MAU | $300 | $300 | $350 | $400 | $450 | $500 |

### G.2. Impression Constraint Check (M24+)

При высоком PP revenue может быть ограничен impression pool (Step 2 constraint flip).

```
Imp_pool(t) = MAU(t) × Sess/MAU(t) × Recs/Sess(t) × Items/Rec × (1-Organic) × Paying_Share(t)
```

**Paying_Share(t)** — доля monetizable impressions, приходящихся на Paying Providers. Растёт с PP.

**Paying_Share_max = 80% [H].** Даже при 100% магазинов paying, ~20% запросов будут нишевыми (размеры, стили), где paying providers не покрывают. Revenue модель не может превысить 80% fill rate.

| Milestone | PP | CP (total) | PP / Stores | **Paying_Share [H]** | Логика |
|-----------|-----|-----|------|-----|--------|
| M12 | 15 | 75 | 13% | 60% | 15 крупных брендов покрывают ~60% запросов |
| M18 | 25 | 90 | 21% | 65% | Шире каталог → больше попаданий |
| M24 | 35 | 105 | 29% | 70% | Step 2 бенчмарк: 25 PP → 70% |
| M30 | 45 | 110 | 38% | 75% | Приближение к потолку |
| M36 | 55 | 115 | 46% | 80% | **Потолок Paying_Share_max** |

| Milestone | MAU | Sessions [D] | Recs [D] | Imp pool paying [D] | Rev if filled | Rev from K-gate | **Binding** |
|-----------|-----|---------|------|------------|--------|--------|----|
| M24 | 8,633 | 12,400 | 27,800 | 58,400 | $21,024 | $20,580 | **K-gate** |
| M30 | 11,589 | 17,200 | 39,500 | 83,000 | $29,880 | $32,130 | **Impression** |
| M36 | 15,907 | 24,500 | 57,000 | 119,700 | $43,092 | $66,000 | **Impression** |

**M30+: Impression-constrained.** Revenue ceiling определяется engagement, не K-gate.

### G.3. Revenue по сценариям (с Phase alignment и impression cap)

**Scenario S (Strict Constitution):**

| Milestone | Phase | **Actual Revenue** | Opex | **Margin** |
|-----------|-------|---------|------|--------|
| M6 | Earn-only | **$0** | $5,406 | **−$5,406** |
| M12 | Earn-only | **$0** | $6,285 | **−$6,285** |
| M18 | Earn-only | **$0** | $7,368 | **−$7,368** |
| M24 | Earn-only | **$0** | $8,815 | **−$8,815** |
| M30 | Earn-only | **$0** | $10,245 | **−$10,245** |
| M33 | **→ Phase 2** | **~$38,000** | ~$11,500 | **+$26,500** |
| M36 | Earn-to-Buy | **$43,092** | $12,496 | **+$30,596** |

*M33 revenue: ~midpoint M30–M36 capacity, capped by impressions.*

**Scenario P (WTP Pilots from M12):**

WTP pilot rate = 30% от full Phase 2 capacity [H]. Обоснование: пилот ограничен малым числом PP-участников (3–5 из 15), тестовые бюджеты.

| Milestone | Phase | **Actual Revenue** | Opex | **Margin** |
|-----------|-------|---------|------|--------|
| M6 | Earn-only | **$0** | $5,406 | **−$5,406** |
| M12 | WTP pilot | **$945** | $6,285 | **−$5,340** |
| M18 | WTP pilot | **$2,063** | $7,368 | **−$5,305** |
| M24 | WTP pilot | **$6,174** | $8,815 | **−$2,641** |
| M30 | WTP pilot | **$8,964** | $10,245 | **−$1,281** |
| M33 | **→ Phase 2** | **~$38,000** | ~$11,500 | **+$26,500** |
| M36 | Earn-to-Buy | **$43,092** | $12,496 | **+$30,596** |

### G.4. Cumulative Investment и Payback

> **Примечание:** Revenue и Opex per period — interpolation от milestone snapshots, не помесячный cashflow. Помесячная P&L-линия (36 строк) — в Block 6. Payback estimate ±2 месяца.

**Scenario S (Strict):**

| Period | Revenue | Opex | Margin | Cumulative |
|--------|---------|------|--------|-----------|
| M1–M12 | $0 | $67,416 | −$67,416 | −$67,416 |
| M13–M24 | $0 | $93,960 | −$93,960 | −$161,376 |
| M25–M33 | $0 | $93,600 | −$93,600 | −$254,976 |
| M33–M36 | $121,700 | $36,000 | +$85,700 | −$169,276 |
| **+ One-time** | | | −$23,000 | **−$192,276** |

**Pre-revenue investment: ~$255K.** Seed не окупается в пределах 36 месяцев. Payback ~M42–44 при сохранении margin ~$30K/мес после Phase 2.

**Scenario P (WTP Pilots):**

| Period | Revenue | Opex | Margin | Cumulative |
|--------|---------|------|--------|-----------|
| M1–M12 | $2,800 | $67,416 | −$64,616 | −$64,616 |
| M13–M24 | $36,000 | $93,960 | −$57,960 | −$122,576 |
| M25–M33 | $54,000 | $93,600 | −$39,600 | −$162,176 |
| M33–M36 | $121,700 | $36,000 | +$85,700 | −$76,476 |
| **+ One-time** | | | −$23,000 | **−$99,476** |

**Pre-Phase 2 investment: ~$162K.** WTP pilots сокращают gap на ~$93K. Seed payback: ~M39–40.

### G.5. Investment Implication

| Метрика | Scenario S | Scenario P |
|---------|-----------|-----------|
| Peak cumulative loss | −$255K | −$162K |
| + One-time | −$278K | −$185K |
| Months to Phase 2 | ~33 | ~33 |
| Months to payback | ~44 | ~40 |
| Monthly burn (avg, Phase 1) | ~$7,700 | ~$4,900 |

**Вывод для инвесторов:** Single seed требует $185–278K pre-revenue инвестиции и 40–44 месяца до payback. Это unit economics одного кластера. Multi-seed economics (Block 4) амортизируют team costs и ускоряют payback через cross-mall effects.

---

## H. SENSITIVITY & SCENARIOS

### H.1. Three Scenarios

| Scenario | Key difference | OIR > 1.0 | Local Seed (all thresholds) | Phase 2 trigger | Seed Payback (Scenario P) |
|----------|---------------|-----------|-----------|---------|-------------|
| **Conservative** | Slow viral, r grows slowly | M30 | M36+ | M36+ | M48+ |
| **Base** | As modeled | M24 | ~M33 | ~M33 | ~M40 |
| **Optimistic** | Strong PMF, fast r | M18 | ~M24 | ~M24 | ~M30 |

*Seed Payback = момент, когда cumulative margin (с учётом $0 revenue в Phase 1 + one-time costs) выходит в ноль. Scenario P (WTP pilots с M12). Scenario S = +4–6 мес к каждому.*

### H.2. Conservative Scenario

- Viral loops: 50% of base case conversion rates
- Retention growth: 50% slower (r = 30% at M36)
- Provider growth: same as base

| Milestone | MAU | k_user | k_prov | k_comb | OIR | Rev capacity (Phase 2 rates) |
|-----------|-----|--------|--------|--------|-----|------|
| M12 | 4,700 | 0.010 | 0.235 | 0.245 | 0.35 | $3,150 |
| M24 | 7,100 | 0.028 | 0.305 | 0.333 | 0.72 | $17,640 |
| M36 | 10,800 | 0.055 | 0.270 | 0.325 | 1.08 | $31,200 |

Local Seed: **~M36** (D30 retention last to clear). Actual Revenue = $0 до ~M36 (Scenario S), WTP pilots до ~M36 (Scenario P).

### H.3. Optimistic Scenario

- Viral loops: 150% of base conversion rates
- Retention: r = 40% by M24
- Provider: aggressive, 50+ PP by M24

| Milestone | MAU | k_user | k_prov | k_comb | OIR | Rev capacity (Phase 2 rates) |
|-----------|-----|--------|--------|--------|-----|------|
| M12 | 5,500 | 0.030 | 0.260 | 0.290 | 0.55 | $3,150 |
| M24 | 13,500 | 0.092 | 0.320 | 0.412 | 1.65 | $28,800 |
| M36 | 26,000 | 0.165 | 0.270 | 0.435 | 3.10 | $56,000 |

Local Seed: **~M24**. Phase 2 revenue starts ~M24 at capacity ~$28,800/мес → rapid payback.

### H.4. Single-Variable Sensitivity на OIR at M24

| Variable | −30% | Base | +30% | Impact |
|----------|------|------|------|--------|
| Paying Providers count | OIR 0.82 | 1.06 | 1.30 | **High** |
| Activated per Provider | OIR 0.87 | 1.06 | 1.25 | **High** |
| Retention rate (r) | OIR 0.95 | 1.06 | 1.18 | Medium |
| Sharing rate | OIR 1.00 | 1.06 | 1.12 | Low |
| Referral rate | OIR 1.00 | 1.06 | 1.12 | Low |

**Top 2 рычага OIR:** Paying Provider count и Activated per Provider. Оба — Provider-side.

### H.5. Retention sensitivity: impact on OIR and revenue timeline

Высокая retention косвенно усиливает OIR (через рост MAU → больше viral → больше N_earned). Показываем эффект:

| r at M24 | MAU | N_viral | N_earned | OIR | Rev capacity (Phase 2) | Phase 2 trigger |
|----------|-----|---------|---------|-----|---------|---------|
| 0.20 | 7,554 | 350 | 3,010 | 1.02 | $17,800 | ~M36+ (D30 slow) |
| 0.25 | 8,055 | 390 | 3,050 | 1.04 | $19,100 | ~M36+ (D30 slow) |
| **0.30** | **8,633** | **443** | **3,103** | **1.06** | **$20,580** | **~M33 (base)** |
| 0.35 | 9,303 | 510 | 3,170 | 1.08 | $22,200 | ~M28 |
| 0.40 | 10,087 | 600 | 3,260 | 1.11 | $24,500 | ~M24 (accel.) |
| 0.50 | 12,000 | 820 | 3,480 | 1.18 | $29,000 | ~M20 (accel.) |

**Вывод:** r влияет на OIR умеренно (Medium impact в §H.4), но **критически** влияет на Phase 2 trigger — разница между M20 и M36+. Retention = главный рычаг timeline, не revenue magnitude.

### H.6. Failure Scenario: Retention Stuck at 25%

**Предпосылка:** Retention не превышает r = 25% (рекомендации недостаточно точны, продукт не формирует ритуал). Все остальные параметры — base case.

| Milestone | r | MAU | N_earned | OIR | k_comb | Rev capacity | Opex |
|-----------|---|-----|---------|-----|--------|---------|------|
| M12 | 18% | 5,160 | 1,291 | 0.44 | 0.250 | $3,150 | $6,412 |
| M18 | 22% | 6,438 | 2,076 | 0.71 | 0.323 | $6,875 | $7,368 |
| M24 | 25% | 7,390 | 3,103 | 1.06 | 0.420 | $17,220 | $8,065 |
| M30 | 25% | 8,247 | 3,945 | 1.34 | 0.478 | $22,320 | $8,624 |
| M36 | 25% | 9,166 | 4,810 | 1.64 | 0.525 | $26,400 | $9,225 |

**Последствия с Phase alignment:**
- OIR > 1.0 достигается к ~M24 (✓)
- D30 retention > 40%: **никогда не достигается** (✗)
- **Local Seed по Конституции: не достигнут** → Phase 2 не запускается
- **Revenue = $0 навсегда** (Scenario S) или ограничен WTP pilots (Scenario P)

**Cumulative burn (Scenario S, retention stuck):**

| Period | Revenue | Opex | Cumulative |
|--------|---------|------|-----------|
| M1–M12 | $0 | $67,416 | −$67,416 |
| M13–M24 | $0 | $90,000 | −$157,416 |
| M25–M36 | $0 | $107,000 | −$264,416 |
| + One-time | | | **−$287,416** |

**Это точка отказа модели.** При retention stuck 25%:
- Сеть растёт (MAU, Providers, OIR — всё в порядке)
- Но Local Seed формально не достигнут → Конституция блокирует монетизацию
- Burn rate ~$7–9K/мес без revenue → $287K за 36 месяцев

**Варианты:**
1. **Снизить порог D30 для Local Seed** (e.g., 30% вместо 40%) — если OIR > 1.0 и все остальные пороги выполнены, retention 30% может быть достаточным для «достаточно хорошего» PMF
2. **WTP pilots как bridge** (Scenario P) — Конституция уже допускает пилоты. При 30% от capacity = ~$5–8K/мес revenue к M24 → cumulative burn сокращается до ~$185K
3. **Признать: retention < 25% устойчиво = отсутствие PMF** → pivot или закрытие. Определить kill threshold: если r < 20% на M18, прекратить инвестиции в seed

---

## I. STRUCTURAL FINDINGS

### I.1. k_combined → OIR replacement

k_combined (Конституция §3.1) имеет структурный потолок (1−r). В steady-state `r + k_combined ≤ 1.0` всегда (с равенством при OIR→∞). Оба порога — k_combined > 1.0 и r + k > 1.0 — математически недостижимы.

**Рекомендация для Конституции v1.3:** Единый порог **OIR > 1.0** (earned > organic). Достижим ~M24 (base case). Содержательно = «сеть растёт преимущественно за счёт собственных каналов».

### I.2. Retention — binding constraint and Phase 2 gatekeeper

D30 retention > 40% — последний порог Local Seed. Все остальные достигаются к M24. Без целенаправленных retention-механик Local Seed отодвигается за M36.

**С учётом Phase alignment это означает:** Revenue = $0 в течение ~33 месяцев (Scenario S). Pre-revenue инвестиция в один seed: $255–278K. Retention — не просто «продуктовая метрика», а **единственный гейт между $0 и $30K+/мес revenue.**

### I.3. Provider growth → revenue, Viral growth → sustainability

| Канал | Revenue impact | MAU impact | Sustainability |
|-------|---------------|-----------|---------------|
| N_organic | Нет | Стабильная база | Зависимость от footfall |
| N_provider | **Прямой** (Credits) | Да | Зависит от Provider мотивации |
| N_viral | Нет напрямую | **Да** | **Self-sustaining** |

### I.4. Impression constraint появляется в M30+

При >45 PP и высоком MAU revenue ceiling определяется impression pool, а не K-gate. Дальнейший рост revenue требует роста engagement (sessions/user, recs/session).

### I.5. Phase transition (with Phase alignment)

```
M1–M33:  Phase 1 (Earn-only). Revenue = $0 (or WTP pilots ≤30% capacity)
         Network grows: MAU, Providers, OIR — all progressing
         Binding constraint: D30 retention → 40%

~M33:    Phase 2 trigger (Local Seed achieved)
         Revenue switches on at mature network rates (~$38K/мес)
         Not gradual ramp — full Credits Economy immediately

M33+:    Revenue = MIN(K_gate, Impression_cap)
         Impression-constrained by ~M36 (45+ PP)
```

### I.6. Investment framing for VC

Single seed = $185–278K pre-revenue investment over ~33 months. This is comparable to:
- Opening a retail location ($200–500K)
- B2B SaaS customer acquisition ($150–300K CAC for enterprise)

Но в отличие от обоих: после Phase 2 trigger margin ~$30K/мес и растёт. Multi-seed economics (Block 4) с cross-mall effects и shared costs существенно улучшают unit economics.

---

## J. SUMMARY FORMULAS

```
# Core dynamics
N_total(t)   = N_organic(t) + N_provider(t) + N_viral(t)
N_organic     = 2,940 / мес [H]   (constant; calibrated from Step 1 footfall × discovery)
MAU(t)       = N_total(t) / (1 - r(t))
N_provider(t)= PP(t) × ActPerPP(t) + NP(t) × ActPerNP(t)
N_viral(t)   = N_share(t) + N_referral(t) + N_wom(t)

# k-metrics
k_user(t)    = N_viral(t) / MAU(t)
k_provider(t)= N_provider(t) / MAU(t)
k_combined(t)= k_user(t) + k_provider(t)             [ceiling: 1-r(t)]
OIR(t)       = (N_provider(t) + N_viral(t)) / N_organic(t)   [threshold: > 1.0]

# Viral loops
N_share(t)   = MAU(t) × share_rate(t) × reach(t) × install_conv(t) × activate_conv(t)
N_referral(t)= MAU(t) × ref_rate(t) × invites(t) × accept_conv(t) × activate_conv(t)
N_wom(t)     = Fashion_FF × wom_lift(t) × install_conv(t) × activate_conv(t)

# Revenue (Phase-gated)
Revenue_capacity(t) = MIN(K_gate_rev(t), Impression_rev(t))
K_gate_rev(t)       = PP(t) × MIN(Earned(t) × K(t), Desired(t)) × Price(t)
Impression_rev(t)   = Imp_pool_paying(t) × Cr_per_slot × Price(t)
Paying_Share_max    = 80% [H]

# Phase gating (Конституция §4)
Actual_Revenue(t)   = 0                              if Phase 1 (Local Seed not achieved)
                    = Revenue_capacity(t) × 0.30 [H] if Phase 1 WTP pilot
                    = Revenue_capacity(t)             if Phase 2+
```

---

*Inputs: Block1_Step1_v1.0, Block1_Step2_v1.0 | Протокол: UNDE_Model_Constitution_v1.2*
