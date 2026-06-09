# Organizations Module

The first public organization slice exposes the current actor's organization list and organization creation.

## Current Endpoints

- `GET /v1/organizations` returns the active organizations that the authenticated actor can access through active memberships.
- `POST /v1/organizations` creates a new active organization and, in the same transaction, creates the owner's active membership.
- `GET /v1/organizations/:organization_id` returns organization detail for actors with an active membership.
- `GET /v1/organizations/:organization_id/memberships` lists active memberships for actors who already belong to the organization.
- `GET /v1/organizations/:organization_id/invitations` lists pending invitations for `owner` and `admin` memberships.
- `POST /v1/organizations/:organization_id/invitations` creates a pending invitation for an existing active user by email.
- `POST /v1/organizations/:organization_id/invitations/:invitation_id/accept` lets the invited actor activate the pending membership.
- `DELETE /v1/organizations/:organization_id/invitations/:invitation_id` revokes a pending invitation for `owner` and `admin` memberships.
- `PATCH /v1/organizations/:organization_id` is restricted to `owner` and `admin` memberships.

## Scoping Rule

- Organization listing is always resolved through `organization_memberships` rather than by owner id alone.
- This keeps the read model aligned with future member, admin, and owner access rules.

## Transaction Rule

- Organization creation and owner membership creation must succeed or fail together.
- The service layer owns this transaction to keep route handlers thin and persistence rules explicit.
