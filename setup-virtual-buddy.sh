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
# Virtual Buddy (v0.4.2, M4.2)
Dev: `npm install && npm run dev`. Deploy: see deploy/. HTTPS is required in production (PWA, mic, push).
Milestones: M1 shell/storage/bundle (this) -> M2 buddy+chat -> M3 memory -> M4 local model+demo -> M5 voice -> M6 calls/splash -> M7 accounts/push -> M8 premium.
VB_EOF
mkdir -p "deploy"
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
mkdir -p "deploy"
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
  "version": "0.4.2",
  "type": "module",
  "scripts": {
    "dev": "vite --host",
    "build": "vite build",
    "preview": "vite preview --host"
  },
  "dependencies": {
    "idb": "^8.0.0",
    "jszip": "^3.10.1",
    "react": "^18.3.1",
    "react-dom": "^18.3.1",
    "react-router-dom": "^6.26.0",
    "@wllama/wllama": "^3.8.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.3.1",
    "vite": "^5.4.0"
  }
}
VB_EOF
mkdir -p "public"
cat > "./public/icon.svg" <<'VB_EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="112" fill="#4f7cff"/><circle cx="256" cy="210" r="86" fill="#fff"/><path d="M110 430c14-82 72-122 146-122s132 40 146 122z" fill="#fff"/></svg>
VB_EOF
mkdir -p "public"
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
mkdir -p "public"
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
mkdir -p "src"
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
import EditMemories from './screens/EditMemories.jsx'
import Demo from './screens/Demo.jsx'
import * as P from './screens/Placeholders.jsx'

// path -> [title, component]. Screen numbers refer to the flow in the spec.
const ROUTES = {
  '/signin': ['Sign in', P.SignIn], '/demo': ['Demo', Demo], '/buddy/edit': ['Buddy', BuddyEditor],
  '/call/incoming': ['Incoming call', P.IncomingCall], '/call/outgoing': ['Calling', P.OutgoingCall],
  '/chat': ['Messages', Chat], '/settings': ['Settings', Settings], '/premium': ['Premium', P.Premium],
  '/profile': ['Your profile', UserProfile], '/about': ['About', About], '/help': ['Help', Help],
  '/memories': ['Memories', EditMemories],
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
mkdir -p "src/ai/local"
cat > "./src/ai/local/engine.js" <<'VB_EOF'
// On-device AI via wllama (llama.cpp compiled to WebAssembly, with WebGPU when the browser has it).
// Everything is loaded lazily so people who never use local models never download the engine.
import { LOCAL_LIMITS, IMPORT_PREFIX, modelLabel, samplingFrom } from './models.js'

const mock = () => globalThis.__VB_MOCK_ENGINE__ // test seam: lets automated tests swap in a fake engine

let wl = null
let loadedUrl = null
let lock = Promise.resolve()
// phase: idle | loading | ready | error. stage (only while a reply is being made): loading | thinking | writing | null.
// Everything shown to people comes from these real states, nothing is faked.
let status = { phase: 'idle', url: null, stage: null, since: 0, error: '' }
const listeners = new Set()
const setStatus = (s) => { status = { ...status, ...s, ...('stage' in s && s.stage !== status.stage ? { since: Date.now() } : {}) }; listeners.forEach((f) => f(status)) }
export const getStatus = () => status
export function subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn) }

async function lib() {
  if (!wl) {
    const [{ Wllama }, wasm] = await Promise.all([import('@wllama/wllama/esm/index.js'), import('@wllama/wllama/esm/wasm/wllama.wasm?url')])
    wl = new Wllama({ default: wasm.default }, { suppressNativeLog: true, allowOffline: true })
  }
  return wl
}
function acquire() {
  let release
  const prev = lock
  lock = new Promise((r) => { release = r })
  return prev.then(() => release)
}

export async function listInstalled() {
  if (mock()) return mock().listInstalled()
  const w = await lib()
  return (await w.modelManager.getModels()).filter((m) => m.size > 0)
    .map((m) => ({ url: m.url, size: m.size, name: modelLabel(m.url), imported: m.url.startsWith(IMPORT_PREFIX) }))
}

async function cleanupPartial(url) {
  try {
    const w = await lib(); const name = await w.cacheManager.getNameFromURL(url)
    const dir = await cacheDir(); if (!dir) return
    let meta = true; try { await dir.getFileHandle(META + name) } catch { meta = false }
    if (!meta) await dir.removeEntry(name) // half-finished file: remove so it doesn't eat storage
  } catch { /* best effort */ }
}

