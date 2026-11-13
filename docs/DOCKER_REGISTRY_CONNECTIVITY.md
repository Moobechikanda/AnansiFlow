# Docker Registry Connectivity Diagnosis

**Result:** Registry connectivity is working from both Windows and a disposable Docker container during this check. The earlier Bundler log records a transient DNS resolution failure inside the build; that failure did not reproduce.

## Commands executed

- Windows DNS: `Resolve-DnsName -Name <host> -Type A` for `rubygems.org`, `index.rubygems.org`, and `registry.npmjs.org`.
- Windows HTTPS: `curl.exe -sS --connect-timeout 10 --max-time 20 -o NUL -w 'http_code=%{http_code} remote_ip=%{remote_ip} total_seconds=%{time_total}' <URL>` for the RubyGems root/index and npm registry root/`pnpm/latest`.
- Windows package endpoint: `curl.exe -sS -I --connect-timeout 10 --max-time 20 -o NUL -w 'http_code=%{http_code} remote_ip=%{remote_ip} total_seconds=%{time_total}' <URL>` for the exact gem URL in the previous build log and npm's pnpm package metadata.
- Docker DNS and HTTPS: `docker run --rm node:24-alpine node -e "<diagnostic script>"`. The script used Node's system resolver (`dns.lookup`) for the same three hosts and Node HTTPS requests for the RubyGems root/index, npm registry root, and pnpm package metadata. It classified resolver, TLS, timeout, and connection errors separately.
- Repeatability: the same disposable-container diagnostic repeated `dns.lookup('rubygems.org')`, a HEAD request to the exact gem URL, and a HEAD request to `https://registry.npmjs.org/pnpm/latest` three times.

No AnansiFlow services were started or stopped. No project files other than this report were changed; no `.env` values or credentials were read or printed.

## Results

| Test | Windows | Disposable Docker container |
|---|---|---|
| `rubygems.org` DNS | Passed; A records returned | Passed; IPv4 and IPv6 addresses returned |
| `index.rubygems.org` DNS | Passed; CNAME/A records returned | Passed; IPv4 and IPv6 addresses returned |
| `registry.npmjs.org` DNS | Passed; A records returned | Passed; IPv4 and IPv6 addresses returned |
| RubyGems root and index HTTPS | Both HTTP 200; curl exit 0 | Both HTTP 200 |
| npm registry root HTTPS | HTTP 200; curl exit 0 | HTTP 200 |
| pnpm package metadata HTTPS | HTTP 200; curl exit 0 | HTTP 200 |
| Exact prior gem URL, `https://rubygems.org/gems/websocket-driver-0.8.2.gem` | HEAD HTTP 200; curl exit 0 | Three HEAD requests returned HTTP 200 |
| Repeat RubyGems DNS | — | Three of three passed |
| HTTPS/TLS, timeout, or HTTP error | None observed | None observed |

## Prior build error and classification

The previous Bundler output included:

```text
Gem::RemoteFetcher::FetchError Socket::ResolutionError: Failed to open TCP connection to rubygems.org:443 (getaddrinfo(3): Try again)
```

It retried the gem download several times; the log later showed `Installing websocket-driver 0.8.2 with native extensions`. The build did not complete before it was stopped.

**Failure category:** transient DNS/name-resolution failure (`getaddrinfo` returned “Try again”, equivalent to a temporary resolver failure). The evidence does not indicate a TLS certificate/handshake failure, connection timeout, or registry HTTP error. Current repeated checks cannot establish what caused the earlier transient resolver response.

## Recommended corrective action

No registry or application configuration change is justified by the current results. If the error recurs, capture timestamps and the full resolver error while checking Docker Desktop's DNS path and any active VPN, proxy, firewall, or upstream DNS instability. Do not hard-code a public DNS server or change Docker networking based on this single transient failure. Once the network path is stable, retry the image build and verify it reaches completion before proceeding with deployment tests.
