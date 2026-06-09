# Tenancy Model

The foundation is organization-aware. A human actor belongs to one or more organizations through `organization_memberships`, and the currently selected organization is represented in the access token claim set.

## Actor Context

- Bearer access tokens are decoded by the authentication handler before route code runs.
- The authenticated actor is attached to request context as `actor_id`, `session_id`, and `organization_id`.
- Routes that require an authenticated user only need to check the request context instead of re-parsing JWTs.

## Active Organization Resolution

- When a user logs in, the auth service resolves the first active membership and uses it as the default active organization.
- `/v1/me` trusts the organization claim only if the actor still has an active membership for that organization.
- If the claim is missing, `/v1/me` falls back to the first active membership for that actor.
- `POST /v1/me/active-organization` validates the requested membership and rotates the current session to a newly issued token pair scoped to the selected organization.

## Repository Scoping Rule

- Organization membership lookups must always include both `user_id` and `organization_id` when resolving actor access.
- This keeps tenant scoping explicit in SQL and reduces the chance of cross-organization leaks in later modules.
