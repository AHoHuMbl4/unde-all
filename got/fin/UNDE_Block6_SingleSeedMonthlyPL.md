# UNDE Block 6 — Single Seed Monthly P&L
## Помесячная модель (36 строк), Ibn Battuta Mall
### v1.1

---

## 0. Назначение

Помесячная разбивка P&L одного Local Seed (Ibn Battuta Mall) на 36 месяцев. Разворачивает milestone snapshots Block 3 §D.1 + §G.1–G.5 в непрерывную помесячную линию. Два сценария монетизации (Strict и WTP Pilots). Sensitivity analysis по 5 ключевым переменным.

**Зависимости:**
- Inputs: Block 1 Steps 1–2 (Unit Economics), Block 3 (Network Dynamics v1.0)
- Протокол: UNDE_Model_Constitution_v1.2
- Key Block 3 outputs: milestone snapshots M3/M6/M9/M12/M18/M24/M30/M36

**Что Block 6 делает и не делает:**
- Block 6 **не добавляет новых механик или структурных гипотез**. Все параметры наследуются из Blocks 1–4.
- Block 6 **фиксирует [H]-траектории** для P&L: помесячную эволюцию AI cost/MAU, Ops, Server, Price per Credit — параметров, заданных в Block 3 §G.1 и Block 4 §B.2 как milestone points, но не разложенных помесячно.
- Список всех используемых [H]-траекторий — в §I (Parameter Registry).

**Изменения v1.1 vs v1.0:**
- Интерполяция: logistic S-curve (вместо линейной) для growth metrics (MAU, PP, N_provider, N_viral)
- Launch spike: M1–M2 дополнительные $3K/$2K opex (field team overlap) [H]
- One-time cost: пересмотрен с $23K до **$18K** — устранён двойной учёт с monthly onboard
- PP → PP_elig (Phase 1): явное указание, что PP в Phase 1 = eligible, не paying
- Footfall sensitivity: добавлен downside 1.25M [H]
- Payback: расширен до ROI calc post-Phase 2

---

## A. МЕТОДОЛОГИЯ

### A.1. Интерполяция: Logistic S-curve

Block 3 предоставляет milestone snapshots на: **M3, M6, M9, M12, M18, M24, M30, M36**. M1–M2 из Block 4 §A.5.

**Линейная интерполяция** (v1.0) предполагает равномерный рост между milestones. Реальная динамика — S-curve: медленный старт (освоение), быстрый рост (тraction), замедление (насыщение).

**v1.1 использует logistic S-curve** для growth metrics (PP, r, N_provider, N_viral, Revenue capacity):

```
f(t) = v_lo + (v_hi − v_lo) × σ_norm(t)
σ_norm(t) = (σ(t) − σ(0)) / (σ(1) − σ(0))
σ(t) = 1 / (1 + e^{−k(t−0.5)}),  k = 6
```

**Линейная** остаётся для cost metrics (AI cost/MAU, Ops, Server) — оптимизация AI cost происходит постепенно, не S-curve.

**Практическое отличие S-curve от linear:**

| Месяц | N_provider (S-curve) | N_provider (linear) | Delta |
|-------|---------------------|-------------------|-------|
| M4 | 318 | 351 | −33 (slower early) |
| M8 | 835 | 807 | +28 (faster mid) |
| M15 | 1,535 | 1,535 | 0 (midpoint) |
| M20 | 2,063 | 2,133 | −70 (slower plateau approach) |

На anchor points (M3, M6, M12 и т.д.) значения **идентичны** — S-curve проходит через все canonical milestones Block 3. Расхождение только между ними.

### A.2. Launch Spike (M1–M2)

Block 4 §A.4 decomposition показывает overlap field team и activation campaigns в первые 6 недель. Модель v1.0 не учитывала этот временной пик:

| Месяц | Дополнительный opex | Источник | Что входит |
|-------|-------------------|----------|-----------|
| M1 | +$3,000 [H] | Block 4 §A.4 | Field team overlap (launch + sustain parallel), activation materials |
| M2 | +$2,000 [H] | Block 4 §A.4 | Tail of activation campaign, QR material refresh |
| M3+ | $0 | — | Seed переходит в sustain mode |

### A.3. One-Time Launch Cost (пересмотрен)

**Проблема v1.0:** One-time $23K (Block 1 Step 1 §E) включал "$15K Provider outreach & onboarding". Monthly opex включает Onboard = PP × $1,000/30 мес. При PP=15 → $15K за 30 месяцев = та же сумма. **Двойной учёт.**

**Разграничение:**

| Категория | One-time (launch) | Monthly (ongoing) | Scope |
|-----------|------------------|-------------------|-------|
| **Provider outreach** | BD travel, pitches, meetings | — | Привлечение Provider к платформе |
| **Provider integration** | — | $1,000/provider/30 мес | Feed setup, catalog QA, training |
| **Mall partnership** | $5,000 | — | Permissions, setup, management relationship |
| **Launch activation** | $3,000 | — | Theater, QR materials, events |
| **Field team** | $5,400 | — | 1.0 FTE × 36 days |

