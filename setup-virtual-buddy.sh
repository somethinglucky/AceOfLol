#!/usr/bin/env bash
set -e
mkdir -p virtual-buddy && cd virtual-buddy
mkdir -p "."
cat > "./.gitignore" <<'VB_EOF'
node_modules
dist
VB_EOF
mkdir -p "."
cat > "./README.md" <<'VB_EOF'
# Virtual Buddy (v0.1, M1)
Dev: `npm install && npm run dev`. Deploy: see deploy/. HTTPS is required in production (PWA, mic, push).
Milestones: M1 shell/storage/bundle (this) -> M2 buddy+chat -> M3 memory -> M4 local model+demo -> M5 voice -> M6 calls/splash -> M7 accounts/push -> M8 premium.
VB_EOF
mkdir -p "./deploy"
cat > "./deploy/deploy.sh" <<'VB_EOF'
#!/usr/bin/env bash
# Run on the droplet from the repo root: ./deploy/deploy.sh
set -e
git pull
npm install
npm run build
sudo mkdir -p /var/www/virtual-buddy
sudo rsync -a --delete dist/ /var/www/virtual-buddy/
echo "Deployed."
VB_EOF
mkdir -p "./deploy"
cat > "./deploy/nginx.conf" <<'VB_EOF'
server {
  listen 80;
  server_name vbuds.app www.vbuds.app;
  root /var/www/virtual-buddy;
  index index.html;
  location / { try_files $uri /index.html; }
  location = /sw.js { add_header Cache-Control "no-cache"; }
}
# After DNS points here, run: sudo certbot --nginx -d vbuds.app -d www.vbuds.app
# (certbot will add the HTTPS settings to this file automatically)
VB_EOF
mkdir -p "."
cat > "./index.html" <<'VB_EOF'
<!doctype html>
<html lang="en" data-theme="ios">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <meta name="theme-color" content="#0b0b0f" />
    <link rel="manifest" href="/manifest.json" />
    <link rel="icon" href="/icon.svg" />
    <title>Virtual Buddy</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.jsx"></script>
  </body>
</html>
VB_EOF
mkdir -p "."
cat > "./package.json" <<'VB_EOF'
{
  "name": "virtual-buddy",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": { "dev": "vite --host", "build": "vite build", "preview": "vite preview --host" },
  "dependencies": { "idb": "^8.0.0", "jszip": "^3.10.1", "react": "^18.3.1", "react-dom": "^18.3.1", "react-router-dom": "^6.26.0" },
  "devDependencies": { "@vitejs/plugin-react": "^4.3.1", "vite": "^5.4.0" }
}
VB_EOF
mkdir -p "./public"
cat > "./public/icon.svg" <<'VB_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="112" fill="#4f7cff"/><circle cx="256" cy="210" r="86" fill="#fff"/><path d="M110 430c14-82 72-122 146-122s132 40 146 122z" fill="#fff"/></svg>
VB_EOF
mkdir -p "./public"
cat > "./public/manifest.json" <<'VB_EOF'
{
  "name": "Virtual Buddy",
  "short_name": "Buddy",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#0b0b0f",
  "theme_color": "#0b0b0f",
  "icons": [{ "src": "/icon.svg", "sizes": "any", "type": "image/svg+xml", "purpose": "any" }]
}
VB_EOF
mkdir -p "./public"
cat > "./public/sw.js" <<'VB_EOF'
// Minimal app-shell cache. Push handling is added in M7.
const CACHE = 'vb-shell-v1'
self.addEventListener('install', (e) => { self.skipWaiting(); e.waitUntil(caches.open(CACHE).then((c) => c.add('/'))) })
self.addEventListener('activate', (e) => e.waitUntil(self.clients.claim()))
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== location.origin) return
  e.respondWith(
    fetch(e.request).then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r })
      .catch(() => caches.match(e.request).then((m) => m || caches.match('/')))
  )
})
VB_EOF
mkdir -p "./src"
cat > "./src/App.jsx" <<'VB_EOF'
import { Routes, Route, useLocation } from 'react-router-dom'
import MenuBar from './components/MenuBar.jsx'
import Landing from './screens/Landing.jsx'
import Settings from './screens/Settings.jsx'
import * as P from './screens/Placeholders.jsx'

