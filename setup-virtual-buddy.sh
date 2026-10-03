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
# Virtual Buddy (v0.2.0, M2)
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
<html lang="en" data-theme="ice">
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
import BuddyEditor from './screens/BuddyEditor.jsx'
import UserProfile from './screens/UserProfile.jsx'
import Chat from './screens/Chat.jsx'
import About from './screens/About.jsx'
import Help from './screens/Help.jsx'
import * as P from './screens/Placeholders.jsx'

// path -> [title, component]. Screen numbers refer to the flow in the spec.
const ROUTES = {
  '/signin': ['Sign in', P.SignIn], '/demo': ['Demo', P.Demo], '/buddy/edit': ['Buddy', BuddyEditor],
  '/call/incoming': ['Incoming call', P.IncomingCall], '/call/outgoing': ['Calling', P.OutgoingCall],
  '/chat': ['Messages', Chat], '/settings': ['Settings', Settings], '/premium': ['Premium', P.Premium],
  '/profile': ['Your profile', UserProfile], '/about': ['About', About], '/help': ['Help', Help],
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
mkdir -p "./src/ai"
cat > "./src/ai/promptBuilder.js" <<'VB_EOF'
import { SAFETY_BLOCK } from './safety.js'

const line = (label, v) => (v && String(v).trim() ? `${label}: ${String(v).trim()}\n` : '')

export function buildSystem({ buddy, profile, memories = [] }) {
  let s = `You are ${buddy.name || 'a friendly companion'}, a companion character in a chat/phone app. Stay in character and write the way a real person texts or talks: natural, warm, usually brief.\n\n`
  s += '## Who you are\n'
  s += line('Description', buddy.personality)
  s += line('Your role in the user\'s life', buddy.role)
  s += line('Family you know about', buddy.family)
  s += line('How you talk / common phrases', buddy.style)
  s += `Gender: ${buddy.gender === 'm' ? 'male' : 'female'}\n`
  if (profile) {
    s += '\n## About the user (use naturally, never recite)\n'
    s += line('Name', profile.name)
    s += line('Nicknames they like', profile.nicknames)
    s += line('Pronouns', profile.pronouns)
    s += line('Family', profile.family)
    s += line('Pets and friends', profile.pets)
    s += line('Topics they enjoy', profile.topics)
    s += line('More about them', profile.about)
  }
  if (memories.length) s += '\n## Things you remember\n' + memories.map((m) => `- ${m.text}`).join('\n') + '\n'
  s += '\n' + SAFETY_BLOCK
  return s
}

// Newest-first trim to a rough character budget, then restore order. Roles: 'user' | 'assistant'.
export function buildContext(messages, maxChars = 12000) {
  const out = []
  let used = 0
  for (let i = messages.length - 1; i >= 0; i--) {
    const m = messages[i]
    used += m.text.length
    if (used > maxChars && out.length) break
    out.unshift({ role: m.role === 'user' ? 'user' : 'assistant', content: m.text })
  }
  return out
}
VB_EOF
mkdir -p "./src/ai"
cat > "./src/ai/provider.js" <<'VB_EOF'
export const PROVIDERS = {
  openai: { label: 'OpenAI', keyHint: 'sk-...' },
  anthropic: { label: 'Anthropic', keyHint: 'sk-ant-...' },
  gemini: { label: 'Google Gemini', keyHint: 'AI...' },
  openrouter: { label: 'OpenRouter', keyHint: 'sk-or-...' },
}

// Providers need alternating roles starting with "user"; merge repeats and drop a leading assistant turn.
export function normalize(messages) {
  const out = []
  for (const m of messages) {
    if (out.length && out[out.length - 1].role === m.role) out[out.length - 1].content += '\n' + m.content
    else out.push({ ...m })
  }
  while (out.length && out[0].role !== 'user') out.shift()
  return out
}

// Yields the data payloads of an SSE response.
export async function* sseData(res) {
  const reader = res.body.getReader()
  const dec = new TextDecoder()
  let buf = ''
  for (;;) {
    const { done, value } = await reader.read()
    if (done) break
    buf += dec.decode(value, { stream: true })
    let i
    while ((i = buf.indexOf('\n')) >= 0) {
      const ln = buf.slice(0, i).replace(/\r$/, ''); buf = buf.slice(i + 1)
      if (ln.startsWith('data:')) { const d = ln.slice(5).trim(); if (d && d !== '[DONE]') yield d }
    }
  }
}

function friendlyError(status, body, label) {
  let detail = ''
  try { const j = JSON.parse(body); detail = j.error?.message || j.message || '' } catch { detail = body.slice(0, 200) }
  if (status === 401 || status === 403) return `${label} rejected the API key (${status}). Check the key in Settings.`
  if (status === 404) return `${label} could not find that model. Check the model name in Settings.${detail ? ' (' + detail + ')' : ''}`
  if (status === 429) return `${label} says you're out of quota or sending too fast (429). ${detail}`
  return `${label} error ${status}. ${detail}`
}

async function post(url, headers, body, signal, label) {
  let res
  try { res = await fetch(url, { method: 'POST', headers: { 'content-type': 'application/json', ...headers }, body: JSON.stringify(body), signal }) }
  catch (e) { if (e.name === 'AbortError') throw e; throw new Error(`Couldn't reach ${label}. Check your connection.`) }
  if (!res.ok) throw new Error(friendlyError(res.status, await res.text(), label))
  return res
}

export async function* streamChat({ provider, apiKey, model, system, messages, signal }) {
  const label = PROVIDERS[provider]?.label || provider
  if (!apiKey) throw new Error(`Add your ${label} API key in Settings first.`)
  const msgs = normalize(messages)

  if (provider === 'openai' || provider === 'openrouter') {
    const url = provider === 'openai' ? 'https://api.openai.com/v1/chat/completions' : 'https://openrouter.ai/api/v1/chat/completions'
    const res = await post(url, { authorization: `Bearer ${apiKey}` }, { model, stream: true, messages: [{ role: 'system', content: system }, ...msgs] }, signal, label)
    for await (const d of sseData(res)) { const t = JSON.parse(d).choices?.[0]?.delta?.content; if (t) yield t }
  } else if (provider === 'anthropic') {
    const res = await post('https://api.anthropic.com/v1/messages',
      { 'x-api-key': apiKey, 'anthropic-version': '2023-06-01', 'anthropic-dangerous-direct-browser-access': 'true' },
      { model, max_tokens: 1024, stream: true, system, messages: msgs }, signal, label)
    for await (const d of sseData(res)) { const j = JSON.parse(d); if (j.type === 'content_block_delta' && j.delta?.text) yield j.delta.text }
  } else if (provider === 'gemini') {
    const res = await post(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`,
      { 'x-goog-api-key': apiKey },
      { systemInstruction: { parts: [{ text: system }] }, contents: msgs.map((m) => ({ role: m.role === 'user' ? 'user' : 'model', parts: [{ text: m.content }] })) }, signal, label)
    for await (const d of sseData(res)) for (const p of JSON.parse(d).candidates?.[0]?.content?.parts || []) if (p.text) yield p.text
  } else {
    throw new Error('Local models arrive in a later update. Pick a cloud provider in Settings for now.')
  }
}
VB_EOF
mkdir -p "./src/ai"
cat > "./src/ai/safety.js" <<'VB_EOF'
// Safety layer v0. Everything here is model-independent and meant to be refined by the app owner.
export const EXIT_TOKEN = '[[EXIT]]'

// Appended to every prompt, whatever model is used.
export const SAFETY_BLOCK = `Ground rules that always apply:
- You are an AI companion. Stay in the role the user chose, but if they sincerely ask whether you are an AI or a real person, tell the truth.
- If the user seems to be in distress, hopeless, or mentions hurting themselves, stay warm and present, take it seriously, and gently encourage reaching out to local emergency services or a crisis line (for example 988 in the US). Never end the conversation in these moments.
- Support the user's real-world relationships, health and goals. Never encourage isolation or discourage them from seeking real help.
- Do not give medical, legal or financial instructions as if you were a professional.
- Only if the user is being abusive or hostile TOWARD YOU repeatedly, and you no longer wish to continue, reply with exactly ${EXIT_TOKEN} and nothing else. Being sad, angry about life, or in crisis is NOT abuse; never use ${EXIT_TOKEN} for those.`

// Hook for checks that must not depend on the model (keyword/crisis handling etc.).
// Return { block: true, reply: '...' } to answer locally instead of calling a model, or null to continue.
export function preSendCheck(/* text */) { return null }
VB_EOF
mkdir -p "./src/components"
cat > "./src/components/Avatar.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
export default function Avatar({ blob, name = '?', size = 40 }) {
  const [url, setUrl] = useState(null)
  useEffect(() => {
    if (!blob) { setUrl(null); return }
    const u = URL.createObjectURL(blob); setUrl(u)
    return () => URL.revokeObjectURL(u)
  }, [blob])
  const style = { width: size, height: size, fontSize: size * 0.45 }
  return url
    ? <img className="avatar" style={style} src={url} alt="" />
    : <div className="avatar ph" style={style}>{(name.trim()[0] || '?').toUpperCase()}</div>
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
mkdir -p "./src/components"
cat > "./src/components/SelectBuddy.jsx" <<'VB_EOF'
import Avatar from './Avatar.jsx'
// Popup for choosing which buddy a screen applies to. "Create New Buddy" comes first when allowed.
export default function SelectBuddy({ buddies, canCreate, onPick, onCreate, onClose }) {
  return (
    <div className="modal-back" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Choose a buddy</h2>
        {canCreate && <button className="pick" onClick={onCreate}><span className="avatar ph" style={{ width: 40, height: 40 }}>+</span>Create new buddy</button>}
        {buddies.map((b) => (
          <button key={b.id} className="pick" onClick={() => onPick(b)}><Avatar blob={b.avatar} name={b.name} />{b.name}</button>
        ))}
        {onClose && <button className="plain" onClick={onClose}>Cancel</button>}
      </div>
    </div>
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
cat > "./src/screens/About.jsx" <<'VB_EOF'
export default function About() {
  return (
    <div className="screen prose">
      <h2>About Virtual Buddy</h2>
      <p>Virtual Buddy is an AI companion that can be whoever you need: a friend, a mentor, an accountability partner, a practice partner for a hard conversation, or a familiar voice when no one else is around. You decide who your buddy is, how they talk, what they remember, and when they reach out.</p>
      <p>Talk by text or by voice, like a phone call. Practice interviews, small talk, or ordering food. Set up daily check-ins, reminders, or a call to help you out of a tricky situation. Your buddy remembers the things that matter to you, and you can view and edit those memories any time.</p>
      <p>Your privacy comes first. Virtual Buddy can run AI models directly on your device, so your conversations never have to leave it. If you want more advanced conversation, you can optionally connect a cloud AI of your choice.</p>
      <p className="muted">Virtual Buddy is an AI, not a person, and is not a substitute for professional or emergency help. If you're in crisis, please contact local emergency services or a crisis line.</p>
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/BuddyEditor.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { get, put, getBuddies, getProfile, getSettings, putSettings, deleteBuddy, getMessages, newId } from '../storage/db.js'
import { toAvatarBlob } from '../storage/image.js'
import Avatar from '../components/Avatar.jsx'

const EMPTY = { name: '', gender: 'f', personality: '', family: '', role: '', style: '', avatar: null }

export default function BuddyEditor() {
  const nav = useNavigate()
  const [params] = useSearchParams()
  const id = params.get('id')
  const [b, setB] = useState(EMPTY)
  const [hasChat, setHasChat] = useState(false)
  const [blocked, setBlocked] = useState(false)
  const [ready, setReady] = useState(false)
  const file = useRef()

  useEffect(() => { (async () => {
    if (id) {
      const found = await get('buddy', id)
      if (found) { setB(found); setHasChat((await getMessages(id)).length > 0) }
    } else {
      const [all, s] = await Promise.all([getBuddies(), getSettings()])
      if (all.length >= 1 && !s.premium) setBlocked(true)
    }
    setReady(true)
  })() }, [id])

  const set = (k) => (e) => setB({ ...b, [k]: e.target.value })

  async function save() {
    if (!b.name.trim()) { alert('Please give your buddy a name.'); return }
    const buddy = { ...b, name: b.name.trim(), id: b.id || newId(), createdAt: b.createdAt || Date.now(), status: b.status || 'awake' }
    await put('buddy', buddy)
    await putSettings({ activeBuddyId: buddy.id })
    // First-time setup continues to the user profile (screen 11); edits go back to settings.
    nav((await getProfile()) ? '/settings' : '/profile', { replace: true })
  }
  async function remove() {
    if (!confirm(`Delete ${b.name} and all of their messages and memories? This can't be undone.`)) return
    await deleteBuddy(b.id); nav('/settings', { replace: true })
  }
  async function pickPhoto(e) {
    const f = e.target.files[0]; if (!f) return
    try { setB({ ...b, avatar: await toAvatarBlob(f) }) } catch { alert("Couldn't read that image.") }
    e.target.value = ''
  }

  if (!ready) return null
  if (blocked) return (
    <div className="screen center">
      <h2>One buddy on the free plan</h2>
      <p className="muted">Premium lets you create more buddies, each with their own personality and memories.</p>
      <div className="stack"><Link className="btn" to="/premium">See premium</Link><Link className="plain" to="/chat">Back to my buddy</Link></div>
    </div>
  )

  return (
    <div className="screen">
      <div className="avatar-pick">
        <Avatar blob={b.avatar} name={b.name || '?'} size={96} />
        <button onClick={() => file.current.click()}>{b.avatar ? 'Change photo' : 'Add photo'}</button>
        <input ref={file} type="file" accept="image/*" hidden onChange={pickPhoto} />
        <p className="muted small">Photos stay on this device.</p>
      </div>
      <label>Name<input value={b.name} onChange={set('name')} placeholder="What do you call your buddy?" /></label>
      <label>Voice
        <select value={b.gender} onChange={set('gender')}><option value="f">Female</option><option value="m">Male</option></select>
      </label>
      <label>Who are they?
        <textarea rows={5} value={b.personality} onChange={set('personality')} placeholder="Describe your buddy: hobbies, interests, work, goals, culture, where they were born and live now, kids, exes, religion, and so on." />
      </label>
      <label>People they know
        <textarea rows={3} value={b.family} onChange={set('family')} placeholder="e.g. You have a sister you're close to named Margret, an accountant in New York." />
      </label>
      <label>Their role in your life
        <textarea rows={2} value={b.role} onChange={set('role')} placeholder="Friend, mentor, partner, accountability buddy, practice partner for interviews..." />
      </label>
      <label>How they talk
        <textarea rows={3} value={b.style} onChange={set('style')} placeholder="Style, common phrases, how often they joke, how formal they are..." />
      </label>
      <div className="stack">
        <button className="btn" onClick={save}>Save</button>
        {hasChat && <Link className="plain" to="/memories">Edit memories</Link>}
        {b.id && <button className="danger" onClick={remove}>Delete buddy</button>}
      </div>
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Chat.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getSettings, putSettings, getProfile, getMessages, put, newId, resolveActiveBuddy } from '../storage/db.js'
import { streamChat, PROVIDERS } from '../ai/provider.js'
import { buildSystem, buildContext } from '../ai/promptBuilder.js'
import { preSendCheck, EXIT_TOKEN } from '../ai/safety.js'
import Avatar from '../components/Avatar.jsx'
import SelectBuddy from '../components/SelectBuddy.jsx'

export default function Chat() {
  const nav = useNavigate()
  const [state, setState] = useState(null) // { buddy, buddies, needsPick, settings }
  const [msgs, setMsgs] = useState([])
  const [input, setInput] = useState('')
  const [live, setLive] = useState(null)   // text of the reply being streamed (null = none)
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState('')
  const [picking, setPicking] = useState(false)
  const abort = useRef(null)
  const end = useRef(null)

  async function load() {
    const r = await resolveActiveBuddy()
    const settings = await getSettings()
    setState({ ...r, settings })
    if (r.buddy) setMsgs(await getMessages(r.buddy.id))
    else if (!r.buddies.length) nav('/buddy/edit', { replace: true })
  }
  useEffect(() => { load(); return () => abort.current?.abort() }, [])
  useEffect(() => { end.current?.scrollIntoView({ block: 'end' }) }, [msgs, live, note])

  if (!state) return null
  const { buddy, buddies, settings } = state
  if (!buddy) return state.needsPick
    ? <SelectBuddy buddies={buddies} onPick={async (b) => { await putSettings({ activeBuddyId: b.id }); load() }} />
    : null

  async function send() {
    const text = input.trim()
    if (!text || busy) return
    setNote(''); setInput('')
    const userMsg = { id: newId(), buddyId: buddy.id, role: 'user', text, ts: Date.now(), source: 'text' }
    await put('message', userMsg)
    const history = [...msgs, userMsg]
    setMsgs(history)

    const pre = preSendCheck(text)
    if (pre?.block) {
      const m = { id: newId(), buddyId: buddy.id, role: 'buddy', text: pre.reply, ts: Date.now(), modelUsed: 'local-rule', source: 'text' }
      await put('message', m); setMsgs([...history, m]); return
    }

    const s = await getSettings()
    const provider = s.activeProvider
    const cfg = s.providers[provider] || {}
    setBusy(true); setLive('')
    abort.current = new AbortController()
    let acc = ''
    try {
      const profile = await getProfile()
      const system = buildSystem({ buddy, profile, memories: [] })
      const ctx = buildContext(history.map((m) => ({ role: m.role === 'user' ? 'user' : 'assistant', text: m.text })))
      for await (const chunk of streamChat({ provider, apiKey: cfg.apiKey, model: cfg.model, system, messages: ctx, signal: abort.current.signal })) {
        acc += chunk; setLive(acc)
      }
    } catch (e) {
      if (e.name !== 'AbortError') setNote(e.message)
    }
    let final = acc.trim()
    if (final.startsWith(EXIT_TOKEN)) final = s.exitMessage
    if (final) {
      const m = { id: newId(), buddyId: buddy.id, role: 'buddy', text: final, ts: Date.now(), modelUsed: `${provider}:${cfg.model}`, source: 'text' }
      await put('message', m); setMsgs([...history, m])
    }
    setLive(null); setBusy(false)
  }

  // While the streamed text could still turn into the exit token, keep showing the typing dots.
  const hideLive = live !== null && (live.trim() === '' || EXIT_TOKEN.startsWith(live.trim()) || live.trim().startsWith(EXIT_TOKEN))
  const label = PROVIDERS[settings.activeProvider]?.label

  return (
    <div className="chat">
      <div className="chat-head">
        <Avatar blob={buddy.avatar} name={buddy.name} size={36} />
        <div><strong>{buddy.name}</strong><div className="small muted">{label ? `via ${label}` : 'offline'}</div></div>
        {buddies.length > 1 && <button className="plain" onClick={() => setPicking(true)}>Switch</button>}
      </div>
      <div className="chat-list">
        {msgs.length === 0 && live === null && <p className="muted center-text">Say hi to {buddy.name}.</p>}
        {msgs.map((m) => <div key={m.id} className={`bubble ${m.role === 'user' ? 'me' : 'them'}`}>{m.text}</div>)}
        {live !== null && (hideLive
          ? <div className="bubble them typing"><i /><i /><i /></div>
          : <div className="bubble them">{live}</div>)}
        {note && <div className="note">{note}</div>}
        <div ref={end} />
      </div>
      <div className="composer">
        <textarea rows={1} value={input} placeholder="Message" onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && window.matchMedia('(pointer: fine)').matches) { e.preventDefault(); send() } }} />
        <button className="send" aria-label="Send" disabled={busy || !input.trim()} onClick={send}>↑</button>
      </div>
      {picking && <SelectBuddy buddies={buddies} onClose={() => setPicking(false)}
        onPick={async (b) => { await putSettings({ activeBuddyId: b.id }); setPicking(false); load() }} />}
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Help.jsx" <<'VB_EOF'
export default function Help() {
  return (
    <div className="screen prose">
      <h2>Getting started</h2>
      <ol>
        <li>Open <strong>Settings</strong> and create your buddy, then fill in your own profile.</li>
        <li>Choose an AI provider, paste your API key, and check the model name.</li>
        <li>Open <strong>Messages</strong> and say hi.</li>
      </ol>
      <h2>Where is my data?</h2>
      <p>Your buddies, messages and settings are stored on this device. Clearing your browser's site data erases them, so use <strong>Settings → Export backup</strong> regularly. To move to a new phone, export a backup and import it there.</p>
      <h2>API keys</h2>
      <p>Your key is stored on this device only and is never included in backups. You are billed by your AI provider, not by Virtual Buddy.</p>
      <h2>Need real help?</h2>
      <p>If you are in crisis, please contact local emergency services or a crisis line (in the US, call or text 988).</p>
      <h2>Report a bug</h2>
      <p className="muted">Coming soon.</p>
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Landing.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getBuddies, getSettings } from '../storage/db.js'
export default function Landing() {
  const [info, setInfo] = useState(null)
  useEffect(() => { Promise.all([getBuddies(), getSettings()]).then(([b, s]) => setInfo({ n: b.length, premium: s.premium })) }, [])
  if (!info) return null
  return (
    <div className="screen center">
      <h1>Virtual Buddy</h1>
      <p className="muted">An AI companion who can be whoever you need. Your conversations can stay on your device.</p>
      <div className="stack">
        {info.n > 0 && <Link className="btn" to="/chat">Open messages</Link>}
        <Link className="btn alt" to="/signin">Sign in / Sign up</Link>
        <Link className="btn alt" to="/demo">Try Demo Buddy</Link>
        {(info.n === 0 || info.premium) && <Link className="btn alt" to="/buddy/edit">Create new buddy</Link>}
        <Link className="plain" to="/settings">Settings</Link>
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
export const IncomingCall = P('Incoming call', 'M6')
export const OutgoingCall = P('Calling...', 'M6')
export const Splash = P('Home', 'M6')
export const Premium = P('Premium', 'M8')
export const EditMemories = P('Edit memories', 'M3')
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/Settings.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getSettings, putSettings, getBuddies } from '../storage/db.js'
import { exportBundle, importBundle, downloadBlob } from '../storage/bundle.js'
import { THEMES, setTheme } from '../state/theme.js'
import { PROVIDERS } from '../ai/provider.js'
import SelectBuddy from '../components/SelectBuddy.jsx'

export default function Settings() {
  const nav = useNavigate()
  const [s, setS] = useState(null)
  const [buddies, setBuddies] = useState([])
  const [msg, setMsg] = useState('')
  const [picking, setPicking] = useState(false)
  const file = useRef()
  const refresh = async () => { setS(await getSettings()); setBuddies(await getBuddies()) }
  useEffect(() => { refresh() }, [])
  if (!s) return null

  const prov = s.activeProvider
  const cfg = s.providers[prov] || { apiKey: '', model: '' }
  const setCfg = (patch) => putSettings({ providers: { ...s.providers, [prov]: { ...cfg, ...patch } } }).then(setS)
  const canCreate = s.premium || buddies.length === 0

  function editBuddy() {
    if (buddies.length === 0) return nav('/buddy/edit')
    if (buddies.length === 1 && !canCreate) return nav(`/buddy/edit?id=${buddies[0].id}`)
    setPicking(true)
  }
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
        <h2>You and your buddy</h2>
        <div className="row">
          <button onClick={editBuddy}>{buddies.length ? 'Edit buddy' : 'Create buddy'}</button>
          <Link className="plain-btn" to="/profile">Edit my profile</Link>
          {buddies.length > 0 && <Link className="plain-btn" to="/chat">Open messages</Link>}
        </div>
      </section>

      <section className="card">
        <h2>AI model</h2>
        <label>Provider
          <select value={prov} onChange={async (e) => setS(await putSettings({ activeProvider: e.target.value }))}>
            {Object.entries(PROVIDERS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </label>
        <label>API key
          <input type="password" autoComplete="off" value={cfg.apiKey} placeholder={PROVIDERS[prov]?.keyHint} onChange={(e) => setCfg({ apiKey: e.target.value })} />
        </label>
        <label>Model
          <input value={cfg.model} onChange={(e) => setCfg({ model: e.target.value })} />
        </label>
        <p className="muted small">Your key is saved only on this device and is sent only to {PROVIDERS[prov]?.label}. You pay that provider directly for usage. Local on-device models are coming in a later update.</p>
      </section>

      <section className="card">
        <h2>If a conversation turns abusive</h2>
        <p className="muted small">What your buddy says when they step away. Make it sound like them.</p>
        <textarea rows={3} value={s.exitMessage} onChange={(e) => setS({ ...s, exitMessage: e.target.value })} onBlur={() => putSettings({ exitMessage: s.exitMessage })} />
      </section>

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

      {picking && <SelectBuddy buddies={buddies} canCreate={canCreate} onClose={() => setPicking(false)}
        onCreate={() => nav('/buddy/edit')} onPick={(b) => nav(`/buddy/edit?id=${b.id}`)} />}
    </div>
  )
}
VB_EOF
mkdir -p "./src/screens"
cat > "./src/screens/UserProfile.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfile, saveProfile } from '../storage/db.js'

const EMPTY = { name: '', nicknames: '', pronouns: '', family: '', pets: '', topics: '', about: '' }

export default function UserProfile() {
  const nav = useNavigate()
  const [p, setP] = useState(EMPTY)
  useEffect(() => { getProfile().then((x) => x && setP({ ...EMPTY, ...x })) }, [])
  const set = (k) => (e) => setP({ ...p, [k]: e.target.value })
  async function save() { await saveProfile(p); nav('/settings', { replace: true }) }
  return (
    <div className="screen">
      <p className="muted">This helps your buddy avoid mix-ups. It stays on this device.</p>
      <label>Your name<input value={p.name} onChange={set('name')} /></label>
      <label>Nicknames you like<input value={p.nicknames} onChange={set('nicknames')} placeholder="Comma separated" /></label>
      <label>Pronouns / gender<input value={p.pronouns} onChange={set('pronouns')} /></label>
      <label>Family<textarea rows={3} value={p.family} onChange={set('family')} placeholder="Who should your buddy know about?" /></label>
      <label>Pets and friends<textarea rows={3} value={p.pets} onChange={set('pets')} /></label>
      <label>Topics you like to talk about<textarea rows={2} value={p.topics} onChange={set('topics')} /></label>
      <label>Anything else<textarea rows={4} value={p.about} onChange={set('about')} placeholder="Work, hobbies, goals, things that worry you, things to avoid..." /></label>
      <div className="stack"><button className="btn" onClick={save}>Save</button></div>
    </div>
  )
}
VB_EOF
mkdir -p "./src/state"
cat > "./src/state/theme.js" <<'VB_EOF'
import { getSettings, putSettings } from '../storage/db.js'
export const THEMES = [
  { id: 'light', label: 'Light' },
  { id: 'ice', label: 'Dark Ice' },
  { id: 'mint', label: 'Dark Mint' },
  { id: 'lilac', label: 'Dark Lilac' },
]
const LEGACY = { ios: 'ice', android: 'mint', custom: 'lilac' } // ids used before v0.1.1
export const normalizeTheme = (id) => LEGACY[id] || (THEMES.some((t) => t.id === id) ? id : 'ice')
const BAR = { light: '#ffffff', ice: '#0b0b0f', mint: '#121212', lilac: '#14101f' }
export function applyTheme(id) {
  id = normalizeTheme(id)
  document.documentElement.dataset.theme = id
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', BAR[id])
}
export async function initTheme() {
  const s = await getSettings()
  const id = normalizeTheme(s.theme)
  if (id !== s.theme) await putSettings({ theme: id })
  applyTheme(id)
}
export async function setTheme(id) { applyTheme(id); await putSettings({ theme: normalizeTheme(id) }) }
VB_EOF
mkdir -p "./src/storage"
cat > "./src/storage/bundle.js" <<'VB_EOF'
import JSZip from 'jszip'
import { STORES, getAll, put, clearStore, putSettings } from './db.js'

export const BUNDLE_VERSION = 1

// Rows -> JSON-safe rows. Image blobs go to media/ in the zip; embeddings are regenerated on import.
function clean(zip, store, rows) {
  return rows.map((r) => {
    const o = {}
    for (const [k, v] of Object.entries(r)) {
      if (k === 'embedding') continue
      if (v instanceof Blob) {
        const path = `media/${store}-${r.id}-${k}`
        zip.file(path, v)
        o[`${k}File`] = path
        continue
      }
      o[k] = v
    }
    if (store === 'settings' && o.providers) { // API keys never leave the device unless the user opts in (later)
      o.providers = Object.fromEntries(Object.entries(o.providers).map(([p, c]) => [p, { ...c, apiKey: '' }]))
    }
    return o
  })
}

export async function exportBundle() {
  const zip = new JSZip()
  zip.file('manifest.json', JSON.stringify({ version: BUNDLE_VERSION, createdAt: new Date().toISOString(), appVersion: '0.2.0' }, null, 2))
  for (const s of STORES) zip.file(`${s}.json`, JSON.stringify(clean(zip, s, await getAll(s))))
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
    for (const r of rows) {
      for (const k of Object.keys(r)) {
        if (!k.endsWith('File')) continue
        const media = zip.file(r[k])
        if (media) r[k.slice(0, -4)] = await media.async('blob')
        delete r[k]
      }
      if (s === 'settings' && mode === 'merge') { // keep this device's API keys when merging
        const { getSettings } = await import('./db.js')
        const cur = await getSettings()
        for (const p of Object.keys(r.providers || {})) r.providers[p].apiKey = cur.providers[p]?.apiKey || r.providers[p].apiKey || ''
      }
      await put(s, r)
    }
  }
}
VB_EOF
mkdir -p "./src/storage"
cat > "./src/storage/db.js" <<'VB_EOF'
import { openDB } from 'idb'

export const STORES = ['buddy', 'userProfile', 'message', 'memory', 'schedule', 'settings']
const DEFAULT_SETTINGS = {
  id: 'main', theme: 'ice', splashFit: 'cover', buttonLayout: [],
  activeProvider: 'openai', // 'local' arrives in M4
  providers: {
    openai: { apiKey: '', model: 'gpt-4o-mini' },
    anthropic: { apiKey: '', model: 'claude-haiku-4-5' },
    gemini: { apiKey: '', model: 'gemini-2.5-flash' },
    openrouter: { apiKey: '', model: 'openrouter/auto' },
  },
  localModelRef: null, activeBuddyId: null, premium: false,
  exitMessage: "You seem to be having a bad day. Let's talk later when you're feeling more like yourself.",
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

export const newId = () => (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(16).slice(2))

export async function getSettings() {
  const saved = (await (await db()).get('settings', 'main')) || {}
  const providers = { ...DEFAULT_SETTINGS.providers }
  for (const k of Object.keys(providers)) providers[k] = { ...providers[k], ...((saved.providers || {})[k] || {}) }
  return { ...DEFAULT_SETTINGS, ...saved, providers }
}
export async function putSettings(patch) { const next = { ...(await getSettings()), ...patch }; await (await db()).put('settings', next); return next }
export async function getAll(store) { return (await db()).getAll(store) }
export async function get(store, id) { return (await db()).get(store, id) }
export async function put(store, value) { return (await db()).put(store, value) }
export async function del(store, id) { return (await db()).delete(store, id) }
export async function clearStore(store) { return (await db()).clear(store) }

// ---- buddies / profile / messages ----
export async function getBuddies() { return (await getAll('buddy')).sort((a, b) => (a.createdAt || 0) - (b.createdAt || 0)) }
export async function getProfile() { return (await get('userProfile', 'me')) || null }
export const saveProfile = (p) => put('userProfile', { ...p, id: 'me' })
export async function getMessages(buddyId) {
  return ((await (await db()).getAllFromIndex('message', 'byBuddy', buddyId)) || []).sort((a, b) => a.ts - b.ts)
}
export async function deleteBuddy(id) {
  const d = await db()
  for (const store of ['message', 'memory', 'schedule']) {
    const keys = await d.getAllKeysFromIndex(store, 'byBuddy', id)
    for (const k of keys) await d.delete(store, k)
  }
  await d.delete('buddy', id)
  const s = await getSettings()
  if (s.activeBuddyId === id) await putSettings({ activeBuddyId: null })
}
// Returns the buddy chat/call screens should use, fixing a stale activeBuddyId.
export async function resolveActiveBuddy() {
  const [buddies, s] = await Promise.all([getBuddies(), getSettings()])
  const found = buddies.find((b) => b.id === s.activeBuddyId)
  if (found) return { buddy: found, buddies, needsPick: false }
  if (buddies.length === 1) { await putSettings({ activeBuddyId: buddies[0].id }); return { buddy: buddies[0], buddies, needsPick: false } }
  return { buddy: null, buddies, needsPick: buddies.length > 1 }
}
VB_EOF
mkdir -p "./src/storage"
cat > "./src/storage/image.js" <<'VB_EOF'
// Shrinks a chosen photo to a small square-ish JPEG so avatars stay light in IndexedDB and backups.
export async function toAvatarBlob(file, max = 320) {
  const bmp = await createImageBitmap(file)
  const scale = Math.min(1, max / Math.max(bmp.width, bmp.height))
  const c = document.createElement('canvas')
  c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale)
  c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height)
  return new Promise((res) => c.toBlob(res, 'image/jpeg', 0.85))
}
VB_EOF
mkdir -p "./src"
cat > "./src/styles.css" <<'VB_EOF'
:root { box-sizing: border-box; padding-top: env(safe-area-inset-top, 0px); padding-bottom: env(safe-area-inset-bottom, 0px); }
*, *::before, *::after { box-sizing: inherit; }
html[data-theme="light"] { --bg:#ffffff; --card:#f2f2f6; --text:#111114; --muted:#6b6b76; --accent:#2f7bff; --on-accent:#ffffff; --radius:14px; --font:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
html[data-theme="ice"]   { --bg:#0b0b0f; --card:#1c1c22; --text:#f5f5f7; --muted:#9a9aa5; --accent:#4f7cff; --on-accent:#ffffff; --radius:16px; --font:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
html[data-theme="mint"]  { --bg:#121212; --card:#232323; --text:#eaeaea; --muted:#a0a0a0; --accent:#6fd09a; --on-accent:#0b1f14; --radius:10px; --font:system-ui,Roboto,"Segoe UI",sans-serif; }
html[data-theme="lilac"] { --bg:#14101f; --card:#221b36; --text:#f1ecff; --muted:#a79fc4; --accent:#b388ff; --on-accent:#1a1030; --radius:22px; --font:system-ui,sans-serif; }
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
.btn { background: var(--accent); border-color: var(--accent); color: var(--on-accent); display: block; }
button.on { background: var(--accent); color: var(--on-accent); }

/* ---- M2 ---- */
.screen label { display: block; margin: 0 0 14px; font-size: .85rem; color: var(--muted); }
input, textarea, select { display: block; width: 100%; margin-top: 6px; font: inherit; font-size: 1rem; color: var(--text); background: var(--card); border: 1px solid transparent; border-radius: var(--radius); padding: 11px 13px; }
input:focus, textarea:focus, select:focus { outline: none; border-color: var(--accent); }
textarea { resize: vertical; }
.small { font-size: .8rem; }
.center-text { text-align: center; }
.btn.alt { background: var(--card); color: var(--text); border-color: var(--card); }
.plain, .plain-btn { background: none; border: 0; color: var(--accent); text-decoration: none; text-align: center; padding: 10px; font: inherit; cursor: pointer; }
.plain-btn { border: 1px solid var(--accent); border-radius: var(--radius); padding: 12px 16px; }
.danger { background: none; color: #ff5c6c; border-color: #ff5c6c; }
.prose h2 { font-size: 1.1rem; margin: 22px 0 8px; } .prose p, .prose li { line-height: 1.5; }
.avatar { border-radius: 50%; object-fit: cover; flex: none; }
.avatar.ph { display: inline-flex; align-items: center; justify-content: center; background: var(--accent); color: var(--on-accent); font-weight: 600; }
.avatar-pick { display: flex; flex-direction: column; align-items: center; gap: 8px; margin-bottom: 18px; }
.avatar-pick p { margin: 0; }

.chat { display: flex; flex-direction: column; height: calc(100dvh - 57px - env(safe-area-inset-top, 0px)); max-width: 640px; margin: 0 auto; }
.chat-head { display: flex; align-items: center; gap: 10px; padding: 8px 14px; border-bottom: 1px solid var(--card); }
.chat-head .plain { margin-left: auto; }
.chat-list { flex: 1; overflow-y: auto; padding: 14px; display: flex; flex-direction: column; gap: 6px; }
.bubble { max-width: 80%; padding: 9px 13px; border-radius: 18px; line-height: 1.35; white-space: pre-wrap; overflow-wrap: anywhere; }
.bubble.me { align-self: flex-end; background: var(--accent); color: var(--on-accent); border-bottom-right-radius: 5px; }
.bubble.them { align-self: flex-start; background: var(--card); border-bottom-left-radius: 5px; }
.typing { display: inline-flex; gap: 4px; padding: 13px 14px; }
.typing i { width: 7px; height: 7px; border-radius: 50%; background: var(--muted); animation: blink 1.2s infinite; }
.typing i:nth-child(2) { animation-delay: .2s; } .typing i:nth-child(3) { animation-delay: .4s; }
@keyframes blink { 0%, 80%, 100% { opacity: .25; } 40% { opacity: 1; } }
.note { align-self: center; text-align: center; color: #ff8a95; font-size: .85rem; padding: 6px 10px; }
.composer { display: flex; align-items: flex-end; gap: 8px; padding: 8px 12px calc(8px + env(safe-area-inset-bottom, 0px)); border-top: 1px solid var(--card); }
.composer textarea { margin: 0; resize: none; max-height: 120px; border-radius: 20px; }
.send { width: 40px; height: 40px; padding: 0; border-radius: 50%; background: var(--accent); border-color: var(--accent); color: var(--on-accent); font-size: 1.2rem; flex: none; }
.send:disabled { opacity: .4; }

.modal-back { position: fixed; inset: 0; background: #0009; display: flex; align-items: flex-end; justify-content: center; z-index: 50; }
.modal { background: var(--bg); width: 100%; max-width: 520px; border-radius: 20px 20px 0 0; padding: 18px 16px calc(18px + env(safe-area-inset-bottom, 0px)); display: flex; flex-direction: column; gap: 10px; }
.modal h2 { margin: 0 0 4px; font-size: 1.05rem; }
.pick { display: flex; align-items: center; gap: 12px; text-align: left; background: var(--card); border-color: var(--card); }
VB_EOF
mkdir -p "."
cat > "./vite.config.js" <<'VB_EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({ plugins: [react()] })
VB_EOF
chmod +x deploy/deploy.sh
echo "Updated virtual-buddy/. Next: npm install && ./deploy/deploy.sh"
