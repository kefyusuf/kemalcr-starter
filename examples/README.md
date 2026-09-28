# Examples

Runnable scripts against a local stack.

## smoke.sh

Exercises the golden path: health → register → organization → product → webhook → password reset.

```sh
./scripts/dev          # start postgres, redis, app
./examples/smoke.sh    # or: ./examples/smoke.sh http://localhost:3000
```

Requires `curl` and `bash`. Tokens are parsed from JSON responses with `sed` to keep the script dependency-free.
