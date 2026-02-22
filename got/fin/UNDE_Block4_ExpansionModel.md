# UNDE Block 4 — Expansion Model
## Режимы масштабирования, multi-seed economics, cross-mall effects
### Dubai Market | v1.1

---

## 0. Назначение

Формализация перехода от single seed (Block 3) к multi-seed expansion. Определение трёх операционных режимов, триггеров переключения, shared cost allocation, cross-mall effects и критериев выхода на второй рынок.

**Зависимости:**
- Inputs: Block 1 Steps 1–2, Block 3 (Network Dynamics v1.0)
- Протокол: UNDE_Model_Constitution_v1.2
- Key Block 3 outputs: single seed = $185–278K investment, ~M33 Local Seed, ~M40–44 payback

**Терминология:**
- **CP** (Connected Providers) — все магазины с интеграцией (бесплатный профиль + каталог)
- **PP** (Paying Providers) — магазины в Credits Economy
- **MAU** — в Block 4 всегда = **Onsite MAU** (пользователи с ≥1 Onsite Active Visit за 30 дней). Конституция §1.1
- **MAU ≈ 5,000** — округление Block 3 canonical value 4,978 (at M12, r=15%). Block 4 = strategic model; точные числа — Block 3/6

---

## A. EXPANSION OPERATING MODEL: 3 РЕЖИМА

### A.1. Определение режимов

| Режим | Manual | Semi-Auto | Self-Serve |
|-------|--------|-----------|-----------|
| **Суть** | Каждый seed запускается командой на месте, 36-day protocol | Часть процессов автоматизирована, team координирует удалённо | Providers подключаются сами, team только мониторит |
| **Provider onboarding** | Ручной: встречи, каталог, обучение | Шаблонный: self-serve dashboard + remote support | Self-serve: API/dashboard, auto-validation |
| **Feed integration** | Manual upload + validation | Template-based + auto-check | API push / scraping, auto-validation |
| **Launch activation** | Field team в молле (theater, QR) | Playbook + local agency | Provider-driven + UNDE templates |
| **Quality control** | Daily traffic-light review | Weekly automated + alerts | Real-time dashboard + auto-intervention |
| **Team allocation** | 1.0 FTE per seed (launch), 0.3 FTE (sustain) | 0.3 FTE per seed (launch), 0.1 FTE (sustain) | 0.05 FTE per seed (sustain), 0 FTE (launch) |

### A.2. Capacity Model

**При команде 3 FTE operations + 1 FTE BD:**

*All figures in this table [H] unless tagged otherwise.*

| Режим | Seeds / квартал (launch) | Max seeds (sustain-only) | Max seeds (while launching 1/qtr) | Bottleneck |
|-------|--------------------------|-------------------------|----------------------------------|-----------|
| **Manual** | 1 seed / квартал | 10 | **4–5** | Launch absorbs 1.0 FTE → only 2 FTE left for sustain |
| **Semi-Auto** | 3–4 seeds / квартал | 30 | **15–20** | Launch = 0.3 FTE/seed × 4 = 1.2 FTE → 1.8 FTE sustain |
| **Self-Serve** | 8–12 seeds / квартал | 60+ | **50+** | Launch ≈ 0 FTE; sustain = 0.05 FTE/seed |

*"Max seeds while launching" — практический лимит: команда одновременно запускает новые seeds и поддерживает существующие. "Sustain-only" — теоретический max если не запускать новых.*

**Manual bottleneck decomposition:**

```
36-day launch cycle:
  Days 1–10:  BD / provider outreach        (1.0 BD FTE)
  Days 5–20:  Feed integration + QA         (0.5 Ops FTE)
  Days 10–30: Activation campaigns in-mall  (1.0 Ops FTE)
  Days 20–36: Monitoring + optimization     (0.3 Ops FTE)
  Overlap:    ~50% parallelizable
  
Launch absorbs: ~1.0 Ops FTE + 1.0 BD FTE for 36 days
Sustain: 0.3 FTE per live seed
Remaining for sustain while launching: 3 FTE Ops − 1.0 launch = 2.0 FTE → 2.0/0.3 ≈ 6 seeds
With BD also sustaining: practical limit = 4–5 seeds while launching
```

**Semi-Auto unlocks:**

| Процесс | Manual время | Semi-Auto время | Экономия | Как |
|---------|-------------|----------------|---------|-----|
| Provider outreach | 10 дней F2F | 5 дней (email + demo) | 50% | CRM templates, case studies, standardized pitch |
| Feed integration | 15 дней | 5 дней | 67% | Dashboard upload + auto-validation rules |
| Activation | 20 дней | 10 дней (playbook + agency) | 50% | Proven playbook, local agency execution |
| QA/monitoring | Daily manual | Weekly auto + alerts | 80% | Automated traffic-light dashboard |
| **Total launch cycle** | **36 дней** | **14–18 дней** | **50–60%** | |

### A.3. Триггеры переключения (metric-based, не calendar)

> **Принцип:** Переход между режимами определяется наблюдаемыми метриками, не датами. Каждый триггер — AND (все условия должны выполняться одновременно).

**Manual → Semi-Auto:**

| # | Триггер | Threshold | Обоснование | Тип |
|---|---------|-----------|-------------|-----|
| 1 | Replicable launch success | ≥ 3 seeds launched + surviving (Onsite MAU > 500) | Доказано: процесс воспроизводим | [H] |
| 2 | Feed self-serve rate | ≥ 40% providers upload via dashboard (no manual help) | Dashboard работает без hand-holding | [H] |
| 3 | Onboarding time ≤ 5 days | Median provider: от контакта до live feed ≤ 5 days | Процесс стандартизирован | [H] |
| 4 | Launch playbook NPS | ≥ 3 seeds executed by non-founding team | Playbook transferable | [H] |
| 5 | Data quality auto-check | ≥ 80% feeds pass validation without manual review | Tooling ready | [H] |

**Earliest possible:** ~M18–24 (after seeds 2–3 launched, tooling built).

**Semi-Auto → Self-Serve:**

