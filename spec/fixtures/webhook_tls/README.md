# Local webhook TLS fixture

The committed key is intentionally public, test-only material. Never use it for a deployed endpoint or CA. The self-signed certificate has a `localhost` DNS SAN and is valid until 2036. Tests temporarily trust it through `SSL_CERT_FILE`; production keeps the platform trust store and peer/hostname verification enabled.

Regenerate before expiry with an OpenSSL CLI and keep the SAN aligned with the tests. The fixture permits deterministic HTTPS transport tests without external DNS or Internet access.
