# Platform operator access

Operator routes affect the whole platform, including events and permissions across organizations. Tenant JWTs and tenant API keys do not authorize them. Organization owners and admins are tenant roles, not platform operators.

| Method | Route | Effect |
|---|---|---|
| GET | `/events/metrics` | Publisher statistics |
| GET | `/events/dead-letter` | Global dead-letter metadata |
| POST | `/events/dead-letter/:id/requeue` | Retry a persisted event |
| GET | `/rbac/permissions` | Global permission catalog |
| GET | `/rbac/roles` | Global role permissions |
| POST | `/rbac/roles/seed` | Insert default global role permissions |
| DELETE | `/rbac/roles/:role/permissions/:permission` | Remove a global role permission |

Set `OPERATOR_TOKEN` to a dedicated, randomly generated secret through your deployment secret store. Send the exact value in `X-Operator-Token`; do not reuse `JWT_SECRET`, a tenant token, or an API key. Missing, empty or whitespace-only configuration disables all operator access. Missing, blank or incorrect credentials receive the standard `401 AUTH_UNAUTHORIZED` response before the route reads or changes platform state. Tokens are not trimmed.

For example, after securely providing both environment variables:

```sh
curl --fail "$PLATFORM_URL/events/metrics" \
  -H "X-Operator-Token: $OPERATOR_TOKEN"
```

Use HTTPS and restrict these paths at the ingress to the operations network. Keep this credential out of browser clients, tenant integrations and header logs. Requests use the operator header alone; a supplied invalid tenant `Authorization` or `X-API-Key` credential still fails the existing authentication middleware.

This shared credential grants access to every operator route. It does not provide individual operator identities, separate read/write roles or an operator audit trail. Deployments requiring those controls should add operator identity and authorization through the shared kernel before delegating operations to multiple people. Existing request IDs remain available for correlation; they are not an audit trail.

## Upgrade and rotation

This change requires no database migration. Existing anonymous event diagnostics and tenant-authenticated global RBAC clients will receive 401 after upgrade. Configure the secret and update operations clients before switching them to the new version. Health, readiness, version and OpenAPI routes remain public.

The app loads settings once per process. To rotate or revoke the credential, update the secret and restart every app replica. During rotation, replicas may accept different values until all have restarted; coordinate client cutover. Clearing the token disables operator routes once the processes restart. Rolling back the application restores the previous unsafe access rules, so retain ingress restrictions during rollback.
