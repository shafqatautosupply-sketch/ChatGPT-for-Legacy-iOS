# Security model

## Who is the attacker?

The **model is not trusted**, and neither is anything it reads. A file in the workspace, a
README, tool output or a web snippet can contain instructions ("prompt injection") that make
the model run commands you never asked for. The agent therefore has to be safe even when the
model is actively trying to misbehave.

The app runs unsandboxed as user `mobile`, so anything the process can do, a command can do.
The guardrails are the only barrier.

## Layers

1. **No shell.** `AGShellRunner` tokenises the command itself and `fork`/`execve`s the binary.
   `$(...)`, backticks, `$VAR`, `~`, redirects (`>`/`<`), pipes, `;` and `&` have no meaning and
   are rejected with an explanation. Supported: quotes, `*`/`?`/`[..]` globs (expanded in-process),
   `cd`/`pwd`, and `a && b && c` (stop at first failure).
2. **Whitelist.** Only listed binaries run, found on a fixed search path (`./make` or
   `/tmp/make` can't impersonate `make`). Default list in `AGGuardrails`.
3. **Path jail** (`AGPathJail`). Every path argument and every file-tool path is resolved
   component by component (symlinks followed by hand, `..` folded afterwards) and must stay
   inside the workspace or the Theos directory, on a `/` boundary (`/SandBox-evil` is outside
   `/SandBox`). Hard-block and secret path lists are *added to* built-in ones; the settings
   screen can no longer remove them.
4. **Per-binary argument rules.** Blocks the flags that turn a tool into a command runner or an
   unjailable file writer: `find -exec/-delete/-fprint*`, `tar --to-command/-P/-I/...`,
   `awk` `system()`/`getline`/`print >`, `sed` `e`/`w`/`r`, `zip -TT`, `date -s`, compiler plugins
   (`-fplugin`, `-Xclang`, `-load`, `-wrapper`, `-specs`).
5. **Theos internals are read-only to the agent**: `bin`, `makefiles`, `vendor`, `templates`,
   `sdks`. Otherwise one write there would taint every future build.
6. **Resource limits.** Per-command timeout (default 120 s, process group killed), stdin is
   `/dev/null`, output capped (head + tail kept), 60 commands per minute, a maximum number of
   model requests per task, and a repeated-identical-call detector.
7. **HTTPS verification** against the bundled `cacert.pem`; no redirects followed (the API key
   header would travel with them); `Settings > Agent > Allow insecure TLS` is an explicit,
   off-by-default escape hatch.

## What this does NOT protect against

- **`make`, `clang`, `ld`, `sed`, `awk` are programming languages.** A Makefile the model writes
  can run anything as `mobile` (`$(shell ...)`, recipes). The same goes for a hostile
  `Makefile` already sitting in a project you open. Treat "the agent may run `make`" as
  "the agent may run code". Remove `make` from *Allowed Binaries* if you want a read-only agent.
- Anything inside the workspace/Theos directories is fair game, including deleting your
  projects. Keep the workspace to things you can lose, or use version control.
- Your **API key is stored in the app's preferences plist in clear text** (iOS 6 jailbreak,
  no keychain use). It is outside the agent's reach (jail + secret paths), but any other
  process running as `mobile` can read it.
- The conversation (including file contents and command output the model touched) is sent
  to Google.
- Plain `http://` base URLs send the key unencrypted (OK on a trusted LAN for a local model server, not otherwise).
- The bundled CA list is Mozilla's, without a few older roots (Baltimore CyberTrust, DigiCert Global Root CA). A provider
  whose chain ends there fails verification until you point `ag_ca_bundle_path` at a fuller bundle or enable the
  explicit insecure switch.
- With an OpenAI-compatible provider your conversation, file contents and command output go to *that* provider.

## Ideas for the next hardening step

- A confirmation dialog for destructive commands (`mv` over existing files, large `cp`).
- Run builds as a separate low-privilege user (needs a helper binary and a setuid step).
- Keychain storage for the API key.


## Approvals, deleting and background (unreleased)

- `make`, `python` and `python3` ask the user first (Deny / Allow once / Allow for this task). A Makefile or
  script can run any code as the app's user, so the prompt is a human check, not a sandbox: it shows the first
  lines of what will run, not the modules or files it pulls in. Turning the switch off removes the main
  protection against a prompt-injected model.
- Deleting is the native `deleteFile` tool (move to `.agent-trash`, confirm, never permanent). Raw `rm` is not
  allowed. `make`/`python` can still delete anything the app's user can; the delete tool does not change that.
- Background mode keeps the process alive, so an approval can be waiting while the app is not visible; it is then asked as a system dialog over the current app. The agent
  thread waits (default 10 minutes, then denies). If iOS kills the app meanwhile, the task is simply gone.


## Web Access (other devices on the network)

What it is: an HTTP server inside the app, off by default, listening on all network interfaces of the phone while
the switch is on. What it protects and what it does not:

- **Who gets in:** only a device you allowed on the phone. There is no password; the question "Allow web access?" is
  shown on the phone and a token is issued only after Allow. The token is random (160 bits), stored in the browser
  and in the app's preferences (like the API key), and sent in a custom header, never in a cookie, so a web site
  open in another tab cannot use it. Cross-site POSTs (a foreign `Origin`) are refused and no CORS headers are sent.
- **Spam and guessing:** pairing questions are rate limited and a refused address is blocked for a while (see the
  changelog). Anyone on the network can make the phone show the question, so read the device name, address and
  code before tapping Allow.
- **What an allowed device can do:** read and write the shared chat, start and stop tasks, switch chats and start a
  new one. With Agent Mode on, a task started from the page has the same tools and the same guardrails as one started
  on the phone. It cannot see or change settings, API keys, the system prompt or guardrails, and it cannot answer
  approval questions: `make`, `python` and deleting files are asked on the phone only. A device that can chat can
  still make the agent read, write and edit files inside the workspace, which needs no question; turn Web Access off
  if you do not want that.
- **Not protected:** the traffic is plain HTTP, so anyone on the same network can read it and could copy a token
  from it (a hotspot you share is such a network). There is no TLS because a self-signed certificate would give every
  browser a warning and old TV browsers refuse it. Use it at home on your own Wi-Fi. Do not forward the port to the
  internet.
- Limits: 16 connections at once, 16 KB of headers, 256 KB of body, 20,000 characters per message, 15 s to send a
  request. The page is a single file with a content security policy that allows no outside resources.
