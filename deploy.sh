#!/bin/bash

# Скрипт для развертывания Docmost на Google Cloud Run
# Использование: ./deploy.sh

set -e

PROJECT_ID="docmost-484110"
REGION="europe-west1"
SERVICE_NAME="docmost"
IMAGE_NAME="europe-west1-docker.pkg.dev/${PROJECT_ID}/docmost-repo/docmost"
VPC_CONNECTOR="docmost-vpc-connector"
CLOUD_SQL_INSTANCE="docmost-484110:europe-west1:docmost-2"

echo "🚀 Начинаем развертывание Docmost на Cloud Run..."

# Проверка наличия .env файла
if [ ! -f .env ]; then
    echo "❌ Ошибка: файл .env не найден!"
    echo "Создайте файл .env с необходимыми переменными окружения."
    exit 1
fi

# Загрузка переменных из .env (безопасный способ)
echo "📋 Загружаем переменные окружения из .env..."
while IFS= read -r line || [ -n "$line" ]; do
    # Пропускаем комментарии и пустые строки
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// }" ]] && continue
    # Экспортируем переменную
    export "$line"
done < .env

# Проверка обязательных переменных
if [ -z "$DATABASE_URL" ] || [ -z "$REDIS_URL" ] || [ -z "$APP_SECRET" ]; then
    echo "❌ Ошибка: не все обязательные переменные окружения установлены!"
    echo "Проверьте DATABASE_URL, REDIS_URL, APP_SECRET в файле .env"
    exit 1
fi

# Проверка, что DATABASE_URL не содержит placeholder
if [[ "$DATABASE_URL" == *"YOUR_POSTGRES_PASSWORD"* ]]; then
    echo "❌ Ошибка: DATABASE_URL содержит placeholder YOUR_POSTGRES_PASSWORD!"
    echo "Замените YOUR_POSTGRES_PASSWORD на реальный пароль от PostgreSQL в файле .env"
    exit 1
fi

# Установка проекта
echo "🔧 Устанавливаем проект Google Cloud..."
gcloud config set project $PROJECT_ID

# Включение необходимых API
echo "🔌 Включаем необходимые API..."
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    artifactregistry.googleapis.com \
    vpcaccess.googleapis.com \
    sqladmin.googleapis.com \
    --quiet

# Проверка существования VPC Connector
echo "🔍 Проверяем VPC Connector..."
if ! gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region=$REGION &>/dev/null; then
    echo "📡 Создаем VPC Connector..."
    gcloud compute networks vpc-access connectors create $VPC_CONNECTOR \
        --region=$REGION \
        --network=default \
        --range=10.8.0.0/28 \
        --min-instances=2 \
        --max-instances=3 \
        --quiet
else
    echo "✅ VPC Connector уже существует"
    # Проверяем статус VPC Connector
    VPC_STATE=$(gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region=$REGION --format="value(state)" 2>/dev/null || echo "UNKNOWN")
    if [ "$VPC_STATE" != "READY" ]; then
        echo "⚠️ ВНИМАНИЕ: VPC Connector в статусе: $VPC_STATE"
        echo "   Убедитесь, что VPC Connector в статусе READY перед развертыванием"
    fi
fi

# Проверка конфигурации Redis
echo "🔍 Проверяем конфигурацию Redis..."
REDIS_INSTANCE="docmost"
if gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "✅ Redis инстанс найден"
    
    # Проверяем сеть Redis
    REDIS_NETWORK=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(authorizedNetwork)" 2>/dev/null || echo "")
    if [ ! -z "$REDIS_NETWORK" ]; then
        if [[ "$REDIS_NETWORK" == *"default"* ]] || [[ "$REDIS_NETWORK" == *"projects/$PROJECT_ID/global/networks/default"* ]]; then
            echo "✅ Redis в правильной сети: $REDIS_NETWORK"
        else
            echo "⚠️ ВНИМАНИЕ: Redis в сети '$REDIS_NETWORK', но VPC Connector в сети 'default'"
            echo "   Убедитесь, что сети совместимы или измените конфигурацию"
        fi
    fi
    
    # Проверяем IP адрес Redis из REDIS_URL
    REDIS_IP=$(echo $REDIS_URL | sed -n 's|.*@\([0-9.]*\):.*|\1|p')
    if [ ! -z "$REDIS_IP" ]; then
        echo "📋 Redis IP из REDIS_URL: $REDIS_IP"
        REDIS_ENDPOINT=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(host)" 2>/dev/null || echo "")
        if [ ! -z "$REDIS_ENDPOINT" ] && [ "$REDIS_ENDPOINT" != "$REDIS_IP" ]; then
            echo "⚠️ ВНИМАНИЕ: IP в REDIS_URL ($REDIS_IP) не совпадает с endpoint Redis ($REDIS_ENDPOINT)"
            echo "   Обновите REDIS_URL в .env файле на: redis://:PASSWORD@$REDIS_ENDPOINT:6379"
        fi
    fi
