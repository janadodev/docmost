# Локальная разработка Docmost

Данная документация описывает процесс настройки и запуска Docmost для локальной разработки.

## Требования

- **Node.js**: версия 20.19+ или 22.12+ (рекомендуется 22.16.0)
- **pnpm**: версия 10.4.0
- **Docker** и **Docker Compose** (для PostgreSQL и Redis)
- **nvm** (опционально, для управления версиями Node.js)

## Первоначальная настройка

### 1. Установка зависимостей

```bash
pnpm install
```

### 2. Настройка базы данных и Redis

Запустите PostgreSQL и Redis через Docker Compose:

```bash
docker compose up -d db redis
```

Или используйте локально установленные PostgreSQL 16 и Redis.

### 3. Создание файла `.env`

Создайте файл `.env` в корне проекта со следующим содержимым:

```env
# База данных PostgreSQL
# Для локальной разработки используем localhost вместо db (имя сервиса в Docker)
DATABASE_URL=postgresql://docmost:docmostdevpass@localhost:5432/docmost?schema=public

# Redis
# Для локальной разработки используем localhost вместо redis (имя сервиса в Docker)
REDIS_URL=redis://localhost:6379

# URL приложения
APP_URL=http://localhost:3000

# Секретный ключ (минимум 32 символа, сгенерирован автоматически)
APP_SECRET=rTKwd7V5EA0f+D0fHeEyP1CUvTxMuES0CRDLo9Wn5jo=

# Хранилище файлов (local для локальной разработки)
STORAGE_DRIVER=local

# Поиск (database для локальной разработки, typesense для продакшена)
SEARCH_DRIVER=database
```

**Важно:**
- Если вы используете Docker Compose для БД, пароль должен совпадать с паролем из `docker-compose.yml`
- `APP_SECRET` должен быть не менее 32 символов и не равен `REPLACE_WITH_LONG_SECRET`
- Для генерации нового секретного ключа: `openssl rand -base64 32 | tr -d '\n' | head -c 64`

### 4. Создание базы данных (если еще не создана)

Если база данных еще не создана, создайте её:

```bash
# Подключитесь к PostgreSQL и создайте базу данных
docker exec -it docmost-db-1 psql -U postgres
CREATE DATABASE docmost;
CREATE USER docmost WITH PASSWORD 'docmostdevpass';
GRANT ALL PRIVILEGES ON DATABASE docmost TO docmost;
\q
```

Или если используете локальный PostgreSQL:

```bash
psql -U postgres
CREATE DATABASE docmost;
CREATE USER docmost WITH PASSWORD 'docmostdevpass';
GRANT ALL PRIVILEGES ON DATABASE docmost TO docmost;
\q
```

### 5. Применение миграций базы данных

```bash
pnpm --filter ./apps/server run migration:latest
```

### 6. Сборка пакета editor-ext

```bash
pnpm run editor-ext:build
```

### 7. Переключение на правильную версию Node.js

Если используется nvm:

```bash
source ~/.nvm/nvm.sh
nvm use 22.16.0
```

## Запуск приложения

### Запуск в режиме разработки (рекомендуется)

Запускает фронтенд и бэкенд одновременно:

```bash
pnpm run dev
```

Это запустит:
- **Фронтенд** (клиент) на `http://localhost:5173/`
- **Бэкенд** (сервер) на `http://localhost:3000`

### Альтернативный вариант: запуск сервисов отдельно

Если нужно запускать сервисы в отдельных терминалах:

**Терминал 1 - Клиент:**
```bash
pnpm run client:dev
```

**Терминал 2 - Сервер:**
```bash
pnpm run server:dev
```

**Терминал 3 - Collaboration сервер (опционально):**
```bash
pnpm run collab:dev
```

## Остановка приложения

### Остановка всех процессов

```bash
pkill -f "pnpm run dev"
pkill -f "concurrently"
```

Или нажмите `Ctrl+C` в терминале, где запущен `pnpm run dev`.

### Остановка отдельных сервисов

```bash
# Остановить только бэкенд
pkill -f "nest start"

# Остановить только фронтенд
pkill -f "vite"
```

## Перезапуск приложения

### Полный перезапуск

1. Остановите все процессы:
```bash
pkill -f "pnpm run dev" && pkill -f "concurrently"
```

2. Убедитесь, что используете правильную версию Node.js:
```bash
source ~/.nvm/nvm.sh && nvm use 22.16.0
```

3. Запустите снова:
```bash
pnpm run dev
```

### Перезапуск после изменения tsconfig.json

