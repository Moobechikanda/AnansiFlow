# Production Docker Build Performance Findings

## Summary

The saved build log shows slow but continuing Bundler activity, not a confirmed deadlock: step `#23` emitted gem fetch/install events through 1,619.1 seconds and ended on a normal `Installing` line, without a Docker `DONE`, error, or cancellation marker. The log stopped updating at 10:51:37; when inspected later there was no active build and no `zedreply:local` image. The exact point of interruption cannot be determined from the log alone.

Likely contributors are compiling many gems from source on Alpine, intermittent RubyGems fetch errors, and a constrained Docker/host memory budget. No evidence proves an out-of-memory event or identifies a single gem's exact compile duration.

## Evidence

### Bundler work and native extensions

The captured BuildKit log for `docker compose -f docker-compose.production.yaml -f docker-compose.source.yaml build --progress=plain rails` shows 296 `Installing` records between elapsed step times 76.57 and 1,619.1 seconds. The final records were `administrate-field-active_storage 1.0.3` and `administrate-field-belongs_to_search 0.10.0`; there is no per-gem completion summary, so the last in-flight install cannot be confirmed individually. No application image layer was committed.

Bundler explicitly logged 31 packages as being installed “with native extensions”:

`bigdecimal 4.1.2`, `cgi 0.5.2`, `racc 1.8.1`, `nio4r 2.7.5`, `date 3.5.1`, `prism 1.9.0`, `erb 6.0.6`, `io-console 0.8.2`, `ffi 1.17.2`, `json 2.19.9`, `bcrypt 3.1.22`, `msgpack 1.8.3`, `cld3 3.7.0`, `commonmarker 0.23.12`, `unicode 0.4.4.5`, `digest-crc 0.6.5`, `unf_ext 0.0.8.2`, `google-protobuf 3.25.7`, `openssl 3.2.0`, `pg 1.5.3`, `nokogiri 1.19.4`, `puma 7.2.1`, `websocket-driver 0.8.2`, `rbs 4.0.3`, `sassc 2.4.0`, `bootsnap 1.16.0`, `oj 3.17.3`, `llhttp-ffi 0.4.0`, `datadog 2.38.0`, `scout_apm 5.3.3`, and `grpc 1.72.0`.

The log progressed well beyond the native-extension entries, including past `grpc`; this is evidence that Bundler advanced, but not a final success result for the overall step. Large C/C++ or otherwise compiled dependencies such as `sassc`, `bootsnap`, `cld3`, `google-protobuf`, `nokogiri`, and especially `grpc` are plausible compile-cost contributors. BuildKit's output does not provide per-gem CPU time, memory, or download-size measurements, so their individual durations cannot be ranked reliably. The `grpc` install entry appears at 1,413.4 seconds of cumulative step time.

### Network retries and build output

- The log records six retries for `libddwaf-1.30.0.0.2` between elapsed times 760.3 and 846.8 seconds: four `getaddrinfo(3): Try again` resolver failures and two `SSL_read: unexpected eof while reading` TLS/connection failures.
- Bundler subsequently logged `Installing libddwaf 1.30.0.0.2` at 873.1 seconds and continued with other gems. Registry connectivity worked in the separate later diagnostic; that does not negate the transient failures recorded during this build.
- Docker emitted one non-fatal `FromAsCasing` warning at Dockerfile line 2. No OOM, compiler error, `failed to solve`, or BuildKit completion marker appears in the saved build output.
- BuildKit marked Dockerfile setup steps `#9` through `#22` as cached. The long work was step `#23` (`bundle install -j 2 -r 10`), not repeated APK or pnpm setup.

### Resource snapshot

Read-only checks reported Docker Desktop's engine with **4 CPUs** and **4,106,866,688 bytes (about 3.82 GiB) memory**. The Windows host reported **8 logical processors**, **5.94 GiB total physical memory**, and about **0.43 GiB available** at inspection time. The only running container observed was the existing PostgreSQL service, using about **46 MiB** and negligible CPU.

These are current resource readings, not measurements captured during the build. They show a limited host/Docker memory budget that could constrain concurrent native compilation, but do not prove memory pressure caused the historical duration. No build-time CPU/memory telemetry or OOM evidence is available.

## Commands and inspection used

- `Get-Content` / `Select-String` on `%TEMP%\AnansiFlow-production-build-20261106.log` to examine elapsed Bundler events, native-extension notices, retries, warnings, and completion/error markers.
- `docker info --format 'CPUs={{.NCPU}} MemoryBytes={{.MemTotal}} Server={{.ServerVersion}}'`
- `docker stats --no-stream --format 'NAME={{.Name}} CPU={{.CPUPerc}} MEM={{.MemUsage}}'`
- `docker ps --format 'NAME={{.Names}} STATUS={{.Status}}'`
- Windows `Get-CimInstance` queries for host processor count, physical memory, and currently available memory.
- Read-only matching of native-extension package names against [`Gemfile.lock`](../Gemfile.lock).

No build was restarted. No services were started or stopped, and no images, caches, application code, Dockerfiles, dependencies, databases, or volumes were modified.

## Recommended next action

Do not change dependencies or the Dockerfile based on this evidence alone. Before another controlled build, free host memory or review Docker Desktop's resource allocation, then capture `--progress=plain` output while monitoring Docker CPU/memory so compilation can be distinguished from network waits. Preserve the existing build cache. If registry errors recur, investigate Docker Desktop/VPN/proxy/DNS stability separately; the six `libddwaf` retries materially added delay even though Bundler later advanced.
