# UNDE Block 8 — Milestone Map & Decision Framework
## Хронологическая карта решений, go/no-go gates, kill criteria
### v1.1

---

## 0. Назначение

Единый операционный документ: **когда** принимаются решения, **на основании чего**, и **что делать** при отклонениях. Связывает все блоки (1–7) в хронологическую карту от M0 (pre-launch) до M48 (network maturity).

**Изменения v1.1 vs v1.0:**
- §B.0b: Терминология CP/AP/PP_elig/PP_paying
- §B.1 Gate 1: D7 Source fix (was r(M6)=12% D30 proxy, now Product benchmark [H]). Gate 1 CP → AP. Seasonal adjustment note
- §B.2 Gate 2: PP → PP_elig, added AP/CP ratio metric
- §B.5 Gate 5: WTP pilot remark (non-baseline)
- §C.2 K2: CP → AP in signals
- §D.1–D.3: [H] tags on all use-of-funds amounts. ROI reference in D.1
- §E.1: AP/CP ratio added to dashboard
- §F.4: Tactical A/B responses при Yellow (new section)
- §J: Evidence placeholders with verification paths (new section)

**Для кого:**
- **Founders:** операционный чеклист — что должно произойти каждый месяц/квартал
- **Investors:** прозрачная система gates — инвестиции разблокируются при достижении метрик, не по календарю
- **Team:** dashboard — какие метрики отслеживать, где green/yellow/red

**Зависимости:**
- Constitution v1.2 (Phases, thresholds)
- Block 3 v1.0 (milestones, OIR trajectory)
- Block 4 v1.1 (expansion triggers, mode transitions)
- Block 6 v1.1 (single-seed P&L, sensitivities)
- Block 7 v1.1 (multi-seed cash flow, runway, fundraising)

**Принцип:** Все gates привязаны к метрикам, не к датам. Даты — ориентиры (Block 3 trajectory), не триггеры (Constitution §4.1).

---

## A. MASTER TIMELINE (VISUAL)

```
M0          M6          M12         M18         M24         M30         M36         M42         M48
│           │           │           │           │           │           │           │           │
├── PRE-LAUNCH ──┤
│  Legal, BD,    │
│  Mall agreement│
│                │
├───── PHASE 1: PROVE ──────────────────────────────────────────────┤
│  Seed #1: Ibn Battuta                                              │
│  ·······M1──────────────M12──────────M24──────────M33═══Phase 2══▶│
│                │         │           │                             │
│                │    Seed #2: MoE     │                             │
│                │    ·····M10─────────M22──────────M40═══Phase 2═══▶
│                │         │           │                             │
│                │         │      Seed #3: Dubai Mall                │
│                │         │      ····M15──────────M27───M44═══P2══▶│
│                │         │           │                             │
│          ┌─────┤    ┌────┤      ┌────┤                             │
│          │GATE1│    │GT2 │      │GT3 │                             │
│          │M6   │    │M12 │      │M18 │                             │
│          └─────┘    └────┘      └────┘                             │
│                                                                    │
├───── SCALE: SEMI-AUTO ────────────────────────────────────────────▶│
│                              Seeds #4-5 (M19-M22)                  │
│                                        Seeds #6-8 (M27-M33)       │
│                                                                    │
├───── FUNDRAISING ─────────────────────────────────────────────────▶│
│  Pre-Seed ──▶│   Seed Round ──▶│         Series A ──────────▶│    │
│  $500K  M0   │   $1M    M12-15 │         $3-5M    M24-30     │    │
│              │                  │                              │    │
│         ┌────┤             ┌────┤                         ┌───┤    │
│         │GT-F1             │GT-F2                         │GT-F3   │
│         └────┘             └────┘                         └───┘    │

Gates: ■ = operational    ▲ = fundraising    ✕ = kill criterion
```

---

## B. GATE DEFINITIONS

### B.0. Gate Taxonomy

| Type | Purpose | Consequence of FAIL |
|------|---------|-------------------|
| **Operational Gate** | Unlock next action (seed launch, mode transition) | Delay action, investigate cause |
| **Fundraising Gate** | Unlock next funding round | Extend runway, adjust scope |
| **Kill Gate** | Continue/pivot/shutdown decision | Reassess entire model |
| **Phase Gate** | Phase 1 → Phase 2 transition (Constitution §4) | Continue Phase 1, no revenue |

### B.0b. Терминология (cross-block)