После изменения `tsconfig.json` рекомендуется полный перезапуск, так как изменения могут не подхватиться автоматически.

## Управление базой данных

### Проверка статуса контейнеров

```bash
docker compose ps
```

### Остановка БД и Redis

```bash
docker compose stop db redis
```

### Запуск БД и Redis

```bash
docker compose start db redis
```

### Полный сброс базы данных

⚠️ **Внимание:** Это удалит все данные!

```bash
# Остановите приложение
pkill -f "pnpm run dev"

# Очистите базу данных
docker exec docmost-db-1 psql -U docmost -d docmost -c "TRUNCATE TABLE workspaces CASCADE;"

# Перезапустите приложение и создайте нового администратора через API
pnpm run dev
```

### Создание нового администратора

После сброса базы данных создайте нового администратора:

```bash
curl -X POST http://localhost:3000/api/auth/setup \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Admin User",
    "email": "admin@example.com",
    "password": "admin123",
    "workspaceName": "My Workspace"
  }'
```

## Сброс пароля администратора

Если забыли пароль администратора, используйте скрипт:

```bash
# Использование скрипта reset-admin-password.ts
pnpm exec tsx reset-admin-password.ts [email] [новый_пароль]

# Пример:
pnpm exec tsx reset-admin-password.ts admin@example.com newpassword123
```

Или сгенерируйте случайный пароль:

```bash
NEW_PASSWORD=$(openssl rand -base64 12 | tr -d '\n' | head -c 16)
pnpm exec tsx reset-admin-password.ts admin@example.com $NEW_PASSWORD
```

## Полезные команды

### Миграции базы данных

```bash
# Создать новую миграцию
pnpm --filter ./apps/server run migration:create

# Применить все миграции
pnpm --filter ./apps/server run migration:latest

# Применить миграции
pnpm --filter ./apps/server run migration:up

# Откатить миграции
pnpm --filter ./apps/server run migration:down

# Откатить все миграции
pnpm --filter ./apps/server run migration:reset
```

### Сборка проекта

```bash
# Собрать все приложения
pnpm run build

# Собрать только сервер
pnpm run server:build

# Собрать только клиент
pnpm run client:build

# Собрать editor-ext пакет
pnpm run editor-ext:build
```

### Проверка работы

```bash
# Проверка health endpoint
curl http://localhost:3000/api/health

# Проверка версии
curl -X POST http://localhost:3000/api/version -H "Content-Type: application/json"
```

## Проверка подключений

### Проверка подключения к PostgreSQL

```bash
docker exec docmost-db-1 psql -U docmost -d docmost -c "SELECT 1;"
```

### Проверка подключения к Redis

```bash
docker exec docmost-redis-1 redis-cli ping
```

### Проверка пользователей в базе данных

```bash
docker exec docmost-db-1 psql -U docmost -d docmost -c "SELECT email, name, role FROM users;"
```

## Решение проблем

### Проблема: "password authentication failed"

Проверьте пароль в `.env` файле. Он должен совпадать с паролем в `docker-compose.yml`:

```bash
docker exec docmost-db-1 env | grep POSTGRES
```

### Проблема: "Vite requires Node.js version 20.19+ or 22.12+"

Убедитесь, что используете правильную версию Node.js:

```bash
node --version
source ~/.nvm/nvm.sh && nvm use 22.16.0
```

### Проблема: "Cannot find module '@docmost/editor-ext'"

Соберите пакет editor-ext:

```bash
pnpm run editor-ext:build
```

### Проблема: Порт уже занят

Найдите процесс, использующий порт:

```bash
# Для порта 3000
lsof -ti:3000

# Для порта 5173
lsof -ti:5173
```

Остановите процесс или измените порт в конфигурации.

### Проблема: Ошибки компиляции TypeScript

Убедитесь, что все зависимости установлены:

```bash
pnpm install
```

Проверьте версию Node.js и перезапустите сервер.

## Структура проекта

- `apps/server/` - Backend (NestJS)
- `apps/client/` - Frontend (React + Vite)
- `packages/editor-ext/` - Расширения редактора
- `.env` - Переменные окружения (не коммитится в git)

## Полезные ссылки

- [Официальная документация](https://docmost.com/docs)
- [Документация по разработке](https://docmost.com/docs/self-hosting/development)

## Примечания

- В dev-режиме сервер автоматически перезапускается при изменении файлов (watch mode)
- Изменения в `tsconfig.json` требуют полного перезапуска
- База данных и Redis должны быть запущены перед запуском приложения
- Для production build используйте `pnpm run build` и `pnpm run start`
