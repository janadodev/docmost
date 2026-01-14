#!/bin/bash

# Скрипт для деплоя приложения Docmost в GCP Cloud Run
# Обновляет только образ приложения, не затрагивая инфраструктуру (SQL, Redis, VPC и т.д.)
# Использование: 
#   ./deploy.sh [--tag TAG] [--no-build]  - деплой новой версии
#   ./deploy.sh --rollback [REVISION]     - откат на предыдущую ревизию
#   ./deploy.sh --list-revisions          - список всех ревизий

set -e  # Остановка при ошибке

# Конфигурация
PROJECT_ID="docmost-484110"
REGION="europe-west1"
SERVICE_NAME="docmost"
REPOSITORY="docmost-repo"
IMAGE_NAME="docmost"
FULL_IMAGE_NAME="europe-west1-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}"

# Параметры по умолчанию
TAG="latest"
SKIP_BUILD=false
ROLLBACK=false
LIST_REVISIONS=false
ROLLBACK_REVISION=""

# Парсинг аргументов
while [[ $# -gt 0 ]]; do
  case $1 in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --no-build)
      SKIP_BUILD=true
      shift
      ;;
    --rollback)
      ROLLBACK=true
      if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
        ROLLBACK_REVISION="$2"
        shift 2
      else
        shift
      fi
      ;;
    --list-revisions)
      LIST_REVISIONS=true
      shift
      ;;
    *)
      echo "Неизвестный параметр: $1"
      echo "Использование:"
      echo "  $0 [--tag TAG] [--no-build]     - деплой новой версии"
      echo "  $0 --rollback [REVISION]        - откат на предыдущую ревизию"
      echo "  $0 --list-revisions             - список всех ревизий"
      exit 1
      ;;
  esac
done

# Проверка авторизации в GCP
echo "🔐 Проверка авторизации в GCP..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
  echo "❌ Ошибка: Вы не авторизованы в GCP"
  echo "Выполните: gcloud auth login"
  exit 1
fi

# Установка проекта
echo "📋 Установка активного проекта..."
gcloud config set project ${PROJECT_ID}

# Обработка списка ревизий
if [ "$LIST_REVISIONS" = true ]; then
  echo "📋 Список ревизий Cloud Run сервиса ${SERVICE_NAME}:"
  echo ""
  gcloud run revisions list \
    --service ${SERVICE_NAME} \
    --region ${REGION} \
    --format="table(metadata.name,status.conditions[0].status,metadata.creationTimestamp,status.traffic[0].percent)"
  exit 0
fi

# Обработка отката
if [ "$ROLLBACK" = true ]; then
  echo "⏪ Откат на предыдущую ревизию..."
  echo "📦 Проект: ${PROJECT_ID}"
  echo "🌍 Регион: ${REGION}"
  echo ""
  
  if [ -z "$ROLLBACK_REVISION" ]; then
    # Получаем предыдущую ревизию автоматически
    echo "🔍 Поиск предыдущей активной ревизии..."
    PREV_REVISION=$(gcloud run revisions list \
      --service ${SERVICE_NAME} \
      --region ${REGION} \
      --format="value(metadata.name)" \
      --limit=2 | tail -n 1)
    
    if [ -z "$PREV_REVISION" ]; then
      echo "❌ Не найдена предыдущая ревизия для отката"
      exit 1
    fi
    
    echo "📌 Найдена ревизия: ${PREV_REVISION}"
    ROLLBACK_REVISION=$PREV_REVISION
  fi
  
  echo "🔄 Переключение трафика на ревизию: ${ROLLBACK_REVISION}..."
  gcloud run services update-traffic ${SERVICE_NAME} \
    --region ${REGION} \
    --to-revisions ${ROLLBACK_REVISION}=100
  
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка при откате"
    exit 1
  fi
  
  echo ""
  echo "✅ Откат успешно выполнен!"
  echo "🌐 URL сервиса: https://docmost-584964349468.${REGION}.run.app"
  echo ""
  echo "Для просмотра всех ревизий выполните:"
  echo "  $0 --list-revisions"
  exit 0
fi

# Обычный деплой
echo "🚀 Начинаю деплой Docmost..."
echo "📦 Проект: ${PROJECT_ID}"
echo "🌍 Регион: ${REGION}"
echo "🏷️  Тег образа: ${TAG}"
echo ""

# Сборка Docker образа
if [ "$SKIP_BUILD" = false ]; then
  echo "🔨 Сборка Docker образа..."
  docker build -t ${FULL_IMAGE_NAME}:${TAG} .
  
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка при сборке Docker образа"
    exit 1
  fi
  echo "✅ Образ успешно собран"
else
  echo "⏭️  Пропуск сборки (--no-build)"
fi

# Авторизация в Artifact Registry
echo "🔑 Авторизация в Artifact Registry..."
gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet

# Пуш образа в Artifact Registry
echo "📤 Загрузка образа в Artifact Registry..."
docker push ${FULL_IMAGE_NAME}:${TAG}

if [ $? -ne 0 ]; then
  echo "❌ Ошибка при загрузке образа"
  exit 1
fi
echo "✅ Образ успешно загружен"

# Деплой в Cloud Run
# Примечание: обновляется только образ приложения
# Все остальные настройки (переменные окружения, Cloud SQL, VPC, Redis и т.д.)
# сохраняются из существующей конфигурации автоматически
echo "🚀 Деплой в Cloud Run (обновление только образа)..."
gcloud run deploy ${SERVICE_NAME} \
  --image ${FULL_IMAGE_NAME}:${TAG} \
  --region ${REGION} \
  --platform managed

if [ $? -ne 0 ]; then
  echo "❌ Ошибка при деплое в Cloud Run"
  exit 1
fi

echo ""
echo "✅ Деплой успешно завершен!"
echo "🌐 URL сервиса: https://docmost-584964349468.${REGION}.run.app"
echo ""
echo "Полезные команды:"
echo "  Просмотр логов:"
echo "    gcloud run services logs read ${SERVICE_NAME} --region ${REGION} --limit 50"
echo ""
echo "  Список ревизий:"
echo "    $0 --list-revisions"
echo ""
echo "  Откат на предыдущую версию:"
echo "    $0 --rollback"
echo "    $0 --rollback <REVISION_NAME>"
