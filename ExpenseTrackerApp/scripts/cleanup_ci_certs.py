#!/usr/bin/env python3
"""Revoke Apple Development certificates that earlier CI builds created.

Every GitHub-hosted Mac is new, so automatic signing creates a fresh development
certificate on each build ("Created via API"). Apple allows only a few, so the
build starts failing with "maximum number of certificates". This removes only
certificates created through the API (CI), never ones made in Xcode on a Mac.
Distribution certificates are never touched.

Usage: cleanup_ci_certs.py <AuthKey.p8> <key id> <issuer id>
"""
import sys, time, json, urllib.request, urllib.error
import jwt  # PyJWT (installed by the workflow)

key_path, key_id, issuer = sys.argv[1:4]
token = jwt.encode(
    {"iss": issuer, "iat": int(time.time()), "exp": int(time.time()) + 600, "aud": "appstoreconnect-v1"},
    open(key_path).read(), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"})
API = "https://api.appstoreconnect.apple.com/v1/certificates"

def call(method, url):
    req = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
        return json.loads(body) if body else {}

certs = call("GET", API + "?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200").get("data", [])
removed = 0
for c in certs:
    a = c.get("attributes", {})
    label = f"{a.get('displayName') or ''} {a.get('name') or ''}".strip()
    if "created via api" not in label.lower():
        print(f"keep    {a.get('certificateType')} {label} (expires {(a.get('expirationDate') or '')[:10]})")
        continue
    try:
        call("DELETE", f"{API}/{c['id']}")
        removed += 1
        print(f"revoked {a.get('certificateType')} {label}")
    except urllib.error.HTTPError as e:
        print(f"could not revoke {c['id']}: {e.code} {e.read()[:200]!r}")
print(f"{removed} CI development certificate(s) revoked, {len(certs) - removed} kept")
