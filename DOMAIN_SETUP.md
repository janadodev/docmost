# Настройка кастомного домена для Docmost в Cloud Run

## Вариант 1: Простой домен (рекомендуется для self-hosted)

### Шаг 1: Создание domain mapping в Cloud Run

```bash
# Замените example.com на ваш домен
gcloud beta run domain-mappings create \
  --service=docmost \
  --domain=example.com \
  --region=europe-west1 \
  --project=docmost-484110
```

### Шаг 2: Получение DNS записей

После создания mapping, выполните:

```bash
gcloud beta run domain-mappings describe example.com \
  --region=europe-west1 \
  --format="get(status.resourceRecords)"
```

Вы получите что-то вроде:
```
NAME: example.com.
TYPE: A
DATA: 216.239.32.21

NAME: example.com.
TYPE: A
DATA: 216.239.34.21

NAME: example.com.
TYPE: A
DATA: 216.239.36.21

NAME: example.com.
TYPE: A
DATA: 216.239.38.21
```

### Шаг 3: Настройка DNS записей

Добавьте эти A-записи в настройках DNS вашего домена у регистратора:

1. Зайдите в панель управления вашего домена (где вы покупали домен)
2. Найдите раздел DNS / DNS Management
3. Добавьте A-записи с IP адресами, полученными на шаге 2
4. Сохраните изменения

**Важно:** DNS изменения могут занять от нескольких минут до 48 часов (обычно 1-2 часа)

### Шаг 4: Обновление APP_URL в Cloud Run

После того, как DNS записи применятся и домен начнет работать:

```bash
gcloud run services update docmost \
  --region=europe-west1 \
  --update-env-vars="APP_URL=https://example.com"
```

### Шаг 5: Проверка статуса domain mapping

```bash
gcloud beta run domain-mappings describe example.com \
  --region=europe-west1 \
  --format="get(status.conditions[0].status,status.url)"
```

Когда статус станет `True`, домен готов к использованию!

---

## Вариант 2: Субдомены (для multi-tenant режима)

Если вы хотите использовать субдомены (например, workspace1.example.com, workspace2.example.com):

### Шаг 1: Создание domain mapping для основного домена

```bash
gcloud beta run domain-mappings create \
  --service=docmost \
  --domain=example.com \
  --region=europe-west1 \
  --project=docmost-484110
```

### Шаг 2: Настройка DNS

Добавьте A-записи для основного домена (как в Варианте 1)

### Шаг 3: Настройка переменных окружения

```bash
gcloud run services update docmost \
  --region=europe-west1 \
  --update-env-vars="CLOUD=true,SUBDOMAIN_HOST=example.com,APP_URL=https://example.com"
```

**Примечание:** 
- `CLOUD=true` - включает режим multi-tenant с субдоменами
- `SUBDOMAIN_HOST=example.com` - базовый домен для субдоменов
- `APP_URL` - основной URL приложения

---

## Вариант 3: Использование Load Balancer (для продвинутых случаев)

Если нужен более гибкий контроль, можно использовать Cloud Load Balancer:

1. Создайте Load Balancer с SSL сертификатом
2. Настройте backend на Cloud Run сервис
3. Настройте DNS на IP Load Balancer

Это более сложный вариант, но дает больше контроля.

---

## Проверка работы

После настройки проверьте:

```bash
# Проверка health endpoint
curl https://example.com/api/health

# Проверка статуса domain mapping
gcloud beta run domain-mappings describe example.com \
  --region=europe-west1 \
  --format="yaml(status)"
```

---

## Важные замечания

1. **SSL сертификат:** Google автоматически выдает и обновляет SSL сертификаты для доменов, подключенных через domain mappings

2. **Время распространения DNS:** Обычно 1-2 часа, но может занять до 48 часов

3. **Проверка DNS:** Используйте `dig example.com` или онлайн инструменты для проверки DNS записей

4. **APP_URL:** Обязательно обновите `APP_URL` после настройки домена, иначе приложение может работать некорректно

5. **CORS и безопасность:** Убедитесь, что все ссылки в приложении используют правильный домен

---

## Устранение проблем

### Домен не работает после настройки DNS

1. Проверьте DNS записи:
   ```bash
   dig example.com
   ```

2. Проверьте статус domain mapping:
   ```bash
   gcloud beta run domain-mappings describe example.com --region=europe-west1
   ```

3. Убедитесь, что A-записи указывают на правильные IP адреса

### SSL сертификат не выдается

Google автоматически выдает сертификаты, но это может занять до 24 часов. Проверьте статус:

```bash
gcloud beta run domain-mappings describe example.com \
  --region=europe-west1 \
  --format="get(status.conditions)"
```

---

## Пример полной настройки

```bash
# 1. Создать domain mapping
DOMAIN="docmost.example.com"
gcloud beta run domain-mappings create \
  --service=docmost \
  --domain=$DOMAIN \
  --region=europe-west1

# 2. Получить DNS записи
gcloud beta run domain-mappings describe $DOMAIN \
  --region=europe-west1 \
  --format="get(status.resourceRecords)"

# 3. После настройки DNS и ожидания распространения (1-2 часа)
# Обновить APP_URL
gcloud run services update docmost \
  --region=europe-west1 \
  --update-env-vars="APP_URL=https://$DOMAIN"

# 4. Проверить статус
gcloud beta run domain-mappings describe $DOMAIN \
  --region=europe-west1 \
  --format="get(status.conditions[0].status,status.url)"
```