**Revised one-time:**

| Статья | Значение | Тип | Примечание |
|--------|---------|-----|-----------|
| BD outreach (pre-launch) | $4,000 | [H] | Travel, meetings, pitch materials. НЕ integration |
| Mall partnership / setup | $5,000 | [H] | Unchanged from Block 1 |
| Launch activation | $3,000 | [H] | Theater, QR, materials |
| Field team (36 days × $150) | $5,400 | [H] | Block 4 §A.4 decomposition |
| Contingency | $600 | [H] | ~3% |
| **Total one-time** | **$18,000** | [H] | Was $23K — снято $5K overlap |

**Monthly Onboard** (PP × $1,000/30) теперь покрывает **только** feed integration, catalog QA, training — без overlap с one-time BD outreach.

### A.4. PP_elig vs PP_paying

В Phase 1 (Earn-only, M1–M32) покупка Credits запрещена (Конституция §4.2). Столбец **PP_elig** в таблицах = количество Providers, которые:
- Активно зарабатывают Credits
- Накопили достаточно для Purchase при переходе к Phase 2
- Имеют motivation и capability стать paying

**PP_paying** = PP_elig × conversion_rate (при Phase 2 trigger). Для baseline модели PP_paying = PP_elig (100% conversion [H] — conservative assumption: все eligible начнут платить).

В Scenario P (WTP pilots M12+) = 3–5 из PP_elig участвуют в пилоте; WTP revenue = 30% capacity.

### A.5. Revenue Capacity и Phase Gating

| Сценарий | M1–M11 | M12–M32 | M33+ |
|----------|--------|---------|------|
| **S (Strict)** | $0 | $0 | Revenue capacity |
| **P (WTP Pilots)** | $0 | Revenue capacity × 30% [H] | Revenue capacity |

*WTP tactic: пилоты проводятся с 3–5 наиболее активными PP_elig (highest Earned Credits). Ставка пилота = $0.10/Credit [H]. Результат используется для: (a) WTP validation, (b) refinement Price per Credit для Phase 2, (c) provider case studies.*

---

## B. MONTHLY P&L — SCENARIO S (STRICT CONSTITUTION)

> **Revenue = $0 до ~M33.** PP_elig = Providers eligible for Phase 2. Revenue capacity показана для справки.


