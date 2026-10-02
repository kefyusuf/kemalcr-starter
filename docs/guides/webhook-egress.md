# Webhook egress protection

Webhook registration accepts HTTPS URLs on port 443. Credentials, fragments, invalid or ambiguous numeric hosts, single-label hosts, trailing DNS dots and nonstandard ports are rejected. IPv4/IPv6 literals must satisfy the same address policy used during delivery. Registration checks syntax and literal addresses without resolving domain names; a registered domain is not a guarantee of future deliverability.

Before every outbound attempt, the app resolves the hostname and validates every returned address. Empty or failed resolution and any unsafe answer fail the attempt. The TCP connection uses a selected validated `Socket::IPAddress` directly, with no second hostname lookup. The original hostname remains in the Host header and TLS SNI/certificate validation. TLS uses peer verification and the runtime CA trust store. Redirects are treated as failures and are not followed.

The policy rejects loopback, private, link-local, unspecified, carrier-grade NAT, documentation, benchmark, multicast and reserved IPv4 ranges. IPv4-mapped IPv6 is rejected by default; IPv6 is restricted to global-unicast space with conservative exclusions for special-purpose, documentation and transition prefixes. The Azure platform virtual address `168.63.129.16` is also rejected. These rules intentionally exclude some special-purpose addresses even where a registry marks an individual exception globally reachable. Review the policy when special-purpose address assignments change.

Delivery reads HTTP status and bounded headers, then closes the connection without buffering or decompressing the response body. Only 2xx is success. TCP connect timeout is five seconds; read/write inactivity timeouts are ten seconds, including TLS handshake IO. These are not a total delivery deadline. Linux system DNS resolution is synchronous and is not bounded by the TCP connect timeout.

## Local tests

Set `WEBHOOK_ALLOW_TEST_LOOPBACK=true` only with `KEMAL_ENV=test`, or inject equivalent Settings in a spec. Both conditions are required. This permits local loopback HTTP/HTTPS and ephemeral ports, preserving TLS verification for HTTPS. It never permits RFC1918 or metadata destinations, and setting the option in production has no effect. The example configuration defaults to false.

Existing delivery integration specs explicitly enable the test option. Tests simulate DNS records through an injected resolver while using real local TCP/HTTP/TLS receivers. The committed localhost TLS key is public test material; it is not a production credential.

## Upgrade and deployment

No database migration is needed. Existing endpoints using HTTP, private destinations or nonstandard ports will fail registration or delivery after upgrade; move clients to a public HTTPS endpoint on port 443. Stored URLs are checked on delivery, so legacy records receive the same protection. Failures remain in the delivery ledger and follow the existing outbox retry/dead-letter flow. This package does not change its reliability semantics or tenant selection.

Deploy with the default false test option and a current CA bundle; the runtime Docker image installs `ca-certificates`. Replace every old app/publisher process. Rolling back restores the previous unrestricted outbound behavior; keep network restrictions during rollback.

Application filtering does not establish your network's routing policy. Restrict workload egress to approved public HTTPS destinations, block internal/metadata/platform ranges at the network layer, use a controlled DNS resolver, and include DNS/slow-header resource limits in your operational setup. Public addresses routed internally by custom networks require deployment-specific deny rules or allowlists. Do not assume this change configures an orchestrator firewall or a total DNS/request deadline.

The approach follows [OWASP SSRF prevention](https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html). Address policy references: [IANA IPv4 special-purpose registry](https://www.iana.org/assignments/iana-ipv4-special-registry/), [IANA IPv6 special-purpose registry](https://www.iana.org/assignments/iana-ipv6-special-registry/) and [Azure platform virtual address](https://learn.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16).
