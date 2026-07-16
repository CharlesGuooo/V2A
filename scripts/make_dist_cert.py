#!/usr/bin/env python3
"""Create a new Apple Distribution certificate from a local CSR via App Store
Connect API, writing the resulting cert (DER) to build/certs/dist.cer.

If the account is at the distribution-cert limit, revokes existing DISTRIBUTION
certs whose name matches "Apple Distribution" and retries once.
"""
import base64, json, time, os, sys, urllib.request, urllib.error, urllib.parse
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, utils

KEY_ID   = os.environ.get("ASC_KEY_ID", "")
ISSUER   = os.environ.get("ASC_ISSUER_ID", "")
KEY_PATH = os.path.expanduser(
    os.environ.get("ASC_KEY_PATH", f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"))
assert KEY_ID and ISSUER, "Set ASC_KEY_ID and ASC_ISSUER_ID env vars (App Store Connect API key)."
CSR_PATH = "build/certs/dist.csr"
CER_OUT  = "build/certs/dist.cer"
API = "https://api.appstoreconnect.apple.com"

def b64url(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()

def make_jwt():
    with open(KEY_PATH, "rb") as f:
        key = serialization.load_pem_private_key(f.read(), password=None)
    header = {"alg": "ES256", "kid": KEY_ID, "typ": "JWT"}
    now = int(time.time())
    payload = {"iss": ISSUER, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    si = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}".encode()
    der = key.sign(si, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der)
    return f"{si.decode()}.{b64url(r.to_bytes(32,'big')+s.to_bytes(32,'big'))}"

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
        return {"__error__": e.code, "__body__": e.read().decode()}

def create_cert(token, csr):
    body = {"data": {"type": "certificates",
            "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr}}}
    return api("POST", "/v1/certificates", token, body)

def main():
    token = make_jwt()
    csr = open(CSR_PATH).read()

    r = create_cert(token, csr)
    if "__error__" in r:
        # Likely at the cert limit — revoke existing DISTRIBUTION certs and retry.
        print(f"create failed ({r['__error__']}), trying to free a slot…", file=sys.stderr)
        lst = api("GET", "/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=200", token)
        for d in lst.get("data", []):
            cid = d["id"]; nm = d["attributes"].get("name","")
            api("DELETE", f"/v1/certificates/{cid}", token)
            print(f"revoked old distribution cert {cid} ({nm})", file=sys.stderr)
        r = create_cert(token, csr)
    if "__error__" in r:
        print(f"cert creation failed: {r['__error__']}\n{r['__body__']}", file=sys.stderr)
        sys.exit(1)

    attrs = r["data"]["attributes"]
    der = base64.b64decode(attrs["certificateContent"])
    with open(CER_OUT, "wb") as f:
        f.write(der)
    print(f"CERT_ID={r['data']['id']}")
    print(f"CERT_NAME={attrs.get('name','')}")
    print(f"wrote {CER_OUT}")

if __name__ == "__main__":
    main()
