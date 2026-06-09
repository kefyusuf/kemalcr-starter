# Architecture Overview

## Goal

This project is a reusable API-first backend foundation built with Kemal and Crystal.

It is designed to support multiple future product layers without rewriting the platform core. The same base should be able to host e-commerce, CMS, and SaaS modules later.

## Structure

The architecture follows a modular monolith model.

### Platform Core

The platform core contains cross-domain capabilities:

- configuration
- request lifecycle handling
- request IDs
- structured errors
- security defaults
- bearer and API key authentication hooks
- idempotency execution
- auth throttling integration

### Foundation Modules

The current foundation module set includes:

- identity
- organizations
- API keys

Identity currently covers:

- login
- refresh rotation
- logout and logout-all
- current actor lookup
- active organization switching

Organizations currently cover:

- tenant-aware organization CRUD
- active membership listing
- invitation create, list, accept, and revoke

API keys currently cover:

- key create, list, and revoke
- one-time secret reveal
- organization-scoped machine authentication for selected read endpoints

### Infrastructure

Infrastructure adapters will provide:

- PostgreSQL access
- Redis access
- JWT signing and verification
- password hashing
- runtime migration support
- Docker build and release image support

## Runtime Model

The project is Docker-first.

The local and CI stack includes:

- app
- PostgreSQL
- Redis

The deployment model remains a single service image with explicit internal module boundaries. The runtime image now contains both the application binary and the migration binary.

## Contract-First Direction

OpenAPI is the source of truth.

The application exposes `/openapi`, and the contract in `openapi/openapi.yaml` continues to evolve ahead of route implementation.

## Request Flow

The default request pipeline is:

1. request context initialization and request ID propagation
2. standardized API error handling
3. bearer JWT or API key authentication
4. security response headers
5. route-level business logic

Write safety features stay explicit at the route or service layer instead of being hidden inside global middleware. Idempotency is applied only to selected POST endpoints, and auth throttling is applied only to login and refresh.

## Current Status

The repository currently includes:

- system endpoints
- a tenant-aware identity and organization foundation
- selected idempotent write flows
- API key management and first machine-authenticated reads
- release metadata, CI validation, deployment guidance, and runtime smoke validation

The foundation is now close to a production-minded starter baseline, with the main remaining work centered around future product modules and platform-specific deployment manifests.
