# UNDE Block 7 — Multi-Seed Cash Flow
## Dubai Network: 1→8 Seeds, 48-Month Model
### v1.1

---

## 0. Назначение

Помесячный cash flow всей Dubai-сети: 8 seeds по timeline Block 4 §G.3, с учётом staggered launches, cross-mall acceleration, mode transitions (Manual → Semi-Auto), central cost allocation, и Phase gating per seed. Horizon = 48 месяцев (M36 + 12 мес для payback visibility).

**Изменения v1.1 vs v1.0:**
- §J formula: Seed_Opex decomposed по компонентам (AI discount только к AI, mode mult раздельно по Ops/Onb/Srv)
- Central_Infra: добавлена явная формула MAX(500, $100 × MAU/1000) [H]
- Phase 1 "age < 12": маркировано как operational proxy [H] с mapping на Конституцию
- §H.4: Seasonality (Dubai ±20% footfall)
- §H.5: Combo downside scenarios (worst case: no breakeven >M72)
- §H.6: Launch velocity opex spike
- §G.4: ROI calculation post-breakeven
- §L: Evidence placeholders расширены с verification paths

**Зависимости:**
- Block 6 v1.1 (single-seed monthly P&L) — trajectory per seed
- Block 4 v1.1 (expansion model) — launch schedule, cost structures, cross-mall effects
- Block 3 v1.0 (network dynamics) — milestone snapshots
- UNDE_Model_Constitution_v1.2 — Phase gating rules

**Ключевое отличие от Block 6:** Block 6 = P&L одного изолированного seed. Block 7 = cash flow всей сети, включая: central costs ($23–30K/мес), tooling investments, staggered seed launches, mode-specific cost adjustments, cross-mall acceleration Revenue-Ready timing.

---

## A. МЕТОДОЛОГИЯ

### A.1. Seed Trajectory

Каждый seed следует Block 6 trajectory (Scenario P), смещённой по launch month. Seed age = global_month − launch_month + 1. При seed age 1–36 используются Block 6 данные; при age > 36 — M36 values (conservative hold).

### A.2. Cross-Mall Acceleration

Позднейшие seeds достигают Revenue-Ready быстрее (Block 4 §C.5):

| Seed | Mall | Launch | Mode | Revenue-Ready age | Revenue-Ready (global) | Source |
|------|------|--------|------|-------------------|----------------------|--------|
| #1 | Ibn Battuta | M1 | Manual | 33 мес | **M33** | Block 3 base case |
| #2 | Mall of Emirates | M10 | Manual | 31 мес | **M40** | 1 prior seed, minimal cross-mall [H] |
| #3 | Dubai Mall | M15 | Manual | 30 мес | **M44** | 2 prior seeds, Block 4 §C.5 [H] |
| #4 | City Centre Mirdif | M19 | Semi-Auto | 27 мес | **M45** | 4 prior seeds [H] |
| #5 | Dubai Marina Mall | M22 | Semi-Auto | 27 мес | **M48** | 4 prior seeds [H] |
| #6 | Dubai Hills Mall | M27 | Semi-Auto | 25 мес | **M51** | Cross-mall + chain coverage [H] |
| #7 | TBD | M30 | Semi-Auto | 24 мес | **M53** | [H] |
| #8 | TBD | M33 | Semi-Auto | 23 мес | **M55** | Block 4 §C.5 max acceleration [H] |

### A.3. Phase Gating per Seed

> **Operational proxy [H]:** Конституция привязывает фазы к метрикам сети (OIR, D30, PP count), не к возрасту seed. Однако для финансовой модели используется age-based proxy, т.к. Block 3 milestone snapshots показывают, что PP > 10 и Coverage > 50% достигаются не раньше M7–M8, а WTP eligibility (Network-Complete subset) — не раньше M12. Фактическое решение о WTP pilot принимается по метрикам, не по календарю.

| Phase | Condition (proxy) | Revenue | Конституция mapping |
|-------|-------------------|---------|---------------------|
| **Phase 1** | Seed age < 12 [H proxy] | $0 | Earn-only: PP < 10 или Coverage < 50% |
| **WTP Pilot** | Seed age ≥ 12, not Revenue-Ready [H proxy] | Rev capacity × 30% [H] | Network-Complete: OIR > 1.0, PP > 10, Coverage > 50% |

> **⚠️ WTP Pilot ≠ монетизация.** WTP pilot — B2B тестирование price per Credit с 3–5 providers. Users не затронуты: бесплатность сохраняется полностью. Revenue от WTP = non-baseline (Scenario P), не гарантированный поток. Baseline model (Scenario S) = $0 до Phase 2.
| **Phase 2** | Revenue-Ready (all thresholds met) | Full rev capacity | All thresholds incl. D30 > 40% |

### A.4. Cost Model

**Local costs** per seed follow Block 6, adjusted by operating mode (Block 4 §B.2):

