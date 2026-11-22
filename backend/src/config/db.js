// One shared CONNECTION POOL for the whole app.
// Opening a MySQL connection is slow, so the pool keeps up to 10 open and
// lends one to each query, then takes it back. Requests don't wait for a
// new connection every time, and MySQL isn't flooded with connections.
import mysql from 'mysql2/promise';
import { env } from './env.js';

export const pool = mysql.createPool({
  host: env.DB_HOST,
  port: env.DB_PORT,
  user: env.DB_USER,
  password: env.DB_PASSWORD,
  database: env.DB_NAME,
  connectionLimit: 10,
  dateStrings: true,      // DATE stays '2025-10-01' (no timezone shifting)
  decimalNumbers: true,   // DECIMAL comes back as a number, not a string
});

// Run a query. Values go in `params` and replace each ? safely:
// the driver escapes them, so user input can never change the SQL itself
// (this is what prevents SQL injection).
export async function query(sql, params = []) {
  const [rows] = await pool.query(sql, params);
  return rows;
}

// Run a stored procedure and return its first result set (the rows it SELECTs).
// `name` is always a fixed string from our own code, never user input.
export async function callProcedure(name, params = []) {
  const placeholders = params.map(() => '?').join(', ');
  const [results] = await pool.query(`CALL ${name}(${placeholders})`, params);
  return Array.isArray(results[0]) ? results[0] : [];
}

// Run several queries as ONE transaction on ONE connection:
// all of them are saved together (COMMIT), or none are (ROLLBACK).
export async function withTransaction(work) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    const result = await work(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();   // always give the connection back to the pool
  }
}
