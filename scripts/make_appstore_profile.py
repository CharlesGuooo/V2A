#!/usr/bin/env python3
"""Create an iOS App Store provisioning profile via App Store Connect API.

Uses an App Store Connect API key (.p8) to:
  1. Look up the bundle ID resource for com.charlesgxy.v2a
  2. Find the Apple Distribution certificate
  3. Create an IOS_APP_STORE profile bound to that bundle + cert
  4. Download it to the local Provisioning Profiles folder

Prints the installed profile's name + UUID on success.
"""
import base64, json, time, os, sys, urllib.request, urllib.error
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_ID   = os.environ.get("ASC_KEY_ID", "")
ISSUER   = os.environ.get("ASC_ISSUER_ID", "")
KEY_PATH = os.path.expanduser(
    os.environ.get("ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"))
assert KEY_ID and ISSUER, "Set ASC_KEY_ID and ASC_ISSUER_ID env vars (App Store Connect API key)."
BUNDLE   = "com.charlesgxy.v2a"
PROFILE_NAME = "V2A App Store (api)"

API = "https://api.appstoreconnect.apple.com"

def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def make_jwt() -> str:
    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}".encode()
    der_sig = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_sig)
    raw_sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{signing_input.decode()}.{b64url(raw_sig)}"

def api(method, path, token, body=None):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            raw = resp.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on {method} {path}:\n{e.read().decode()}", file=sys.stderr)
        raise

def main():
    token = make_jwt()

    # 1. Bundle ID resource
    r = api("GET", f"/v1/bundleIds?filter[identifier]={BUNDLE}&limit=200", token)
    bundle_id = next((d["id"] for d in r["data"] if d["attributes"]["identifier"] == BUNDLE), None)
    if not bundle_id:
        print(f"Bundle ID {BUNDLE} not found in account", file=sys.stderr); sys.exit(1)
    print(f"bundleId resource: {bundle_id}")

    # 2. Distribution certificate
    r = api("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200", token)
    if not r["data"]:
        print("No DISTRIBUTION certificate in account", file=sys.stderr); sys.exit(1)
    want = os.environ.get("CERT_ID")
    chosen = next((d for d in r["data"] if d["id"] == want), None) if want else r["data"][0]
    if chosen is None:
        chosen = r["data"][0]
    cert_id = chosen["id"]
    print(f"distribution cert: {cert_id} ({chosen['attributes'].get('name','')})")

    # 3. Delete any stale profile with our name, then create fresh
    r = api("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(PROFILE_NAME)}&limit=200", token)
    for d in r.get("data", []):
        if d["attributes"]["name"] == PROFILE_NAME:
            api("DELETE", f"/v1/profiles/{d['id']}", token)
            print(f"deleted stale profile {d['id']}")

    body = {
        "data": {
            "type": "profiles",
            "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    }
    r = api("POST", "/v1/profiles", token, body)
    attrs = r["data"]["attributes"]
    content = base64.b64decode(attrs["profileContent"])
    uuid = attrs["uuid"]

    dest_dir = os.path.expanduser("~/Library/MobileDevice/Provisioning Profiles")
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, f"{uuid}.mobileprovision")
    with open(dest, "wb") as f:
        f.write(content)
    print(f"PROFILE_NAME={PROFILE_NAME}")
    print(f"PROFILE_UUID={uuid}")
    print(f"installed: {dest}")

import urllib.parse
if __name__ == "__main__":
    main()