| M | PP_elig | r | MAU | OIR | Rev cap | AI | Ops | Onb | Srv | Lnch | **Opex** | **Rev** | **Margin** | **Cum** |
|---|--------|------|-------|------|---------|-----|------|-----|-----|------|---------|---------|------------|---------|
| 1 | 1 | 5% | 800 | 0.02 | $0 | $656 | $2,000 | $33 | $200 | $3,000 | **$5,889** | **$0** | **$-5,889** | $-5,889 |
| 2 | 2 | 7% | 2,000 | 0.05 | $0 | $1,600 | $2,000 | $66 | $220 | $2,000 | **$5,886** | **$0** | **$-5,886** | $-11,775 |
| 3 | 3 | 10% | 3,530 | 0.08 | $90 | $2,753 | $2,000 | $100 | $240 | — | **$5,093** | **$0** | **$-5,093** | $-16,868 |
| 4 | 4 | 10% | 3,655 | 0.11 | $244 | $2,752 | $2,000 | $133 | $260 | — | **$5,145** | **$0** | **$-5,145** | $-22,013 |
| 5 | 6 | 12% | 3,922 | 0.18 | $565 | $2,851 | $2,000 | $200 | $280 | — | **$5,331** | **$0** | **$-5,331** | $-27,344 |
| 6 | 8 | 12% | 4,054 | 0.21 | $720 | $2,837 | $2,000 | $266 | $300 | — | **$5,403** | **$0** | **$-5,403** | $-32,747 |
| 7 | 8 | 12% | 4,171 | 0.24 | $984 | $2,919 | $2,000 | $266 | $300 | — | **$5,485** | **$0** | **$-5,485** | $-38,232 |
| 8 | 11 | 14% | 4,420 | 0.30 | $1,535 | $3,094 | $2,000 | $366 | $300 | — | **$5,760** | **$0** | **$-5,760** | $-43,992 |
| 9 | 12 | 14% | 4,544 | 0.33 | $1,800 | $3,180 | $2,000 | $400 | $300 | — | **$5,880** | **$0** | **$-5,880** | $-49,872 |
| 10 | 12 | 14% | 4,645 | 0.36 | $2,130 | $3,251 | $2,000 | $400 | $300 | — | **$5,951** | **$0** | **$-5,951** | $-55,823 |
| 11 | 14 | 15% | 4,872 | 0.41 | $2,819 | $3,410 | $2,000 | $466 | $300 | — | **$6,176** | **$0** | **$-6,176** | $-61,999 |
| 12 | 15 | 15% | 4,977 | 0.44 | $3,150 | $3,483 | $2,000 | $500 | $300 | — | **$6,283** | **$0** | **$-6,283** | $-68,282 |
| 13 | 15 | 16% | 5,086 | 0.46 | $3,445 | $3,519 | $2,000 | $500 | $308 | — | **$6,327** | **$0** | **$-6,327** | $-74,609 |
| 14 | 17 | 17% | 5,308 | 0.50 | $4,061 | $3,625 | $2,000 | $566 | $316 | — | **$6,507** | **$0** | **$-6,507** | $-81,116 |
| 15 | 20 | 18% | 5,672 | 0.57 | $5,012 | $3,828 | $2,000 | $666 | $325 | — | **$6,819** | **$0** | **$-6,819** | $-87,935 |
| 16 | 22 | 20% | 6,051 | 0.64 | $5,963 | $4,036 | $2,000 | $733 | $333 | — | **$7,102** | **$0** | **$-7,102** | $-95,037 |
| 17 | 24 | 21% | 6,300 | 0.68 | $6,579 | $4,145 | $2,000 | $800 | $341 | — | **$7,286** | **$0** | **$-7,286** | $-102,323 |
| 18 | 25 | 22% | 6,430 | 0.71 | $6,875 | $4,179 | $2,000 | $833 | $350 | — | **$7,362** | **$0** | **$-7,362** | $-109,685 |
| 19 | 25 | 23% | 6,583 | 0.73 | $7,961 | $4,167 | $2,083 | $833 | $358 | — | **$7,441** | **$0** | **$-7,441** | $-117,126 |
| 20 | 27 | 24% | 6,930 | 0.79 | $10,229 | $4,275 | $2,166 | $900 | $366 | — | **$7,707** | **$0** | **$-7,707** | $-124,833 |
| 21 | 30 | 26% | 7,471 | 0.88 | $13,727 | $4,482 | $2,250 | $1,000 | $375 | — | **$8,107** | **$0** | **$-8,107** | $-132,940 |
| 22 | 32 | 28% | 8,041 | 0.97 | $17,225 | $4,687 | $2,333 | $1,066 | $383 | — | **$8,469** | **$0** | **$-8,469** | $-141,409 |
| 23 | 34 | 29% | 8,443 | 1.03 | $19,493 | $4,787 | $2,416 | $1,133 | $391 | — | **$8,727** | **$0** | **$-8,727** | $-150,136 |
| 24 | 35 | 30% | 8,632 | 1.06 | $20,580 | $4,747 | $2,500 | $1,166 | $400 | — | **$8,813** | **$0** | **$-8,813** | $-158,949 |
| 25 | 35 | 31% | 8,835 | 1.09 | $21,317 | $4,788 | $2,500 | $1,166 | $408 | — | **$8,862** | **$0** | **$-8,862** | $-167,811 |
| 26 | 37 | 32% | 9,297 | 1.15 | $22,855 | $4,955 | $2,500 | $1,233 | $416 | — | **$9,104** | **$0** | **$-9,104** | $-176,915 |
| 27 | 40 | 34% | 10,019 | 1.25 | $25,230 | $5,259 | $2,500 | $1,333 | $425 | — | **$9,517** | **$0** | **$-9,517** | $-186,432 |
| 28 | 42 | 36% | 10,787 | 1.35 | $27,604 | $5,576 | $2,500 | $1,400 | $433 | — | **$9,909** | **$0** | **$-9,909** | $-196,341 |
| 29 | 44 | 37% | 11,332 | 1.41 | $29,142 | $5,756 | $2,500 | $1,466 | $441 | — | **$10,163** | **$0** | **$-10,163** | $-206,504 |
| 30 | 45 | 38% | 11,588 | 1.44 | $29,880 | $5,794 | $2,500 | $1,500 | $450 | — | **$10,244** | **$0** | **$-10,244** | $-216,748 |
| 31 | 45 | 39% | 11,903 | 1.49 | $30,927 | $5,856 | $2,583 | $1,500 | $458 | — | **$10,397** | **$0** | **$-10,397** | $-227,145 |
| 32 | 47 | 40% | 12,547 | 1.57 | $33,113 | $6,060 | $2,666 | $1,566 | $466 | — | **$10,758** | **$0** | **$-10,758** | $-237,903 |
| 33 | 50 | 42% | 13,617 | 1.71 | $36,486 | $6,468 | $2,750 | $1,666 | $475 | — | **$11,359** | **$36,486** | **$+25,127** | $-212,776 |
| 34 | 52 | 43% | 14,754 | 1.85 | $39,858 | $6,890 | $2,833 | $1,733 | $483 | — | **$11,939** | **$39,858** | **$+27,919** | $-184,857 |
| 35 | 54 | 44% | 15,508 | 1.93 | $42,044 | $7,102 | $2,916 | $1,800 | $491 | — | **$12,309** | **$42,044** | **$+29,735** | $-155,122 |
| 36 | 55 | 45% | 15,907 | 1.98 | $43,092 | $7,158 | $3,000 | $1,833 | $500 | — | **$12,491** | **$43,092** | **$+30,601** | $-124,521 |