// path -> [title, component]. Screen numbers refer to the flow in the spec.
const ROUTES = {
  '/signin': ['Sign in', P.SignIn], '/demo': ['Demo', P.Demo], '/buddy/edit': ['Buddy', P.BuddyEditor],
  '/call/incoming': ['Incoming call', P.IncomingCall], '/call/outgoing': ['Calling', P.OutgoingCall],
  '/chat': ['Messages', P.Chat], '/settings': ['Settings', Settings], '/premium': ['Premium', P.Premium],
  '/profile': ['Your profile', P.UserProfile], '/about': ['About', P.About], '/help': ['Help', P.Help],
  '/memories': ['Memories', P.EditMemories],
}
const NO_MENU = ['/', '/home']

export default function App() {
  const { pathname } = useLocation()
  const [title] = ROUTES[pathname] || ['']
  return (
    <>
      {!NO_MENU.includes(pathname) && <MenuBar title={title} />}
      <Routes>
        <Route path="/" element={<Landing />} />
        <Route path="/home" element={<P.Splash />} />
        {Object.entries(ROUTES).map(([path, [, C]]) => <Route key={path} path={path} element={<C />} />)}
      </Routes>
    </>
  )
}
VB_EOF
mkdir -p "./src/components"
cat > "./src/components/MenuBar.jsx" <<'VB_EOF'
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'

const ITEMS = [['Settings', '/settings'], ['Make call', '/call/outgoing'], ['Receive call', '/call/incoming'], ['Messaging', '/chat'], ['About', '/about'], ['Help', '/help']]

export default function MenuBar({ title }) {
  const nav = useNavigate()
  const [open, setOpen] = useState(false)
  return (
    <header className="menubar">
      <button aria-label="Back" onClick={() => nav(-1)}>‹</button>
      <h1>{title}</h1>
      <button aria-label="Menu" onClick={() => setOpen(!open)}>☰</button>
      {open && (
        <nav className="menu" onClick={() => setOpen(false)}>
          {ITEMS.map(([label, to]) => <Link key={to} to={to}>{label}</Link>)}
        </nav>
      )}
    </header>
  )
}
VB_EOF
mkdir -p "./src"
cat > "./src/main.jsx" <<'VB_EOF'
import React from 'react'
import { createRoot } from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.jsx'
import { initTheme } from './state/theme.js'
import './styles.css'

initTheme()
if ('storage' in navigator && navigator.storage.persist) navigator.storage.persist().catch(() => {})
if ('serviceWorker' in navigator) window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').catch(() => {}))

