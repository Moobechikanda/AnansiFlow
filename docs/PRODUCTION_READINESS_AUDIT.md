# AnansiFlow Production Readiness Audit

**Status:** Phase 1 repository audit complete. Phase 2 image build is blocked pending reliable package-registry connectivity.

## Scope and safety

Reviewed the Docker build, production/source/development/Caddy Compose files, Docker build ignore rules, Caddy configuration, the sanitized environment example, Rails production/database/storage/Redis configuration, container entrypoint, and PostgreSQL extension/migration definitions.

The local `.env` file was not read. No database or volume operations were run. No deployment configuration was changed as part of this audit. A pre-existing healthy PostgreSQL container was observed and left untouched.

## Findings

### Production image and application source

- [`docker-compose.production.yaml`](../docker-compose.production.yaml) sets `chatwoot/chatwoot:latest` as the base image. [`docker-compose.source.yaml`](../docker-compose.source.yaml) overrides Rails and Sidekiq with the `zedreply:local` image built from [`docker/Dockerfile`](../docker/Dockerfile). The intended deployment must include the source override; the production file alone does not select the AnansiFlow image.
- The Dockerfile copies the repository into `/app`, installs Ruby gems and JavaScript packages, precompiles production assets, and uses a separate final Ruby stage with PostgreSQL client and image-processing runtime packages. It removes `node_modules` and test specs after asset compilation.
- The production Compose base bind-mounts branding assets and customized Rails views from the host over paths already copied into the image. This can make a deployment depend on extra host files and can override the exact files built into the image. These mounts should be evaluated for removal in favor of the image-baked copies, while retaining the customization.
- The Dockerfile's `pnpm i`, build packages, runtime shared-library availability, Git SHA generation, and image build have not been verified by an actual build. They are audit items, not confirmed defects; avoid changing package names or commands until build evidence identifies a requirement.
- [`.dockerignore`](../.dockerignore) excludes `.env` files and local build/runtime directories from the build context, and also excludes Compose files and the Dockerfile itself. Docker receives the selected Dockerfile separately from the build context, but the build should be tested in the intended environment.

### Compose integration, networking, and persistence

- The intended three-file Compose invocation is production + source + Caddy. The source override provides a single `zedreply:local` build/image definition for both Rails and Sidekiq.
- PostgreSQL uses `pgvector/pgvector:pg16`; Redis currently uses the floating `redis:alpine` tag. Rails and Sidekiq wait for PostgreSQL and Redis health checks. The production Compose file defines PostgreSQL and Redis health checks, but no Rails, Sidekiq, or Caddy health check.
- Rails binds host port 9000 to loopback only. PostgreSQL and Redis are also bound to loopback rather than all host interfaces; removing host port publication entirely would further reduce exposure while preserving container-to-container access.
- Caddy and Rails use Compose's default project network, and the Caddy upstream is `rails:3000`. This is consistent with the production service name, but merged Compose output and proxy connectivity have not been validated.
- Named volumes persist PostgreSQL data at `/var/lib/postgresql/data`, Redis data at `/data`, and Active Storage at `/app/storage`. No volume has been modified. Backup/restore procedures remain to be tested and documented.

### Environment and security configuration

- [`.env.example`](../.env.example) contains development-oriented values, including `RAILS_ENV=development`, a localhost HTTP frontend URL, placeholder/empty secret and database/Redis values, and a blank Redis password. It is not a safe production deployment template as-is.
- The production Compose file requires `POSTGRES_PASSWORD` during interpolation. It does not impose an equivalent non-empty requirement for `REDIS_PASSWORD`, although Redis is launched with a `requirepass` command. Production configuration should fail clearly when required credentials are missing and should use the same credentials for the application and service health check.
- Rails production configuration does not require the Rails master key and defaults `FORCE_SSL` to false. The public domain mode must set the intended public URL and enforce HTTPS; local testing must be documented separately.
- Caddy requires `SITE_DOMAIN` and listens on HTTP/HTTPS ports. This is appropriate for public automatic HTTPS with a resolvable public hostname, but there is no documented local production-testing mode yet. Public HTTPS cannot be validated until a real domain and DNS are configured.
- The Rails entrypoint enables shell tracing (`set -x`), waits for PostgreSQL, runs `bundle install`, then waits for `bundle check`. It needs review for production log hygiene, unnecessary runtime installation, and failure behavior before changing it.
- The Compose deployment loads `.env` into application containers. Required production variables include Rails environment/secret and URL settings, PostgreSQL and Redis connection credentials, mail delivery settings, and the selected Active Storage service credentials when using cloud storage. Optional authentication, OAuth, social, AI, and monitoring integrations need only be configured when enabled.

### Rails, assets, PostgreSQL, and migrations

- `config/database.yml` uses PostgreSQL and reads host, port, database, username, and password from environment variables, with production defaults that differ from the database name explicitly set by production Compose. The deployment template should state a consistent explicit set.
- Rails production serves precompiled assets only (`config.assets.compile = false`) and enables static file serving by default. The Dockerfile invokes `assets:precompile` with a placeholder secret during the production build. Asset compilation and asset availability have not yet been verified.
- The application has a `/health` route. No container health check currently uses it.
- The schema enables `pg_stat_statements`, `pg_trgm`, `pgcrypto`, `plpgsql`, and `vector`. Existing migrations enable required extensions, and the application schema contains vector columns/indexes. The `pgvector/pgvector:pg16` image is therefore appropriate in principle; compatibility still needs runtime verification.
- Rails migrations include project-specific business changes and must be preserved. Migration status against a production database has not been queried. No migration should be run until the target database is identified and an independently verified backup exists.

## Phase 1 conclusion

The repository contains most building blocks for the intended architecture, including a custom multi-stage image, an image override for both application services, PostgreSQL 16 with pgvector, persistent named volumes, a Caddy upstream, and an application health route. This is not sufficient evidence of production readiness: the intended Compose combination, secret requirements, public/local domain modes, image build, runtime health, and backup/recovery still require implementation and verification.

## Validation status

| Check | Result |
|---|---|
| Repository/working tree inspection | Passed; no pre-existing working-tree changes were reported |
| Docker Compose CLI availability | Passed; Docker Compose v5.5.1 is installed |
| Production + source Compose configuration validation | Passed with `docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml config --quiet` |
| Production + source + Caddy Compose configuration validation | Blocked: `SITE_DOMAIN` is unset; Compose emitted the expected required-variable error |
| Production image build | Not verified: retry of `docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml build --progress=plain rails` remained in Dockerfile step `#23` (`bundle install`) for about 1,619 seconds. The captured log has no completion or error marker; when checked, no build session was active and `zedreply:local` did not exist. Build duration is consistent with installing/compiling the production gem set in the Alpine build stage; no specific Dockerfile defect has been established. |
| Rails/Sidekiq/PostgreSQL/Redis startup | Not run |
| Database connection and migration status | Not run |
| Asset availability and `/health` | Not run |
| Caddy configuration and proxy | Not run |
| Persistence backup/restore | Not run |
| Public HTTPS | Not run; requires a valid domain and DNS |

## Next phases

1. Make the production/source Compose combination use the custom image consistently and harden production-only configuration without changing the development Compose file unnecessarily.
2. Provide validated local production-testing and public-domain HTTPS modes, with clear required-variable errors.
3. Add a sanitized production environment template and a deployment guide, including safe migration and backup/restore procedures.
4. Build and validate the application and services incrementally. Do not run database migrations against an existing database without first identifying the target and verifying a backup.
