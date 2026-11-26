# sandbox-probe

Checks on the device what the agent's kernel sandbox (Seatbelt, `Sources/Agent/AGSandbox.m`)
really enforces. The app also runs a small self-test of its own before using the sandbox
(a child applies the profile and must be refused when it writes outside the workspace); this
tool tests much more.

```sh
cd Tools/sandbox-probe && ./build.sh      # needs $THEOS, clang, ldid
su mobile -c ./sbtest                     # run as the app's user, not root
su mobile -c "./sbtest /usr/bin/python3 /var/mobile/theos"   # also runs python, extra read dirs
```

Every row should say `OK`. Expected on iOS 6.1.3 (iPhone 4s): writes outside the work dir,
reads of the home folder, network and Mach lookups are BLOCKED; the sandbox cannot be loosened
afterwards; children and exec'd programs (`rm -rf`) inherit it.

What it does **not** cover (the kernel ignores these rules, so the profile has none):
signals/ptrace against other processes of the same user, `process-exec` restrictions, and
`/var/tmp` (always readable and writable).
