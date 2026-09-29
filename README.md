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
pinned tools and shared packages:

```bash
aftman install
wally install
```

For gameplay testing, open the existing Studio-authored development place. This repository does not
include the complete map and model assets: the current bootstrap requires authored
`Workspace.World.Arena.Markers.Bounds` and `Workspace.World.BaseIslands`, along with the configured
model templates. A
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
rojo build test.project.json -o .verification/mythic-legends-tests-check.rbxlx
git diff --check
```

Selene checks first-party Luau under `src` and `tests`, excluding vendored/generated dependencies.
StyLua uses the checked-in 100-column, tab-indented, LF configuration in `.stylua.toml`; the
explicit width above matches it. Editor settings pin the same release as `aftman.toml`.
`.editorconfig` and `.gitattributes` keep encoding and line endings consistent. Report line-ending
failures separately from other formatting differences. [CI](.github/workflows/verify.yml) runs these
same static checks on pushes and pull requests.
The temporary production Rojo build verifies source mappings without adding a generated place file
to the repository. CI also builds the disposable test project. Neither build can verify missing
Studio-authored content; gameplay and device behavior still require a Studio playtest.

### Strict type checking

Linting, formatting, and building do not run Luau's type checker. `tools/Typecheck.ps1` uses pinned
luau-lsp 1.70.0 with the current Luau type solver (`LuauSolverV2`), strict mode, strict DataModel
resolution, separate production/test Rojo sourcemaps, installed
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
   `default.project.json`.
2. Use Studio Script Analysis to check the production source, including inactive `PostLaunch`
   modules. Tests stay outside the authored place and are checked through the CLI test-project
   sourcemap. Confirm that the inspected files use strict checking; non-strict files remain
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

Jest Roblox tests are excluded from `default.project.json`, so production builds and new syncs do not
add them to the authored development place. If that place was previously synced with the old mapping,
delete `ServerStorage.Tests` once in Studio and save the place; the intentionally permissive
`ServerStorage` boundary may preserve that former child. Confirm it is absent before publishing.
Run the complete suite from Windows or macOS with:

```powershell
pwsh -NoProfile -File tools/Test.ps1
```

The command installs the locked shared and test dependencies, builds an ignored disposable place
from `test.project.json`, and uses Studio's command-line runner to execute Jest before closing Studio.
It prints the test output and exits nonzero on a failed or missing result. Studio must be installed;
pass `-Studio <path>` only when it is outside the documented default location. The runner discovers
`tests/__tests__/*.spec.lua` through `tests/jest.config.lua`. Keep unit tests deterministic: do not
call live DataStores, invoke production remotes, depend on wall-clock time, or mutate Studio-authored
content.

Ordinary Studio sessions use an isolated, ephemeral ProfileStore mock. Restarting Studio does not
verify live cross-session persistence; persistence validation must explicitly exercise the intended
store and save lifecycle.

### Player-data foundation review

The pre-release foundation uses the intentionally fresh `MythicLegends_MVP_v1` data namespace;
the prototype store is left untouched and is not migrated. New profiles start with 100 Gold and
the protected wooden pair. This is a foundation increment, not the complete MVP economy or roster.
Prototype stand assignment and menus remain until their separate replacement tasks.

The runtime suite covers transaction rollback, duplicate/stale requests, bounded receipts, session
loss, client-safe projection, category capacities, active reservations, and partial collection.
After syncing source, check a fresh Studio play session for 100 Gold, both wooden items, normal
capture/stand assignment, and repeated collection without duplicate Materials. Near capacity, only
what fits transfers and remaining output stays in the stand. No new Shop/crafting/upgrade actions
are added in this increment. Mock tests do not establish live durable-save behaviour.

### Base foundation review

The Base foundation keeps the same MVP data namespace and adds Base state to schema-4 profiles
without resetting Gold, Inventory, purchased upgrades, active-job bookkeeping, receipts, or legacy
stand production.
A Base starts with two Shrine-only slots and one free permanent Crafting Station, whose unique saved
identity is reused on rebuild/reconnect. The Station and legacy stands do not occupy Shrine slots.
Capacity derives from the purchased expansion count and configuration (maximum six); it is not saved
as a copied limit. Expansion purchases, Station interaction, and crafting remain separate work.
Existing stand gameplay remains available; server-only Shrine construction is described below.

After syncing source and starting a fresh play session, inspect the player's runtime Base attributes:
`UsedShrineSlots = 0`, `UnlockedShrineSlots = 2`, `MaxShrineSlots = 6`. The existing
`PB_CraftingStation_Root` should have `OwnerId`, `StationInstanceId`, and
`StationDefinitionId = basic_crafting_station`. Reset should retain that identity and leave normal
stand assignment/collection intact. There is intentionally no new Station prompt or menu. Automated
tests cover schema additions, identity reuse after serialization, derived capacity, safe runtime
allocation failure, and Base reconstruction; they do not establish live save durability.

### Shrine-construction logic review

`BaseService.BuildShrine(player, request)` is a server-only command; there is no new menu, remote, or
Shrine model spawn. It supports Fire, Water, Earth, Air, Light, and Dark definitions in
`Shared.Configurations.Shrines`. Each costs 100 configured Gold, starts at level 1, and takes the
lowest-numbered empty unlocked Shrine slot. Duplicate elements are allowed. Neither Materials nor
an owned Mythling are required. The prototype Shrine asset does not define this behavior.

Requests contain `requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`, `shrineId`,
and `expectedGoldCost`. Reuse the original request to retry. Success returns `shrineInstanceId`,
`shrineId`, `buildSlotId`, `level`, and `goldSpent` in the transaction's `values`; the normal state
projection carries the confirmed Gold, owned Shrines, and capacity. A stale price is rejected,
never silently charged. Persisted receipts prevent repeat charges even after reconnect.

Schema 6 adds missing slot IDs and levels to v4/v5 records without resetting earned state. Existing
valid slots and levels are retained; incomplete older records receive deterministic lowest-free
slots and level 1. Corrupt or conflicting ownership is rejected rather than erased or remapped.
The automated suite exercises all six elements, duplicate and stale requests, full capacity,
insufficient Gold, rollback, automatic gap filling, projection privacy, and serialized reconnects.
Production, assignments, upgrades, dismantling, and UI integration are separate reviewable tasks.
These checks establish in-session atomicity and serialized-state behavior, not live save durability.

### Shrine-accounting logic review

`Domain.Production.ShrineAccrual.Accrue` is a pure server-side calculation, not a live service or
player command. It accepts an accounting ledger, a server-authored time, and resolved form/Shrine
metadata; it returns a detached updated ledger or an error without changing its inputs. Production
configuration starts at one-second accounting batches and one XP per eligible working second;
progression configuration supplies the shared level curve, cap, and linear Yield bonus. These
accounting batches do not set save or replication frequency.

Tests use synthetic Mythlings and Materials, leaving the unfinished roster and prototype assets
untouched. They exercise whole output, retained partial work, worker changes, chronological XP and
levels, full/empty pauses, offline equivalence, and repeated-time safety. Long offline intervals skip
identical batches up to the next level/storage event rather than iterating every elapsed second.
The current live stand-production path remains unchanged. Assignment/collection commands, save
integration, migration of retained work, and final content remain separate reviewable tasks; this
increment does not claim live persistence or gameplay integration.

For this isolated review, capped Mythlings continue production but stop earning new XP; any XP
already earned (including pending credit and the cap-reaching batch's remainder) is retained.
This cap behavior is provisional pending confirmation before live integration.

### Admin commands

Public chat commands use `/admin <command> <argument>` after syncing and starting a fresh play session:

- `/admin event blockstorm` starts the existing eight-second, non-colliding visual event. Only one
  Blockstorm runs at a time; it does not change combat, rewards, or player state.
- `/admin teleport fire` moves the requesting character to Fire Island's authored landing point.
- `/admin teleport base` returns the requesting character to their own assigned Base's `Spawn` part.

The old `/admin blockstorm` spelling is replaced; there is no `tp` alias or `help` command. Command
arguments are case-insensitive. Usage errors and results appear privately in chat, with a toast
fallback if the standard chat channels are unavailable. All current players have access, with
server-side rate limiting and one pending teleport per player.

For Fire, place an anchored, level Part named `TeleportPoint` under
`Workspace.World.ElementalIslands.FireIsland.Markers`. Use size `4, 0.2, 4`, disable `CanCollide`,
`CanTouch`, `CanQuery`, and `CastShadow`, and set `Transparency` to `1` after positioning. Put its top
just above solid walkable ground, with space for an avatar, and rotate around Y to choose the arrival
facing. Save these map edits in Studio. No `SpawnLocation` or respawn change is needed.

Water, Earth, Air, Light, and Dark resolve their configured island models the same way and report
that the island is not ready until its marker exists. Model names and request/landing settings live
in `src/ReplicatedStorage/Shared/Configurations/AdminCommands.lua`; update those names when replacing
island models. Missing destinations never fall back to an arbitrary model pivot. Teleports check
ground and overhead clearance, account for avatar height, request streaming when enabled, and cancel
if the character or destination changes while waiting. They do not reset Stamina, effects, capture
state, or progression; ordinary Arena/ring boundary checks continue to apply.

For more help, check out [the Rojo documentation](https://rojo.space/docs).

## Working in the repository

Read [AGENTS.md](AGENTS.md) before making changes. Follow the [project structure and coding
conventions](docs/CONVENTIONS.md), along with the [Studio/Rojo ownership
rules](docs/TECHNICAL_DESIGN.md#roblox-studio-and-rojo-ownership) in Technical Design.