createRoot(document.getElementById('root')).render(<BrowserRouter><App /></BrowserRouter>)
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Landing.jsx" <<'VB_EOF'
import { Link } from 'react-router-dom'
export default function Landing() {
  return (
    <div className="screen center">
      <h1>Virtual Buddy</h1>
      <p className="muted">An AI companion who can be whoever you need. Your conversations can stay on your device.</p>
      <div className="stack">
        <Link className="btn" to="/signin">Sign in / Sign up</Link>
        <Link className="btn" to="/demo">Try Demo Buddy</Link>
        <Link className="btn" to="/buddy/edit">Create new buddy</Link>
      </div>
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Placeholders.jsx" <<'VB_EOF'
// Screens built in later milestones. Replace each export with a real file as it is built.
const P = (name, milestone) => () => (
  <div className="screen center"><h2>{name}</h2><p className="muted">Coming in {milestone}.</p></div>
)
export const SignIn = P('Sign in / Sign up', 'M7')
export const Demo = P('Try Demo Buddy', 'M4')
export const BuddyEditor = P('Create / Edit Buddy', 'M2')
export const IncomingCall = P('Incoming call', 'M6')
export const OutgoingCall = P('Calling...', 'M6')
export const Chat = P('Messages', 'M2')
export const Splash = P('Home', 'M6')
export const Premium = P('Premium', 'M8')
export const UserProfile = P('Your profile', 'M2')
export const About = P('About', 'M2')
export const Help = P('Help', 'M2')
export const EditMemories = P('Edit memories', 'M3')
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Settings.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { getSettings } from '../storage/db.js'
import { exportBundle, importBundle, downloadBlob } from '../storage/bundle.js'
import { THEMES, setTheme } from '../state/theme.js'

export default function Settings() {
  const [s, setS] = useState(null)
  const [msg, setMsg] = useState('')
  const file = useRef()
  const refresh = () => getSettings().then(setS)
  useEffect(() => { refresh() }, [])
  if (!s) return null

  async function doExport() { downloadBlob(await exportBundle(), `virtualbuddy-${new Date().toISOString().slice(0, 10)}.vbbundle`); setMsg('Backup downloaded.'); refresh() }
  async function doImport(e, mode) {
    const f = e.target.files[0]; if (!f) return
    if (mode === 'replace' && !confirm('Replace everything on this device with the backup?')) return
    try { await importBundle(f, mode); setMsg('Backup imported.') } catch (err) { setMsg(err.message) }
    refresh()
  }

  return (
    <div className="screen">
      <section className="card">
        <h2>Theme</h2>
        <div className="row">{THEMES.map((t) => (
          <button key={t.id} className={s.theme === t.id ? 'on' : ''} onClick={async () => { await setTheme(t.id); refresh() }}>{t.label}</button>
        ))}</div>
      </section>
      <section className="card">
        <h2>Backup</h2>
        <p className="muted">Last backup: {s.lastBackupAt ? new Date(s.lastBackupAt).toLocaleString() : 'never'}</p>
        <div className="row">
          <button onClick={doExport}>Export backup</button>
          <button onClick={() => { file.current.dataset.mode = 'merge'; file.current.click() }}>Import (merge)</button>
          <button onClick={() => { file.current.dataset.mode = 'replace'; file.current.click() }}>Import (replace)</button>
        </div>
        <input ref={file} type="file" accept=".vbbundle,.zip" hidden onChange={(e) => { doImport(e, e.target.dataset.mode); e.target.value = '' }} />
        {msg && <p>{msg}</p>}
      </section>
    </div>
  )
}
VB_EOF
mkdir -p "./src/state"
cat > "./src/state/theme.js" <<'VB_EOF'
import { getSettings, putSettings } from '../storage/db.js'
// 'custom' is the placeholder for the third theme (to be decided).
export const THEMES = [{ id: 'ios', label: 'iOS' }, { id: 'android', label: 'Android' }, { id: 'custom', label: 'Third theme (TBD)' }]
export function applyTheme(id) { document.documentElement.dataset.theme = id }
export async function initTheme() { applyTheme((await getSettings()).theme) }
export async function setTheme(id) { applyTheme(id); await putSettings({ theme: id }) }
VB_EOF
mkdir -p "./src/storage"
cat > "./src/storage/bundle.js" <<'VB_EOF'
import JSZip from 'jszip'
import { STORES, getAll, put, clearStore, putSettings } from './db.js'

export const BUNDLE_VERSION = 1

// Blobs (avatars, splash image) and embeddings are not JSON; handled in a later milestone (media/ folder).
function clean(store, rows) {
  return rows.map((r) => {
    const o = {}
    for (const [k, v] of Object.entries(r)) {
      if (v instanceof Blob || k === 'embedding') continue
      o[k] = v
    }
    if (store === 'settings') o.apiKeys = {} // keys never leave the device unless the user opts in (later)
    return o
  })
}

export async function exportBundle() {
  const zip = new JSZip()
  zip.file('manifest.json', JSON.stringify({ version: BUNDLE_VERSION, createdAt: new Date().toISOString(), appVersion: '0.1.0' }, null, 2))
  for (const s of STORES) zip.file(`${s}.json`, JSON.stringify(clean(s, await getAll(s))))
  const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' })
  await putSettings({ lastBackupAt: new Date().toISOString() })
  return blob
}

export function downloadBlob(blob, name) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob); a.download = name; a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 5000)
}

// mode: 'merge' (keep existing, overwrite same ids) | 'replace' (wipe first)
export async function importBundle(file, mode = 'merge') {
  const zip = await JSZip.loadAsync(file)
  const manifest = JSON.parse(await zip.file('manifest.json').async('string'))
  if (manifest.version > BUNDLE_VERSION) throw new Error('This backup was made by a newer version of the app.')
  for (const s of STORES) {
    const f = zip.file(`${s}.json`); if (!f) continue
    const rows = JSON.parse(await f.async('string'))
    if (mode === 'replace') await clearStore(s)
    for (const r of rows) await put(s, r)
  }
}
VB_EOF
mkdir -p "./src/storage"
cat > "./src/storage/db.js" <<'VB_EOF'
import { openDB } from 'idb'

