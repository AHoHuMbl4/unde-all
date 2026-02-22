# UNDE Block 1 — Unit Economics одного Local Seed
## Подшаг 2: Conversion Chain
### Ibn Battuta Mall | v1.0

---

## 0. Назначение

Полная воронка от Mall Footfall до Revenue per Seed. Каждый шаг — одна конверсия с типом источника. Все inputs из Подшага 1 v1.0. Арифметика верифицирована программно.

**Упрощения Step 2 (будут сняты в Step 3):**
- `Earned` = earned/month (не rolling 90d balance). Накопление, decay и spend — в Step 3.
- `Monthly Return Rate (r)` = приближение steady-state, не строгая когортная D30.

---

## A. WATERFALL: FOOTFALL → REVENUE

### A.1. User Funnel

| Шаг | Метрика | Значение | Conversion | Тип conv. |
|-----|---------|---------|-----------|----------|
| 0 | Mall Monthly Footfall | 1,500,000 | — | [B/H] |
| 1 | Fashion Footfall | 525,000 | 35% от шага 0 | [B] |
| 2 | App Installs | 10,500 | 2% от шага 1 | [H] |
| 3 | New Onsite Activated (N) | 4,200 | 40% от шага 2 | [H] |
| 4 | Returning Onsite MAU | 741 | N × r / (1 − r) | [D] |
| 5 | **Total Onsite MAU** | **4,941** | N / (1 − r) | [D] |

Где `r` = Monthly Return Rate (approx) = 0.15 [H].

**Сквозная конверсия Footfall → Onsite MAU: 0.33%** [D]

### A.2. Engagement Funnel

| Шаг | Метрика | Значение | Формула |
|-----|---------|---------|---------|
| 6a | Sessions (new) | 4,200 | 4,200 MAU × 1.0 visit/мес [H] |
| 6b | Sessions (returning) | 2,223 | 741 MAU × 3.0 visits/мес [H] |
| 6 | **Total Sessions** | **6,423** | 4,200 + 2,223 |
| 7a | Recs (new) | 8,400 | 4,200 sess × 2.0 recs/visit [H] |
| 7b | Recs (returning) | 5,557 | 2,223 sess × 2.5 recs/visit [H] |
| 7 | **Total Recommendations** | **13,957** | 8,400 + 5,557 |
| 8 | Total Item Impressions | 69,785 | 13,957 × 5 items/rec [H] |
| 9 | **Monetizable Item Impressions** | **48,849** | 69,785 × 70% (organic threshold 30% [H]) |

### A.3. Impression Allocation

Не все monetizable impressions доступны paying providers. Impression возникает у любого provider'а, чей товар релевантен запросу. Paying providers получают приоритет внутри своих eligible слотов.

| Параметр | Значение | Тип | Логика |
|----------|---------|-----|--------|
| Paying Provider Impression Share | 60% | [H] | 15 paying из 120 stores — крупные бренды с широким каталогом покрывают ~60% релевантных запросов |
| Impressions available to Paying Providers | 29,309 | [D] | 48,849 × 60% |
| Impressions to non-paying (organic only) | 19,540 | [D] | 48,849 × 40% |

**Share масштабируется с числом Paying Providers:** при 40 PP из 120 stores → share ≈ 80% [H].

### A.4. Monetization Funnel (15 Paying Providers, K=0.5)

| Шаг | Метрика | Значение | Формула |
|-----|---------|---------|---------|
| 10 | Paying Provider Imp pool | 29,309 | 48,849 × 60% |
| 11 | Imp per Paying Provider | 1,953 | 29,309 ÷ 15 |
| 12 | Slots to prioritize (50%) | 976 | 1,953 × 50% [H] |
| 13 | Desired Credits spend | 2,928 | 976 × 3 Cr/slot [H] |
| 14 | K-cap (Max Purchase) | 2,100 | Earned 4,200/мес × K=0.5 |
| 15 | **Purchased Credits / Provider** | **2,100** | MIN(2,928; 2,100). K-constrained |
| 16 | **Revenue / Provider / month** | **$210** | 2,100 × $0.10/Cr [H] |

