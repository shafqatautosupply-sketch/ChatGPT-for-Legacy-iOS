# Host-side tests

Tests for the parts of the app that do not need UIKit: the shell runner and guardrails,
file tools, context builder (token saver), provider profiles, chat store and HTTPS client.

```sh
Tests/run.sh      # Linux with clang + GNUstep; see the header of the script for packages
```

They exercise real behaviour (they fork real processes, write real files, talk to local
HTTP/HTTPS servers), including the attacks the old guardrails let through.

Limits: they run against GNUstep, libcurl 8 and OpenSSL 3, not the iOS 6 SDK, libcurl 7.33 or
OpenSSL 1.0.2, and they do not cover any UI code. `support/` has small stand-ins for GCD and
CFUUID (the chat store test runs queue blocks inline, so it does not prove ordering across
threads). Treat a pass here as "the logic is right", not as "it runs on the device".