| Component | Manual | Semi-Auto | Adjustment |
|-----------|--------|-----------|------------|
| Local Ops | 1.0× Block 6 | 0.5× | Dashboard + playbook replace field team |
| Onboarding | 1.0× Block 6 | 0.4× | Chain coverage + dashboard self-serve |
| Server/Other | 1.0× Block 6 | 0.65× | Shared infra |

**AI cost** includes scale discount (Block 4 §B.2):

| Active seeds | Discount | Source |
|-------------|---------|--------|
| 1 | 0% | Baseline |
| 2–4 | 4% | Shared caching begins [H] |
| 5–8 | 8% | Batch inference across seeds [H] |
| 9–15 | 15% | Full optimization [H] |

**Central costs** (Block 4 §B.2):

| Active seeds | Central Team | Central Infra | Total Central |
|-------------|-------------|---------------|---------------|
| 1–3 | $23,000/mo | MAX($500, $100 × MAU/1000) [H] | ~$23.5K |
| 4–6 | $27,000/mo | MAX($500, $100 × MAU/1000) [H] | ~$28–30K |
| 7–8+ | $30,000/mo | MAX($500, $100 × MAU/1000) [H] | ~$34–39K |

*Central Infra = $100 per 1,000 aggregate MAU (CDN, DB replication, monitoring, CI/CD). Floor $500. At 80K MAU → $8K infra.*

**One-time costs:**

| Category | Amount | When |
|----------|--------|------|
| Manual seed launch | $18,000 | Seeds 1–2 (Block 6 v1.1 §A.3) |
| Semi-Auto-ready seed launch | $14,000 | Seed 3 (transition period) |
| Semi-Auto seed launch | $4,000 | Seeds 4–8 (Block 4 §A.4) |
| Tooling: monitoring dashboard + playbook | $7,000 | M12 (before seed 2 launch) |
| Tooling: self-serve dashboard + feed validation | $23,000 | M14 (before seed 3) |
| **Total one-time** | **$100,000** | |

---

## B. PHASE MAP — SEED × MONTH


```
Seed  Mall              Launch   |----- Phase 1 -----|---- WTP Pilot ----|--- Phase 2 --->
                                 M1    M12    M24    M36    M48
  #1   Ibn Battuta          M1    ···········wwwwwwwwwwwwwwwwwwwww████████████████
  #2   Mall of Emirates     M10            ···········wwwwwwwwwwwwwwwwwww█████████
  #3   Dubai Mall           M15                 ···········wwwwwwwwwwwwwwwwww█████
  #4   City Centre Mirdif   M19                     ···········wwwwwwwwwwwwwww████
  #5   Dubai Marina Mall    M22                        ···········wwwwwwwwwwwwwww█
  #6   Dubai Hills Mall     M27                             ···········wwwwwwwwwww
  #7   Seed #7              M30                                ···········wwwwwwww
  #8   Seed #8              M33                                   ···········wwwww
                                 |    |    |    |    |
                                 M1   M12  M24  M36  M48
Legend: · = Phase 1 ($0)   w = WTP Pilot (30%)   █ = Phase 2 (full)
```

**Наблюдение:** К M36 только Seed #1 в Phase 2. К M48 — 5 из 8. Все 8 seeds в Phase 2 к ~M55.

---

## C. MONTHLY CASH FLOW (48 MONTHS)

> Compact view: каждая строка = 1 месяц. Seeds = количество активных seeds. Rev = total actual revenue (Phase-gated). Opex = local + central. OT = one-time (launches + tooling). Net = Rev − Opex − OT.


