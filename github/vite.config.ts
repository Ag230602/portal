import {defineConfig} from 'vite';
import react from '@vitejs/plugin-react';
import {fileURLToPath} from 'node:url';
export default defineConfig({root:fileURLToPath(new URL('.',import.meta.url)),publicDir:'../public',base:process.env.GITHUB_PAGES_BASE||'./',plugins:[react()],build:{outDir:'../dist-github',emptyOutDir:true},server:{host:'127.0.0.1'}});
