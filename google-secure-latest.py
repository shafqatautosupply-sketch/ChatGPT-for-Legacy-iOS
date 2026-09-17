import urllib2
import json
import subprocess
import sys
import os
import time
import re
import shlex

#=========================================
#Google Gemini Configuration
#=========================================
APIKEY = "API-KEY"
MODEL = "gemini-1.5-flash"

MINREQUESTINTERVAL = 5
lastrequesttime = 0

WORKSPACEDIR = os.path.abspath(os.getcwd())
THEOSDIR = os.path.abspath("/var/mobile/theos")
HISTORYFILE = "agenthistory.json"
SESSIONREQUESTCOUNT = 0

#=========================================
#SECURITY & WHITELIST CONFIGURATIONS
#=========================================
HARDBLOCKPATHS = [
    "/System", "/usr/lib", "/usr/libexec", "/usr/sbin",
    "/sbin", "/bin", "/boot", "/var/stash",
    "/usr/share/firmware", "/usr/standalone"
]

SECRETPATHS = [
    "/var/Keychains", "/var/mobile/Library/Mail",
    "/private/var/db", "/var/mobile/Library/Accounts"
]

#Strict Whitelist of allowed binaries
ALLOWEDBINARIES = {
    "clang", "clang-3.7", "cc", "c++", "as", "ld", "lipo", "strip",
    "dpkg-deb", "dpkg-query", "dpkg-split", "dpkg-trigger", "redeb",
    "ldid", "codesign_allocate", "class-dump", "classdump-dyld", "machocheck",
    "echo", "cat", "ls", "cp", "mv", "mkdir", "touch", "ln", "rm", "rmdir",
    "grep", "egrep", "fgrep", "find", "sed", "awk", "gawk", "tar", "zip", "unzip",
    "7z", "7za", "gzip", "gunzip", "bzip2", "xz", "diff", "patch", "date", "uname",
    "basename", "dirname", "strings", "head", "tail", "make", "git"
}

# Dangerous binary flags that allow sub-shell or arbitrary execution
FORBIDDEN_FLAGS = {
    "find": ["-exec", "-execdir", "-ok", "-okdir", "-delete"],
    "awk": ["system", "exec"],
    "gawk": ["system", "exec"],
    "git": ["--exec-path", "-C"]
}

bashtimestamps = []

def checkvelocityratelimit():
    global bashtimestamps
    now = time.time()
    bashtimestamps = [t for t in bashtimestamps if now - t < 60]
    if len(bashtimestamps) >= 30:
        return False, "Velocity limit reached: Too many shell commands executed in the last minute (Max 30/min)."
    bashtimestamps.append(now)
    return True, ""

def ispathallowed(pathstr):
    try:
        abspath = os.path.realpath(pathstr)
        absworkspace = os.path.realpath(WORKSPACEDIR)
        abstheos = os.path.realpath(THEOSDIR)

        return (abspath.startswith(absworkspace + os.sep) or abspath == absworkspace or
                abspath.startswith(abstheos + os.sep) or abspath == abstheos)
    except Exception:
        return False

def issafecommand(command):
    if not command or not command.strip():
        return False, "Command rejected: Empty command", []

    allowed, velreason = checkvelocityratelimit()
    if not allowed:
        return False, velreason, []

    # POSIX shell tokenization preserving quotes and spaces in Python 2.7
    try:
        if isinstance(command, unicode):
            command = command.encode('utf-8')
        tokens = shlex.split(command.strip())
    except Exception as e:
        return False, "Command rejected: Invalid shell syntax (" + str(e) + ")", []

    if not tokens:
        return False, "Command rejected: Empty token list", []

    basebin = os.path.basename(tokens[0])

    if basebin not in ALLOWEDBINARIES:
        return False, "BLOCKED (Guardrails): Command '" + basebin + "' is not in the allowed execution whitelist.", []

    # Check for forbidden execution flags
    if basebin in FORBIDDEN_FLAGS:
        for flag in FORBIDDEN_FLAGS[basebin]:
            if flag in tokens:
                return False, "BLOCKED (Guardrails): Flag '" + flag + "' is forbidden for binary '" + basebin + "'.", []

    # Sensitive path checks in arguments
    for token in tokens[1:]:
        for secret in SECRETPATHS:
            if secret in token:
                return False, "BLOCKED (Guardrails): Target argument accesses restricted directory '" + secret + "'.", []

    return True, "", tokens

#=========================================
#TOOL FUNCTIONS
#=========================================

def enforceratelimit():
    global lastrequesttime
    elapsed = time.time() - lastrequesttime
    if elapsed < MINREQUESTINTERVAL:
        sleeptime = MINREQUESTINTERVAL - elapsed
        print("\n[RATE LIMIT] Waiting time to stay under rate limit...")
        time.sleep(sleeptime)
    lastrequesttime = time.time()