| Термин | Определение | Где используется |
|--------|------------|-----------------|
| **CP (Connected Provider)** | Feed загружен в систему. Pipeline signal — подключён, но может быть неактивен | Gates 1, 3 (coverage metric) |
| **AP (Active Provider)** | Feed обновлён ≤ 7 дней + ≥ 1 user touchpoint за месяц. Health signal — реально работает | Gates 2, 4, 5 (engagement metric) |
| **PP_elig** | Provider, накопивший достаточно Earned Credits для Purchase при Phase 2. Ready but not yet paying | Gates 2–5 (monetization readiness) |
| **PP_paying** | PP_elig, реально покупающий Credits. Появляется **только** после Phase 2 trigger (или WTP pilot) | Gate 5+ (actual revenue) |

*CP → AP conversion target: ≥ 70% [H]. If CP high but AP low → providers connected but disengaged.*

---

### B.1. GATE 1: First Signal (M6)

> **Question:** Is the product working? Do users come back?

| # | Metric | Green ✓ | Yellow ⚠ | Red ✕ | Source |
|---|--------|---------|----------|-------|--------|
| 1 | Onsite MAU | > 2,000 [H] | 1,000–2,000 | < 1,000 | Block 3 §D.1 (M6: 4,055 [D]) |
| 2 | D7 retention | > 25% [H] | 15–25% | < 15% | Product benchmark [H]. *Note: Block 3 r(M6)=12% = D30 proxy, not D7. D7 measured independently* |
| 3 | Active Providers (AP) | > 35 [H] | 20–35 | < 20 | Block 3 §D.1 (M6: 55 CP × 70% ≈ 38 AP [H]) |
| 4 | AI rec quality (user rating) | > 3.5/5 [H] | 3.0–3.5 | < 3.0 | Product metric [H] |
| 5 | Activation rate | > 30% [H] | 20–30% | < 20% | Block 1 Step 2 (40% [H]) |

> **Seasonal adjustment [H]:** If Gate 1 falls in Jun–Aug (Dubai summer, −20% footfall [H]), MAU thresholds adjusted down 15% [H]: Green > 1,700, Yellow 850–1,700, Red < 850. Other metrics unaffected (retention/activation = ratios, not absolutes).

**Actions:**

| Result | Action |
|--------|--------|
| All Green | Proceed: begin Seed #2 BD outreach (launch M10) |
| Any Yellow | Investigate: identify bottleneck, fix before Seed #2 launch |
| Any Red | **GATE 1 HOLD:** Do not launch Seed #2. Focus resources on Seed #1. Re-evaluate at M9 |
| 2+ Red | **Escalate to Kill Gate K1** (§C) |

---

### B.2. GATE 2: Traction Confirmed (M12)

> **Question:** Is the network forming? Are Providers engaged?

| # | Metric | Green ✓ | Yellow ⚠ | Red ✕ | Source |
|---|--------|---------|----------|-------|--------|
| 1 | Onsite MAU | > 4,000 [H] | 3,000–4,000 | < 3,000 | Block 3 §D.1 (M12: 4,978 [D]) |
| 2 | D30 retention | > 15% [H] | 10–15% | < 10% | Block 3 trajectory (r at M12: 15% [H]) |
| 3 | PP_elig (eligible, not yet paying) | > 12 [H] | 8–12 | < 8 | Block 3 §D.1 (M12: 15 PP [H]) |
| 4 | OIR | > 0.30 [H] | 0.20–0.30 | < 0.20 | Block 3 §D.1 (M12: 0.44 [D]) |
| 5 | Provider share of traffic | > 20% [H] | 15–20% | < 15% | Block 3 §C.3 (M12: 28% [D]) |
| 6 | AP / CP ratio | > 65% [H] | 50–65% | < 50% | Health signal [H] |
| 7 | Seed #2 MAU (age 3) | > 1,500 [H] | 1,000–1,500 | < 1,000 | Replicability signal |

**Actions:**

| Result | Action |
|--------|--------|
| All Green | **FUNDRAISING GATE F2:** Raise Seed round ($1M). Launch Seed #3 (M15). Begin WTP pilots |
| Any Yellow | Raise Seed round with adjusted terms. Delay Seed #3 by 1–2 quarters |
| Any Red | **GATE 2 HOLD:** No Seed round. No Seed #3. Fix fundamentals |
| D30 < 10% + OIR < 0.20 | **Escalate to Kill Gate K2** (§C) |

---

### B.3. GATE 3: Network Forming (M18)

