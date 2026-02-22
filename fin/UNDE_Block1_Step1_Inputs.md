# UNDE Block 1 — Unit Economics одного Local Seed
## Подшаг 1: Inputs & Assumptions
### Ibn Battuta Mall | v1.0

---

## 0. Почему Ibn Battuta

Консервативный baseline: ниже footfall и аренда, чем у центральных моллов. Если экономика сходится здесь — сходится в любом молле 200–500 магазинов в Дубае.

---

## A. ПРОФИЛЬ МОЛЛА

| Параметр | Значение | Тип | Источник |
|----------|---------|-----|----------|
| Outlets всего | 400+ | [V] | Официальный сайт / Visit Dubai |
| Stores (магазины) | 300+ | [V] | Wikipedia |
| Магазинов fashion | ~120 | [D] | 300 stores × 40% fashion-доля [B] (бенчмарк по Дубаю) |
| Monthly footfall (baseline) | 1,500,000 | [B/H] | 15–18M/год, third-party estimate (Occupi и др.) |
| Monthly footfall (upside) | 1,750,000 | [V] | 21M/год, рекорд 2017, пресс-релизы |
| Daily footfall (baseline) | ~50,000 | [D] | 1.5M ÷ 30 |
| Доля fashion-посетителей | 35% | [B] | Аудит: оценка 30–40%, нижняя середина |
| Fashion monthly footfall (baseline) | 525,000 | [D] | 1,500,000 × 35% |

---

## B. ВОРОНКА ПОЛЬЗОВАТЕЛЕЙ

| Параметр | Значение | Тип | Логика |
|----------|---------|-----|--------|
| App adoption rate | 2% | [H] | % от fashion footfall. Бенчмарк: mall apps ~1–3% в первый год |
| Monthly installs | 10,500 | [D] | 525,000 × 2% |
| Install → Activation rate | 40% | [H] | Онбординг + первая Onsite Active Visit. Бенчмарк: consumer apps 20–50% |
| New Onsite Activated / month (N) | 4,200 | [D] | 10,500 × 40% |
| Monthly Return Rate (r) | 15% | [H] | Pre-Seed steady-state. Порог Seed по Конституции: D30 >40% |

**Steady-state Onsite MAU (формула геометрического ряда):**

```
Total_Onsite_MAU    = N / (1 - r) = 4,200 / 0.85 = 4,941
Returning_Onsite_MAU = N × r / (1 - r) = 4,200 × 0.15 / 0.85 = 741
```

| Метрика | Значение | Тип | Назначение |
|---------|---------|-----|-----------|
| Onsite MAU (total) | 4,941 | [D] | Общая аудитория, AI inference cost |
| New Onsite Activated | 4,200 | [D] | Acquisition, Provider earning |
| Returning Onsite MAU | 741 | [D] | Core monetization base |

**Recommendations (сегментировано по поведению):**

| Сегмент | MAU | Visits/мес [H] | Recs/visit [H] | Sessions [D] | Recs [D] |
|---------|-----|---------------|----------------|-------------|---------|
| New activated | 4,200 | 1.0 | 2.0 | 4,200 | 8,400 |
| Returning | 741 | 3.0 | 2.5 | 2,223 | 5,557 |
| **Total** | **4,941** | | | **6,423** | **13,957** |

**Sensitivity (footfall):**

| Сценарий | Footfall/мес | Fashion footfall | New Activated | Returning MAU | Total Onsite MAU | Monthly Recs |
|----------|-------------|-----------------|--------------|--------------|-----------------|-------------|
| Downside | 1,250,000 | 437,500 | 3,500 | 617 | 4,117 | 11,631 |
| **Baseline** | **1,500,000** | **525,000** | **4,200** | **741** | **4,941** | **13,957** |
| Upside | 1,750,000 | 612,500 | 4,900 | 864 | 5,764 | 16,283 |

---

## C. ITEM IMPRESSIONS И МОНЕТИЗАЦИЯ