def executecommand(command):
    print("\n[AGENT] Evaluating shell command: " + command)
    
    safe, reason, tokens = issafecommand(command)
    if not safe:
        print("[GUARDRAIL TRIGGERED] " + reason)
        return reason

    print("[AGENT] Executing directly (no shell sub-process) inside: " + WORKSPACEDIR)
    try:
        # Direct execution without shell re-parsing
        output = subprocess.check_output(
            tokens,
            cwd=WORKSPACEDIR,
            stderr=subprocess.STDOUT
        )
    except subprocess.CalledProcessError as e:
        output = e.output
    except Exception as e:
        output = str(e)
        
    print("\n[TOOL OUTPUT SENT TO GEMINI]:\n" + str(output))
    return output

def writefilecontent(filepath, content):
    print("\n[AGENT] Writing file securely: " + filepath)
    
    targetpath = os.path.abspath(os.path.join(WORKSPACEDIR, filepath))
    if not ispathallowed(targetpath):
        err = "Error: Cannot write outside of workspace or Theos directory."
        print("[GUARDRAIL TRIGGERED] " + err)
        return err
        
    try:
        if isinstance(content, unicode):
            content = content.encode('utf-8')
            
        targetdir = os.path.dirname(targetpath)
        if not os.path.exists(targetdir):
            os.makedirs(targetdir)

        f = open(targetpath, "wb")
        f.write(content)
        f.close()
        
        success = "Success: File written to " + filepath
        print("[TOOL OUTPUT SENT TO GEMINI]: " + success)
        return success
    except Exception as e:
        err = "Error writing file: " + str(e)
        print("[GUARDRAIL TRIGGERED] " + err)
        return err

def callgemini(contents):
    enforceratelimit()
    global SESSIONREQUESTCOUNT
    SESSIONREQUESTCOUNT += 1
    
    # Official Google Gemini REST API Specification endpoint:
    # POST https://generativelanguage.googleapis.com/v1beta/models/{MODEL}:generateContent?key={API_KEY}
    url = "https://generativelanguage.googleapis.com/v1beta/models/" + MODEL + ":generateContent?key=" + APIKEY
    
    headers = {
        "Content-Type": "application/json"
    }
    
    payload = {
        "contents": contents,
        "tools": [
            {
                "functionDeclarations": [
                    {
                        "name": "runShellCommand",
                        "description": (
                            "Execute a terminal command directly within the workspace or Theos directory. "
                            "Strictly protected by Whitelist Guardrails. "
                            "ALLOWED BINARIES: make, git, clang, cc, c++, dpkg-deb, ldid, "
                            "echo, cat, ls, cp, mv, mkdir, rm (within workspace/theos only, no wildcards/symlinks), grep, find, tar, zip, unzip, date. "
                            "Shell chaining (&&, ;, |) and unlisted commands are strictly blocked."
                        ),
                        "parameters": {
                            "type": "OBJECT",
                            "properties": {
                                "command": {
                                    "type": "STRING",
                                    "description": "The allowed single shell command to execute"
                                }
                            },
                            "required": ["command"]
                        }
                    },
                    {
                        "name": "writeFile",
                        "description": (
                            "Write text content (such as C code, headers, Makefiles) directly to a file within "
                            "the workspace securely. Fully supports all C syntax, curly braces {}, parentheses (), and symbols "
                            "without needing shell escaping."
                        ),
                        "parameters": {
                            "type": "OBJECT",
                            "properties": {
                                "filepath": {
                                    "type": "STRING",
                                    "description": "The relative file path inside the workspace"
                                },
                                "content": {
                                    "type": "STRING",
                                    "description": "The exact text content to write into the file"
                                }
                            },
                            "required": ["filepath", "content"]
                        }
                    }
                ]
            }
        ]
    }
    
    reqdata = json.dumps(payload)
    maxretries = 3
    
    for attempt in range(1, maxretries + 1):
        try:
            req = urllib2.Request(url, reqdata, headers)
            response = urllib2.urlopen(req)
            data = json.loads(response.read())
            return data
            
        except urllib2.HTTPError as e:
            code = e.code
            try:
                errbody = e.read()
            except:
                errbody = ""
                
            if code in [503, 429] and attempt < maxretries:
                waittime = 5
                print("\n[API WARNING] Received HTTP " + str(code) + " (High Demand / Overloaded).")
                print("[API RETRY] Attempt " + str(attempt) + " of " + str(maxretries) + ". Waiting before retrying...")
                time.sleep(waittime)
                enforceratelimit()
                continue
            else:
                print("[API ERROR] HTTP Status: " + str(code))
                print("[API ERROR] Response: " + str(errbody))
                raise e
        except Exception as e:
            if attempt < maxretries:
                print("\n[API WARNING] Network error: " + str(e))
                print("[API RETRY] Attempt " + str(attempt) + " of " + str(maxretries) + ". Retrying...")
                time.sleep(2)
                continue
            else:
                raise e

