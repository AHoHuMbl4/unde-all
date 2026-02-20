# UNDE — Evidence & Sources Sheet
## Сквозной реестр гипотез, источников и статусов верификации
### v1.6

---

## 0. Назначение

Единый справочник всех параметров модели, требующих верификации. Связывает [H]-гипотезы с конкретными источниками данных и сроками проверки. Используется для: (a) приоритизации evidence-gathering до/после launch, (b) подготовки investor data room, (c) отслеживания перехода NEED_SRC → FOUND → VERIFIED.

**Изменения v1.6 vs v1.5:**
- F3: явно помечен [H theory — obsolete]. Добавлен текст "Устаревший порог, заменён на OIR > 1.0, будет обновлён в Constitution v1.3"
- E1b-note: конкретная арифметика $/token → $/MAU (12K tok × $0.068/1K = $0.82). Плюс optimization path к $0.45

**Data type tags (из Конституции, НЕ менять):**
- **[H]** — Hypothesis. Обоснованная оценка, не подтверждённая данными
- **[H proxy]** — Operational proxy. Заменяет другой параметр для удобства измерения
- **[D]** — Derived. Вычисляется из других параметров
- **[V]** — Verified (Constitution meaning). Подтверждено источником с указанием ссылки
- **[F]** — Fact. Подтверждено собственными операционными данными

*[H/D/V] = тип числа в модели. Не путать со статусом верификации ниже.*

**Статусы верификации (Evidence Sheet pipeline):**
- **NEED_SRC** — Источник не определён или не найден
- **FOUND** — Источник найден, данные ещё не извлечены/проанализированы
- **VERIFIED** — Данные извлечены, параметр подтверждён или скорректирован. Параметр в модели переходит в [V] или [F]

**Покрытие:** Constitution v1.2, Blocks 1 (Steps 1–2), 3, 4, 6, 7, 8

---

## A. КАТЕГОРИЯ: MARKET & FOOTFALL

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| A1 | Ibn Battuta monthly footfall | ~1.5M unique visitors/month [H baseline] | [H] → [D] when sourced | B1§A, B3§B, B6§C, B7§C | **Critical** | Pre-launch |

*A1 note: 1.5M = [H] until source found. Once daily/annual figure obtained (e.g. from Nakheel IR), monthly = derived via multiplication → A1 becomes [D], raw source figure becomes [V].*
| A2 | Fashion footfall share | 30% of total | [H] | B1§A | High | Pre-launch |
| A3 | Footfall_Variance (seasonal multiplier) | 0.85 (summer) / 1.00 (base) / 1.20 (winter peak) | [H] | B7§H.4, B8§B.1 | High | Pre-launch |
| A3b | Event_Boost (Dubai Summer Surprises, DSF, etc.) | +10–25% during promo months | [H] | New | Medium | Pre-launch |
| A4 | Mall visitor overlap rate | 2.3 avg unique malls visited per unique person per month | [H] | B4§C | Medium | Pre-launch |
| A5 | Footfall downside scenario | 1.25M (−17%) | [H] | B6§E, B7§H.5 | Medium | M6 validation |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| A1-src1 | Emaar Malls / Nakheel annual reports (Ibn Battuta = Nakheel) | Public | IR pages, investor presentations | NEED_SRC |
| A1-src2 | Dubai Statistics Center (DSC.gov.ae) — Monthly Trade Index | Public | Downloadable | FOUND | *Proxy for A3/A3b variance, NOT direct proof of A1 footfall. Trade index ≠ mall visitor count* |
| A1-src3 | Placer.ai / SafeGraph mall traffic data (paid) | Paid | $500–2K for dataset | NEED_SRC |
| A3-src1 | DSC seasonal retail index (monthly breakdown) | Public | DSC.gov.ae | FOUND |
| A3-src2 | KPMG GCC Consumer Pulse Survey 2024 | Public | kpmg.com/ae | NEED_SRC |
| A3b-src1 | Dubai Festivals & Retail Establishment (DFRE) — DSS/DSF impact reports | Public | mydsf.ae, visitdubai.com | FOUND |
| A4-src1 | Emaar/Majid Al Futtaim loyalty program data (cross-mall) | Request | Via mall partnership BD | NEED_SRC |