export async function downloadModel(url, { onProgress, signal } = {}) {
  if (mock()) return mock().downloadModel(url, { onProgress, signal })
  if (!/^https:\/\//i.test(url) && !/^http:\/\/localhost[:/]/i.test(url)) throw new Error('Model links must start with https://')
  if (!/\.gguf(\?.*)?$/i.test(url)) throw new Error('That link should end in .gguf')
  const w = await lib()
  try {
    await w.modelManager.downloadModel(url, { signal, progressCallback: ({ loaded, total }) => onProgress?.(loaded, total) })
  } catch (e) {
    await cleanupPartial(url)
    if (e?.name === 'AbortError' || signal?.aborted) throw e
    const msg = String(e?.message || e)
    if (/404|not found/i.test(msg)) throw new Error("That model file couldn't be found. The host may have moved it. You can pick a different one, or choose a .gguf file from your device.")
    if (/quota|space|storage/i.test(msg)) throw new Error('Not enough free storage on this device for that model.')
    throw new Error(`Download failed: ${msg}`)
  }
}

// ---- Storage on this device (the model cache lives in the browser's private file area, invisible to file apps)
const META = '__metadata__'
async function cacheDir(create = false) {
  if (!navigator.storage?.getDirectory) return null
  const root = await navigator.storage.getDirectory()
  try { return await root.getDirectoryHandle('cache', { create }) } catch { return null }
}
async function unloadEngine() {
  if (wl && wl.isModelLoaded()) { try { await wl.exit() } catch { /* ignore */ } }
  loadedUrl = null; setStatus({ phase: 'idle', url: null, stage: null })
}
export async function storageReport() {
  let usage = 0, quota = 0
  try { const e = await navigator.storage.estimate(); usage = e.usage || 0; quota = e.quota || 0 } catch { /* ignore */ }
  const files = new Map(), metas = new Map()
  const dir = await cacheDir()
  if (dir) for await (const [name, h] of dir.entries()) {
    if (h.kind !== 'file') continue
    const f = await h.getFile()
    if (name.startsWith(META)) { let m = null; try { m = JSON.parse(await f.text()) } catch { /* ignore */ } metas.set(name.slice(META.length), m) }
    else files.set(name, f.size)
  }
  const items = [...files].map(([name, size]) => {
    const m = metas.get(name)
    const complete = !!m && (!m.originalSize || m.originalSize === size || m.etag === 'local-import')
    return { name, size, complete, label: m?.originalURL ? modelLabel(m.originalURL) : 'Incomplete file' }
  })
  for (const k of metas.keys()) if (!files.has(k)) items.push({ name: k, size: 0, complete: false, label: 'Leftover info file', orphan: true })
  items.sort((a, b) => b.size - a.size)
  return { usage, quota, items }
}
export async function deleteCacheItem(name) {
  await unloadEngine()
  const dir = await cacheDir(); if (!dir) return
  for (const n of [name, META + name]) { try { await dir.removeEntry(n) } catch { /* already gone */ } }
}
export async function clearAllModelFiles() {
  await unloadEngine()
  const root = await navigator.storage.getDirectory()
  try { await root.removeEntry('cache', { recursive: true }) } catch { /* nothing there */ }
}

export async function importFile(file, { onProgress } = {}) {
  if (mock()) return mock().importFile(file, { onProgress })
  if (!/\.gguf$/i.test(file.name)) throw new Error('Please choose a .gguf model file.')
  if ((await file.slice(0, 4).text()) !== 'GGUF') throw new Error("That file doesn't look like a GGUF model.")
  const w = await lib()
  const url = IMPORT_PREFIX + encodeURIComponent(file.name)
  const name = await w.cacheManager.getNameFromURL(url)
  let n = 0
  const counted = file.stream().pipeThrough(new TransformStream({ transform(chunk, c) { n += chunk.byteLength; onProgress?.(n, file.size); c.enqueue(chunk) } }))
  await w.cacheManager.write(name, counted, { etag: 'local-import', originalSize: file.size, originalURL: url })
  return url
}

export async function removeModel(url) {
  if (mock()) return mock().removeModel(url)
  const w = await lib()
  if (loadedUrl === url) { await w.exit(); loadedUrl = null; setStatus({ phase: 'idle', url: null }) }
  const m = (await w.modelManager.getModels({ includeInvalid: true })).find((x) => x.url === url)
  if (m) await m.remove()
}

async function ensureLoaded(url) {
  const w = await lib()
  if (loadedUrl === url && w.isModelLoaded()) return w
  if (w.isModelLoaded()) await w.exit()
  loadedUrl = null
  setStatus({ phase: 'loading', url, stage: 'loading', error: '' })
  const model = (await w.modelManager.getModels()).find((m) => m.url === url)
  if (!model) { setStatus({ phase: 'error', stage: null, error: 'missing' }); throw new Error("That model isn't on this device any more. Open Settings, then AI model, to download one.") }
  const params = { n_ctx: LOCAL_LIMITS.nCtx }
  try {
    await w.loadModel(model, params)
  } catch {
    // Some phones can't give the model graphics memory: try again on the processor.
    try { if (w.isModelLoaded()) await w.exit(); await w.loadModel(model, { ...params, n_gpu_layers: 0 }) }
    catch (e2) {
      setStatus({ phase: 'error', stage: null, error: 'load-failed' })
      throw new Error(`This device couldn't load ${modelLabel(url)}. It may not have enough memory; try a smaller model. (${String(e2?.message || e2).slice(0, 120)})`)
    }
  }
  loadedUrl = url
  setStatus({ phase: 'ready', url, error: '' })
  return w
}

// Same shape as the cloud providers: yields text pieces. One request at a time.
export async function* streamLocal({ modelUrl, system, messages, signal, sampling }) {
  const sp = samplingFrom(sampling)
  if (mock()) {
    setStatus({ stage: 'thinking' })
    try { for await (const t of mock().stream({ modelUrl, system, messages, signal, sampling: sp })) { setStatus({ stage: 'writing' }); yield t } }
    finally { setStatus({ stage: null }) }
    return
  }
  if (!modelUrl) throw new Error('No on-device model yet. Open Settings, then AI model, to download one.')
  setStatus({ stage: 'loading' }) // waiting our turn / loading
  const release = await acquire()
  try {
    const w = await ensureLoaded(modelUrl)
    if (signal?.aborted) return
    setStatus({ stage: 'thinking' }) // reading the prompt
    const params = {
      messages: [{ role: 'system', content: system }, ...messages],
      stream: true, abortSignal: signal,
      max_tokens: Number(sp.max_tokens) || LOCAL_LIMITS.maxTokens,
      temperature: Number(sp.temperature), top_k: Number(sp.top_k), top_p: Number(sp.top_p),
      min_p: Number(sp.min_p), penalty_repeat: Number(sp.repeat_penalty),
    }
    if (sp.seed !== '' && sp.seed != null && Number.isFinite(Number(sp.seed))) params.seed = Math.trunc(Number(sp.seed))
    const it = await w.createChatCompletion(params)
    for await (const c of it) { const d = c.choices?.[0]?.delta?.content; if (d) { if (status.stage !== 'writing') setStatus({ stage: 'writing' }); yield d } }
  } catch (e) {
    const msg = String(e?.message || e)
    if (/exceeds the available context|context size/i.test(msg)) throw new Error("That was too much for this model to hold in mind at once. Try a shorter message, or a model with more memory in Settings.")
    throw e
  } finally {
    setStatus({ stage: null })
    release()
  }
}
VB_EOF
mkdir -p "src/ai/local"
cat > "./src/ai/local/models.js" <<'VB_EOF'
// Curated on-device models (GGUF, 4-bit). Sizes are approximate. If a link ever 404s the app says so and
// people can still pick their own .gguf file or paste a link in Settings.
export const CATALOG = [
  { id: 'qwen25-05b', name: 'Qwen2.5 0.5B', tier: 'tiny', sizeMB: 400, license: 'Apache 2.0',
    blurb: 'Smallest and fastest. Best for older or low-memory phones.',
    url: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q4_k_m.gguf' },
  { id: 'gemma3-1b', name: 'Gemma 3 1B', tier: 'small', sizeMB: 810, license: 'Gemma Terms of Use',
    blurb: 'A good balance of quality, speed and size.',
    url: 'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf' },
  { id: 'llama32-1b', name: 'Llama 3.2 1B', tier: 'small', sizeMB: 810, license: 'Llama 3.2 Community License',
    blurb: 'A friendly conversationalist of about the same size.',
    url: 'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf' },
  { id: 'qwen25-15b', name: 'Qwen2.5 1.5B', tier: 'good', sizeMB: 1100, license: 'Apache 2.0',
    blurb: 'Noticeably smarter, needs a newer phone with plenty of memory.',
    url: 'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf' },
]
export const DEMO_MODEL = CATALOG[0]
export const IMPORT_PREFIX = 'https://imported.local/'

// Small models have small context windows, so everything sent to them is trimmed harder.
export const LOCAL_LIMITS = { nCtx: 3072, historyChars: 3500, memoryChars: 1000, maxTokens: 512 }
// Advanced controls for on-device replies. Defaults favour short, steady, human-sounding texts.
export const SAMPLING_DEFAULTS = { temperature: 0.6, top_k: 40, top_p: 0.9, min_p: 0.05, repeat_penalty: 1.15, max_tokens: 200, seed: '' }
export const SAMPLING_FIELDS = [
  { key: 'temperature', label: 'Temperature', min: 0, max: 1.5, step: 0.05, help: 'Lower is calmer and more predictable. Higher is more varied, and small models get silly when it is too high.' },
  { key: 'top_k', label: 'Top K', min: 1, max: 200, step: 1, help: 'Only the K most likely next words are considered. Lower is safer.' },
  { key: 'top_p', label: 'Top P', min: 0.1, max: 1, step: 0.05, help: 'Considers only the most likely words that add up to this share of the probability.' },
  { key: 'min_p', label: 'Min P', min: 0, max: 0.5, step: 0.01, help: 'Drops words that are very unlikely compared to the best one. Helps small models stay on track.' },
  { key: 'repeat_penalty', label: 'Repeat penalty', min: 1, max: 1.6, step: 0.05, help: 'Discourages repeating itself. Too high makes replies odd.' },
  { key: 'max_tokens', label: 'Max reply length (tokens)', min: 30, max: 800, step: 10, help: 'A hard cap on reply length (about 3 tokens per 2 words). Short caps keep a chatty model from rambling.' },
]
export function samplingFrom(saved) { return { ...SAMPLING_DEFAULTS, ...(saved || {}) } }

export const CLOUD_LIMITS = { historyChars: 12000, memoryChars: 2500, maxTokens: 1024 }
export const limitsFor = (provider) => (provider === 'local' ? LOCAL_LIMITS : CLOUD_LIMITS)

export function modelLabel(url) {
  if (!url) return 'an on-device model'
  const hit = CATALOG.find((m) => m.url === url)
  if (hit) return hit.name
  try { return decodeURIComponent(url.split('/').pop()).replace(/\.gguf$/i, '') } catch { return 'an on-device model' }
}
VB_EOF
mkdir -p "src/ai"
cat > "./src/ai/promptBuilder.js" <<'VB_EOF'
import { SAFETY_BLOCK } from './safety.js'

const line = (label, v) => (v && String(v).trim() ? `${label}: ${String(v).trim()}\n` : '')

// How a real friend texts. Small models follow short, concrete rules and imitate examples, so this is
// blunt on purpose, and repeated at the very end of the prompt where small models pay most attention.
const TEXTING_RULES = `How you talk:
- You are a person texting a friend, not an assistant. Never say things like "How can I assist you", "How can I help", "I'm here to help", "As an AI", or "Is there anything else".
- Keep it short: usually 1 or 2 sentences. Match the length and mood of what they wrote. A short question gets a short answer.
- Answer only what was asked. Do not list facts about yourself or recite your background, hobbies or family unless they ask for exactly that. Share one small thing at a time.
- If asked about your day, mention one ordinary thing in a sentence, then ask about theirs. Don't make a speech.
- Ask at most one question, and only when it feels natural. No bullet points, no headings, no emojis unless it's how you talk.
- Use the "How you talk" notes below for your voice. If you are described as quiet or not chatty, be brief and dry, not bubbly.`

const EXAMPLES = `Examples of the feel (not to be copied word for word):
Them: hey
You: hey! good to see you
Them: rough day
You: ugh, I'm sorry. want to tell me about it?
Them: what did you do today
You: not much, mostly errands. you?`

export function buildSystem({ buddy, profile, memories = [], compact = false }) {
  let s = `You are ${buddy.name || 'a friendly companion'}, a companion character in a chat/phone app. Stay in character and write the way a real person texts or talks: natural, warm, usually brief.\n\n`
  s += TEXTING_RULES + '\n\n'
  s += '## Who you are (background for you to know. Only bring it up when it fits)\n'
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
  if (compact) s += '\n\n' + EXAMPLES + `\n\nRemember: you are ${buddy.name || 'their friend'}, texting. Short, natural, no assistant phrases, and only answer what was asked.`
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
mkdir -p "src/ai"
cat > "./src/ai/provider.js" <<'VB_EOF'
import { streamLocal } from './local/engine.js'

export const PROVIDERS = {
  local: { label: 'On this device (private)', keyHint: '' },
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

export async function* streamChat({ provider, apiKey, model, system, messages, signal, sampling }) {
  const label = PROVIDERS[provider]?.label || provider
  const msgs = normalize(messages)
  if (provider === 'local') {
    yield* streamLocal({ modelUrl: model, system, messages: msgs, signal, sampling })
    return
  }
  if (!apiKey) throw new Error(`Add your ${label} API key in Settings first.`)

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
    throw new Error('Unknown AI provider. Pick one in Settings.')
  }
}

// Runs a prompt to completion and returns the full text (used for background jobs like memory extraction).
export async function completeChat(args) {
  let out = ''
  for await (const chunk of streamChat(args)) out += chunk
  return out
}
VB_EOF
mkdir -p "src/ai"
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
mkdir -p "src/components"
cat > "./src/components/AdvancedControls.jsx" <<'VB_EOF'
import { useState } from 'react'
import { putSettings } from '../storage/db.js'
import { SAMPLING_DEFAULTS, SAMPLING_FIELDS, samplingFrom } from '../ai/local/models.js'

// Optional tuning for the on-device model. Safe defaults; Reset puts everything back.
export default function AdvancedControls({ settings, onChange, active = true }) {
  const [open, setOpen] = useState(false)
  const v = samplingFrom(settings.sampling)
  const save = async (patch) => { await putSettings({ sampling: { ...v, ...patch } }); onChange?.() }
  const reset = async () => { await putSettings({ sampling: null }); onChange?.() }
  const changed = JSON.stringify(v) !== JSON.stringify(SAMPLING_DEFAULTS)
  return (
    <section className="card adv">
      <h2>Advanced (on-device model)</h2>
      {!active && <p className="notice">These apply only when the provider above is “On this device”.</p>}
      <p className="muted small">These change how the on-device model writes. They can make replies steadier or shorter, but they cannot make a small model smarter. A bigger model is the only thing that does that.</p>
      <button type="button" onClick={() => setOpen(!open)} aria-expanded={open}>{open ? 'Hide advanced controls' : 'Show advanced controls'}</button>
      {open && (
        <div className="stack">
          {SAMPLING_FIELDS.map((f) => (
            <label key={f.key}>{f.label}
              <small>{f.help}</small>
              <div className="adv-row">
                <input type="range" min={f.min} max={f.max} step={f.step} value={v[f.key]} onChange={(e) => save({ [f.key]: Number(e.target.value) })} />
                <input type="number" key={f.key + v[f.key]} min={f.min} max={f.max} step={f.step} defaultValue={v[f.key]} onBlur={(e) => { const n = Number(e.target.value); if (e.target.value !== '' && Number.isFinite(n)) save({ [f.key]: Math.min(f.max, Math.max(f.min, n)) }) }} />
              </div>
            </label>
          ))}
          <label>Seed
            <small>Leave empty for a fresh result each time. A number makes replies repeatable, which is handy for testing.</small>
            <input type="number" inputMode="numeric" placeholder="random" key={'seed' + v.seed} defaultValue={v.seed} onBlur={(e) => save({ seed: e.target.value === '' ? '' : Math.trunc(Number(e.target.value)) })} />
          </label>
          <button type="button" onClick={reset} disabled={!changed}>Reset to defaults</button>
        </div>
      )}
    </section>
  )
}
VB_EOF
mkdir -p "src/components"
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
mkdir -p "src/components"
cat > "./src/components/Field.jsx" <<'VB_EOF'
// A labelled input with a permanent caption underneath (placeholders vanish while typing; captions don't).
export default function Field({ label, hint, children }) {
  return (
    <label className="field">
      <span className="lbl">{label}</span>
      {children}
      {hint && <span className="hint">{hint}</span>}
    </label>
  )
}
VB_EOF
mkdir -p "src/components"
cat > "./src/components/LocalModelPanel.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { checkDevice, recommend, fitFor, describeDevice, UNSUPPORTED_MESSAGE } from '../device/capability.js'
import { CATALOG } from '../ai/local/models.js'
import { listInstalled, downloadModel, importFile, removeModel } from '../ai/local/engine.js'
import StoragePanel from './StoragePanel.jsx'
import { putSettings } from '../storage/db.js'

const mb = (n) => (n >= 1e9 ? (n / 1e9).toFixed(1) + ' GB' : Math.round(n / 1e6) + ' MB')

export default function LocalModelPanel({ settings, onChange }) {
  const [device, setDevice] = useState(null)
  const [installed, setInstalled] = useState([])
  const [busy, setBusy] = useState(null)      // { label, loaded, total }
  const [error, setError] = useState('')
  const [custom, setCustom] = useState('')
  const [storeKey, setStoreKey] = useState(0)
  const abort = useRef(null)
  const file = useRef()
  const active = settings.providers.local?.model || ''

  const refresh = async () => { try { setInstalled(await listInstalled()) } catch (e) { setError(e.message) } }
  useEffect(() => { checkDevice().then(setDevice); refresh() }, [])

  const setActive = async (url) => { await putSettings({ providers: { ...settings.providers, local: { ...settings.providers.local, model: url } } }); onChange() }
  const afterInstall = async (url) => { await refresh(); if (!active || !installed.some((m) => m.url === active)) await setActive(url) }

  async function download(url, label, sizeMB, key = url) {
    if (navigator.connection?.type === 'cellular' && !confirm(`This download is large${sizeMB ? ` (about ${sizeMB} MB)` : ''} and you seem to be on mobile data. Download anyway?`)) return
    setError(''); abort.current = new AbortController(); setBusy({ key, label, loaded: 0, total: 0 })
    try {
      await downloadModel(url, { signal: abort.current.signal, onProgress: (loaded, total) => setBusy({ key, label, loaded, total }) })
      await afterInstall(url)
    } catch (e) { if (e.name !== 'AbortError') setError(e.message) }
    setBusy(null); setStoreKey((k) => k + 1)
  }
  async function pickFile(e) {
    const f = e.target.files[0]; e.target.value = ''; if (!f) return
    setError(''); setBusy({ key: 'file', label: f.name, loaded: 0, total: f.size })
    try { afterInstall(await importFile(f, { onProgress: (loaded, total) => setBusy({ key: 'file', label: f.name, loaded, total }) })); await refresh() } catch (err) { setError(err.message) }
    setBusy(null); setStoreKey((k) => k + 1)
  }
  async function remove(m) {
    if (!confirm(`Remove ${m.name} from this device? You can download it again later.`)) return
    await removeModel(m.url); if (active === m.url) await setActive(''); await refresh(); setStoreKey((k) => k + 1)
  }

  if (!device) return <p className="muted small">Checking your device...</p>
  const rec = recommend(device)
  const installedUrls = new Set(installed.map((m) => m.url))
  const total = installed.reduce((n, m) => n + m.size, 0)
  const pct = busy && busy.total ? Math.round((busy.loaded / busy.total) * 100) : 0
  const Progress = ({ k }) => !busy || busy.key !== k ? null : (
    <div className="progress" role="status">
      <div className="small">{busy.total ? `Downloading… ${pct}% (${mb(busy.loaded)} of ${mb(busy.total)})` : busy.loaded ? `Downloading… ${mb(busy.loaded)}` : 'Starting download…'}</div>
      <div className="bar"><div style={{ width: `${pct}%` }} /></div>
      {abort.current && k !== 'file' && <button className="quiet" onClick={() => abort.current.abort()}>Cancel</button>}
    </div>
  )

  return (
    <div className="local">
      <p className={`notice ${device.supported ? '' : 'warn'}`}>
        {device.supported ? `Your device can run AI on its own: ${describeDevice(device)}.` : UNSUPPORTED_MESSAGE}
      </p>

      {installed.length > 0 && (
        <>
          <h3>On this device</h3>
          {installed.map((m) => (
            <div key={m.url} className={`model ${active === m.url ? 'inuse' : ''}`}>
              <div><strong>{m.name}</strong>{m.imported && <span className="chip">Your file</span>}<div className="small muted">{mb(m.size)}</div></div>
              <div className="row">
                {active === m.url ? <span className="chip pin">In use</span> : <button onClick={() => setActive(m.url)}>Use</button>}
                <button className="quiet" onClick={() => remove(m)}>Remove</button>
              </div>
            </div>
          ))}
          <p className="muted small">Models use about {mb(total)}. They live only on this device and are not included in backups.</p>
        </>
      )}

      {device.supported && (
        <>
          <h3>Download a model</h3>
          <p className="muted small">Smaller models are faster and fit more phones; bigger ones sound smarter. One download, then it works offline. Use Wi-Fi if you can.</p>
          {CATALOG.filter((m) => !installedUrls.has(m.url)).map((m) => (
            <div key={m.id} className="model">
              <div>
                <strong>{m.name}</strong>
                {rec?.id === m.id && <span className="chip new">Recommended</span>}
                {fitFor(device, m) === 'heavy' && <span className="chip">May be slow here</span>}
                <div className="small muted">{m.blurb}</div>
                <div className="small muted">About {m.sizeMB >= 1000 ? (m.sizeMB / 1000).toFixed(1) + ' GB' : m.sizeMB + ' MB'} · {m.license}</div>
              </div>
              <button disabled={!!busy} onClick={() => download(m.url, m.name, m.sizeMB)}>{busy?.key === m.url ? 'Downloading…' : 'Download'}</button>
              <Progress k={m.url} />
            </div>
          ))}

          <h3>Use your own model</h3>
          <div className="row"><button disabled={!!busy} onClick={() => file.current.click()}>Choose a .gguf file</button></div>
          <input ref={file} type="file" hidden onChange={pickFile} /> {/* no accept filter: phones grey out files they do not recognise */}
          <Progress k="file" />
          <label className="field" style={{ marginTop: 12 }}>
            <span className="lbl">Or download from a link</span>
            <input value={custom} onChange={(e) => setCustom(e.target.value)} placeholder="https://.../model-q4_k_m.gguf" inputMode="url" />
            <span className="hint">Only use models from sources you trust. Check the model's license before using it.</span>
          </label>
          <button disabled={!!busy || !custom.trim()} onClick={() => download(custom.trim(), 'your model', undefined, 'custom')}>{busy?.key === 'custom' ? 'Downloading…' : 'Download from link'}</button>
          <Progress k="custom" />
        </>
      )}

      <StoragePanel settings={settings} onChange={onChange} refreshKey={storeKey} />
      {error && <p className="error">{error}</p>}
    </div>
  )
}
VB_EOF
mkdir -p "src/components"
cat > "./src/components/MenuBar.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { Link, useLocation, useNavigate } from 'react-router-dom'

const ITEMS = [['Settings', '/settings'], ['Make call', '/call/outgoing'], ['Receive call', '/call/incoming'], ['Messaging', '/chat'], ['About', '/about'], ['Help', '/help']]

export default function MenuBar({ title }) {
  const nav = useNavigate()
  const { pathname } = useLocation()
  const [open, setOpen] = useState(false)
  useEffect(() => setOpen(false), [pathname])
  useEffect(() => {
    if (!open) return
    const onKey = (e) => e.key === 'Escape' && setOpen(false)
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open])
  return (
    <header className="menubar">
      <button aria-label="Back" onClick={() => nav(-1)}>‹</button>
      <h1>{title}</h1>
      <button aria-label="Menu" aria-expanded={open} onClick={() => setOpen(!open)}>☰</button>
      {open && (
        <>
          <div className="menu-back" onClick={() => setOpen(false)} />
          <nav className="menu">
            {ITEMS.map(([label, to]) => <Link key={to} to={to} onClick={() => setOpen(false)}>{label}</Link>)}
          </nav>
        </>
      )}
    </header>
  )
}
VB_EOF
mkdir -p "src/components"
cat > "./src/components/ReplyStatus.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'

// Honest progress for the on-device model. The stage comes from the real engine state; the words only
// move forward inside the stage we are really in, and the dots/timer are real elapsed seconds.
const WORDS = {
  loading: ['Waking up', 'Loading', 'Initializing'],
  thinking: ['Remembering', 'Contemplating'],
}
const WORD_SECONDS = 8

function clock(s) { return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${String(s % 60).padStart(2, '0')}s` }

export default function ReplyStatus({ stage, since }) {
  const [now, setNow] = useState(Date.now())
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t) }, [])
  if (!stage || !WORDS[stage]) return null
  const secs = Math.max(0, Math.floor((now - since) / 1000))
  const words = WORDS[stage]
  const i = Math.min(words.length - 1, Math.floor(secs / WORD_SECONDS))
  const dots = i === words.length - 1 ? secs - i * WORD_SECONDS : secs % WORD_SECONDS
  let hint = ''
  if (stage === 'loading') {
    if (secs >= 180) hint = "This is taking unusually long and may be stuck. If nothing changes soon, tap ■ and try a smaller model in Settings."
    else if (secs >= 45) hint = "Still loading. The first reply is slow because the model has to be read into memory. I can't see exact progress, but it hasn't failed."
    else hint = 'The first reply is the slowest. After this the model stays awake.'
  } else if (secs >= 60) hint = 'Still thinking. Older phones can be slow with long conversations.'
  return (
    <div className="note soft reply-status" role="status" aria-live="polite">
      <div className="rs-line">{words[i]}{'.'.repeat(dots)} <span className="rs-time">{clock(secs)}</span></div>
      {hint && <div className="rs-hint">{hint}</div>}
    </div>
  )
}
VB_EOF
mkdir -p "src/components"
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
mkdir -p "src/components"
cat > "./src/components/StoragePanel.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { storageReport, deleteCacheItem, clearAllModelFiles, listInstalled } from '../ai/local/engine.js'
import { putSettings } from '../storage/db.js'

const mb = (n) => (n >= 1e9 ? (n / 1e9).toFixed(2) + ' GB' : Math.round(n / 1e6) + ' MB')

// Shows everything the on-device AI has stored, including half-finished downloads, with a way to delete it.
export default function StoragePanel({ settings, onChange, refreshKey }) {
  const [r, setR] = useState(null)
  const [err, setErr] = useState('')
  const load = () => storageReport().then(setR).catch((e) => setErr(e.message))
  useEffect(() => { load() }, [refreshKey])
  async function afterDelete() { await load(); onChange?.() }
  async function dropMissingActive() { // if the model in use was deleted, forget it so the app asks for a new one
    const s = settings.providers.local
    try { const inst = await listInstalled(); if (s?.model && !inst.some((m) => m.url === s.model)) await putSettings({ providers: { ...settings.providers, local: { ...s, model: '' } } }) } catch { /* ignore */ }
  }
  async function del(it) {
    if (!confirm(`Delete ${it.label} (${mb(it.size)}) from this device?`)) return
    await deleteCacheItem(it.name)
    await dropMissingActive()
    await afterDelete()
  }
  async function clearAll() {
    if (!confirm('Delete every downloaded AI model and unfinished download from this device? Your buddies, chats and memories are not touched.')) return
    await clearAllModelFiles()
    await dropMissingActive()
    await afterDelete()
  }
  if (!r) return err ? <p className="error">{err}</p> : null
  const modelBytes = r.items.reduce((n, i) => n + i.size, 0)
  return (
    <div className="storage">
      <h3>Storage</h3>
      <p className="small muted">Your browser says this app uses {mb(r.usage)}{r.quota ? ` of about ${mb(r.quota)} available to it` : ''}. AI models are kept in a private area of the browser, so they don't show up in your Files app. Delete them here to free the space.</p>
      {r.items.length === 0 && <p className="small muted">No AI model files stored.</p>}
      {r.items.map((it) => (
        <div key={it.name} className="model">
          <div><strong>{it.label}</strong>{!it.complete && <span className="chip">Unfinished</span>}<div className="small muted">{mb(it.size)}</div></div>
          <button className="quiet" onClick={() => del(it)}>Delete</button>
        </div>
      ))}
      {r.items.length > 0 && <button className="quiet" onClick={clearAll}>Delete all model files ({mb(modelBytes)})</button>}
      {r.usage - modelBytes > 50e6 && <p className="small muted">The rest ({mb(Math.max(0, r.usage - modelBytes))}) is the app itself and its cache. If your browser still shows lots of space used, clearing this site's data in your browser settings frees it too (back up your buddies first).</p>}
    </div>
  )
}
VB_EOF
mkdir -p "src/demo"
cat > "./src/demo/demoBuddy.js" <<'VB_EOF'
import { SAFETY_BLOCK } from '../ai/safety.js'

export const DEMO_ID = 'demo'
// Fixed and not editable. Not a role-played person: it talks honestly as the AI it is.
export const DEMO_BUDDY = { id: DEMO_ID, name: 'Demo Buddy', gender: 'f', avatar: null, demo: true }

export function buildDemoSystem(modelName) {
  return `You are Demo Buddy, the built-in demo companion of an app called Virtual Buddy. You are not playing a human character. You are an AI language model (${modelName}) and you speak honestly about that, including that you can make mistakes.

Your job is to let the person try the app right away. Be warm, curious and brief, usually one to three sentences, the way people text. Chat about whatever they like. If they ask about yourself, answer truthfully as the AI you are; do not invent a human life story, family or job.

If they ask what Virtual Buddy is: it lets people create companions that can be a friend, mentor, accountability partner or practice partner for hard conversations. People choose who their buddy is, how they talk, and what they remember. Buddies chat by text and by voice, and everything can run privately on the person's own device. Free accounts get one buddy plus you; premium adds more buddies and cloud AI.

${SAFETY_BLOCK}`
}
VB_EOF
mkdir -p "src/device"
cat > "./src/device/capability.js" <<'VB_EOF'
import { CATALOG } from '../ai/local/models.js'

let cached
// Looks at what this browser/device can do. Cheap, but cached for the session.
export async function checkDevice(force = false) {
  if (cached && !force) return cached
  const ua = navigator.userAgent || ''
  const isIOS = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
  const wasm = typeof WebAssembly === 'object'
  const secure = !!window.isSecureContext
  const opfs = !!(navigator.storage && navigator.storage.getDirectory)
  let webgpu = false
  try { webgpu = !!(navigator.gpu && (await navigator.gpu.requestAdapter())) } catch { /* no GPU access */ }
  let quotaMB = null, usedMB = null
  try { const e = await navigator.storage.estimate(); quotaMB = Math.round((e.quota || 0) / 1e6); usedMB = Math.round((e.usage || 0) / 1e6) } catch { /* unknown */ }
  const memoryGB = navigator.deviceMemory || null // Chrome only, capped at 8
  const freeMB = quotaMB != null ? Math.max(0, quotaMB - (usedMB || 0)) : null

  const supported = wasm && secure && opfs
  let tier = 'tiny'
  if (supported) {
    if (memoryGB && memoryGB >= 6) tier = 'good'
    else if (memoryGB && memoryGB >= 4) tier = 'small'
    else if (!memoryGB && !isIOS) tier = 'small'          // unknown memory on desktop-class browsers
    else if (!memoryGB && isIOS && webgpu) tier = 'small' // newer iPhones
    else tier = 'tiny'
  }
  cached = { isIOS, wasm, secure, opfs, webgpu, memoryGB, quotaMB, usedMB, freeMB, supported, tier,
    cores: navigator.hardwareConcurrency || null }
  return cached
}

export const UNSUPPORTED_MESSAGE = "This device can't run AI on its own. Upgrade to premium to use cloud AI, or try a newer phone."

const ORDER = ['tiny', 'small', 'good']
// Which catalog entry to suggest for this device.
export function recommend(device) {
  if (!device?.supported) return null
  return device.tier === 'tiny' ? CATALOG.find((m) => m.id === 'qwen25-05b') : CATALOG.find((m) => m.id === 'gemma3-1b')
}
// 'ok' | 'heavy' (bigger than the device tier suggests) for a catalog entry.
export function fitFor(device, model) {
  if (!device?.supported) return 'no'
  return ORDER.indexOf(model.tier) > ORDER.indexOf(device.tier) ? 'heavy' : 'ok'
}
export function describeDevice(d) {
  const bits = [d.webgpu ? 'graphics acceleration available' : 'no graphics acceleration (will use the processor)']
  if (d.memoryGB) bits.push(`about ${d.memoryGB}${d.memoryGB >= 8 ? '+' : ''} GB memory`)
  if (d.freeMB != null) bits.push(`${d.freeMB >= 1000 ? (d.freeMB / 1000).toFixed(1) + ' GB' : d.freeMB + ' MB'} free storage`)
  return bits.join(', ')
}
VB_EOF
mkdir -p "src"
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
mkdir -p "src/memory"
cat > "./src/memory/extract.js" <<'VB_EOF'
import { getSettings, getProfile, getMessages } from '../storage/db.js'
import { completeChat } from '../ai/provider.js'
import { limitsFor, SAMPLING_DEFAULTS } from '../ai/local/models.js'
import { listMemories, addMemory, getCursor, setCursor, normText, KINDS } from './store.js'

const running = new Set()

// Pulls {summary, memories[]} out of a model reply, tolerating code fences and chatter around the JSON.
export function parseExtraction(raw) {
  const a = raw.indexOf('{'), b = raw.lastIndexOf('}')
  if (a < 0 || b <= a) throw new Error('The AI did not return memories in a readable format.')
  const j = JSON.parse(raw.slice(a, b + 1))
  const memories = (Array.isArray(j.memories) ? j.memories : [])
    .map((m) => (typeof m === 'string' ? { text: m, kind: 'fact' } : m))
    .filter((m) => m && typeof m.text === 'string' && m.text.trim().length > 2)
    .map((m) => ({ text: m.text.trim().slice(0, 400), kind: KINDS.includes(m.kind) && m.kind !== 'summary' ? m.kind : 'fact' }))
    .slice(0, 10)
  const summary = typeof j.summary === 'string' ? j.summary.trim().slice(0, 600) : ''
  return { summary, memories }
}

export async function pendingInfo(buddyId) {
  const cursor = await getCursor(buddyId)
  const msgs = (await getMessages(buddyId)).filter((m) => m.ts > cursor)
  return { msgs, userCount: msgs.filter((m) => m.role === 'user').length, lastTs: msgs.length ? msgs[msgs.length - 1].ts : 0 }
}

function buildPrompt({ buddy, profile, existing, msgs }) {
  const who = profile?.name?.trim() || 'the user'
  const system = `You maintain the long-term memory of a companion character named ${buddy.name}. Read the conversation and decide what ${buddy.name} should remember about ${who} for future conversations.

Rules:
- Keep only durable or useful things: people and pets (with names), birthdays and dates, plans, ongoing projects, preferences, important events, and ongoing situations.
- Write each memory as one short, specific statement in the third person, e.g. "${who} has a cat named Pickles." Maximum about 25 words each.
- Do not repeat anything already remembered. If something changed, write the new fact.
- Never store passwords, payment card numbers, government ID numbers, or exact street addresses.
- Zero memories is fine if nothing is worth keeping. Never more than 8.
- Also write a summary of 1-2 sentences saying what was discussed and any open threads worth following up on.
- kind must be one of: fact, event, preference, project.

Reply with ONLY JSON, no other text, in this shape:
{"summary": "...", "memories": [{"text": "...", "kind": "fact"}]}

Already remembered (do not repeat):
${existing.length ? existing.map((m) => '- ' + m.text).join('\n') : '(nothing yet)'}`
  const transcript = msgs.map((m) => `${m.role === 'user' ? who : buddy.name}: ${m.text.slice(0, 800)}`).join('\n')
  return { system, messages: [{ role: 'user', content: `Conversation:\n${transcript}\n\nReturn the JSON now.` }] }
}

// opts: { force, minUserMsgs, quietMs }. Returns { status: 'ok'|'skipped'|'error', added, message }.
export async function extractNow(buddy, { force = false, minUserMsgs = 3, quietMs = 0 } = {}) {
  if (running.has(buddy.id)) return { status: 'skipped', added: 0, message: 'Already updating.' }
  running.add(buddy.id)
  try {
    const info = await pendingInfo(buddy.id)
    if (!info.userCount) return { status: 'skipped', added: 0, message: 'Nothing new to learn from yet.' }
    if (!force && info.userCount < minUserMsgs) return { status: 'skipped', added: 0, message: 'Not enough new messages yet.' }
    if (!force && quietMs && Date.now() - info.lastTs < quietMs) return { status: 'skipped', added: 0, message: 'Conversation still in progress.' }
    const s = await getSettings()
    const cfg = s.providers[s.activeProvider]
    const isLocal = s.activeProvider === 'local'
    if (isLocal ? !cfg?.model : !cfg?.apiKey) return { status: 'skipped', added: 0, message: isLocal ? 'Download an on-device model in Settings so your buddy can update their memories.' : 'Add an API key in Settings so your buddy can update their memories.' }

    const [profile, existingAll] = await Promise.all([getProfile(), listMemories(buddy.id)])
    const small = isLocal // small on-device models get a much shorter prompt
    const existing = existingAll.slice(0, small ? 20 : 60)
    const msgs = info.msgs.slice(small ? -14 : -60).map((m) => ({ ...m, text: m.text.slice(0, small ? 300 : 800) }))
    const { system, messages } = buildPrompt({ buddy, profile, existing, msgs })
    const raw = await completeChat({ provider: s.activeProvider, apiKey: cfg.apiKey, model: cfg.model, system, messages,
      sampling: { ...SAMPLING_DEFAULTS, temperature: 0.2, top_k: 20, repeat_penalty: 1.0, max_tokens: 700 } }) // notes need steady, complete JSON
    const { summary, memories } = parseExtraction(raw)

    const seen = new Set(existingAll.map((m) => normText(m.text)))
    const convId = `conv-${msgs[0].ts}`
    let added = 0
    for (const m of memories) {
      const key = normText(m.text)
      if (seen.has(key)) continue
      seen.add(key)
      await addMemory(buddy.id, { text: m.text, kind: m.kind, isNew: true, sourceConversationId: convId })
      added++
    }
    if (summary && !seen.has(normText(summary))) {
      await addMemory(buddy.id, { text: summary, kind: 'summary', isNew: true, sourceConversationId: convId, createdAt: msgs[msgs.length - 1].ts })
      added++
    }
    await setCursor(buddy.id, info.msgs[info.msgs.length - 1].ts)
    return { status: 'ok', added, message: added ? `Added ${added} new ${added === 1 ? 'memory' : 'memories'}.` : 'Nothing new worth remembering.' }
  } catch (e) {
    return { status: 'error', added: 0, message: e.message || 'Something went wrong.' }
  } finally {
    running.delete(buddy.id)
  }
}
VB_EOF
mkdir -p "src/memory"
cat > "./src/memory/retrieve.js" <<'VB_EOF'
// Memory retrieval v1: lexical (BM25-style) scoring. No model download needed.
// pickMemories() is the single entry point, so embedding-based scoring can be added later without touching callers.
const STOP = new Set('a an the and or but if then so of to in on at by for with about as is are was were be been am do does did have has had i me my you your we our they them their he she it its this that these those not no yes just really very can will would should could what when where who how why from up out over again into than too also'.split(' '))

export function tokenize(text) {
  const words = (text.toLowerCase().match(/[\p{L}\p{N}]+/gu) || []).filter((w) => w.length > 1 && !STOP.has(w))
  return words.map((w) => {
    if (w.length > 5 && w.endsWith('ing')) return w.slice(0, -3)
    if (w.length > 4 && w.endsWith('ed')) return w.slice(0, -2)
    if (w.length > 3 && w.endsWith('s')) return w.slice(0, -1)
    return w
  })
}

export function pickMemories(memories, queryText, { max = 12, charBudget = 2500, allBelow = 15 } = {}) {
  const active = memories.filter((m) => m.status !== 'archived')
  let ranked
  if (active.length <= allBelow) {
    ranked = [...active].sort((a, b) => Number(b.pinned) - Number(a.pinned) || (b.createdAt || 0) - (a.createdAt || 0))
  } else {
    const docs = active.map((m) => ({ m, toks: tokenize(m.text) }))
    const df = new Map()
    for (const d of docs) for (const t of new Set(d.toks)) df.set(t, (df.get(t) || 0) + 1)
    const q = new Set(tokenize(queryText))
    const N = docs.length
    const newest = Math.max(...active.map((m) => m.createdAt || 0)) || 1
    const scored = docs.map(({ m, toks }) => {
      let s = 0
      for (const t of new Set(toks)) if (q.has(t)) s += Math.log(1 + (N - df.get(t) + 0.5) / (df.get(t) + 0.5))
      s /= Math.sqrt(Math.max(toks.length, 4)) / 2
      s += 0.15 * ((m.createdAt || 0) / newest)          // gentle recency nudge
      if (m.kind === 'summary') s *= 0.6                 // summaries rank below specific facts
      return { m, s: s + (m.pinned ? 100 : 0) }
    })
    ranked = scored.sort((a, b) => b.s - a.s).map((x) => x.m)
  }
  const out = []
  let used = 0
  for (const m of ranked) {
    if (out.length >= max) break
    if (used + m.text.length > charBudget && out.length) break
    out.push(m); used += m.text.length
  }
  return out
}
VB_EOF
mkdir -p "src/memory"
cat > "./src/memory/store.js" <<'VB_EOF'
import { db, getAll, put, get, newId, getSettings, putSettings } from '../storage/db.js'

export const KINDS = ['fact', 'event', 'preference', 'project', 'summary']

export async function listMemories(buddyId) {
  const rows = (await (await db()).getAllFromIndex('memory', 'byBuddy', buddyId)) || []
  return rows.sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0))
}

export async function addMemory(buddyId, { text, kind = 'fact', status = 'active', pinned = false, isNew = false, sourceConversationId = null, createdAt }) {
  const now = Date.now()
  const m = { id: newId(), buddyId, text: text.trim(), kind: KINDS.includes(kind) ? kind : 'fact', status, pinned, isNew, sourceConversationId, createdAt: createdAt || now, updatedAt: now }
  await put('memory', m)
  return m
}
export async function updateMemory(id, patch) {
  const m = await get('memory', id); if (!m) return null
  const next = { ...m, ...patch, updatedAt: Date.now() }
  await put('memory', next); return next
}
export async function deleteMemories(ids) {
  const d = await db()
  for (const id of ids) await d.delete('memory', id)
}
export async function clearNewFlags(buddyId) {
  for (const m of await listMemories(buddyId)) if (m.isNew) await put('memory', { ...m, isNew: false })
}

// Extraction cursor per buddy: timestamp of the last message already processed.
export async function getCursor(buddyId) { return ((await getSettings()).memoryCursors || {})[buddyId] || 0 }
export async function setCursor(buddyId, ts) {
  const s = await getSettings()
  await putSettings({ memoryCursors: { ...(s.memoryCursors || {}), [buddyId]: ts } })
}

export const normText = (t) => t.toLowerCase().replace(/[^\p{L}\p{N}\s]/gu, '').replace(/\s+/g, ' ').trim()
VB_EOF
mkdir -p "src/screens"
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
mkdir -p "src/screens"
cat > "./src/screens/BuddyEditor.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { get, put, getBuddies, getProfile, getSettings, putSettings, deleteBuddy, getMessages, newId } from '../storage/db.js'
import { toAvatarBlob } from '../storage/image.js'
import { loadDraft, saveDraft, clearDraft, blobToDataUrl, dataUrlToBlob } from '../state/draft.js'
import Avatar from '../components/Avatar.jsx'
import Field from '../components/Field.jsx'

const EMPTY = { name: '', gender: 'f', personality: '', family: '', role: '', style: '', avatar: null }

export default function BuddyEditor() {
  const nav = useNavigate()
  const [params] = useSearchParams()
  const id = params.get('id')
  const draftKey = `buddy:${id || 'new'}`
  const [b, setB] = useState(EMPTY)
  const [dirty, setDirty] = useState(false)
  const [hasChat, setHasChat] = useState(false)
  const [blocked, setBlocked] = useState(false)
  const [ready, setReady] = useState(false)
  const [restored, setRestored] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const file = useRef()

  useEffect(() => { (async () => {
    let base = EMPTY
    if (id) {
      const found = await get('buddy', id)
      if (found) { base = found; setHasChat((await getMessages(id)).length > 0) }
    } else {
      const [all, s] = await Promise.all([getBuddies(), getSettings()])
      if (all.length >= 1 && !s.premium) setBlocked(true)
    }
    const d = loadDraft(draftKey)
    if (d) {
      const { avatarData, ...fields } = d
      base = { ...base, ...fields, avatar: avatarData ? await dataUrlToBlob(avatarData) : base.avatar }
      setDirty(true); setRestored(true)
    }
    setB(base); setReady(true)
  })() }, [id])

  // Autosave the draft whenever the user has changed something.
  useEffect(() => {
    if (!ready || !dirty) return
    let cancelled = false
    ;(async () => {
      const { avatar, ...fields } = b
      const avatarData = avatar ? await blobToDataUrl(avatar) : null
      if (!cancelled) saveDraft(draftKey, { ...fields, avatarData })
    })()
    return () => { cancelled = true }
  }, [b, dirty, ready])

  const update = (patch) => { setB((cur) => ({ ...cur, ...patch })); setDirty(true); setError('') }
  const set = (k) => (e) => update({ [k]: e.target.value })

  async function save() {
    if (saving) return
    if (!b.name.trim()) { setError('Please give your buddy a name first.'); return }
    setSaving(true); setError('')
    try {
      const buddy = { ...b, name: b.name.trim(), id: b.id || newId(), createdAt: b.createdAt || Date.now(), status: b.status || 'awake' }
      await put('buddy', buddy)
      await putSettings({ activeBuddyId: buddy.id })
      clearDraft(draftKey)
      // First-time setup continues to the user profile (screen 11); edits go back to settings.
      nav((await getProfile()) ? '/settings' : '/profile', { replace: true })
    } catch (e) {
      setSaving(false)
      setError(`Couldn't save: ${e.message || 'storage error'}. Your text is safe in this form; try again, or export a backup from Settings.`)
    }
  }
  async function remove() {
    if (!confirm(`Say goodbye to ${b.name}? Their messages and memories will be deleted from this device. This can't be undone.`)) return
    clearDraft(draftKey); await deleteBuddy(b.id); nav('/settings', { replace: true })
  }
  async function pickPhoto(e) {
    const f = e.target.files[0]; if (!f) return
    try { update({ avatar: await toAvatarBlob(f) }) } catch { setError("Couldn't read that image.") }
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
      {restored && <p className="notice">We restored what you were typing. Press Save to keep it.</p>}
      <div className="avatar-pick">
        <Avatar blob={b.avatar} name={b.name || '?'} size={96} />
        <button onClick={() => file.current.click()}>{b.avatar ? 'Change photo' : 'Add photo'}</button>
        <input ref={file} type="file" accept="image/*" hidden onChange={pickPhoto} />
        <p className="muted small">Pictures only. Your buddy's photo stays on this device.</p>
      </div>

      <Field label="Name"><input value={b.name} onChange={set('name')} placeholder="What do you call your buddy?" /></Field>
      <Field label="Voice" hint="Sets your buddy's default voice for calls.">
        <select value={b.gender} onChange={set('gender')}><option value="f">Female</option><option value="m">Male</option></select>
      </Field>
      <Field label="Who are they?" hint="Please describe your buddy: hobbies, interests, work, goals, culture or ethnicity, where they were born and live now, kids, exes, religion, and so on.">
        <textarea rows={6} value={b.personality} onChange={set('personality')} />
      </Field>
      <Field label="People they know" hint="Family and others your buddy knows. Example: You have a sister you're close to named Margret, an accountant in New York.">
        <textarea rows={3} value={b.family} onChange={set('family')} />
      </Field>
      <Field label="Their role in your life" hint="What are they to you? Friend, mentor, partner, accountability buddy, practice partner for interviews...">
        <textarea rows={2} value={b.role} onChange={set('role')} />
      </Field>
      <Field label="How they talk" hint="Their style, common phrases, how often they joke, how formal they are...">
        <textarea rows={3} value={b.style} onChange={set('style')} />
      </Field>

      <div className="savebar">
        {error && <p className="error">{error}</p>}
        <button className="btn" disabled={saving} onClick={save}>{saving ? 'Saving...' : 'Save'}</button>
      </div>

      {hasChat && (
        <section className="after">
          <Link className="plain-btn" to={`/memories?id=${b.id}`}>Edit memories</Link>
          <p className="muted small">See, fix, add, or remove the things {b.name || 'your buddy'} remembers about you and your conversations.</p>
        </section>
      )}

      {b.id && (
        <section className="goodbye">
          <p className="muted small">Saying goodbye to {b.name}? Deleting a buddy also deletes all of their messages and memories from this device. If you might want them back, export a backup from Settings first.</p>
          <button className="quiet" onClick={remove}>Delete {b.name}</button>
        </section>
      )}
    </div>
  )
}
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/Chat.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { getSettings, putSettings, getProfile, getMessages, put, newId, resolveActiveBuddy } from '../storage/db.js'
import { streamChat, PROVIDERS } from '../ai/provider.js'
import { buildSystem, buildContext } from '../ai/promptBuilder.js'
import { preSendCheck, EXIT_TOKEN } from '../ai/safety.js'
import { limitsFor, modelLabel, DEMO_MODEL } from '../ai/local/models.js'
import ReplyStatus from '../components/ReplyStatus.jsx'
import { listInstalled, downloadModel, subscribe, getStatus } from '../ai/local/engine.js'
import { checkDevice, UNSUPPORTED_MESSAGE } from '../device/capability.js'
import { DEMO_BUDDY, buildDemoSystem } from '../demo/demoBuddy.js'
import Avatar from '../components/Avatar.jsx'
import SelectBuddy from '../components/SelectBuddy.jsx'
import { listMemories } from '../memory/store.js'
import { pickMemories } from '../memory/retrieve.js'
import { extractNow } from '../memory/extract.js'

const CLOUD = ['openai', 'anthropic', 'gemini', 'openrouter']

// Works out how this chat can actually run right now.
async function planFor(s, demo) {
  if (!demo && s.activeProvider !== 'local') {
    return s.providers[s.activeProvider]?.apiKey ? { mode: 'cloud', provider: s.activeProvider } : { mode: 'need-key' }
  }
  const device = await checkDevice()
  const installed = device.supported ? await listInstalled().catch(() => []) : []
  const preferred = s.providers.local?.model
  const modelUrl = installed.find((m) => m.url === preferred)?.url || installed[0]?.url || null
  if (modelUrl) return { mode: 'local', modelUrl }
  if (!device.supported) {
    const key = [s.activeProvider, ...CLOUD].find((p) => CLOUD.includes(p) && s.providers[p]?.apiKey)
    return key ? { mode: 'cloud', provider: key } : { mode: 'unsupported' }
  }
  return demo ? { mode: 'download' } : { mode: 'need-model' }
}

export default function Chat() {
  const nav = useNavigate()
  const [params] = useSearchParams()
  const isDemo = params.get('b') === 'demo'
  const [state, setState] = useState(null) // { buddy, buddies, needsPick, settings }
  const [plan, setPlan] = useState(null)
  const [msgs, setMsgs] = useState([])
  const [input, setInput] = useState('')
  const [live, setLive] = useState(null)   // text of the reply being streamed (null = none)
  const [busy, setBusy] = useState(false)
  const [note, setNote] = useState('')
  const [picking, setPicking] = useState(false)
  const [dl, setDl] = useState(null)       // demo model download progress
  const [engine, setEngine] = useState(getStatus())
  const abort = useRef(null)
  const dlAbort = useRef(null)
  const end = useRef(null)
  const buddyRef = useRef(null)
  const stopped = useRef(false)

  async function load() {
    const settings = await getSettings()
    if (isDemo) {
      const { buddies } = await resolveActiveBuddy()
      setState({ buddy: DEMO_BUDDY, buddies, settings }); setMsgs(await getMessages(DEMO_BUDDY.id)); setPlan(await planFor(settings, true))
      return
    }
    const r = await resolveActiveBuddy()
    setState({ ...r, settings })
    if (r.buddy) {
      setMsgs(await getMessages(r.buddy.id)); setPlan(await planFor(settings, false))
      extractNow(r.buddy, { minUserMsgs: 3, quietMs: 30 * 60 * 1000 })
    } else if (!r.buddies.length) nav('/buddy/edit', { replace: true })
  }
  useEffect(() => { load(); return () => { abort.current?.abort(); dlAbort.current?.abort() } }, [isDemo])
  useEffect(() => subscribe(setEngine), [])
  useEffect(() => { end.current?.scrollIntoView({ block: 'end' }) }, [msgs, live, note])
  useEffect(() => { buddyRef.current = isDemo ? null : state?.buddy || null }, [state, isDemo])
  // Leaving the app/tab is a natural end of conversation: let the buddy update their memories.
  useEffect(() => {
    const onHide = () => { if (document.visibilityState === 'hidden' && buddyRef.current) extractNow(buddyRef.current, { minUserMsgs: 3 }) }
    document.addEventListener('visibilitychange', onHide)
    return () => document.removeEventListener('visibilitychange', onHide)
  }, [])

  if (!state) return null
  const { buddy, buddies, settings } = state
  if (!buddy) return state.needsPick
    ? <SelectBuddy buddies={buddies} onPick={async (b) => { await putSettings({ activeBuddyId: b.id }); load() }} />
    : null

  const ready = plan && (plan.mode === 'local' || plan.mode === 'cloud')

  async function getDemoModel() {
    setNote(''); dlAbort.current = new AbortController(); setDl({ loaded: 0, total: 0 })
    try {
      await downloadModel(DEMO_MODEL.url, { signal: dlAbort.current.signal, onProgress: (loaded, total) => setDl({ loaded, total }) })
      const s = await getSettings()
      if (!s.providers.local?.model) await putSettings({ providers: { ...s.providers, local: { ...s.providers.local, model: DEMO_MODEL.url } } })
      setPlan(await planFor(await getSettings(), true))
    } catch (e) { if (e.name !== 'AbortError') setNote(e.message) }
    setDl(null)
  }

  async function send() {
    const text = input.trim()
    if (!text || busy) return
    const s = await getSettings()
    const pl = await planFor(s, isDemo)
    setPlan(pl)
    if (pl.mode !== 'local' && pl.mode !== 'cloud') return // the banner explains what to do

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

    const provider = pl.mode === 'local' ? 'local' : pl.provider
    const cfg = s.providers[provider] || {}
    const model = pl.mode === 'local' ? pl.modelUrl : cfg.model
    const lim = limitsFor(provider)
    setBusy(true); setLive(''); stopped.current = false
    abort.current = new AbortController()
    let acc = ''
    try {
      let system
      if (isDemo) system = buildDemoSystem(pl.mode === 'local' ? modelLabel(pl.modelUrl) : 'a cloud AI model')
      else {
        const profile = await getProfile()
        const recent = history.slice(-3).map((m) => m.text).join(' ')
        const memories = pickMemories(await listMemories(buddy.id), recent, { charBudget: lim.memoryChars, max: provider === 'local' ? 6 : 12 })
        system = buildSystem({ buddy, profile, memories, compact: provider === 'local' })
      }
      const ctx = buildContext(history.map((m) => ({ role: m.role === 'user' ? 'user' : 'assistant', text: m.text })), lim.historyChars)
      for await (const chunk of streamChat({ provider, apiKey: cfg.apiKey, model, system, messages: ctx, signal: abort.current.signal, sampling: s.sampling })) {
        acc += chunk; setLive(acc)
      }
    } catch (e) {
      if (e.name !== 'AbortError') setNote(e.message)
    }
    let final = acc.trim()
    if (final.startsWith(EXIT_TOKEN)) final = s.exitMessage
    if (final) {
      const m = { id: newId(), buddyId: buddy.id, role: 'buddy', text: final, ts: Date.now(), modelUsed: `${provider}:${modelLabel(model)}`, source: 'text' }
      await put('message', m); setMsgs([...history, m])
      if (!isDemo) extractNow(buddy, { minUserMsgs: 8 }) // background; never blocks the chat
    }
    else if (!acc.trim() && !stopped.current) setNote((n) => n || "No reply came back that time. Try sending your message again.")
    setLive(null); setBusy(false)
  }

  // While the streamed text could still turn into the exit token, keep showing the typing dots.
  const hideLive = live !== null && (live.trim() === '' || EXIT_TOKEN.startsWith(live.trim()) || live.trim().startsWith(EXIT_TOKEN))
  const sub = isDemo ? 'Demo · runs on your device' : plan?.mode === 'local' ? 'on this device' : PROVIDERS[plan?.provider || settings.activeProvider]?.label ? `via ${PROVIDERS[plan?.provider || settings.activeProvider].label}` : ''
  const pct = dl && dl.total ? Math.round((dl.loaded / dl.total) * 100) : 0

  return (
    <div className="chat">
      <div className="chat-head">
        <Avatar blob={buddy.avatar} name={buddy.name} size={36} />
        <div><strong>{buddy.name}</strong><div className="small muted">{sub}</div></div>
        {!isDemo && buddies.length > 1 && <button className="plain" onClick={() => setPicking(true)}>Switch</button>}
        {isDemo && buddies.length === 0 && <Link className="plain" to="/buddy/edit">Create your own</Link>}
      </div>
      <div className="chat-list">
        {msgs.length === 0 && live === null && ready && <p className="muted center-text">Say hi to {buddy.name}.</p>}
        {msgs.map((m) => <div key={m.id} className={`bubble ${m.role === 'user' ? 'me' : 'them'}`}>{m.text}</div>)}
        {live !== null && (hideLive
          ? <div className="bubble them typing"><i /><i /><i /></div>
          : <div className="bubble them">{live}</div>)}
        {busy && hideLive && (engine.stage === 'loading' || engine.stage === 'thinking') && <ReplyStatus stage={engine.stage} since={engine.since} />}
        {note && <div className="note">{note}</div>}
        <div ref={end} />
      </div>

      {plan && plan.mode === 'download' && (
        <div className="banner">
          <strong>Get Demo Buddy ready</strong>
          <p className="small muted">Demo Buddy runs on your phone, so it's free and private. This is a one-time download of about {DEMO_MODEL.sizeMB} MB. Wi-Fi is best.</p>
          {dl ? (
            <>
              <div className="small">{dl.total ? `${pct}% (${Math.round(dl.loaded / 1e6)} of ${Math.round(dl.total / 1e6)} MB)` : 'Starting...'}</div>
              <div className="bar"><div style={{ width: `${pct}%` }} /></div>
              <button className="quiet" onClick={() => dlAbort.current?.abort()}>Cancel</button>
            </>
          ) : <button className="btn" onClick={getDemoModel}>Download and start</button>}
        </div>
      )}
      {plan && plan.mode === 'unsupported' && (
        <div className="banner"><p className="small">{UNSUPPORTED_MESSAGE}</p><Link className="plain-btn" to="/premium">See premium</Link></div>
      )}
      {plan && plan.mode === 'need-model' && (
        <div className="banner"><p className="small">Your buddy needs an on-device model to think with. It's a one-time download.</p><Link className="plain-btn" to="/settings">Choose a model</Link></div>
      )}
      {plan && plan.mode === 'need-key' && (
        <div className="banner"><p className="small">Add your API key in Settings to chat with a cloud AI, or switch to an on-device model.</p><Link className="plain-btn" to="/settings">Open Settings</Link></div>
      )}

      <div className="composer">
        <textarea rows={1} value={input} placeholder="Message" disabled={!ready} onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && !e.shiftKey && window.matchMedia('(pointer: fine)').matches) { e.preventDefault(); send() } }} />
        <button className={`send ${busy ? 'stop' : ''}`} aria-label={busy ? 'Stop' : 'Send'} disabled={!busy && (!ready || !input.trim())}
          onClick={busy ? () => { stopped.current = true; abort.current?.abort() } : send}>{busy ? '■' : '↑'}</button>
      </div>
      {picking && <SelectBuddy buddies={buddies} onClose={() => setPicking(false)}
        onPick={async (b) => { await putSettings({ activeBuddyId: b.id }); setPicking(false); load() }} />}
    </div>
  )
}
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/Demo.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { getBuddies } from '../storage/db.js'