else
    echo "⚠️ ВНИМАНИЕ: Redis инстанс '$REDIS_INSTANCE' не найден в регионе $REGION"
    echo "   Убедитесь, что имя инстанса правильное или создайте Redis инстанс"
fi

    # Дополнительная диагностика Redis
    REDIS_AUTH_ENABLED=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(authEnabled)" 2>/dev/null || echo "")
    if [ "$REDIS_AUTH_ENABLED" = "True" ]; then
        echo "✅ Redis AUTH включен (требуется пароль)"
    else
        echo "⚠️ Redis AUTH отключен"
    fi
    
    # Проверяем, что VPC Connector может достичь Redis
    echo "🔍 Проверяем доступность Redis через VPC..."
    REDIS_ENDPOINT=$(gcloud redis instances describe $REDIS_INSTANCE --region=$REGION --project=$PROJECT_ID --format="value(host)" 2>/dev/null || echo "")
    if [ ! -z "$REDIS_ENDPOINT" ]; then
        echo "   Redis endpoint: $REDIS_ENDPOINT"
        echo "   Redis IP в REDIS_URL: $REDIS_IP"
        if [ "$REDIS_ENDPOINT" = "$REDIS_IP" ]; then
            echo "   ✅ IP адреса совпадают"
        else
            echo "   ❌ ОШИБКА: IP адреса НЕ совпадают!"
            echo "      Обновите REDIS_URL в .env на: redis://:PASSWORD@$REDIS_ENDPOINT:6379"
        fi
    fi

echo ""
echo "📋 ВАЖНО: Убедитесь, что Redis Memorystore настроен правильно:"
echo "   1. Redis должен быть в сети 'default' (или той же, что и VPC Connector)"
echo "   2. Authorized network Redis должен включать сеть 'default'"
echo "   3. Проверьте в консоли: Memorystore → Redis → ваш инстанс"
echo "   4. VPC Connector должен быть в статусе READY"
echo ""
echo "🔍 ДИАГНОСТИКА ПОДКЛЮЧЕНИЯ К REDIS:"
echo "   Redis IP: $REDIS_IP"
echo "   Redis диапазон: 10.151.36.32/29"
echo "   VPC Connector диапазон: 10.8.0.0/28"
echo "   Проверяем маршрутизацию..."

# Получаем Redis диапазон из конфигурации
REDIS_RANGE="10.151.36.32/29"
ROUTE_EXISTS=$(gcloud compute routes list --filter="network:default AND destRange:$REDIS_RANGE" --format="value(name)" 2>/dev/null | head -1 || echo "")
if [ ! -z "$ROUTE_EXISTS" ]; then
    ROUTE_DETAILS=$(gcloud compute routes describe $ROUTE_EXISTS --format="value(destRange,nextHopIp,priority)" 2>/dev/null || echo "")
    echo "   ✅ Маршрут к Redis существует: $ROUTE_EXISTS"
    if [ ! -z "$ROUTE_DETAILS" ]; then
        echo "      Детали маршрута: $ROUTE_DETAILS"
    fi
else
    echo "   ⚠️ Маршрут к Redis не найден!"
    echo "      Проверяем все маршруты к приватным диапазонам..."
    ALL_PRIVATE_ROUTES=$(gcloud compute routes list --filter="network:default AND destRange:10.0.0.0/8" --format="table(name,destRange,nextHopIp,priority)" 2>/dev/null | head -5 || echo "")
    if [ ! -z "$ALL_PRIVATE_ROUTES" ]; then
        echo "      Найденные маршруты к приватным диапазонам:"
        echo "$ALL_PRIVATE_ROUTES" | while IFS= read -r line; do
            echo "        $line"
        done
    fi
