
### Why a monorepo
- **Atomic changes:** Update API, UI, and TF together; reviewers see the full context.
- **One CI pipeline:** Lint/test once; path filters run only what changed (fast).
- **Shared tooling:** One `Justfile` drives infra + FE + BE; `.env` variables flow consistently.
- **Single source of truth:** Infra and app code live together; fewer “mismatched env” surprises.

### Why `apps/web` for the frontend
- **Convention for multiple apps:** Leaves room for `apps/admin`, `apps/docs`, etc. without reshuffling later.
- **Isolation:** Keeps Node toolchain, lockfile, and `dist/` artifacts contained.
- **Clear deploy surface:** CI can key off `apps/web/**` to build/deploy the SPA only when it changes.

### Why `iqana_demo` (backend) at the repo root
- **Python package simplicity:** Top-level package = clean imports, easy `pip install -e .`, tidy pytest/mypy.
- **Lambda packaging:** Keeps handler path stable (`iqana_demo.api.app:app`) and minimizes zip size churn.
- **Tooling compatibility:** Plays nicely with `uv`, Ruff, mypy, and GitHub Actions without custom path hacks.

### Why `infra` at the repo root
- **Repo-wide ownership:** Infra spans **both** API & web (API Gateway, Cognito, DDB, S3/CF, KMS, Secrets).
- **Modules + env overlays:** `infra/modules/*` are reusable; `infra/envs/dev` composes them for an environment.
- **Outputs feed apps:** TF outputs (API endpoint, CF domain, Cognito IDs) are consumed by the web build/Justfile.

### When to split repos later (not now)
- Independent release cadence for FE vs BE, or team boundaries require separate permissions.
- Very large CI graphs or repo size becomes a bottleneck (mitigate first with path filters and caching).

