# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-28

### Added
- Multi-tenant identity: register, login, refresh rotation with reuse detection, logout
- Organizations, memberships, invitations, API keys
- RBAC (owner / admin / member) with data-driven role-permission mappings
- Idempotent writes (`Idempotency-Key`) on selected POST endpoints
- Outbox event system: publisher fiber, retry/backoff, dead-letter queue, Redis wake-up
- Password reset (request/confirm) with pluggable email adapter (`console` / `smtp`)
- Outbound webhooks with HMAC-SHA256 signatures and delivery ledger
- Products module as the plug-and-play domain template
- Billing adapter port (`null` / `stripe`) and Stripe signature-verified webhook receiver
- OpenAPI 3.1.0 contract, Docker-first dev/prod images, GitHub Actions CI
- Example scripts under `examples/`

[Unreleased]: https://github.com/kefyusuf/kemalcr-starter/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kefyusuf/kemalcr-starter/releases/tag/v0.1.0