| M | Seeds | MAU | Rev | Local Opex | Central | **Opex** | OT | **Net CF** | **Cum CF** |
|---|-------|------|-----|-----------|---------|---------|-----|----------|----------|
| 1 | 1 | 800 | $0 | $5,889 | $23,500 | $29,389 | $18,000 | $-47,389 | $-47,389 |
| 2 | 1 | 2,000 | $0 | $5,886 | $23,500 | $29,386 | $0 | $-29,386 | $-76,775 |
| 3 | 1 | 3,530 | $0 | $5,093 | $23,500 | $28,593 | $0 | $-28,593 | $-105,368 |
| 4 | 1 | 3,655 | $0 | $5,145 | $23,500 | $28,645 | $0 | $-28,645 | $-134,013 |
| 5 | 1 | 3,922 | $0 | $5,331 | $23,500 | $28,831 | $0 | $-28,831 | $-162,844 |
| 6 | 1 | 4,054 | $0 | $5,403 | $23,500 | $28,903 | $0 | $-28,903 | $-191,747 |
| 7 | 1 | 4,171 | $0 | $5,485 | $23,500 | $28,985 | $0 | $-28,985 | $-220,732 |
| 8 | 1 | 4,420 | $0 | $5,760 | $23,500 | $29,260 | $0 | $-29,260 | $-249,992 |
| 9 | 1 | 4,544 | $0 | $5,880 | $23,500 | $29,380 | $0 | $-29,380 | $-279,372 |
| 10 | 2 | 5,445 | $0 | $11,682 | $23,500 | $35,182 | $18,000 | $-53,182 | $-332,554 |
| 11 | 2 | 6,872 | $0 | $11,861 | $23,600 | $35,461 | $0 | $-35,461 | $-368,015 |
| 12 | 2 | 8,507 | $945 | $11,125 | $23,800 | $34,925 | $7,000 | $-40,980 | $-408,995 |
| 13 | 2 | 8,741 | $1,033 | $11,220 | $23,800 | $35,020 | $0 | $-33,987 | $-442,982 |
| 14 | 2 | 9,230 | $1,218 | $11,578 | $23,900 | $35,478 | $23,000 | $-57,260 | $-500,242 |
| 15 | 3 | 10,526 | $1,503 | $17,816 | $24,000 | $41,816 | $14,000 | $-54,313 | $-554,555 |
| 16 | 3 | 12,222 | $1,788 | $18,130 | $24,200 | $42,330 | $0 | $-40,542 | $-595,097 |
| 17 | 3 | 14,250 | $1,973 | $17,738 | $24,400 | $42,138 | $0 | $-40,165 | $-635,262 |
| 18 | 3 | 14,629 | $2,062 | $17,980 | $24,400 | $42,380 | $0 | $-40,318 | $-675,580 |
| 19 | 4 | 15,950 | $2,388 | $23,082 | $28,500 | $51,582 | $4,000 | $-53,194 | $-728,774 |
| 20 | 4 | 17,856 | $3,068 | $23,569 | $28,700 | $52,269 | $0 | $-49,201 | $-777,975 |
| 21 | 4 | 20,149 | $5,063 | $23,276 | $29,000 | $52,276 | $0 | $-47,213 | $-825,188 |
| 22 | 5 | 22,002 | $6,200 | $28,150 | $29,200 | $57,350 | $4,000 | $-55,150 | $-880,338 |
| 23 | 5 | 24,217 | $7,065 | $28,711 | $29,400 | $58,111 | $0 | $-51,046 | $-931,384 |
| 24 | 5 | 26,533 | $7,677 | $28,274 | $29,600 | $57,874 | $0 | $-50,197 | $-981,581 |
| 25 | 5 | 27,584 | $8,183 | $28,899 | $29,700 | $58,599 | $0 | $-50,416 | $-1,031,997 |
| 26 | 5 | 28,916 | $9,774 | $29,736 | $29,800 | $59,536 | $0 | $-49,762 | $-1,081,759 |
| 27 | 6 | 30,933 | $10,664 | $35,105 | $30,000 | $65,105 | $4,000 | $-58,441 | $-1,140,200 |
| 28 | 6 | 33,494 | $11,887 | $35,758 | $30,300 | $66,058 | $0 | $-54,171 | $-1,194,371 |
| 29 | 6 | 36,756 | $13,313 | $36,012 | $30,600 | $66,612 | $0 | $-53,299 | $-1,247,670 |
| 30 | 7 | 39,086 | $15,815 | $41,685 | $33,900 | $75,585 | $4,000 | $-63,770 | $-1,311,440 |
| 31 | 7 | 41,897 | $17,451 | $42,483 | $34,100 | $76,583 | $0 | $-59,132 | $-1,370,572 |
| 32 | 7 | 45,184 | $19,060 | $42,567 | $34,500 | $77,067 | $0 | $-58,007 | $-1,428,579 |
| 33 | 8 | 48,107 | $47,496 | $48,463 | $34,800 | $83,263 | $4,000 | $-39,767 | $-1,468,346 |
| 34 | 8 | 51,998 | $52,142 | $49,801 | $35,100 | $84,901 | $0 | $-32,759 | $-1,501,105 |
| 35 | 8 | 56,012 | $56,209 | $50,234 | $35,600 | $85,834 | $0 | $-29,625 | $-1,530,730 |
| 36 | 8 | 58,540 | $59,393 | $51,594 | $35,800 | $87,394 | $0 | $-28,001 | $-1,558,731 |
| 37 | 8 | 60,985 | $61,396 | $52,974 | $36,000 | $88,974 | $0 | $-27,578 | $-1,586,309 |
| 38 | 8 | 62,676 | $63,994 | $53,810 | $36,200 | $90,010 | $0 | $-26,016 | $-1,612,325 |
| 39 | 8 | 64,133 | $65,664 | $54,439 | $36,400 | $90,839 | $0 | $-25,175 | $-1,637,500 |
| 40 | 8 | 66,331 | $89,648 | $55,615 | $36,600 | $92,215 | $0 | $-2,567 | $-1,640,067 |
| 41 | 8 | 69,039 | $95,137 | $57,096 | $36,900 | $93,996 | $0 | $+1,141 | $-1,638,926 |
| 42 | 8 | 72,196 | $100,972 | $58,659 | $37,200 | $95,859 | $0 | $+5,113 | $-1,633,813 |
| 43 | 8 | 75,349 | $106,445 | $60,182 | $37,500 | $97,682 | $0 | $+8,763 | $-1,625,050 |
| 44 | 8 | 77,822 | $132,229 | $61,329 | $37,700 | $99,029 | $0 | $+33,200 | $-1,591,850 |
| 45 | 8 | 80,088 | $153,724 | $62,302 | $38,000 | $100,302 | $0 | $+53,422 | $-1,538,428 |
| 46 | 8 | 82,521 | $159,555 | $63,447 | $38,200 | $101,647 | $0 | $+57,908 | $-1,480,520 |
| 47 | 8 | 85,633 | $166,351 | $64,958 | $38,500 | $103,458 | $0 | $+62,893 | $-1,417,627 |
| 48 | 8 | 88,850 | $190,495 | $66,405 | $38,800 | $105,205 | $0 | $+85,290 | $-1,332,337 |