| Параметр | Значение | Тип | Логика |
|----------|---------|-----|--------|
| Items per Recommendation | 5 | [H] | AI показывает 3–6 вариантов |
| Total Item Impressions / month | 69,785 | [D] | 13,957 × 5 |
| Organic threshold | 30% | [H] | Конституция §7: мин. 30% слотов органические |
| **Monetizable Item Impressions / month** | **48,849** | [D] | 69,785 × 70% |

### Provider Structure

| Метрика | Значение | Тип | Логика |
|---------|---------|-----|--------|
| Connected Providers (coverage) | 75+ | [H] | Порог Seed: >50% fashion (~120). 75 = 63% покрытие. Каталог загружен, органически попадают в рекомендации |
| Active Paying Providers | 15 | [H] | Provider'ы, активно тратящие Credits на приоритет |
| Paying Provider Impression Share | 60% | [H] | 15 paying из 120 stores — крупные бренды с широким каталогом покрывают ~60% релевантных запросов |
| Impressions available to Paying Providers | 29,309 | [D] | 48,849 × 60% |
| Avg Imp per Paying Provider / month | 1,953 | [D] | 29,309 ÷ 15 |

### Provider-driven acquisition: связь с k_provider

Provider-driven acquisition target из Конституции: 30–40% от общего трафика [H]. Это дальний таргет для зрелого Seed. На старте acquisition идёт от всех Connected Providers (75+), не только Paying (15):

| Метрика | Значение | Тип | Логика |
|---------|---------|-----|--------|
| Activated через Paying Providers | 300/мес | [D] | 15 × 20 activated per provider |
| Activated через Connected (non-paying) | 900/мес | [H] | 60 providers × ~15 activated |
| **Total Provider-driven activated** | **1,200/мес** | [D] | 300 + 900 |
| **% от New Onsite Activated** | **29%** | [D] | 1,200 / 4,200. Близко к нижней границе таргета 30–40% |

---

## D. CREDITS ECONOMY (per Active Paying Provider)

### D.1. Earning side

**Модельный Provider** (средний, приводит пользователей через QR + соцсети):

| Действие | Users/мес | Credits/действие [H] | Credits/мес [D] |
|----------|----------|---------------------|----------------|
| Установки по ссылке Provider | 50 | +10 | 500 |
| Из них activated (40%) | 20 | +100 | 2,000 |
| D7 return (30% от activated) | 6 | +50 | 300 |
| D30 return (15% от activated) | 3 | +150 | 450 |
| Shares от привлечённых | 5 | +30 | 150 |
| Verified Actions (покупки) | 4 | +200 | 800 |
| **Итого Earned / мес** | | | **4,200** |

### D.2. K-коэффициент (Rolling 90d Earned)

**Правило:** K определяется по Rolling 90d Earned (Qualified) — суммарные заработанные Credits за последние 90 дней. Это не «баланс» (не уменьшается при тратах), а гейт для определения Max Purchase.

| Месяц | Earned (месяц) | Rolling 90d Earned | K [H] | Max Purchase (месяц) [D] |
|-------|---------------|-------------------|-------|--------------------------|
| M1 | 4,200 | 4,200 | 0.3 | 1,260 |
| M2 | 4,200 | 8,400 | 0.5 | 2,100 |
| M3 | 4,200 | 12,600 | 0.5 | 2,100 |
| M4+ | 4,200 | 12,600 (steady) | 0.5 | 2,100 |

**Steady-state (M4+):** Rolling 90d Earned = 12,600 → K = 0.5 → Max Purchase = 2,100/мес

### D.3. Spending side

| Параметр | Значение | Тип | Логика |
|----------|---------|-----|--------|
| Avg Credits per prioritized slot | 3 | [H] | Аукционная механика; на старте конкуренция низкая |
| Provider хочет приоритизировать | 50% своих слотов | [H] | Часть и так органически видна |
| Slots to prioritize / month | 976 | [D] | 1,953 × 50% |
| Desired Credits spend / month | 2,928 | [D] | 976 × 3 |
| **Capped by Max Purchase** | **2,100** | [D] | FLOOR(MIN(2,928; 2,100)). K ограничивает трату |