export default function Demo() {
  const [none, setNone] = useState(null)
  useEffect(() => { getBuddies().then((b) => setNone(b.length === 0)) }, [])
  return (
    <div className="screen">
      <h2>Meet Demo Buddy</h2>
      <p className="muted">Try Virtual Buddy right now, with nothing to set up. Demo Buddy is an AI that is honest about being an AI. It runs on your own device, so it's free and private.</p>
      <div className="stack">
        <Link className="btn" to="/chat?b=demo">Text Demo Buddy</Link>
        <Link className="btn alt" to="/call/outgoing?b=demo">Call Demo Buddy <span className="chip">soon</span></Link>
        <Link className="btn alt" to="/call/incoming?b=demo">Demo Buddy calls me <span className="chip">soon</span></Link>
        {none && <Link className="btn alt" to="/buddy/edit">Create new buddy</Link>}
      </div>
      <section className="prose" style={{ marginTop: 28 }}>
        <h2>About Virtual Buddy</h2>
        <p>Virtual Buddy is an AI companion that can be whoever you need: a friend, a mentor, an accountability partner, or a practice partner for a hard conversation. You decide who your buddy is, how they talk, and what they remember.</p>
        <p>Talk by text or by voice. Your buddy remembers the things that matter to you, and you can view and edit those memories any time. AI models can run directly on your device, so your conversations never have to leave it.</p>
        <p className="muted">Virtual Buddy is an AI, not a person, and is not a substitute for professional or emergency help.</p>
      </section>
    </div>
  )
}
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/EditMemories.jsx" <<'VB_EOF'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { todayLocal } from '../version.js'
import { get, getBuddies, resolveActiveBuddy, downloadText } from '../storage/db.js'
import { KINDS, listMemories, addMemory, updateMemory, deleteMemories, clearNewFlags, normText } from '../memory/store.js'
import { extractNow, pendingInfo } from '../memory/extract.js'

