"""Meditron LLM endpoint for the CNA simulation.

Port 8000  OpenAI-compatible inference API (GET /v1/models, POST /v1/chat/completions)
Port 8001  decoy management endpoint. The firewall must block it, which proves the
           "inference port only" rule is enforced at port level.

LLM_MODE=stub  canned answer, no GPU, deterministic latency
LLM_MODE=rcp   forwards the request to EPFL RCP (real Meditron weights)
"""
import json, os, ssl, sys, threading, time, urllib.request, urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = os.environ.get("LLM_MODE", "stub")
BASE = os.environ.get("RCP_BASE_URL", "").rstrip("/")
KEY = os.environ.get("RCP_API_KEY", "")
MODEL = os.environ.get("RCP_MODEL", "")


def log(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def rcp(path, body=None):
    req = urllib.request.Request(BASE + path, method="POST" if body else "GET")
    req.add_header("Authorization", "Bearer " + KEY)
    req.add_header("Content-Type", "application/json")
    data = json.dumps(body).encode() if body else None
    with urllib.request.urlopen(req, data, timeout=120, context=ssl.create_default_context()) as r:
        return r.status, r.read()


class Inference(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def log_message(self, fmt, *a):
        log("inference %s %s" % (self.client_address[0], fmt % a))

    def do_GET(self):
        if self.path == "/v1/models":
            if MODE == "rcp":
                return self._proxy("/models")
            return self._send(200, {"data": [{"id": "meditron-stub", "object": "model"}]})
        self._send(404, {"error": "not found"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = json.loads(self.rfile.read(n) or b"{}")
        if self.path != "/v1/chat/completions":
            return self._send(404, {"error": "not found"})
        if MODE == "rcp":
            if MODEL and not body.get("model"):
                body["model"] = MODEL
            return self._proxy("/chat/completions", body)
        self._send(200, {
            "id": "stub-1", "object": "chat.completion", "model": "meditron-stub",
            "choices": [{"index": 0, "finish_reason": "stop",
                         "message": {"role": "assistant",
                                     "content": "[stub] Placeholder answer. No real model behind this endpoint."}}],
        })

    def _proxy(self, path, body=None):
        try:
            code, raw = rcp(path, body)
            self.send_response(code)
        except urllib.error.HTTPError as e:
            code, raw = e.code, e.read()
            self.send_response(code)
        except Exception as e:
            code, raw = 502, json.dumps({"error": "upstream RCP unreachable: %s" % e}).encode()
            self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)


class Admin(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.end_headers()
        self.wfile.write(b"ADMIN-DECOY: reachable means the firewall is misconfigured\n")

    def log_message(self, fmt, *a):
        log("ADMIN-DECOY hit from %s" % self.client_address[0])


if __name__ == "__main__":
    port_i = int(os.environ.get("INFERENCE_PORT", 8000))
    port_a = int(os.environ.get("ADMIN_PORT", 8001))
    log("meditron-llm mode=%s inference=%d admin-decoy=%d" % (MODE, port_i, port_a))
    if MODE == "rcp" and not (BASE and KEY):
        sys.exit("LLM_MODE=rcp needs RCP_BASE_URL and RCP_API_KEY (see .env.example)")
    threading.Thread(target=ThreadingHTTPServer(("0.0.0.0", port_a), Admin).serve_forever, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", port_i), Inference).serve_forever()