fi

# Проверяем все VPC Peerings для диагностики
echo "   Проверяем все VPC Peerings в сети default..."
# Используем describe сети, чтобы получить список peerings
NETWORK_PEERINGS=$(gcloud compute networks describe default --format="yaml" 2>/dev/null | grep -A 20 "peerings:" | grep "name:" | sed 's/.*name: //' || echo "")
if [ ! -z "$NETWORK_PEERINGS" ]; then
    echo "      Найденные VPC Peerings:"
    echo "$NETWORK_PEERINGS" | while IFS= read -r peering_name; do
        if [ ! -z "$peering_name" ]; then
            PEERING_STATE_TMP=$(gcloud compute networks peerings describe "$peering_name" --network=default --format="value(state)" 2>/dev/null || echo "UNKNOWN")
            echo "        - $peering_name (состояние: $PEERING_STATE_TMP)"
        fi
    done
else
    echo "      VPC Peerings не найдены"
fi

# Проверяем VPC Peering для Redis
echo "   Проверяем VPC Peering для Redis..."
# Получаем все peerings из сети и ищем Redis peering
ALL_PEERINGS=$(gcloud compute networks describe default --format="yaml" 2>/dev/null | grep -A 20 "peerings:" | grep "name:" | sed 's/.*name: //' || echo "")
REDIS_PEERING=""
PEERING_STATE="UNKNOWN"
if [ ! -z "$ALL_PEERINGS" ]; then
    # Ищем peering, который содержит "redis" в имени
    REDIS_PEERING=$(echo "$ALL_PEERINGS" | grep -i "redis" | head -1 || echo "")
    if [ -z "$REDIS_PEERING" ]; then
        # Если не нашли по "redis", берем первый peering (обычно для Memorystore это единственный)
        REDIS_PEERING=$(echo "$ALL_PEERINGS" | head -1 || echo "")
    fi
fi

if [ ! -z "$REDIS_PEERING" ]; then
    # Получаем состояние peering из описания сети
    # Ищем блок с именем peering и извлекаем состояние из следующей строки
    PEERING_BLOCK=$(gcloud compute networks describe default --format="yaml" 2>/dev/null | grep -A 15 "name: $REDIS_PEERING" | head -15 || echo "")
    PEERING_STATE=$(echo "$PEERING_BLOCK" | grep "state:" | sed 's/.*state: //' | head -1 || echo "UNKNOWN")
    PEERING_NETWORK=$(echo "$PEERING_BLOCK" | grep "network:" | sed 's/.*network: //' | head -1 || echo "")
    
    echo "   ✅ VPC Peering найден: $REDIS_PEERING"
    echo "      Состояние: $PEERING_STATE"
    if [ ! -z "$PEERING_NETWORK" ]; then
        echo "      Peer Network: $PEERING_NETWORK"
    fi
    
    if [ "$PEERING_STATE" = "ACTIVE" ]; then
        echo "      ✅ Peering активен и готов к использованию"
    else
        echo "      ⚠️ ВНИМАНИЕ: VPC Peering не в состоянии ACTIVE!"
        echo "         Это может быть причиной проблем с подключением к Redis"
    fi
else
    echo "   ⚠️ VPC Peering для Redis не найден!"
    echo "      Memorystore должен автоматически создавать peering при создании инстанса"
    echo "      Проверьте в консоли: VPC Network → VPC Network Peering"
    if [ ! -z "$ALL_PEERINGS" ]; then
        echo "      Все найденные peerings:"
        echo "$ALL_PEERINGS" | while IFS= read -r peering; do
            echo "        - $peering"
        done
    fi
fi

# Проверяем firewall правила для порта 6379
echo "   Проверяем firewall правила для порта 6379..."
FIREWALL_6379=$(gcloud compute firewall-rules list --filter="network:default AND allowed.ports:6379" --format="value(name)" 2>/dev/null | head -1 || echo "")
if [ ! -z "$FIREWALL_6379" ]; then
    echo "   ✅ Firewall правило для порта 6379 найдено: $FIREWALL_6379"