| # | Триггер | Threshold | Обоснование | Тип |
|---|---------|-----------|-------------|-----|
| 1 | Provider inbound rate | ≥ 50% new providers apply inbound (not outbound BD) | Brand Pull mode active (§F) | [H] |
| 2 | Feed integration time | ≤ 48 hours from signup to live (automated) | API + auto-validation mature | [H] |
| 3 | Launch without field team | ≥ 3 seeds launched with 0 FTE on-site | Provider-driven activation works | [H] |
| 4 | Active seeds | ≥ 15 live seeds | Sufficient scale for platform economics | [H] |
| 5 | Support tickets per seed | ≤ 5 / month (down from 20+ in Manual) | Platform self-explanatory | [H] |

**Earliest possible:** ~M30–42 (requires Semi-Auto stability + brand recognition).

### A.4. Cost Structure по режимам

| Cost component | Manual | Semi-Auto | Self-Serve | Тип |
|---------------|--------|-----------|-----------|-----|
| **Launch cost / seed** | $12,000–16,000 | $3,000–5,000 | $500–1,000 | [H] |
| **Onboarding cost / provider** | $1,000 | $300–500 | $50–100 | [H] |
| **Monthly sustain / seed** | $2,000–3,000 | $800–1,200 | $200–400 | [H] |
| **Support load (tickets/seed/mo)** | 20–30 | 8–12 | 3–5 | [H] |

**Launch cost decomposition (Manual):**

| Компонент | Стоимость | Примечание |
|-----------|----------|-----------|
| BD travel + meetings | $2,000 | Dubai: local, minimal travel |
| Provider onboarding (15 local providers × $200 setup) | $3,000 | Per-provider-per-seed: setup, training, QA |
| Activation campaign (theater, QR, materials) | $3,000 | Step 1 бенчмарк |
| Field team allocation (36 days × $150/day) | $5,400 | 1.0 FTE pro-rata |
| Contingency | $600 | ~4% |
| **Total** | **$14,000** | |

**Onboarding cost taxonomy:**

| Тип | Cost | Scope | Amortization |
|-----|------|-------|-------------|
| **Local provider** (independent store) | $200–300 [H] | 1 seed | Direct: per seed |
| **Chain brand** (first integration) | $1,000–2,000 [H] | All seeds with that chain | Amortized: across N seeds where chain present |
| **Chain brand** (additional seed) | $50–100 [H] | 1 seed | Marginal: feed already structured, just location data |

*Chain integration (§F.2) fundamentally cheaper per-seed: one API setup → all locations. Local provider onboarding = per-seed cost, no amortization.*

**One-time tooling investment (enables Semi-Auto):**

| Tool | Cost | When needed |
|------|------|------------|
| Self-serve provider dashboard (MVP) | $15,000 [H] | Before seed #3 |
| Automated feed validation | $8,000 [H] | Before seed #3 |
| Traffic-light monitoring dashboard | $5,000 [H] | Before seed #2 |
| Launch playbook documentation | $2,000 [H] | After seed #1 |
| **Total** | **$30,000** | |

### A.5. Seed Ramp Curve

Как новый seed проходит стадии от запуска до Revenue-Ready, по режиму.

*All milestone figures below [H] — validated after first 2 seeds.*

**Manual launch (36-day protocol):**

| Week | Milestone | CP | PP | Onsite MAU | Coverage | Режим activity |
|------|-----------|----|----|-----|---------|---------------|
| W0–W2 | Pre-launch BD | 10 | 0 | 0 | 8% | Provider outreach, feed loading |
| W2–W4 | Soft launch | 25 | 1 | 200 | 21% | Activation begins, first users |
| W4–W6 | Active launch | 40 | 3 | 800 | 33% | Theater activations, QR campaigns |
| M2–M3 | Early traction | 50 | 5 | 1,500 | 42% | Optimization, provider training |
| M3–M6 | Growth | 55–65 | 8–12 | 3,000–4,000 | 46–54% | Stabilization, move to sustain mode |
| M6–M12 | Maturation | 75 | 15 | 5,000 | 63% | Block 3 M12 baseline |

**Semi-Auto launch (14–18 day protocol):**

| Week | Milestone | CP | PP | Onsite MAU | Coverage |
|------|-----------|----|----|-----|---------|
| W0–W1 | Remote BD + dashboard | 15 | 0 | 0 | 13% |
| W1–W3 | Parallel launch | 35 | 2 | 500 | 29% |
| M1–M2 | Traction | 50 | 5 | 2,000 | 42% |
| M3–M6 | Growth | 65 | 12 | 4,000 | 54% |
| M6–M12 | Maturation | 75 | 15 | 5,000 | 63% |

**Time to Block 3 M12 baseline (CP=75, PP=15, MAU≈5K):**

| Режим | Time to M12 baseline | Time to Revenue-Ready | Cost to Revenue-Ready |
|-------|---------------------|-------------------|-------------------|
| Manual | 12 months | ~M33 | $185–278K (Block 3) |
| Semi-Auto | 10 months [H] | ~M29 [H] | $140–200K [H] |
| Self-Serve | 8 months [H] | ~M26 [H] | $80–120K [H] |

*Semi-Auto/Self-Serve ускоряют seed maturation через: (a) faster provider onboarding, (b) cross-mall avatar portability (§C), (c) brand chain coverage already loaded. Estimates [H] — validated after 3+ seeds.*

---

## B. MULTI-SEED ECONOMICS

### B.1. Cost Taxonomy: Local vs Central

| Category | Type | Examples | Allocation rule |
|----------|------|---------|----------------|
| **Local Ops** | Per seed | Field launches, local BD, seed-level support | Direct to seed |
| **Local AI** | Per MAU | AI inference, recommendations per user | MAU-weighted |
| **Provider Onboarding** | Per provider | Integration, training, feed setup | Direct to seed (first); shared if chain (§F) |
| **Central: R&D** | Shared | Core product, ML models, platform features | Even split across active seeds |
| **Central: Infra** | Shared (scale) | Server, DB, CDN, monitoring | MAU-weighted |
| **Central: Team** | Shared | Leadership, strategy, analytics, enterprise BD | Even split across active seeds |
| **Central: Tooling** | One-time | Dashboards, playbooks, automation | Amortized over all seeds lifetime |