---

## D. QUARTERLY SUMMARY


| Quarter | Period | Seeds | Avg MAU | Revenue | Opex | One-time | **Net CF** | **Cum CF** |
|---------|--------|-------|---------|---------|------|----------|----------|----------|
| Q1 | M1–M3 | 1 | 2,110 | $0 | $87,368 | $18,000 | $-105,368 | $-105,368 |
| Q2 | M4–M6 | 1 | 3,877 | $0 | $86,379 | $0 | $-86,379 | $-191,747 |
| Q3 | M7–M9 | 1 | 4,378 | $0 | $87,625 | $0 | $-87,625 | $-279,372 |
| Q4 | M10–M12 | 2 | 6,941 | $945 | $105,568 | $25,000 | $-129,623 | $-408,995 |
| Q5 | M13–M15 | 3 | 9,499 | $3,754 | $112,314 | $37,000 | $-145,560 | $-554,555 |
| Q6 | M16–M18 | 3 | 13,700 | $5,823 | $126,848 | $0 | $-121,025 | $-675,580 |
| Q7 | M19–M21 | 4 | 17,985 | $10,519 | $156,127 | $4,000 | $-149,608 | $-825,188 |
| Q8 | M22–M24 | 5 | 24,250 | $20,942 | $173,335 | $4,000 | $-156,393 | $-981,581 |
| Q9 | M25–M27 | 6 | 29,144 | $28,621 | $183,240 | $4,000 | $-158,619 | $-1,140,200 |
| Q10 | M28–M30 | 7 | 36,445 | $41,015 | $208,255 | $4,000 | $-171,240 | $-1,311,440 |
| Q11 | M31–M33 | 8 | 45,062 | $84,007 | $236,913 | $4,000 | $-156,906 | $-1,468,346 |
| Q12 | M34–M36 | 8 | 55,516 | $167,744 | $258,129 | $0 | $-90,385 | $-1,558,731 |
| Q13 | M37–M39 | 8 | 62,598 | $191,054 | $269,823 | $0 | $-78,769 | $-1,637,500 |
| Q14 | M40–M42 | 8 | 69,188 | $285,757 | $282,070 | $0 | $+3,687 | $-1,633,813 |
| Q15 | M43–M45 | 8 | 77,753 | $392,398 | $297,013 | $0 | $+95,385 | $-1,538,428 |
| Q16 | M46–M48 | 8 | 85,668 | $516,401 | $310,310 | $0 | $+206,091 | $-1,332,337 |


**First positive quarter: Q14 (M40–M42).** Cumulative не выходит в positive в пределах M48.

---

## E. ANNUAL P&L


| Year | Period | Seeds | Total Rev | Total Opex | One-time | **Net** | **Cum** |
|------|--------|-------|-----------|-----------|----------|---------|---------|
| Y1 | M1–M12 | 2 | $945 | $366,940 | $43,000 | $-408,995 | $-408,995 |
| Y2 | M13–M24 | 5 | $41,038 | $568,624 | $45,000 | $-572,586 | $-981,581 |
| Y3 | M25–M36 | 8 | $321,387 | $886,537 | $12,000 | $-577,150 | $-1,558,731 |
| Y4 | M37–M48 | 8 | $1,385,610 | $1,159,216 | $0 | $+226,394 | $-1,332,337 |


**Y4 = первый profit-positive год.** Inflection: seeds #2–#3 входят в Phase 2 (M40, M44), revenue рamp ускоряется.

---

## F. INVESTMENT & RUNWAY ANALYSIS

### F.1. Investment Profile

| Метрика | Значение |
|---------|---------|
| Peak cumulative burn | **$-1,640,067** (M40) |
| Total one-time investments | $100,000 |
| First positive monthly CF | M41 |
| Monthly margin at M48 | +$85,290 |
| Est. cumulative breakeven | **~M60** (projection) |

### F.2. Fundraising Runway

