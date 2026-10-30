#!/usr/bin/env python3
"""Test için Firebase taklidi (sadece geliştirme; oyuna dahil değil).

Desteklenenler:
  - Anonim giriş:  POST /v1/accounts:signUp,  token yenileme: POST /v1/token
  - Realtime Database REST: GET / PUT / PATCH / POST / DELETE  /<yol>.json?auth=<token>
  - {".sv": "timestamp"} sunucu saati, X-Firebase-ETag + if-match (412)
  - Canlı dinleme (Accept: text/event-stream): put / patch / keep-alive olayları
  - database.rules.json kurallarının bu oyunun kullandığı alt kümesi (auth, $değişkenler,
    data/newData/root, child/val/exists/hasChildren, now, matches)

Kullanım:  python3 server.py <port> [kurallar.json]
Ortam: FAKE_LATENCY_MS (her isteğe eklenen gecikme)
"""
import hashlib
import json
import os
import re
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LOCK = threading.Condition()
DB = {}
VERSION = [0]
TOKENS = {}      # id token -> uid
REFRESH = {}     # refresh token -> uid
PUSH_COUNTER = [0]
RULES = None
LATENCY = int(os.environ.get("FAKE_LATENCY_MS", "0")) / 1000.0
STATS = {"requests": 0, "denied": 0, "bytes_out": 0}


def now_ms():
    return int(time.time() * 1000)


def split(path):
    return [p for p in path.strip("/").split("/") if p]


def get_at(tree, parts):
    cur = tree
    for p in parts:
        if not isinstance(cur, dict) or p not in cur:
            return None
        cur = cur[p]
    return cur


def resolve_sv(v):
    if isinstance(v, dict):
        if v == {".sv": "timestamp"}:
            return now_ms()
        return {k: resolve_sv(x) for k, x in v.items()}
    if isinstance(v, list):
        return {str(i): resolve_sv(x) for i, x in enumerate(v) if x is not None}
    return v


def prune(v):
    if isinstance(v, dict):
        out = {k: prune(x) for k, x in v.items()}
        out = {k: x for k, x in out.items() if x is not None}
        return out or None
    return v


def set_at(tree, parts, value):
    """Yeni bir ağaç döndürür (kopya üzerinde değişiklik)."""
    if not parts:
        return prune(value)
    tree = dict(tree) if isinstance(tree, dict) else {}
    child = set_at(tree.get(parts[0]), parts[1:], value)
    if child is None:
        tree.pop(parts[0], None)
    else:
        tree[parts[0]] = child
    return tree or None


def to_client(v):
    """Ardışık sayısal anahtarlı nesneleri Firebase gibi diziye çevirir."""
    if isinstance(v, dict):
        keys = list(v.keys())
        if keys and all(k.isdigit() for k in keys):
            idx = sorted(int(k) for k in keys)
            if idx[-1] < 2 * len(idx):
                arr = [None] * (idx[-1] + 1)
                for k in keys:
                    arr[int(k)] = to_client(v[k])
                return arr
        return {k: to_client(x) for k, x in v.items()}
    return v


# ---------------------------------------------------------------- kurallar

class Snap:
    def __init__(self, tree, parts):
        self.tree, self.parts = tree, parts

    def child(self, p):
        return Snap(self.tree, self.parts + split(str(p)))

    def parent(self):
        return Snap(self.tree, self.parts[:-1])

    def val(self):
        v = get_at(self.tree, self.parts)
        if isinstance(v, str):
            return JsStr(v)
        return None if isinstance(v, dict) else v

    def exists(self):
        return get_at(self.tree, self.parts) is not None

    def hasChildren(self, names=None):
        v = get_at(self.tree, self.parts)
        if not isinstance(v, dict):
            return False
        return all(n in v for n in (names or [])) if names else True

    def hasChild(self, n):
        return self.child(n).exists()

    def isNumber(self):
        return isinstance(self.val(), (int, float)) and not isinstance(self.val(), bool)

    def isString(self):
        return isinstance(self.val(), str)