---

## B. КАТЕГОРИЯ: USER BEHAVIOR

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| B1 | App adoption rate (from fashion footfall) | 2% | [H] | B1§A | **Critical** | M3 validation |
| B2 | Install → Activation rate | 40% | [H] | B1§A, B8§B.1 | **Critical** | M1 measurement |
| B3 | Monthly Return Rate (r) initial | 15% | [H] | B1§A, B3§D.1 | **Critical** | M3 (D30 cohort) |
| B4 | Return Rate trajectory | 15% (M6) → 22% (M18) → 30% (M24) → 45% (M36) | [H] | B3§D.1, B6§C | **Critical** | M6+ tracking |
| B5 | D7 retention (Gate 1) | >25% Green | [H] | B8§B.1 | High | M2 (first cohort) |
| B6 | D30 retention target (Phase 2) | >40% | [H] | Constitution §3.1, B8§B.5 | **Critical** | M24+ tracking |
| B7 | Viral coefficient (user sharing) | k_user: 0.003 (M3) → 0.107 (M36) | [H] | B3§B, B3§D.1 | Medium | M6+ measurement |
| B8 | Items per Recommendation | 5 | [H] | B1§C | Low | Product decision |
| B9 | Visits per MAU per month | Casual 1.5, Regular 4, Power 8 | [H] | B1§C | Medium | M3 measurement |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| B1-src1 | Mixpanel/Amplitude mobile app benchmarks (retail category) | Public | Annual reports | FOUND |
| B1-src2 | Mall app adoption benchmarks (Westfield, Simon Property Group) | Semi-public | Industry reports, app store data | NEED_SRC |
| B3-src1 | Liftoff Mobile App Retention Report 2024 | Public | liftoff.io | FOUND |
| B3-src2 | Adjust Global App Trends Report | Public | adjust.com | FOUND |
| B5-src1 | Shopping app D7 benchmarks (Appsflyer retention data) | Public | appsflyer.com/resources | NEED_SRC |

---

## C. КАТЕГОРИЯ: PROVIDER ECONOMICS

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| C1 | Connected Providers target (M6) | 55 CP | [H] | B3§D.1 | High | M6 validation |
| C2 | Paying Providers trajectory | 3 (M3) → 15 (M12) → 55 (M36) | [H] | B3§C.1, B3§D.1 | **Critical** | M6+ tracking |
| C3 | Activated users per PP per month | 12 (M3) → 42 (M36) | [H] | B3§C.1 | High | M3+ measurement |
| C4 | Provider share of traffic target | 30–40% | [H] | Constitution, B3§C.3 | **Critical** | M12 validation |
| C5 | AP/CP ratio target | ≥70% | [H] | B8§B.0b | Medium | M6 measurement |
| C6 | Provider churn benchmark | <5% monthly (Green) | [H] | B8§B.4, B8§E.1 | Medium | M6+ tracking |
| C7 | Provider onboarding cost (manual) | $200–300 per local provider | [H] | B4§A.4 | Medium | M3 actual |
| C8 | Chain brand first integration cost | $1,000–2,000 | [H] | B4§A.4 | Medium | First chain deal |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| C4-src1 | Internal: Seed #1 attribution tracking (M6+) | Internal | Product analytics | NEED_SRC |
| C6-src1 | SaaS B2B churn benchmarks (Recurly, ProfitWell/Paddle) | Public | recurly.com, paddle.com | FOUND |
| C7-src1 | Internal: Seed #1 post-launch cost reconciliation | Internal | M3+ finance | NEED_SRC |

---