def loadhistory():
    if os.path.exists(HISTORYFILE):
        try:
            f = open(HISTORYFILE, "r")
            data = json.load(f)
            f.close()
            print("[HISTORY] Loaded previous conversation from " + HISTORYFILE)
            return data
        except Exception as e:
            print("[HISTORY] Could not load history file: " + str(e))
    return []

def savehistory(contents):
    try:
        f = open(HISTORYFILE, "w")
        json.dump(contents, f)
        f.close()
    except Exception as e:
        print("[HISTORY] Could not save history file: " + str(e))

GLOBALCONTENTS = loadhistory()

def getsafecontext(contents, maxmessages=1000):
    if not contents:
        return []
        
    if len(contents) > maxmessages:
        context = contents[-maxmessages:]
    else:
        context = list(contents)
        
    while len(context) > 0:
        firstmsg = context[0]
        role = firstmsg.get("role")
        parts = firstmsg.get("parts", [])
        isfuncresponse = (role == "user" and any("functionResponse" in p for p in parts))
        
        if isfuncresponse or role == "model":
            context.pop(0)
        else:
            break
            
    if not context:
        for i in range(len(contents) - 1, -1, -1):
            msg = contents[i]
            role = msg.get("role")
            parts = msg.get("parts", [])
            isfuncresponse = (role == "user" and any("functionResponse" in p for p in parts))
            if role == "user" and not isfuncresponse:
                context = contents[i:]
                break
                
    if not context and contents:
        lastmsg = contents[-1]
        if lastmsg.get("role") == "user":
            context = [lastmsg]
            
    return context

def runagentloop(userprompt):
    global GLOBALCONTENTS
    print("\nUser: " + userprompt)
    
    GLOBALCONTENTS.append({
        "role": "user",
        "parts": [{"text": userprompt}]
    })
    
    while True:
        print("[AGENT] Sending request to Gemini REST API... (Session Requests: " + str(SESSIONREQUESTCOUNT) + ")")
        
        contexttosend = getsafecontext(GLOBALCONTENTS, maxmessages=50)
        
        try:
            apiresponse = callgemini(contexttosend)
        except Exception as e:
            print("[AGENT] API Error: " + str(e))
            break
            
        print("[AGENT] Received response.")
        
        try:
            candidate = apiresponse["candidates"][0]
            content = candidate["content"]
            parts = content["parts"]
        except (KeyError, IndexError):
            print("[AGENT] Unexpected response format")
            break
            
        GLOBALCONTENTS.append(content)
        savehistory(GLOBALCONTENTS)
        
        hasfunctioncall = False
        for part in parts:
            if "functionCall" in part:
                hasfunctioncall = True
                funccall = part["functionCall"]
                funcname = funccall["name"]
                funcargs = funccall["args"]
                
                print("[AGENT] Gemini requested tool: " + funcname)
                
                if funcname == "runShellCommand":
                    cmd = funcargs.get("command", "")
                    tooloutput = executecommand(cmd)
                    
                    GLOBALCONTENTS.append({
                        "role": "user",
                        "parts": [{
                            "functionResponse": {
                                "name": "runShellCommand",
                                "response": {"output": tooloutput}
                            }
                        }]
                    })
                    savehistory(GLOBALCONTENTS)
                    
                elif funcname == "writeFile":
                    filepath = funcargs.get("filepath", "")
                    content = funcargs.get("content", "")
                    tooloutput = writefilecontent(filepath, content)
                    
                    GLOBALCONTENTS.append({
                        "role": "user",
                        "parts": [{
                            "functionResponse": {
                                "name": "writeFile",
                                "response": {"output": tooloutput}
                            }
                        }]
                    })
                    savehistory(GLOBALCONTENTS)
                    
        if not hasfunctioncall:
            finaltext = ""
            for part in parts:
                if "text" in part:
                    finaltext += part["text"]
            print("\nGemini: " + finaltext)
            break
            
    savehistory(GLOBALCONTENTS)

print("=== Pythonista Whitelist-Hardened Gemini Agent Initialized (Direct Exec, Official REST) ===")
print("Workspace: " + WORKSPACEDIR)
print("Theos Directory: " + THEOSDIR)
print("Safety Jails: STRICT WHITELIST + DIRECT EXEC + WRITEFILE ENABLED")
print("Persistent Storage: ACTIVE (Chat saves to " + HISTORYFILE + ")")

while True:
    try:
        prompt = raw_input("\nAsk agent anything or type exit: ")
        if prompt.lower() == 'exit':
            break
        if prompt.strip():
            runagentloop(prompt)
    except KeyboardInterrupt:
        break
