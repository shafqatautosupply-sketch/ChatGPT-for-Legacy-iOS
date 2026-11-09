import http.server, ssl, threading, time, gzip, json, sys
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        n=int(self.headers.get('Content-Length',0)); body=self.rfile.read(n)
        if self.path=='/slow': time.sleep(8)
        if self.path=='/redirect':
            self.send_response(302); self.send_header('Location','http://127.0.0.1:8081/leak'); self.end_headers(); return
        if self.path=='/429':
            self.send_response(429); self.send_header('Retry-After','7'); self.end_headers(); self.wfile.write(b'{"error":{"message":"quota"}}'); return
        out=json.dumps({"echo_len":len(body),"key":self.headers.get('x-goog-api-key'),"expect":self.headers.get('Expect'),"ae":self.headers.get('Accept-Encoding')}).encode()
        if self.path=='/gzip': out=gzip.compress(out); self.send_response(200); self.send_header('Content-Encoding','gzip')
        else: self.send_response(200)
        self.send_header('Content-Length',str(len(out))); self.end_headers(); self.wfile.write(out)
    do_GET=do_POST
def run(port,tls):
    s=http.server.ThreadingHTTPServer(('127.0.0.1',port),H)
    if tls:
        c=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER); c.load_cert_chain('/tmp/ag_tls/cert.pem','/tmp/ag_tls/key.pem'); s.socket=c.wrap_socket(s.socket,server_side=True)
    s.serve_forever()
threading.Thread(target=run,args=(8080,False),daemon=True).start()
threading.Thread(target=run,args=(8081,False),daemon=True).start()
run(8443,True)
