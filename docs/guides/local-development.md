# Local Development

## Runtime Model

This project is Docker-first. The default local stack runs:

- the Kemal application
- PostgreSQL
- Redis

## Start the Stack

```sh
docker compose up --build
```

The application is exposed on `http://localhost:3000`.

## Migrations

Run migrations through the app container:

```sh
scripts/migrate up
```

Other supported actions:

- `scripts/migrate down`
- `scripts/migrate reset`
- `scripts/migrate status`

## Tests

Run the full suite with:

```sh
scripts/test
```

The test script applies migrations before running specs.

## Release Smoke Test

Build the release image locally with:

```sh
docker build -f docker/app/Dockerfile --target runtime -t kemalcr-runtime .
```

Then run the dependency services and smoke test the runtime image:

```sh
docker compose up -d postgres redis
docker run --rm \
  --network kemalcr_default \
  -p 3001:3000 \
  -e HOST=0.0.0.0 \
  -e PORT=3000 \
  -e DATABASE_URL=postgres://postgres:postgres@postgres:5432/kemalcr_development \
  -e REDIS_URL=redis://redis:6379/0 \
  -e JWT_SECRET=change-me-in-real-environments \
  -e PASSWORD_PEPPER=change-me-in-real-environments \
  kemalcr-runtime
```

Verify the runtime container with:

```sh
curl http://localhost:3001/health
```

## Environment Variables

Baseline settings live in `.env.example`.

Important values:

- `DATABASE_URL`
- `REDIS_URL`
- `AUTH_LOGIN_THROTTLE_LIMIT`
- `AUTH_REFRESH_THROTTLE_LIMIT`
- `AUTH_THROTTLE_WINDOW_SECONDS`
- `MIGRATIONS_PATH`
- `APP_NAME`
- `APP_VERSION`
- `APP_BUILD_TIME`
- `APP_GIT_SHA`

The release Docker image can bake these values at build time with Docker build args. The `/version` endpoint exposes them so a deployed container can report exactly which build is running.

Authentication throttling is Redis-backed by default. Set either throttle limit to `0` to disable that endpoint's fixed-window limiter during local experiments.

## Current Limitations

- The initial test flow uses the same PostgreSQL database container and truncates tables between repository tests.
- A dedicated test database can be introduced later if isolation requirements increase.
