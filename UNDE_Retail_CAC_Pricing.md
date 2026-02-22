# UNDE — Исследование CAC в офлайн-ритейле и ориентиры для B2B-ценообразования

**Внутренний документ для финансовой модели | Февраль 2026**

---

## 1. CAC в офлайн-ритейле: что считать

### 1.1. Два практичных определения CAC в офлайне

В офлайне (особенно в больших торговых центрах) чаще считают не “CAC” в классическом перформанс‑смысле, а два близких показателя:

1) **Marketing CAC (drive‑to‑store)** — стоимость инкрементального визита в магазин *(CPV/CPF = cost per store visit / cost per footfall)*  
2) **Location CAC** — стоимость доступа к трафику через аренду *(Occupancy Cost Ratio, OCR = occupancy costs / sales)*

---

### 1.2. Drive‑to‑store: публичные кейсы CPV/CPF

Ниже — конкретные публичные кейсы, которые можно использовать как «якоря» по порядку величин:

| Регион | Кейс | Метрика | Значение |
|---|---|---:|---:|
| Азия (Тайвань/Сингапур/Малайзия) | Triumph | CPF | **$0.65** [1] |
| Ближний Восток (KSA) | Home Box | CPV | **$0.19** [2] |
| Европа (Швейцария) | Purina | CPV | **1.58 CHF** [3] |

---

### 1.3. Как перевести CPV в CAC нового покупателя

Формула для финансовой модели:

**CAC_new = CPV / (CR_store × Share_new_buyers)**

Где:
- **CR_store** — конверсия *визит → покупка*
- **Share_new_buyers** — доля новых покупателей среди покупок *(сценарный параметр модели)*

**Конверсия визит → покупка (CR_store):** ориентир **20–40%** для физического ритейла (зависит от категории и формата магазина). [4]

**Доля новых покупателей (Share_new_buyers):** в открытых источниках нет универсального бенчмарка, поэтому для финмодели задаётся сценарно (и валидируется на данных пилота).

Из формулы следует удобный «мультипликатор»:

**CAC_new ≈ (1 / (CR_store × Share_new_buyers)) × CPV**

При CR_store = 20–40% и сценарном Share_new_buyers = 20–50%:

- **Лучший случай:** 1 / (0.40 × 0.50) = **5×**
- **Худший случай:** 1 / (0.20 × 0.20) = **25×**

Итого для модели: **CAC_new ≈ 5–25 × CPV** (в зависимости от CR_store и доли новых покупателей).

---

### 1.4. Location CAC: Occupancy Cost Ratio (OCR)

OCR = доля продаж, уходящая на occupancy (аренда и связанные платежи).

Публичные ориентиры:

- **Klépierre (Европа): OCR 12.6%** (H1 2024). [5]  
- **Majid Al Futtaim (UAE, рейтинг Fitch): OCR ~11%**. [6]

Для расчётов:

- **Occupancy cost на транзакцию** = Average Basket × OCR  
- **Occupancy cost на нового** = (Average Basket × OCR) / Share_new_buyers

---

### 1.5. Ориентиры аренды для целевых регионов (контекст для OCR)

**Дубай (Nikoliers, Q1 2025):**
- *Key malls*: **371 AED / sq ft / year** (средневзвешенно по новым сделкам). [7]  
- *Landmark malls*: **1,113 AED / sq ft / year** (средневзвешенно по новым сделкам). [7]

**Алматы (Cushman & Wakefield):**
- Marketbeat Almaty Q4 2024: ставки могут доходить **до $30 / sq m** (контекст: retail/стрит‑ритейл). [8]  
- Street Retail report Q3 2022 (Алматы): максимум **$28.35 / sq m** (Medeu). [9]

---

## 2. Онлайн CAC в fashion (для сравнения)

| Сегмент | CAC (диапазон) | Источник |
|---|---:|---|
| Fashion e‑commerce (обычный ритейл) | **$10–$50** | Opensend [10] |
| Luxury goods / luxury e‑commerce | **~$175**, может быть **>$200** | Opensend [10] |
| Fashion (широкий диапазон) | **$32–$250** | LoyaltyLion [11] |