### D.4. Revenue per Provider

| Параметр | Значение | Тип |
|----------|---------|-----|
| Purchased Credits / month (steady-state) | 2,100 | [D] |
| Price per Credit | $0.10 | [H] |
| **Revenue per Provider / month** | **$210** | [D] |

---

## E. COSTS (per Seed / month)

| Статья | Значение | Тип | Логика |
|--------|---------|-----|--------|
| AI cost per MAU | $0.70 | [H] | AI_cost_per_MAU = Queries_per_MAU × Avg_cost_per_query. Пессимистичная оценка |
| AI cost / month | $3,459 | [D] | 4,941 MAU × $0.70 |
| Ops team (part-time per Seed) | $2,000 | [H] | 0.5 FTE community/support @ $4K/мес |
| Provider onboarding (amortized) | $500 | [H] | 15 providers × $1,000 one-time ÷ 30 мес |
| Server / infra | $300 | [H] | Cloud, indoor positioning processing |
| **Total monthly opex per Seed** | **$6,259** | [D] | |

**One-time launch cost per Seed:**

| Статья | Значение | Тип |
|--------|---------|-----|
| Provider outreach & onboarding | $15,000 | [H] |
| Mall partnership / setup | $5,000 | [H] |
| Local marketing launch | $3,000 | [H] |
| **Total one-time** | **$23,000** | [H] |

---

## F. SEED-LEVEL P&L SNAPSHOT

| Метрика | Значение | Тип |
|---------|---------|-----|
| Core Revenue per Seed / month | $3,150 | [D] |
| Total Opex per Seed / month | $6,259 | [D] |
| **Core Contribution Margin** | **−$3,109** | [D] |

---

## G. СВОДКА INPUTS

| Параметр | Значение | Тип |
|----------|---------|-----|
| Monthly footfall (baseline) | 1,500,000 | [B/H] |
| Fashion footfall share | 35% | [B] |
| App adoption rate | 2% | [H] |
| Activation rate | 40% | [H] |
| Monthly Return Rate (r) | 15% | [H] |
| Onsite MAU (total, steady-state) | 4,941 | [D] |
| Returning Onsite MAU | 741 | [D] |
| Monthly Recommendations | 13,957 | [D] |
| Items / recommendation | 5 | [H] |
| Organic threshold | 30% | [H] |
| Connected Providers | 75+ | [H] |
| Active Paying Providers | 15 | [H] |
| Paying Provider Impression Share | 60% | [H] |
| Credits per prioritized slot | 3 | [H] |
| K coefficient (steady-state) | 0.5 | [H] |
| Price per Credit | $0.10 | [H] |
| Revenue per Provider / month | $210 | [D] |
| Core Revenue per Seed / month | $3,150 | [D] |
| AI cost per MAU | $0.70 | [H] |
| Monthly opex per Seed | $6,259 | [D] |
| Contribution Margin | −$3,109 | [D] |
| One-time launch cost | $23,000 | [H] |

---

## H. ПОЛИТИКА ОКРУГЛЕНИЙ

| Правило | Применение |
|---------|-----------|
| Пользователи, сессии, Providers | FLOOR (целое число, округление вниз) |
| Credits (earned, purchased) | FLOOR (целое число, округление вниз) |
| Item Impressions, Slots | FLOOR (целое число, округление вниз) |
| Revenue, Costs | ROUND до целого доллара |
| Retention %, adoption % | Без округления (хранятся как десятичные) |

---

*Источники: Аудит Dubai Malls Feb 2026, UNDE_Model_Constitution_v1.2, Visit Dubai, Wikipedia, Occupi (third-party estimates)*