### B.2. Cost Model: 1 seed vs 5 seeds vs 15 seeds

**Assumptions:**
- Все seeds в Dubai, same team
- Режим: Manual (1 seed), Semi-Auto (5 seeds), Self-Serve (15 seeds)
- Все seeds at M12 maturity (для сравнимости)
- Central team: 3 FTE Ops ($4K/FTE/mo Dubai), 1 FTE BD ($5K/mo), 1 FTE Tech ($6K/mo) = $23K/mo fixed

**AI cost scaling [H]:**

```
AI_cost_per_MAU(t, N_seeds) = Base_AI_cost × (1 − Scale_Discount(N_seeds)) × Optimization(t)

Base_AI_cost       = $0.82 / MAU / mo   [H]
Scale_Discount     = {1 seed: 0%, 5 seeds: 8%, 15 seeds: 20%}  [H]
                     Shared model caching, batch inference across seeds
Optimization(t)    = see calibration table below  [H]
                     Per-seed: cheaper models for simple queries, caching popular recs
```

**Optimization(t) calibration:** lookup table, калибровано по Block 3 §G.1:

| t | Optimization | 1 seed AI/MAU | Check vs Block 3 |
|---|-------------|--------------|------------------|
| M1 | 1.00 | $0.82 | — (pre-launch) |
| M6 | 0.85 | $0.70 | ✓ Block 3: $0.70 |
| M12 | 0.85 | $0.70 | — (plateau) |
| M18 | 0.79 | $0.65 | ✓ Block 3: $0.65 |
| M24 | 0.67 | $0.55 | ✓ Block 3: $0.55 |
| M30 | 0.61 | $0.50 | ✓ Block 3: $0.50 |
| M36 | 0.55 | $0.45 | ✓ Block 3: $0.45 |

| Cost component | 1 seed (Manual) | 5 seeds (Semi-Auto) | 15 seeds (Self-Serve) |
|---------------|-----------------|--------------------|--------------------|
| **Local Ops per seed** | $2,500/mo | $1,000/mo | $300/mo |
| **Local AI per seed** | $3,500/mo | $3,200/mo | $2,785/mo |
| **Local Other per seed** | $800/mo | $500/mo | $200/mo |
| **Subtotal Local / seed** | **$6,800/mo** | **$4,700/mo** | **$3,285/mo** |
| | | | |
| **Central Team** | $23,000/mo | $23,000/mo | $30,000/mo |
| **Central Infra** | $500/mo | $1,500/mo | $3,000/mo |
| **Central / seed** | **$23,500/mo** | **$4,900/mo** | **$2,200/mo** |
| | | | |
| **Total Opex / seed** | **$30,300/mo** | **$9,600/mo** | **$5,485/mo** |

**Central team at 15 seeds:** +$7K/mo (дополнительный Ops FTE для scale).

### B.3. Contribution Margin per Seed

> **Примечание:** "Rev capacity" = если Phase 2 active. "Actual Rev" учитывает Phase gating: $0 (Phase 1 Strict) или 30% capacity (WTP pilot). Все seeds ниже показаны at same maturity для сравнения cost structures, не реальной timeline.

**At M12 maturity:**

| Metric | 1 seed | 5 seeds | 15 seeds |
|--------|--------|---------|----------|
| Rev capacity (Phase 2 rates) | $3,150 | $3,150 | $3,150 |
| Actual Rev: Scenario S (Phase 1) | $0 | $0 | $0 |
| Actual Rev: Scenario P (WTP 30%) | $945 | $945 | $945 |
| Local Opex / seed | $6,800 | $4,700 | $3,285 |
| **Margin (Capacity)** | **−$3,650** | **−$1,550** | **−$135** |
| **Margin (Actual, Scenario P)** | **−$5,855** | **−$3,755** | **−$2,340** |
| Central / seed | $23,500 | $4,900 | $2,200 |
| **Fully-loaded (Capacity)** | **−$27,150** | **−$6,450** | **−$2,335** |
| **Fully-loaded (Actual P)** | **−$29,355** | **−$8,655** | **−$4,540** |

**At M24 maturity:**

| Metric | 1 seed | 5 seeds | 15 seeds |
|--------|--------|---------|----------|
| Rev capacity (Phase 2 rates) | $20,580 | $20,580 | $20,580 |
| Actual Rev: Scenario P (WTP 30%) | $6,174 | $6,174 | $6,174 |
| Local Opex / seed | $8,815 | $6,200 | $4,500 |
| **Margin (Capacity)** | **+$11,765** | **+$14,380** | **+$16,080** |
| **Margin (Actual P)** | **−$2,641** | **−$26** | **+$1,674** |
| Central / seed | $23,500 | $4,900 | $2,200 |
| **Fully-loaded (Capacity)** | **−$11,735** | **+$9,480** | **+$13,880** |
| **Fully-loaded (Actual P)** | **−$26,141** | **−$4,926** | **−$526** |

**Breakeven (fully-loaded, Phase 2 revenue):**
- 1 seed: never breaks even (central costs > single seed capacity)
- 5 seeds: breaks even when average seed reaches ~M20 maturity [D]
- 15 seeds: breaks even when average seed reaches ~M14 maturity [D]

### B.4. Network P&L Snapshot (Year 3, 15 seeds scenario)

**Assumptions:** 15 seeds, average maturity M18, Semi-Auto/Self-Serve mix. Phase status: 6 seeds in Phase 2 (Revenue-Ready), 4 seeds WTP pilot, 5 seeds Phase 1 Strict.

| Line | Calculation | Total / month |
|------|------------|--------------|
| **Revenue** | | |
| → 6 Phase 2 seeds × $12K avg capacity | 6 × $12,000 | $72,000 |
| → 4 WTP pilot seeds × $2K avg (30% of ~$7K) | 4 × $2,000 | $8,000 |
| → 5 Phase 1 seeds × $0 | 5 × $0 | $0 |
| **Total Actual Revenue** | | **$80,000** |
| | | |
| **Opex** | | |
| Local Opex (15 seeds × $4,200 avg) | | $63,000 |
| Central Team | | $30,000 |
| Central Infra | | $3,000 |
| **Total Opex** | | **$96,000** |
| | | |
| **Network Margin** | | **−$16,000** |

