#!/usr/bin/env python3
"""federfall-j3t5 / federfall-8qz — a fake OIDC provider for the rule suite.

Without one, nothing in the suite can complete an OAuth2 sign-in, so the whole
provisioning path (oauth2_provisioning.pb.js + zv_oauth2_provisioning.js) went
untested — including the createData merge that let a first-time arrival make
itself a supervisor.

It implements exactly the two server-to-server calls PocketBase makes while
handling `POST /api/collections/users/auth-with-oauth2`, and nothing else (the
browser-facing authorize step never happens: the test hands PocketBase a code
directly):

- `POST /token`    answers with the posted `code` AS the access token;
- `GET /userinfo`  base64url-decodes the bearer token back into the claims.

So the code a test sends IS the identity it wants to sign in as —
`base64url(json(claims))` — and every sign-in is stateless: no client
registration, no sessions, no keys. `oidc_code()` in test_rules.py builds one.

Usage (run.sh starts it): fake_oidc.py <port>
"""
import base64
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):  # keep the suite's output readable
        pass

    def _json(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        if self.path.split("?")[0] != "/token":
            return self._json(404, {"error": "not_found"})
        n = int(self.headers.get("Content-Length", 0))
        form = parse_qs(self.rfile.read(n).decode())
        code = form.get("code", [""])[0]
        if not code:
            return self._json(400, {"error": "invalid_grant"})
        self._json(200, {
            "access_token": code, "token_type": "Bearer", "expires_in": 3600,
        })

    def do_GET(self):
        path = self.path.split("?")[0]
        if path == "/health":
            return self._json(200, {"ok": True})
        if path != "/userinfo":
            return self._json(404, {"error": "not_found"})
        token = self.headers.get("Authorization", "").split(" ", 1)[-1]
        try:
            pad = "=" * (-len(token) % 4)
            claims = json.loads(base64.urlsafe_b64decode(token + pad))
        except Exception:
            return self._json(401, {"error": "invalid_token"})
        self._json(200, claims)


if __name__ == "__main__":
    # 0.0.0.0, not loopback: the PocketBase container reaches this through the
    # host gateway (host.containers.internal), i.e. from outside the host's
    # loopback interface. It lives only as long as one run.sh invocation.
    HTTPServer(("0.0.0.0", int(sys.argv[1])), Handler).serve_forever()
