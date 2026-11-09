#!/bin/bash
# Host-side tests for the agent core. Needs clang, GNUstep Foundation, libcurl and
# libBlocksRuntime (Ubuntu: clang gnustep-base-common libgnustep-base-dev gnustep-make
# libcurl4-openssl-dev libblocksruntime-dev libobjc-13-dev python3 openssl).
# These do not run on the phone; they check the logic that does not need UIKit.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; export AG_REPO="$(dirname "$HERE")"; S="$AG_REPO/Sources"
REAL_HOME="$HOME"   # GNUstep keeps NSUserDefaults per process name under the real home
export HOME="$(mktemp -d)"; mkdir -p "$HOME/Library"
CC="clang -fblocks -fobjc-exceptions -fgnu-runtime -DGNU_RUNTIME=1 -DGNUSTEP -DFALSE=0 -DTRUE=1 -DGNUSTEP_BASE_LIBRARY=1 \
 -fno-strict-aliasing -fconstant-string-class=NSConstantString -Wno-import -Wno-deprecated-declarations -w \
 -I$HERE/support -I/usr/include/GNUstep -I/usr/lib/gcc/x86_64-linux-gnu/13/include \
 -I$S/API -I$S/Agent -I$S/Model -I$S/Storage -I$S/Support -I$AG_REPO/Vendor/curl/include \
 -include sys/stat.h -include stdlib.h -include unistd.h"
LIBS="-lgnustep-base -lBlocksRuntime -lobjc -lm"
OUT="$(mktemp -d)"; fail=0
# every suite starts from empty saved defaults (see rm below)
run() { name=$1; shift; echo "=== $name"; rm -f "$REAL_HOME/GNUstep/Defaults/$name.plist" ; if ! $CC "$@" $LIBS -o "$OUT/$name" 2>"$OUT/$name.log"; then echo "BUILD FAILED"; cat "$OUT/$name.log"; fail=1; return; fi
        NSZombieEnabled=YES NSDeallocateZombies=NO "$OUT/$name" 2>&1 | tee "$OUT/$name.out" | grep -E "PASS|FAIL|ALL|SOME|===|deallocated instance" ; [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1; }

run shell    "$HERE/ShellGuardrailsTests.m"   $S/Agent/AGShellRunner.m $S/Agent/AGGuardrails.m $S/Agent/AGPathJail.m
run text     "$HERE/TextUtilTests.m"          $S/Support/AGTextUtil.m
run tools    "$HERE/AgentToolsTests.m"        $S/Support/AGTextUtil.m $S/Agent/AGAgentTools.m $S/Agent/AGShellRunner.m $S/Agent/AGGuardrails.m $S/Agent/AGPathJail.m
run context  "$HERE/ContextBuilderTests.m"    $S/API/AGContextBuilder.m $S/Model/AGMessage.m
run config   "$HERE/ProviderConfigTests.m"    $S/API/AGProviderConfig.m $S/Model/AGMessage.m
run store    "$HERE/ConversationStoreTests.m" $S/Storage/AGConversationStore.m $S/Model/AGMessage.m $S/Model/AGConversation.m \
             -include "$HERE/support/dispatch_shim.h" -include "$HERE/support/cf_shim.h"

# HTTPS client against local HTTP/HTTPS servers
mkdir -p /tmp/ag_tls && ( cd /tmp/ag_tls && openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 2 \
  -subj "/CN=localhost" -addext "subjectAltName=DNS:localhost,IP:127.0.0.1" 2>/dev/null )
python3 "$HERE/support/test_server.py" >/dev/null 2>&1 & SERVER=$!; sleep 1.5
run http     "$HERE/HTTPClientTests.m"        $S/API/AGHTTPClient.m -lcurl
kill $SERVER 2>/dev/null
# The real agent loop against a fake Gemini server. NSZombieEnabled makes any message to a freed
# object visible (on iOS it is a SIGSEGV; on Linux freed memory still "works", which hid a real crash).
loop() { mode=$1; shift
  rm -f "$REAL_HOME/GNUstep/Defaults/loop.plist"
  python3 "$HERE/support/fake_gemini.py" 3 $mode >/dev/null 2>&1 & FAKE=$!; sleep 1
  OUT=$(NSZombieEnabled=YES NSDeallocateZombies=NO "$OUT_DIR/loop" $mode 2>&1); RC=$?; kill $FAKE 2>/dev/null; wait $FAKE 2>/dev/null
  echo "$OUT" | grep -E "PASS|FAIL|ALL|SOME"
  Z=$(echo "$OUT" | grep -c "deallocated instance")
  if [ "$Z" -ne 0 ]; then echo "FAIL loop($mode): $Z messages sent to freed objects"; fail=1; fi
  [ $RC -eq 0 ] || fail=1; }
echo "=== loop (real AGGeminiClient agent loop, fake server)"
OUT_DIR="$OUT"
if $CC -I$HERE/support -I$S/Support -include "$HERE/support/dispatch_shim.h" -include "$HERE/support/cf_shim.h" "$HERE/AgentLoopTests.m" \
   $S/API/AGGeminiClient.m $S/API/AGProviderConfig.m $S/API/AGContextBuilder.m $S/API/AGHTTPClient.m $S/Agent/AGAgentTools.m $S/Agent/AGShellRunner.m \
   $S/Agent/AGGuardrails.m $S/Agent/AGPathJail.m $S/Support/AGTextUtil.m $S/Storage/AGConversationStore.m $S/Model/AGMessage.m $S/Model/AGConversation.m \
   $LIBS -lcurl -o "$OUT/loop" 2>"$OUT/loop.log"; then
  loop normal; loop same; loop steps
else echo "BUILD FAILED"; cat "$OUT/loop.log"; fail=1; fi
[ $fail -eq 0 ] && echo "ALL SUITES PASSED" || { echo "SOME SUITES FAILED"; exit 1; }