> **Question:** Is the multi-seed model working? Can we scale?

| # | Metric | Green ✓ | Yellow ⚠ | Red ✕ | Source |
|---|--------|---------|----------|-------|--------|
| 1 | Seed #1 OIR | > 0.60 | 0.45–0.60 | < 0.45 | Block 3 §D.1 (M18: 0.71) |
| 2 | Seed #1 D30 retention | > 20% | 15–20% | < 15% | Block 3 trajectory (M18: 22%) |
| 3 | Seeds live (MAU > 500) | ≥ 3 | 2 | 1 | Block 4 §G.3 |
| 4 | Provider share (Seed #1) | > 30% | 25–30% | < 25% | Block 3 §C.3 (M18: 37%) |
| 5 | WTP pilot data | Price confirmed ≥ $0.08/Credit | $0.05–0.08 | < $0.05 or refused | Block 6 §A.5 |
| 6 | Cross-mall effect (Seed #2–3) | Measurable MAU uplift | Inconclusive | Zero effect | Block 4 §C |
| 7 | Semi-Auto readiness | ≥ 2/5 triggers met | 1/5 | 0/5 | Block 4 §A.3 |

**Actions:**

| Result | Action |
|--------|--------|
| All Green | **Transition to Semi-Auto.** Launch Seeds #4–5 (M19–22). Tooling investment $23K |
| Any Yellow | Selective Semi-Auto: launch Seed #4 only. Defer #5 pending improvement |
| Any Red | **GATE 3 HOLD:** No Semi-Auto. No new seeds. Optimize existing 3 seeds |
| OIR < 0.45 + D30 < 15% + WTP refused | **Escalate to Kill Gate K3** (§C) |

---

### B.4. GATE 4: Revenue Validation (M24)

> **Question:** Will this business make money?

| # | Metric | Green ✓ | Yellow ⚠ | Red ✕ | Source |
|---|--------|---------|----------|-------|--------|
| 1 | Seed #1 OIR | > 1.0 | 0.80–1.0 | < 0.80 | Block 3 §D.1 (M24: 1.06) |
| 2 | Seed #1 D30 | > 28% | 20–28% | < 20% | Block 3 trajectory (M24: 30%) |
| 3 | WTP-validated price | ≥ $0.10/Credit | $0.08–0.10 | < $0.08 | Constitution §2.5 |
| 4 | Network MAU (all seeds) | > 20,000 | 15,000–20,000 | < 15,000 | Block 7 §C (M24: 26,533) |
| 5 | Seeds live | ≥ 5 | 4 | < 4 | Block 4 §G.3 |
| 6 | Monthly WTP revenue (actual) | > $5,000 | $3,000–5,000 | < $3,000 | Block 7 §C (M24: $7,677) |
| 7 | Provider churn (monthly) | < 5% | 5–10% | > 10% | Operational metric [H] |

**Actions:**

| Result | Action |
|--------|--------|
| All Green | **FUNDRAISING GATE F3:** Raise Series A ($3–5M). Begin Seeds #6–8. Prepare Market 2 analysis |
| Any Yellow | Raise smaller round ($2–3M). Launch Seeds #6–7 only. Defer Market 2 |
| Any Red | **GATE 4 HOLD:** No Series A. No new seeds beyond 5. Focus on Revenue-Ready for Seed #1 |
| OIR < 0.80 + WTP < $0.08 + churn > 10% | **Escalate to Kill Gate K4** (§C) |

---

### B.5. GATE 5: Phase 2 Entry — Seed #1 (M33 target)

> **Question:** Has Seed #1 earned the right to monetize?

**Primary thresholds (Constitution §3.1 — 1-в-1, все AND):**

| # | Metric | Threshold | Type | Constitution ref |
|---|--------|-----------|------|-----------------|
| 1 | Onsite MAU | > 500 (sustained) | [H] | §3.1 row 1 |
| 2 | Active Providers (AP) | ≥ 10 | [H] | §3.1 row 2 |
| 3 | k_combined | > 1.0 | [H] | §3.1 row 3 |
| 4 | D30 retention | > 40% | [H] | §3.1 row 4 |
| 5 | Category coverage | > 50% fashion stores | [H] | §3.1 row 5 |

**Supplementary signals (operational proxies, не заменяют primary):**

| # | Metric | Expected at Phase 2 | Type | Why tracked |
|---|--------|---------------------|------|-------------|
| S1 | OIR | > 1.0 (sustained 3+ months) | [H proxy] | Easier to measure than k_combined; strong correlate (Block 3 §A.3) |
| S2 | PP_elig | ≥ 10 | [H proxy] | Monetization readiness signal; AP ≥ 10 is necessary but PP_elig confirms Credits engagement |

> **Mapping note:** Constitution §3.1 uses "k_combined > 1.0". На практике k_combined трудно надёжно измерить и стабилизировать в steady-state при высоком retention (Block 3 §A.2 показывает структурное ограничение). Для операционного контроля используем OIR > 1.0 как proxy — сильно коррелирует с network effect (earned acquisition > organic). Эта подстановка помечена [H proxy] и будет согласована с Constitution v1.3 после данных Seed #1.

**All primary thresholds must be met simultaneously** (Constitution §3.1). This is not a gate with Yellow — it's binary: met or not met.

| Result | Action |
|--------|--------|
| All met | **PHASE 2 ACTIVE for Seed #1.** Full monetization. Revenue = Rev capacity |
| Not met | Continue Phase 1. Re-check monthly. Revenue = WTP pilot only (30% cap) |
| Not met by M36 | Adjust financial projections. Not a kill signal — seed may reach Phase 2 later |

*Phase 2 gates apply independently to each seed. Seed #2 Phase 2 ≠ Seed #1 Phase 2.*

> **⚠️ WTP revenue до Phase 2 = pilot-only.** Revenue в строке "WTP pilot (30% cap)" — B2B тестирование price с 3–5 providers (Block 7 §A.3). Users не затронуты. Это non-baseline revenue (Scenario P), не гарантированный поток. Baseline (Scenario S) = $0 до Phase 2.

---

### B.6. GATE 6: Network Maturity (M36)

> **Question:** Is Dubai proving the model for expansion?

| # | Metric | Green ✓ | Yellow ⚠ | Red ✕ | Source |
|---|--------|---------|----------|-------|--------|
| 1 | Seeds in Phase 2 | ≥ 2 | 1 | 0 | Block 7 §G |
| 2 | Network monthly margin | > −$30K | −$30K to −$60K | < −$60K | Block 7 §C (M36: −$28K) |
| 3 | Total network MAU | > 50,000 | 35,000–50,000 | < 35,000 | Block 7 §C (M36: 58,540) |
| 4 | Semi-Auto stable | ≥ 3/5 triggers met | 2/5 | < 2/5 | Block 4 §A.3 |
| 5 | Chain brand coverage | ≥ 3 brands across 4+ seeds | 2 brands | < 2 | Block 4 §F |
| 6 | Market 2 triggers | ≥ 2/4 met | 1/4 | 0/4 | Block 4 §G.4 |

**Actions:**

| Result | Action |
|--------|--------|
| All Green | **Begin Market 2 preparation.** Dubai on autopilot trajectory. Self-Serve transition planning |
| Any Yellow | Continue Dubai focus. Market 2 delayed to M42+ |
| Any Red | **GATE 6 HOLD:** Re-evaluate expansion plan. Focus on getting existing seeds to Phase 2 |

---

### B.7. GATE 7: Network Breakeven (M41 target)

> **Question:** Is the network self-sustaining?

| # | Metric | Threshold | Source |
|---|--------|-----------|--------|
| 1 | Monthly Net CF | > $0 (sustained 2+ months) | Block 7 §C (M41: +$1,141) |
| 2 | Seeds in Phase 2 | ≥ 3 | Block 7 §G |
| 3 | Monthly revenue | > $80K | Block 7 §C trajectory |
| 4 | Revenue / Opex ratio | > 1.0× | Block 7 §F |

| Result | Action |
|--------|--------|
| All met | **Network profitable.** Re-invest margin into Market 2 or accelerate remaining seed Phase 2 entries |
| Not met by M48 | Extend runway analysis. Assess if trajectory is positive (margin improving month-over-month) vs flat |

---

## C. KILL CRITERIA

> **Kill gates are escalation decisions, not automatic shutdowns.** Each requires founder + board discussion. Options: pivot product, pivot market, wind down gracefully.

### C.1. Kill Gate K1: Product Failure (earliest: M9)

**Trigger:** Gate 1 Red ×2 at M6 AND no improvement by M9.

| Signal | Threshold | Interpretation |
|--------|-----------|----------------|
| MAU < 1,000 at M6, < 1,500 at M9 | Flat or declining | Users don't find value |
| D7 < 15% at M6, < 18% at M9 | No retention improvement | Product not sticky |
| Activation < 20% | Consistent | UX/onboarding broken |

**Decision framework:**

| Option | When appropriate | Action |
|--------|-----------------|--------|
| **Fix & Retry** | One metric Red, others Yellow+ | 3-month sprint on bottleneck. Re-evaluate at M12 |
| **Pivot Market** | Product works but Dubai wrong market | Test different mall / different city. Budget: $50K |
| **Pivot Product** | Core rec engine works but wrong use case | Explore non-fashion verticals. Budget: $100K |
| **Wind Down** | All metrics Red, no improvement trend | Graceful shutdown. Return remaining capital. Timeline: 3 months |

---

### C.2. Kill Gate K2: Network Failure (earliest: M12)

**Trigger:** Gate 2 Red (D30 < 10% + OIR < 0.20) AND no improvement trend.

| Signal | Interpretation |
|--------|----------------|
| Providers don't engage (AP < 20, even if CP > 40) | Value prop doesn't resonate with B2B side |
| Users don't return (D30 < 10%) | Product is novelty, not habit |
| Traffic stays organic-only (OIR < 0.20) | No network effect forming |

**This is the most dangerous kill signal.** Low D30 + low OIR = the atomic network isn't viable. Without network effects, UNDE is a standalone app, not a platform.

---

### C.3. Kill Gate K3: Monetization Failure (earliest: M18)

**Trigger:** WTP pilots show Providers won't pay at any price.

| Signal | Interpretation |
|--------|----------------|
| All WTP pilots refused or priced < $0.03/Credit | Credits economy doesn't work |
| Providers prefer direct marketing channels | UNDE doesn't offer incremental value |
| Provider churn > 15% monthly | Providers actively leaving |

---

### C.4. Kill Gate K4: Economics Failure (earliest: M24)

**Trigger:** Unit economics don't work at validated scale.

| Signal | Interpretation |
|--------|----------------|
| Revenue/Opex ratio < 0.3× at M24 scale | Revenue can never cover costs |
| AI cost not decreasing (still > $0.60/MAU at M24) | Optimization not happening |
| Retention plateaued < 20% (no path to 40%) | Phase 2 will never trigger |

---

## D. FUNDRAISING GATES

### D.1. Gate F1: Pre-Seed ($500K)

| Timing | M0 (pre-launch) |
|--------|-----------------|
| **What investor sees** | Team, product demo, market analysis, financial model (Blocks 1–7), mall LOI |
| **What we promise** | Gate 1 results by M6 |
| **Runway** | ~14 months (to M14) |
| **Use of funds** | Seed #1 launch ($18K [H]), 6 months ops ($170K [H]), team salaries ($280K [H]), contingency ($32K [H]) |
| **Return profile** | Block 7 §G.4: $1.64M peak investment → $1.56M/year run-rate at maturity. <1 year payback post-Phase 2. IRR ~35–45% [H]. Pre-Seed = first tranche of staged deployment |

### D.2. Gate F2: Seed Round ($1M)

| Timing | M12–M15 (after Gate 2) |
|--------|------------------------|
| **Required metrics** | Gate 2 Green or Yellow (no Red) |
| **What investor sees** | Seed #1 data (MAU, retention, OIR), Seed #2 early signal, WTP pilot plan |
| **What we promise** | Gate 4 results by M24 |
| **Runway** | Extends to ~M25 (combined with Pre-Seed remainder) |
| **Use of funds** | Seeds #3–5 ($36K [H]), tooling ($23K [H]), 12 months team + ops ($750K [H]), marketing ($100K [H]), contingency ($91K [H]) |

### D.3. Gate F3: Series A ($3–5M)

| Timing | M24–M30 (after Gate 4) |
|--------|------------------------|
| **Required metrics** | Gate 4 Green; ideally Seed #1 approaching Phase 2 |
| **What investor sees** | 5+ seeds, validated unit economics, WTP revenue, cross-mall effect data, Semi-Auto working |
| **What we promise** | Network breakeven by M41, all 8 seeds Phase 2 by M55, Market 2 entry |
| **Runway** | To M48+ (self-sustaining) |
| **Use of funds** | Seeds #6–8 ($12K [H]), Market 2 prep ($200K [H]), team scaling ($2.4M [H]), platform engineering ($800K [H]), contingency ($500K+ [H]) |

---

## E. OPERATING DASHBOARD — TRAFFIC LIGHT

### E.1. Monthly Metrics (per seed)

| Metric | Green ✓ | Yellow ⚠ | Red ✕ | Cadence |
|--------|---------|----------|-------|---------|
| Onsite MAU | ≥ Block 3 trajectory | 70–100% of trajectory | < 70% | Weekly |
| D7 retention | > 25% | 18–25% | < 18% | Weekly |
| D30 retention | > Block 3 r(t) | 70–100% of trajectory | < 70% | Monthly |
| New CP/month | ≥ Block 3 trajectory | 70–100% | < 70% | Monthly |
| AP/CP ratio | > 70% | 50–70% | < 50% | Monthly |
| PP_elig growth | On track | Slowing | Stalled or declining | Monthly |
| OIR | ≥ Block 3 trajectory | 70–100% | < 70% | Monthly |
| AI cost/MAU | ≤ Block 6 trajectory | Up to 120% | > 120% | Monthly |
| Provider churn | < 5% | 5–10% | > 10% | Monthly |
| User NPS | > 40 | 25–40 | < 25 | Quarterly |

### E.2. Monthly Metrics (network-level)

| Metric | Green ✓ | Yellow ⚠ | Red ✕ | Cadence |
|--------|---------|----------|-------|---------|
| Total MAU (all seeds) | ≥ Block 7 trajectory | 70–100% | < 70% | Weekly |
| Monthly Net CF | ≥ Block 7 trajectory | −20% variance | > −20% variance | Monthly |
| Cash runway | > 12 months | 6–12 months | < 6 months | Monthly |
| Seeds in Phase 2 | On schedule | 1 quarter behind | > 2 quarters behind | Quarterly |
| Central cost / seed | Declining trend | Flat | Increasing | Monthly |

### E.3. Escalation Protocol

```
Green → Continue operations. No action required.
Yellow → Investigate within 1 week. Root cause analysis. Action plan within 2 weeks.
Red → Emergency review within 48 hours. Resource reallocation. Gate holds triggered.
2+ Red sustained 2+ months → Kill Gate escalation (§C).
```

---

## F. DECISION TREE — WHAT TO DO WHEN

### F.1. "MAU is below trajectory"

```
MAU below trajectory
├── Activation rate low? (< 30%)
│   ├── YES → UX/onboarding problem. Fix first-time experience
│   └── NO → Traffic volume problem
│       ├── Provider channels delivering? (N_provider on track?)
│       │   ├── YES → Organic discovery broken. Check QR placement, indoor positioning
│       │   └── NO → Provider engagement problem
│       │       ├── Enough providers? (CP on track?)
│       │       │   ├── YES → Provider motivation. Credits not compelling enough?
│       │       │   └── NO → BD pipeline. Accelerate outreach
│       └── Footfall seasonal? (summer dip?)
│           ├── YES → Expected. Compare vs seasonal-adjusted trajectory
│           └── NO → Structural issue. Investigate mall foot traffic data
```

### F.2. "Retention is below trajectory"

```
D30 below trajectory
├── D7 also low? (< 18%)
│   ├── YES → Product doesn't hook. Priority: core value loop
│   │   ├── Rec quality? (user ratings < 3.5) → Improve AI model
│   │   ├── Inventory coverage? (< 50%) → Onboard more providers
│   │   └── App performance? → Technical fixes
│   └── NO → D7 ok but D30 low = users forget
│       ├── Re-engagement working? → Push notification strategy
│       ├── Avatar progression compelling? → Gamification review
│       └── New content cadence? → Provider feed freshness
```

### F.3. "Providers won't pay"

```
WTP pilot failing
├── Providers see value? (use dashboard, check analytics)
│   ├── YES → Price too high. Test lower ($0.05, $0.03)
│   │   ├── Pay at lower price → Adjust model. Block 6 rev_cap recalculated
│   │   └── Won't pay at any price → Credits economy broken (Kill Gate K3)
│   └── NO → Providers don't engage with platform at all
│       ├── Traffic sufficient? (> 50 users/month to provider)
│       │   ├── YES → Analytics/dashboard not compelling. Redesign
│       │   └── NO → Seed too small. Need more MAU before WTP
```

### F.4. Tactical Responses (A/B при Yellow)

> Конкретные эксперименты для быстрого исправления Yellow metrics. Каждый = 2–4 недели sprint, measurable outcome.

| Yellow signal | Tactic A | Tactic B | Expected lift | Cost |
|---------------|----------|----------|--------------|------|
| D7 < 25% (Gate 1) | **Onboarding redesign:** сократить до 3 шагов, first rec за 60 сек | **Push notification A/B:** D3 reminder с персональным outfit | +10–15% D7 [H] | $0 (product work) |
| D30 < trajectory (Gate 2) | **Avatar progression:** visible level-up at D14, D30 reward | **Weekly digest:** email/push с "new arrivals matching your style" | +5–8% D30 [H] | $0 (product) |
| Provider share < 20% (Gate 2) | **Provider incentive sprint:** bonus Credits за первых 10 activated users | **QR placement audit:** relocate from counter to fitting room | +3–5% provider share [H] | $500/seed [H] |
| WTP < $0.08 (Gate 3) | **Value demo:** show providers "users who saw your items" analytics free for 30 days, then gate behind Credits | **Tiered pricing:** $0.05 base + $0.12 premium (priority + analytics) | Validate WTP range | $0 |

*Каждый A/B тест = max 1 месяц. If neither A nor B improves metric → structural problem, not tactical. Escalate to next gate level.*

---

## G. MILESTONE CHECKLIST (Operational)

### G.1. Pre-Launch (M-3 to M0)

| # | Task | Owner | Deliverable | Status |
|---|------|-------|------------|--------|
| 1 | Company registration (Dubai) | Founder | Trade license | ☐ |
| 2 | Mall partnership agreement (Ibn Battuta) | BD | Signed LOI/contract | ☐ |
| 3 | First 5 provider LOIs | BD | Signed letters of intent | ☐ |
| 4 | Product MVP ready | Tech | Working app + AI recs | ☐ |
| 5 | Indoor positioning tested | Tech | Accuracy < 5m in-mall | ☐ |
| 6 | Pre-Seed closed ($500K) | Founder | Funds in bank | ☐ |
| 7 | Financial model complete (Blocks 1–7) | Founder | This document set | ☐ |

### G.2. M1–M6: Seed #1 Launch & First Signal

| Month | Key actions | Gate |
|-------|------------|------|
| M1 | Launch activation (theater, QR), first 15 providers live | — |
| M2 | First MAU data. AI rec quality monitoring begins | — |
| M3 | 3+ PP_elig. First retention cohort (D30 for M1 installs) | — |
| M4 | Provider feedback round. Credits earning visible in dashboard | — |
| M5 | Seed #2 BD outreach begins (if M3 signals positive) | — |
| **M6** | **GATE 1: First Signal** | **§B.1** |

### G.3. M7–M12: Traction Building

| Month | Key actions | Gate |
|-------|------------|------|
| M7 | Monitoring dashboard ready ($7K tooling). PP_elig > 10 target | — |
| M9 | Kill Gate K1 check (if Gate 1 was Red) | §C.1 |
| M10 | Seed #2 launch (Mall of Emirates) — if Gate 1 Green/Yellow | — |
| **M12** | **GATE 2: Traction Confirmed. GATE F2: Seed Round.** Begin WTP pilots | **§B.2, §D.2** |

### G.4. M13–M18: Multi-Seed Validation

| Month | Key actions | Gate |
|-------|------------|------|
| M14 | Self-serve dashboard + feed validation ready ($23K tooling) | — |
| M15 | Seed #3 launch (Dubai Mall) — if Gate 2 Green/Yellow | — |
| **M18** | **GATE 3: Network Forming.** Semi-Auto decision | **§B.3** |

### G.5. M19–M24: Scale Test

| Month | Key actions | Gate |
|-------|------------|------|
| M19 | Seed #4 launch (Semi-Auto mode) | — |
| M22 | Seed #5 launch | — |
| **M24** | **GATE 4: Revenue Validation. GATE F3: Series A.** | **§B.4, §D.3** |

### G.6. M25–M36: Revenue Ramp

| Month | Key actions | Gate |
|-------|------------|------|
| M27 | Seed #6 launch | — |
| M30 | Seed #7 launch | — |
| M33 | Seed #8 launch. **GATE 5: Phase 2 — Seed #1** | **§B.5** |
| **M36** | **GATE 6: Network Maturity** | **§B.6** |

### G.7. M37–M48: Network Profitability

| Month | Key actions | Gate |
|-------|------------|------|
| M40 | Seed #2 Phase 2 entry | — |
| **M41** | **GATE 7: Network Breakeven** (target) | **§B.7** |
| M44 | Seed #3 Phase 2. Market 2 preparation | — |
| M48 | 5 seeds Phase 2. +$85K/mo margin. Market 2 launch decision | — |

---

## H. RELATIONSHIP: BLOCKS → GATES → ACTIONS

| Block | Provides | Used in Gate | Key metric |
|-------|----------|-------------|------------|
| Block 1 (Unit Economics) | Baseline MAU, PP, revenue/cost | All Gates (baseline) | Rev per Provider, Cost per MAU |
| Block 3 (Network Dynamics) | Monthly trajectory, OIR milestones | Gates 1–5 (trajectory targets) | OIR, k_combined, retention |
| Block 4 (Expansion) | Mode triggers, cross-mall effects | Gates 3, 6 (expansion decisions) | Semi-Auto triggers, Market 2 triggers |
| Block 6 (Single Seed P&L) | Revenue capacity, cost structure | Gates 4–5 (unit economics validation) | Rev/Cost ratio, AI cost/MAU |
| Block 7 (Multi-Seed CF) | Network cash flow, runway | Gates 6–7, F1–F3 (investment decisions) | Net CF, cumulative, runway |

---

## I. PARAMETER REGISTRY

| Parameter | Value | Type | Source |
|-----------|-------|------|--------|
| Gate 1 timing (target) | M6 | [H proxy] | Block 3 §D.1 |
| Gate 2 timing (target) | M12 | [H proxy] | Block 3 §D.2 |
| Gate 3 timing (target) | M18 | [H proxy] | Block 4 §A.3 |
| Gate 4 timing (target) | M24 | [H proxy] | Block 7 §F.3 |
| Gate 5 timing (target) | M33 | [D] from Block 3 trajectory | Constitution §3.1 thresholds |
| Gate 6 timing (target) | M36 | [H proxy] | Block 7 §G |
| Gate 7 timing (target) | M41 | [D] from Block 7 trajectory | Block 7 §C |
| Green/Yellow/Red thresholds | Various | [H] | Calibrated from Block 3 trajectories |
| Kill Gate escalation | 2+ Red sustained 2+ months | [H] | Operational policy |
| Pre-Seed amount | $500K | [H] | Block 7 §F.2 |
| Seed Round amount | $1M | [H] | Block 7 §F.3 |
| Series A amount | $3–5M | [H] | Block 7 §F.3 |
| AP/CP target ratio | ≥ 70% | [H] | Block 8 v1.1 §B.0b |
| Seasonal MAU adjustment (summer) | −15% thresholds | [H] | Block 8 v1.1 §B.1 |

---

## J. EVIDENCE PLACEHOLDERS

| Reference | Used in | Status | Verification path |
|-----------|---------|--------|-------------------|
| D7 retention benchmark (>25% Green) | §B.1 Gate 1 | **TBD → [V]** | Industry benchmarks: Mixpanel / Amplitude mobile app retention reports; validate against Seed #1 M3 cohort |
| AP/CP ratio target (70%) | §B.0b, §B.2, §E.1 | **TBD → [V]** | Internal: Seed #1 M3+ provider engagement data |
| Seasonal footfall variance (±20%) | §B.1, §H.4 (Block 7) | **TBD → [V]** | DSC.gov.ae Monthly Trade Index; Emaar Malls quarterly reports |
| Gate thresholds calibration | §B.1–B.7 all | **TBD → [V]** | Block 3 trajectories used as baselines; recalibrate after Seed #1 M6 actuals |
| WTP price floor ($0.08 Yellow) | §B.3 Gate 3 | **TBD → [V]** | WTP pilot data (M12+); conjoint analysis if needed |
| Provider churn benchmarks (<5% Green) | §B.4, §E.1 | **TBD → [V]** | SaaS B2B churn benchmarks (Recurly, ProfitWell reports); validate against Seed #1 M6+ data |
| Kill Gate escalation timing (2+ Red, 2+ months) | §C, §E.3 | **[H]** | Operational policy — calibrate after first Yellow/Red event |
| Use of funds allocations (D.1–D.3) | §D | **[H]** | Block 7 opex trajectories + Dubai FTE salary benchmarks (GulfTalent) |

*Priority: items 1, 3, 6 verifiable pre-launch via public benchmarks. Items 2, 4, 5, 7 require Seed #1 operational data (M3–M12).*

---

*Inputs: Constitution v1.2, Blocks 1–4, 6–7 | Протокол: UNDE_Model_Constitution_v1.2*