const KIND_LABEL = { fact: 'Fact', event: 'Event', preference: 'Preference', project: 'Project', summary: 'Conversation summary' }

export default function EditMemories() {
  const [params] = useSearchParams()
  const [buddy, setBuddy] = useState(null)
  const [mems, setMems] = useState([])
  const [tab, setTab] = useState('active')
  const [q, setQ] = useState('')
  const [sel, setSel] = useState(new Set())
  const [editing, setEditing] = useState(null) // { id, text }
  const [draft, setDraft] = useState({ text: '', kind: 'fact' })
  const [adding, setAdding] = useState(false)
  const [status, setStatus] = useState('')
  const [busy, setBusy] = useState(false)
  const [pending, setPending] = useState(0)
  const file = useRef()

  const reload = async (b = buddy) => { if (b) { setMems(await listMemories(b.id)); setPending((await pendingInfo(b.id)).userCount) } }
  useEffect(() => { (async () => {
    const id = params.get('id')
    const b = (id && (await get('buddy', id))) || (await resolveActiveBuddy()).buddy || (await getBuddies())[0]
    setBuddy(b || null)
    if (b) await reload(b)
  })() }, [])
  // "New" badges stay visible while you look, then clear: after a few seconds, on leaving, or when the tab closes.
  useEffect(() => {
    if (!buddy) return
    const clear = () => clearNewFlags(buddy.id)
    const t = setTimeout(clear, 4000)
    window.addEventListener('pagehide', clear)
    return () => { clearTimeout(t); window.removeEventListener('pagehide', clear); clear() }
  }, [buddy])

  const list = useMemo(() => {
    const f = normText(q)
    return mems.filter((m) => (tab === 'archived' ? m.status === 'archived' : m.status !== 'archived') && (!f || normText(m.text).includes(f)))
      .sort((a, b) => Number(b.pinned) - Number(a.pinned) || (b.createdAt || 0) - (a.createdAt || 0))
  }, [mems, tab, q])
  const counts = { active: mems.filter((m) => m.status !== 'archived').length, archived: mems.filter((m) => m.status === 'archived').length }

  if (!buddy) return <div className="screen center"><p className="muted">Create a buddy first, and their memories will show up here.</p></div>

  const toggle = (id) => setSel((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n })
  const act = async (fn) => { await fn(); await reload() }

  async function addManual() {
    if (draft.text.trim().length < 3) return
    await act(() => addMemory(buddy.id, { text: draft.text, kind: draft.kind }))
    setDraft({ text: '', kind: 'fact' }); setAdding(false)
  }
  async function saveEdit() {
    if (editing.text.trim().length < 3) return
    await act(() => updateMemory(editing.id, { text: editing.text.trim(), isNew: false })); setEditing(null)
  }
  async function bulk(kind) {
    const ids = [...sel]; if (!ids.length) return
    if (kind === 'delete' && !confirm(`Are you sure? ${ids.length} ${ids.length === 1 ? 'memory' : 'memories'} will be deleted for good.`)) return
    await act(async () => {
      if (kind === 'delete') await deleteMemories(ids)
      else for (const id of ids) await updateMemory(id, { status: kind === 'archive' ? 'archived' : 'active' })
    })
    setSel(new Set())
  }
  async function updateFromChats() {
    setBusy(true); setStatus('')
    const r = await extractNow(buddy, { force: true })
    setStatus(r.message); setBusy(false); await reload()
  }
  async function download() {
    const out = { app: 'virtual-buddy', type: 'memories', buddy: buddy.name, exportedAt: new Date().toISOString(),
      memories: mems.map(({ text, kind, status, pinned, createdAt }) => ({ text, kind, status, pinned, createdAt })) }
    downloadText(JSON.stringify(out, null, 2), `${buddy.name}-memories-${todayLocal()}.json`, 'application/json')
  }
  async function importFile(e) {
    const f = e.target.files[0]; e.target.value = ''; if (!f) return
    try {
      const j = JSON.parse(await f.text())
      const rows = Array.isArray(j) ? j : j.memories
      if (!Array.isArray(rows)) throw new Error('bad file')
      const have = new Set(mems.map((m) => normText(m.text)))
      let n = 0
      for (const r of rows) {
        if (!r?.text || have.has(normText(r.text))) continue
        have.add(normText(r.text)); n++
        await addMemory(buddy.id, { text: r.text, kind: r.kind, status: r.status === 'archived' ? 'archived' : 'active', pinned: !!r.pinned, createdAt: r.createdAt })
      }
      setStatus(`Imported ${n} ${n === 1 ? 'memory' : 'memories'}.`); await reload()
    } catch { setStatus("That doesn't look like a memories file.") }
  }

  return (
    <div className="screen">
      <p className="muted">Everything {buddy.name} remembers about you. Fix mistakes, add things you want them to know, or let go of what no longer matters.</p>

      <div className="row gap-b">
        <button onClick={() => setAdding(!adding)}>Add a memory</button>
        <button disabled={busy} onClick={updateFromChats}>{busy ? 'Thinking...' : 'Update from recent chats'}</button>
      </div>
      <p className="muted small">{buddy.name} updates their memories on their own after longer chats{pending ? ` (${pending} new ${pending === 1 ? 'message' : 'messages'} since the last update)` : ''}. You can also do it now.</p>
      {status && <p className="notice">{status}</p>}

      {adding && (
        <section className="card">
          <textarea rows={3} value={draft.text} onChange={(e) => setDraft({ ...draft, text: e.target.value })} placeholder={`e.g. ${buddy.name} should know that my birthday is in May.`} />
          <div className="row" style={{ marginTop: 8 }}>
            <select style={{ width: 'auto' }} value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value })}>
              {KINDS.filter((k) => k !== 'summary').map((k) => <option key={k} value={k}>{KIND_LABEL[k]}</option>)}
            </select>
            <button className="on" onClick={addManual}>Add</button>
            <button onClick={() => setAdding(false)}>Cancel</button>
          </div>
        </section>
      )}

      <div className="tabs">
        <button className={tab === 'active' ? 'on' : ''} onClick={() => { setTab('active'); setSel(new Set()) }}>Remembered ({counts.active})</button>
        <button className={tab === 'archived' ? 'on' : ''} onClick={() => { setTab('archived'); setSel(new Set()) }}>Set aside ({counts.archived})</button>
      </div>
      {tab === 'archived' && <p className="muted small">Set-aside memories are kept but not used in conversations, until you restore them.</p>}
      <input type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search memories" style={{ marginBottom: 12 }} />

      {list.length === 0 && <p className="muted center-text">{mems.length ? 'Nothing matches.' : `${buddy.name} hasn't made any memories yet. Chat for a while, or add one yourself.`}</p>}
      {list.map((m) => (
        <div key={m.id} className={`mem ${sel.has(m.id) ? 'sel' : ''}`}>
          <label className="mem-check"><input type="checkbox" checked={sel.has(m.id)} onChange={() => toggle(m.id)} aria-label="Select" /></label>
          <div className="mem-body">
            <div className="chips">
              <span className="chip">{KIND_LABEL[m.kind] || 'Fact'}</span>
              {m.isNew && <span className="chip new">New</span>}
              {m.pinned && <span className="chip pin">Pinned</span>}
              <span className="small muted">{new Date(m.createdAt).toLocaleDateString()}</span>
            </div>
            {editing?.id === m.id ? (
              <>
                <textarea rows={3} value={editing.text} onChange={(e) => setEditing({ ...editing, text: e.target.value })} />
                <div className="row" style={{ marginTop: 8 }}><button className="on" onClick={saveEdit}>Save</button><button onClick={() => setEditing(null)}>Cancel</button></div>
              </>
            ) : (
              <>
                <p className="mem-text">{m.text}</p>
                <div className="mem-actions">
                  <button className="link" onClick={() => setEditing({ id: m.id, text: m.text })}>Edit</button>
                  <button className="link" onClick={() => act(() => updateMemory(m.id, { pinned: !m.pinned }))}>{m.pinned ? 'Unpin' : 'Pin'}</button>
                  <button className="link" onClick={() => act(() => updateMemory(m.id, { status: m.status === 'archived' ? 'active' : 'archived' }))}>{m.status === 'archived' ? 'Restore' : 'Set aside'}</button>
                </div>
              </>
            )}
          </div>
        </div>
      ))}

      {sel.size > 0 && (
        <div className="savebar bulkbar">
          <span>{sel.size} selected</span>
          <div className="row">
            <button onClick={() => bulk(tab === 'archived' ? 'restore' : 'archive')}>{tab === 'archived' ? 'Restore' : 'Set aside'}</button>
            <button className="quiet" onClick={() => bulk('delete')}>Delete…</button>
            <button className="link" onClick={() => setSel(new Set())}>Clear</button>
          </div>
        </div>
      )}

      <section className="card" style={{ marginTop: 28 }}>
        <h2>Backup</h2>
        <p className="muted small">Download these memories as a file you can keep, or bring memories back from one. They're also included in the full backup in Settings.</p>
        <div className="row">
          <button onClick={download}>Download memories</button>
          <button onClick={() => file.current.click()}>Import memories</button>
        </div>
        <input ref={file} type="file" accept=".json,application/json" hidden onChange={importFile} />
      </section>
    </div>
  )
}
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/Help.jsx" <<'VB_EOF'
export default function Help() {
  return (
    <div className="screen prose">
      <h2>Getting started</h2>
      <ol>
        <li>Open <strong>Settings</strong> and create your buddy, then fill in your own profile.</li>
        <li>Choose how your buddy thinks: <strong>On this device</strong> (free and private; download a model once) or a cloud provider (paste your own API key).</li>
        <li>Open <strong>Messages</strong> and say hi.</li>
      </ol>
      <h2>Where is my data?</h2>
      <p>Your buddies, messages and settings are stored on this device. Clearing your browser's site data erases them, so use <strong>Settings → Export backup</strong> regularly. To move to a new phone, export a backup and import it there.</p>
      <h2>On-device AI</h2>
      <p>On-device models run on your phone, so your conversations don't leave it. Smaller models are faster and fit more phones; bigger ones sound smarter. Models are large downloads (a few hundred megabytes up to about a gigabyte), so use Wi-Fi if you can. They stay on this device and are not part of backups. On some iPhones the first load also fetches a small compatibility file, so an internet connection may be needed then.</p>
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
mkdir -p "src/screens"
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
mkdir -p "src/screens"
cat > "./src/screens/Placeholders.jsx" <<'VB_EOF'
// Screens built in later milestones. Replace each export with a real file as it is built.
const P = (name, milestone) => () => (
  <div className="screen center"><h2>{name}</h2><p className="muted">Coming in {milestone}.</p></div>
)
export const SignIn = P('Sign in / Sign up', 'M7')

export const IncomingCall = P('Incoming call', 'M6')
export const OutgoingCall = P('Calling...', 'M6')
export const Splash = P('Home', 'M6')
export const Premium = P('Premium', 'M8')
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/Settings.jsx" <<'VB_EOF'
import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getSettings, putSettings, getBuddies } from '../storage/db.js'
import { exportBundle, importBundle, downloadBlob } from '../storage/bundle.js'
import { THEMES, setTheme } from '../state/theme.js'
import { PROVIDERS } from '../ai/provider.js'
import SelectBuddy from '../components/SelectBuddy.jsx'
import { APP_VERSION, todayLocal } from '../version.js'
import AdvancedControls from '../components/AdvancedControls.jsx'
import LocalModelPanel from '../components/LocalModelPanel.jsx'

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
  async function doExport() {
    const b = buddies.find((x) => x.id === s.activeBuddyId) || buddies[0]
    const who = (b?.name || 'buddy').replace(/[^\p{L}\p{N}]+/gu, '')
    downloadBlob(await exportBundle(), `myBuddy${todayLocal()}${who}.zip`) // .zip so phone file pickers let you choose it
    setMsg('Backup downloaded.'); refresh()
  }
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
          <Link className="plain-btn" to="/demo">Try Demo Buddy</Link>
        </div>
      </section>

      <section className="card">
        <h2>AI model</h2>
        <label>Provider
          <select value={prov} onChange={async (e) => setS(await putSettings({ activeProvider: e.target.value }))}>
            {Object.entries(PROVIDERS).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </label>
        {prov === 'local' ? (
          <LocalModelPanel settings={s} onChange={refresh} />
        ) : (
          <>
            <label>API key
              <input type="password" autoComplete="off" value={cfg.apiKey} placeholder={PROVIDERS[prov]?.keyHint} onChange={(e) => setCfg({ apiKey: e.target.value })} />
            </label>
            <label>Model
              <input value={cfg.model} onChange={(e) => setCfg({ model: e.target.value })} />
            </label>
            <p className="muted small">Your key is saved only on this device and is sent only to {PROVIDERS[prov]?.label}. You pay that provider directly for usage.</p>
          </>
        )}
      </section>

      <AdvancedControls settings={s} onChange={refresh} active={prov === 'local'} />

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
        <input ref={file} type="file" hidden onChange={(e) => { doImport(e, e.target.dataset.mode); e.target.value = '' }} />
        {msg && <p>{msg}</p>}
      </section>

      <p className="muted small center-text">Virtual Buddy v{APP_VERSION}</p>

      {picking && <SelectBuddy buddies={buddies} canCreate={canCreate} onClose={() => setPicking(false)}
        onCreate={() => nav('/buddy/edit')} onPick={(b) => nav(`/buddy/edit?id=${b.id}`)} />}
    </div>
  )
}
VB_EOF
mkdir -p "src/screens"
cat > "./src/screens/UserProfile.jsx" <<'VB_EOF'
import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { getProfile, saveProfile } from '../storage/db.js'
import { loadDraft, saveDraft, clearDraft } from '../state/draft.js'
import Field from '../components/Field.jsx'

