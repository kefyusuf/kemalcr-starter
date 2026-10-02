FROM crystallang/crystal:1.17.1-alpine AS base

WORKDIR /app

RUN apk add --no-cache \
    bash \
    build-base \
    git \
    postgresql-client \
    postgresql-dev \
    tzdata \
    yaml-dev

COPY shard.yml shard.lock ./
RUN shards install --production

FROM base AS dev

COPY . .
RUN shards install

EXPOSE 3000

CMD ["crystal", "run", "src/app.cr", "--error-trace"]

FROM base AS build

COPY . .
RUN shards install --production
RUN mkdir -p bin
RUN crystal build --release --no-debug src/app.cr -o bin/kemalcr_starter
RUN crystal build --release --no-debug src/migrate.cr -o bin/migrate

FROM alpine:3.20 AS runtime

ARG APP_VERSION=0.1.0
ARG APP_BUILD_TIME=unknown
ARG APP_GIT_SHA=unknown

WORKDIR /app

RUN apk add --no-cache ca-certificates gc gmp libgcc libstdc++ pcre2 tzdata

ENV APP_VERSION=${APP_VERSION} \
    APP_BUILD_TIME=${APP_BUILD_TIME} \
    APP_GIT_SHA=${APP_GIT_SHA}

COPY --from=build /app/bin/kemalcr_starter ./kemalcr_starter
COPY --from=build /app/bin/migrate ./migrate
COPY --from=build /app/openapi ./openapi
COPY --from=build /app/db/migrations ./db/migrations

EXPOSE 3000

CMD ["./kemalcr_starter"]