Примечание: LoyaltyLion также указывает на рост CAC примерно на **~40% между 2023 и 2025** (в статье приведена ссылка на сторонний источник); в этом документе это используется как индикатор тренда, а не как “точность до доллара”. [11]

---

## 3. Бюджеты и рынки, важные для монетизации UNDE

- **Маркетинговые бюджеты = 9.1% выручки компании (2023)** — Gartner (CMO Spend Survey). [12]  
- **US retail media spend (2025) > $62B** — eMarketer. [13]  
- **Ожидаемый рост retail media в США ~20% в 2025** — Nielsen. [14]  
- **Shopper marketing: прогноз $20.7B** (контекст: обзор 2024 и outlook 2025) — MarketingCharts. [15]

---

## 4. UNDE: рабочая модель B2B‑pricing для финмодели

Ниже — не “рынок”, а параметры, которые UNDE закладывает в модель продукта.

- **UNDE CPV (MVP): $3–$10 за подтверждённый визит** *(сценарий ценообразования UNDE)*  
- Пример: **500 визитов/мес → $1,500–$5,000/мес** (арифметика по модели)

---

## 5. Атрибуция в офлайне: практичная многоуровневая схема

UNDE может сочетать детерминированные и вероятностные сигналы; каждый уровень добавляет уверенности и/или детализации:

| Уровень | Что измеряем | Тип |
|---|---|---|
| 1 | Показ → клик “Где купить” | детерминированно |
| 2 | Посещение геозоны магазина (dwell time) | вероятностно |
| 3 | Self‑report “я купил” (геймификация/бонус) | вероятностно |
| 4 | Фото чека (OCR извлекает магазин/дату/сумму) | вероятностно |
| 5 | QR в магазине | детерминированно |
| 6 | Промокод на кассе (код‑маркер) | детерминированно |
| 7 | POS‑интеграция | детерминированно |

---

## 6. Вывод: примерный CAC в ТЦ (fashion massmarket) — Казахстан и Дубай

Ниже — **практичный ориентир “CAC” для оффлайн‑fashion в крупных ТЦ** через перформанс‑механику *drive‑to‑store* (когда мы покупаем **визиты в магазин / store visits**, а затем переводим их в покупки).

### 6.1. Контекст по стоимости охвата (почему Казахстан и Дубай отличаются)

- **Казахстан (Meta):** в обзоре рынка Meta в Казахстане (данные Meta Ads Manager, собранные Admixer — официальный Meta Business Partner) отмечено, что **CPM для 18–24 стабильно ниже $1**, а для 35–44 **доходил до ~$2**. [16]  
- **ОАЭ / Дубай:** в бенчмарке Facebook CPM по странам для **UAE указан CPM ~$8.98**. [17] Дополнительно, в кейсе TikTok For Business по **Dunkin’ UAE** зафиксирован **CPM 8.52 AED**. [18]

Это означает, что **стоимость охвата в Дубае заметно выше**, чем в Казахстане — и в плановой оценке *drive‑to‑store* это, как правило, поднимает и CPV/CPF (стоимость визита), если креатив/аудитория/цель кампании сопоставимы.

### 6.2. Расчётный ориентир CPV → CAC (для финмодели)

Мы используем публичные “якоря” по CPV/CPF из кейсов ($0.19–$0.65) [1][2] и корректируем их до **плановых диапазонов** для Казахстана и Дубая с учётом разницы в CPM. [16][17][18]

Далее применяем:
- **CR_store (визит → покупка): 20–40%** (бенчмарк для физического ритейла). [4]  
- **Share_new_buyers (доля новых покупателей): 20–50%** — *сценарный параметр*, который нужно валидировать в пилоте.

| Локация (ТЦ) | Плановый CPV (store visit) | CAC_purchase = CPV / CR_store | CAC_new = CPV / (CR_store × Share_new_buyers) |
|---|---:|---:|---:|
| **Казахстан (Алматы/Астана, крупные ТЦ)** | **$0.15 – $0.35** | **$0.4 – $1.8** | **$0.8 – $8.8** |
| **Дубай (крупные моллы)** | **$0.60 – $1.50** | **$1.5 – $7.5** | **$3 – $37.5** |

