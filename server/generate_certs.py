#!/usr/bin/env python3
"""Генерация self-signed сертификата для WSS (LAN / свой сервер)."""
from pathlib import Path
import subprocess
import sys

DIR = Path(__file__).resolve().parent / "certs"
DIR.mkdir(parents=True, exist_ok=True)
cert = DIR / "cert.pem"
key = DIR / "key.pem"

if cert.exists() and key.exists():
    print(f"Уже есть:\n  {cert}\n  {key}")
    print("Удалите их, если нужно пересоздать.")
    sys.exit(0)

# 1) openssl
try:
    subprocess.check_call([
        "openssl", "req", "-x509", "-newkey", "rsa:2048",
        "-keyout", str(key),
        "-out", str(cert),
        "-days", "3650",
        "-nodes",
        "-subj", "/CN=veniamin/O=Veniamin/C=RU",
    ])
    print(f"OK (openssl):\n  {cert}\n  {key}")
    sys.exit(0)
except (FileNotFoundError, subprocess.CalledProcessError):
    pass

# 2) cryptography
try:
    from cryptography import x509
    from cryptography.x509.oid import NameOID
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    import datetime

    key_obj = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "veniamin"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Veniamin"),
    ])
    cert_obj = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key_obj.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.datetime.utcnow() - datetime.timedelta(days=1))
        .not_valid_after(datetime.datetime.utcnow() + datetime.timedelta(days=3650))
        .add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.DNSName("veniamin.local"),
                x509.IPAddress(__import__("ipaddress").IPv4Address("127.0.0.1")),
            ]),
            critical=False,
        )
        .sign(key_obj, hashes.SHA256())
    )
    key.write_bytes(
        key_obj.private_bytes(
            serialization.Encoding.PEM,
            serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption(),
        )
    )
    cert.write_bytes(cert_obj.public_bytes(serialization.Encoding.PEM))
    print(f"OK (cryptography):\n  {cert}\n  {key}")
    sys.exit(0)
except ImportError:
    print(
        "Нужен openssl в PATH или: pip install cryptography\n"
        "Затем снова: python generate_certs.py"
    )
    sys.exit(1)
