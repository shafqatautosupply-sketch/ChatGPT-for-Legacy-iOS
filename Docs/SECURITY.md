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
- Plain `http://` base URLs send the key unencrypted.

## Ideas for the next hardening step

- A confirmation dialog for destructive commands (`mv` over existing files, large `cp`).
- Run builds as a separate low-privilege user (needs a helper binary and a setuid step).
- Keychain storage for the API key.
