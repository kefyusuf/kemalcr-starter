# Open-source starter release roadmap

Updated: 2026-10-02. Assessment baseline: `2677f78`.

## Purpose and intended users

Kemalcr is a reusable, self-hosted, multi-tenant API starter for developers building SaaS, commerce, CMS and similar products. The maintainer ships a foundation and reference deployment guidance; consumers operate their own services. This roadmap separates **publishing the starter** from **operating a customer production deployment**.

Keep Crystal, Kemal, PostgreSQL 16, Redis 7 and the modular monolith. The shared kernel owns identity, tenant context, authorization, errors, idempotency, audit and reliable event contracts. Infrastructure supplies technology adapters; business modules remain independently extensible. Service splitting, another database engine and an external broker are not prerequisites.

Products is a CRUD module example, and billing is an optional adapter integration. A full commerce product would need orders, inventory, payment/refund state and fulfillment. A CMS would need publishing, revisions and media. Those workflows belong to consumer domain modules. Enterprise SSO/SCIM, custom roles and sophisticated metered billing are optional extensions driven by adopters' needs.

## Evidence and research basis

On 2026-10-02 the complete existing suite passed in an isolated Docker environment: **172 examples, 0 failures, 0 errors, 0 pending**. Fresh-database migrations, Crystal format checks and OpenAPI YAML parsing passed. A background logging `Channel::ClosedError` was also observed and needs investigation. These results establish a baseline; they do not prove security coverage, OpenAPI conformance, recovery capability or production performance.

This roadmap is informed by primary sources:

- [AWS SaaS tenant isolation](https://docs.aws.amazon.com/whitepapers/latest/saas-architecture-fundamentals/tenant-isolation.html) and [OWASP multi-tenant security](https://cheatsheetseries.owasp.org/cheatsheets/Multi_Tenant_Security_Cheat_Sheet.html): tenant boundaries must hold independently of authentication, including asynchronous flows.
- [OWASP API Security Top 10](https://owasp.org/API-Security/editions/2023/en/0x11-t10/) and [SSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html): verify resource/function authorization, bound consumption, and protect user-configurable outbound destinations.
- [AWS transactional outbox](https://docs.aws.amazon.com/prescriptive-guidance/latest/cloud-design-patterns/transactional-outbox.html): commit business writes and events together, and tolerate duplicate delivery. This design guidance does not require an AWS queue or a stack change.
- [OWASP password recovery](https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html) and [NIST SP 800-63B-4](https://pages.nist.gov/800-63-4/sp800-63b.html): treat recovery, abuse resistance and password policy as explicit security contracts. NIST is a benchmark here, not a statement of legal applicability.
- [Stripe webhooks](https://docs.stripe.com/webhooks) and [idempotent requests](https://docs.stripe.com/api/idempotent_requests): handle duplicate/out-of-order provider events and repeated provider writes safely.
- [Google SRE SLOs](https://sre.google/workbook/implementing-slos/) and [canary releases](https://sre.google/workbook/canarying-releases/): define measurable outcomes and observable, reversible releases.
- [PostgreSQL 16 recovery](https://www.postgresql.org/docs/16/continuous-archiving.html) and [GitLab migration practices](https://docs.gitlab.com/development/database/avoiding_downtime_in_migrations/): design recovery and compatible schema evolution before deployment.
- [OWASP container security](https://cheatsheetseries.owasp.org/cheatsheets/Docker_Security_Cheat_Sheet.html), [secrets management](https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html) and [GitHub deployment OIDC](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-cloud-providers): use least privilege, explicit secrets lifecycle and scoped deployment identities.

The priorities below are project-specific engineering judgments based on those sources and repository inspection. They are not a compliance certification or an implementation-complete claim.

## Comparison with the existing foundation

| Area | Existing building blocks | Work required for the release baseline |
|---|---|---|
| Identity | Registration, JWT sessions, refresh rotation, logout and reset | Shared production password policy, recovery/email reliability, verified enrollment and abuse controls |
| Tenancy and RBAC | Organization context, memberships and service guards | Async tenant boundaries, distinct operator privileges and consistent role-policy semantics |
| API keys | Hashing, expiry checks, revocation and organization reads | Documented machine permissions, key lifecycle and quotas |
| Events | Outbox tables, publisher, retries and dead letters | Transactional producers, atomic claims, replay-safe consumers and tested shutdown |
| Idempotency | Redis locks and durable response records | Crash/lease recovery, atomic outcome recording and retention |
| Webhooks | HMAC, timeouts and a delivery ledger | Tenant isolation, production egress policy, replay guidance and delivery-failure isolation |
| Billing | Checkout adapter and signature verification | Provider mappings, deduplication, idempotency, reconciliation and entitlement state before paid use |
| Contracts and CI | OpenAPI, request/repository/integration specs and image smoke | Full-suite discovery, semantic contract validation and migrated-runtime readiness smoke |
| Deployment | Image, migration CLI, health/version and basic logs | Least privilege, safe migration workflow, restore/rollback drills and actionable operational signals |
| Open-source lifecycle | MIT license, README, examples and changelog | Contribution/security policies, support matrix, compatibility rules and repeatable release artifacts |

## Priorities and dependencies

**P0** blocks claiming that an affected capability is safe for untrusted multi-tenant use. **P1** is required for the next hardened starter release or its production reference path. **P2** is optional or adopter-driven. Optional integrations can be disabled in the supported release configuration until their own gates pass; their maturity must be documented.

| Phase | Priority | Depends on | Outcome |
|---|---|---|---|
| R0: scope and verified baseline | P1 | None | Record intended use, evidence, capability maturity and the active roadmap |
| R1: tenant and operator boundaries | P0 | R0 | Prove tenant-owned delivery, privileged operations and safe outbound access |
| R2: state and event reliability | P0 | R1 | Prove transactional writes, atomic claiming, replay safety and crash recovery |
| R3: identity and API safety | P1 | R1, R2 | Make enrollment, recovery, credentials and request limits production-minded |
| R4: release gates and reference deployment | P1 | R2, R3 | Build, verify, migrate, observe, restore and roll back a repeatable release |
| R5: open-source release and adoption | P1 | R4 | Publish a documented, supported artifact and validate the clean-user journey |
| R6: adopter-driven extensions | P2 / conditional | Relevant earlier gates | Complete selected billing/domain/enterprise features based on real demand |

These phases are planned. Passing the existing suite does not complete R1-R5. No calendar estimate is committed before the detailed implementation plans and environment choices exist.

## Phase requirements and acceptance gates

### R0 — Scope and verified baseline

- **BASE-01:** Maintain an endpoint/capability inventory and distinguish implemented, experimentally integrated, verified and production-reference-supported behavior.
- **BASE-02:** Preserve historical planning records and record the current commit, test command/results and known diagnostic output.
- **BASE-03:** Separate public starter release criteria from consumer go-live criteria. Record the default/optional module configuration intended for the hardened release.

Exit: the active roadmap is reviewable, old completion claims are not treated as current verification, and the next implementation work package is explicit.

### R1 — Tenant and operator boundaries

- **SEC-01:** Carry explicit tenant ownership through event production, persistence, retries and webhook selection. Unknown/global ownership must fail closed for tenant delivery; explicitly authorized mappings are the exception.
- **SEC-02:** Separate organization administration from platform operations. Define privileged access for global event/RBAC management, including private ingress and strong operator authentication.
- **SEC-03:** Protect configurable webhook destinations against private/link-local/metadata destinations, IPv4/IPv6 variants, DNS changes and redirect bypasses. Require production HTTPS and network egress controls; allow local test receivers only through an explicit test policy.

Exit: two-organization tests prove that one tenant's events cannot reach another tenant's endpoint, including wildcard/retry paths; anonymous and ordinary-user negative authorization tests pass; outbound destination defenses have regression coverage.

### R2 — State and event reliability

- **REL-01:** Put every promised domain event and its business mutation in the same PostgreSQL transaction; verify all service wiring, including API-key events.
- **REL-02:** Claim pending events atomically. Define lease/reclaim behavior for concurrency, slow receivers and process failure before supporting multiple publishers.
- **REL-03:** Make local consumer effects and deduplication atomic per handler. An already-successful handler must tolerate retry when a later handler fails.
- **REL-04:** Define crash-safe idempotency completion, stale-request recovery, lease ownership and bounded replay retention. Avoid duplicate committed writes across restart/retry.
- **REL-05:** Test SIGTERM handling, publisher/subscriber shutdown and in-flight drain or durable recovery within the termination budget.
- **REL-06:** Propagate request correlation and tenant attribution to events. Document internal ordering and external delivery guarantees; do not promise exactly-once network delivery.

Exit: rollback injection, concurrent claim, replay-after-side-effect, restart-after-write and termination tests pass. Slow external receivers do not invalidate the lease assumptions or stall unrelated work without a documented bound.

### R3 — Identity and API safety

- **AUTH-01:** Reject unsafe production configuration and placeholder secrets at startup. Document secret/key rotation, compatibility and session impact.
- **AUTH-02:** Unify registration/reset policy, support long passphrases and compromised-password checks, and choose a benchmarked hashing policy with a compatible migration path. Evaluate NIST's 15-character password-only baseline and removal of mandatory composition rules; verify there is no silent truncation.
- **AUTH-03:** Define verified-email or controlled invitation onboarding. Make reset requests consistent in response/timing and tokens atomically single-use; deliver email reliably with transport security and protected token handling.
- **AUTH-04:** Use independent account/IP/tenant/key abuse controls and trusted-proxy rules. Define Redis-outage behavior. Apply bounded bodies, integration responses, pagination and consistent validation/errors.
- **AUTH-05:** Make role-management semantics match authorization enforcement. Document machine-key permissions, expiry/revocation/rotation and supported machine operations.

Exit: negative auth/tenant tests, reset concurrency, provider failure and abusive-input tests pass. Production operator access has a strong-authentication boundary; enterprise end-user SSO remains optional.

### R4 — Release gates and reference deployment

- **DEL-01:** Discover and run the full spec suite in CI, plus canonical formatting and semantic OpenAPI validation. Test critical route/request/response/security contracts; YAML parsing alone is not enough. [OpenAPI 3.1](https://spec.openapis.org/oas/v3.1.0.html).
- **DEL-02:** Build once; promote immutable artifacts with version/commit metadata. Scan dependencies/images, record dispositions, use a non-root runtime and publish supported runtime versions and upgrade guidance.
- **DEL-03:** Runtime smoke must migrate a fresh database and verify readiness plus an authenticated synthetic journey. Define readiness HTTP status and degraded dependency behavior.
- **DEL-04:** Separate migration/application identities, serialize migrations and rehearse old/new binary compatibility. Prefer additive changes before removals; avoid blind destructive down-migration rollback.
- **OPS-01:** Provide a minimal production reference topology with TLS, private PostgreSQL/Redis, distinct environments/secrets and restricted operations access. A hardened single-host example is acceptable with its availability limits documented; Kubernetes is optional.
- **OPS-02:** Define request success/latency and event-lag indicators, alerts and incident ownership. Measure queue age, retries, dead letters, pool pressure and integration failures; avoid unbounded metric labels.
- **OPS-03:** Provide backup/restore and rollback runbooks and execute drills in a reference environment. Measure RPO/RTO; retention/export/deletion policy is chosen by adopters based on their data and obligations.
- **OPS-04:** Load/failure-test representative auth/CRUD/event workloads, slow receivers and dependency restarts. Investigate the observed logging-channel diagnostic before the reference path is declared clean.

Exit: full CI and contract gates pass; the exact runtime artifact succeeds on a clean reference deployment; restore and rollback evidence exists; capacity and operational limitations are documented.

### R5 — Open-source release and adoption

- **OSS-01:** Add contribution guidance for module boundaries, Crystal conventions, TDD and local Docker checks; add a code of conduct and a private vulnerability-reporting policy with a realistic maintainer response process.
- **OSS-02:** Publish support/compatibility expectations, module maturity, API/webhook versioning rules, deprecation guidance and a release checklist. Keep changelog links consistent with tags that actually exist.
- **OSS-03:** Publish a tagged release and versioned image only after gates pass; provide reproducible build instructions and artifact identity. Documentation publication does not itself authorize a release.
- **OSS-04:** Test the clean-user quickstart and module tutorial from the release artifact. Add issue/PR templates and a dependency-update/release-maintenance cadence that maintainers can sustain.
- **OSS-05:** Collect adopter feedback and prioritize demonstrated problems before expanding the shared kernel.

Exit: another developer can start, test and extend the starter from the documented release; knows what is supported and how to report bugs privately; can follow the reference deployment without guessing unsafe defaults.

### R6 — Conditional extensions

Paid billing requires durable organization/customer/subscription mapping, provider idempotency, inbound deduplication, out-of-order reconciliation and entitlement state before enabling charges. Complete provider sandbox lifecycle tests first. SSO/SCIM, custom roles, usage metering, full product workflows and higher availability are separate modules/work packages justified by adopter demand. Evaluate PostgreSQL RLS as additional defense only with pool-context and role-bypass tests; it is not a substitute for application tenant scoping. [PostgreSQL RLS](https://www.postgresql.org/docs/16/ddl-rowsecurity.html).

## Consumer go-live path

Consumers select region, budget, enrollment, enabled integrations, data policy, availability/recovery targets and the operator responsible for incidents. A starter cannot promise a universal SLA or legal compliance on their behalf.

1. Finish the relevant module gates and freeze the intended API contract; keep unfinished optional billing disabled.
2. Build/scan a release artifact and deploy it to a staging environment with separate data/secrets.
3. Run serialized compatible migrations and synthetic tenant journeys; verify negative isolation cases and observable event processing.
4. Complete representative load/dependency-failure tests and measured restore/rollback drills. Select feasible SLO/RPO/RTO targets from business tolerances and capacity.
5. Promote the same image digest to production; terminate TLS at trusted ingress and keep DB/Redis and operational routes private.
6. Verify migration completion, readiness, version and an authenticated synthetic flow before admitting a small pilot cohort. Use a simple rehearsed blue/green or gradual rollout if suitable for the topology.
7. Watch predefined error/latency/queue-lag abort thresholds. Revert the compatible application artifact on failure; follow the rehearsed data/schema recovery plan.
8. Expand access only after reviewing pilot evidence and confirming alert/incident ownership.

Possible discussion targets, **not measurements or promised SLAs**: 99.9% successful-request availability, p95 below 300 ms for agreed ordinary CRUD at the measured load, event-to-first-attempt p95 below 5 seconds excluding receiver outages, RPO up to 15 minutes and RTO up to 60 minutes. Consumers must revise these if their deployment/budget cannot demonstrate them. Define request inclusion, measurement window and external dependency exclusions before using them.

## Execution policy and next work package

For each code behavior change: create a focused branch, write the regression/spec, observe the intended failure (**red**), implement the smallest fix (**green**), refactor while green, run the full suite and relevant release checks, commit, then open a PR with the failure/pass evidence. Merge and deployment are separate decisions. Documentation changes use content/link/diff verification rather than artificial implementation-mirroring tests.

Start with **R1**: tenant ownership of events, two-organization webhook regression, scoped delivery, and operator-boundary tests. Keep outbound destination protection as the next focused R1 change. Resolve R1 before introducing new public capabilities; R2 follows before scaling publishers or claiming reliable end-to-end events.
