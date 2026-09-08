const { Client } = require('pg');

async function main() {
  const client = new Client({
    host: 'db.hhxwhopaazqjdlreqhkf.supabase.co',
    port: 5432,
    user: 'postgres',
    password: process.env.PGPASSWORD,
    database: 'postgres',
  });
  await client.connect();
  try {
    const tables = await client.query(
      `select table_name from information_schema.tables
       where table_schema = 'public' and table_type = 'BASE TABLE'
       order by table_name`);
    console.log('TABLES:', tables.rows.map(r => r.table_name).join(', '));

    const policies = await client.query(
      `select policyname, tablename from pg_policies where schemaname = 'public' order by tablename, policyname`);
    console.log('POLICIES:', policies.rows.map(r => `${r.tablename}.${r.policyname}`).join(', '));

    const qr = await client.query(`select product_code, batch_id from qr_codes`);
    console.log('QR SEED:', JSON.stringify(qr.rows));
    const batch = await client.query(`select batch_code, trust_tier, status from batches`);
    console.log('BATCH SEED:', JSON.stringify(batch.rows));

    const fn = await client.query(
      `select p.oid::regprocedure as name, l.lanname
       from pg_proc p join pg_language l on l.oid = p.prolang
       where p.proname = 'get_public_passport'`);
    console.log('FUNCTION:', JSON.stringify(fn.rows));

    await client.query('SET ROLE anon');
    const passport = await client.query(`select public.get_public_passport('HC-2026-DEMO-001')`);
    console.log('AS ANON:', JSON.stringify(passport.rows[0].get_public_passport).slice(0, 500));
    const denied = await client.query(`select count(*) from batches`);
    console.log('ANON DIRECT TABLE ACCESS (should be blocked):', JSON.stringify(denied.rows));
    await client.query('RESET ROLE');
  } catch (e) {
    console.error('ERR', e.message);
  } finally {
    await client.end().catch(() => {});
  }
}
main();