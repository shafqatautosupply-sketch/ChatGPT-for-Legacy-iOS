# Changelog

## Unreleased
- **Kernel sandbox for commands (Seatbelt).** Every command runs with writes limited to the workspace, no reads
  of `/var/mobile` outside the workspace/Theos, no network and no Mach lookups; descriptors above 2 are closed.
  The app first proves the kernel enforces the profile. `rm` is now on the default allowed list, behind the
  confirmation prompt, and only works while the sandbox is active (it refuses the workspace itself and its
  parents). If you saved your own Allowed Binaries list, add `rm` there. New `agent_sandbox*` defaults and
  `Tools/sandbox-probe` (device check). Not covered: signals/ptrace between your own processes and exec policy
  (the kernel ignores those rules). See Docs/SECURITY.md.
- **Web Access.** Settings > Other devices > Web Access starts a small HTTP server (port 8080 by default) that serves
  a responsive chat page (`Resources/agentic-web.html`, one file, no external resources) to any browser on the
  same network: phone, tablet, laptop, Android TV (D-pad friendly, dark/light, 17-20 px text on big screens).
  - **No password, the phone decides.** A device taps Connect, the phone shows "Allow web access?" with the
    device name, its address and a 4-digit code that the page shows too. Allow gives that browser a random token
    (kept in the browser, sent as `X-AG-Token`); Deny refuses. Questions expire after 2 minutes; at most 4 wait at
    once; one address can ask once every 2 s, a refusal blocks it for 30 s and three refusals for 10 minutes.
    Allowed devices are listed in Settings (swipe to remove, "Disconnect all"); unused for 30 days = asks again.
  - **One transcript.** The page and the phone show the same chat: a message sent from the web appears on the
    phone and the other way round; the chat list, new chat, open chat and Stop work from the page. Agent Mode is
    followed, not switched, from the page: it shows an Agent/Chat badge.
  - **Prompts stay on the phone.** The page cannot answer approval questions (`make`, `python`, deleting files)
    and has no endpoint for settings, keys or guardrails. While one waits, the page only says "Waiting for your
    approval on the phone: <title>"; the command and file contents are never sent to it.
  - **Host header allow-list** (DNS rebinding): only IP addresses, `localhost`, `*.local` and names in the
    `agent_web_allowed_hosts` default are answered; anything else gets 403.
  - Host suite `WebAccessTests.m` (84 checks, real sockets on localhost): request parsing limits, pairing rules,
    API auth, cross-site refusal, long polling, approvals never exposed.
- **`deleteFile` tool.** Moves a file or folder to `<workspace>/.agent-trash/<timestamp>/` (log in `log.txt`,
  restore with `mv`); nothing is ever deleted for good. Refuses the workspace, the Theos folder and their
  parents, Theos read-only dirs, `.git` and the trash; a symlink is moved itself and its target is never
  touched; folders need `recursive=true`. (`rm` is allowed only inside the kernel sandbox, see above.)
- **Confirmation prompts** for `make`, `python`, `python3` (`python` and `python3` are new on the default allowed list; if you saved your own Allowed Binaries list, add them there: the list is sent to the model in the `runShellCommand` description, and the prompt applies whatever the list says) and for deletes:
  Deny / Allow once / Allow for this task (forgotten when the next task starts or Stop is tapped). The prompt
  shows the command, the folder and the first lines of the script or Makefile. No answer in 10 minutes = denied;
  with no approval screen installed everything gated is denied. Switches: Settings > Agent Guardrails > Ask me before.
- **Background running.** `Info.plist` asks for the private modes `continuous` and `unboundedTaskCompletion`
  (jailbroken iOS honours them). While a task runs a background task assertion is held, and a local notification
  says when it finished. No audio is played. The debug log records `backgroundTimeRemaining` when the app goes to
  the background ("unlimited" = the plist modes are in effect).
- **Questions over other apps.** When the app is not visible, an approval question is shown as a system dialog
  (CFUserNotification, drawn by SpringBoard; Deny is the default button) so you can answer from anywhere, also on
  the lock screen; the agent thread waits for the tap. If iOS dismisses it early it is shown again (3 times), and if
  the system dialog is unavailable a local notification is posted instead and the question waits in the app.
  Coming back to the app swaps the dialog for the in-app alert. Switches and a "Test the approval dialog" row:
  Settings > Agent Guardrails > Background.