### A.5. Seed-Level Roll-up

| Метрика | Значение | Формула |
|---------|---------|---------|
| Active Paying Providers | 15 | [H] |
| **Core Revenue / Seed / month** | **$3,150** | 15 × $210 |
| Total Opex / Seed / month | $6,259 | AI $3,459 + Ops $2,000 + Onboard $500 + Server $300 |
| **Contribution Margin** | **−$3,109** | $3,150 − $6,259 |

---

## B. INVENTORY REVENUE CEILING (impression-based)

Максимальная выручка при 100% заполнении всех eligible слотов paying providers. Не учитывает K-cap (отдельное ограничение).

```
Inventory_ceiling = Paying_Provider_Imp_Pool × Credits_per_slot × Price_per_Credit
                  = 29,309 × 3 × $0.10 = $8,793/мес
```

| Метрика | Значение |
|---------|---------|
| Inventory ceiling | $8,793 |
| Current opex | $6,259 |
| Ceiling vs Opex | **Ceiling > Opex** |
| Breakeven fill rate | 71.2% |
| Current effective fill rate | 35.8% |

Модель может сойтись при достаточном fill rate. Gap между текущими 35.8% и необходимыми 71.2% — достижимый через рост Paying Providers и K.

---

## C. CONSTRAINT FLIP: K-CAP → IMPRESSION SCARCITY

Переключение binding constraint на **~21 Paying Providers** (при share 60%):

| Paying Prov | Imp/Prov | Desired Cr | K-cap | Purchased | Rev/Prov | Rev/Seed | Constraint |
|------------|---------|-----------|-------|----------|---------|---------|-----------|
| 10 | 2,930 | 4,395 | 2,100 | 2,100 | $210 | $2,100 | K-cap |
| 15 | 1,953 | 2,928 | 2,100 | 2,100 | $210 | $3,150 | K-cap |
| 20 | 1,465 | 2,196 | 2,100 | 2,100 | $210 | $4,200 | K-cap |
| **21** | **1,395** | **2,091** | **2,100** | **2,091** | **$209** | **$4,391** | **Flip** |
| 25 | 1,172 | 1,758 | 2,100 | 1,758 | $176 | $4,395 | Impression |
| 30 | 976 | 1,464 | 2,100 | 1,464 | $146 | $4,392 | Impression |
| 35 | 837 | 1,254 | 2,100 | 1,254 | $125 | $4,389 | Impression |
| 50 | 586 | 879 | 2,100 | 879 | $88 | $4,395 | Impression |

**Revenue плато после flip: ~$4,395/мес.** Дальнейший рост — только через engagement (MAU, Recs) или рост share (больше paying providers → шире каталог → выше share).

---

## D. SINGLE-VARIABLE SENSITIVITY

### D.1. K-коэффициент (15 PP, share 60%)

| K | Max Purchase | Desired | Purchased | Rev/Seed | Constraint |
|---|-------------|---------|----------|---------|-----------|
| 0.3 | 1,260 | 2,928 | 1,260 | $1,890 | K-cap |
| **0.5** | **2,100** | **2,928** | **2,100** | **$3,150** | **K-cap** |
| 0.7 | 2,940 | 2,928 | 2,928 | $4,392 | Impression |
| 1.0 | 4,200 | 2,928 | 2,928 | $4,392 | Impression |

**При K ≥ 0.7 constraint flips to impression.** K выше 0.7 не увеличивает revenue при 15 PP.

### D.2. Price per Credit (15 PP, K=0.5)

| Price/Credit | Rev/Seed |
|-------------|---------|
| $0.05 | $1,575 |
| $0.08 | $2,520 |
| **$0.10** | **$3,150** |
| $0.12 | $3,780 |
| $0.15 | $4,725 |
| $0.20 | $6,300 |

