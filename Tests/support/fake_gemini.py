# Fake model endpoint on port 8082, speaks BOTH APIs (decided by URL path):
#   .../chat/completions            -> strict OpenAI Chat Completions (validates the request, HTTP 400 if invalid)
#   .../models/<m>:generateContent  -> Gemini generateContent
# Answers with N tool calls, then a text answer. A request without "tools" always gets a text answer.
import http.server, json, sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 3
SAME = len(sys.argv) > 2 and sys.argv[2] == "same"   # always the same command: a stuck model
count = {"n": 0}

def validate_openai(body, auth):
    if auth != "Bearer KEY": return 401, "Incorrect API key provided"
    if body.get("model") != "m": return 400, "unknown model %r" % body.get("model")
    msgs = body.get("messages")
    if not msgs: return 400, "messages must not be empty"
    if any(m.get("role") == "system" for m in msgs[1:]): return 400, "a system message may only be the first message"
    for t in body.get("tools", []):
        f = t.get("function", {})
        if t.get("type") != "function" or f.get("parameters", {}).get("type") != "object":
            return 400, "invalid tool definition (schema types must be lowercase)"
    for i, m in enumerate(msgs):
        if not isinstance(m.get("content"), str): return 400, "message %d: content must be a string" % i
        calls = m.get("tool_calls")
        if calls:
            for k, c in enumerate(calls):
                try: json.loads(c["function"]["arguments"])
                except Exception: return 400, "message %d: arguments is not valid JSON" % i
                nxt = msgs[i + 1 + k] if i + 1 + k < len(msgs) else {}
                if nxt.get("role") != "tool" or nxt.get("tool_call_id") != c.get("id"):
                    return 400, "message %d: tool call %s has no matching tool message" % (i, c.get("id"))
        if m.get("role") == "tool":
            prev = [x for x in msgs[:i] if x.get("role") != "tool"]
            ids = [c.get("id") for c in (prev[-1].get("tool_calls") or [])] if prev else []
            if m.get("tool_call_id") not in ids: return 400, "message %d: tool message without a call" % i
    return 200, None

class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        raw = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        count["n"] += 1
        body = json.loads(raw)
        cmd = "echo same" if SAME else "echo step%d" % count["n"]
        if self.path.endswith("/chat/completions"):
            code, err = validate_openai(body, self.headers.get("Authorization"))
            if code != 200: return self.reply(code, {"error": {"message": err, "type": "invalid_request_error"}})
            if "tools" in body and count["n"] <= N:
                if count["n"] > 1:   # the previous tool output must have been sent back
                    last = body["messages"][-1]
                    if last.get("role") != "tool" or "step%d" % (count["n"] - 1) not in last.get("content", "") and not SAME:
                        return self.reply(400, {"error": {"message": "tool output was not returned to the model"}})
                msg = {"role": "assistant", "content": None, "tool_calls": [{"id": "call_%d" % count["n"], "type": "function",
                       "function": {"name": "runShellCommand", "arguments": json.dumps({"command": cmd})}}]}
                fin = "tool_calls"
            else:
                msg = {"role": "assistant", "content": "All done."}; fin = "stop"
            return self.reply(200, {"choices": [{"index": 0, "message": msg, "finish_reason": fin}],
                "usage": {"prompt_tokens": 100, "completion_tokens": 5, "prompt_tokens_details": {"cached_tokens": 64}}})
        # Gemini
        part = {"functionCall": {"name": "runShellCommand", "args": {"command": cmd}}} if count["n"] <= N else {"text": "All done."}
        self.reply(200, {"candidates": [{"content": {"role": "model", "parts": [part]}}], "usageMetadata": {"promptTokenCount": 100, "candidatesTokenCount": 5}})
http.server.ThreadingHTTPServer(('127.0.0.1', 8082), H).serve_forever()
