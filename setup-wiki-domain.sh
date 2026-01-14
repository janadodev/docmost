#!/bin/bash

# Скрипт для настройки домена wiki.megatools.janado.de для Docmost
# Проект: docmost-484110
# DNS зона: megatool-janado-de (в другом проекте)

set -e

DOMAIN="wiki.megatools.janado.de"
SERVICE_NAME="docmost"
REGION="europe-west1"
PROJECT_ID="docmost-484110"

echo "=========================================="
echo "Настройка домена $DOMAIN для Docmost"
echo "=========================================="
echo ""

# Шаг 1: Создание резервного статического IP адреса
echo "Шаг 1: Создание резервного статического IP адреса..."
IP_NAME="docmost-wiki-ip"
EXISTING_IP=$(gcloud compute addresses describe $IP_NAME --global --format="get(address)" 2>/dev/null || echo "")

if [ -z "$EXISTING_IP" ]; then
    echo "Создаю новый IP адрес..."
    gcloud compute addresses create $IP_NAME \
        --global \
        --project=$PROJECT_ID
    EXISTING_IP=$(gcloud compute addresses describe $IP_NAME --global --format="get(address)")
    echo "✓ IP адрес создан: $EXISTING_IP"
else
    echo "✓ IP адрес уже существует: $EXISTING_IP"
fi

echo ""
echo "=========================================="
echo "ВАЖНО: Добавьте следующую A-запись в вашу DNS зону megatool-janado-de:"
echo ""
echo "DNS name: wiki.megatools.janado.de."
echo "Type: A"
echo "TTL: 300"
echo "Record data: $EXISTING_IP"
echo ""
echo "После добавления записи нажмите Enter для продолжения..."
read
echo ""

# Шаг 2: Создание SSL сертификата
echo "Шаг 2: Создание SSL сертификата..."
CERT_NAME="docmost-wiki-cert"
EXISTING_CERT=$(gcloud compute ssl-certificates describe $CERT_NAME --global --format="get(name)" 2>/dev/null || echo "")

if [ -z "$EXISTING_CERT" ]; then
    echo "Создаю SSL сертификат (это может занять несколько минут)..."
    gcloud compute ssl-certificates create $CERT_NAME \
        --domains=$DOMAIN \
        --global \
        --project=$PROJECT_ID
    echo "✓ SSL сертификат создан"
else
    echo "✓ SSL сертификат уже существует"
fi

echo ""

# Шаг 3: Создание backend service для Cloud Run
echo "Шаг 3: Создание backend service..."
BACKEND_SERVICE_NAME="docmost-wiki-backend"
EXISTING_BACKEND=$(gcloud compute backend-services describe $BACKEND_SERVICE_NAME --global --format="get(name)" 2>/dev/null || echo "")

if [ -z "$EXISTING_BACKEND" ]; then
    echo "Создаю backend service..."
    gcloud compute backend-services create $BACKEND_SERVICE_NAME \
        --global \
        --load-balancing-scheme=EXTERNAL \
        --protocol=HTTPS \
        --project=$PROJECT_ID
    
    # Добавляем Cloud Run сервис как backend
    CLOUD_RUN_URL=$(gcloud run services describe $SERVICE_NAME --region=$REGION --format="value(status.url)" --project=$PROJECT_ID)
    CLOUD_RUN_NAME=$(echo $CLOUD_RUN_URL | sed 's|https://||' | sed 's|.run.app||')
    
    echo "Добавляю Cloud Run сервис в backend..."
    gcloud compute backend-services add-backend $BACKEND_SERVICE_NAME \
        --global \
        --network-endpoint-group=$CLOUD_RUN_NAME \
        --network-endpoint-group-region=$REGION \
        --project=$PROJECT_ID
    
    echo "✓ Backend service создан"
else
    echo "✓ Backend service уже существует"
fi

echo ""

# Шаг 4: Создание URL map
echo "Шаг 4: Создание URL map..."
URL_MAP_NAME="docmost-wiki-urlmap"
EXISTING_URLMAP=$(gcloud compute url-maps describe $URL_MAP_NAME --global --format="get(name)" 2>/dev/null || echo "")

if [ -z "$EXISTING_URLMAP" ]; then
    echo "Создаю URL map..."
    gcloud compute url-maps create $URL_MAP_NAME \
        --default-service=$BACKEND_SERVICE_NAME \
        --global \
        --project=$PROJECT_ID
    echo "✓ URL map создан"
else
    echo "✓ URL map уже существует"
fi

echo ""

# Шаг 5: Создание target HTTPS proxy
echo "Шаг 5: Создание target HTTPS proxy..."
PROXY_NAME="docmost-wiki-https-proxy"
EXISTING_PROXY=$(gcloud compute target-https-proxies describe $PROXY_NAME --global --format="get(name)" 2>/dev/null || echo "")

if [ -z "$EXISTING_PROXY" ]; then
    echo "Создаю HTTPS proxy..."
    gcloud compute target-https-proxies create $PROXY_NAME \
        --url-map=$URL_MAP_NAME \
        --ssl-certificates=$CERT_NAME \
        --global \
        --project=$PROJECT_ID
    echo "✓ HTTPS proxy создан"
else
    echo "✓ HTTPS proxy уже существует"
fi

echo ""

# Шаг 6: Создание forwarding rule
echo "Шаг 6: Создание forwarding rule..."
RULE_NAME="docmost-wiki-forwarding-rule"
EXISTING_RULE=$(gcloud compute forwarding-rules describe $RULE_NAME --global --format="get(name)" 2>/dev/null || echo "")

if [ -z "$EXISTING_RULE" ]; then
    echo "Создаю forwarding rule..."
    gcloud compute forwarding-rules create $RULE_NAME \
        --address=$IP_NAME \
        --target-https-proxy=$PROXY_NAME \
        --ports=443 \
        --global \
        --project=$PROJECT_ID
    echo "✓ Forwarding rule создан"
else
    echo "✓ Forwarding rule уже существует"
fi

echo ""
echo "=========================================="
echo "Настройка завершена!"
echo ""
echo "IP адрес для DNS: $EXISTING_IP"
echo ""
echo "Теперь обновите APP_URL в Cloud Run:"
echo "gcloud run services update $SERVICE_NAME \\"
echo "  --region=$REGION \\"
echo "  --update-env-vars=\"APP_URL=https://$DOMAIN\" \\"
echo "  --project=$PROJECT_ID"
echo "=========================================="