## D. КАТЕГОРИЯ: CREDITS ECONOMY & PRICING

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| D1 | Price per Credit | $0.10 (Phase 1–2), $0.12 (M24+) | [H] | Constitution §2.5, B6§I | **Critical** | WTP pilot (M12+) |
| D2 | K coefficient (Earn-to-Spend) | 0.3 → 0.5 → 0.7 → 1.0 by tier | [H] | Constitution §2.3 | High | WTP pilot design |
| D3 | Credits per user action | Install +10, Activation +100, D7 +50, D30 +150 | [H] | Constitution §2.2 | Medium | Product calibration (M3+) |
| D4 | Organic threshold (non-paid recs) | 30% minimum | [H] | Constitution §7, B1§C | High | Product architecture |
| D5 | Avg Credits per prioritized slot | 3 | [H] | B1§C | Low | WTP pilot (M12+) |
| D6 | Credits decay (90 days + 10%/week) | 90-day validity, then 10%/week decay | [H] | Constitution §2.6 | Low | Product decision |
| D7 | WTP price floor (Gate 3 Yellow) | $0.05–0.08/Credit | [H] | B8§B.3 | High | WTP pilot (M12+) |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| D1-src1 | Competitor pricing: StoreTraffic ($29.95–$51.95/mo), Dor ($135/mo) | Public | Competitor websites | FOUND |
| D1-src2 | Retail analytics pricing benchmarks (Placer, RetailNext, Springboard) | Semi-public | Pricing pages, Capterra reviews | NEED_SRC |
| D1-src3 | Conjoint analysis / Van Westendorp with pilot providers | Internal | WTP pilot M12+ | NEED_SRC |

---

## E. КАТЕГОРИЯ: COST STRUCTURE

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| E1 | AI cost per MAU (initial) | $0.82/mo | [H] | B3§G.1, B4§B.2, B6§I | **Critical** | M1 measurement |
| E1b | AI workload per MAU (bridge) | ~15 requests/MAU/month × ~800 tokens/request avg = ~12K tokens/MAU/month | [H] | New (bridge E1↔E1-src) | **Critical** | M1 measurement |
| E2 | AI cost optimization trajectory | $0.82 → $0.70 (M6) → $0.45 (M36) | [H] | B3§G.1, B6§I | High | M6+ tracking |
| E3 | AI scale discount (5–8 seeds) | 8% | [H] | B4§B.2, B7§A.4 | Medium | M19+ (5 seeds) |
| E4 | Ops team cost (Dubai) | $2,000–3,000/mo per seed (Manual) | [H] | B3§G.1, B6§I | High | M1 actual |
| E5 | Central team cost | $23K/mo (1–3 seeds) → $30K/mo (7+) | [H] | B4§B.2, B7§A.4 | High | M1 actual |
| E6 | Central team FTE rates (Dubai) | Ops $4K, BD $5K, Tech $6K /FTE/mo | [H] | B4§B.2 | High | Pre-launch |
| E7 | Server / infra per seed | $200 (M1) → $500 (M36) | [H] | B3§G.1, B6§I | Low | M1 measurement |
| E8 | Central Infra formula | MAX(500, FLOOR(Total_MAU / 1000) × 100) | [H] | B7§J | Low | M12+ validation |
| E9 | One-time launch cost (Manual) | $18,000 | [H] | B6§A.3, B7§A.4 | High | M3 reconciliation |
| E10 | Semi-Auto launch cost | $4,000 | [H] | B4§A.4, B7§A.4 | Medium | M19+ actual |
| E11 | Tooling investment (Semi-Auto) | $30,000 total | [H] | B4§A.4, B7§A.4 | Medium | M12–14 spend |
| E12 | Semi-Auto cost multipliers (ops 0.5×, onb 0.4×, srv 0.65×) | As stated | [H] | B4§B.2, B7§A.4 | Medium | M19+ validation |
| E13 | Launch velocity spike | +10–15% local opex when 2+ simultaneous launches | [H] | B7§H.6, B7§J | Low | M19+ observation |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| E1-src1 | OpenAI API pricing (GPT-4o, GPT-4o-mini volume tiers) | Public | openai.com/pricing | FOUND |
| E1-src2 | Anthropic Claude API pricing (volume discounts) | Public | anthropic.com/pricing | FOUND |
| E1-src3 | AWS Bedrock / Google Vertex AI reserved capacity pricing | Public/NDA | Cloud provider sales | NEED_SRC |
| E1-src4 | Internal: actual AI inference cost per request (M1 measurement) | Internal | Product analytics | NEED_SRC |
| E1b-src1 | Internal: avg requests/user/session × sessions/MAU/month (product analytics M1+) | Internal | Product analytics | NEED_SRC |
| E1b-src2 | Internal: avg tokens/request (prompt + completion) from API logs | Internal | API dashboard | NEED_SRC |
| E1b-note | *Bridge arithmetic: ~15 req/MAU/mo × ~800 tok/req = ~12K tok/MAU/mo. At GPT-4o volume pricing ~$0.068/1K tokens [V from E1-src1]: 12K × $0.000068 ≈ $0.82/MAU. Without this bridge, API pricing proves $/token but NOT $/MAU. Optimization path: prompt compression (−30% tokens), caching (−20% requests), model downgrade for simple queries (−40% $/token) → trajectory to $0.45* | — | — | — |
| E6-src1 | GulfTalent Salary Survey 2024 (UAE tech salaries) | Public | gulftalent.com | FOUND |
| E6-src2 | Bayt.com UAE salary index | Public | bayt.com | FOUND |
| E6-src3 | Glassdoor Dubai tech salaries | Public | glassdoor.com | FOUND |
| E9-src1 | Internal: Seed #1 post-launch financial reconciliation | Internal | M3+ finance | NEED_SRC |