class JsStr(str):
    def matches(self, rx):
        return re.search(rx, self) is not None

    @property
    def length(self):
        return len(self)


def eval_rule(expr, ctx):
    e = expr
    e = e.replace("===", "==").replace("!==", "!=").replace("&&", " and ").replace("||", " or ")
    e = re.sub(r"!(?!=)", " not ", e)
    e = e.replace("null", "None").replace("true", "True").replace("false", "False")
    # /regex/ -> r"regex"
    e = re.sub(r"\.matches\(/(.*?)/\)", lambda m: '.matches(r"%s")' % m.group(1), e)
    e = re.sub(r"\$(\w+)", r"_v_\1", e)
    e = e.replace(".length", ".length")
    try:
        return bool(eval(e, {"__builtins__": {}}, ctx))
    except Exception as ex:  # noqa
        sys.stderr.write("rule error %r: %s\n" % (expr, ex))
        return False


def check_write(uid, parts, old_tree, new_tree):
    """Yazmaya izin var mı? (.write kademeli: yoldaki herhangi bir düğüm izin verirse yeter,
    sonra yazılan her yeni düğümün .validate kuralları geçmeli.)"""
    if RULES is None:
        return True
    auth = {"uid": uid} if uid else None
    t = now_ms()

    def ctx_for(rule_parts, vars_):
        c = {"auth": _Obj(auth) if auth else None, "now": t,
             "data": Snap(old_tree, rule_parts), "newData": Snap(new_tree, rule_parts),
             "root": Snap(old_tree, []), "newRoot": Snap(new_tree, [])}
        for k, v in vars_.items():
            c["_v_" + k[1:]] = JsStr(v)
        return c

    rules = RULES.get("rules", {})
    node = rules
    vars_ = {}
    granted = False

    def step(node, key):
        if key in node:
            return node[key], None
        for k in node:
            if k.startswith("$"):
                return node[k], k
        return None, None

    depth = []
    if ".write" in node and eval_rule(node[".write"], ctx_for([], vars_)):
        granted = True
    for p in parts:
        nxt, var = step(node, p) if isinstance(node, dict) else (None, None)
        depth.append(p)
        if var:
            vars_[var] = p
        if nxt is None:
            node = None
            break
        node = nxt
        if not granted and ".write" in node and eval_rule(node[".write"], ctx_for(list(depth), vars_)):
            granted = True
    if not granted:
        # Daha derin düğümlerde izin olabilir (ör. çok yollu PATCH yerine tek yazma).
        if node is not None and isinstance(node, dict):
            granted = _deep_grant(node, list(depth), dict(vars_), get_at(new_tree, depth), ctx_for, old_tree)
        if not granted:
            return False
    # .validate
    return _validate(rules, [], {}, new_tree, old_tree, ctx_for, parts)


def _deep_grant(node, base, vars_, newval, ctx_for, old_tree):
    """Yazılan her yaprak altındaki .write kuralı izin veriyorsa kabul (Firebase'in
    kademeli kuralına uygun: üst izin vermiyorsa alttaki her değişiklik izinli olmalı)."""
    oldval = get_at(old_tree, base)
    keys = set()
    if isinstance(newval, dict):
        keys |= set(newval.keys())
    if isinstance(oldval, dict):
        keys |= set(oldval.keys())
    if not keys:
        return False
    for k in keys:
        nv = newval.get(k) if isinstance(newval, dict) else None
        ov = oldval.get(k) if isinstance(oldval, dict) else None
        if nv == ov:
            continue
        child, var = (node[k], None) if k in node else next(((node[x], x) for x in node if x.startswith("$")), (None, None))
        if child is None:
            return False
        v2 = dict(vars_)
        if var:
            v2[var] = k
        if ".write" in child and eval_rule(child[".write"], ctx_for(base + [k], v2)):
            continue
        if not isinstance(child, dict) or not _deep_grant(child, base + [k], v2, nv, ctx_for, old_tree):
            return False
    return True


