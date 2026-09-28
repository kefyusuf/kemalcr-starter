# Examples

Runnable scripts against a local stack. Start the API first:

```sh
./scripts/dev
```

All scripts accept an optional base URL (default `http://localhost:3000`).

## Golden path

| Script | What it shows |
|--------|----------------|
| [`smoke.sh`](smoke.sh) | End-to-end smoke: health → register → org → product → webhook → password reset |
| [`01-auth-and-org.sh`](01-auth-and-org.sh) | Register, `/v1/me`, organization, memberships, login |
| [`02-products-and-webhooks.sh`](02-products-and-webhooks.sh) | Product CRUD, webhook endpoint + delivery list |

```sh
./examples/smoke.sh
./examples/01-auth-and-org.sh
./examples/02-products-and-webhooks.sh http://localhost:3000
```

Requires `bash` and `curl`. Tokens are parsed from JSON with `sed` so the scripts stay dependency-free.

## Tips

- Password policy: min 8 chars, at least one uppercase, one lowercase, one digit
- Webhook secrets are returned **once** at creation
- `Idempotency-Key` is supported on selected POST endpoints (org create, invitation create, auth refresh, API key create)
