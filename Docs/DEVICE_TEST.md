# On-device test checklist (iPhone 4S, iOS 6.1)

The host tests in `Tests/` cannot cover UIKit or the real libcurl/OpenSSL pair, and this release was not
run on a device by its author. Please go through this once after installing.

## HTTPS (most important)
1. Settings > Agent: *Allow insecure TLS* must be **off**. Send "hi" in Pure chat.
   - Works: certificate verification works with the bundled CA list. Done.
   - Error mentioning curl error 60 / certificate: check the device date/time. If that is right, the
     OpenSSL 1.0.2 build cannot validate Google's chain. Temporary workaround: turn insecure TLS on;
     better: replace `Resources/cacert.pem` with a bundle that includes the roots your chain needs
     (or set the `ag_ca_bundle_path` default to your own file).
2. Turn on airplane mode, send a message: a readable network error appears (not a hang).

## Agent loop
3. Ask: "create hello.txt containing hi, then show its contents". Expect writeFile, readFile, a text answer.
4. Ask for something long, press **Stop** mid-way, then send a new message: no error, no second agent.
5. Ask: "list files and run `cd proj && ls`" (create `proj` first). `&&` and `cd` work.
6. Ask it to run `echo hi > x.txt`: refused with an explanation, then it uses writeFile.
7. Ask it to `cat /etc/passwd` and `ls ..`: refused.
8. Run `make package` on a small Theos project: output ends with the real result; a failing build shows the error at the end.

## Interface
9. Long chat (30+ messages): appending messages stays smooth; scrolling is smooth.
10. Role labels are colored, tool results are monospaced, code blocks keep their `*` characters.
11. Toggle Terminal Mode and Markdown: the chat redraws once, nothing is lost.
12. Switch to another chat while the agent is running: the old reply does not appear in the new chat.
13. Chats list opens instantly; open an old chat saved by version 1.0: messages and tool calls show correctly.

## Tokens
14. Settings > "Last request" shows prompt/cached/output counts. In a long agent session the prompt count should
    level off instead of growing every step once the Context budget is reached.
