# Deployment Guide

## Deployment Model

This starter ships a runtime Docker image that contains:

- the `kemalcr_starter` application binary
- the `migrate` CLI binary
- the OpenAPI document
- the SQL migration files

The recommended deployment flow is:

1. Build and tag the runtime image.
2. Push the image to your container registry.
3. Run `./migrate up` from that image against the target PostgreSQL database.
4. Start the application container with the same image.
5. Verify `/health`, `/ready`, and `/version` after rollout.

## Required Environment Variables

At minimum, provide these values in the target environment:

- `HOST=0.0.0.0`
- `PORT=3000`
- `KEMAL_ENV=production`
- `DATABASE_URL`
- `REDIS_URL`
- `JWT_SECRET`
- `PASSWORD_PEPPER`

Recommended metadata values:

- `APP_NAME`
- `APP_VERSION`
- `APP_BUILD_TIME`
- `APP_GIT_SHA`

Optional throttling controls:

- `AUTH_LOGIN_THROTTLE_LIMIT`
- `AUTH_REFRESH_THROTTLE_LIMIT`
- `AUTH_THROTTLE_WINDOW_SECONDS`

## Build the Release Image

Build a tagged image with release metadata:

```sh
docker build -f docker/app/Dockerfile --target runtime \
  -t registry.example.com/kemalcr:1.0.0 \
  --build-arg APP_VERSION=1.0.0 \
  --build-arg APP_BUILD_TIME="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --build-arg APP_GIT_SHA="$(git rev-parse HEAD)" \
  .
```

Push the image after the build succeeds:

```sh
docker push registry.example.com/kemalcr:1.0.0
```

## Run Database Migrations

Run migrations before shifting production traffic:

```sh
docker run --rm \
  -e KEMAL_ENV=production \
  -e DATABASE_URL=postgres://user:password@postgres:5432/app \
  -e REDIS_URL=redis://redis:6379/0 \
  -e JWT_SECRET=replace-me \
  -e PASSWORD_PEPPER=replace-me \
  registry.example.com/kemalcr:1.0.0 ./migrate up
```

To inspect migration state without changing it:

```sh
docker run --rm \
  -e KEMAL_ENV=production \
  -e DATABASE_URL=postgres://user:password@postgres:5432/app \
  -e REDIS_URL=redis://redis:6379/0 \
  -e JWT_SECRET=replace-me \
  -e PASSWORD_PEPPER=replace-me \
  registry.example.com/kemalcr:1.0.0 ./migrate status
```

## Start the Application Container

After migrations succeed, start the same image as the application service:

```sh
docker run -d \
  --name kemalcr \
  -p 3000:3000 \
  -e HOST=0.0.0.0 \
  -e PORT=3000 \
  -e KEMAL_ENV=production \
  -e DATABASE_URL=postgres://user:password@postgres:5432/app \
  -e REDIS_URL=redis://redis:6379/0 \
  -e JWT_SECRET=replace-me \
  -e PASSWORD_PEPPER=replace-me \
  -e APP_NAME=kemalcr_starter \
  registry.example.com/kemalcr:1.0.0
```

## Post-Deploy Verification

Verify the container after rollout:

```sh
curl http://localhost:3000/health
curl http://localhost:3000/ready
curl http://localhost:3000/version
```

Expected checks:

- `/health` returns `status: ok`
- `/ready` reports PostgreSQL and Redis as `up`
- `/version` exposes the deployed version, build time, and git SHA

## Rollback Notes

- Prefer backward-compatible migrations for zero-downtime rollouts.
- Keep the previous image tag available for rollback.
- If a deployment fails after migrations but before traffic shift, inspect `./migrate status` and apply a targeted rollback plan instead of assuming `down` is always safe.

## Current Limitations

- The repository ships Docker and container guidance, but not a production orchestrator manifest such as Kubernetes, Nomad, or ECS.
- Secret management is expected to come from the target platform rather than from checked-in files.
- `/ready` currently verifies dependency reachability, not deeper app-level business checks.