**+ One-time launch cost: $18,000 [H]**
**Total Cum S at M36 (incl. one-time): $-142,521**

---

## C. MONTHLY P&L — SCENARIO P (WTP PILOTS FROM M12)

> **WTP pilot = 30% от Revenue capacity начиная с M12** (3–5 PP_elig в пилоте). **Phase 2 full revenue с M33.**


| M | MAU | Rev cap | **Rev P** | **Opex** | **Margin P** | **Cum P** |
|---|-------|---------|---------|---------|------------|---------|
| 1 | 800 | $0 | **$0** | $5,889 | **$-5,889** | $-5,889 |
| 2 | 2,000 | $0 | **$0** | $5,886 | **$-5,886** | $-11,775 |
| 3 | 3,530 | $90 | **$0** | $5,093 | **$-5,093** | $-16,868 |
| 4 | 3,655 | $244 | **$0** | $5,145 | **$-5,145** | $-22,013 |
| 5 | 3,922 | $565 | **$0** | $5,331 | **$-5,331** | $-27,344 |
| 6 | 4,054 | $720 | **$0** | $5,403 | **$-5,403** | $-32,747 |
| 7 | 4,171 | $984 | **$0** | $5,485 | **$-5,485** | $-38,232 |
| 8 | 4,420 | $1,535 | **$0** | $5,760 | **$-5,760** | $-43,992 |
| 9 | 4,544 | $1,800 | **$0** | $5,880 | **$-5,880** | $-49,872 |
| 10 | 4,645 | $2,130 | **$0** | $5,951 | **$-5,951** | $-55,823 |
| 11 | 4,872 | $2,819 | **$0** | $6,176 | **$-6,176** | $-61,999 |
| 12 | 4,977 | $3,150 | **$945** | $6,283 | **$-5,338** | $-67,337 |
| 13 | 5,086 | $3,445 | **$1,033** | $6,327 | **$-5,294** | $-72,631 |
| 14 | 5,308 | $4,061 | **$1,218** | $6,507 | **$-5,289** | $-77,920 |
| 15 | 5,672 | $5,012 | **$1,503** | $6,819 | **$-5,316** | $-83,236 |
| 16 | 6,051 | $5,963 | **$1,788** | $7,102 | **$-5,314** | $-88,550 |
| 17 | 6,300 | $6,579 | **$1,973** | $7,286 | **$-5,313** | $-93,863 |
| 18 | 6,430 | $6,875 | **$2,062** | $7,362 | **$-5,300** | $-99,163 |
| 19 | 6,583 | $7,961 | **$2,388** | $7,441 | **$-5,053** | $-104,216 |
| 20 | 6,930 | $10,229 | **$3,068** | $7,707 | **$-4,639** | $-108,855 |
| 21 | 7,471 | $13,727 | **$4,118** | $8,107 | **$-3,989** | $-112,844 |
| 22 | 8,041 | $17,225 | **$5,167** | $8,469 | **$-3,302** | $-116,146 |
| 23 | 8,443 | $19,493 | **$5,847** | $8,727 | **$-2,880** | $-119,026 |
| 24 | 8,632 | $20,580 | **$6,174** | $8,813 | **$-2,639** | $-121,665 |
| 25 | 8,835 | $21,317 | **$6,395** | $8,862 | **$-2,467** | $-124,132 |
| 26 | 9,297 | $22,855 | **$6,856** | $9,104 | **$-2,248** | $-126,380 |
| 27 | 10,019 | $25,230 | **$7,569** | $9,517 | **$-1,948** | $-128,328 |
| 28 | 10,787 | $27,604 | **$8,281** | $9,909 | **$-1,628** | $-129,956 |
| 29 | 11,332 | $29,142 | **$8,742** | $10,163 | **$-1,421** | $-131,377 |
| 30 | 11,588 | $29,880 | **$8,964** | $10,244 | **$-1,280** | $-132,657 |
| 31 | 11,903 | $30,927 | **$9,278** | $10,397 | **$-1,119** | $-133,776 |
| 32 | 12,547 | $33,113 | **$9,933** | $10,758 | **$-825** | $-134,601 |
| 33 | 13,617 | $36,486 | **$36,486** | $11,359 | **$+25,127** | $-109,474 |
| 34 | 14,754 | $39,858 | **$39,858** | $11,939 | **$+27,919** | $-81,555 |
| 35 | 15,508 | $42,044 | **$42,044** | $12,309 | **$+29,735** | $-51,820 |
| 36 | 15,907 | $43,092 | **$43,092** | $12,491 | **$+30,601** | $-21,219 |

