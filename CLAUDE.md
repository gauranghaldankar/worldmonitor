# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

World Monitor is a real-time geopolitical intelligence dashboard aggregating 68+ data sources (conflicts, markets, flights, vessels, cyber threats, disasters, news). It runs as a web SPA (Vercel), desktop app (Tauri), and PWA. Five variants (`full`, `tech`, `finance`, `happy`, `commodity`) are served from a single codebase, selected by hostname or `VITE_VARIANT` env var.

## Common Commands

### Development
```bash
npm run dev              # Start dev server (full variant, localhost:3000)
npm run dev:tech         # Tech variant
npm run dev:finance      # Finance variant
npm run dev:happy        # Happy variant
```

### Building
```bash
npm run build            # TypeScript compile + Vite build (full variant)
npm run build:tech       # Build tech variant
npm run build:finance    # Build finance variant
```

### Type Checking
```bash
npm run typecheck        # Check src/ (main frontend)
npm run typecheck:api    # Check api/, server/, src/generated/
npm run typecheck:all    # Both
```

### Testing
```bash
npm run test:data                    # Unit/data tests (~49 files, Node test runner)
tsx --test tests/some-file.test.mjs  # Run a single test file
npm run test:e2e                     # All Playwright E2E tests (all variants)
npm run test:e2e:full                # E2E for full variant only
npm run test:feeds                   # Validate RSS feed availability
npm run test:sidecar                 # Test edge function bundles
```

### Proto / Code Generation
```bash
make generate    # Regenerate TypeScript clients + server stubs from proto definitions
make lint        # Lint .proto files
make install     # Install buf + sebuf plugins (requires Go)
```

### Linting
```bash
npm run lint:md  # Markdown lint (only 3 rules: MD012, MD022, MD032)
```

### Desktop (Tauri)
```bash
npm run desktop:dev          # Dev mode with devtools
npm run desktop:build:full   # Build desktop app (full variant)
```

### Pre-Push Hook
The `.husky/pre-push` hook runs automatically: typecheck (src + api), CJS syntax check on `scripts/*.cjs`, esbuild bundle validation on `api/*.js`, runtime E2E tests, markdown lint, and version check. All must pass.

## Architecture

### No-Framework Frontend (src/)
Vanilla TypeScript with direct DOM manipulation. No React/Vue/Svelte — panels extend a custom `Panel` base class with lifecycle methods (`render()`, `destroy()`), debounced innerHTML updates, and event delegation on stable containers. Inter-panel communication uses `CustomEvent` dispatch (`wm:breaking-news`, `wm:deduct-context`, `theme-changed`).

### Proto-First RPC (api/ + server/)
Every API endpoint is defined in `proto/worldmonitor/{domain}/v1/*.proto` with HTTP annotations. `make generate` produces:
- **Client stubs**: `src/generated/client/` — typed fetch wrappers
- **Server stubs**: `src/generated/server/` — handler interfaces + route descriptors
- **OpenAPI specs**: `docs/api/`

22 service domains: aviation, climate, conflict, cyber, displacement, economic, giving, imagery, infrastructure, intelligence, maritime, market, military, natural, news, positive-events, prediction, research, resources, trade, weapons, core.

### API Routing Pattern
```
POST /api/{domain}/v1/{rpc}  →  api/{domain}/v1/[rpc].ts (Vercel edge function)
                              →  imports server/worldmonitor/{domain}/v1/handler.ts
                              →  dispatches to individual RPC file (e.g., list-market-quotes.ts)
```

Shared middleware in `api/_api-key.js`, `api/_cors.js`, `api/_rate-limit.js`. Gateway in `server/gateway.ts` handles routing, cache tier headers, and premium RPC gating.

### Server Handlers (server/worldmonitor/)
Each domain: `{domain}/v1/handler.ts` (composition) + individual RPC files + `_shared.ts` (domain utils). Shared server utilities in `server/_shared/` (Redis client, rate limiting, LLM integration, cache keys).

