# Настройка домена wiki.megatools.janado.de для Docmost

## Простой способ (через Google Cloud Console)

### Шаг 1: Создание Domain Mapping в Cloud Run

1. Откройте [Google Cloud Console](https://console.cloud.google.com/)
2. Выберите проект **docmost-484110**
3. Перейдите в **Cloud Run** → выберите сервис **docmost**
4. Перейдите на вкладку **"Domain mappings"** (или **"Доменные сопоставления"**)
5. Нажмите **"Add mapping"** (или **"Добавить сопоставление"**)
6. Введите домен: `wiki.megatools.janado.de`
7. Нажмите **"Continue"**

### Шаг 2: Верификация домена

Google предоставит **TXT-запись** для верификации. Пример:
```
Name: wiki.megatools.janado.de.
Type: TXT
Value: google-site-verification=XXXXXXXXXXXXX
```

**Добавьте эту TXT-запись в вашу DNS зону `megatool-janado-de`:**

1. Откройте DNS зону `megatool-janado-de` в другом проекте
2. Нажмите **"+ Add standard"**
3. Заполните:
   - **DNS name**: `wiki.megatools.janado.de.`
   - **Type**: `TXT`
   - **TTL**: `300`
   - **Record data**: значение из Google (например, `google-site-verification=XXXXXXXXXXXXX`)
4. Сохраните

### Шаг 3: Ожидание верификации

После добавления TXT-записи:
- Подождите 5-15 минут для распространения DNS
- Вернитесь в Cloud Run Domain Mappings
- Нажмите **"Verify"** или дождитесь автоматической верификации

### Шаг 4: Получение A-записей

После верификации Google предоставит **A-записи**. Пример:
```
Name: wiki.megatools.janado.de.
Type: A
Data: 216.239.32.21
Data: 216.239.34.21
Data: 216.239.36.21
Data: 216.239.38.21
```

### Шаг 5: Добавление A-записей в DNS зону

**Добавьте все A-записи в вашу DNS зону:**

1. В DNS зоне `megatool-janado-de` нажмите **"+ Add standard"**
2. Для каждой A-записи:
   - **DNS name**: `wiki.megatools.janado.de.`
   - **Type**: `A`
   - **TTL**: `300`
   - **Record data**: IP адрес (например, `216.239.32.21`)
3. Сохраните все записи

**Или добавьте все IP адреса одной записью (если ваша DNS зона поддерживает множественные значения):**
- **DNS name**: `wiki.megatools.janado.de.`
- **Type**: `A`
- **TTL**: `300`
- **Record data**: `216.239.32.21, 216.239.34.21, 216.239.36.21, 216.239.38.21`

### Шаг 6: Ожидание распространения DNS

- DNS изменения распространяются обычно за 1-2 часа
- Можно проверить через: `dig wiki.megatools.janado.de`

### Шаг 7: Обновление APP_URL

После того, как домен начнет работать:

```bash
gcloud run services update docmost \
  --region=europe-west1 \
  --update-env-vars="APP_URL=https://wiki.megatools.janado.de" \
  --project=docmost-484110
```

### Шаг 8: Проверка

```bash
# Проверка DNS
dig wiki.megatools.janado.de

# Проверка health endpoint
curl https://wiki.megatools.janado.de/api/health

# Проверка статуса domain mapping
gcloud beta run domain-mappings describe wiki.megatools.janado.de \
  --region=europe-west1 \
  --project=docmost-484110
```

---

## Альтернативный способ (через gcloud CLI)

Если вы хотите использовать командную строку, сначала нужно верифицировать домен:

### 1. Верификация домена

```bash
# Это откроет браузер для верификации через Google Search Console
gcloud domains verify wiki.megatools.janado.de
```

Или добавьте TXT-запись вручную (см. Шаг 2 выше).

### 2. Создание domain mapping

```bash
gcloud beta run domain-mappings create \
  --service=docmost \
  --domain=wiki.megatools.janado.de \
  --region=europe-west1 \
  --project=docmost-484110
```

### 3. Получение DNS записей

```bash
gcloud beta run domain-mappings describe wiki.megatools.janado.de \
  --region=europe-west1 \
  --format="get(status.resourceRecords)" \
  --project=docmost-484110
```

### 4. Добавление A-записей в DNS зону

Добавьте полученные A-записи в зону `megatool-janado-de` (как в Шаге 5 выше).

---

## Важные замечания

1. **SSL сертификат**: Google автоматически выдает SSL сертификат после настройки domain mapping (может занять до 24 часов)

2. **DNS зона в другом проекте**: Убедитесь, что у вас есть доступ к проекту с DNS зоной `megatool-janado-de`

3. **Время распространения**: DNS изменения могут занять 1-2 часа

4. **APP_URL**: Обязательно обновите `APP_URL` после настройки домена

5. **Проверка**: Используйте `dig` или онлайн DNS checker для проверки DNS записей

---

## Устранение проблем

### Домен не верифицируется

- Убедитесь, что TXT-запись добавлена правильно
- Проверьте, что DNS изменения распространились: `dig -t TXT wiki.megatools.janado.de`
- Подождите 15-30 минут после добавления TXT-записи

### A-записи не работают

- Проверьте, что все A-записи добавлены
- Проверьте DNS: `dig wiki.megatools.janado.de`
- Убедитесь, что нет конфликтующих CNAME записей

### SSL сертификат не выдается

- Это может занять до 24 часов
- Проверьте статус в Cloud Run Domain Mappings
- Убедитесь, что A-записи настроены правильно