**+ One-time launch cost: $18,000 [H]**
**Total Cum P at M36 (incl. one-time): $-39,219**

---

## D. ANNUAL P&L & INVESTMENT PROFILE

### D.1. По годам


| Год | Период | Opex | Rev S | Margin S | Rev P | Margin P |
|-----|--------|------|-------|----------|-------|----------|
| Y1 | M1–M12 | $68,282 | $0 | $-68,282 | $945 | $-67,337 |
| Y2 | M13–M24 | $90,667 | $0 | $-90,667 | $36,339 | $-54,328 |
| Y3 | M25–M36 | $127,052 | $161,480 | $+34,428 | $227,498 | $+100,446 |
| **Total** | **M1–M36** | **$286,001** | **$161,480** | **$-124,521** | **$264,782** | **$-21,219** |


### D.2. Cumulative Investment Profile

| Метрика | Scenario S | Scenario P |
|---------|-----------|-----------|
| Peak cumulative loss (excl. one-time) | $-237,903 (M32) | $-134,601 (M32) |
| + One-time ($18,000) | $-255,903 | $-152,601 |
| Cum at M36 (incl. one-time) | $-142,521 | $-39,219 |
| Avg monthly burn (M1–M32) | $7,434 | $4,206 |
| Monthly margin at M36 (Phase 2) | +$30,601 | +$30,601 |
| **Est. payback** | **~M41** | **~M38** |

### D.3. Payback & ROI Calculation

*Payback = месяц, когда cumulative (incl. one-time) выходит в ноль при сохранении M36 margin rate.*


| Месяц | Cum S (projected) | Cum P (projected) |
|-------|-------------------|-------------------|
| M36 | $-142,521 | $-39,219 |
| M38 | $-81,319 | $21,983 ← breakeven |
| M40 | $-20,117 | $83,185 |
| M42 | $41,085 ← breakeven | $144,387 |
| M44 | $102,287 | $205,589 |
| M46 | $163,489 | $266,791 |
| M48 | $224,691 | $327,993 |


**ROI (Year 1 post-Phase 2):**

| Метрика | Scenario S | Scenario P |
|---------|-----------|-----------|
| Annual margin (M36 rate × 12) | $367,212 | $367,212 |
| Total investment at Phase 2 trigger | $142,521 | $39,219 |
| **ROI** | **258%** | **936%** |

*ROI = annualized Phase 2 margin ÷ total investment. >100% = investment repays within first year of Phase 2.*

### D.4. Reconciliation с Block 3 §G.4

| Метрика | Block 3 estimate | Block 6 v1.1 | Delta | Причина |
|---------|-----------------|-------------|-------|---------|
| Y1 Opex | ~$67,400 | $68,282 | $+882 | Launch spike +$5K, offset by ramp M1–M2 low MAU |
| Peak cum loss S | ~$255K | $255,903K | Smaller | Ramp effect + S-curve + revised one-time |
| Peak cum loss P | ~$162K | $152,601K | Smaller | WTP revenue точнее рассчитана помесячно |
| One-time cost | $23K | $18K | −$5K | Устранён двойной учёт с monthly onboard |
| Payback S | ~M44 | ~M41 | ~−3 мес | Меньший cumulative deficit |
| Payback P | ~M40 | ~M38 | ~−2 мес | Меньший cumulative deficit |

**Block 6 v1.1 = canonical source для финансовых расчётов.** Block 3 §G.4 — ориентировочный.

---

## E. SENSITIVITY ANALYSIS

### E.0. Резюме: Top 5 переменных по силе влияния

| # | Переменная | −30% impact на Cum P | +30% impact | Rank |
|---|-----------|---------------------|-------------|------|
| 1 | Phase 2 trigger month | M24 vs M33: +$168K | M36 vs M33: −$104K | **Критический** |
| 2 | AI cost / MAU | AI×0.7: +$46K | AI×1.5: −$77K | **Высокий** |
| 3 | Footfall (1.25M vs 1.5M) | −$31K | — | **Средний** |
| 4 | Retention trajectory | Indirect (через Phase 2 timing) | Indirect | **Средний (indirect)** |
| 5 | PP growth | −$11K direct | +$9K | **Низкий (в Phase 1)** |

### E.1. Phase 2 Trigger Month

**Самая чувствительная переменная.** Каждый месяц задержки ≈ $10K дополнительного burn.