| Raise Amount | Runway (months) | Reaches M | Status at end |
|-------------|----------------|-----------|---------------|
| $500K | ~14 мес | M14 | ❌ Before seed #3 launch |
| $750K | ~20 мес | M20 | ❌ Before Semi-Auto transition |
| $1.0M | ~25 мес | M25 | ⚠️ 5 seeds live, no Phase 2 yet |
| $1.5M | ~34 мес | M34 | ⚠️ Seed #1 entering Phase 2, revenue starting |
| **$2.0M** | **48+ мес** | **M48+** | **✓ Network cash-flow positive, 5 seeds Phase 2** |

*Runway = месяц, когда cash balance (raise + cumulative CF) падает ниже $0. Не включает выручку от следующих раундов.*

### F.3. Staged Fundraising Scenario

| Round | Timing | Amount | Purpose | Milestone to unlock next round |
|-------|--------|--------|---------|-------------------------------|
| **Pre-Seed** | M0 | $500K | Seeds 1–2 + tooling | Seed 1 MAU > 3K, 10+ PP_elig, retention signal |
| **Seed** | M12–M15 | $1.0M | Seeds 3–5 + Semi-Auto | Seed 1 OIR > 0.5, Seed 2 MAU > 2K, WTP validation |
| **Series A** | M24–M30 | $3–5M | Seeds 6–8 + Market 2 prep | Network MAU > 30K, Phase 2 revenue proven, unit economics validated |

*Pre-Seed + Seed = $1.5M → runway to ~M34. Series A bridges to network profitability.*

### F.4. Burn Rate Profile


| Period | Avg monthly burn | Avg monthly revenue | Net burn rate |
|--------|-----------------|--------------------|--------------| 
| Y1 (M1–M12) | $34,161 | $78 | $-34,083 |
| Y2 (M13–M24) | $51,135 | $3,419 | $-47,716 |
| Y3 (M25–M36) | $74,878 | $26,782 | $-48,096 |
| Y4 (M37–M48) | $96,601 | $115,467 | $+18,866 |


### F.5. Central Cost Leverage

Central cost = фиксированная база ($23–30K/мес). При 1 seed = 81% opex. При 8 seeds = 37% opex. **Каждый новый seed разбавляет central cost burden.**


| Global month | Seeds | Central cost | Central % of opex | Central / seed |
|-------------|-------|-------------|-------------------|----------------|
| M6 | 1 | $23,500 | 81% | $23,500 |
| M12 | 2 | $23,800 | 68% | $11,900 |
| M18 | 3 | $24,400 | 58% | $8,133 |
| M24 | 5 | $29,600 | 51% | $5,920 |
| M30 | 7 | $33,900 | 45% | $4,843 |
| M36 | 8 | $35,800 | 41% | $4,475 |
| M42 | 8 | $37,200 | 39% | $4,650 |
| M48 | 8 | $38,800 | 37% | $4,850 |


---

## G. EXTENDED PROJECTION (M49–M60)

> Beyond M48: not modeled помесячно, projected from M48 run rate + Phase 2 entries.

### G.1. Remaining Phase 2 Entries

| Seed | Revenue-Ready | Additional monthly margin (est.) |
|------|-------------|--------------------------------|
| #6 (Dubai Hills) | M51 | +$15,000 [H] |
| #7 | M53 | +$15,000 [H] |
| #8 | M55 | +$15,000 [H] |

*Estimate: each Phase 2 seed adds ~$15K/mo net margin at entry (rev capacity ~$20K − local opex ~$5K). Ramps to ~$30K/mo at maturity.*

### G.2. Projection

| Global month | Phase 2 seeds | Est. monthly margin | Est. cumulative |
|-------------|--------------|--------------------|-----------------| 
| M48 | 5 of 8 | +$85K | −$1,332K |
| M51 | 6 of 8 | +$100K | −$1,050K |
| M54 | 7 of 8 | +$115K | −$705K |
| M55 | 8 of 8 | +$130K | −$575K |
| **M60** | **8 of 8** | **+$130K** | **~+$50K** |

**Est. cumulative breakeven: ~M60 (Year 5).** Post-breakeven margin: ~$130K/mo → ~$1.56M/year.

### G.4. ROI Calculation

| Metric | Scenario P (base) |
|--------|------------------|
| Total cumulative investment at peak (M40) | $1.64M |
| Annualized margin at M55 (all Phase 2) | $1.56M/year |
| **ROI Year 1 post-breakeven (M60–M72)** | **~95%** |
| **ROI Year 1 post-peak-margin (M55–M67)** | **~1.5×** ($1.56M / $1.03M net outstanding) |
| Estimated 5-year total return (M1–M72) | ~$1.6M net positive |

*ROI = annualized margin ÷ outstanding investment. At $130K/mo and ~$1M outstanding at M55, payback completes M60. Following 12 months generate ~$1.56M on top.*

