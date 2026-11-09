# Fake Gemini endpoint: answers with N tool calls, then a text answer. Port 8082.
import http.server, json, sys
N = int(sys.argv[1]) if len(sys.argv) > 1 else 3
SAME = len(sys.argv) > 2 and sys.argv[2] == "same"   # always the same command: a stuck model
count = {"n": 0}
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        count["n"] += 1
        if count["n"] <= N:
            part = {"functionCall": {"name": "runShellCommand", "args": {"command": "echo same" if SAME else "echo step%d" % count["n"]}}}
        else:
            part = {"text": "All done."}
        body = json.dumps({"candidates": [{"content": {"role": "model", "parts": [part]}}],
                           "usageMetadata": {"promptTokenCount": 100, "candidatesTokenCount": 5}}).encode()
        self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
http.server.ThreadingHTTPServer(('127.0.0.1', 8082), H).serve_forever()