else
    echo "   ℹ️ Firewall правило для порта 6379 не найдено (это нормально для Memorystore)"
    echo "      Memorystore использует authorized networks вместо firewall правил"
fi

# Проверяем доступность Redis через VPC Connector
echo "   Проверяем доступность Redis через VPC Connector..."
if [ ! -z "$REDIS_IP" ] && [ ! -z "$REDIS_ENDPOINT" ]; then
    # Проверяем, что Redis IP находится в приватном диапазоне
    if [[ "$REDIS_IP" =~ ^10\. ]] || [[ "$REDIS_IP" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] || [[ "$REDIS_IP" =~ ^192\.168\. ]]; then
        echo "      ✅ Redis IP ($REDIS_IP) находится в приватном диапазоне"
        echo "      ✅ VPC Connector должен маршрутизировать трафик к Redis"
        
        # Проверяем, что маршрут существует
        if [ ! -z "$ROUTE_EXISTS" ]; then
            echo "      ✅ Маршрут к Redis существует и активен"
        else
            echo "      ⚠️ Маршрут к Redis не найден - это может быть проблемой!"
        fi
        
        # Проверяем, что VPC Peering активен
        if [ ! -z "$REDIS_PEERING" ] && [ "$PEERING_STATE" = "ACTIVE" ]; then
            echo "      ✅ VPC Peering активен - подключение должно работать"
        else
            echo "      ⚠️ VPC Peering не активен или не найден - это может быть проблемой!"
        fi
    else
        echo "      ⚠️ Redis IP ($REDIS_IP) не в приватном диапазоне"
        echo "      Это может быть проблемой для подключения через VPC Connector"
    fi
fi

# Финальная сводка диагностики
echo ""
echo "📊 СВОДКА ДИАГНОСТИКИ ПОДКЛЮЧЕНИЯ К REDIS:"
DIAGNOSTIC_ISSUES=0

if [ -z "$REDIS_IP" ] || [ -z "$REDIS_ENDPOINT" ]; then
    echo "   ❌ Redis IP не определен"
    DIAGNOSTIC_ISSUES=$((DIAGNOSTIC_ISSUES + 1))
else
    echo "   ✅ Redis IP определен: $REDIS_IP"
fi

if [ -z "$ROUTE_EXISTS" ]; then
    echo "   ❌ Маршрут к Redis не найден"
    DIAGNOSTIC_ISSUES=$((DIAGNOSTIC_ISSUES + 1))
else
    echo "   ✅ Маршрут к Redis существует"
fi

if [ -z "$REDIS_PEERING" ] || [ "$PEERING_STATE" != "ACTIVE" ]; then
    echo "   ❌ VPC Peering не активен или не найден"
    DIAGNOSTIC_ISSUES=$((DIAGNOSTIC_ISSUES + 1))
else
    echo "   ✅ VPC Peering активен: $REDIS_PEERING"
fi

VPC_STATE=$(gcloud compute networks vpc-access connectors describe $VPC_CONNECTOR --region=$REGION --format="value(state)" 2>/dev/null || echo "UNKNOWN")
if [ "$VPC_STATE" != "READY" ]; then
    echo "   ❌ VPC Connector не в состоянии READY: $VPC_STATE"
    DIAGNOSTIC_ISSUES=$((DIAGNOSTIC_ISSUES + 1))
else
    echo "   ✅ VPC Connector готов: $VPC_CONNECTOR"
fi

if [ $DIAGNOSTIC_ISSUES -eq 0 ]; then
    echo ""
    echo "   ✅ Все проверки пройдены успешно!"
    echo "   Приложение должно иметь возможность подключиться к Redis"
else
    echo ""
    echo "   ⚠️ Найдено проблем: $DIAGNOSTIC_ISSUES"
    echo "   Проверьте конфигурацию выше и исправьте проблемы перед развертыванием"
fi
echo ""

# Проверка существования Artifact Registry репозитория
echo "🔍 Проверяем Artifact Registry репозиторий..."
if ! gcloud artifacts repositories describe docmost-repo --location=$REGION &>/dev/null; then
    echo "📦 Создаем Artifact Registry репозиторий..."
    gcloud artifacts repositories create docmost-repo \
        --repository-format=docker \
        --location=$REGION \
        --description="Docker repository for Docmost" \
        --quiet
else
    echo "✅ Artifact Registry репозиторий уже существует"
fi

# Сборка и загрузка образа
echo "🏗️  Собираем и загружаем Docker образ..."
gcloud builds submit --tag ${IMAGE_NAME}:latest

# Подготовка переменных окружения для Cloud Run
# PORT убран - Cloud Run устанавливает его автоматически

# Функция для безопасного добавления переменной окружения
add_env_var() {
    local key=$1
    local value=$2
    if [ ! -z "$value" ]; then
        # Экранируем запятые и кавычки в значениях для gcloud
        local escaped_value=$(echo "$value" | sed 's/,/\\,/g' | sed 's/"/\\"/g')
        if [ -z "$ENV_VARS" ]; then
            ENV_VARS="${key}=${escaped_value}"
        else
            ENV_VARS="${ENV_VARS},${key}=${escaped_value}"
        fi
    fi
}

ENV_VARS=""
add_env_var "NODE_ENV" "production"

# Преобразуем DATABASE_URL для использования Private IP Cloud SQL
# Если DATABASE_URL содержит localhost, пытаемся получить Private IP Cloud SQL
DB_URL_FOR_CLOUD_RUN="$DATABASE_URL"
if [[ "$DATABASE_URL" == *"@localhost"* ]] || [[ "$DATABASE_URL" == *"@127.0.0.1"* ]]; then
    echo "🔍 Пытаемся получить IP адрес Cloud SQL..."
    
    # Получаем все IP адреса Cloud SQL
    CLOUD_SQL_IPS=$(gcloud sql instances describe docmost-2 --format="value(ipAddresses)" --project=$PROJECT_ID 2>/dev/null || echo "")
    
    # Ищем Private IP (начинается с 10.)
    CLOUD_SQL_PRIVATE_IP=$(echo "$CLOUD_SQL_IPS" | grep -oE "10\.[0-9]+\.[0-9]+\.[0-9]+" | head -1 || echo "")
    
    # Если Private IP не найден, ищем Public IP
    if [ -z "$CLOUD_SQL_PRIVATE_IP" ]; then
        echo "⚠️ Private IP не найден, пытаемся получить Public IP..."
        CLOUD_SQL_PUBLIC_IP=$(gcloud sql instances describe docmost-2 --format="get(ipAddresses[0].ipAddress)" --project=$PROJECT_ID 2>/dev/null | grep -vE "^10\." | head -1 || echo "")
        
        if [ ! -z "$CLOUD_SQL_PUBLIC_IP" ]; then
            echo "✅ Найден Public IP Cloud SQL: $CLOUD_SQL_PUBLIC_IP"
            CLOUD_SQL_IP="$CLOUD_SQL_PUBLIC_IP"
            USE_PUBLIC_IP=true
        else
            echo "❌ ОШИБКА: Не удалось найти ни Private, ни Public IP Cloud SQL!"
            echo "   Проверьте, что Cloud SQL инстанс существует и имеет IP адрес"
            exit 1
        fi
    else
        echo "✅ Найден Private IP Cloud SQL: $CLOUD_SQL_PRIVATE_IP"
        CLOUD_SQL_IP="$CLOUD_SQL_PRIVATE_IP"
        USE_PUBLIC_IP=false
    fi
    
    # Извлекаем части из connection string
    # Формат: postgresql://user:pass@host/dbname
    if [[ "$DATABASE_URL" =~ postgresql://([^:]+):([^@]+)@([^/]+)/(.+) ]]; then
        DB_USER="${BASH_REMATCH[1]}"
        DB_PASS="${BASH_REMATCH[2]}"
        DB_NAME="${BASH_REMATCH[4]}"
        
        # Удаляем query параметры из DB_NAME, если есть
        DB_NAME="${DB_NAME%%\?*}"
        
        # Формируем новый URL с IP адресом
        DB_URL_FOR_CLOUD_RUN="postgresql://${DB_USER}:${DB_PASS}@${CLOUD_SQL_IP}:5432/${DB_NAME}"
        
        if [ "$USE_PUBLIC_IP" = true ]; then
            echo "✅ Преобразовали DATABASE_URL для использования Public IP: $CLOUD_SQL_IP"
            echo "   ⚠️ ВНИМАНИЕ: Используется Public IP. Убедитесь, что:"
            echo "   1. Cloud SQL разрешает подключения с вашего IP"
            echo "   2. Firewall правила настроены правильно"
        else
            echo "✅ Преобразовали DATABASE_URL для использования Private IP: $CLOUD_SQL_IP"
        fi
    else
        echo "❌ ОШИБКА: Не удалось распарсить DATABASE_URL!"
        echo "   Проверьте формат DATABASE_URL в .env файле"
        exit 1
    fi
fi

add_env_var "DATABASE_URL" "$DB_URL_FOR_CLOUD_RUN"
add_env_var "CLOUD_SQL_INSTANCE" "$CLOUD_SQL_INSTANCE"

# Убеждаемся, что REDIS_URL использует IPv4 (family=4) для правильной маршрутизации через VPC
REDIS_URL_FOR_CLOUD_RUN="$REDIS_URL"
if [[ "$REDIS_URL" != *"family=4"* ]]; then
    if [[ "$REDIS_URL" == *"?"* ]]; then
        REDIS_URL_FOR_CLOUD_RUN="${REDIS_URL}&family=4"
    else
        REDIS_URL_FOR_CLOUD_RUN="${REDIS_URL}?family=4"
    fi
    echo "✅ Добавили family=4 в REDIS_URL для IPv4 маршрутизации"
fi

add_env_var "REDIS_URL" "$REDIS_URL_FOR_CLOUD_RUN"
add_env_var "APP_SECRET" "$APP_SECRET"

# Не передаем APP_URL, если это placeholder значение
if [ ! -z "$APP_URL" ] && [[ "$APP_URL" != *"your-app-url.com"* ]] && [[ "$APP_URL" != *"localhost"* ]]; then
    add_env_var "APP_URL" "$APP_URL"
    echo "✅ APP_URL установлен: $APP_URL"
else
    echo "⚠️ APP_URL не установлен или содержит placeholder - будет установлен после получения URL сервиса"
fi

if [ ! -z "$STORAGE_DRIVER" ]; then
    add_env_var "STORAGE_DRIVER" "$STORAGE_DRIVER"
    add_env_var "AWS_S3_REGION" "$AWS_S3_REGION"
    add_env_var "AWS_S3_BUCKET" "$AWS_S3_BUCKET"
    add_env_var "AWS_S3_ENDPOINT" "$AWS_S3_ENDPOINT"
    add_env_var "AWS_S3_ACCESS_KEY_ID" "$AWS_S3_ACCESS_KEY_ID"
    add_env_var "AWS_S3_SECRET_ACCESS_KEY" "$AWS_S3_SECRET_ACCESS_KEY"
    add_env_var "AWS_S3_FORCE_PATH_STYLE" "$AWS_S3_FORCE_PATH_STYLE"
fi

# Развертывание на Cloud Run
echo "🚀 Развертываем на Cloud Run..."
gcloud run deploy $SERVICE_NAME \
    --image ${IMAGE_NAME}:latest \
    --region $REGION \
    --platform managed \
    --allow-unauthenticated \
    --vpc-connector $VPC_CONNECTOR \
    --vpc-egress all-traffic \
    --add-cloudsql-instances $CLOUD_SQL_INSTANCE \
    --set-env-vars "$ENV_VARS" \
    --memory 2Gi \
    --cpu 2 \
    --timeout 600 \
    --cpu-boost \
    --max-instances 2 \
    --min-instances 1 \
    --startup-probe=initialDelaySeconds=60,periodSeconds=10,failureThreshold=30,tcpSocket.port=8080 \
    --quiet

# Получение URL сервиса
SERVICE_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format='value(status.url)')

echo ""
echo "✅ Развертывание завершено!"
echo "🌐 URL сервиса: $SERVICE_URL"
echo ""
echo "📝 Следующие шаги:"
echo "1. Обновите APP_URL в .env файле: APP_URL=$SERVICE_URL"
echo "2. Обновите сервис: gcloud run services update $SERVICE_NAME --region $REGION --update-env-vars APP_URL=$SERVICE_URL"
echo "3. Выполните миграции базы данных (если еще не выполнены)"
echo "4. Откройте $SERVICE_URL в браузере"
