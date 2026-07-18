import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // Dev convenience: forward API calls to the FastAPI backend.
      '/api': 'http://localhost:8000',
    },
  },
})