export const STORES = ['buddy', 'userProfile', 'message', 'memory', 'schedule', 'settings']
const DEFAULT_SETTINGS = {
  id: 'main', theme: 'ios', splashFit: 'cover', buttonLayout: [], activeProvider: 'local',
  apiKeys: {}, localModelRef: null, exitMessage: "You seem to be having a bad day. Let's talk later when you're feeling more like yourself.",
  onboarded: false, lastBackupAt: null,
}

let dbp
export function db() {
  dbp ||= openDB('virtual-buddy', 1, {
    upgrade(d) {
      d.createObjectStore('buddy', { keyPath: 'id' })
      d.createObjectStore('userProfile', { keyPath: 'id' })
      const msg = d.createObjectStore('message', { keyPath: 'id' }); msg.createIndex('byBuddy', 'buddyId')
      const mem = d.createObjectStore('memory', { keyPath: 'id' }); mem.createIndex('byBuddy', 'buddyId')
      const sch = d.createObjectStore('schedule', { keyPath: 'id' }); sch.createIndex('byBuddy', 'buddyId')
      d.createObjectStore('settings', { keyPath: 'id' })
    },
  })
  return dbp
}

export async function getSettings() { return { ...DEFAULT_SETTINGS, ...((await (await db()).get('settings', 'main')) || {}) } }
export async function putSettings(patch) { const next = { ...(await getSettings()), ...patch }; await (await db()).put('settings', next); return next }
export async function getAll(store) { return (await db()).getAll(store) }
export async function put(store, value) { return (await db()).put(store, value) }
export async function clearStore(store) { return (await db()).clear(store) }
VB_EOF
mkdir -p "./src"
cat > "./src/styles.css" <<'VB_EOF'
:root { box-sizing: border-box; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }
*, *::before, *::after { box-sizing: inherit; }
html[data-theme="ios"]     { --bg:#0b0b0f; --card:#1c1c22; --text:#f5f5f7; --muted:#9a9aa5; --accent:#4f7cff; --radius:16px; --font:-apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }
html[data-theme="android"] { --bg:#121212; --card:#232323; --text:#eaeaea; --muted:#a0a0a0; --accent:#6fd09a; --radius:10px; --font:Roboto,system-ui,sans-serif; }
html[data-theme="custom"]  { --bg:#14101f; --card:#221b36; --text:#f1ecff; --muted:#a79fc4; --accent:#b388ff; --radius:22px; --font:system-ui,sans-serif; } /* placeholder palette */
html, body, #root { height: 100%; margin: 0; }
body { background: var(--bg); color: var(--text); font-family: var(--font); }
.menubar { position: sticky; top: env(safe-area-inset-top, 0px); display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background: var(--bg); border-bottom: 1px solid var(--card); z-index: 10; }
.menubar h1 { font-size: 1.05rem; margin: 0; }
.menubar button { background: none; border: 0; color: var(--text); font-size: 1.6rem; padding: 4px 10px; }
.menu { position: absolute; top: 100%; right: 8px; background: var(--card); border-radius: var(--radius); padding: 6px; display: flex; flex-direction: column; min-width: 180px; box-shadow: 0 8px 24px #0008; }
.menu a { color: var(--text); text-decoration: none; padding: 12px 14px; }
.screen { padding: 16px; max-width: 560px; margin: 0 auto; }
.center { text-align: center; padding-top: 12vh; }
.stack { display: flex; flex-direction: column; gap: 12px; margin-top: 24px; }
.card { background: var(--card); border-radius: var(--radius); padding: 16px; margin-bottom: 16px; }
.card h2 { margin-top: 0; font-size: 1rem; }
.row { display: flex; flex-wrap: wrap; gap: 8px; }
.muted { color: var(--muted); }
button, .btn { font: inherit; color: var(--text); background: var(--card); border: 1px solid var(--muted); border-radius: var(--radius); padding: 12px 16px; text-decoration: none; cursor: pointer; }
.card button, .on { border-color: var(--accent); }
.btn { background: var(--accent); border-color: var(--accent); color: #fff; display: block; }
button.on { background: var(--accent); color: #fff; }
VB_EOF
mkdir -p "."
cat > "./vite.config.js" <<'VB_EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({ plugins: [react()] })
VB_EOF
chmod +x deploy/deploy.sh
echo "Created virtual-buddy/. Next: cd virtual-buddy && npm install && npm run dev"