| Phase 2 at | Cum P at M36 (incl. OT) | vs Base | Impact |
|-----------|------------------------|---------|--------|
| M24 | $129,236 | $+168,456 | Optimistic PMF |
| M27 | $83,909 | $+123,129 | Accelerated |
| M30 | $26,525 | $+65,745 | Slightly ahead |
| M33 | $-39,220 | $+0 | **Base case** |
| M36 | $-122,093 | $-82,873 | Conservative |


### E.2. AI Cost per MAU

AI cost = ~55% total opex. Оптимизация (кэширование, дешёвые модели для простых запросов, батчинг) — второй по силе рычаг.


| AI multiplier | AI/MAU at M36 | Cum P at M36 | vs Base |
|--------------|--------------|-------------|---------|
| 0.7× | $0.32 | $7,267 | $+46,487 |
| 0.85× | $0.38 | $-15,979 | $+23,241 |
| 1.0× | $0.45 | $-39,220 | $+0 |
| 1.2× | $0.54 | $-70,209 | $-30,989 |
| 1.5× | $0.68 | $-116,693 | $-77,473 |


### E.3. Footfall (новое в v1.1)

Mall footfall baseline = 1.5M/мес [B/H]. Sensitivity по downside (1.25M) и upside (1.75M).


| Footfall/мес | Множитель | Cum P at M36 | vs Base |
|-------------|----------|-------------|---------|
| 1,245,000 | 0.83× | $-70,009 | $-30,789 | **(downside)**
| 1,350,000 | 0.9× | $-57,334 | $-18,114 |
| 1,500,000 | 1.0× | $-39,220 | $+0 | **base**
| 1,650,000 | 1.1× | $-21,108 | $+18,112 |
| 1,755,000 | 1.17× | $-8,405 | $+30,815 | **(upside)**


**При downside footfall (1.25M):** −$31K vs base. Эффект средний — footfall влияет на N_organic (и через неё на MAU и AI cost), но revenue в Phase 1 = $0, поэтому прямой revenue impact только в WTP/Phase 2 window.

### E.4. Retention Trajectory


| Retention path | r at M36 | Cum P M36 | Примечание |
|---------------|----------|-----------|-----------|
| Stuck (r×0.6) | 27% | $-17,346 | Low MAU → low AI cost, but Phase 2 never triggers (D30 < 40%) |
| Slow (r×0.8) | 36% | $-27,235 | Phase 2 задерживается → M36+ |
| **Base** (r×1.0) | 45% | $-39,220 | Phase 2 at ~M33 |
| Fast (r×1.2) | 54% | $-54,200 | Phase 2 potentially ~M27 (if gating accelerated) |
| Accel (r×1.5) | 60% | $-79,886 | Theoretical; very high MAU + AI cost pre-Phase 2 |

> **⚠️ Парадокс retention в Phase 1:** Более высокая retention → больший MAU → выше AI cost → хуже cum P (при $0 или limited revenue). Реальная ценность retention — ускорение Phase 2 trigger (§E.1). При fast retention + Phase 2 at M27 → cum P **+$65K** (positive).

### E.5. PP Growth


| PP trajectory | PP_elig at M36 | Cum P M36 | vs Base |
|--------------|---------------|-----------|---------|
| PP×0.6 | 33 | $-26,356 | $+12,864 |
| PP×0.8 | 44 | $-32,754 | $+6,466 |
| PP×1.0 | 55 | $-39,220 | $+0 |
| PP×1.3 | 71 | $-48,618 | $-9,398 |
| PP×1.5 | 82 | $-55,123 | $-15,903 |

**Парадокс PP в Phase 1:** Рост PP увеличивает onboarding cost. Revenue растёт только в Phase 2. PP growth = investment in future revenue capacity.

### E.6. Combined Scenarios


| Сценарий | Ключевые отличия | Phase 2 | Cum P M36 | Payback |
|----------|-----------------|---------|-----------|---------|
| **Downside** | r×0.6, FF 1.25M, AI×1.2, Phase 2 M36 | M36 | $-142,758 | ~M41 |
| **Conservative** | r×0.7, Rev×0.7, FF 0.9×, Phase 2 M36 | M36 | $-164,677 | ~M42 |
| **Base** | As modeled | M33 | $-39,220 | ~M38 |
| **Optimistic** | r×1.4, PP×1.3, Rev×1.3, FF 1.1×, Phase 2 M27 | M27 | $198,482 | **Paid back** |


---

## F. KEY METRICS TRAJECTORY

### F.1. Unit Economics Ratios (selected months)


| M | ARPU (cap/MAU) | Cost/MAU | Rev/Cost | Margin/MAU (cap) |
|---|---------------|---------|----------|-----------------|
| 1 | $0.00 | $7.36 | 0.00× | $-7.36 |
| 3 | $0.03 | $1.44 | 0.02× | $-1.42 |
| 6 | $0.18 | $1.33 | 0.13× | $-1.16 |
| 9 | $0.40 | $1.29 | 0.31× | $-0.90 |
| 12 | $0.63 | $1.26 | 0.50× | $-0.63 |
| 18 | $1.07 | $1.14 | 0.93× | $-0.08 |
| 24 | $2.38 | $1.02 | 2.34× | $+1.36 |
| 30 | $2.58 | $0.88 | 2.92× | $+1.69 |
| 33 | $2.68 | $0.83 | 3.21× | $+1.85 |
| 36 | $2.71 | $0.79 | 3.45× | $+1.92 |