**For investor framing:** $1.64M peak investment → $1.56M/year run-rate at network maturity = **<1 year payback post-maturity**. IRR ~35–45% (depending on timing of capital deployment).

> **⚠️ Scope note:** ROI 1.5× и IRR 35–45% — investor narrative metrics, не operational parameters. Эти цифры следует выносить в Investor Appendix / Pitch Deck, не в core cashflow model. Core model оперирует monthly margin и cumulative CF — метриками, которые можно верифицировать операционно.

### G.3. Scenario S (Strict) Comparison

| Метрика | Scenario P (WTP) | Scenario S (Strict) | Delta |
|---------|-----------------|--------------------|----|
| Total WTP revenue (M1–M48) | $408K | $0 | −$408K |
| Peak cumulative burn | −$1.64M | −$2.05M | −$408K deeper |
| Required total investment | ~$1.7M | ~$2.1M | +$400K |
| Cumulative breakeven | ~M60 | ~M64 | +4 мес later |

**WTP pilots сокращают peak burn на $400K — существенная разница для fundraising.**

---

## H. SENSITIVITY ANALYSIS

### H.1. Expansion Pace

| Scenario | Seeds by M36 | Peak burn | Monthly breakeven | Cum breakeven |
|----------|-------------|-----------|-------------------|---------------|
| **Slow (4 seeds)** | 4 | ~$800K | ~M38 | ~M52 |
| **Base (8 seeds)** | 8 | ~$1.64M | ~M41 | ~M60 |
| **Aggressive (12 seeds)** | 12 | ~$2.4M | ~M39 | ~M56 |

*Aggressive: +4 seeds в Semi-Auto M25–M36. Faster monthly breakeven (more Phase 2 revenue sooner) but deeper peak burn. Requires $2.5M+ investment.*

### H.2. Phase 2 Acceleration

Если retention достигает 40% быстрее (strong PMF) → seeds enter Phase 2 раньше:

| Scenario | Seed #1 Phase 2 | Avg Revenue-Ready age | Peak burn | Cum breakeven |
|----------|----------------|---------------------|-----------|---------------|
| **Slow retention** | M36 | 35 мес | ~$1.9M | ~M68 |
| **Base** | M33 | 28 мес avg | ~$1.64M | ~M60 |
| **Fast retention** | M27 | 23 мес avg | ~$1.2M | ~M48 |

*Fast retention = most powerful lever: −$440K peak burn, −12 months to breakeven.*

### H.3. Central Cost Scenarios

| Scenario | Central team/mo | Peak burn | Impact |
|----------|----------------|-----------|--------|
| **Lean** ($18K team) | $18K + infra | ~$1.4M | −$240K (fewer FTEs early, outsource some ops) |
| **Base** ($23–30K) | As modeled | ~$1.64M | — |
| **Heavy** ($35K from M1) | $35K + infra | ~$1.9M | +$260K (premature team scaling) |

### H.4. Seasonality (Dubai)

Dubai retail footfall varies ~±20% seasonally [H]: peak Oct–Mar (tourism season, cooler weather), trough Jun–Aug (summer heat, resident exodus).

| Scenario | Impact on model | Revenue effect | Opex effect |
|----------|----------------|----------------|-------------|
| **Summer trough** (3 мес/год, −20% footfall) | N_organic −20%, MAU −12–15% | WTP/Phase 2 rev −15% in those months | AI cost −12–15% (lower MAU) |
| **Peak season** (3 мес/год, +20% footfall) | N_organic +20%, MAU +10–12% | Rev +12% | AI cost +10–12% |
| **Net annual effect** | ~symmetric | −2–3% vs non-seasonal model [D] | Roughly neutral |

*Net effect small (±20% for 3 months each ≈ cancels). Tactical implication: **launch seeds in Q4 (Oct)** to ride peak season through M1–M6, when early traction is critical. Avoid summer launches (M6–M8).*

**Annual cash flow variance from seasonality:** ±$15–20K per seed. At 8 seeds: ±$120–160K annual variance. **Does not change structural conclusions** but affects monthly burn rate planning.

### H.5. Combo Downside Scenarios

| Scenario | Variables | Peak burn | Monthly breakeven | Cum breakeven |
|----------|----------|-----------|-------------------|---------------|
| **Base** | As modeled | $1.64M | M41 | ~M60 |
| **Downside A:** Slow retention + high central | r×0.8, Central $30K from M1 | ~$2.1M | M46 | ~M70 |
| **Downside B:** Low footfall + slow retention | FF 1.25M, r×0.8, Phase 2 +6 мес | ~$2.0M | M48 | ~M68 |
| **Worst case:** All downsides | FF 1.25M, r×0.7, Central $30K, AI×1.2 | ~$2.5M | M52+ | **>M72** |

*Worst case = structural risk. If retention stays below 30% AND footfall drops AND costs spike → network never reaches breakeven within reasonable horizon. **Kill criterion: if Seed #1 D30 < 15% at M12 → reassess entire model.***

