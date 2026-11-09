# legacy-cli (original Python agent)

`agent.py` is the standalone command-line agent (Python 2.7 on iOS 6) that the native app was ported from.
It is **not used by the app** and was not changed in the 1.1.0 clean-up. Known issues, if you still run it:

- Its API key is placed in the URL query string (ends up in logs/proxies); the app sends it as a header.
- `rm` is allowed but its arguments are not checked against the workspace (only a list of secret substrings).
- The `awk`/`sed` forbidden-flag check matches whole tokens, so `awk 'BEGIN{system("id")}'` is not caught.
- It does verify nothing about TLS beyond what its Python build does.

Its design (split the command with `shlex`, no shell) is the model the native shell runner now follows.