const EMPTY = { name: '', nicknames: '', pronouns: '', family: '', pets: '', topics: '', about: '' }
const KEY = 'profile'

export default function UserProfile() {
  const nav = useNavigate()
  const [p, setP] = useState(EMPTY)
  const [ready, setReady] = useState(false)
  const [dirty, setDirty] = useState(false)
  const [restored, setRestored] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => { (async () => {
    let base = { ...EMPTY, ...((await getProfile()) || {}) }
    const d = loadDraft(KEY)
    if (d) { base = { ...base, ...d }; setDirty(true); setRestored(true) }
    setP(base); setReady(true)
  })() }, [])
  useEffect(() => { if (ready && dirty) saveDraft(KEY, p) }, [p, dirty, ready])

  const set = (k) => (e) => { setP({ ...p, [k]: e.target.value }); setDirty(true); setError('') }
  async function save() {
    if (saving) return
    setSaving(true)
    try { await saveProfile(p); clearDraft(KEY); nav('/settings', { replace: true }) }
    catch (e) { setSaving(false); setError(`Couldn't save: ${e.message || 'storage error'}. Your text is safe in this form; try again.`) }
  }
  if (!ready) return null
  return (
    <div className="screen">
      {restored && <p className="notice">We restored what you were typing. Press Save to keep it.</p>}
      <p className="muted">This helps your buddy avoid mix-ups. It stays on this device.</p>
      <Field label="Your name"><input value={p.name} onChange={set('name')} /></Field>
      <Field label="Nicknames you like" hint="Separate with commas."><input value={p.nicknames} onChange={set('nicknames')} /></Field>
      <Field label="Pronouns / gender"><input value={p.pronouns} onChange={set('pronouns')} /></Field>
      <Field label="Family" hint="Who should your buddy know about?"><textarea rows={3} value={p.family} onChange={set('family')} /></Field>
      <Field label="Pets and friends" hint="Names, and anything your buddy should remember about them."><textarea rows={3} value={p.pets} onChange={set('pets')} /></Field>
      <Field label="Topics you like to talk about"><textarea rows={2} value={p.topics} onChange={set('topics')} /></Field>
      <Field label="Anything else" hint="Work, hobbies, goals, things that worry you, things to avoid..."><textarea rows={4} value={p.about} onChange={set('about')} /></Field>
      <div className="savebar">
        {error && <p className="error">{error}</p>}
        <button className="btn" disabled={saving} onClick={save}>{saving ? 'Saving...' : 'Save'}</button>
      </div>
    </div>
  )
}
VB_EOF
mkdir -p "src/state"
cat > "./src/state/draft.js" <<'VB_EOF'
// Unsaved-form drafts, kept in localStorage so a reload or accidental navigation never loses typing.
const k = (key) => `vb-draft:${key}`
export function loadDraft(key) { try { return JSON.parse(localStorage.getItem(k(key))) } catch { return null } }
export function saveDraft(key, v) { try { localStorage.setItem(k(key), JSON.stringify(v)) } catch { /* storage full/blocked: ignore */ } }
export function clearDraft(key) { try { localStorage.removeItem(k(key)) } catch { /* ignore */ } }
export const blobToDataUrl = (blob) => new Promise((res) => { const r = new FileReader(); r.onload = () => res(r.result); r.readAsDataURL(blob) })
export const dataUrlToBlob = async (u) => (await fetch(u)).blob()
VB_EOF
mkdir -p "src/state"
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
mkdir -p "src/storage"
cat > "./src/storage/bundle.js" <<'VB_EOF'
import JSZip from 'jszip'
import { STORES, getAll, put, clearStore, putSettings, getSettings } from './db.js'

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
  zip.file('manifest.json', JSON.stringify({ version: BUNDLE_VERSION, createdAt: new Date().toISOString(), appVersion: '0.4.2' }, null, 2))
  for (const s of STORES) zip.file(`${s}.json`, JSON.stringify(clean(zip, s, await getAll(s))))
  const blob = await zip.generateAsync({ type: 'blob', compression: 'DEFLATE' })
  await putSettings({ lastBackupAt: new Date().toISOString() })
  return blob
}