### D.3. AI Cost per MAU (Revenue = $3,150)

| AI $/MAU | AI Cost | Total Opex | Margin |
|---------|--------|-----------|--------|
| $0.30 | $1,482 | $4,282 | −$1,132 |
| $0.50 | $2,470 | $5,270 | −$2,120 |
| **$0.70** | **$3,459** | **$6,259** | **−$3,109** |
| $1.00 | $4,941 | $7,741 | −$4,591 |

### D.4. Adoption Rate (15 PP, K=0.5)

| Adoption | MAU | Recs | Mon. Imp | Rev | Opex | Margin |
|---------|-----|------|---------|-----|------|--------|
| 1.0% | 2,470 | 6,975 | 24,412 | $2,196 | $4,529 | −$2,333 |
| 1.5% | 3,705 | 10,462 | 36,617 | $3,150 | $5,394 | −$2,244 |
| **2.0%** | **4,941** | **13,957** | **48,849** | **$3,150** | **$6,259** | **−$3,109** |
| 2.5% | 6,176 | 17,445 | 61,057 | $3,150 | $7,123 | −$3,973 |
| 3.0% | 7,411 | 20,932 | 73,262 | $3,150 | $7,988 | −$4,838 |

**Парадокс adoption:** При K-constrained revenue (15 PP), рост adoption увеличивает MAU и AI cost, но revenue не растёт (K-cap не зависит от MAU). Adoption выгоден только в связке с ростом Paying Providers.

---

## E. DOWNSIDE SCENARIOS

| Сценарий | PP | Adopt | Activ | r | MAU | Rev | Opex | Margin |
|----------|---|------|------|---|-----|-----|------|--------|
| **Worst case** | 10 | 2.0% | 40% | 10% | 4,666 | $2,100 | $5,899 | −$3,799 |
| Low retention | 15 | 2.0% | 40% | 10% | 4,666 | $3,150 | $6,066 | −$2,916 |
| Low adoption | 15 | 1.0% | 40% | 15% | 2,470 | $2,196 | $4,529 | −$2,333 |
| Low activation | 15 | 2.0% | 25% | 15% | 3,088 | $2,745 | $4,962 | −$2,217 |

Worst case: −$3,799/мес. Наименьший убыток при low activation (−$2,217): меньше MAU → меньше AI cost.

---

## F. COMBO SCENARIOS

**Opex breakdown:** AI (MAU × $0.70) + Ops ($2,000) + Onboard (PP × $1,000 ÷ 30) + Server ($300).

| Сценарий | PP | K | $/Cr | r | Share | MAU | Rev | Opex | Margin | ARPU |
|----------|---|---|-----|---|-------|-----|-----|------|--------|------|
| **Baseline** | **15** | **0.5** | **$0.10** | **15%** | **60%** | **4,941** | **$3,150** | **$6,259** | **−$3,109** | **$0.64** |
| More PP (optimal) | 21 | 0.5 | $0.10 | 15% | 60% | 4,941 | $4,391 | $6,459 | −$2,068 | $0.89 |
| Higher K | 15 | 0.7 | $0.10 | 15% | 60% | 4,941 | $4,392 | $6,259 | −$1,867 | $0.89 |
| Higher price | 15 | 0.5 | $0.15 | 15% | 60% | 4,941 | $4,725 | $6,259 | −$1,534 | $0.96 |

### Breakeven paths

| Path | PP | K | $/Cr | r | Share | MAU | Rev | Opex | Margin |
|------|---|---|-----|---|-------|-----|-----|------|--------|
| **A: Price + 21PP** | **21** | **0.5** | **$0.15** | **15%** | **60%** | **4,941** | **$6,587** | **$6,459** | **+$128** |
| **B: Growth (mod all)** | **25** | **0.7** | **$0.12** | **20%** | **70%** | **5,250** | **$7,173** | **$6,808** | **+$365** |
| **C: Mature Seed** | **40** | **0.7** | **$0.12** | **30%** | **80%** | **6,000** | **$11,030** | **$7,833** | **+$3,197** |

