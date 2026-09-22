# Mythic Legends

A mobile-first Roblox creature-collection and Base-progression game. Players capture Mythlings in a
shared Arena, assign them to elemental Shrines, and grow their roster and Base.

## Documentation

| Document | Canonical content |
| --- | --- |
| [Game Design Document](docs/GDD.md) | Player experience, gameplay rules, launch/future scope, pacing goals, and gameplay acceptance criteria. |
| [Technical Design](docs/TECHNICAL_DESIGN.md) | Runtime architecture, networking, combat implementation, data schemas, persistence, UI code ownership, and implementation alignment. |
| [Coding Conventions](docs/CONVENTIONS.md) | Project layout, Rojo hierarchy, naming, module organization, typing, cleanup, formatting, and logging. |
| [UI Guidelines](docs/UI_GUIDELINES.md) | Menu behavior, visual conventions, accessibility, empty states, and player feedback. |
| This README | Project setup and development/verification commands. |

Write each rule in its owning document and link to it from the others. The GDD describes approved
behavior; the [implementation alignment notes](docs/TECHNICAL_DESIGN.md#implementation-alignment)
identify work needed to bring the prototype into line with it. Runtime balance values belong in
`src/ReplicatedStorage/Shared/Configurations`.

## Getting started

Use Roblox Studio with the Rojo Studio plugin, Aftman, and PowerShell 7 (`pwsh`). Install the
pinned tools and shared/test packages:

```bash
aftman install
wally install
wally install --project-path tests
```

For gameplay testing, open the existing Studio-authored development place. This repository does not
include the complete map and model assets: the current bootstrap requires authored
`Workspace.Map.Arena` and `Workspace.Map.BaseIslands`, along with the configured model templates. A
clean Rojo build supplies the mapped code and hierarchy, but is not a complete playable place. See
[Studio/Rojo ownership](docs/TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) for the authored
containers to preserve.

Start the Rojo server from the repository root, then connect to it through the Rojo Studio plugin in
that development place:

```bash
rojo serve
```

## Verification

Before handing off source changes, run the static verification suite:

```bash
selene src tests
stylua --check --column-width 100 src tests
pwsh -File tools/Typecheck.ps1
rojo build default.project.json -o .verification/mythic-legends-check.rbxlx
git diff --check
```

Selene checks first-party Luau under `src` and `tests`, excluding vendored/generated dependencies.
StyLua uses the checked-in 100-column, tab-indented, LF configuration in `.stylua.toml`; the
explicit width above matches it. Editor settings pin the same release as `aftman.toml`.
`.editorconfig` and `.gitattributes` keep encoding and line endings consistent. Report line-ending
failures separately from other formatting differences. [CI](.github/workflows/verify.yml) runs these
same static checks on pushes and pull requests.
The temporary Rojo build verifies source mappings without adding a generated place file to the
repository. It cannot verify missing Studio-authored content. Gameplay and device behavior still
require a Studio playtest.

### Strict type checking

Linting, formatting, and building do not run Luau's type checker. `tools/Typecheck.ps1` uses pinned
luau-lsp 1.70.0 with the current Luau type solver (`LuauSolverV2`), strict mode, strict DataModel
resolution, the current Rojo sourcemap, installed
dependencies, and a SHA-256-verified Roblox API definition snapshot from that same release. It
checks the pinned Wally and wally-package-types versions, reinstalls the shared and test packages
from their manifests/lockfiles, and generates Wally type re-exports. Reinstalling regenerates Wally's
entrypoints before each check because wally-package-types 1.6.2 cannot process its own previous
output. The command supports repeated runs and repairs interrupted export generation without
hand-editing package implementations. Wally may refresh its registry/package cache, so installation
still needs the same cache permissions and network access as the setup commands.

The first run downloads the definitions into ignored `.tools/`; subsequent runs can use the
verified cached copy. Sourcemaps and build outputs use ignored `.verification/`.

The analyzer checks all first-party `src` and `tests` files, including inactive `PostLaunch` source.
Vendor/generated diagnostics are excluded; first-party integration errors remain failures. To
cross-check against the installed Studio version:

1. Sync the intended checkout and installed dependencies into the Studio development place using
   the project's Rojo mapping.
2. Use Studio Script Analysis to check the first-party scope, including source, tests, and inactive
   `PostLaunch` modules. Confirm that those files use strict checking; non-strict files remain
   compliance gaps even when they report no diagnostics.
3. Require no unresolved type errors in the stated scope. Record the Studio version, scope,
   exclusions, and remaining diagnostics. If the analysis cannot be completed, report it as
   unverified. A targeted check does not establish repository-wide compliance.

Record the checker/version, analyzed scope, unresolved diagnostics, and exclusions for either path.
A targeted check does not establish repository-wide compliance. The CLI API snapshot is deliberately
pinned; update its release and checksum together when adopting newer Roblox API types. The script
accepts `-Rojo`, `-LuauLsp`, `-Wally`, and `-WallyPackageTypes` executable paths when tool shims are
unavailable.

### Runtime tests

Jest Roblox tests are isolated under `ServerStorage.Tests` and do not run in production. After
installing their server-only Wally dependencies, run them from the Studio Command Bar while the
place is stopped:

```luau
require(game.ServerStorage.Tests.TestRunner).Run()
```

The runner discovers `tests/__tests__/*.spec.lua` through `tests/jest.config.lua`. Keep unit tests
deterministic: do not call live DataStores, invoke production remotes, depend on wall-clock time, or
mutate Studio-authored content.

Ordinary Studio sessions use an isolated, ephemeral ProfileStore mock. Restarting Studio does not
verify live cross-session persistence; persistence validation must explicitly exercise the intended
store and save lifecycle.

For more help, check out [the Rojo documentation](https://rojo.space/docs).

## Working in the repository

Read [AGENTS.md](AGENTS.md) before making changes. Follow the [project structure and coding
conventions](docs/CONVENTIONS.md), along with the [Studio/Rojo ownership
rules](docs/TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) in Technical Design. Art-source
conventions are in [art/README.md](art/README.md).
