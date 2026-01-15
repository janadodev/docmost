import * as bcrypt from 'bcrypt';
import * as dotenv from 'dotenv';
import * as path from 'path';
import pg from 'pg';

// Загружаем переменные окружения
const envPath = path.resolve(__dirname, '.env');
dotenv.config({ path: envPath });

async function resetAdminPassword(email: string, newPassword: string) {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL не найден в .env файле');
  }

  // Генерируем хеш пароля
  const saltRounds = 12;
  const passwordHash = await bcrypt.hash(newPassword, saltRounds);

  // Подключаемся к базе данных
  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
  });

  try {
    await client.connect();
    console.log('Подключение к базе данных установлено');

    // Обновляем пароль
    const result = await client.query(
      `UPDATE users 
       SET password = $1, 
           has_generated_password = false,
           updated_at = NOW()
       WHERE email = $2
       RETURNING id, email, name, role`,
      [passwordHash, email]
    );

    if (result.rows.length === 0) {
      console.error(`Пользователь с email ${email} не найден`);
      process.exit(1);
    }

    const user = result.rows[0];
    console.log('\n✅ Пароль успешно обновлен!');
    console.log(`Email: ${user.email}`);
    console.log(`Имя: ${user.name}`);
    console.log(`Роль: ${user.role}`);
    console.log(`\nНовый пароль: ${newPassword}`);
  } catch (error) {
    console.error('Ошибка при обновлении пароля:', error);
    process.exit(1);
  } finally {
    await client.end();
  }
}

// Получаем аргументы из командной строки
const email = process.argv[2] || 'ip@janado.de';
const newPassword = process.argv[3];

if (!newPassword) {
  console.error('Использование: tsx reset-admin-password.ts [email] [новый_пароль]');
  console.error('Пример: tsx reset-admin-password.ts ip@janado.de mynewpassword123');
  process.exit(1);
}

resetAdminPassword(email, newPassword);
