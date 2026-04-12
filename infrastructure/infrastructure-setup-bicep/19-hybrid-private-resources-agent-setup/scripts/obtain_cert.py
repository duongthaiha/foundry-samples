"""
Let's Encrypt certificate obtainer for Azure Key Vault.
Uses the ACME protocol with DNS-01 challenge.
Does NOT require admin rights (unlike certbot on Windows).

Usage:
  python obtain_cert.py --domain agent.belugaconsultant.co.uk --keyvault aiservicescdpy-kv --email admin@belugaconsultant.co.uk
"""
import argparse
import json
import base64
import hashlib
import time
import subprocess
import tempfile
import os
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, ec
import requests

ACME_DIRECTORY = "https://acme-v02.api.letsencrypt.org/directory"

def b64url(data):
    if isinstance(data, str):
        data = data.encode()
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def get_directory():
    return requests.get(ACME_DIRECTORY).json()

def create_account_key():
    return ec.generate_private_key(ec.SECP256R1())

def get_jwk(key):
    pub = key.public_key().public_numbers()
    x_bytes = pub.x.to_bytes(32, "big")
    y_bytes = pub.y.to_bytes(32, "big")
    return {"crv": "P-256", "kty": "EC", "x": b64url(x_bytes), "y": b64url(y_bytes)}

def get_thumbprint(jwk):
    canonical = json.dumps(jwk, sort_keys=True, separators=(",", ":"))
    return b64url(hashlib.sha256(canonical.encode()).digest())

def sign_request(key, url, payload, nonce, kid=None):
    jwk = get_jwk(key)
    protected = {"alg": "ES256", "nonce": nonce, "url": url}
    if kid:
        protected["kid"] = kid
    else:
        protected["jwk"] = jwk
    
    protected_b64 = b64url(json.dumps(protected))
    if payload is None:
        payload_b64 = ""
    elif payload == "":
        payload_b64 = ""
    else:
        payload_b64 = b64url(json.dumps(payload))
    
    signing_input = f"{protected_b64}.{payload_b64}".encode()
    from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
    sig_der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(sig_der)
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    
    return {
        "protected": protected_b64,
        "payload": payload_b64,
        "signature": b64url(sig)
    }

def acme_request(url, key, payload, nonce, kid=None):
    body = sign_request(key, url, payload, nonce, kid)
    resp = requests.post(url, json=body, headers={"Content-Type": "application/jose+json"})
    return resp, resp.headers.get("Replay-Nonce")

