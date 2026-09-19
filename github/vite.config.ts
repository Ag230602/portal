import {defineConfig,type Plugin} from 'vite';
import react from '@vitejs/plugin-react';
import {fileURLToPath} from 'node:url';
import {existsSync} from 'node:fs';
// GitHub Pages cannot rewrite SPA paths. Emit real dashboard index files so refreshes work.
function dashboardPages():Plugin{return {name:'dashboard-pages',enforce:'post',generateBundle(_options,bundle){const index=bundle['index.html'];if(!index||index.type!=='asset')throw new Error('Missing portal entry HTML.');for(const role of ['student','coordinator','admin'])this.emitFile({type:'asset',fileName:role+'/dashboard/index.html',source:index.source});}};}
const repoName=process.env.GITHUB_REPOSITORY?.split('/')[1];
const projectBase=process.env.GITHUB_ACTIONS==='true'&&repoName&&!repoName.endsWith('.github.io')&&!existsSync(fileURLToPath(new URL('../public/CNAME',import.meta.url)))?'/'+repoName+'/':'/';
export default defineConfig({root:fileURLToPath(new URL('.',import.meta.url)),publicDir:'../public',base:process.env.GITHUB_PAGES_BASE||projectBase,plugins:[react(),dashboardPages()],build:{outDir:'../dist-github',emptyOutDir:true},server:{host:'127.0.0.1',port:5173,strictPort:true}});
