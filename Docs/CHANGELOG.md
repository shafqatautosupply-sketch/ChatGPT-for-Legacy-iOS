# Changelog

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