**Rev/Cost > 1.0×** (revenue capacity exceeds opex) достигается при ~M22. Фактический breakeven зависит от Phase gating.

### F.2. Opex Structure Evolution


| M | AI cost | AI % | Ops | Ops % | Onboard | Server | Launch | Total |
|---|---------|------|------|-------|---------|--------|--------|-------|
| 1 | $656 | 11% | $2,000 | 34% | $33 | $200 | $3,000 | $5,889 |
| 3 | $2,753 | 54% | $2,000 | 39% | $100 | $240 | — | $5,093 |
| 6 | $2,837 | 53% | $2,000 | 37% | $266 | $300 | — | $5,403 |
| 12 | $3,483 | 55% | $2,000 | 32% | $500 | $300 | — | $6,283 |
| 18 | $4,179 | 57% | $2,000 | 27% | $833 | $350 | — | $7,362 |
| 24 | $4,747 | 54% | $2,500 | 28% | $1,166 | $400 | — | $8,813 |
| 30 | $5,794 | 57% | $2,500 | 24% | $1,500 | $450 | — | $10,244 |
| 36 | $7,158 | 57% | $3,000 | 24% | $1,833 | $500 | — | $12,491 |

**Тренд:** AI cost доля растёт с ~11% (M1, ramp) до ~57% (M36). Ops доля снижается с ~34% до ~24%. Launch spike в M1–M2 (51% of opex) — одноразовый.

---

## G. STRUCTURAL FINDINGS

### G.1. Phase 2 trigger = единственный вопрос, который имеет значение

Sensitivity analysis подтверждает: **Phase 2 trigger month — переменная с максимальным влиянием на cumulative P&L.** Разница между M24 и M36 = $250K+. Все остальные переменные (AI cost, PP, retention, footfall) значимы преимущественно через их влияние на Phase 2 timing.

**Следствие для стратегии:** Все ресурсы Phase 1 → D30 retention > 40% (binding constraint).

### G.2. AI cost — второй по значимости рычаг

При 30% снижении AI cost/MAU seed выходит в positive territory даже при base Phase 2 timing. Пути снижения (все [H]):
- Кэширование популярных рекомендаций (top 100 запросов = 30–40% трафика)
- Дешёвые модели для простых запросов (size lookup, store location, stock check)
- Батчинг inference для не-real-time задач (аватар update, style profiling)

### G.3. Footfall downside — управляемый риск

Снижение footfall с 1.5M до 1.25M (−17%) → −$31K в cumulative P. Эффект средний: footfall влияет на N_organic, но в Phase 1 revenue = $0 (основной cost impact через AI cost на MAU). В Phase 2 footfall влияет сильнее (через impression pool). **Mitigation:** seasonal campaign alignment (peak footfall months = activation push).

### G.4. Adoption paradox подтверждён (Block 1 Step 2 §G.3)

Рост MAU без роста PP = рост cost без revenue. Acquisition spending обоснован только в связке с Provider growth.

### G.5. Pre-revenue investment summary