---

## F. КАТЕГОРИЯ: NETWORK DYNAMICS

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| F1 | OIR trajectory | 0.08 (M3) → 0.44 (M12) → 1.06 (M24) → 1.98 (M36) | [D] from [H] inputs | B3§D.1 | **Critical** | M6+ tracking |
| F2 | OIR > 1.0 crossing | ~M24 | [D] | B3§D.2 | **Critical** | M18+ tracking |
| F3 | k_combined > 1.0 steady-state constraint | **Устаревший порог.** Математически недостижим в steady-state при r > 0 (Block 3 §A.2). Заменён на OIR > 1.0 как operational proxy (Block 8 §B.5). Будет формально обновлён в Constitution v1.3 | [H theory — obsolete] | Constitution §3.1, B3§A.2, B8§B.5 | — | *Не верифицируемый параметр. Оставлен для audit trail* |
| F4 | Cross-mall Transfer rate | 4–14% per pair (= share of existing-user installs in new seed's total installs) | [H] | B4§C | Medium | M10+ (seed 2 data) |
| F5 | Revenue-Ready acceleration by seed # | 33 (seed 1) → 23 (seed 8) months | [H] | B4§C.5, B7§A.2 | Medium | M33+ validation |
| F6 | Phase 2 trigger = dominant sensitivity variable | $250K+ swing in cumulative P | [D] | B6§E, B7§I | **Critical** | M24+ tracking |

**Источники для верификации:**

| # | Источник | Тип | Доступность | Статус |
|---|---------|-----|-------------|--------|
| F1-src1 | Internal: Seed #1 OIR calculated monthly from product analytics | Internal | M3+ | NEED_SRC |
| F4-src1 | Internal: Seed #2 app install data with "existing user" flag | Internal | M10+ | NEED_SRC |

---

## G. КАТЕГОРИЯ: EXPANSION & OPERATIONS

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| G1 | Seed launch schedule | M1/M10/M15/M19/M22/M27/M30/M33 | [H] | B4§G.3, B7§A.2 | High | Ongoing |
| G2 | Manual → Semi-Auto trigger | ≥3 seeds surviving + 5 criteria | [H] | B4§A.3 | High | M18–24 |
| G3 | Semi-Auto → Self-Serve trigger | ≥15 seeds + 5 criteria | [H] | B4§A.3 | Low | M30–42 |
| G4 | Market 2 triggers | 4 criteria (seeds, margin, brand pull, playbook) | [H] | B4§G.4 | Medium | M36+ |
| G5 | WTP pilot eligibility | Seed age ≥ 12 [H proxy] | [H proxy] | B6§A.5, B7§A.3, B8§B.5 | High | M12 |
| G6 | Phase 1 age proxy | Seed age < 12 ≈ pre-WTP-eligibility | [H proxy] | B7§A.3 | Medium | — |

---

## H. КАТЕГОРИЯ: GATE THRESHOLDS (Block 8)

| # | Параметр | Значение | Тип | Gate | Приоритет | Timing |
|---|----------|---------|-----|------|-----------|--------|
| H1 | Gate 1 MAU Green | >2,000 | [H] | B8§B.1 | High | M6 |
| H2 | Gate 1 D7 Green | >25% | [H] | B8§B.1 | High | M6 |
| H3 | Gate 1 AP Green | >35 | [H] | B8§B.1 | High | M6 |
| H4 | Gate 2 OIR Green | >0.30 | [H] | B8§B.2 | High | M12 |
| H5 | Gate 3 WTP price Green | ≥$0.08/Credit | [H] | B8§B.3 | **Critical** | M18 |
| H6 | Gate 4 monthly WTP revenue Green | >$5,000 | [H] | B8§B.4 | High | M24 |
| H7 | Gate 5 all Constitution §3.1 | MAU>500, AP≥10, k>1.0, D30>40%, Coverage>50% | [H] | B8§B.5 | **Critical** | M33 |
| H8 | Seasonal MAU adjustment (summer) | 1 − A3(summer) = 1 − 0.85 = 15% threshold reduction | [D] from A3 | B8§B.1 | — | Derived, not independent |
| H9 | Kill escalation rule | 2+ Red sustained 2+ months | [H] | B8§C, B8§E.3 | High | Ongoing |

---

## I. КАТЕГОРИЯ: FUNDRAISING

| # | Параметр | Значение | Тип | Блок(и) | Приоритет | Timing |
|---|----------|---------|-----|---------|-----------|--------|
| I1 | Pre-Seed amount | $500K | [H] | B7§F.2, B8§D.1 | High | M0 |
| I2 | Seed Round amount | $1M | [H] | B7§F.3, B8§D.2 | High | M12–15 |
| I3 | Series A amount | $3–5M | [H] | B7§F.3, B8§D.3 | Medium | M24–30 |
| I4 | Pre-Seed use of funds | Launch $18K, Ops $170K, Team $280K, Contingency $32K | [H] | B8§D.1 | High | M0 |
| I5 | ROI post-breakeven | ~1.5× / year | [H] narrative | B7§G.4 | Medium | M55+ |
| I6 | IRR estimate | 35–45% | [H] narrative | B7§G.4 | Medium | M55+ |

---

## J. VERIFICATION PRIORITY MATRIX

### J.1. Pre-Launch (now → M0): верифицировать до привлечения Pre-Seed

| Priority | Parameter(s) | Action | Source | Impact if wrong |
|----------|-------------|--------|--------|----------------|
| **P1** | A1 (footfall 1.5M) | Request from Nakheel IR / DSC.gov.ae | Public | Entire model scales linearly. ±30% footfall = ±30% MAU baseline |
| **P2** | E6 (Dubai FTE salaries) | Cross-reference GulfTalent + Bayt + Glassdoor | Public | Central cost = 81% of Y1 opex. ±20% = ±$55K/year |
| **P3** | E1 + E1b (AI cost $0.82/MAU = workload × $/token) | Benchmark: OpenAI/Anthropic pricing × estimated workload. Verify workload in M1 | Public + test | AI cost = largest variable cost. ±30% = ±$35K/year. Without E1b bridge, pricing sources don't prove $/MAU |
| **P4** | A3 (Footfall_Variance 0.85–1.20) | DSC monthly retail data + DFRE event reports | Public | Affects launch timing + gate seasonal adjustments |
| **P5** | D1 (competitor pricing) | Scan StoreTraffic, Dor, RetailNext pricing pages | Public | Anchors WTP pilot price range |

### J.2. M1–M6: верифицировать в первые 6 месяцев

| Priority | Parameter(s) | Action | Source | Impact if wrong |
|----------|-------------|--------|--------|----------------|
| **P6** | B1, B2 (adoption 2%, activation 40%) | Measure actual install + activation | Internal | If <1% adoption → model breaks (MAU < 500) |
| **P7** | B3 (retention 15% at M6) | Track D30 cohort from M1 installs | Internal | If <10% → Kill Gate K2 risk |
| **P8** | C1 (55 CP at M6) | Track actual provider onboarding | Internal | If <30 → coverage problem |
| **P9** | E9 (launch cost $18K) | Reconcile actual spend vs budget | Internal | First real cost data point |
| **P10** | E4 (ops cost $2K/mo) | Track actual ops hours × rates | Internal | If >$3K → central cost model off |

### J.3. M6–M12: верифицировать до Seed Round

| Priority | Parameter(s) | Action | Source | Impact if wrong |
|----------|-------------|--------|--------|----------------|
| **P11** | F1 (OIR 0.44 at M12) | Calculate from product analytics | Internal | OIR trajectory = biggest P&L lever |
| **P12** | C4 (provider share 28% at M12) | Attribution tracking | Internal | Core business model assumption |
| **P13** | E2 (AI cost $0.70 at M6) | Actual cloud bills ÷ MAU | Internal | Optimization trajectory validated or not |
| **P14** | B4 (retention trajectory improving) | Cohort analysis M1 vs M3 vs M6 | Internal | Must show improvement trend for Seed Round |

### J.4. M12–M24: верифицировать до Series A

| Priority | Parameter(s) | Action | Source | Impact if wrong |
|----------|-------------|--------|--------|----------------|
| **P15** | D1 (WTP at $0.10/Credit) | WTP pilot results | Internal | No WTP = no revenue model |
| **P16** | F4 (cross-mall 4–14%) | Seed 2 attribution vs Seed 1 data | Internal | Cross-mall thesis validated or not |
| **P17** | E12 (Semi-Auto cost reductions) | Actual vs projected for seeds 3–5 | Internal | Expansion economics validated |
| **P18** | G2 (Semi-Auto triggers met) | Check 5 criteria at M18–24 | Internal | Expansion pace gated |

---

## K. SUMMARY STATISTICS

| Metric | Count |
|--------|-------|
| Total [H] parameters across all blocks | ~187 |

*Count method: unique parameters in registries of Constitution v1.2, Blocks 1 (Steps 1–2), 3, 4, 6, 7, 8 — deduplicated by parameter name. Approximate: some parameters appear in 2–3 blocks with slightly different granularity.*
| [H] parameters in this sheet (deduplicated, key) | 67 |
| [H proxy] parameters | 4 |
| [D] derived parameters | 5 |
| [H theory] (not verifiable — mathematical property) | 1 |
| Sources with status **FOUND** | 13 |
| Sources with status **NEED_SRC** | 17 |
| Sources with status **VERIFIED** | 0 (pre-launch) |
| **Total sources listed** | **30** (FOUND + NEED_SRC + VERIFIED) |
| **Critical priority** | 12 |
| **High priority** | 22 |
| **Medium priority** | 21 |
| **Low priority** | 11 |
| Pre-launch verifiable (public sources) | 5 (P1–P5) |
| M1–M6 verifiable (internal data) | 5 (P6–P10) |
| M6–M12 verifiable (internal) | 4 (P11–P14) |
| M12–M24 verifiable (internal) | 4 (P15–P18) |

**Verification pipeline:**
- Pre-launch: P1–P5 → FOUND → VERIFIED. Параметры в модели переходят [H] → [V]
- By M6: P6–P10 measured internally → VERIFIED. Параметры → [V] или [F]
- By M12: P11–P14 → VERIFIED. 14+ параметров с [V]/[F] — достаточно для Seed Round data room
- By M24: P15–P18 → VERIFIED. 18+ параметров — достаточно для Series A due diligence

*Note: [V] в Конституции = "Verified" (данные подтверждены источником). FOUND/NEED_SRC/VERIFIED — статусы верификации в этом документе. Не путать.*

---

*Cross-references: Constitution v1.2, Blocks 1, 3, 4, 6 v1.1, 7 v1.1, 8 v1.1 | Протокол: UNDE_Model_Constitution_v1.2*
