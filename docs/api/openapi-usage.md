# OpenAPI Usage

## Purpose

`openapi/openapi.yaml` is the contract source of truth for this project.

The implementation should follow the contract, not the other way around. Route handlers, request validation, and response shapes must align with the OpenAPI file.

## Current Scope

The current contract covers:

- system endpoints
- authentication endpoints
- current actor endpoints
- shared schemas for tokens, users, organizations, memberships, and errors

## Rules

1. Add or change the OpenAPI contract before implementing a new endpoint.
2. Reuse shared schemas and shared error responses whenever possible.
3. Keep machine-stable error codes inside the error envelope.
4. Treat authentication and tenancy behavior as part of the contract, not as implementation detail.
5. Keep descriptions in English.

## Near-Term Workflow

1. Expand request and response schemas for auth flows.
2. Add organization and membership resources.
3. Add API key resources.
4. Add examples once handlers are implemented.

## Validation

The OpenAPI file should remain YAML-parseable and should be linted once the dedicated lint tool is added to the project.
