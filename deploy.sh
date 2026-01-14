#!/bin/bash

# Скрипт для деплоя Docmost в Cloud Run
# Использование: ./deploy.sh [tag]
# Пример: ./deploy.sh v1.0.0 или ./deploy.sh latest

set -e

# Конфигурация
PROJECT_ID="docmost-484110"
REGION="europe-west1"
SERVICE_NAME="docmost"
REPOSITORY="docmost-repo"
IMAGE_NAME="docmost"

# Получаем тег (по умолчанию latest)
TAG=${1:-latest}
FULL_IMAGE_NAME="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${IMAGE_NAME}:${TAG}"

echo "=========================================="
echo "Деплой Docmost в Cloud Run"
echo "=========================================="
echo "Проект: $PROJECT_ID"
echo "Сервис: $SERVICE_NAME"
echo "Регион: $REGION"
echo "Образ: $FULL_IMAGE_NAME"
echo "=========================================="
echo ""

# Шаг 1: Проверка, что мы в правильной директории
if [ ! -f "Dockerfile" ]; then
    echo "❌ Ошибка: Dockerfile не найден. Запустите скрипт из корневой директории проекта."
    exit 1
fi

# Шаг 2: Аутентификация в Artifact Registry
echo "Шаг 1: Настройка аутентификации для Artifact Registry..."
if ! gcloud auth configure-docker ${REGION}-docker.pkg.dev --quiet 2>/dev/null; then
    echo "❌ Ошибка при настройке аутентификации Docker"
    exit 1
fi
echo "✓ Аутентификация настроена"

# Шаг 3: Сборка Docker образа
echo ""
echo "Шаг 2: Сборка Docker образа..."
echo "Это может занять несколько минут..."
if ! docker build -t $FULL_IMAGE_NAME .; then
    echo "❌ Ошибка при сборке образа"
    exit 1
fi
echo "✓ Образ собран успешно"

# Шаг 4: Публикация образа в Artifact Registry
echo ""
echo "Шаг 3: Публикация образа в Artifact Registry..."
if ! docker push $FULL_IMAGE_NAME; then
    echo "❌ Ошибка при публикации образа"
    exit 1
fi
echo "✓ Образ опубликован успешно"

# Шаг 5: Обновление Cloud Run сервиса
echo ""
echo "Шаг 4: Обновление Cloud Run сервиса..."
if ! gcloud run services update $SERVICE_NAME \
    --image=$FULL_IMAGE_NAME \
    --region=$REGION \
    --project=$PROJECT_ID; then
    echo "❌ Ошибка при обновлении сервиса"
    exit 1
fi
echo "✓ Сервис обновлен успешно"

# Шаг 6: Получение URL и проверка
echo ""
echo "Шаг 5: Проверка деплоя..."
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME \
    --region=$REGION \
    --format="value(status.url)" \
    --project=$PROJECT_ID 2>/dev/null)

if [ -z "$SERVICE_URL" ]; then
    echo "⚠️  Не удалось получить URL сервиса"
else
    echo "URL сервиса: $SERVICE_URL"
    
    # Проверка health endpoint
    echo ""
    echo "Проверка health endpoint..."
    sleep 5  # Даем время сервису запуститься
    
    if HEALTH_RESPONSE=$(curl -s -w "\n%{http_code}" "${SERVICE_URL}/api/health" 2>/dev/null); then
        HTTP_CODE=$(echo "$HEALTH_RESPONSE" | tail -n1)
        BODY=$(echo "$HEALTH_RESPONSE" | head -n-1)
        
        if [ "$HTTP_CODE" = "200" ]; then
            echo "✓ Health check успешен (HTTP $HTTP_CODE)"
            if command -v python3 &> /dev/null; then
                echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"
            else
                echo "$BODY"
            fi
        else
            echo "⚠️  Health check вернул код $HTTP_CODE"
            echo "$BODY"
        fi
    else
        echo "⚠️  Не удалось выполнить health check (сервис может еще запускаться)"
    fi
fi

echo ""
echo "=========================================="
echo "✓ Деплой завершен успешно!"
echo "=========================================="
echo ""
echo "Для проверки вручную:"
echo "  curl ${SERVICE_URL}/api/health"
echo ""
