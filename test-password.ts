import * as bcrypt from 'bcrypt';
import * as dotenv from 'dotenv';
import * as path from 'path';
import pg from 'pg';

// Загружаем переменные окружения
const envPath = path.resolve(__dirname, '.env');
dotenv.config({ path: envPath });

async function testPassword(email: string, password: string) {
  if (!process.env.DATABASE_URL) {
    throw new Error('DATABASE_URL не найден в .env файле');
  }

  const client = new pg.Client({
    connectionString: process.env.DATABASE_URL,
  });

  try {
    await client.connect();
    console.log('Подключение к базе данных установлено');

    // Получаем хеш пароля из базы
    const result = await client.query(
      `SELECT password FROM users WHERE email = $1`,
      [email]
    );

    if (result.rows.length === 0) {
      console.error(`Пользователь с email ${email} не найден`);
      process.exit(1);
    }

    const passwordHash = result.rows[0].password;
    console.log(`Хеш пароля из БД: ${passwordHash?.substring(0, 20)}...`);
    console.log(`Длина хеша: ${passwordHash?.length}`);

    // Проверяем пароль
    const isValid = await bcrypt.compare(password, passwordHash);
    console.log(`\nПроверка пароля "${password}": ${isValid ? '✅ ВЕРНО' : '❌ НЕВЕРНО'}`);

    // Генерируем новый хеш для сравнения
    const newHash = await bcrypt.hash(password, 12);
    console.log(`\nНовый хеш для "${password}": ${newHash.substring(0, 20)}...`);
    
    const isValidNew = await bcrypt.compare(password, newHash);
    console.log(`Проверка нового хеша: ${isValidNew ? '✅ ВЕРНО' : '❌ НЕВЕРНО'}`);

  } catch (error) {
    console.error('Ошибка:', error);
    process.exit(1);
  } finally {
    await client.end();
  }
}

const email = process.argv[2] || 'ip@janado.de';
const password = process.argv[3] || 'SG4Vsu8oA7SUAVmY';

testPassword(email, password);