| Метрика | Scenario S | Scenario P |
|---------|-----------|-----------|
| Total investment to Phase 2 | ~${abs(rows[-1]['Cum_S'] - one_time)//1000 + 1}K | ~${abs(rows[-1]['Cum_P'] - one_time)//1000 + 1}K |
| Monthly burn rate (avg M1–M32) | ~${sum(r['Total_opex'] - r['Rev_S'] for r in rows[:32]) // 32:,} | ~${sum(r['Total_opex'] - r['Rev_P'] for r in rows[:32]) // 32:,} |
| Payback post-Phase 2 | ~{int(abs(rows[-1]['Cum_S'] - one_time) / margin_36) + 1} мес | ~{int(abs(rows[-1]['Cum_P'] - one_time) / margin_36) + 1} мес |
| ROI Year 1 post-Phase 2 | {data['roi_S']:.0%} | {data['roi_P']:.0%} |
| M36 monthly margin | +${margin_36:,} | +${margin_36:,} |

---

## H. СКВОЗНЫЕ ФОРМУЛЫ

```
# Network (S-curve interpolated from Block 3 milestones)
MAU(t)           = N_total(t) / (1 − r(t))                    [D]
N_total(t)       = N_organic + N_provider(t) + N_viral(t)     [D]
N_organic        = 2,940 / мес                                [H, constant]
OIR(t)           = (N_provider(t) + N_viral(t)) / N_organic   [D]

# Revenue (Phase-gated)
Rev_capacity(t)  = MIN(K_gate(t), Impression_cap(t))          [D]
Price(t)         = $0.10 (M1–M23), $0.12 (M24+)              [H]

Rev_S(t) = 0 if t < 33; Rev_capacity(t) if t ≥ 33
Rev_P(t) = 0 if t < 12; Rev_capacity(t) × 0.30 if 12 ≤ t < 33; Rev_capacity(t) if t ≥ 33

# Opex
AI_cost(t)       = MAU(t) × AI_cost_per_MAU(t)                [D]
Ops(t)           = linear interpolation: $2,000 → $3,000       [H trajectory]
Onboard(t)       = PP_elig(t) × $1,000 / 30                   [D] (integration only)
Server(t)        = linear interpolation: $200 → $500            [H trajectory]
Launch_spike     = M1: +$3,000, M2: +$2,000                   [H]
One_time         = $18,000                                     [H]

# Interpolation
Growth_metrics   = logistic S-curve (k=6)                      [PP, r, N_prov, N_viral, Rev_cap]
Cost_metrics     = linear                                      [AI cost/MAU, Ops, Server]

# Payback
Payback_month    = M36 + CEIL(|Cum(M36)| / Monthly_Margin_M36)
ROI_year1        = (Monthly_Margin_M36 × 12) / |Total_Investment|
```

---

## I. PARAMETER REGISTRY

Все параметры Block 6 наследуются из Blocks 1–4. [H]-траектории фиксируются здесь для P&L:

| Параметр | Значение / Trajectory | Тип | Источник |
|----------|----------------------|-----|----------|
| Mall Monthly Footfall | 1,500,000 | [B/H] | Block 1 Step 1 §A |
| Fashion Footfall Share | 35% | [B] | Block 1 Step 1 §A |
| N_organic | 2,940/мес (constant) | [H] | Block 3 §A.4 |
| Organic Threshold | 30% slots | [H] | Constitution §7 |
| Items per Recommendation | 5 | [H] | Block 1 Step 1 §C |
| Price per Credit | $0.10 (M1–M23) → $0.12 (M24+) | [H] | Constitution §2.5, Block 3 §G.1 |
| K coefficient | 0.3 → 0.5 → 0.7 → 1.0 (by tier) | [H] | Constitution §2.3 |
| AI cost/MAU trajectory | $0.82 (M1) → $0.70 (M6) → $0.45 (M36) | [H] | Block 3 §G.1, Block 4 §B.2 |
| Ops team | $2,000 (M1–M18) → $3,000 (M36) | [H] | Block 3 §G.1 |
| Server / infra | $200 (M1) → $500 (M36) | [H] | Block 3 §G.1 |
| Launch spike (M1/M2) | +$3,000 / +$2,000 | [H] | **Block 6 v1.1** (derived from Block 4 §A.4) |
| One-time launch cost | $18,000 (revised from $23K) | [H] | **Block 6 v1.1** (revised, see §A.3) |
| Onboard amortized | PP × $1,000 / 30 мес (integration only) | [H/D] | Block 1 Step 1 §E (clarified scope) |
| WTP pilot rate | 30% of capacity | [H] | Block 3 §G.3 |
| Phase 2 trigger (base) | ~M33 | [D] | Block 3 §E.2 |
| Paying_Share_max | 80% | [H] | Block 3 §G.2 |
| S-curve steepness (k) | 6 | [H] | **Block 6 v1.1** (interpolation parameter) |

---

## J. EVIDENCE PLACEHOLDERS

| Reference | Used in | Status | Placeholder source |
|-----------|---------|--------|-------------------|
| Mall annual footfall 1.5M baseline | §B (all rows) | **TBD → [V]** | Occupi estimates, mall management press releases |
| AI inference cost benchmarks ($0.70–0.45/MAU) | §B, §E.2 | **TBD → [V]** | OpenAI/Anthropic API pricing calculators, internal benchmarks |
| Mall app adoption rates (1–3%) | §I (adoption 2%) | **TBD → [V]** | App Annie / data.ai mall app benchmarks |
| Consumer app activation (20–50%) | §I (activation 40%) | **TBD → [V]** | Amplitude / Mixpanel industry reports |
| Dubai retail seasonality (footfall variance) | §E.3 | **TBD → [V]** | Dubai Statistics Center, KPMG GCC consumer survey |
| Provider willingness-to-pay ($0.10–0.15/Credit) | §I (Price per Credit) | **TBD → [V]** | WTP pilot data (M12+), StoreTraffic/Placer.ai pricing |

*Каждый TBD placeholder должен быть заменён на конкретный URL или document title перед использованием в investor materials.*

---

*Inputs: Block 1 Steps 1–2, Block 3 v1.0, Block 4 v1.1 | Протокол: UNDE_Model_Constitution_v1.2*