**Path A** — ближайший breakeven: +6 Paying Providers + Price/Credit $0.15. Все остальные параметры baseline.

**Payback on one-time $23,000:**

| Path | Margin/мес | Payback |
|------|-----------|---------|
| A: Price + 21PP | +$128 | ~180 мес (не реалистичен как standalone) |
| B: Growth | +$365 | ~63 мес |
| C: Mature Seed | +$3,197 | **7.2 мес** |

---

## G. СТРУКТУРНЫЕ ВЫВОДЫ

### G.1. Impression share — structural driver

| Paying Providers | Estimated Share [H] | Inventory Ceiling | vs Opex |
|-----------------|--------------------|--------------------|---------|
| 15 (12% stores) | 60% | $8,793 | $8,793 > $6,259 ✓ |
| 25 (21%) | 70% | $10,258 | $10,258 > $6,808 ✓ |
| 40 (33%) | 80% | $11,724 | $11,724 > $7,833 ✓ |

При AI cost $0.70/MAU inventory ceiling выше opex во всех сценариях. Structural blocker отсутствует.

### G.2. Два потолка revenue

1. **Inventory ceiling** = Paying Imp Pool × Cr/slot × $/Cr. Зависит от engagement + share.
2. **K-gate ceiling** = ΣProviders × Earned × K × $/Cr. Зависит от earning + K.

Revenue = MIN(inventory, K-gate). При малом PP → K-gate binding. При большом PP → inventory binding.

### G.3. Парадокс adoption

Рост adoption увеличивает MAU → AI cost, но не revenue (K-capped). Revenue растёт от adoption только при одновременном росте Paying Providers. Следствие: не тратить на user acquisition больше, чем Providers готовы монетизировать.

### G.4. Три рычага breakeven (по силе воздействия)

1. **Paying Provider count** — линейный рост revenue до flip (~21 PP). Каждый +1 PP = +$210/мес.
2. **Price per Credit** — $0.10 → $0.15 = +50% revenue при тех же Credits. Требует willingness-to-pay validation.
3. **K unlock** — при 15 PP, K 0.5→0.7 = +$1,242 revenue. Но выше 0.7 constraint flips to impression.

---

## H. СКВОЗНАЯ ФОРМУЛА

```
Revenue_Seed = Paying_Providers × MIN(Earned × K, Desired_Spend) × Price_per_Credit

Earned          = f(Users_brought, Activation, Retention, VAs)     [per provider/month]
Desired_Spend   = (Paying_Imp_Pool ÷ PP) × Prio_rate × Cr_per_slot
Paying_Imp_Pool = Monetizable_Imp × Impression_Share

Monetizable_Imp = Total_Recs × Items/rec × (1 − Organic_threshold)
Total_Recs      = Sess_new × Recs/visit_new + Sess_ret × Recs/visit_ret

Binding constraint flips at ~21 PP (at share 60%, K=0.5, current engagement)
```

---

## I. UNIT ECONOMICS RATIOS (baseline)

| Метрика | Значение | Тип | Примечание |
|---------|---------|-----|-----------|
| ARPU (Revenue / total Onsite MAU) | $0.64 | [D] | |
| Revenue / Returning MAU | $4.25 | [D] | Ratio — revenue генерируется всей базой |
| Revenue / Session | $0.49 | [D] | |
| Revenue / Recommendation | $0.23 | [D] | |
| Revenue / Monetizable Impression | $0.064 | [D] | |
| Cost / Onsite MAU | $1.27 | [D] | |
| Revenue / Cost per MAU | 0.50x | [D] | |
| Footfall → Revenue | $0.0021/visitor | [D] | |

---

*Inputs: UNDE_Block1_Step1_Inputs_v1.0 | Протокол: UNDE_Model_Constitution_v1.2*