### Variant System
- Hostname detection: `tech.worldmonitor.app` → tech, `finance.worldmonitor.app` → finance
- Config in `src/config/variants/` and `src/config/variant.ts`
- Each variant defines its own panels, map layers, feed categories, and bootstrap keys
- Desktop: switchable via `localStorage['worldmonitor-variant']` without rebuild

### Bootstrap Hydration
On page load, two parallel requests (`/api/bootstrap?tier=fast` and `?tier=slow`) fetch up to 38 pre-cached datasets from Redis in a single pipeline call. Panels call `getHydratedData(key)` on mount for instant rendering.

### Map Rendering (Two Engines)
- **deck.gl** — flat 2D map (scatterplot, heatmap, arc, GeoJSON layers)
- **globe.gl** — 3D globe (polygons, points, arcs, labels)
- Both share a unified layer toggle catalog: `src/config/map-layer-definitions.ts`

### Railway Relay (scripts/ais-relay.cjs)
Persistent Node.js process handling stateful connections Vercel can't support: AIS vessel WebSocket, OpenSky aircraft polling, Telegram MTProto ingestion, OREF rocket alerts, RSS proxy. Authenticated via `RELAY_SHARED_SECRET`.

### Caching (Three Tiers)
1. **In-memory** (60–900s) — hot paths
2. **Redis/Upstash** (120–86400s) — cross-user dedup, bootstrap data
3. **IndexedDB** (client) — survives reloads, TTL envelopes

Cache stampede prevention via in-flight promise dedup. Negative caching with `__WM_NEG__` sentinel. Circuit breakers (2 failures → 5-min cooldown) per feed.

### Desktop Integration (src-tauri/)
Tauri wraps the same SPA. A Node.js sidecar server (`src-tauri/sidecar/local-api-server.mjs`) runs locally, loading the same `api/*.js` handlers. API calls are patched at runtime (`installRuntimeFetchPatch()`) to route through the sidecar.

### Discriminated Union Markers
All map markers carry a `_kind` field for exhaustive type-safe dispatch:
```typescript
type MapMarker = { _kind: 'conflict'; ... } | { _kind: 'flight'; ... } | { _kind: 'vessel'; ... } | ...
```

### Key Patterns
- **SmartPollLoop** — adaptive refresh with exponential backoff, hidden-tab throttle, in-flight dedup
- **Event delegation** — listeners on stable containers, `event.target.closest()` for matching (survives innerHTML replacement)
- **Per-domain edge functions** — each domain is a separate Vercel function for fast cold starts (~100ms)
- **Graceful degradation** — missing API keys disable features, failed APIs serve stale data

## Key Directories

| Directory | Purpose |
|-----------|---------|
| `src/` | Frontend: components, services, config, utils |
| `src/config/` | Variant configs, map layer definitions, feed lists |
| `src/services/` | Data fetching, ML worker, intelligence analysis |
| `api/` | Vercel edge functions (entry points) |
| `server/worldmonitor/` | RPC handler implementations (22 domains) |
| `server/_shared/` | Redis, rate limiting, LLM, cache keys |
| `proto/` | Protobuf service definitions |
| `src/generated/` | Auto-generated client/server stubs (do not edit) |
| `shared/` | Runtime JSON data (stocks, crypto, ETFs, RSS domains) |
| `scripts/` | Relay server, seed jobs, build helpers |
| `tests/` | Unit/data tests (Node test runner) |
| `e2e/` | Playwright E2E tests |
| `src-tauri/` | Tauri desktop app (Rust + Node.js sidecar) |
| `convex/` | Convex backend (email registration) |
| `docker/` | Dockerfile + nginx config for self-hosting |

## TypeScript Configuration
- `tsconfig.json` — main frontend (src/), strict mode, `@/*` path alias
- `tsconfig.api.json` — extends base, covers api/, server/, src/generated/
- Target: ES2020, module: ESNext, bundler resolution

## Environment
- Node.js 22 (pinned in `.nvmrc`)
- All API keys are optional — features degrade gracefully without them
- `.env.example` documents every variable with signup links
