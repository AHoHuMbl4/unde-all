# UNDE Infrastructure — Итоговое ТЗ v7.2

> **🔄 Обновлено под [Pipeline v5.1](../UNDE_Fashion_Recognition_Pipeline_v5.1.md)** — dual retrieval (pgvector + Ximilar), availability post-filter, embedding серверы, feature flags, conditional tagging. Все изменения помечены `🔄 v5.1` в соответствующих файлах.

Этот документ разделён на 8 файлов по функциональным областям.

| Файл | Содержание | Серверы |
|------|-----------|---------|
| [00_Overview.md](00_Overview.md) | Принципы, архитектурная диаграмма, карта всех серверов | — |
| [01_Catalog_Pipeline.md](01_Catalog_Pipeline.md) | Сбор каталога, фото, коллажи, staging, Object Storage | Scraper, Apify, Photo Downloader, Ximilar Sync, Collage, Staging DB, Object Storage |
| [02_Recognition_Pipeline.md](02_Recognition_Pipeline.md) | Fashion Recognition: detection → tagging → search → availability → rerank (🔄 v5.1) | Recognition Orchestrator, Ximilar Gateway, LLM Reranker, Embedder |
| [03_Dialogue_Pipeline.md](03_Dialogue_Pipeline.md) | Диалог с аватаром: эмоции, голос, LLM, контекст, персона | Mood Agent, Voice Server, LLM Orchestrator, Context Agent, Persona Agent |
| [04_Local_User_Data_Shards.md](04_Local_User_Data_Shards.md) | User Data: схема БД, pgvector, FTS, репликация, шардирование, бэкапы | Local Shards (32 GB, NVMe), Hetzner Replicas, Patroni + etcd |
| [05_Data_Flow.md](05_Data_Flow.md) | Диаграммы потоков данных (8 сценариев, 🔄 v5.1: Embedding Batch) | — |
| [06_Operations.md](06_Operations.md) | Расписание, мониторинг, деплой, безопасность, credentials | — |
| [07_Server_Layout_v7.md](07_Server_Layout_v7.md) | Карта серверов, стоимость, WireGuard, failover, PostHog, мониторинг | Все серверы (локальные + Helsinki) |

## Связанные документы

- `UNDE_Infrastructure_BD.md` — масштабирование до 10K юзеров (RAM, шардирование, стоимость)
- `UNDE_Smart_Context_Architecture.md` — три слоя знания (Semantic Retrieval, User Knowledge, Context Agent)
- `UNDE_Persona_Voice_Layer.md` — характер, тон, стиль, голос, аватар (Persona Agent)

---

*Документ создан: 2026-02-01*
*Разделён на файлы: 2026-02-16*
*Обновлён: 2026-02-23 (v7.2 — локальные серверы, PostHog, мониторинг, Helsinki GW)*
*Обновлён: 2026-02-26 (v7.2.1 — Pipeline v5.1: dual retrieval, availability filter, embedding серверы)*
*Версия: 7.2.1*
