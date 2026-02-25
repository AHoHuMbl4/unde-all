# Credentials

| Файл | Что внутри |
|------|-----------|
| `redis-push.env` | Redis пароль (push.unde.life, 10.1.0.4) |
| `staging-db.env` | Все пользователи Staging DB (10.1.0.8) — apify, downloader, ximilar, scraper, collage |
| `s3-object-storage.env` | S3 Access/Secret Keys для Hetzner Object Storage (hel1) |
| `brightdata-proxy.env` | Bright Data residential proxy (zone-zara) |
| `gemini.env` | Gemini API Key (llm-reranker) |
| `production-db.env` | Production DB (10.1.1.2 PgBouncer → database AX41) |

## Готовые connection strings для .env серверов

### Apify (10.1.0.9)
```
STAGING_DB_URL=postgresql://apify:xkjmAm2GX69NFm72cLzKR8u@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/7
```

### Photo Downloader (10.1.0.10)
```
STAGING_DB_URL=postgresql://downloader:81Su89FKj0uaFarSO3aNLePD@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/7
```

### Ximilar Sync (10.1.0.11)
```
STAGING_DB_URL=postgresql://ximilar:TsdSsI9ysTDgx6JUQXC60zSU@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/7
```

### Scraper (10.1.0.3)
```
STAGING_DB_URL=postgresql://scraper:XZpWsOGuuw55cHDKIZUqzEyJ@10.1.0.8:6432/unde_staging
```

### Collage (10.1.0.16)
```
STAGING_DB_URL=postgresql://collage:cwNPBoxs6KEuCbmyabxZJIk@10.1.0.8:6432/unde_staging
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/8
```

### Recognition (10.1.0.14)
```
DATABASE_URL=postgresql://undeuser:X37nLbzPI2jeL@10.1.1.2:6432/unde_main
REDIS_URL=redis://:kyha6QEgtmjk3vuFflSdUDa1Xqu41zRl9ce9oq0+UPQ=@10.1.0.4:6379/6
```

### LLM Reranker (10.1.0.13)
```
GEMINI_API_KEY=AIzaSyBQB2jKFgBDLeBIiqeHFVC_8q5INAvr9D0
```

### Shard Replica 0 (10.1.1.10) — PostgreSQL unde_shard
```
# LUKS password (md1 → /pgdata):
ejJyDBJpN92Q7BniB15pMC0IMjbvoEVTTDr6LZi1sao=

# DB users:
app_rw:       L4h9PdcAba99uTFH8ALDSu5Y7UDLghPK
knowledge_rw: JoqXKwo+cPsIfTBxwF9hRGroNiLs+gRl
persona_rw:   Px/GguJP6QJYlvbxQy7j0Rqu3ip2eYpG
replicator:   tOoue+JVwLYe3CnlJh4WuwIg3SmnxMDE
monitoring:   hiRU89R+C77qiHm4naTEaNUJNyN7S4b+
```

## S3 Object Storage (hel1.your-objectstorage.com)

### unde-images (каталог)
```
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=D62288LJKR53ZYQPTUVW
S3_SECRET_KEY=jqXFjNLxlo0LkUusNkoxYonhBcXbI29d6LFWEJBy
S3_BUCKET=unde-images
```

### unde-user-media (юзеры)
```
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=GXQ6TZCA397EA2SQ0R0B
S3_SECRET_KEY=OkweQeLAZgFcCuWlnAbTvTwGhJdZbnvCNodHKBVW
S3_BUCKET=unde-user-media
```

### unde-shard-backups (бэкапы)
```
S3_ENDPOINT=https://hel1.your-objectstorage.com
S3_ACCESS_KEY=W1H1ASKEO13SWA71SU0P
S3_SECRET_KEY=b1U59f7t67osOgdohNifsTLHxDP594NmZLImYkpx
S3_BUCKET=unde-shard-backups
```
