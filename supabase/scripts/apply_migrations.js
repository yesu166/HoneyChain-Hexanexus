#!/usr/bin/env node
// HoneyChain — apply versioned Supabase migrations in order.
//
// Usage:
//   Set SUPABASE_DB_URL (direct PostgreSQL connection string, password
//   percent-encoded, sslmode=require) then:
//   npm run apply
//
//   Alternative CLI workflow (requires `supabase login` with an access token):
//     supabase link --project-ref <project-ref>
//     supabase db push

const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

// Load the sibling .env (SUPABASE_DB_URL) so `npm run apply` works out of
// the box. Real values live in the gitignored .env; .env.example documents
// the variable name only.
const envFile = path.resolve(__dirname, '.env');
if (fs.existsSync(envFile)) {
  for (const line of fs.readFileSync(envFile, 'utf8').split(/\r?\n/)) {
    if (line && !line.startsWith('#') && !process.env[line.split('=')[0]]) {
      const i = line.indexOf('=');
      if (i > 0) process.env[line.slice(0, i)] = line.slice(i + 1);
    }
  }
}

// Supabase direct endpoints terminate TLS with a CA chain that is not in the
// default trust store. This is a dev/admin tool: skip CA verification only
// when SUPABASE_DB_INSECURE=1 is explicitly set, never by default.
if (process.env.SUPABASE_DB_INSECURE === '1') {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

async function main() {
  const url = process.env.SUPABASE_DB_URL;
  if (!url) {
    console.error('SUPABASE_DB_URL is not set. See .env.example.');
    process.exit(1);
  }

  const client = new Client({ connectionString: url });
  await client.connect();

  const migrationsDir = path.resolve(__dirname, '../migrations');
  const files = fs
    .readdirSync(migrationsDir)
    .filter((f) => f.endsWith('.sql'))
    .sort();

  for (const file of files) {
    const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    console.log(`Applying ${file}...`);
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query('COMMIT');
      console.log(`  OK ${file}`);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`  FAILED ${file}: ${err.message}`);
      await client.end();
      process.exit(1);
    }
  }

  console.log('All migrations applied.');
  await client.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});