def _validate(node, path, vars_, new_tree, old_tree, ctx_for, write_parts):
    # Sadece yazılan yolun altındaki/üstündeki düğümleri doğrula.
    if not isinstance(node, dict):
        return True
    n = len(min(path, write_parts, key=len))
    if path[:n] != write_parts[:n]:
        return True
    val = get_at(new_tree, path)
    if ".validate" in node and val is not None and len(path) >= len(write_parts):
        if not eval_rule(node[".validate"], ctx_for(path, vars_)):
            return False
    if not isinstance(val, dict):
        return True
    for k in val:
        child, var = (node[k], None) if k in node else next(((node[x], x) for x in node if x.startswith("$")), (None, None))
        if child is None:
            continue
        v2 = dict(vars_)
        if var:
            v2[var] = k
        if not _validate(child, path + [k], v2, new_tree, old_tree, ctx_for, write_parts):
            return False
    return True


def check_read(uid, parts):
    if RULES is None:
        return True
    auth = {"uid": uid} if uid else None
    node = RULES.get("rules", {})
    depth = []
    vars_ = {}
    if ".read" in node and eval_rule(node[".read"], {"auth": _Obj(auth) if auth else None, "now": now_ms(), "data": Snap(DB, []), "root": Snap(DB, [])}):
        return True
    for p in parts:
        depth.append(p)
        if p in node:
            node = node[p]
        else:
            k = next((x for x in node if x.startswith("$")), None)
            if not k:
                return False
            vars_[k] = p
            node = node[k]
        ctx = {"auth": _Obj(auth) if auth else None, "now": now_ms(), "data": Snap(DB, depth), "root": Snap(DB, [])}
        ctx.update({"_v_" + k[1:]: JsStr(v) for k, v in vars_.items()})
        if ".read" in node and eval_rule(node[".read"], ctx):
            return True
    return False


class _Obj:
    def __init__(self, d):
        self.__dict__.update(d)


