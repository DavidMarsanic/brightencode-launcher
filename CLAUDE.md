# Securexe / Brightencode Ecosystem

This repo is one of four core repos in the Securexe/Brightencode app-distribution ecosystem (GitHub org `DavidMarsanic`, all under `~/Developer/` locally), plus a family of small "applet" repos it builds and distributes.

## The four core repos

- **brightencode-launcher** (this repo) — the **wrapper**: Rust/Tauri desktop client. Registers the `securexe://` protocol, verifies Ed25519-signed links, downloads/verifies/caches/runs cataloged binaries, holds local account/library state — the source of truth. Owns the app's identity (bundle id, code signing, release pipeline). Does not implement the interface itself.
- **brightencode-launcher-ui** — the **launcher** (interface component): plain HTML/CSS/JS, no framework. Renders the gallery/browse/account UI, driven entirely by the command+event contract documented in its `CONTRACT.md`. A separate repo so the interface can evolve, be swapped, or eventually be reused/third-party-built independently of the wrapper's trusted backend logic. Composition is build-time only, never live/dynamic: `brightencode-launcher/launcher-ui.version` pins an exact release tag, and `scripts/vendor-launcher-ui.sh` downloads and unpacks it into `vendor/launcher-ui/` (tauri.conf.json's `frontendDist`) before every dev/build. Bumping the pin — not a runtime plugin mechanism — is how an interface update ships.
- **brightencode-web** — Next.js site. Hosts the public catalog, the developer dashboard (claim a repo, manage its declared dependencies/requirements), and device linking. Reads manifest/release data from the worker.
- **brightencode-worker** — Node.js orchestrator/build server (`orchestrator/` + `builder/`, both `.mjs`). Builds submitted Go/Rust applet repos with `CGO_ENABLED=0` and serves `/manifest` + `/download` per repo+commit+target. Has its own `app`/`component`/`asset` reference+vendoring system (see its CLAUDE.md), but that vendors raw source only (no build step, no JS/npm toolchain, and macOS builds bypass it via a separate GitHub Actions relay) — not used for the launcher/launcher-ui split above, which uses a plain GitHub Releases pin instead.

## Applet repos

Small, single-purpose apps, each auto-built by the worker and listed in the catalog: `video-clipper`, `instagram-image-filter` (instaframe), `fberadicator`, `pdf-toolkit`, `duplicate-cleaner`, `gif-maker`, `clip-and-gif`, `disk-space-cleaner`, `image-converter`, `photo-privacy-cleaner`, `private-file-share`, `icon-builder`, and `icon-composer` (a public Go package + CLI, no UI — generates the gradient+icon+letters `AppIcon.icns` used by the others).

## The applet shape

Every applet converges on the same structure, first established in `video-clipper`:

- Go, `CGO_ENABLED=0`, no cgo dependencies — a hard constraint, not a style choice: the worker cross-compiles every repo from one build box with no native per-OS toolchains.
- A local HTTP+SSE server (`internal/server`) serving an embedded static frontend (`web/static`, `go:embed`) — the app's actual UI.
- GUI via spawning the system's installed Chrome/Chromium in `--app=<url>` mode (`internal/browser/appwindow.go`), not an embedded native webview — the only cgo-free way to get a real window. Known cost: the window shows Chrome's own Dock icon, not the app's; a fix exists but isn't production-wired yet.
- `internal/jobs` — a generic async job registry for streaming progress over SSE.
- `internal/browser`, `internal/paths` — copied verbatim between apps.
- `packaging/macos/<name>.app/` — Info.plist + `Contents/MacOS/launch.sh` execing a staged `<name>-bin`. Auto-detected by the worker.
- `securexe.json` — `{version, dependencies[], requirements[]}`; parsed directly by brightencode-web's `lib/releases.ts`/`lib/utilities.ts`. This is a real, live-consumed schema, not aspirational.
- `README.md`, MIT `LICENSE`, matching `.gitignore`.

**Composition pattern:** when an app's core domain logic is genuinely reusable, expose it as a public top-level Go package (e.g. `gif-maker/engine`, not `internal/engine` — Go's `internal/` visibility rule blocks cross-module imports). Importing apps add it as a normal `go.mod` dependency via `go get github.com/DavidMarsanic/<repo>@main`. Proven in `clip-and-gif`, which imports both `video-clipper`'s and `gif-maker`'s engine packages.

The shared applet scaffolding above (server, browser/window hosting, job registry, SSE, output handling) is currently copied per-app; extracting it into a versioned shared component is under consideration, not yet decided.
