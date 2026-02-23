# Credentials

| Файл | Что внутри |
|------|-----------|
| `redis-push.env` | Redis пароль (push.unde.life, 10.1.0.4) |
| `staging-db.env` | Все пользователи Staging DB (10.1.0.8) — apify, downloader, ximilar, scraper, collage |

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