# ---------------------------------------------------------------- HTTP

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, obj, extra=None):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)
        STATS["bytes_out"] += len(body)

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(n) if n else b""
        return json.loads(raw) if raw else None

    def _route(self, method):
        global DB
        STATS["requests"] += 1
        if LATENCY:
            time.sleep(LATENCY)
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if u.path.startswith("/v1/accounts:signUp"):
            self._body()
            uid = "u" + uuid.uuid4().hex[:12]
            tok, ref = uuid.uuid4().hex, uuid.uuid4().hex
            TOKENS[tok] = uid
            REFRESH[ref] = uid
            return self._send(200, {"idToken": tok, "refreshToken": ref, "localId": uid, "expiresIn": "3600"})
        if u.path.startswith("/v1/token"):
            b = self._body() or {}
            uid = REFRESH.get(b.get("refresh_token"))
            if not uid:
                return self._send(400, {"error": {"message": "INVALID_REFRESH_TOKEN"}})
            tok = uuid.uuid4().hex
            TOKENS[tok] = uid
            return self._send(200, {"id_token": tok, "refresh_token": b["refresh_token"], "user_id": uid, "expires_in": "3600"})
        if not u.path.endswith(".json"):
            return self._send(404, {"error": "not found"})
        parts = split(u.path[:-5])
        auth = q.get("auth", [""])[0]
        uid = TOKENS.get(auth)
        if auth and not uid:
            return self._send(401, {"error": "Auth token is expired"})

        if method == "GET":
            if not check_read(uid, parts):
                STATS["denied"] += 1
                return self._send(401, {"error": "Permission denied"})
            if "text/event-stream" in (self.headers.get("Accept") or ""):
                return self._stream(parts)
            with LOCK:
                v = get_at(DB, parts)
            extra = {}
            if self.headers.get("X-Firebase-ETag") == "true":
                extra["ETag"] = etag(v)
            return self._send(200, to_client(v), extra)

        body = self._body()
        with LOCK:
            old = DB
            if method == "PUT":
                im = self.headers.get("if-match")
                if im is not None and im != etag(get_at(DB, parts)):
                    return self._send(412, to_client(get_at(DB, parts)), {"ETag": etag(get_at(DB, parts))})
                new = set_at(DB, parts, resolve_sv(body)) or {}
                result = resolve_sv(body)
                changes = [(parts, result)]
            elif method == "PATCH":
                new = DB
                changes = []
                for k, v in (body or {}).items():
                    sub = parts + split(k)
                    new = set_at(new, sub, resolve_sv(v)) or {}
                    changes.append((sub, resolve_sv(v)))
                result = body
            elif method == "POST":
                PUSH_COUNTER[0] += 1
                key = "-N%013d%05d" % (now_ms(), PUSH_COUNTER[0])
                sub = parts + [key]
                new = set_at(DB, sub, resolve_sv(body)) or {}
                result = {"name": key}
                changes = [(sub, resolve_sv(body))]
            elif method == "DELETE":
                new = set_at(DB, parts, None) or {}
                result = None
                changes = [(parts, None)]
            else:
                return self._send(405, {})
            if not all(check_write(uid, c[0], old, new) for c in changes):
                STATS["denied"] += 1
                return self._send(401, {"error": "Permission denied"})
            DB = new
            VERSION[0] += 1
            EVENTS.append((VERSION[0], method, parts, changes))
            del EVENTS[:-500]
            LOCK.notify_all()
        return self._send(200, to_client(result))

    def _stream(self, parts):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Transfer-Encoding", "chunked")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()

        def chunk(text):
            b = text.encode()
            self.wfile.write(b"%x\r\n%s\r\n" % (len(b), b))
            self.wfile.flush()
            STATS["bytes_out"] += len(b)

        try:
            with LOCK:
                seen = VERSION[0]
                v = get_at(DB, parts)
            chunk("event: put\ndata: %s\n\n" % json.dumps({"path": "/", "data": to_client(v)}))
            last_ka = time.time()
            while True:
                with LOCK:
                    LOCK.wait(timeout=1.0)
                    evs = [e for e in EVENTS if e[0] > seen]
                    if evs:
                        seen = evs[-1][0]
                    snap = DB
                out = []
                for _, method, wparts, changes in evs:
                    for cparts, val in changes:
                        n = min(len(cparts), len(parts))
                        if cparts[:n] != parts[:n]:
                            continue
                        if len(cparts) >= len(parts):
                            rel = "/" + "/".join(cparts[len(parts):])
                            out.append(("put", rel, to_client(get_at(snap, cparts))))
                        else:
                            out.append(("put", "/", to_client(get_at(snap, parts))))
                for kind, rel, data in out:
                    chunk("event: %s\ndata: %s\n\n" % (kind, json.dumps({"path": rel, "data": data})))
                if time.time() - last_ka > 10:
                    chunk("event: keep-alive\ndata: null\n\n")
                    last_ka = time.time()
        except (BrokenPipeError, ConnectionResetError, OSError):
            return

    def do_GET(self):
        self._route("GET")

    def do_PUT(self):
        self._route("PUT")

    def do_PATCH(self):
        self._route("PATCH")

    def do_POST(self):
        self._route("POST")

    def do_DELETE(self):
        self._route("DELETE")


EVENTS = []


def etag(v):
    return hashlib.md5(json.dumps(v, sort_keys=True).encode()).hexdigest()


def main():
    global RULES
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9000
    if len(sys.argv) > 2:
        with open(sys.argv[2]) as f:
            RULES = json.load(f)
    srv = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    srv.daemon_threads = True
    print("fake firebase on", port, "rules" if RULES else "no rules", flush=True)

    def dump():
        while True:
            time.sleep(5)
            sys.stdout.write("stats %s\n" % json.dumps(STATS))
            sys.stdout.flush()
    threading.Thread(target=dump, daemon=True).start()
    srv.serve_forever()


if __name__ == "__main__":
    main()