def main():
    parser = argparse.ArgumentParser(description="Obtain Let's Encrypt cert for Azure Key Vault")
    parser.add_argument("--domain", required=True, help="Domain (e.g., agent.belugaconsultant.co.uk)")
    parser.add_argument("--keyvault", required=True, help="Azure Key Vault name")
    parser.add_argument("--certname", default="teams-bot-tls", help="Certificate name in Key Vault")
    parser.add_argument("--email", required=True, help="Email for Let's Encrypt")
    args = parser.parse_args()

    print("=" * 60)
    print(" Let's Encrypt Certificate for Azure Key Vault")
    print("=" * 60)
    print(f"  Domain:    {args.domain}")
    print(f"  Key Vault: {args.keyvault}")
    print(f"  Email:     {args.email}")
    print()

    # Step 1: Get ACME directory
    print("[1/7] Fetching ACME directory...")
    directory = get_directory()
    nonce = requests.head(directory["newNonce"]).headers["Replay-Nonce"]

    # Step 2: Create account
    print("[2/7] Creating ACME account...")
    account_key = create_account_key()
    resp, nonce = acme_request(directory["newAccount"], account_key,
        {"termsOfServiceAgreed": True, "contact": [f"mailto:{args.email}"]}, nonce)
    if resp.status_code not in (200, 201):
        print(f"  Failed to create account: {resp.text}")
        return
    kid = resp.headers["Location"]
    print(f"  Account created: {kid[:50]}...")

    # Step 3: Create order
    print("[3/7] Creating certificate order...")
    resp, nonce = acme_request(directory["newOrder"], account_key,
        {"identifiers": [{"type": "dns", "value": args.domain}]}, nonce, kid)
    if resp.status_code != 201:
        print(f"  Failed: {resp.text}")
        return
    order = resp.json()
    order_url = resp.headers["Location"]

    # Step 4: Get DNS-01 challenge
    print("[4/7] Getting DNS-01 challenge...")
    auth_url = order["authorizations"][0]
    resp, nonce = acme_request(auth_url, account_key, "", nonce, kid)
    auth = resp.json()
    
    dns_challenge = None
    for ch in auth["challenges"]:
        if ch["type"] == "dns-01":
            dns_challenge = ch
            break
    
    if not dns_challenge:
        print("  No DNS-01 challenge available!")
        return

    token = dns_challenge["token"]
    thumbprint = get_thumbprint(get_jwk(account_key))
    key_auth = f"{token}.{thumbprint}"
    txt_value = b64url(hashlib.sha256(key_auth.encode()).digest())

    print()
    print("=" * 60)
    print("  ACTION REQUIRED: Create DNS TXT record at IONOS")
    print("=" * 60)
    print()
    print(f"  Record Type: TXT")
    print(f"  Host:        _acme-challenge.agent")
    print(f"  Value:       {txt_value}")
    print(f"  TTL:         300")
    print()
    print("  Go to: https://my.ionos.co.uk/domains")
    print()
    input("  Press ENTER after creating the TXT record and waiting ~2 minutes...")

    # Verify DNS
    print("  Verifying DNS propagation...")
    for attempt in range(6):
        try:
            import subprocess as sp
            result = sp.run(["nslookup", "-type=TXT", f"_acme-challenge.{args.domain}"], 
                          capture_output=True, text=True, timeout=10)
            if txt_value in result.stdout:
                print(f"  DNS verified!")
                break
        except:
            pass
        if attempt < 5:
            print(f"  Not found yet, waiting 30s... (attempt {attempt+1}/6)")
            time.sleep(30)
    
    # Step 5: Respond to challenge
    print("[5/7] Responding to challenge...")
    resp, nonce = acme_request(dns_challenge["url"], account_key, {}, nonce, kid)
    
    # Wait for validation
    for _ in range(10):
        time.sleep(5)
        resp, nonce = acme_request(auth_url, account_key, "", nonce, kid)
        status = resp.json()["status"]
        print(f"  Status: {status}")
        if status == "valid":
            break
        if status == "invalid":
            print(f"  Challenge failed: {resp.json()}")
            return

    # Step 6: Finalize order with CSR
    print("[6/7] Finalizing order...")
    cert_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    csr = x509.CertificateSigningRequestBuilder().subject_name(
        x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, args.domain)])
    ).add_extension(
        x509.SubjectAlternativeName([x509.DNSName(args.domain)]), critical=False
    ).sign(cert_key, hashes.SHA256())
    
    csr_der = csr.public_bytes(serialization.Encoding.DER)
    resp, nonce = acme_request(order["finalize"], account_key,
        {"csr": b64url(csr_der)}, nonce, kid)
    
    # Wait for cert
    for _ in range(10):
        time.sleep(3)
        resp, nonce = acme_request(order_url, account_key, "", nonce, kid)
        order_status = resp.json()
        if order_status["status"] == "valid":
            break

    # Download cert
    cert_url = order_status.get("certificate")
    if not cert_url:
        print("  No certificate URL in order!")
        return
    resp, nonce = acme_request(cert_url, account_key, "", nonce, kid)
    cert_pem = resp.text

    # Step 7: Create PFX and import to Key Vault
    print("[7/7] Importing to Azure Key Vault...")
    
    key_pem = cert_key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.TraditionalOpenSSL,
        serialization.NoEncryption()
    )
    
    with tempfile.NamedTemporaryFile(suffix=".pem", delete=False, mode="w") as f:
        f.write(cert_pem)
        f.write(key_pem.decode())
        combined_path = f.name
    
    pfx_path = combined_path.replace(".pem", ".pfx")
    pfx_pass = "TempPass123!"
    
    os.system(f'openssl pkcs12 -export -out "{pfx_path}" -in "{combined_path}" -password pass:{pfx_pass}')
    
    result = subprocess.run([
        "az", "keyvault", "certificate", "import",
        "--vault-name", args.keyvault,
        "--name", args.certname,
        "--file", pfx_path,
        "--password", pfx_pass,
        "-o", "json"
    ], capture_output=True, text=True)
    
    os.unlink(combined_path)
    os.unlink(pfx_path)
    
    if result.returncode == 0:
        cert_info = json.loads(result.stdout)
        print()
        print("=" * 60)
        print("  SUCCESS!")
        print("=" * 60)
        print(f"  Certificate imported to: {args.keyvault}/{args.certname}")
        print(f"  Domain: {args.domain}")
        print()
        print("  Next steps:")
        print("  - App Gateway will auto-pick up the new cert from Key Vault")
        print("  - You can delete the _acme-challenge TXT record from IONOS")
        print("  - Certificate expires in 90 days — re-run to renew")
    else:
        print(f"  Failed to import: {result.stderr}")

if __name__ == "__main__":
    main()
