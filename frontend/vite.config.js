// Vite = the dev server and build tool for the React app.
// The proxy sends every /api request to the Express backend on port 5000,
// so the browser sees ONE origin (localhost:5173): the login cookie just works
// and there are no CORS problems in development.
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    chunkSizeWarningLimit: 1000,   // the chart library alone is ~500 kB
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:5000',
    },
  },
});
