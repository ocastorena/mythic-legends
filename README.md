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

### Feature-first source-layout review

Server feature implementations live beside their owning service; reusable server-only contracts and
accounting live under `ServerScriptService.Shared`. These modules do not replicate through
`ReplicatedStorage.Shared`, and technical facilities such as logging, remotes, and lifecycle support
remain in `Infrastructure`. Moving a pure module beside a service does not expose or start it: the
service's `init.lua` remains its public lifecycle/API boundary, while deterministic tests may require
the private pure child directly.

After a source-layout change, rerun the complete static suite and runtime tests above. Then cleanly
sync the intended checkout into the authored development place and use a fresh play session to check
that the existing service bootstrap, prototype flows, and authored dependencies still load. A Rojo
build alone does not establish that Studio-authored content or live gameplay survived the move.

### Launch Mythling form catalogue review

`Shared.Configurations.MythlingForms` contains the 18 permanent, neutrally identified launch forms
and their approved business values; the [catalogue contract](docs/TECHNICAL_DESIGN.md#launch-mythling-form-catalogue)
lists the exact six evolution chains and scalable ID rules. Creature names, concepts, models, icons,
and descriptions remain open. IDs are not player-facing names or owned-instance IDs.

`MythlingCatalogUtil.ValidateLaunch` validates this separate catalogue before server services start.
Run the static suite and runtime tests above for catalogue and invalid-fixture checks. After syncing,
a fresh Studio session should still use the unchanged three-form prototype capture/spawn and stand
paths. The new definitions are not exposed through the service context: metadata validation does
not activate them in the Arena, live production, evolution, sales, saves, or menus. This increment
changes neither existing `typeId` values nor the save schema.

### Launch Material catalogue review

The six normal Materials now have stable element-based IDs and matching Shrine output references;
see the [catalogue contract](docs/TECHNICAL_DESIGN.md#launch-material-catalogue). Display names such as
`Fire Material` are temporary and thumbnails are empty until the final names/icons are chosen.
Each launch Material is configured to buy for 10 Gold, sell for 2 Gold, and stack to the shared
1,000-unit limit. These are metadata values, not new purchase or sale actions.

`MaterialCatalogUtil.Validate` checks the real catalogue before server services start. Run the static
suite and runtime tests above; catalogue tests include invalid element coverage, output references,
prices, and stack limits. Then sync and start a fresh Studio play session to check normal startup and
the existing prototype capture/stand-production/collection flow. The retained prototype Materials
are marked `launchEnabled = false`, but this flag does not disable or rewrite those existing paths.
This increment adds no live Shrine ledger, save-schema change, UI, Shop, sale, or crafting integration.

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

The schema-6 layout upgrade adds missing slot IDs and levels to v4/v5 records without resetting
earned state. Existing valid slots and levels are retained; incomplete older records receive
deterministic lowest-free slots and level 1. Corrupt or conflicting ownership is rejected rather
than erased or remapped.
The automated suite exercises all six elements, duplicate and stale requests, full capacity,
insufficient Gold, rollback, automatic gap filling, projection privacy, and serialized reconnects.
The commands below now add settlement, assignments, collection, upgrades, and dismantling;
automatic production lifecycle and UI integration remain separate tasks.
These checks establish in-session atomicity and serialized-state behavior, not live save durability.

### Shrine-accounting save foundation review

Schema 7 adds empty `stored`, `progress`, `newWork`, and `workerIdsBySlot` fields to constructed
Shrines, plus one private profile-wide `productionClock` with `lastAccruedAt` and `nextBatchAt`.
Load initializes that schedule once from current server time, never from an old login time. New
Shrine construction initializes its empty fields in the existing purchase transaction without
shifting the shared clock. No production or XP is awarded by these additions.

Run the static suite and runtime tests above. Schema tests cover additive v4–v6 upgrades, repeated
preparation, serialized-state retention, invalid/partial accounting rejection, and projection
privacy; construction tests check empty fields and unchanged clock timing. Existing valid state,
identities, unrelated fields, and prototype stand behavior must survive. This is the saved-state
foundation only: no live accrual, assignment, collection, Mythling progression changes, or UI is
enabled. Existing DataService saves own the new fields; tests and ordinary Studio mocks do not
prove live durable persistence. See the
[schema contract](docs/TECHNICAL_DESIGN.md#schema-7-shrine-accounting-foundation).

### Shrine-accounting draft adapter review

`ServerScriptService.Shared.ShrineAccounting.SettleToDraft` adapts a prepared current-schema
transaction draft to the shared accrual engine and merges only accounting fields back on success.
It defaults to the real launch form and Shrine metadata without changing saved `typeId` identities. Known forms
must already have explicit level, XP, and pending XP; no capture defaults or migrations are added.
Unreferenced legacy forms without pending credit remain untouched. See the
[adapter contract](docs/TECHNICAL_DESIGN.md#shrine-accounting-draft-adapter) for rejection boundaries.

Run the static suite and runtime tests above. Tests exercise detached failures, preserved unrelated
state, transactions through `Transactions.Run`, and serialized continuation. Projection keeps pending
XP private. The server-shared adapter supports on-demand settlement, atomic assignment, collection,
Shrine upgrades, and dismantling; it is not an automatic lifecycle hook, remote, or menu action.
Callers must use it inside `DataService.Transact` or `Update`; it neither authenticates a player nor
saves a profile by itself.
These tests do not establish live durable persistence.

### On-demand Shrine settlement review

`ProductionService.SettleShrines(player)` is a server-only command returning the normal transaction
result, with `values.settledAt` on success. It uses the player's already-loaded profile and reads
server time inside its transaction; callers cannot provide elapsed time, metadata, or a ledger.
The service must be running and the player connected. There are no automatic join/leave/timer
calls, new save checkpoints, remotes, menus, or changes to the existing stand paths.

Run the static suite and runtime tests above. Controlled DataSource tests cover transaction results
and repeated settlement, not live durable saves. Settling twice at the same time awards no duplicate
work, though each accepted `Update` has its own revision/receipt. Future worker or production changes
must settle and mutate in the same draft, not call this command before a separate transaction. See
the [command contract](docs/TECHNICAL_DESIGN.md#on-demand-shrine-settlement).
The disposable runner cannot create engine `Player` instances; automated service-gate tests cover
lifecycle and impostor rejection. Actual connected/disconnected-player dispatch still needs a playtest.

### Shrine-accounting logic review

`ServerScriptService.Shared.ShrineAccrual.Accrue` is a pure server-side calculation, not a live
service or player command. It accepts an accounting ledger, a server-authored time, and resolved
form/Shrine metadata. It returns a detached updated ledger or an error without changing its inputs.
Production configuration starts at one-second accounting batches and one XP per eligible working
second; progression configuration supplies the shared level curve, cap, and linear Yield bonus.
These accounting batches do not set save or replication frequency.

Tests use synthetic Mythlings and Materials, leaving the unfinished roster and prototype assets
untouched. They exercise whole output, retained partial work, worker changes, chronological XP and
levels, full/empty pauses, offline equivalence, and repeated-time safety. Long offline intervals skip
identical batches up to the next level/storage event rather than iterating every elapsed second.
The current live stand-production path remains unchanged. Server-only settlement, assignment,
collection, Shrine upgrades, and dismantling use the engine through the shared adapter. Automatic
lifecycle integration, migration of retained prototype work, and final content remain separate
tasks; pure tests do not prove live persistence.

Capped Mythlings continue production but stop earning new XP; any XP
already earned (including pending credit and the cap-reaching batch's remainder) is retained.

### Shrine-assignment logic review

`ServerScriptService.Services.BaseService.ShrineAssignments.Assign` and `.Remove` are
feature-private pure operations on one profile's accounting view. Assignment requires an owned,
unassigned Mythling and an empty unlocked slot in a matching-element Shrine. Remove the current
worker before moving it elsewhere or replacing it. Removal checks the expected worker so an
outdated selection cannot remove a different Mythling. Emptying slot 1 leaves any worker in slot 2
in slot 2.

Accepted changes settle prior production and XP before changing the slot map. Unassignment retains
ownership, pending XP, stored Materials, unfinished work, and the shared batch schedule. Invalid
requests return an error without changing the input, and backdated changes are rejected. Tests cover
all six elements with synthetic content; there are no new catalogue entries, menus, or model changes.

The ledger uses `workerIdsBySlot` with string slot keys instead of its former dense array. That
earlier test-ledger shape was never persisted, so no player-data migration is needed. The server-only
commands below now derive this view from canonical owned state and commit through the existing
transaction and duplicate-request protection. Prototype stand assignment remains separate.

### Atomic Shrine-assignment command review

`BaseService.AssignShrineWorker(player, request)` and `RemoveShrineWorker(player, request)` are
server-only commands for the running service and a connected player's already-loaded profile.
Assignment requests contain `requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`,
`shrineInstanceId`, numeric `slotId`, and `workerId`. Removal uses `expectedWorkerId` instead of
`workerId`. Retry the original request unchanged. Success returns `shrineInstanceId`, `slotId`,
`workerId`, and `settledAt` in transaction `values`.

Each command settles prior work and changes the slot map in one `DataService.Transact` callback,
using one server timestamp and the real form/Shrine metadata. It never calls standalone settlement
before a second transaction. Moving workers still requires explicit unassignment; removal retains
ownership and earned/pending XP. The shared adapter stages only accounting, progression, and slot
maps while preserving unrelated state. Legacy deletion rejects canonical launch forms and retained
entries with Shrine assignments or pending credit, preventing dangling links or erased earned work.

Run the static suite and runtime tests above. Transaction fixtures cover duplicate/stale requests,
profile isolation, rollback, assignments across all six elements, and retained work. Actual connected/
disconnected-player dispatch and durable saves still need a playtest. These commands add no remote,
menu, model, automatic production loop, acquisition grant, profile auto-load, or schema migration.
The [command contract](docs/TECHNICAL_DESIGN.md#atomic-shrine-assignment-commands) owns implementation details.

### Shrine-collection logic review

`ServerScriptService.Services.ProductionService.ShrineCollection.Collect` is a feature-private pure
operation taking the selected Shrine and its expected Material ID. It settles elapsed production
and XP, transfers every whole Material that fits in Inventory, and retains the remainder in the
Shrine. Capacity uses the shared Inventory rules: separately rounded Material stacks, purchased
upgrades, and active crafting-refund reservations. Collection neither releases reservations nor
grants extra XP.

Tests cover partial/full bags, matching and other Material reservations, retained unfinished work,
full-storage pauses, repeated timestamps, stale selections, and detached serialized results using
synthetic content. Empty storage returns `NothingToCollect`, including when Inventory is full;
stored output with no room returns `InventoryFull`. Rejections leave both inputs unchanged.

The result contains the settled accounting ledger and updated Material map; the server-only command
below now commits both in one profile transaction with revision/receipt protection. The shared
capacity helper lives under `ServerScriptService/Shared/InventoryCapacity`; existing prototype
callers retain their behavior. The pure operation adds no remote, save-schema change, or menu, and
its isolated tests do not establish durable-save behavior.

### Atomic Shrine-collection command review

`ProductionService.CollectShrine(player, request)` is a server-only command for the running service
and a connected player's already-loaded profile. Requests contain `requestId`
(`<expectedRevision>:<unique token>`), `expectedRevision`, `shrineInstanceId`, and
`expectedMaterialId`. Retry the original request unchanged. Success returns `shrineInstanceId`,
`materialId`, `collected`, `remaining`, and `settledAt` in transaction `values`.

The command derives accounting, Materials, purchased capacity, and crafting reservations from the
same transaction draft. One `DataService.Transact` callback settles prior work and commits the
Shrine debit with the Inventory grant, using one server timestamp and real launch metadata. It
never calls standalone settlement or a separate Material grant. A positive partial transfer
succeeds and leaves the remainder in Shrine storage; full bags reject with `InventoryFull`, while
no whole output returns `NothingToCollect`. Rejection rolls back gameplay changes, including staged
accounting, though DataService may record the rejection receipt and revision. Receipt replay never
resamples time or grants Materials twice. Jobs and reservations remain unchanged.

Run the static suite and runtime tests above. Transaction fixtures cover receipt safety, stale
selections, profile isolation, rollback, reservations, partial transfers, and retained work. Actual
connected/disconnected-player dispatch and durable saves still need a playtest. There is no new
remote, menu, model, automatic production loop, acquisition grant, profile auto-load, save request,
or schema migration; prototype stand collection is unchanged. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-shrine-collection-command).

### Shrine-upgrade logic review

`ServerScriptService.Services.BaseService.ShrineUpgrades.Upgrade` is a feature-private pure
operation. It purchases only the next Shrine level using collected matching Materials and Gold:
level 1→2 costs 1,000 Gold + 400 Materials; level 2→3 costs 15,000 Gold + 4,000 Materials. The
shared Shrine configuration owns all six elements' 1/2/3 worker slots, 300/1,200/3,600 storage, and
target-level costs. Pure tests inject synthetic content; the server-only command below uses the
existing canonical launch definitions without changing the unfinished names or prototype assets.

Accepted upgrades settle the whole profile under the old storage limit before paying and increasing
the level. Existing workers, stored output, unfinished work, earned XP, and the batch schedule survive;
the new slot remains empty. Increased storage resumes production without backfilling full-storage
time. Neither Shrine output nor crafting-refund reservations can pay the cost. Tests cover both
transitions, all six elements, stale quotes/levels, insufficient funds, reservation protection,
full-storage pauses, and serialized mid-batch continuation.

The result contains the accounting ledger, replacement Material map, and remaining Gold. The
server-only command below now commits them together with its revision/receipt record, preserving
all other profile fields. Rejections leave every input unchanged. The pure reducer itself supplies
no authentication, remote, save migration, timer, auto-assignment, or UI.

### Atomic Shrine-upgrade command review

`BaseService.UpgradeShrine(player, request)` is a server-only command for the running service and a
connected player's already-loaded profile. `Types.UpgradeShrineRequest` contains `requestId`
(`<expectedRevision>:<unique token>`), `expectedRevision`, `shrineInstanceId`, `expectedLevel`,
`expectedMaterialId`, `expectedGoldCost`, and `expectedMaterialQuantity`. Retry the original request
unchanged. Success returns `shrineInstanceId`, `previousLevel`, `level`, `materialId`, `goldSpent`,
`materialsSpent`, and `settledAt` in transaction `values`.

One `DataService.Transact` callback uses one server timestamp to settle at the old capacity, charge
owned Inventory Materials and Gold, and install exactly the next level with its receipt. It derives
resources and accounting from the same draft and resolves the quote against real launch metadata.
The shared level bridge preserves every assignment, identity, other Shrine level, stored output,
unfinished work, and earned/pending XP; new slots start empty. Neither uncollected Shrine output nor
crafting-refund reservations can pay the price. A failed purchase rolls back gameplay changes,
including staged accounting, though DataService may record the rejection receipt and revision.
Receipt replay never resamples time or charges twice.

Run the static suite and runtime tests above. Transaction fixtures cover next-level purchases,
stale quotes, receipt safety, rollback, reservation protection, and retained work. Actual connected/
disconnected-player dispatch and durable saves still need a playtest. There is no new remote, menu,
model, automatic production lifecycle, profile auto-load, save request, or schema migration;
prototype stand paths remain unchanged. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-shrine-upgrade-command).

### Shrine-dismantling logic review

`ServerScriptService.Services.BaseService.ShrineDismantling.Dismantle` is a feature-private pure
operation selecting a built Shrine instance and its expected level. It requires matching
Base/accounting views for every constructed Shrine, no assigned workers, and no completed
Materials after settling elapsed production. A due batch can complete output even after
unassignment; collect that output before dismantling.

Success removes only the selected Shrine from the returned accounting ledger and built-Shrine map.
Its unfinished progress and unresolved work are discarded; owned Mythlings and their earned/pending
XP remain. Purchased build slots, other Shrine positions, the permanent Station, and prototype stands
are untouched. The existing lowest-free-slot rule can reuse the freed slot. There is no Gold or
Material refund, stored building, automatic unassignment, or automatic collection.

Tests cover all six elements and levels, purchased-slot retention, stale/replaced instances, mismatched
views, batch boundaries, rollback, pending-XP continuation, and serialized detached state. The
server-only command below now commits the removal and surviving accounting with the profile's
revision/receipt record. It preserves canonical accounting rather than replacing surviving records
with the reducer's ownership-only map. Rejections leave every input unchanged. The pure operation
itself supplies no authentication, save-schema migration, model deletion, or menu.

### Atomic Shrine-dismantling command review

`BaseService.DismantleShrine(player, request)` is a server-only command for the running service and
a connected player's already-loaded profile. Requests contain only `requestId`
(`<expectedRevision>:<unique token>`), `expectedRevision`, `shrineInstanceId`, and `expectedLevel`.
Retry the original request unchanged. Success returns `shrineInstanceId`, `shrineId`, `buildSlotId`,
`level`, and `settledAt` in transaction `values`.

One `DataService.Transact` callback uses one server timestamp, derives both views from the same
draft, and settles production before removing exactly the selected empty Shrine. Workers must be
unassigned and completed output collected first; a due batch that completes output also rejects
removal. Unfinished Shrine work is discarded without forcing an early batch, while every owned
worker and its earned/pending XP remain. Other Shrine accounting, purchased slots, the permanent
Station, legacy state, Materials, Gold, jobs, and reservations are preserved. No refund is granted.

Failed removal rolls back gameplay changes, including staged accounting, though DataService may
record a rejection receipt and revision. Identity/level-bound receipts prevent replayed removal
from affecting a replacement in the freed slot; replay does not resample time. Transaction fixtures
cover empty/occupied/storage gates, stale selections, receipts, rollback, and retained state.
Actual connected/disconnected-player dispatch and durable saves still need a playtest. There is no
new remote, menu, model deletion, automatic lifecycle, profile auto-load, explicit save request, or
schema migration. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-shrine-dismantling-command).

### Mythling-evolution logic review

`ServerScriptService.Services.InventoryService.MythlingEvolution.Evolve` is a feature-private pure
operation selecting an owned Mythling, its expected current form, and its expected next form. It
follows the current form's optional `evolution = { targetFormId, requiredLevel }` metadata; no link
means no further evolution, independently of rarity or stage. Required levels are configurable per
link; synthetic launch-like tests use levels 6 and 40 without finalizing the roster.

Evolution is manual and free, including while assigned or while Shrine storage is full. It settles
elapsed work under the old form before checking the earned level, then changes only that owned
worker's form ID. Identity, level, XP, pending credit, assignment slot, completed Materials, unfinished
work, and batch timing survive. Due XP can unlock evolution; incomplete batches are never awarded
early. An already-eligible Mythling can take two separate evolution actions at the same timestamp.

Tests cover eligibility, old/new-form production within a batch, stale requests, invalid/cyclic or
cross-element links, terminal forms, preserved inactive legacy fields, arithmetic rollback, and
serialized continuation. The reducer validates the selected reachable chain, not the future complete
18-form launch catalogue. It adds no live command, save-schema change, acquisition reset, or menu.
A future authenticated service must commit the whole ledger through revision/receipt protection,
preserving unrelated owned/profile fields. The authored Studio game and prototype roster are unchanged.

### Mythling-sale logic review

`ServerScriptService.Services.InventoryService.MythlingSales.Sell` is a feature-private pure
operation selecting one owned Mythling with its expected current form and quoted Gold value. The
current form's optional `sale = { gold }` metadata owns eligibility and payout; no sale definition
means not sellable. Tests use synthetic forms with the approved 25/100/300-Gold launch prices,
without changing the unfinished roster.

The Mythling must be unassigned, including from a full Shrine. Final-copy sales are allowed. Level,
XP, inactive legacy Luck/Traits, rarity, and acquisition route never multiply the configured value.
Evolution changes which form supplies that value. Stale form/price requests, assigned workers,
invalid metadata, and unsafe Gold arithmetic reject without changing inputs.

Success settles the whole production ledger normally, removes only the selected worker, and returns
the replacement ledger and Gold balance together. Earned Shrine work and other workers' XP remain;
remaining pending XP leaves with the sold instance and never transfers to a replacement. Selling
does not force a partial batch, collect Shrine output, or touch crafting reservations.

Tests cover fixed prices, assignment/removal and evolution sequences, stale/repeated requests,
accounting boundaries, final-copy sales, overflow rollback, and detached serialized results. A future
authenticated adapter must commit the ledger, canonical owned-record deletion, Gold, and request
receipt atomically, serialized with assignment/evolution. This increment adds no live sale endpoint,
save-schema change, catalogue change, or menu. Prototype deletion remains separate and now rejects
canonical forms or retained entries with Shrine assignments/pending credit; it is not a sale API.

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
