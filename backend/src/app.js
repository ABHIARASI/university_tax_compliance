// Builds the Express app: security middleware -> routes -> error handling.
// (server.js starts it; keeping them apart lets tests use the app without a port.)
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import { env } from './config/env.js';
import { pool } from './config/db.js';
import authRoutes from './routes/auth.routes.js';
import metaRoutes from './routes/meta.routes.js';
import universityRoutes from './routes/university.routes.js';
import adminRoutes from './routes/admin.routes.js';
import { notFound, errorHandler } from './middleware/errorHandler.js';

export const app = express();

app.use(helmet());                                   // safe HTTP headers
app.use(cors({ origin: env.CLIENT_URL, credentials: true }));  // only our React app, with cookies
app.use(express.json({ limit: '100kb' }));           // read JSON bodies (and cap their size)
app.use(cookieParser());                             // read the login cookie

// health check: is the API up, and can it reach MySQL?
app.get('/api/health', async (req, res) => {
  await pool.query('SELECT 1');
  res.json({ status: 'ok', database: 'connected', time: new Date().toISOString() });
});

app.use('/api/auth', authRoutes);
app.use('/api/meta', metaRoutes);
app.use('/api/university', universityRoutes);
app.use('/api/admin', adminRoutes);

app.use(notFound);        // no route matched -> 404
app.use(errorHandler);    // any error -> one consistent JSON response