export function downloadBlob(blob, name) {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob); a.download = name; a.style.display = 'none'
  document.body.appendChild(a); a.click() // attached to the page so mobile browsers keep the file name
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove() }, 5000)
}

// mode: 'merge' (keep existing, overwrite same ids) | 'replace' (wipe first)
export async function importBundle(file, mode = 'merge') {
  let zip
  try { zip = await JSZip.loadAsync(file) } catch { throw new Error("That file isn't a Virtual Buddy backup. Choose the myBuddy….zip file you exported.") }
  if (!zip.file('manifest.json')) throw new Error("That zip file isn't a Virtual Buddy backup (no manifest inside).")
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
        const cur = await getSettings()
        for (const p of Object.keys(r.providers || {})) r.providers[p].apiKey = cur.providers[p]?.apiKey || r.providers[p].apiKey || ''
      }
      await put(s, r)
    }
  }
}
VB_EOF
mkdir -p "src/storage"
cat > "./src/storage/db.js" <<'VB_EOF'
import { openDB } from 'idb'

export const STORES = ['buddy', 'userProfile', 'message', 'memory', 'schedule', 'settings']
const DEFAULT_SETTINGS = {
  id: 'main', theme: 'ice', splashFit: 'cover', buttonLayout: [],
  activeProvider: 'local',
  providers: {
    local: { apiKey: '', model: '' }, // model = URL of the installed on-device model in use
    openai: { apiKey: '', model: 'gpt-4o-mini' },
    anthropic: { apiKey: '', model: 'claude-haiku-4-5' },
    gemini: { apiKey: '', model: 'gemini-flash-latest' },
    openrouter: { apiKey: '', model: 'openrouter/auto' },
  },
  localModelRef: null, activeBuddyId: null, premium: false,
  exitMessage: "You seem to be having a bad day. Let's talk later when you're feeling more like yourself.",
  onboarded: false, lastBackupAt: null,
  sampling: null, // on-device advanced controls; null = app defaults
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
  if (providers.gemini.model === 'gemini-2.5-flash') providers.gemini.model = DEFAULT_SETTINGS.providers.gemini.model // retired default
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

export function downloadText(text, name, type = 'text/plain') {
  const a = document.createElement('a')
  a.href = URL.createObjectURL(new Blob([text], { type })); a.download = name; a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 5000)
}
VB_EOF
mkdir -p "src/storage"
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
mkdir -p "src"
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

