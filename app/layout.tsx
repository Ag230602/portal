import type {Metadata} from 'next';
import {headers} from 'next/headers';
import './globals.css';
export async function generateMetadata():Promise<Metadata>{const h=await headers();const host=h.get('host')||'naac-point-five-portal.crafty-rice-4042.chatgpt.site';const origin=(host.startsWith('localhost')?'http://':'https://')+host;return {title:'NAAC Point-5 | Data Collection & AI Summary Portal',description:'Collect institutional data, preserve evidence, and prepare traceable NAAC Point-5 reports.',openGraph:{title:'NAAC Point-5',description:'Data Collection & AI Summary Portal',images:[{url:origin+'/og.png',width:1536,height:1024}]},twitter:{card:'summary_large_image',title:'NAAC Point-5',images:[origin+'/og.png']}};}
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="en"><body>{children}</body></html>;}