**Defensive policy (downside scenarios):**
- **Downside A/B:** Cap launches at 6 seeds (defer #7–#8). Saves ~$8K one-time + $10K/mo local opex. Peak burn drops ~$200K.
- **Worst case:** Cap launches at 5 seeds, pause at Semi-Auto (no Self-Serve investment). Reduces peak burn to ~$2.1M. If Seed #1 not in Phase 2 by M36 → freeze expansion, operate on sustain-only budget.

### H.6. Launch Velocity Opex Spike

High-velocity periods (2+ seeds launching within 3 months) create temporary opex spikes:

| Effect | Cause | Size | Duration |
|--------|-------|------|----------|
| Team context-switching | BD + ops split across 2 simultaneous launches | +10–15% local opex [H] | 2–3 months |
| Onboarding queue delays | Provider integration bottleneck | +5–10% onboarding cost [H] | 1–2 months |
| QA overhead | Multiple feeds going live, quality control strain | +$500–1,000/seed [H] | Launch month only |

*Modeled impact: ~$2–4K additional opex per high-velocity quarter. Total over 48 months: ~$15–20K. **Not material** vs $1.6M total burn, but explains month-to-month variance.*

---

## I. STRUCTURAL FINDINGS

### I.1. Central cost = dominant expense in Year 1

При 1 seed: central = 81% of total opex. Seed revenue is irrelevant vs central burden. **The first seed doesn't need to be profitable — it needs to prove the model fast enough to justify multi-seed investment.** Single-seed economics (Block 6) — misleading without central context.

### I.2. Seed velocity = second most important lever

Faster seed launches → faster central cost dilution → earlier network breakeven. But premature launches (before playbook proven) = wasted $18K/seed + team distraction. **Optimal: prove with 2 seeds, then accelerate.**

### I.3. Phase 2 timing dominates everything (again)

Block 6 finding confirmed at network level: Phase 2 trigger month is the #1 sensitivity variable. Fast retention (Phase 2 at M27 vs M33) = $440K less peak burn and 12 months earlier breakeven.

### I.4. WTP pilots are not optional

$408K difference between Scenario P and S. WTP pilots from M12 should be treated as a strategic imperative, not an optional experiment. They fund ~25% of the gap.

### I.5. Staged fundraising is the only viable path

$2M upfront is possible but risky (48 months of blind faith). Staged approach (Pre-Seed $500K → Seed $1M → Series A $3–5M) de-risks for investors and forces milestone discipline.

### I.6. Year 4 inflection is real

Y4 = +$226K net. By M55 (all Phase 2): +$130K/mo = $1.56M/year. Network payback at ~M60. **Post-payback economics are strong — the question is surviving to get there.**

---

## J. СКВОЗНЫЕ ФОРМУЛЫ

```
# Per-seed (from Block 6, offset by launch month)
Seed_Rev(i, t)   = Block6_Rev_P(seed_age(i,t))  × Phase_gate(i,t)
seed_age(i, t)   = t − launch_month(i) + 1

# Per-seed opex (component-level, §A.4)
Seed_AI(i, t)    = Block6_AI(seed_age)     × (1 − AI_scale_discount(N_active(t)))
Seed_Ops(i, t)   = Block6_Ops(seed_age)    × Mode_ops_mult(mode_i)
Seed_Onb(i, t)   = Block6_Onboard(seed_age)× Mode_onb_mult(mode_i)
Seed_Srv(i, t)   = Block6_Server(seed_age) × Mode_srv_mult(mode_i)
Seed_Opex(i, t)  = Seed_AI + Seed_Ops × V_ops(t) + Seed_Onb × V_onb(t) + Seed_Srv + Launch_spike(seed_age)

# Mode multipliers (§A.4):
#   Manual:    ops=1.0, onb=1.0, srv=1.0
#   Semi-Auto: ops=0.5, onb=0.4, srv=0.65
# AI_scale_discount applies ONLY to AI component (not ops/onboard/server)

# Launch velocity spike multipliers (§H.6, optional):
#   V_ops(t)  = 1.0 if ≤1 seed launching in quarter; 1.10–1.15 if 2+ [H]
#   V_onb(t)  = 1.0 if ≤1 seed launching in quarter; 1.05–1.10 if 2+ [H]
#   Default (base model): V_ops = V_onb = 1.0 (spike not in baseline, sensitivity only)

Phase_gate (operational proxy [H], see §A.3):
  Phase 1:  seed_age < 12 (proxy for pre-WTP-eligibility)  → $0
  WTP:      seed_age ≥ 12 AND t < Revenue_Ready(i)         → Rev_cap × 0.30
  Phase 2:  t ≥ Revenue_Ready(i)                            → Rev_cap

# Network aggregation
Total_Rev(t)     = Σ Seed_Rev(i, t)     for all active seeds
Total_Local(t)   = Σ Seed_Opex(i, t)    for all active seeds
Central(t)       = Central_Team(N_active) + Central_Infra(Total_MAU)
Central_Infra(t) = MAX(500, FLOOR(Total_MAU(t) / 1000) × 100)   [H]
                   # $100 per 1,000 MAU, floor $500. Covers: CDN, DB, monitoring, CI/CD
Total_Opex(t)    = Total_Local(t) + Central(t)
One_Time(t)      = Σ launch_cost(i)  if seed_i launches at t  +  tooling(t)
Net_CF(t)        = Total_Rev(t) − Total_Opex(t) − One_Time(t)
Cum_CF(t)        = Σ Net_CF(1..t)
```

---

## K. PARAMETER REGISTRY

| Параметр | Значение | Тип | Источник |
|----------|---------|-----|----------|
| Seed launch schedule | M1/M10/M15/M19/M22/M27/M30/M33 | [H] | Block 4 §G.3 |
| Revenue-Ready acceleration | 33→23 мес by seed # | [H] | Block 4 §C.5 |
| Manual launch cost | $18,000 | [H] | Block 6 v1.1 §A.3 |
| Semi-Auto launch cost | $4,000 | [H] | Block 4 §A.4 |
| Tooling investment | $30,000 total | [H] | Block 4 §A.4 |
| Central Team (1–3 seeds) | $23,000/mo | [H] | Block 4 §B.2 |
| Central Team (4–6 seeds) | $27,000/mo | [H] | Block 4 §B.2 (interpolated) |
| Central Team (7+ seeds) | $30,000/mo | [H] | Block 4 §B.2 |
| AI scale discount (5–8 seeds) | 8% | [H] | Block 4 §B.2 |
| Semi-Auto local ops multiplier | 0.5× | [H/D] | Block 4 §B.2 ratio |
| Semi-Auto onboard multiplier | 0.4× | [H/D] | Block 4 §B.2 ratio |
| WTP pilot rate | 30% of capacity | [H] | Block 3 §G.3 |
| WTP eligibility | Seed age ≥ 12 | [H] | Block 6 §A.5 |
| S-curve steepness (from Block 6) | k=6 | [H] | Block 6 v1.1 §A.1 |
| Central Infra formula | MAX(500, $100 × MAU/1000) | [H] | **Block 7 v1.1** §A.4, §J |
| Seasonality variance (Dubai) | ±20% footfall, ±15% revenue | [H] | **Block 7 v1.1** §H.4 |
| Launch velocity spike | +10–15% local opex during overlap | [H] | **Block 7 v1.1** §H.6 |
| Phase 1 age proxy | seed_age < 12 ≈ pre-WTP-eligibility | [H proxy] | **Block 7 v1.1** §A.3 |

---

## L. EVIDENCE PLACEHOLDERS

| Reference | Used in | Status | Placeholder source | Verification path |
|-----------|---------|--------|-------------------|-------------------|
| Dubai mall visitor overlap (2.3 malls/mo) | §A.2 | **TBD → [V]** | Emaar Malls Annual Report 2023, Majid Al Futtaim Holding sustainability report | Request data from mall management during BD outreach |
| Dubai retail seasonality (±20%) | §H.4 | **TBD → [V]** | Dubai Statistics Center Monthly Trade Index, KPMG GCC Consumer Pulse Survey 2024 | Downloadable from DSC.gov.ae |
| Semi-Auto cost reduction benchmarks | §A.4 | **TBD → [V]** | Internal: post-launch reconciliation Seed #1 vs #2 | Available after M12 |
| AI inference scale discount (8% at 5 seeds) | §A.4 | **TBD → [V]** | OpenAI volume pricing tiers (>$1K/mo = 20% discount), Anthropic committed-use discounts, AWS Bedrock reserved capacity | Public pricing pages + sales team quotes |
| Central team cost (Dubai FTEs) | §A.4 | **TBD → [V]** | GulfTalent Salary Survey 2024, Bayt.com UAE salary index, Glassdoor Dubai tech salaries | Cross-reference 3 sources |
| Seed launch cost actual | §A.4 | **TBD → [V]** | Seed #1 post-launch financial reconciliation | Available M3+ |
| Revenue-Ready timing validation | §A.2 | **TBD → [V]** | Seed #1 D30 retention curve (M6+), provider growth rate vs model | Tracked in traffic-light dashboard |
| Mall footfall baselines | §C (all rows) | **TBD → [V]** | Occupi / RetailNext annual mall traffic reports, Emaar investor presentations | Request via mall partnership agreements |

*Priority for [V]: items 1, 4, 5, 8 can be partially verified before launch via public sources. Items 2, 3, 6, 7 require operational data (M3+ for costs, M6+ for retention).*

---

*Inputs: Block 6 v1.1, Block 4 v1.1, Block 3 v1.0 | Протокол: UNDE_Model_Constitution_v1.2*