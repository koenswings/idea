// Uploaded by kit-kolibri-morango.sh to <engine checkout>/script/.zz-kolibri-morango.ts (untracked).
// list: print one JSON line per Kolibri-family instance docked on THIS Engine (read-only).
// cmd <command...>: push one Engine command (same path as the Console) and wait for its trace.
import { Repo, DocumentId } from '@automerge/automerge-repo'
import { WebSocketClientAdapter } from '@automerge/automerge-repo-network-websocket'
import fs from 'fs'; import os from 'os'
const [mode, ...rest] = process.argv.slice(2); const CMD = rest.join(' ')
const su = fs.readFileSync('store-identity/store-url.txt','utf8').trim(), lu = fs.readFileSync('store-identity/command-log-url.txt','utf8').trim()
const port = (fs.readFileSync('config.yaml','utf8').match(/^\s*port:\s*(\d+)/m)||[])[1] || '4321'
const repo = new Repo({ network: [new WebSocketClientAdapter('ws://127.0.0.1:'+port)] })
const to = setTimeout(() => { console.log(JSON.stringify({ error: 'timeout' })); process.exit(3) }, 360000)
const h = await repo.find<any>(su.replace('automerge:','') as DocumentId); await h.whenReady()
const lh = await repo.find<any>(lu.replace('automerge:','') as DocumentId); await lh.whenReady(); await new Promise(r=>setTimeout(r,1500))
const s = h.doc(); const eng:any = Object.values(s.engineDB??{}).find((e:any)=>e.hostname===os.hostname())
if (!eng) { console.log(JSON.stringify({ error: 'local engine not in store' })); process.exit(3) }
if (mode === 'list') {
  for (const i of Object.values<any>(s.instanceDB??{})) {
    const d = i.storedOn && s.diskDB?.[i.storedOn]
    if (!d || d.dockedTo !== eng.id) continue
    console.log(JSON.stringify({ id: i.id, name: i.name, instanceOf: i.instanceOf, status: i.status, diskId: i.storedOn, device: d.device ?? '', port: i.port ?? '' }))
  }
} else if (mode === 'cmd' && CMD) {
  const t0 = Date.now(); h.change((d:any)=>{ d.engineDB[eng.id].commands.push(CMD) })
  for (let k=0;k<300;k++){ await new Promise(r=>setTimeout(r,1000)); const t:any=Object.values(lh.doc()?.traces??{}).find((t:any)=>t.startedAt>=t0-2000&&CMD.startsWith(t.command)&&t.completedAt&&t.status!=='running'); if(t){console.log(JSON.stringify({ trace: t.command, status: t.status, error: String(t.error??'').slice(0,200) }));clearTimeout(to);process.exit(t.status==='failed'||t.status==='error'?4:0)} }
  console.log(JSON.stringify({ error: 'no trace' })); process.exit(4)
} else { console.log(JSON.stringify({ error: 'usage' })); process.exit(2) }
clearTimeout(to); process.exit(0)
