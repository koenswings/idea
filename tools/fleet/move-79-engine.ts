// move-79-engine.ts — uploaded by move-79.sh to <engine checkout>/script/.zz-move-79.ts (untracked) on a pool Pi.
// Same store path as the Console and kit-kolibri-morango-engine.ts. Modes:
//   state                 one JSON line: this Engine (id, hostname, moveAppCrossEngine counted?), its docked
//                         disks and the instances stored on them (read-only)
//   find <name>           one JSON line per instance with that name anywhere in the store (read-only)
//   op <sourceInstanceId> the newest moveApp Operation whose subject is that id (read-only)
//   cmd <command...>      push ONE Engine command to THIS Engine and wait for its trace (MOVE_TIMEOUT s, default 5400)
import { Repo, DocumentId } from '@automerge/automerge-repo'
import { WebSocketClientAdapter } from '@automerge/automerge-repo-network-websocket'
import fs from 'fs'; import os from 'os'
const [mode, ...rest] = process.argv.slice(2); const CMD = rest.join(' ')
const LIMIT = Number(process.env.MOVE_TIMEOUT || 5400)
const out = (o: unknown) => console.log(JSON.stringify(o))
const su = fs.readFileSync('store-identity/store-url.txt', 'utf8').trim()
const lu = fs.readFileSync('store-identity/command-log-url.txt', 'utf8').trim()
const port = (fs.readFileSync('config.yaml', 'utf8').match(/^\s*port:\s*(\d+)/m) || [])[1] || '4321'
const repo = new Repo({ network: [new WebSocketClientAdapter('ws://127.0.0.1:' + port)] })
const to = setTimeout(() => { out({ error: 'timeout' }); process.exit(3) }, (LIMIT + 120) * 1000)
const h = await repo.find<any>(su.replace('automerge:', '') as DocumentId); await h.whenReady()
await new Promise(r => setTimeout(r, 1500))
const s = h.doc()
const eng: any = Object.values(s.engineDB ?? {}).find((e: any) => e.hostname === os.hostname())
if (!eng) { out({ error: 'local engine not in store' }); process.exit(3) }
const inst = (i: any) => ({ id: i.id, name: i.name, instanceOf: i.instanceOf, status: i.status, diskId: i.storedOn, port: i.port ?? null, lastStarted: i.lastStarted ?? null })
if (mode === 'state') {
  const caps: string[] = eng.capabilities ?? []
  const disks = Object.values<any>(s.diskDB ?? {}).filter(d => d.dockedTo === eng.id)
  const ids = new Set(disks.map(d => d.id))
  out({ engineId: eng.id, hostname: eng.hostname, lastBooted: eng.lastBooted ?? null,
    moveAppCrossEngine: caps.includes('moveAppCrossEngine') && eng.capabilitiesBootedAt === eng.lastBooted,
    disks: disks.map(d => ({ id: d.id, name: d.name ?? null, device: d.device ?? null })),
    instances: Object.values<any>(s.instanceDB ?? {}).filter(i => ids.has(i.storedOn)).map(inst) })
} else if (mode === 'find' && CMD) {
  for (const i of Object.values<any>(s.instanceDB ?? {})) if (i.name === CMD) {
    const d = s.diskDB?.[i.storedOn]; out({ ...inst(i), dockedTo: d?.dockedTo ?? null })
  }
} else if (mode === 'op' && CMD) {
  const ops = Object.values<any>(s.operationDB ?? {}).filter(o => o.kind === 'moveApp' && String(o.subject) === CMD)
    .sort((a, b) => (b.createdAt ?? b.startedAt ?? 0) - (a.createdAt ?? a.startedAt ?? 0))
  out(ops[0] ? { id: ops[0].id, status: ops[0].status, stepLabel: ops[0].stepLabel ?? null, error: ops[0].error ?? null, move: ops[0].move ?? null } : { error: 'no moveApp op' })
} else if (mode === 'cmd' && CMD) {
  const lh = await repo.find<any>(lu.replace('automerge:', '') as DocumentId); await lh.whenReady()
  const t0 = Date.now(); h.change((d: any) => { d.engineDB[eng.id].commands.push(CMD) })
  for (let k = 0; k < LIMIT; k++) {
    await new Promise(r => setTimeout(r, 1000))
    const t: any = Object.values(lh.doc()?.traces ?? {}).find((t: any) => t.startedAt >= t0 - 2000 && CMD.startsWith(t.command) && t.completedAt && t.status !== 'running')
    if (t) { out({ trace: t.command, status: t.status, errorCode: t.errorCode ?? null, errorMessage: t.errorMessage ?? null, result: t.result ?? null }); clearTimeout(to); process.exit(t.status === 'error' ? 4 : 0) }
  }
  out({ error: 'no trace within MOVE_TIMEOUT' }); process.exit(4)
} else { out({ error: 'usage: state | find <name> | op <id> | cmd <command...>' }); process.exit(2) }
clearTimeout(to); process.exit(0)