> Как читать таблицу:  
> - **CAC_purchase** — «сколько стоит привести покупателя» (без разделения на “новый/старый”).  
> - **CAC_new** — «сколько стоит новый покупатель», поэтому диапазон шире: он зависит от *Share_new_buyers* (его можно узнать только на фактических данных по магазину/моллу).

---

## Источники

1) The Trade Desk — Triumph case study (CPF $0.65):  
https://www.thetradedesk.com/assets/general/Triumph_Xaxis_Foursquare_CaseStudy.pdf

2) TikTok For Business — Home Box case study (CPV $0.19):  
https://www.tiktok.com/business/en-US/inspiration/home-box-retail

3) The Trade Desk — Purina Switzerland case study (CPV 1.58 CHF):  
https://www.thetradedesk.com/resources/purina-drives-in-store-sales-in-switzerland

4) Contentsquare — Conversion rate benchmarks (physical stores 20–40%):  
https://contentsquare.com/blog/conversion-rate/

5) Klépierre — Press release (occupancy cost ratio 12.6%):  
https://www.klepierre.com/en/les-actualites/strong-operating-performance-driving-to-valuation-increase-and-guidance-upgrade

6) Fitch / Majid Al Futtaim (hosted) — OCR around 11%:  
https://www.majidalfuttaim.com/-/media/digital-library-documents/investor-relations/ratings/2026/fitch-affirms-mafaa-at-bbb-outlook-stable_jan2025.pdf

7) Nikoliers — Dubai Retail Market Overview Q1 2025 (rents in key/landmark malls):  
https://www.nikoliers.ae/wp-content/uploads/2025/04/Nikoliers-Dubai-Retail-Market-Overview-Q1-2025.pdf

8) Cushman & Wakefield / Veritas — Marketbeat Almaty Q4 2024 (rents up to $30/sqm):  
https://cushwake.kz/wp-content/uploads/2025/02/CW_Kazakhstan_Marketbeat_Almaty_Q4_2024.pdf

9) Cushman & Wakefield — Street Retail report Q3 2022 (Almaty max $28.35/sqm):  
https://cushwake.kz/wp-content/uploads/2022/10/Street-Retail-report_Q3_2022_ENG.pdf

10) Opensend — eCommerce CAC stats (fashion $10–$50; luxury ~$175 and $200+):  
https://www.opensend.com/post/customer-acquisition-cost-ecommerce

11) LoyaltyLion — Average CAC in ecommerce 2025 (fashion $32–$250; trend +40% 2023–2025):  
https://loyaltylion.com/blog/blog-average-cac-ecommerce

12) Gartner — marketing budgets 9.1% of company revenue in 2023 (press release):  
https://www.gartner.com/en/newsroom/press-releases/2023-05-22-gartner-survey-reveals-71-percent-of-cmos-believe-they-lack-sufficient-budget-to-fully-execute-their-strategy-in-2023

13) eMarketer — US retail media spend 2025 >$62B:  
https://www.emarketer.com/content/10-billion-incremental-ad-spending-will-flow-us-retail-media-2025

14) Nielsen — future of retail media (рост ~20% в 2025 и цифры eMarketer):  
https://www.nielsen.com/insights/2025/future-retail-media/

15) MarketingCharts — Shopper Marketing прогноз $20.7B (контекст: обзор 2024, outlook 2025):  
https://www.marketingcharts.com/television-234866

16) Admixer Advertising (Meta Business Partner) — «Рынок Meta в Казахстане 2025» (CPM < $1 для 18–24; до ~$2 для 35–44):  
https://pulse.admixeradvertising.com/meta/meta-market-kazakhstan-2025/

17) Lebesgue — Facebook CPM by country (UAE CPM ~$8.98):  
https://lebesgue.io/facebook-ads/average-facebook-cpm-by-country

18) TikTok For Business — Dunkin’ UAE case study (CPM 8.52 AED):  
https://www.tiktok.com/business/en-US/inspiration/dunkin-uae-performance
