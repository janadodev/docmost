# Проверка авторизации Google Cloud

## Текущий статус:

✅ **gcloud установлен**: Google Cloud SDK 527.0.0
✅ **Аккаунт авторизован**: dev@janado.de
⚠️ **Текущий проект**: megatools-dev (нужно переключить на docmost-484110)

## Что нужно сделать:

### 1. Переключить проект на docmost-484110:

```bash
gcloud config set project docmost-484110
```

### 2. Проверить авторизацию (если нужно):

```bash
gcloud auth login
```

### 3. Проверить доступ к проекту:

```bash
gcloud projects describe docmost-484110
```

## После проверки:

Убедитесь, что:
- ✅ Проект переключен на `docmost-484110`
- ✅ Вы авторизованы как `dev@janado.de`
- ✅ У вас есть права на проект `docmost-484110`

## Если нужно авторизоваться заново:

```bash
gcloud auth login
gcloud auth application-default login
```

Второй команда нужна для доступа к API из приложений.