- New host suite `ApprovalTests.m` (prompt/deny/allow/timeout/Stop, and 40+ delete cases including the attacks).
  The UIKit parts are not covered by host tests and were only syntax-checked against stubs.
- **Thinking level setting** (Settings > Model > Thinking): Auto, Model default, Minimal, Low, Medium, High.
  Auto sends Medium to Gemini 3+ Flash-Lite models (at their minimal default they end multi-step agent tasks
  too early) and nothing to other models. thinkingLevel is only sent to Gemini 3 and newer (2.5 answers HTTP 400,
  so there it is skipped) and never together with the hidden `ag_thinking_budget`. Only used in Agent Mode.

## 1.2.0
- **OpenAI-compatible endpoints** next to Google Gemini. *Settings > Model Configurations* now has two sections,
  "Google Gemini" (as before) and "OpenAI Compatible" (OpenAI, OpenRouter, DeepSeek, Groq, LM Studio, Ollama...),
  each with its own "Add..." row. Chat, Agent mode, the four tools, Token Saver, history, retry/backoff, step limit
  and the loop guard are shared; only the request/response format differs:
  `POST {base URL}/chat/completions`, `Authorization: Bearer <key>`, `tool_calls` / `tool` messages with matching
  `tool_call_id`s. The base URL may be `https://host/v1`, `https://host`, or a full `.../chat/completions`.
- Profiles saved by older versions have no type and stay Gemini; nothing to migrate.
- Chats can be continued after switching provider (call ids are matched by position). Caveat: continuing a chat
  that already used tools on an OpenAI-compatible model with a Gemini 3 model may be refused by Gemini, which wants
  its own thought signatures on earlier calls. Start a new chat in that case.
- Token usage row works for both (OpenAI `usage`, including cached tokens where the server reports them).
- Renamed `AGGeminiClient` to `AGChatClient` (it now speaks both APIs).
- Tests: strict fake OpenAI server (rejects bad auth, upper-case schema types, unmatched `tool_call_id`s with HTTP 400),
  OpenAI payload structure tests, loop tests for tool calls, pure chat and error bodies, all under zombie detection.

## 1.1.3
- **Pre-Execution Commands now expand `$NAME` and `${NAME}`** (not in single quotes), as a shell would.
  Since 1.1.0 commands run without a shell, so `export PATH=$PATH:/var/mobile/theos/bin` set PATH to the
  literal text `$PATH:/var/mobile/theos/bin`; `make` then could not find `sh`, `clang`, `ldid` and the like.
  Nothing is executed during expansion (no `$(...)`, no backticks).

## 1.1.2
- **Crash fix: the app died (SIGSEGV in the agent loop) as soon as the agent ran a second tool call.**
  Cause (introduced in 1.1.0): the loop guard kept an autoreleased string across iterations, but each
  iteration runs in its own `@autoreleasepool`, so the next iteration messaged freed memory. The guard now
  keeps plain numbers. The crash logs from three different builds all showed the same frame.
- New integration test runs the real agent loop against a fake Gemini server under `NSZombieEnabled`
  (which turns "message sent to a freed object" into a visible failure); all other suites run under it too.
  It also covers the stuck-model guard (stops after 3 identical calls) and the step limit.
- The 1.1.1 rendering changes were a wrong guess at this crash. They are harmless and kept (the text
  cleaner also saves tokens), but they were not the cause.

## 1.1.1
- **Crash fix (iOS 6.1.3 report: main thread inside UITextView layout while appending a message).**
  The new message styling is reduced to what the original code already used on iOS 6:
  - removed paragraph/line spacing attributes (not proven in the iOS 6 text view);
  - Courier is used only when the text is pure ASCII (otherwise the system font), so the text
    view never has to substitute fonts glyph by glyph; the `->`/`...` markers in monospaced
    blocks are ASCII instead of arrow/ellipsis characters;
  - tool output and all displayed text go through `AGTextUtil`: ANSI escape codes, NUL and
    other control characters (including the C1 range that Latin-1 decoding of binary output
    produces) and carriage returns are removed. This also stops them costing tokens.