**Network breakeven:** When ~8 seeds reach Phase 2 (of 15). At average M24 maturity across Phase 2 seeds.

**Year 4 projection (15 seeds: 12 Phase 2, 3 WTP pilot):**

| Line | Calculation | Total / month |
|------|------------|--------------|
| Revenue: 12 Phase 2 × $25K capacity | | $300,000 |
| Revenue: 3 WTP × $4K | | $12,000 |
| **Total Actual Revenue** | | **$312,000** |
| Total Opex | | $108,000 |
| **Network Margin** | | **+$204,000** |

---

## C. CROSS-MALL EFFECT: AVATAR PORTABILITY

### C.1. Механика

Пользователь с аватаром из Seed A посещает молл Seed B. Avatar portable: все стилевые предпочтения, размеры, история рекомендаций переносятся.

**Эффект на Seed B:**
- Activation: пользователь не проходит cold start, AI знает предпочтения → сразу релевантные рекомендации
- Retention: выше, т.к. ценность ощущается с первого визита
- Attribution: портированный пользователь = N_earned (не N_organic), улучшает OIR

### C.2. Параметры модели

| Параметр | Определение | Значение | Тип |
|----------|------------|---------|-----|
| **Transfer_Physical(A↔B)** | % MAU Seed A, которые физически оказываются в молле Seed B за месяц | Per-pair, see table below | [H] |
| **Onsite_Use_Rate_cold** | % посетителей молла, которые делают Onsite Active Visit (без аватара) | 40% [H] | = Activate_Conv из Block 1 |
| **Activation_Uplift_B** | Множитель Onsite_Use_Rate для портированных (аватар уже есть) | 1.4–1.6× [H] | Нет cold start → выше мотивация |
| **Onsite_Use_Rate_ported** | = Onsite_Use_Rate_cold × Activation_Uplift_B | 56–64% [D] | Производная |
| **Retention_Uplift_B** | Прирост D30 retention для портированных | +30–50% [H] | Cold D30: 15%. Ported: 20–23% |
| **Cross_OIR_credit** | Портированные считаются в N_earned Seed B (не N_organic) | Yes | Они пришли через UNDE, не через footfall |

**Transfer_Physical per pair [H]:**

Dubai mall overlap: средний покупатель посещает 2.3 молла/мес [H, industry surveys]. Proximity определяет вероятность пересечения конкретных пар.

| Seed A | Seed B | Drive time | Transfer_Physical | Rationale |
|--------|--------|-----------|------------------|-----------|
| Ibn Battuta | Mall of Emirates | 15 min | **12%** | Same corridor (JBR/Marina/Al Barsha), high overlap |
| Ibn Battuta | Dubai Mall | 30 min | **5%** | Different catchment, tourist-heavy DM |
| Ibn Battuta | Dubai Marina Mall | 10 min | **14%** | Adjacent neighborhoods |
| Mall of Emirates | Dubai Mall | 20 min | **8%** | Moderate overlap, both destination malls |
| Mall of Emirates | Dubai Marina Mall | 12 min | **11%** | Close proximity |
| Dubai Mall | City Centre Mirdif | 25 min | **4%** | Opposite sides of city |
| **Average across all pairs** | | | **~8%** | Weighted by seed launch order |

*Proximity rule of thumb: <15 min = 10–14%, 15–20 min = 8–12%, 20–30 min = 4–8%, >30 min = 2–4%. Validated against Dubai shopping behaviour data [V, TBD].*

### C.3. Impact на Seed B: Mall of Emirates (при Seed A = Ibn Battuta, 5,000 MAU)

```
Transfer_Physical(IBN→MOE) = 12%   [H, per-pair table]

Ported_Activated_MOE = MAU_IBN × Transfer_Physical × Onsite_Use_Rate_ported
                    = 5,000 × 12% × (40% × 1.5)
                    = 5,000 × 12% × 60%
                    = 360 / мес [D]
```

*Сравнение: если бы те же люди пришли как cold users: 5,000 × 12% × 40% = 240. Uplift = +120 (+50%).*

