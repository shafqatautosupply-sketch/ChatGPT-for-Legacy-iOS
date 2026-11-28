# Agentic: user manual

Agentic is an AI chat client and coding agent for jailbroken iOS 6 devices. It uses Google Gemini.

## 1. First start
1. **Settings > Model Configurations** has two sections:
   - **Google Gemini**: your Gemini API key (free from Google AI Studio).
   - **OpenAI Compatible**: any server that speaks the OpenAI Chat Completions API. Tap *Add OpenAI Compatible...*,
     then fill in Base URL (for example `https://api.openai.com/v1`, `https://openrouter.ai/api/v1`,
     `https://api.deepseek.com`, or a local server such as `http://192.168.1.5:1234/v1`), the model name and the key
     (local servers often accept any text; leave nothing empty if the app complains about a missing key).
   Several configurations can exist in each section; tap one to make it active (the check mark can be in either
   section). Tap the (i) button to edit, swipe to delete. Editing a configuration keeps it active.
   **Agent Mode needs a model that supports tool calling.** If a model does not, you get an HTTP 400 notice; use
   Pure chat or pick another model.
2. Type a message at the bottom and tap **Send**. While a reply is pending the button says **Stop**.
3. **Chats** lists saved conversations; **New Chat** starts a fresh one. Switching chat stops any running agent.

The key is saved in the app's preferences on the device (not the keychain) and is sent only to the
configured API host (as `x-goog-api-key` for Gemini, as a Bearer token for OpenAI-compatible servers), over HTTPS
with certificate verification. `http://` URLs (fine for a server on your own network) send it unencrypted.

## 2. Modes (Settings > Agent and Chat)
- **Agent Mode**: the model can use tools in your workspace folder: run commands, read, write and edit files.
- **Pure chat**: Agent Mode off. Plain conversation; earlier tool exchanges are shown but not replayed.
- **Terminal Mode**: green-on-black console look.
- **Markdown Logic**: headings, bold/italic, lists, inline code and code blocks.

## 3. What the agent can run
Commands are *not* passed to a shell. You can use quotes, `*.m`-style globs, `cd dir && make package`,
and `&&` chains. Pipes, redirects, `;`, `$(...)`, backticks and `$VAR` are refused with an explanation
(the model then adapts, e.g. uses the file tools instead of `>`). A failing command shows `[exit code N]`.

Tools: `runShellCommand`, `readFile` (line ranges, tells you where to continue), `writeFile`, `editFile`
(exact replace, cheapest way to change a file).

## 4. Settings
**Agent Guardrails & Workspace**
- *Workspace Directory*: the folder the agent works in (default `Documents/SandBox`). Its parent folders
  and everything outside it, except the Theos directory, are off limits.
- *Request gap (sec)*: pause between model calls (default 5 s, helps with free-tier limits).
- *Command timeout*: a command running longer is killed (default 120 s).
- *Max agent steps*: model requests per task before it stops (default 40).
- *Allow insecure TLS*: off by default. See `SECURITY.md` before turning it on.
- *Pre-Execution Commands*: `export NAME=value` lines added to the environment of every command. `$NAME` and `${NAME}` are expanded (so `export PATH=$PATH:/var/mobile/theos/bin` works); one variable per line; nothing else is executed. The default search path already includes `<theos>/bin`, so a PATH line is rarely needed; `export THEOS=/var/mobile/theos` is the one Theos needs.
- *Allowed Binaries*: whitelist. *Hard Block / Secret Paths*: extra paths to forbid, on top of the built-in ones.

**Chat History Limits**
- *Messages saved*: 0 = keep everything. *Messages loaded*: how many are shown (default 30; lower = smoother).
- *Context budget*: see Token Saver. Default 24,000 (estimated tokens).

**Token Saver** (switch): shrinks old tool output and old file contents in the request, then leaves out
old turns, once the history passes the context budget. The first message and the newest messages are
always sent in full. What you see and what is saved is never changed. "Last request" shows the
tokens the API reported for the previous call (input, cached, output).

## 5. Tips for low token usage
- Ask for changes to existing files (the agent will use `editFile` instead of rewriting whole files).
- Start a new chat per task; the whole chat is re-sent with every request.
- Keep the loaded-message limit low if scrolling gets heavy; it only affects display.
- Advanced (set with a defaults editor): `ag_thinking_level` (Gemini 3: minimal/low/medium/high) or
  `ag_thinking_budget` (Gemini 2.5: number of thinking tokens) to limit reasoning cost.

## 6. Troubleshooting
- **"certificate could not be verified"**: check the device date and time first. The bundled CA list does not contain
  a few older roots (e.g. Baltimore CyberTrust, DigiCert Global Root CA), so some hosts can fail even with a correct
  clock; see `SECURITY.md` for the options (custom CA file, or the explicit insecure switch).
- **HTTP 429**: free-tier rate limit. Requests are retried automatically a few times; raise the
  interval between requests if it keeps happening.
- **"Stopped after N steps"**: send a message to let it continue, or raise *Max agent steps*.
- **A command says it is not allowed**: it is not in *Allowed Binaries* (or it uses a blocked flag; the message says which).


## Web Access: use the chat from another device

1. Settings > Other devices > turn **Web Access** on. Open **Address & Devices** and read the address
   (for example `http://192.168.1.20:8080`; tap it to copy). The phone and the other device must be on the same Wi-Fi.
2. On the other device (Android TV browser, tablet, laptop) open that address and press **Connect**.
   The page shows a 4-digit code.
3. On the phone a message "Allow web access?" appears (also over other apps and on the lock screen when
   "Ask over other apps" is on). Check the code matches, tap **Allow**.
4. The page is now a chat window for the app. It shows the same chat as the phone, so both stay in sync.
   When Agent Mode is on the model can use its tools from there too; questions about `make`, `python` and deleting
   files appear on the phone, not on the page.

Notes
- Switch Web Access off, or remove a device (swipe) or use **Disconnect all devices**, to cut access at once.
- The page works on phones, tablets and TVs: small screens get a slide-in chat list, large screens a permanent one.
  Enter sends (on phones Enter adds a line, use Send). Light/dark toggle is in the top bar.
- Keep "Keep running in background" (Agent Guardrails & Workspace) on, or the page stops answering when the app is
  not on screen. If the port is taken, pick another one under Address & Devices.
- The connection is plain HTTP: use it on a network you trust. See `Docs/SECURITY.md`.