- Host tests are now repeatable (they no longer inherit saved defaults from a previous run).

## 1.1.0

### Security
- Shell commands no longer run through `/bin/sh` (tokenizer + `fork/execve`). Closed: `$HOME`/`$()`/backtick
  expansion, `>file` redirects, newline-separated commands, `awk system()`, `sed e/w/r`, `find -exec`.
- Symlink-aware, boundary-safe path jail for every tool (old check was `hasPrefix` on a string:
  sibling directories like `SandBox-evil` and symlinks inside the workspace escaped it).
- **TLS certificate verification was disabled** (`CURLOPT_SSL_VERIFYPEER = 0`): anyone on the network
  could read the API key or inject tool calls. Now verified against the bundled Mozilla CA list.
- Request timeout was never applied (a stalled connection hung the agent forever); redirects are no
  longer followed with the API key header attached.
- `cycript` removed from the default whitelist; Theos `bin/makefiles/vendor/templates/sdks` are read-only.
- Settings screen defaults no longer silently replace the real whitelist/blocklists with shorter copies.
- Crash handler no longer loops forever on SIGSEGV and no longer logs to world-readable `/tmp`.

### Correctness
- Commands with empty output were **executed twice** (e.g. `mkdir`, `cp`, `mv`, `touch`). Fixed.
- `readFile` claimed "lines 1-200" but silently truncated after ~4000 characters, so the model skipped
  code. Output is now cut on a line boundary and the header says exactly which lines were shown.
- Tool output keeps its head **and tail** (the error is usually at the end of `make` output), exit codes are reported.
- Stop no longer leaves the conversation permanently broken (an unanswered function call made every later
  request fail with HTTP 400); histories are repaired before sending.
- Stop followed by a new message could revive the old agent loop (two agents in one chat). Runs are now
  identified by a counter; switching chats stops the running agent.
- Transient 429/5xx/timeouts are retried with backoff instead of ending a long task.
- Maximum steps per task and a repeated-call detector stop runaway loops.
- `thinkingLevel: HIGH` was sent on every agent request: rejected by Gemini 2.5 models and maximum
  reasoning cost on Gemini 3. Now off unless you opt in (`ag_thinking_level` / `ag_thinking_budget`).
- Provider profiles: two profiles with the same name+URL collided and renaming the active profile
  orphaned it. Fixed with stable ids (existing duplicates are repaired on first launch).
- Chat saves could finish out of order and leave an older snapshot on disk; `createdAt` was reset on every save.
- Error notices were sent back to the model as if it had said them; they are now local-only.

### Token usage
- `editFile` tool (exact-match replace): changing one line no longer means re-sending the file.
- Tool calls were sent twice (real call + display text). Fixed.
- **Token Saver** (on by default): when the estimated history passes a budget (default 24,000 tokens), old
  tool output and file contents inside old calls are shrunk, then old turns are dropped (the first message
  is always kept). It happens in steps and is remembered, so the request prefix stays identical between
  steps and Gemini's implicit caching can apply. Your saved chat is never changed.
  The old "auto-compress" asked the model to summarise the chat on every save and overwrote the history; removed.
- Settings shows the last request's prompt/cached/output token counts.

### Interface
- Appending a message no longer copies and re-measures the whole log (O(1) instead of O(chat)).
- Per-message render cache; regexes compiled once; correct markdown (code blocks untouched by bold/italic).
- Colored role labels, monospaced tool output, spacing. Terminal theme unchanged.
- Chat list uses an index file instead of parsing every chat.

### Structure
- One `AG` class prefix (the `CG` prefix collided with CoreGraphics), sources grouped by role,
  vendored libraries moved to `Vendor/`, dead Xcode project and unused classes removed
  (all recoverable from git history).

## 1.0.0 and earlier
First Theos build of the Gemini agent (fork of Legacy-Chatbox / ChatGPT for Legacy iOS).
