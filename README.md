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
paths. The definitions are not exposed through the service context: metadata validation alone does
not activate them in the Arena or menus. Canonical capture grants, Shrine commands, evolution, and
Mythling sales consume the relevant metadata directly. The catalogue itself does not rewrite
existing `typeId` values or change the save schema.

### Canonical capture-grant review

The existing server-only `InventoryService.SaveWonMythling(player, params)` boundary now accepts
the 18 canonical launch forms through private `CaptureGrant`. A successful grant retains the exact
caught form and creates one owned instance with level 1, XP 0, and explicit pending XP 0. It grants
no Luck, Trait, copied rarity/Yield/sale value, automatic assignment, or Gold. Existing progression
and inactive legacy records remain unchanged.

The closed selection is `{ typeId, variantId }`; canonical forms accept only the retained
`"regular"` sentinel, not a cosmetic variant or model binding. The grant validates supported
form/variant IDs, current-schema owned state, owned-instance identity, server time, and available
Mythling capacity. Ownership creation and the repeated capacity check share one `DataService.Update`
transaction. ClaimService owns the non-yielding contest resolution
that prevents a second award; this is not a client-request endpoint or a retryable purchase API.
An asynchronous save request does not establish durable delivery. See the
[grant contract](docs/TECHNICAL_DESIGN.md#canonical-capture-grant-boundary).

Run the static suite and runtime tests above. Tests cover canonical grant defaults and rejection
boundaries while retaining unrelated saved data. After syncing, the authored Arena still captures
its three known prototype forms: their compatibility path remains enabled, but unknown IDs are
rejected. Activating the 18-form spawn pool still requires approved asset bindings and spawn
integration; no new model mapping, UI, remote, or schema migration is added here. Verify actual
connected-player capture, reset/rejoin retention, and durable saves separately from injected and
serialized-state tests.

### Launch Material catalogue review

The six normal Materials now have stable element-based IDs and matching Shrine output references;
see the [catalogue contract](docs/TECHNICAL_DESIGN.md#launch-material-catalogue). Display names such as
`Fire Material` are temporary and thumbnails are empty until the final names/icons are chosen.
Each launch Material is configured to buy for 10 Gold, sell for 2 Gold, and stack to the shared
1,000-unit limit. Metadata alone adds no purchase or sale action; the server-only Material
sale/discard commands below consume these shared definitions.

`MaterialCatalogUtil.Validate` checks the real catalogue before server services start. Run the static
suite and runtime tests above; catalogue tests include invalid element coverage, output references,
prices, and stack limits. Then sync and start a fresh Studio play session to check normal startup and
the existing prototype capture/stand-production/collection flow. The retained prototype Materials
are marked `launchEnabled = false`, but this flag does not disable or rewrite those existing paths.
Catalogue validation adds no save-schema change, UI, Shop, or crafting integration.

### Launch Equipment catalogue review

`Equipment.definitions` and `EquipmentRecipes` describe the wooden pair and twelve named elemental
items without granting or equipping them. `EquipmentCatalog.Resolve(definitionId, finishId)` returns
their fixed rarity, name, element, sword-effect reference, sell value, and shared base profile.
Crafted definitions require a valid finish; plain wooden items reject one. Names are not lookup keys.

`EquipmentCatalogUtil.ValidateLaunch` checks definitions, recipes, effects, Material references,
and resale relationships before startup. Run the verification commands above; real-catalogue tests
also pin the approved initial values and unchanged wooden gameplay. Server loadout/combat resolution
uses the canonical definitions; the unchanged client still uses the wooden-only `profiles` map.

Crafted model bindings and thumbnails are explicitly empty while assets remain undecided. There is
no wooden-model fallback, GUI change, saved-stat copy, Shop purchase, or active elemental effect yet.
The headless crafting and atomic loadout commands consume this catalogue, but unbound crafted items
cannot pass the server's mounted-Equipment action checks. See the
[catalogue contract](docs/TECHNICAL_DESIGN.md#launch-equipment-catalogue).

### Starter initialization and atomic loadout review

The recurring player template has empty Equipment and loadout tables. Schema preparation grants the
protected wooden pair and initial slot references only for clearly untouched initialization state;
it does not refill chosen empty slots, replace missing items, or reinterpret ambiguous retained
progress as a new player. Reconnect/reset preserves the saved selection. See the
[initialization contract](docs/TECHNICAL_DESIGN.md#one-time-starter-equipment-initialization).

Server-only `CombatService.EquipEquipment` and `UnequipEquipment` use revision-bound transactions
and exact owned identities. Equip derives the slot from metadata; unequip requires the expected
slot occupant. The existing `Combat.Equip` endpoint now adapts its instance-only request to that
atomic command, while `Combat.GetLoadout` is read-only and never selects a replacement automatically.
See the [request/result contract](docs/TECHNICAL_DESIGN.md#atomic-loadout-implementation).

Only a fresh successful selection change updates the current live character: it invalidates the
old swing authorization, removes guard protection, and rebuilds attachments without resetting
Stamina, cooldowns, swing locks, or an existing lowering deadline. Replays and unchanged selections
skip those runtime effects. Server actions require the exact owned instance, definition, finish,
and matching hand-mounted model. Client/GUI integration is unchanged; crafted assets remain unbound,
with no wooden fallback or active elemental effects.

Run the verification commands above for one-time defaults, retained/ambiguous saves, empty-slot
reconnects, stale/replayed commands, compatibility, mount identity, and rollback. Playtest normal
wooden combat, death/reset, and Equipment changes during attack/guard transitions separately.
In-memory and serialized tests do not prove durable persistence or crafted combat readiness.

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
as a copied limit. The server-only expansion and crafting commands are described below; Station
interaction remains separate work. Existing stand gameplay remains available.

After syncing source and starting a fresh play session, inspect the player's runtime Base attributes:
`UsedShrineSlots = 0`, `UnlockedShrineSlots = 2`, `MaxShrineSlots = 6`. The existing
`PB_CraftingStation_Root` should have `OwnerId`, `StationInstanceId`, and
`StationDefinitionId = basic_crafting_station`. Reset should retain that identity and leave normal
stand assignment/collection intact. There is intentionally no new Station prompt or menu. Automated
tests cover schema additions, identity reuse after serialization, derived capacity, safe runtime
allocation failure, and Base reconstruction; they do not establish live save durability.

### Atomic Base-expansion review

`BaseService.ExpandBase(player, request)` purchases the next permanent Shrine-only build slot through
one server-side transaction. Starting from two slots, four sequential purchases reach the six-slot
MVP maximum. `Configurations.Bases` owns prices: 10,000/50,000/150,000/500,000 Gold plus
50/100/150/200 of **each** normal Material respectively. The permanent Crafting Station has no cost
and never consumes a Shrine slot.

Requests contain `requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`,
`expectedUpgradeCount`, `expectedGoldCost`, and `expectedMaterialQuantity`. The Material quote is
the quantity for each of the six fixed ingredients, not their combined total. The server resolves
the next expansion and full Material mix; the caller cannot substitute elements, choose a target
slot, or skip purchases. Reuse the original request for retries so its receipt returns the original
result without spending again. Stale progression or prices are rejected rather than silently changed.
Success returns `previousUpgradeCount`, `upgradeCount`, `unlockedShrineSlots`, `maxShrineSlots`,
`goldSpent`, and `materialsSpentPerType` in the transaction's `values`.

Only collected Inventory Materials and owned Gold pay for the expansion. Shrine storage and crafting
refund reservations are not payment, and reservations are not released. The purchase preserves
existing Shrine slots/workers/output/XP, the production clock, Station identity, and other upgrades.
It adds one empty logical build slot without requiring a particular Shrine layout or ownership of
all six elements. There is no construction timer or production multiplier.
The full payment mix must fit the existing Material capacity alongside active refund reservations;
the new Base slot cannot supply capacity for its own ingredients. Confirmed State exposes the
derived Base status, and an existing runtime Base's capacity attributes refresh after success.

Run the static suite and runtime tests above, then verify connected-player dispatch and saved
purchase retention through reset/rejoin in a suitable playtest. Tests cover sequential purchases,
fixed-mix affordability, stale/replayed requests, capacity limits, and preservation of unrelated
state; they do not prove durable saves. This command adds no GUI, remote, model placement, or schema
migration. See the [command contract](docs/TECHNICAL_DESIGN.md#atomic-base-expansion-command).

### Atomic Inventory-capacity upgrade review

`InventoryService.UpgradeCapacity(player, request)` buys the next capacity upgrade for exactly one
category on the player's already-loaded profile. Materials and Equipment each progress from
12 to 24 to 36 slots; Mythlings progress from 24 to 36 to 48. The three purchase counts are independent.
Every category's first upgrade costs 20,000 Gold plus 50 of each normal Material, and its final
upgrade costs 300,000 Gold plus 200 of each. The server resolves these configured prices and limits.

The closed request contains `requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`,
`category` (`materials`, `mythlings`, or `equipment`), `expectedUpgradeCount`, `expectedGoldCost`,
and `expectedMaterialQuantity`. The Material quote is per type across the fixed six-Material mix.
No substituted ingredient, skipped upgrade, or purchase beyond the category's second upgrade is
accepted. Reuse the original request for retries; stale counts/prices reject instead of changing
what is purchased, and recorded receipts prevent duplicate payment or capacity grants.
Success returns `category`, `previousUpgradeCount`, `upgradeCount`, `limit`, `maxLimit`, `goldSpent`,
and `materialsSpentPerType` in the transaction's `values`.

Payment and the selected purchased count commit in one transaction. The complete recipe plus active
refund reservations must fit the **old** Material capacity: upgrading Materials cannot make room for
its own payment. Gold and all ingredients must already be owned in Inventory; Shrine output and
crafting reservations cannot pay costs. Other categories, Equipment/Loadout, Mythlings, Base state,
Shrine accounting, and job reservations remain unchanged. No copied capacity is saved.

Inventory upgrades use no Shop stock allowance, need no refresh period, and remain owned through
refresh, reset, reconnect, and price changes. Reaching the final upgrade means maximum capacity,
not waiting for Shop restock. The shared fixed-payment rule also preserves existing Base-expansion
behavior; costs remain in their respective feature configurations.
`Inventory.capacityUpgradeCosts` owns these two prices; `Configurations.UpgradeMaterials` owns
the shared six-Material mix.

Run the static suite and runtime tests above for each category's two purchases, independent limits,
pre-upgrade payment capacity, reservation protection, stale/replayed requests, rollback, and retained
state. Connected-player dispatch and durable persistence still require playtesting. This increment
adds no GUI, remote, timer, Shop refresh, model, or schema migration. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-inventory-capacity-upgrade-command).

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
The commands below add settlement, assignments, collection, upgrades, and dismantling. Canonical
Shrine production also has the automatic profile lifecycle described below; UI integration remains
separate work.
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
identities, unrelated fields, and prototype stand behavior must survive. Schema preparation itself
awards no work or XP; the commands and automatic lifecycle below perform settlement separately.
Existing DataService saves own the new fields; tests and ordinary Studio mocks do not prove live
durable persistence. See the
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
Shrine upgrades, dismantling, Mythling evolution, sales, and profile lifecycle settlement. It does not
own a timer, remote, or menu action.
Callers must use it inside a DataService transaction; it neither authenticates a player nor
saves a profile by itself.
These tests do not establish live durable persistence.

### On-demand Shrine settlement review

`ProductionService.SettleShrines(player)` is a server-only command returning the normal transaction
result, with `values.settledAt` on success. It uses the player's already-loaded profile and reads
server time inside its transaction; callers cannot provide elapsed time, metadata, or a ledger.
The service must be running and the player connected. The command itself starts no timer or save
checkpoint and adds no remote, menu, or changes to the existing stand paths. Automatic profile
settlement uses the separate lifecycle hook below, not this connected-player command.

Run the static suite and runtime tests above. Controlled DataSource tests cover transaction results
and repeated settlement, not live durable saves. Settling twice at the same time awards no duplicate
work, though each accepted `Update` has its own revision/receipt. Future worker or production changes
must settle and mutate in the same draft, not call this command before a separate transaction. See
the [command contract](docs/TECHNICAL_DESIGN.md#on-demand-shrine-settlement).
The disposable runner cannot create engine `Player` instances; automated service-gate tests cover
lifecycle and impostor rejection. Actual connected/disconnected-player dispatch still needs a playtest.

### Automatic Shrine-production lifecycle review

Canonical Shrine work and XP now settle before a prepared profile becomes publicly loaded, at
online checkpoints, and before normal release. `ProductionService` registers the pure
`ProfileProduction.Settle` hook during initialization; DataService owns the session boundaries and
runs every registered hook on one detached transaction draft with one server timestamp. An invalid,
erroring, yielding, or session-lost operation cannot partially commit accounting.

The private production clock adds optional `lastOnlineCheckpointAt` and `offlineSince` bookkeeping.
Existing schema-7 clocks with both absent remain valid: the first successful Ready settlement
initializes the checkpoint without resetting earned work or the batch schedule. Ready settles from
the saved accrual cursor before clearing the offline marker; checkpoints settle before advancing
their marker; release settles before recording the offline boundary. These markers neither replace
`lastAccruedAt` nor apply an offline bonus. Invalid partial or out-of-order markers are rejected.

`Production.onlineCheckpointIntervalSeconds` initially configures a 30-second Heartbeat-driven
checkpoint interval, separate from one-second accounting batches. The scheduler only visits already
loaded profiles, performs one catch-up settlement after a delayed tick, and stops with its service.
It never loads profiles or requests a save on each tick. The pure boundary hook remains available
when runtime production tasks stop so DataService can still finalize profiles.

Run the static suite and runtime tests above for clean release/reconnect, checkpoint recovery,
repeated boundaries, full-storage pauses, offline equivalence, preserved partial work/XP, invalid
markers, hook rollback, and scheduler cleanup. `SaveNow` checkpoints before requesting the normal
asynchronous save; this is not a durable acknowledgement. Final-save fallback and failed-release
behavior follow the [lifecycle contract](docs/TECHNICAL_DESIGN.md#automatic-shrine-production-lifecycle).
Actual join/leave/shutdown ordering and durable persistence still need live playtests outside the
default ephemeral Studio mock. No GUI, remotes, capture grants, schema bump, or prototype-production
migration are included; existing stand accrual remains separate.

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
collection, Shrine upgrades, dismantling, evolution, and sales use the engine through the shared adapter.
The profile lifecycle above uses the same engine. Migration of retained prototype work and final
content remain separate tasks; pure tests do not prove live persistence.

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
link; the canonical launch definitions use levels 6 and 40 without finalizing creative names/assets.

Evolution is manual and free, including while assigned or while Shrine storage is full. It settles
elapsed work under the old form before checking the earned level, then changes only that owned
worker's form ID. Identity, level, XP, pending credit, assignment slot, completed Materials, unfinished
work, and batch timing survive. Due XP can unlock evolution; incomplete batches are never awarded
early. An already-eligible Mythling can take two separate evolution actions at the same timestamp.

Tests cover eligibility, old/new-form production within a batch, stale requests, invalid/cyclic or
cross-element links, terminal forms, preserved inactive legacy fields, arithmetic rollback, and
serialized continuation. The reducer validates the selected reachable chain, while catalogue validation
checks all six complete launch chains. The server-only command below now commits the canonical form
change and accounting through revision/receipt protection, preserving unrelated owned/profile fields.
The pure operation itself adds no authentication, save-schema change, acquisition reset, or menu.

### Atomic Mythling-evolution command review

`InventoryService.EvolveMythling(player, request)` is a server-only command for the running service
and a connected player's already-loaded profile. `Types.EvolveMythlingRequest` contains only
`requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`, `workerId`, `expectedFormId`,
and `expectedTargetFormId`. Retry the original request unchanged. Success returns `workerId`,
`previousFormId`, `formId`, `level`, `xp`, and `settledAt` in transaction `values`; pending XP stays
private.

One `DataService.Transact` callback uses one server timestamp and real launch evolution links to
settle prior work under the old form, check eligibility, and update only the selected owned `typeId`.
Evolution is free and manual, including while assigned. Due XP can satisfy the configured level
requirement, but unresolved partial-batch credit is never awarded early. Identity, level, XP,
pending credit, assignments, stored output, unfinished work, inactive legacy fields, and the common
schedule survive. A sufficiently leveled Mythling can follow the next link in a separate request
without retraining.

Failed evolution rolls back gameplay changes, including staged accounting, though DataService may
record a rejection receipt and revision. Identity/current-form/target-bound receipts replay the
original result without resampling time or evolving again. Run the static suite and runtime tests
above for eligibility, all six chains, stale selections, replay, rollback, and retained-state checks.
Actual connected/disconnected-player dispatch and durable saves still need a playtest. This adds no
remote, menu, capture grant, schema migration, automatic production lifecycle, profile auto-load, or
explicit save request; the prototype roster remains unchanged. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-mythling-evolution-command).

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
accounting boundaries, final-copy sales, overflow rollback, and detached serialized results. The
server-only command below commits the ledger, canonical owned-record deletion, Gold, and request
receipt atomically, serialized with assignment/evolution. The pure operation itself adds no
authentication, save-schema change, catalogue change, or menu. Prototype deletion remains separate
and rejects canonical forms or retained entries with Shrine assignments/pending credit; it is not a
sale API.

### Atomic Mythling-sale command review

`InventoryService.SellMythling(player, request)` is a server-only command for the running service
and a connected player's already-loaded profile. `Types.SellMythlingRequest` contains only
`requestId` (`<expectedRevision>:<unique token>`), `expectedRevision`, `workerId`, `expectedFormId`,
and `expectedGoldValue`. Retry the original request unchanged. Success returns `workerId`, `formId`,
`goldGranted`, and `settledAt` in transaction `values`.

One `DataService.Transact` callback uses one server timestamp and the current canonical form's sale
metadata to validate ownership, unassignment, and the expected form/price. It settles accounting,
removes exactly the selected owned Mythling, and credits Gold with the receipt in the same draft.
Final-copy sales are allowed; assigned workers must first be unassigned, even if storage is full.
Level, XP, acquisition route, and inactive legacy values never modify the payout. The sold worker's
remaining pending XP retires with that instance; every other worker's progression, earned Shrine
work, Materials, and unrelated currency fields survive. The shared Gold-credit guard also retains
headroom for every active canonical job's exact paid-Gold refund. DataService may resolve a due job
as transaction preparation, described below; the sale itself never consumes its reservations.

Failed sales roll back gameplay changes, including staged accounting, though DataService may record
a rejection receipt and revision. Identity/form/price-bound receipts replay without resampling time,
settling again, or paying twice. Run the static suite and runtime tests above for configured payouts,
stale selections, assignment gates, replay, rollback, and retained-state checks. Actual connected/
disconnected-player dispatch and durable saves still need a playtest. There is no new remote, menu,
capture grant, schema migration, production timer, profile auto-load, or explicit save request.
Prototype capture/stand paths remain unchanged. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-mythling-sale-command).

### Atomic Material-sale and discard review

`InventoryService.SellMaterial(player, request)` and `DiscardMaterial(player, request)` operate on a
connected player's already-loaded profile. Exact quantity/owned-total selections and sale-price
quotes reject stale state rather than clamp to another amount; unchanged retries replay their
receipt. Only the six enabled normal Materials are eligible. Sale grants the configured payout
(initially 2 Gold per Material); discard grants zero Gold and leaves currency untouched.

Materials must first be collected from Shrine storage. Neither command collects or settles Shrine
work, spends crafting reservations, resets Shop stock, or blocks removal merely because Inventory
is over capacity. Sale also protects exact paid-Gold refund headroom. DataService can resolve due
jobs before the requested mutation in the same transaction. See the
[command contract](docs/TECHNICAL_DESIGN.md#atomic-material-sale-and-discard-commands)
for closed request/result fields and numeric-safety rules.

Run the static suite and runtime tests above for all six IDs, partial/full removal, stale quotes,
replay/conflicts, overflow, rollback, reservation retention, and over-capacity recovery. Playtest
connected-player dispatch and durable retention separately. There is no new GUI, remote, schema,
timer, profile auto-load, or explicit save request.

### Equipment sale review

`InventoryService.SellEquipment(player, request)` is a server-only, revision-bound command.
Select an owned instance with its exact definition/optional finish and quoted Gold value. The
command requires it to be unequipped, protects original starter grants, resolves the fixed sale
value from metadata, and removes the item and credits Gold in one transaction. All twelve crafted
variants initially sell for 25 Gold, independently of their acquisition route. Crafting refund
headroom remains protected, and retries cannot sell twice. The sale itself never changes loadout,
jobs, reservations, or Shrine work; shared transaction preparation may complete a due job first.

See the [Equipment sale contract](docs/TECHNICAL_DESIGN.md#atomic-equipment-sale-command).
Run the verification commands above for variant identity, ownership, starter/equipped rejection,
quote conflicts, numeric limits, and rollback. The sale adds no GUI, remote, asset binding, or combat
effect; loadout edits use the atomic commands above. Connected-player and durable-persistence checks
remain separate.

### Headless crafting and mutation preparation review

`CraftingService.StartJob(player, request)` and `CancelJob(player, request)` are server-only,
revision-bound commands for connected players with loaded profiles. Start validates the permanent
Station and exact recipe quote, charges Gold/owned Materials, and reserves Equipment output plus
Material refund space. One active job is allowed. The twelve launch recipes initially cost 50 Gold
and five matching Materials, produce one named elemental item, and take 60 seconds.

Versioned receipts retain actual payments, exact definition/finish and generated output IDs, and the
server deadline. Due jobs grant that recorded output automatically without equipping it; unfinished
cancellation refunds exactly the recorded costs. Completion wins at the deadline. Changed recipes,
reconnects, and later capacity reductions do not reprice or replace an existing promise. Gold sales
cannot consume the safe-integer headroom reserved for cancellation. Up to 32 canonical resolved
jobs are retained, with the just-resolved record protected during that pruning pass; opaque legacy
records are preserved, including multiple retained active prototype jobs. Any such active job blocks
a new start without gaining an invented refund or preventing valid canonical due completion.

DataService runs registered mutation preparation before each admitted `Transact`/`Update` callback,
using one timestamp and detached draft. Due resolution and the requested action commit together;
an action rejection rolls both back. Receipt replays and stale requests skip preparation. Crafting
also resolves on Ready/Checkpoint/Release, before exposure/finalization, and a configurable
one-second scheduler requests resolution only for already-loaded profiles with due jobs. These
hooks remain usable after CraftingService stops. Direct prototype Base `MarkDirty` writers are not
covered by preparation or rollback.

Run the verification commands above for receipt replay/conflicts, exact-deadline cancellation,
reserved space, safe Gold refunds, recipe edits, serialized continuation, malformed state, ID
collisions, session loss, and callback failures. Inspect connected-player dispatch, shutdown, and
durable retention separately; a successful transaction or asynchronous save request is not a
durable acknowledgement. No GUI, remote, Station prompt, model binding, or crafted combat is added.
See the [implementation contract](docs/TECHNICAL_DESIGN.md#headless-crafting-implementation) for
request/result fields and compatibility boundaries.

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
