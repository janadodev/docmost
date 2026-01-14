# Развертывание Docmost на Google Cloud Run

## Предварительные требования

1. Установлен Google Cloud SDK
2. Включены необходимые API
3. Создан VPC Connector для доступа к Redis

## Шаг 1: Включить необходимые API

```bash
gcloud services enable \
  cloudbuild.googleapis.com \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  vpcaccess.googleapis.com \
  sqladmin.googleapis.com
```

## Шаг 2: Создать VPC Connector (если еще не создан)

```bash
gcloud compute networks vpc-access connectors create docmost-vpc-connector \
  --region=europe-west1 \
  --network=default \
  --range=10.8.0.0/28 \
  --min-instances=2 \
  --max-instances=3
```

## Шаг 3: Создать Artifact Registry репозиторий

```bash
gcloud artifacts repositories create docmost-repo \
  --repository-format=docker \
  --location=europe-west1 \
  --description="Docker repository for Docmost"
```

## Шаг 4: Подготовить переменные окружения

Убедитесь, что в файле `.env` заполнены все необходимые переменные:
- `DATABASE_URL` - с реальным паролем PostgreSQL
- `APP_SECRET` - сгенерированный секретный ключ (минимум 32 символа)
- `REDIS_URL` - строка подключения к Redis
- `STORAGE_DRIVER=s3`
- Все `AWS_S3_*` переменные для GCS

## Шаг 5: Развернуть через Cloud Build (рекомендуется)

```bash
gcloud builds submit --config cloudbuild.yaml
```

## Шаг 6: Развернуть вручную

### 6.1. Собрать и загрузить образ

```bash
gcloud builds submit --tag europe-west1-docker.pkg.dev/docmost-484110/docmost-repo/docmost:latest
```

### 6.2. Создать Cloud Run сервис

```bash
# Загрузите переменные из .env файла
export $(cat .env | grep -v '^#' | xargs)

gcloud run deploy docmost \
  --image europe-west1-docker.pkg.dev/docmost-484110/docmost-repo/docmost:latest \
  --region europe-west1 \
  --platform managed \
  --allow-unauthenticated \
  --vpc-connector docmost-vpc-connector \
  --vpc-egress all-traffic \
  --add-cloudsql-instances docmost-484110:europe-west1:docmost-2 \
  --set-env-vars "DATABASE_URL=$DATABASE_URL,REDIS_URL=$REDIS_URL,APP_SECRET=$APP_SECRET,APP_URL=$APP_URL,STORAGE_DRIVER=$STORAGE_DRIVER,AWS_S3_REGION=$AWS_S3_REGION,AWS_S3_BUCKET=$AWS_S3_BUCKET,AWS_S3_ENDPOINT=$AWS_S3_ENDPOINT,AWS_S3_ACCESS_KEY_ID=$AWS_S3_ACCESS_KEY_ID,AWS_S3_SECRET_ACCESS_KEY=$AWS_S3_SECRET_ACCESS_KEY,AWS_S3_FORCE_PATH_STYLE=$AWS_S3_FORCE_PATH_STYLE,NODE_ENV=production,PORT=3000" \
  --memory 2Gi \
  --cpu 2 \
  --timeout 300 \
  --max-instances 10 \
  --min-instances 0
```

## Шаг 7: Настроить подключение к Cloud SQL

После развертывания:

1. Откройте Cloud Run → docmost → Edit & Deploy New Revision
2. Connections → Add Connection
3. Выберите `docmost-2`
4. Обновите `DATABASE_URL` на формат с Unix socket:
   ```
   postgresql://postgres:PASSWORD@/docmost?host=/cloudsql/docmost-484110:europe-west1:docmost-2
   ```

## Шаг 8: Обновить APP_URL

После получения URL от Cloud Run (например, `https://docmost-xxxxx.run.app`):

```bash
gcloud run services update docmost \
  --region europe-west1 \
  --update-env-vars APP_URL=https://docmost-xxxxx.run.app
```

## Шаг 9: Выполнить миграции базы данных

```bash
# Подключитесь к Cloud Run контейнеру или выполните локально с правильным DATABASE_URL
gcloud run jobs create docmost-migrate \
  --image europe-west1-docker.pkg.dev/docmost-484110/docmost-repo/docmost:latest \
  --region europe-west1 \
  --set-env-vars "DATABASE_URL=..." \
  --command "pnpm" \
  --args "migration:latest"

# Или выполните миграции локально с правильным DATABASE_URL
cd apps/server
pnpm migration:latest
```

## Проверка развертывания

1. Откройте URL сервиса Cloud Run
2. Проверьте логи: `gcloud run logs read docmost --region europe-west1`
3. Убедитесь, что все переменные окружения установлены правильно

## Обновление приложения

Для обновления просто запустите сборку заново:

```bash
gcloud builds submit --tag europe-west1-docker.pkg.dev/docmost-484110/docmost-repo/docmost:latest
gcloud run deploy docmost \
  --image europe-west1-docker.pkg.dev/docmost-484110/docmost-repo/docmost:latest \
  --region europe-west1
```

## Важные замечания

- Redis доступен только из VPC, поэтому обязателен VPC Connector
- PostgreSQL лучше подключать через Cloud SQL connection (Unix socket)
- APP_URL должен быть обновлен после получения реального URL
- APP_SECRET должен быть уникальным и безопасным (минимум 32 символа)