/* ---- M2.1 fixes ---- */
[hidden] { display: none !important; }              /* author display rules were overriding the hidden attribute */
.field { display: block; margin: 0 0 18px; }
.field .lbl { display: block; font-size: .9rem; font-weight: 600; color: var(--text); }
.field .hint { display: block; margin-top: 6px; font-size: .8rem; line-height: 1.4; color: var(--muted); }
.notice { background: var(--card); border-radius: var(--radius); padding: 10px 14px; font-size: .85rem; color: var(--muted); }
.error { color: #ff8a95; font-size: .85rem; margin: 0 0 8px; }
.savebar { position: sticky; bottom: 0; margin: 8px -16px 0; padding: 10px 16px calc(10px + env(safe-area-inset-bottom, 0px)); background: var(--bg); border-top: 1px solid var(--card); }
.savebar .btn { width: 100%; }
.savebar .btn:disabled { opacity: .6; }
.after { margin-top: 28px; display: flex; flex-direction: column; gap: 8px; }
.after p { margin: 0; }
.goodbye { margin-top: 96px; padding: 20px 0 48px; border-top: 1px solid var(--card); }
.goodbye p { margin: 0 0 10px; line-height: 1.45; }
.quiet { background: none; border: 0; padding: 6px 0; color: var(--muted); font-size: .85rem; text-decoration: underline; cursor: pointer; }
.menu-back { position: fixed; inset: 0; z-index: 9; }
.menu { z-index: 11; }

/* ---- M3 memories ---- */
.row.gap-b { margin-bottom: 8px; }
.tabs { display: flex; gap: 8px; margin: 16px 0 10px; }
.tabs button { flex: 1; }
.mem { display: flex; gap: 10px; background: var(--card); border-radius: var(--radius); padding: 12px; margin-bottom: 10px; border: 1px solid transparent; }
.mem.sel { border-color: var(--accent); }
.mem-check { margin: 0; padding-top: 2px; }
.mem-check input { width: 20px; height: 20px; margin: 0; accent-color: var(--accent); }
.mem-body { flex: 1; min-width: 0; }
.mem-text { margin: 6px 0; line-height: 1.4; overflow-wrap: anywhere; }
.chips { display: flex; flex-wrap: wrap; align-items: center; gap: 6px; }
.chip { font-size: .7rem; padding: 2px 8px; border-radius: 999px; background: var(--bg); color: var(--muted); }
.chip.new { background: var(--accent); color: var(--on-accent); }
.chip.pin { color: var(--accent); }
.mem-actions { display: flex; gap: 16px; }
.link { background: none; border: 0; padding: 4px 0; color: var(--accent); font-size: .85rem; cursor: pointer; }
.bulkbar { display: flex; align-items: center; justify-content: space-between; gap: 8px; }

/* ---- M4 local AI + demo ---- */
.notice.warn { color: #ffb86b; }
.local h3 { font-size: .95rem; margin: 18px 0 8px; }
.model { display: flex; justify-content: space-between; align-items: center; gap: 12px; background: var(--bg); border: 1px solid transparent; border-radius: var(--radius); padding: 12px; margin-bottom: 8px; }
.model.inuse { border-color: var(--accent); }
.model .chip { margin-left: 8px; }
.progress { margin-top: 14px; }
.bar { height: 8px; background: var(--bg); border-radius: 999px; overflow: hidden; margin: 6px 0; }
.bar > div { height: 100%; background: var(--accent); transition: width .2s; }
.banner { margin: 0 12px 8px; padding: 14px; background: var(--card); border-radius: var(--radius); display: flex; flex-direction: column; gap: 8px; }
.banner p { margin: 0; }
.note.soft { color: var(--muted); }
.btn .chip { margin-left: 6px; background: transparent; border: 1px solid currentColor; }
.send.stop { font-size: .9rem; }

.reply-status { text-align: left; align-self: flex-start; max-width: 92%; }
.reply-status .rs-line { font-size: .95rem; word-break: break-all; }
.reply-status .rs-time { opacity: .6; font-size: .8rem; margin-left: 4px; }
.reply-status .rs-hint { font-size: .8rem; margin-top: 4px; opacity: .85; }
.adv label small { display:block; color: var(--muted); font-weight: 400; }
.adv .adv-row { display:flex; gap:10px; align-items:center; }
.adv .adv-row input[type=range] { flex:1; }
.adv .adv-row input[type=number] { width: 84px; }

.model { flex-wrap: wrap; }
.model .progress { flex-basis: 100%; margin-top: 8px; }
.storage { margin-top: 20px; }
VB_EOF
mkdir -p "src"
cat > "./src/version.js" <<'VB_EOF'
export const APP_VERSION = '0.4.2'
// Today's date on the person's own clock (not UTC), as YYYY-MM-DD.
export const todayLocal = () => { const d = new Date(); return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}` }
VB_EOF
mkdir -p "."
cat > "./vite.config.js" <<'VB_EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
export default defineConfig({
  plugins: [react()],
  optimizeDeps: { exclude: ['@wllama/wllama'] }, // ships its own worker/wasm; keep it out of dep pre-bundling
})
VB_EOF
chmod +x deploy/deploy.sh
echo "Updated virtual-buddy/ to v0.4.2. Next: npm install && ./deploy/deploy.sh"
