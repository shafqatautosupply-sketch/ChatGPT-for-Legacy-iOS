# Agentic: user manual

Agentic is an AI chat client and coding agent for jailbroken iOS 6 devices. It uses Google Gemini.

## 1. First start
1. **Settings > Model Configurations**: add your Gemini API key (free from Google AI Studio). Several
   profiles can exist; tap one to make it active. Editing a profile keeps it active.
2. Type a message at the bottom and tap **Send**. While a reply is pending the button says **Stop**.
3. **Chats** lists saved conversations; **New Chat** starts a fresh one. Switching chat stops any running agent.

The key is saved in the app's preferences on the device (not the keychain) and is sent only to the
configured API host, over HTTPS with certificate verification.

## 2. Modes (Settings > Mode)
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
- *Minimum seconds between requests*: pause between model calls (default 5 s, helps with free-tier limits).
- *Command timeout*: a command running longer is killed (default 120 s).
- *Max agent steps*: model requests per task before it stops (default 40).
- *Allow insecure TLS*: off by default. See `SECURITY.md` before turning it on.
- *Pre-Execution Commands*: `export NAME=value` lines added to the environment of every command.
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
- **"certificate could not be verified"**: check the device date and time first. Then see `SECURITY.md`.
- **HTTP 429**: free-tier rate limit. Requests are retried automatically a few times; raise the
  interval between requests if it keeps happening.
- **"Stopped after N steps"**: send a message to let it continue, or raise *Max agent steps*.
- **A command says it is not allowed**: it is not in *Allowed Binaries* (or it uses a blocked flag; the message says which).