**Для Dubai Mall (Seed #3, Transfer от IBN = 5%):**

```
Ported_Activated_DM = 5,000 × 5% × 60% = 150 / мес [D]
                    + from MOE (5,000 × 8% × 60%) = 240
                    = 390 total ported [D]
```

| Metric | Seed B (standalone) | Seed B (with portability from A) | Delta |
|--------|-------------------|--------------------------------|-------|
| N_organic | 2,940 | 2,940 | 0 |
| N_ported | 0 | 360 | +360 (counted as N_earned) |
| N_provider | 1,200 | 1,200 | 0 |
| N_viral | 91 | 99 (+9% from ported viral) | +8 |
| **N_total** | **4,231** | **4,599** | **+368** |
| Onsite MAU (at r=15%) | 5,000 | 5,430 | **+430 (+9%)** |
| OIR | 0.44 | 0.56 | **+0.12 (+27%)** |

**Ported users' D30 retention:** 20–23% vs 15% for cold users [H]. Higher signal density from Day 1 → faster trust flywheel.

### C.4. Network Effect Amplification

При N seeds, per-pair Transfer_Physical varies:

```
Cross_Mall_Boost(Seed_i) = Σ (MAU_j × Transfer_Physical(j→i) × Onsite_Use_Rate_ported)
                           for all j ≠ i
```

| Seeds in Dubai | Pairs | Avg Transfer [D] | Ported activated / seed [D] | Onsite MAU uplift / seed | OIR uplift |
|---------------|-------|------------------|---------------------------|------------------|-----------|
| 1 (IBN) | 0 | — | 0 | 0% | 0 |
| 2 (IBN+MOE) | 1 | 12% | 360 | +7% | +0.12 |
| 3 (+Dubai Mall) | 3 | 8% avg | 500–600 | +10–12% | +0.17–0.20 |
| 5 (+Marina+Hills) | 10 | 7% avg | 700–900 | +14–18% | +0.24–0.31 |
| 8 (all major) | 28 | 6% avg | 900–1,200 | +18–24% | +0.31–0.41 |

*Average Transfer снижается с каждым новым seed: distant pairs (4–5%) разбавляют proximate pairs (12–14%). Ported/seed растёт за счёт числа пар, но с diminishing returns.*

**Pessimistic cross-mall scenario:** All Transfer_Physical = 5% max (пользователи не переносят привычку между моллами), Activation_Uplift = 1.2× (минимальный). Ported = 5,000 × 5% × (40% × 1.2) = 120/мес от одного seed.

| Seeds | Ported (pessimistic) | Onsite MAU uplift | OIR uplift | Impact on Revenue-Ready timing |
|-------|---------------------|-----------|-----------|---------------------------|
| 3 | 170–240 | +3–5% | +0.06–0.08 | Delay vs base: +0 мес (negligible) |
| 5 | 340–480 | +7–10% | +0.12–0.16 | Delay vs base: +3–4 мес |
| 8 | 600–840 | +12–17% | +0.20–0.29 | Delay vs base: +6–9 мес |

**В pessimistic сценарии cross-mall effect ≈ nice-to-have, не game-changer.** Revenue-Ready timing определяется retention и provider growth, не cross-mall traffic.

### C.5. Revised Time to Local Seed (with cross-mall)

| Scenario | Time to Revenue-Ready (base) | Time (pessimistic cross) | Investment (base) |
|----------|--------------------------|-------------------------|-------------------|
| Standalone seed (Block 3) | ~M33 | ~M33 | $185–278K |
| Seed #3 (2 prior seeds active) | ~M30 [H] | ~M32 [H] | $150–220K [H] |
| Seed #5 (4 prior seeds active) | ~M27 [H] | ~M30 [H] | $120–170K [H] |
| Seed #8 (7 prior seeds active) | ~M23 [H] | ~M29 [H] | $90–140K [H] |

*Acceleration drivers: cross-mall OIR boost + chain provider coverage (§F) + faster onboarding (Semi-Auto). Pessimistic: cross-mall minimal, but Semi-Auto + chain coverage still accelerate by 1–4 months.*

---

## D. OIR: PER SEED VS AGGREGATE

### D.1. Правило

> **Primary:** OIR считается per seed. Все пороги (Local Seed, Phase transitions) применяются per seed.
>
> **Reporting:** Aggregate OIR показывается для VC/board, но с обязательной декомпозицией.

**Обоснование:** Aggregate OIR может маскировать слабые seeds. Один seed с OIR 3.0 и четыре с OIR 0.3 дают aggregate ~0.9 — выглядит нормально, но 4 из 5 seeds нежизнеспособны.

### D.2. Aggregate OIR Formula

```
Aggregate_OIR = Σ(N_earned_i) / Σ(N_organic_i)   [MAU-weighted by construction]
```

Эквивалентно:

```
Aggregate_OIR = Σ(OIR_i × N_organic_i) / Σ(N_organic_i)
```

### D.3. Reporting Template

| Metric | Seed 1 | Seed 2 | Seed 3 | ... | **Aggregate** |
|--------|--------|--------|--------|-----|-----------|
| OIR | 1.44 | 0.71 | 0.33 | ... | 0.89 |
| Onsite MAU | 11,589 | 6,438 | 3,530 | ... | 21,557 |
| Phase | 2 | 1 (WTP) | 1 | ... | — |
| Revenue | $29,880 | $2,063 | $0 | ... | $31,943 |

**Aggregate OIR dashboard rules:**
- Always show: min / median / max OIR across seeds
- Flag: any seed with OIR < 0.3 after M12 → intervention needed
- Board deck: aggregate + distribution chart (histogram)

---

## E. SEED LIFECYCLE & PHASE TRANSITIONS

### E.0. Local Seed: два уровня

> **Проблема:** "Local Seed" используется и как "сеть работает" (OIR > 1.0, providers active), и как "можно включать Phase 2 revenue" (D30 > 40%). Это разные моменты, разделённые ~9 месяцами.

| Термин | Пороги | Когда (base) | Что разрешает |
|--------|--------|-------------|--------------|
| **Local Seed (Network-Complete)** | Onsite MAU > 500, PP > 10, OIR > 1.0, Coverage > 50% | ~M24 | Сеть самодостаточна по acquisition. WTP pilots допускаются |
| **Local Seed (Revenue-Ready)** | Все вышеперечисленное + D30 > 40% | ~M33 | Phase 2: полная Credits Economy |

*Network-Complete ≠ Revenue-Ready. Разрыв = retention gap. Конституция v1.3 должна формализовать оба уровня.*

### E.1. Unified Seed Lifecycle

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────────────┐
│  Launch   │───→│  Early   │───→│  Growth  │───→│ Network-     │───→│ Revenue-     │
│  (W0–W6)  │    │ (M2–M6)  │    │ (M6–M24) │    │ Complete     │    │ Ready        │
│           │    │          │    │          │    │ (M24–M33)    │    │ (M33+)       │
└──────────┘    └──────────┘    └──────────┘    └──────────────┘    └──────────────┘
      │               │               │               │                    │
   MAU=0          MAU>500         OIR growing      OIR>1.0             D30>40%
   CP=0           CP>25          PP>10             D30 growing         Phase 2 active
                  PP=0–3         Coverage>50%      WTP pilots OK

*(MAU = Onsite MAU throughout)*
```

### E.2. Phase Transition Triggers (per seed)

| From → To | Trigger | Automatic? | Revenue impact |
|-----------|---------|-----------|----------------|
| Launch → Early | Onsite MAU > 500 + CP > 25 | Yes | $0 |
| Early → Growth | PP > 10 + Coverage > 50% | Yes | $0 |
| Growth → Network-Complete | OIR > 1.0 + Onsite MAU > 500 + PP > 10 + Coverage > 50% | Yes | WTP pilots allowed (30% capacity) |
| Network-Complete → Revenue-Ready | D30 > 40% (all thresholds met) | Yes | **Phase 2: full Credits Economy** |

### E.3. Per-seed Monitoring (Traffic Light)

| Zone | Condition | Action |
|------|-----------|--------|
| 🟢 Green | All metrics on or above Block 3 trajectory | Continue, optimize |
| 🟡 Yellow | 1–2 metrics > 20% below trajectory | Diagnosis: what's lagging? Targeted intervention |
| 🔴 Red | Onsite MAU declining OR retention < 10% at M6+ OR OIR flat at < 0.2 after M12 | Escalate: team review, consider pause/close |

**Kill threshold:** If seed is 🔴 for 3 consecutive months after M9 → close seed, reallocate resources. Sunk cost: $30–50K (Manual) or $15–25K (Semi-Auto). Better to kill early than drain to $200K+.

**Post-kill reallocation:** Released FTE (0.3 sustain) + freed budget → reinvest into strongest 🟢 seeds (boost activation, extend coverage) or accelerate next seed launch. Portfolio discipline: 5 mediocre seeds < 3 strong seeds. Max 2 concurrent 🔴 seeds before forced portfolio review.

---

## F. BRAND PULL MODE

### F.1. Определение

Brand Pull = состояние, когда Providers (включая chain brands) приходят к UNDE сами, а не через outbound BD.

**Наблюдаемые метрики:**

| Метрика | Pre-Pull | Pull Active | Тип |
|---------|----------|------------|-----|
| Inbound provider inquiries / mo | 0–2 | 5+ per seed | [H] |
| Inbound share of new providers | < 20% | > 50% | [H] |
| Time: inquiry → live feed | 10+ days | ≤ 48 hours | [H] |
| Chain brands requesting multi-mall | 0 | 1+ per quarter | [H] |

### F.2. Chain Brand Effect

Одна интеграция с chain brand (e.g., Zara/H&M → 4–6 locations in Dubai malls) → coverage uplift across multiple seeds одновременно.

```
Chain_Coverage_Boost(seed_i) = Brand_SKU / Total_mall_SKU(seed_i)  ×  Chain_Present(brand, seed_i)
Chain_Present(brand, seed_i) = {1 if brand has location in mall_i, 0 otherwise}
```

**Ограничение:** boost only applies to seeds where the chain has a physical location. Chain integration ≠ coverage in all seeds.

| Brand example | Dubai locations [H] | Seeds with presence (of 8) | Coverage boost per present seed |
|--------------|-------------------|--------------------------|-------------------------------|
| Zara | 5 | 5 of 8 (63%) | +8–12% |
| H&M | 4 | 4 of 8 (50%) | +10–15% |
| Nike | 6 | 6 of 8 (75%) | +5–8% |
| **One chain (avg)** | **5** | **5 of 8 (63%)** | **+8–12% in those 5 seeds only** |

**Impact cascade:**

```
Chain integration → Coverage ↑ in 5 seeds simultaneously
                  → Rec quality ↑ (more SKUs matched)
                  → Retention ↑ (better experience)
                  → OIR ↑ (more users return)
                  → More providers see value → more inbound
```

### F.3. When Does Pull Activate?

| Condition | Threshold [H] | Why |
|-----------|--------------|-----|
| Total UNDE Onsite MAU (all seeds) | > 15,000 | Enough traffic to be visible to brands |
| Seeds with Phase 2 revenue | ≥ 2 | Proof that Credits Economy works |
| Provider case studies published | ≥ 3 | Social proof for new brands |
| Industry press / conference mention | ≥ 1 | Awareness among brand decision-makers |

**Estimated timing:** M24–M30 (after 3–5 seeds live, first Phase 2 revenue visible).

### F.4. Brand Pull = Semi-Auto Trigger

Brand Pull активирует триггер Semi-Auto → Self-Serve transition. Когда chains request multi-mall и >50% providers inbound, manual BD больше не нужен. Self-serve dashboard + API становятся основным каналом подключения.

---

## G. DUBAI EXPANSION SEQUENCE

### G.1. Mall Selection Framework

| Критерий | Вес | Источник |
|---------|-----|---------|
| Fashion footfall / month (FF) | 25% | Mall annual reports, industry data [V] |
| Fashion store count (FS) | 20% | Mall directory [V] |
| Proximity to existing seeds (PX) | 20% | Geography [D] |
| Anchor brand overlap (AO) | 15% | Cross-reference with integrated brands [D] |
| Demographic fit (DF) | 10% | Dubai Statistics Center [V] |
| Mall management cooperation (MC) | 10% | Relationship [H] |

**Score formula:**

```
Score = FF_norm × 0.25 + FS_norm × 0.20 + PX_norm × 0.20 + AO_norm × 0.15 + DF_norm × 0.10 + MC_norm × 0.10
Normalized: each factor 0–100, based on best-in-set = 100.
```

### G.2. Dubai Malls Ranked

**Normalization basis:** FF: 1,200K = 100. FS: 250 = 100. PX: 10 min = 100 (closer = better). AO: 90% overlap = 100. DF: best fit = 100. MC: best relationship = 100.

> **⚠️ Все числа ниже = [H, pending V].** FF и FS — оценки на основе открытых источников, не verified data. Score используется для приоритизации, не как факт. Перед investor deck заменить на [V] из §J Evidence Placeholders.

| Mall | FF [H] | FF_n | FS [H] | FS_n | PX (min) | PX_n | AO% [H] | AO_n | DF_n [H] | MC_n [H] | **Score** |
|------|-----|------|-----|------|----------|------|-----|------|------|------|---------|
| Mall of the Emirates | 750K | 63 | 180 | 72 | 15 | 87 | 50% | 56 | 90 | 80 | **73** |
| Dubai Mall | 1,200K | 100 | 250 | 100 | 30 | 67 | 70% | 78 | 70 | 60 | **81** |
| City Centre Mirdif | 400K | 33 | 100 | 40 | 35 | 57 | 40% | 44 | 80 | 70 | **49** |
| Dubai Marina Mall | 300K | 25 | 80 | 32 | 10 | 100 | 35% | 39 | 95 | 75 | **55** |
| Dubai Hills Mall | 350K | 29 | 90 | 36 | 25 | 73 | 45% | 50 | 85 | 65 | **52** |

**Ranking by Score:** 1. Dubai Mall (81) → 2. Mall of the Emirates (73) → 3. Dubai Marina (55) → 4. Dubai Hills (52) → 5. Mirdif (49).

**Но: Seed #2 = Mall of the Emirates (не Dubai Mall) — strategic override:**
- Proximity to IBN (15 min) максимизирует cross-mall effect в критический ранний период
- Lower complexity: 180 stores vs 250 (easier to launch)
- Same demographic corridor (JBR/Marina/Al Barsha)
- Dubai Mall = Seed #3 после доказательства процесса на MOE

**Seed #3 = Dubai Mall:**
- Largest mall globally, highest footfall
- Maximum chain brand overlap (all major brands present)
- Tourist-heavy → lower retention but higher awareness
- Strategic: "if UNDE works in Dubai Mall, every brand wants in"

### G.3. Expansion Timeline (Base Case)

| Quarter | Action | Seeds live | Режим |
|---------|--------|-----------|-------|
| Q1–Q3 (M1–M9) | Seed #1: Ibn Battuta | 1 | Manual |
| Q4 (M10–M12) | Seed #2: Mall of Emirates launch | 2 | Manual |
| Q5–Q6 (M13–M18) | Seed #3: Dubai Mall launch. Tooling investment for Semi-Auto | 3 | Manual → Semi-Auto |
| Q7–Q8 (M19–M24) | Seeds #4–#5: Mirdif + Marina. Semi-Auto mode | 5 | Semi-Auto |
| Q9–Q12 (M25–M36) | Seeds #6–#8. Brand Pull emerging. First Phase 2 revenues | 8 | Semi-Auto → Self-Serve transition |

### G.4. Dubai → Second Market: Триггеры и Framework

> **Принцип:** Второй рынок после доказательства replicability + scalability в Dubai. Не по календарю.

**Триггеры выхода на Market 2:**

| # | Trigger | Threshold | Тип |
|---|---------|-----------|-----|
| 1 | Dubai seeds in Semi-Auto | ≥ 5 seeds + ≥ 2 in Phase 2 | [H] |
| 2 | Network margin positive | > $0 / mo (all seeds combined) | [H] |
| 3 | Chain brand requesting new market | ≥ 1 brand says "we want UNDE in [city]" | [H] |
| 4 | Playbook transferable | Launch executed by non-Dubai team | [H] |

**Market 2 Selection Criteria:**

| Критерий | Вес | Rationale |
|---------|-----|-----------|
| Mall density (malls per capita) | 25% | More malls = more seeds = faster network |
| Fashion retail spend / capita | 20% | Willingness to pay = Credits demand |
| Smartphone + app penetration | 15% | User adoption feasibility |
| English / Arabic language fit | 10% | Localization cost |
| Regulatory simplicity | 10% | Speed to launch |
| Existing chain brand overlap with Dubai | 15% | Cross-market portability |
| Time zone proximity to HQ | 5% | Ops coordination |

**Shortlist [H]:**

| Market | Mall density | Fashion spend | Chain overlap | Score |
|--------|-------------|--------------|--------------|-------|
| Riyadh | Very high | Very high | 80%+ | **91** |
| Abu Dhabi | High | High | 90%+ | **85** |
| Doha | Medium | Very high | 75% | **78** |
| Kuwait City | Medium | High | 70% | **73** |
| Istanbul | Very high | Medium | 60% | **68** |

*GCC markets preferred: similar demo, same chains, Arabic/English, regulatory simplicity. Istanbul = high density but localization + regulatory overhead.*

---

## H. STRUCTURAL FINDINGS

### H.1. Manual mode is a necessary bottleneck

Linear growth (1 seed/quarter) is a feature, not a bug, in Phase 1. It ensures quality, builds playbook, prevents over-extension. Attempting Semi-Auto before 3 successful seeds = premature optimization.

### H.2. Central cost allocation is the "venture effect"

Single seed never covers central costs ($23K/mo). At 5 seeds, central cost per seed drops to $4.9K → breakeven possible at M20 maturity. At 15 seeds → $2.2K → breakeven at M14. This is the core scaling argument for investors.

### H.3. Cross-mall = compounding advantage (but not silver bullet)

Each new seed makes all existing seeds more valuable (MAU uplift, OIR boost) and makes itself cheaper to achieve Revenue-Ready. In base case (per-pair Transfer 4–14%), 5 seeds → +14–18% MAU uplift per seed, ~3–6 month acceleration to Revenue-Ready. In pessimistic case (Transfer = 5% flat), effect is minimal — retention and provider growth remain primary drivers.

### H.4. Brand Pull mode = inflection point

When providers come inbound, the entire cost structure shifts: BD cost → 0, onboarding cost drops 90%, launch cost drops 75%. This is the trigger for Self-Serve and exponential seed growth.

### H.5. OIR per seed prevents "aggregate fiction"

Measuring OIR aggregate without per-seed decomposition allows masking weak seeds behind strong ones. Per-seed OIR as primary metric + aggregate as secondary preserves operational rigor.

### H.6. Phase alignment constrains network economics

With Phase 1 = $0 revenue, the network runs at loss until seeds individually reach Revenue-Ready (~M33 standalone, ~M23–30 with cross-mall). WTP pilots reduce but don't eliminate the gap. Total investment to network breakeven: $500K–800K over 24–36 months [H], depending on seed velocity and retention trajectory.

**ROI framing:** Pre-revenue investment per seed = $185–278K (Scenario S/P). After Phase 2 trigger, margin = ~$30K/mo per mature seed. Payback on single seed investment: 6–9 months of Phase 2 revenue. Network investment ($500–800K) → payback 4–8 months after network breakeven (Year 4 margin ~$200K/mo).

**Enterprise Bridge scenario:** Контракт с девелопером (e.g., Majid Al Futtaim: 29 моллов в GCC) может покрыть запуск 3–5 seeds: фиксированная плата за пилот ($50–100K) + commitment на feed integration по всем моллам. Это сокращает pre-revenue gap на $150–250K и ускоряет Semi-Auto transition (chain feeds = instant coverage). Не моделируется как baseline (зависит от одной сделки), но как upside scenario для investor pitch.

### H.7. Central cost sensitivity

Central team cost ($23K/mo baseline) — наибольший risk при медленном seed launch:

| N active seeds | Central / seed | Break-even maturity (Phase 2) | Risk |
|---------------|---------------|------------------------------|------|
| 1 | $23,500 | Never | **Fatal** |
| 2 | $11,750 | ~M28 | High: if any seed fails, back to 1 |
| 3 | $7,833 | ~M24 | Medium |
| 5 | $4,900 | ~M20 | Manageable |

**Stress test: Central = $50K/mo** (senior hires, expanded platform team):

| N seeds | Central / seed | Break-even maturity | vs $23K baseline |
|---------|---------------|--------------------|--------------------|
| 2 | $25,000 | Never | −$13K/seed worse |
| 5 | $10,000 | ~M26 | −$5K/seed worse |
| 10 | $5,000 | ~M20 | −$100/seed (negligible) |
| 15 | $3,333 | ~M16 | −$1.1K/seed |

**Вывод:** $50K central допустим только при ≥5 seeds. При 2 seeds + $50K central = $25K/seed overhead → network не breakeven even с Phase 2 revenue. Hiring ahead of seed count = highest-ROI risk in expansion.

---

## I. SUMMARY FORMULAS

```
# Capacity
Seeds_per_quarter(mode)  = {Manual: 1, Semi-Auto: 3-4, Self-Serve: 8-12}
Max_while_launching(mode)= {Manual: 4-5, Semi-Auto: 15-20, Self-Serve: 50+}
Max_sustain_only(mode)   = {Manual: 10, Semi-Auto: 30, Self-Serve: 60+}

# Cost structure
Opex_seed(t) = Local_Ops(mode) + AI_cost(MAU, N_seeds, t) + Local_Other(mode) + Central_alloc(N_seeds)
Central_alloc = Central_Total / N_active_seeds
AI_cost_per_MAU(t, N) = 0.82 × (1 - Scale_Discount(N)) × Optimization(t)  [H]
  Scale_Discount  = {1: 0%, 5: 8%, 15: 20%}
  Optimization(t) = lookup table: M1=1.0, M6=0.85, M18=0.79, M24=0.67, M30=0.61, M36=0.55

# Cross-mall (per-pair Transfer)
Ported_Activated(A→B) = MAU_A × Transfer_Physical(A,B) × Onsite_Use_Rate_ported
Onsite_Use_Rate_ported = Onsite_Use_Rate_cold × Activation_Uplift_B   [H]
Transfer_Physical(A,B) = per-pair [H]: <15min: 10-14%, 15-20min: 8-12%, 20-30min: 4-8%, >30min: 2-4%
Cross_MAU_boost(B)     = Σ Ported_Activated(j→B)   for all j ≠ B
OIR_boost(B)           = Cross_MAU_boost(B) / N_organic_B   [ported = earned]

# Chain brand effect
Chain_Coverage_Boost(seed_i) = Brand_SKU / Mall_SKU(i) × Chain_Present(brand, seed_i)
Chain_Present(brand, seed_i) = {0, 1}   [brand has location in mall_i]

# Network economics
Network_Revenue    = Σ Actual_Revenue(seed_i)           [Phase-gated per seed]
Network_Opex       = Σ Local_Opex(seed_i) + Central_Total
Network_Margin     = Network_Revenue - Network_Opex

# OIR
OIR_per_seed(i)    = N_earned(i) / N_organic(i)         [PRIMARY]
OIR_aggregate      = Σ N_earned(i) / Σ N_organic(i)     [REPORTING ONLY]

# Phase transitions per seed (two-level Local Seed)
Network_Complete   = ALL(Onsite_MAU>500, PP>10, OIR>1.0, Coverage>50%)  → WTP pilots OK
Revenue_Ready      = Network_Complete AND D30>40%                       → Phase 2 full revenue
Kill_threshold     = Red_zone 3 consecutive months after M9 → close + reinvest
```

---

## J. EVIDENCE PLACEHOLDERS

Источники, помеченные [V] (Verified), требуют конкретных ссылок. Ниже — placeholder'ы для заполнения перед investor deck.

| Reference | Used in | Status | Placeholder source |
|-----------|---------|--------|-------------------|
| Mall annual footfall reports | G.1 (FF/mo) | **TBD** | Dubai: Majid Al Futtaim annual reports, Emaar annual reports, mall management press releases |
| Fashion store counts | G.1 (FS) | **TBD** | Mall directories (ibm.ae, malloftheemirates.com, thedubaimall.com) |
| Dubai Statistics Center (demographics) | G.1 (DF) | **TBD** | dsc.gov.ae — Population by age/gender/nationality |
| Dubai mall visitor surveys | C.2 (Transfer_Physical) | **TBD** | JLL/CBRE Dubai retail reports, "Dubai Mall Visitor Behaviour" surveys |
| Dubai shopping behaviour (cross-mall frequency) | C.2 (per-pair Transfer table) | **TBD** | Mall loyalty program data, Majid Al Futtaim customer analytics, KPMG GCC consumer survey |
| GCC fashion retail spend | G.4 (Market 2) | **TBD** | Euromonitor, Statista — Fashion retail per capita GCC |
| Smartphone penetration | G.4 (Market 2) | **TBD** | GSMA Intelligence, Statista — UAE/KSA/Qatar mobile data |

*Каждый [V] placeholder должен быть заменён на конкретный URL или document title перед использованием в investor materials.*

---

*Inputs: Block 1 Steps 1–2, Block 3 v1.0 | Протокол: UNDE_Model_Constitution_v1.2*
