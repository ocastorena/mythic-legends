# Mythic Legends — Technical Design

This document is the canonical implementation contract for architecture, networking, persistence,
transactions, and source ownership. The [GDD](GDD.md) owns gameplay rules, progression, launch
scope, pacing targets, and gameplay acceptance criteria. [UI guidelines](UI_GUIDELINES.md) own menu
behavior and presentation. [Conventions](CONVENTIONS.md) owns project structure and coding practices;
the [README](../README.md) owns setup and verification commands. Runtime tuning lives in
[shared configuration](../src/ReplicatedStorage/Shared/Configurations).

Requirements below describe the approved launch target unless explicitly labeled as current
implementation or a future update. Moving a contract into this document does not mean the prototype
implements it. See [implementation alignment](#implementation-alignment) before treating target schemas or transactions
as available APIs. Technical work must not add excluded or unapproved gameplay. The full Divine
Intervention system remains deferred and requires separate design approval. The existing public
`/admin event blockstorm` visual prototype is explicitly enabled; other launch systems must not
depend on it.
Ragdoll requires explicit post-launch approval. The GDD's six [elemental sword
effects](GDD.md#elemental-sword-effects) are approved for launch: first-crafted swords share the
wooden sword's base statistics and each adds its configured effect. All first-crafted Shield
variants share gameplay values and have no elemental ability. Launch Equipment types are
one-handed swords and separate Shields, progressing from the plain wooden starter pair to Stage 1.
Additional archetypes and Stage 2 or later upgrades are future updates. Higher-stage stat divergence
still needs its detailed design and implementation contract; launch needs no Equipment-upgrade
endpoint or transaction.

## Runtime architecture

The first release uses the approved Rojo Bootstrap architecture and ProfileStore-backed player
persistence. `default.project.json` defines the canonical Roblox Explorer hierarchy; Studio-authored
descendants are preserved only at explicitly mixed-ownership containers.

- **MainServer** is the only server bootstrap. It initializes modules under
  `ServerScriptService.Services` in deterministic lifecycle order and owns the player join/leave
  wiring. It explicitly starts the existing `PostLaunch.DivineInterventionService` visual prototype
  through the same lifecycle. No other post-launch services are auto-loaded.
- **Server services** own validation, authoritative simulation, mutations, persistence requests, and
  grants. No domain service independently loads a profile or writes a Roblox DataStore.
- **Feature-private modules** live beside their owning service's `init.lua`. Pure reducers there are
  directly testable but are not auto-started, remotely exposed, or part of the service's public API
  unless `init.lua` deliberately delegates to them.
- **Server-only shared modules** under `ServerScriptService.Shared` own contracts, arithmetic, and
  support used across feature services. They are not client-visible. `Infrastructure` separately
  owns technical runtime mechanisms such as logging, remotes, rate limits, and lifecycle support;
  it does not own gameplay or economy policy.
- **MainClient** is the only client bootstrap. It initializes state/networking before feature
  controllers under `StarterPlayerScripts.Controllers`.
- **Client controllers** own input, UI, local animation, sound, VFX, and rendering of
  server-confirmed state. They cannot mutate persistent player data, Arena ownership, capture state,
  or economy state.
- **Shared configuration** is version-controlled Luau content under
  `ReplicatedStorage.Shared.Configurations`. It contains static definitions and balance values only;
  it must never be written at runtime.
- **DataService** owns one ProfileStore session per Roblox user ID using the configured development
  namespace `MythicLegends_MVP_v1`. It reconciles defaults, associates the user ID, handles session
  termination, and ends the session when the player leaves. At launch readiness, the approved
  one-time switch to `MythicLegends_v1` leaves both the old prototype and development stores
  untouched. Within whichever namespace is active, forward-only schema upgrades
  add Base ownership, Shrine slots/levels, and schema-7 accounting before reconciliation; the old v2-to-v3
  prototype migration is not invoked.
  Future target-schema changes still require explicit migrations; reconciliation alone is not a
  migration. Registered pure profile hooks settle canonical production before loaded-state
  publication, at online checkpoints, and before release. Studio uses an isolated, ephemeral mock
  store by default.
- **Combat is the stated exception.** Its client-reported, server-validated relay and immediate
  local presentation remain exactly as defined in [client-reported sword
  combat](#client-reported-sword-combat). This architecture must not be changed by the general UI
  synchronization rule below.

## Initial loading

`ReplicatedFirst.LoadingScreen` owns the early loading presentation and its private `Assets` helper.
Preload only the initial view: visible startup UI, the current character, and nearby spawn geometry
selected from explicit map and owned-base roots. Do not scan all of Workspace/ReplicatedStorage or
preload catalogues, unopened menus, other players' bases, or every island at join.

Request streaming once around the actual character position, with the player's own Base Spawn as a
fallback. Bounded readiness checks re-resolve the character root, owned Base Spawn, and HUD as they
arrive; an empty container or global descendant count is not a readiness signal. Preserve the loading
timeout, minimum display, fade, and owned input/camera cleanup. Later content loads when needed.
Validate cold joins on target devices before claiming a load-time improvement.

## Project structure and coding conventions

`ServerScriptService.Shared.ProductionLedger` is the server-only accounting contract used by
production accrual and data migrations. Its placement makes the cross-feature dependency explicit
without exposing a service's private implementation or replicating it to clients.
`ServerScriptService.Shared.Types` owns server service protocols;
`StarterPlayerScripts.Types` owns client controller and view-prop contracts. Saved-state, payload,
and configuration types needed by both runtimes remain in `ReplicatedStorage.Shared.Types`.
Feature-specific pure operations live beside the owning service: Base owns assignment, Shrine
upgrade, and dismantling; Production owns Shrine collection; Inventory owns Mythling evolution and
sale. Base owns assignment, upgrade, and dismantling commands, Production owns settlement and
collection, and Inventory owns evolution and Mythling sales. Canonical action endpoints delegate
to these command owners; automatic settlement remains server-only.
`Shared.ShrineAccounting` is the common transaction-draft adapter consumed by Base,
Production, and Inventory. Tests may require pure children directly.
Combat geometry helpers likewise remain private children of CombatService.

[Conventions](CONVENTIONS.md) owns the [repository layout](CONVENTIONS.md#project-structure),
[Roblox Explorer hierarchy](CONVENTIONS.md#roblox-explorer-hierarchy), naming, file organization,
typing, lifecycle cleanup, formatting, and logging rules. `default.project.json` is the executable
source of the Rojo mapping. This document retains runtime responsibilities, network and persistence
contracts, UI ownership, and the [Studio/Rojo boundary](#roblox-studio-and-rojo-ownership).

## Network contract

Rojo is the only creator of production remotes. `RemoteUtil.Resolve` validates their classes and
returns the typed domain structure; it must not silently create or replace missing remotes.

```text
Network
  Admin       Feedback
  State       Update, Request
  Inventory   EvolveMythling, SellMythling, SellEquipment, SellMaterial, DiscardMaterial,
              UpgradeCapacity, DeleteMythling (retired compatibility response)
  Shop        GetShop, BuyOffer
  Crafting    GetStation, StartJob, CancelJob
  Production  GetStatus, Collect, CollectShrine
  Base        GetBase, BuildShrine, ExpandBase, GetShrine, AssignShrineWorker,
              RemoveShrineWorker, UpgradeShrine, DismantleShrine, PlaceMythling, RemoveMythling
  Combat      StartAttack, ReportHit, SetShieldGuard, Reaction, Impact, GetLoadout, Equip,
              EquipEquipment, UnequipEquipment
  World       Spawned, ClaimState
```

- Client-to-server messages are untrusted intent. The owning service validates types, lengths,
  ranges, ownership, permissions, world state, and cooldowns before mutating anything.
- Every client-triggered endpoint must have an appropriate server-side rate limit. Client-side
  debounce exists only for responsiveness and is never a security boundary.
- Apply request admission before profile access or other protected work. Rejections must remain
  small and must not construct full state snapshots or start profile loads. `Combat.GetLoadout` and
  `Combat.Equip` use already-loaded profiles; while bootstrap is loading, return `NotReady`.
  Failed loadout responses omit `snapshot`; clients keep their last confirmed view. Successful
  responses retain the existing snapshot fields, including a valid empty Equipment collection;
  owned entries additionally carry optional `finishId`. Get is read-only, and the existing
  instance-only Equip endpoint uses the [atomic loadout adapter](#atomic-loadout-implementation).
- Use a `RemoteEvent` when no immediate response is required. Use a client-to-server
  `RemoteFunction` only when the caller needs an explicit success or error result. Never invoke a
  client synchronously from the server.
- Reliable gameplay state uses `RemoteEvent`; disposable high-frequency cosmetic telemetry may use
  `UnreliableRemoteEvent` only when loss and reordering are acceptable.
- Persistent state is confirmed through the revisioned State channel. Domain remotes do not accept
  arbitrary state keys, Instance paths, or generic mutation commands.

This endpoint inventory matches [default.project.json](../default.project.json). Declared endpoints
do not establish authored interaction bindings, GUI integration, or verified live-client dispatch.
`Inventory.DeleteMythling` is a non-mutating compatibility response, never a sale API.
Existing remote names stay unchanged unless an explicit migration updates declarations, resolver
types, server handlers, and client callers together.

### Inventory request endpoints

`Network.Inventory` declares six canonical RemoteFunctions: `EvolveMythling`, `SellMythling`,
`SellEquipment`, `SellMaterial`, `DiscardMaterial`, and `UpgradeCapacity`. Each accepts the matching
closed request type in `Shared.Types` and returns the existing `TransactionResult` unchanged.
`InventoryRemotes` binds them to the public InventoryService facade rather than constructing a
second set of mutation handlers. Its private `InventoryRequests` adapter forwards the original
payload; the owning command validates exact fields, quotes, ownership, and action-specific rules.
There is no client-selected target Player, arbitrary mutation key, price override, or timestamp.

Availability requires a running endpoint lifetime and the genuine connected calling Player. One
shared per-player budget admits all Inventory endpoints before profile access or other protected work;
`Configurations.InventoryRequests` initially allows a burst of six and refills two per second.
Unavailable/rate-limited canonical calls return `DataUnavailable`/`RateLimited` with revision zero.
Inventory actions are globally available, without character-alive, proximity, Base, or Arena gates.
Neither the adapter nor its rejection path loads profiles, constructs snapshots, changes saved state,
settles production, requests a save, unassigns workers, or unequips items. Canonical transactions retain
their existing shared preparation and settlement rules. Departures forget request buckets; Stop
clears all seven handlers and buckets, and retained callbacks reject after the lifecycle closes.

Do not preflight ownership, quantities, form, progression, or price before forwarding a retry:
transaction receipt lookup must still replay a committed sale after its item is gone or an evolution
after its form changed. Use projected `transactionRevision` for `expectedRevision`, never the State
packet sequence, and retry the original revision-bound envelope unchanged. Confirmed projected owned
identities/quantities and static catalogue metadata supply sale/evolution quotes; Shop's read-only
upgrade rows supply capacity quotes. These are selections, not authority; the server revalidates them.
No additional full Inventory snapshot or private reservation/pending-XP/receipt projection is added.

The old `DeleteMythling` RemoteFunction stays declared so existing clients can resolve it, but admitted
calls always return `{ ok = false, code = "UnsupportedAction" }`. It never reads/deletes a Mythling,
settles work, unassigns a stand, grants Gold, or starts a transaction. Unavailable and rate-denied
legacy responses keep its small `{ ok, code }` shape. In particular, the former unassign-before-delete
sequence is removed: a rejected legacy request cannot alter placement or earned work. Do not silently
translate instance-only deletion into a sale. Removing its old menu caller belongs to the separate
GUI integration. Live-client transport and durable persistence remain independent verification gates.

### Public admin chat commands

`AdminCommandService` is the single server listener for `TextChatService.AdminCommand`. Its strict
`/admin <command> <argument>` parser accepts `teleport` with a configured element or `base`, and
`event blockstorm`. The previous direct `/admin blockstorm` spelling is removed; no `tp` or `help`
command is registered. All current players have access, preserving the public prototype policy.
Malformed requests cannot select another player or pass an arbitrary position/Instance path.

`Configurations.AdminCommands` owns request limits, streaming timeout, landing clearance, and the
element-to-model mapping. Island markers are `Markers.TeleportPoint` children of the configured
models under `Workspace.World.ElementalIslands`, consistently named `<Element>Island`. The
configuration's `islandName` selects the model; missing markers remain unavailable.
`BaseService.GetSpawnPoint` resolves only the requesting player's assigned Base through its server
slot ownership records. The teleport helper verifies a living, unseated character, an anchored and
level marker, walkable ground, and overhead clearance before moving the character with `PivotTo`.
It accounts for avatar height and preserves the model's root-to-pivot offset, then clears existing
linear/angular velocity without resetting character or player data.

Only one teleport may be pending per player. Streaming is requested with a bounded timeout when
enabled; character identity, marker identity/transform, destination validity, and service lifecycle
are checked again after the yield. Reset, disconnect, or shutdown invalidates the pending move.
Stamina, action deadlines, elemental effects, and capture state stay with their owning services;
ordinary position-based Arena/ring checks handle the new location.

`DivineInterventionService.StartEvent` exposes only the existing Blockstorm presentation and retains
its single-event guard and shutdown cleanup. It no longer owns a chat listener.
`Network.Admin.Feedback` is server-to-client only: the server sends authored messages exclusively to
the requesting player. `AdminCommandController` displays them in the standard system chat channel,
with the existing toast system as fallback. Unfiltered command text is never echoed to clients.

## Client/server state synchronization

For every system other than the documented combat exception, clients send an intent request and wait
for a server-confirmed result before changing authoritative UI state.

1. The client may immediately show input feedback and a pending/loading state.
2. The server validates the request against the cached player document, metadata, runtime
   eligibility, capacity, affordability, and permissions.
3. For persistent mutations, the server uses a duplicate-safe DataService transaction while the
   ProfileStore session is active. The owning service applies runtime-only mutations without adding
   them to the profile. The server then returns or replicates the authoritative result.
4. The client updates inventory, Gold, Shrine output, Crafting Jobs, capture state, Equipment,
   Stamina, and elemental effect state only from that confirmed result. Future Consumable buffs
   follow the same rule.
5. A rejection does not spend costs or grant the requested result and supplies a player-facing
   reason when appropriate, such as `InventoryFull`, insufficient Gold/Materials, invalid selection,
   unavailable capacity, or not-in-Arena. Independent elapsed production, completed jobs, or Stamina
   accounting may still advance.

Capture meters, Stamina, active Shield state, temporary knockback immunity, elemental effect state
and deadlines, and active Arena contests are server-owned runtime state. They are not persistent;
they clear on disconnect or server shutdown. Reset clears the affected character's active/pending
effects and all capture progress. Arena transitions and Equipment changes preserve already-applied
effects and their deadlines. Owned Mythlings, earned Gold,
and other confirmed persistent progression are retained under the normal player-save contract.
Active Consumable buffs do not exist at launch, and their future disconnect behavior remains a
separate design decision.

Private player UI state uses a client-ready `Network.State.Request` snapshot followed by revisioned
incremental `Network.State.Update` packets. Only an explicit client-safe projection may be
replicated; the complete ProfileStore document, permissions, internal flags, and server-only state
must never be sent to the client. `LocalData` owns the client cache and change signal. A missed or
out-of-order revision triggers a bounded snapshot resynchronization instead of polling.

The [network contract](#network-contract) defines endpoint ownership and transport rules. Runtime
combat values may use an explicit server-confirmed presentation channel; they must not be added to
persistent profiles merely to display them.

### Transaction and save guarantees

- Serialize persistent mutations per active profile. Validate against the same state that will be
  committed, then atomically apply every affected field and the request's resolution record. A
  failure must not leave a deducted cost without its result, receipt, or refund guarantee.
- Keep request IDs and bounded resolution records sufficient to reject stale/replayed commands or
  return the original result. Reusing an ID with a different payload is invalid. The same
  transaction includes inventory, currency, assignment links, reservations, and production cursors
  whenever they are affected together.
- In-session atomicity and durable persistence are distinct. A confirmed runtime mutation must be
  included in the profile's save lifecycle, but requesting a save is not proof it reached durable
  storage. An operation that requires durable acknowledgement must observe its transaction ID in the
  persisted save result before claiming that guarantee.
- `DataService.Transact` uses an already-active profile, stages edits on a detached document, rejects
  yielding/erroring callbacks, and commits the resolution receipt with the resulting state. Callback
  code must not perform outside effects or mutate borrowed live records. IDs have the form
  `<expectedRevision>:<unique token>`; the owning server feature derives the operation/signature from
  validated input. Retries carry the original ID, revision, operation, and signature. Changed payloads
  conflict; stale revisions cannot execute after bounded receipt eviction. Successful and domain-rejected
  decisions retain their original result, without retaining unbounded history. Replication exposes the
  current transaction revision, never private receipts or request signatures.
- `DataService.Update` gives server-authored transitions the same atomic path with a fresh request ID.
  Their source must already prevent duplicate events; retryable purchase/job commands must instead use
  `Transact` with a stable original request. Existing capture grants/removals, Material grants, and
  stand production settlement/collection use this path alongside the canonical feature commands.
- `DataService.RegisterMutationPreparation(owner, callback)` registers an ordered, non-yielding
  draft rule before DataService starts; registration then closes. After a new request passes
  revision/replay admission, `Transact` samples one server timestamp, runs every preparation on its
  detached draft, then calls the requested mutation with that same draft and timestamp. `Update`
  uses this path too. Preparation never opens a nested transaction or publishes an intermediate
  result. A domain rejection rolls back preparation and action together while retaining the normal
  rejection receipt; an error, yield, or lost session commits neither gameplay changes nor receipt.
  Receipt replays, conflicts, and stale requests never run preparation. Crafting uses this boundary
  to resolve due promises before acquisitions and other transactional mutations. Feature-specific
  preservation rules below describe their own edits, not a prohibition on this shared due resolution.
- `DataService.RegisterProfileSettlement(owner, callback)` registers a server-owned, non-yielding
  lifecycle rule during initialization. Registration closes before profiles load. All callbacks for
  one Ready, Checkpoint, or Release boundary receive one draft and server timestamp inside one
  transaction; none may perform outside effects. `DataService.Checkpoint(player)` uses only an
  already-loaded active profile. See the [production lifecycle](#automatic-shrine-production-lifecycle).
- The transitional `MarkDirty` path publishes direct prototype Base changes and invalidates
  stale transaction revisions. It runs no preparation and supplies no rollback; do not treat a
  separate checkpoint before such a write as an atomic replacement. `SaveNow` only requests an
  asynchronous ProfileStore save, not durable acknowledgement. Keep these limitations explicit while remaining
  prototype writers are replaced.
- Keep the store name and profile-key namespace stable when increasing the document's schema
  version. Changing a namespace is a separate data migration, not a routine version increment.

**Approved data boundaries:** the 2026-09-28 implementation trial started schema 4 in the separate
`MythicLegends_MVP_v1` namespace without migrating or overwriting the old
`MythicLegends_PlayerData_v2` prototype store. Development remains on that namespace. When the
experience is ready to launch, change the configured store once to `MythicLegends_v1`; do not make
that change during ordinary development. The launch boundary starts fresh schema-7 profiles without
reading, copying, deleting, or overwriting either earlier store. New launch profiles receive the
configured 100 Gold, protected starter identities, Inventory-upgrade defaults, empty crafting
reservation bookkeeping, and private transaction state. This is a one-time release boundary, not a
reset mechanism. Reconnects and future updates retain balances and ownership in
`MythicLegends_v1`; later schema versions require ordinary forward-only migrations without changing
its name. Prototype `base.stands` and Mythling fields remain temporary compatibility state until the
Shrine/form slice replaces their consumers; this baseline does not declare them launch content or
establish the final roster.

## Client-reported sword combat

Gameplay behavior is defined by the GDD's [MVP player combat
system](GDD.md#mvp-player-combat-system) and [Shield actions](GDD.md#shield-actions). This protocol
preserves the approved MVP tradeoff: responsive visible-blade contact is reported by the attacker
and validated by the server. There is no independent server arc scan, position rewind, or
server-selected substitute target.

The logical message names used below are mapped to the existing endpoints:

| Logical message | Existing endpoint | Direction |
| --- | --- | --- |
| `MeleeSwing` | `Network.Combat.StartAttack` | Attacking client to server |
| `HitReport` | `Network.Combat.ReportHit` | Attacking client to server |
| Guard request/release | `Network.Combat.SetShieldGuard` | Owning client to server |
| Accepted launch | `Network.Combat.Reaction` | Server to target client |
| Confirmed impact | `Network.Combat.Impact` | Server to observing clients |

The logical names are explanatory labels, not additional remotes to create.

`StartAttack` carries `{ sequence, character }`; `ReportHit` carries
`{ sequence, character, targetUserId, targetCharacter }`. Both character references must match the
current characters when the server validates the request. `Reaction` includes the target character,
and the receiving client rejects reactions for a replaced character.

`SetShieldGuard` carries `{ action, sequence, character }`. `action` is `Begin`, `Raised`,
`Release`, or `Lowered`; `sequence` increases for each new press, and `character` must match the
sender's current character. Send `Begin` at press time and `Release` at release time, independently
of animation loading. `Raised`/`Lowered` report animation markers for the same attempt. Old-character
messages and stale markers cannot affect a later attempt. Release and lowering cleanup bypass the
activation rate limit. Keyboard guard uses `F`; right mouse remains camera input.

The server publishes character `GuardPhase` (`Lowered`, `Raising`, `Guarding`, `Lowering`),
`GuardSequence`, `ShieldGuarding` (actual protection), and `SwingLocked`. `GuardRequestSequence`
records a processed Begin request; `GuardRejectedSequence` identifies a rejected press in one
attribute, avoiding a split sequence/boolean acknowledgment. Client prediction grants no protection.
The client reflects insufficient Stamina and requires a fresh press after rejection or guard break.

### Combat Loadout presentation

Primary Weapons and Shields are character-mounted Models rather than Roblox `Tool` instances.
Entering the Arena moves an equipped sword and Shield from their authored sheath attachments to the
R15 right-hand and left-hand attachments respectively and enables their actions.
Leaving returns equipped Models to their sheath attachments and disables attack/guard without
changing the saved Combat Loadout or clearing existing elemental effects and their timers.
Either slot may be empty; an empty Primary Weapon slot permits Shield equip.

#### Atomic loadout implementation

Canonical `CombatService.EquipEquipment(player, request)` and `UnequipEquipment(player, request)`
require a running service, connected Player, and already-loaded profile. Private `LoadoutCommands`
uses the existing `DataService.Transact` path, including shared mutation preparation, under
operations `Combat.EquipEquipment` and `Combat.UnequipEquipment`.

Equip accepts only `requestId`, `expectedRevision`, `instanceId`, `expectedDefinitionId`, and
optional `expectedFinishId`. Unequip accepts only `requestId`, `expectedRevision`, `slot`
(`PrimaryWeapon` or `Shield`), and `expectedInstanceId`. IDs are nonempty and bounded to 128 bytes;
revisions are nonnegative safe whole numbers. Signatures bind the exact selection, with absent
finish distinct from any finish ID. Validate the schema, owned entry, saved slot references, and
canonical definition/finish pair inside the transaction. Equip derives its slot and compatibility
from metadata. Unequip requires the expected occupant but does not resolve it, so explicit removal
can recover an unsupported or dangling reference without deleting retained Equipment. The loadout
edit itself changes no ownership, starter protection, capacity, or static item metadata; shared
preparation may still resolve a due Crafting Job in the same transaction.

Equip success values are `instanceId`, `definitionId`, optional `finishId`, `slot`, `changed`, and
`shieldUnequipped`. Unequip returns `instanceId`, `slot`, and `changed = true`. Selecting the already
equipped compatible item succeeds with `changed = false`; selecting a different saved occupant
for unequip rejects with `SlotChanged`. Stale definition/finish quotes reject with `EquipmentChanged`.
The retained handedness rule can clear only the Shield reference when a two-handed definition is
equipped and rejects incompatible Shield equip; no such launch definition or attack is introduced.

`Combat.GetLoadout` only snapshots confirmed owned IDs/finishes and bounded saved slot references;
it never repairs or auto-selects an empty/unsupported slot. The existing rate-limited `Combat.Equip`
RemoteFunction remains an instance-only compatibility adapter. It resolves the owned selection and
uses a fresh server-generated revision-bound request ID for the canonical command. It does not
supply client-controlled retry identity; new retryable callers use the canonical request envelope.

`Combat.EquipEquipment` and `UnequipEquipment` are the Rojo-declared retryable RemoteFunctions.
`LoadoutRequests` binds their raw envelopes to those same public CombatService methods and returns
`TransactionResult` without a second snapshot or mutation path. Callers quote projected
`transactionRevision`, not the State packet sequence, and retry the unchanged request. Do not check
current ownership, slot, definition, or finish before canonical receipt lookup: a previous unequip
must replay even when the slot is now empty. The existing `afterLoadoutCommit` gate is the only
post-transaction reconciliation; successful replay and unchanged selections still skip it.

All four loadout endpoints share the configured request budget (initial burst 12, refill four per
second). Legacy Equip and both canonical changes share the existing 0.5-second mutation interval;
Get does not consume that interval. `Configurations.LoadoutRequests` owns these limits. Availability,
rate admission, and any change interval are checked before loaded-profile access. A not-ready profile
does not start the change interval. Canonical rejections return `DataUnavailable`/`RateLimited` with
revision zero and no snapshot; legacy response shapes/codes remain unchanged. No endpoint loads a
profile or requires an alive character, proximity, or Arena membership. The server validates the
genuine connected calling Player rather than accepting a target identity. Departure clears shared
request state; stopping removes all four handlers, and retained callbacks reject before doing work.

After a fresh successful `changed` commit, reconcile only the current live R15 character: force
guard protection off, invalidate the previous swing authorization, and rebuild attachments from
current saved state. Replayed receipts and unchanged selections skip these runtime effects. Keep
the existing accounting object, Stamina, attack cooldown, unfinished swing lock, immunity, sequences,
and any already-running lowering deadline. Combat timing stays in its monotonic `os.clock` domain;
the persistence transaction timestamp never advances or resets combat deadlines. Dead-character
presentation remains cleared until the next character initialization.

`LoadoutUtil` resolves ownership without writes. Mounted Equipment, authorized swings, and active
guard selections bind the exact instance ID, definition ID, and optional finish ID. Character/model
attributes and the hand Motor6D endpoints must match the saved selection before actions are eligible;
unknown or incompatible retained selections fail closed without rewriting them. Server resolution
and non-GUI client input use canonical definitions and finishes; existing previews and VFX retain
their compatibility map.
Crafted model bindings are empty and cannot mount or authorize combat; there is no wooden fallback
or GUI change. The accepted-hit path implements the elemental accounting described below,
but these transaction/runtime checks do not establish durable saves or complete crafted combat readiness.

#### Two-handed loadouts — future update contract

Additional archetypes are outside the MVP. When introduced, a two-handed weapon uses its authored
two-hand pose without a Shield. Enforce the GDD's [Equipment
compatibility](GDD.md#equipment-compatibility) on the server using the Primary Weapon definition's
static `handsRequired` value (`1` or `2`). Equipping a two-handed weapon
atomically clears `combatLoadout.shieldInstanceId` and removes protection without deleting the owned
Shield or changing its capacity use. Reject Shield equip while a two-handed weapon is equipped.
On load, reconcile an incompatible saved pair by retaining the Primary Weapon and clearing only
the Shield reference. Switching back does not automatically restore it; no restore record is saved.
An empty Primary Weapon slot permits Shield equip. Validate compatibility independently of whether
the weapon Model is drawn or sheathed, and preserve the action timing and Stamina rules below.
Archetype-specific attacks still need their own approved contracts; this retained design does not
require implementing two-handed Equipment for launch.

### Attacking client

1. One shared client attack function is the only source of a sword swing. Left click and the
   dedicated mobile Attack button may call that function, but they must not create duplicate
   activations for one input.
2. The client sends one `MeleeSwing` activation with a monotonically increasing sequence,
   immediately plays the visible swing animation, and opens its contact window from animation
   markers, with a configured timing fallback when an animation lacks those markers. A player with
   insufficient Stamina or an active Shield guard cannot begin a weapon action.
3. During that window, the client sweeps the visible sword blade through interpolated positions
   between rendered frames. Contact is based on the blade geometry, not a large character-centered
   cone.
4. The client excludes its own character and selects at most one eligible target: the target with
   the closest valid blade contact, breaking ties by attacker-to-target distance, then player user
   ID. Optional line-of-sight filtering may reject contact through solid geometry.
5. On first valid contact, the attacker immediately presents the configured hit effect, sound,
   trail, and brief animation hit-stop. It then sends exactly one `HitReport` containing the
   activation's swing sequence and the selected target's user ID.
6. A swing that finds no blade contact sends no hit report, but its activation still consumes the
   weapon's configured Stamina cost. Walking near another player without activating the sword must
   never produce a hit.

Private `CombatController.EquipmentSelection` resolves the replicated character's definition,
owned-instance, and finish attributes through `EquipmentCatalog`. Prediction requires the correct
hand/item kind, a nonempty configured model binding, matching model identity/slot attributes,
PrimaryPart and Hitbox geometry, and the hand Motor6D's exact endpoints. A captured selection binds
the character, IDs, model, Hitbox, and motor; re-resolution compares those identities, not the
newly derived metadata table. Delayed attack and guard activation callbacks reject stale selections.
Changes to either hand's definition, instance, or finish invalidate local actions without resetting
attack deadlines or sequences. Guard release and lowering cleanup remain valid after selection loss
and retain the original guard profile's timing. These are prediction checks, not server authority;
remote payloads, contact geometry, Stamina, hit acceptance, and elemental-effect ownership are unchanged.
This integration does not change GUI rendering or bind provisional crafted assets.

### Server validation and relay

The server does not independently scan an arc, rewind player positions, replace the reported target,
or manufacture an alternative hit. It first validates each `MeleeSwing`, including that the attacker
is not guarding, deducts its configured Stamina cost whether the swing later hits or misses, starts
the weapon cooldown, and records a short-lived authorization for that sequence. It then either
accepts a matching reported attacker-target pair or rejects it. The server rejects conflicting
action requests so simultaneous Attack and Shield input cannot grant both a swing and protection;
rejected swing requests do not consume Stamina.

Initial wooden and first-crafted swords cost 20 Stamina per accepted activation and have a
one-second cooldown between accepted start times. Settle eligible elapsed Stamina recovery before
checking affordability. The cooldown starts on activation, not animation completion; a new swing
must also respect any unfinished action lock. Hits and misses use the same activation cost.

Before accepting a `HitReport`, the server verifies:

- The attacker still owns and equips the supported melee weapon recorded in the server-authorized
  swing. The server resolves its definition from the Combat Loadout; `HitReport` does not supply a
  weapon definition.
- The attacker and reported target are distinct playable characters.
- Both characters satisfy the Arena-only rule for that weapon.
- The swing sequence matches the attacker's latest unconsumed server-authorized activation.
- The authorization has not expired and the target is not temporarily knockback-immune.
- The reported characters are within the weapon's configured reach plus a bounded server-tolerance
  distance.

On acceptance, the server consumes the authorization without deducting Stamina a second time,
assigns an idempotent hit ID, settles relevant combat accounting, and resolves whether the hit is
blocked. It resolves the configured launch and eligible elemental effect, records the target's
temporary knockback immunity, relays the launch to the target client, and broadcasts the confirmed
impact presentation. Each hit's launch, effect, and any Dark Stamina return resolve once. The server
never applies health damage.

Consuming the one-hit authorization does not end the swing's action lock. Guard remains unavailable
until the configured, server-owned swing duration ends. An accepted guard activation invalidates any
outstanding hit authorization from the finished swing, so a late report cannot land while the
attacker is guarding. Equipment changes, Arena exit, or character replacement also invalidate
outstanding hit authorizations and clear incompatible action state; switching Equipment cannot reuse
a previous swing's authorization.

Changing Equipment must not refund spent Stamina or reset the accepted attack's cooldown or action
lock, or skip a remaining guard transition. Clear invalid hit/visual state while retaining those
timing limits; an Equip request cannot be used to attack faster or raise a Shield before the
accepted swing ends.

### Elemental sword effects

Implement the GDD's [elemental sword effects](GDD.md#elemental-sword-effects) and
[initial effect tuning](GDD.md#initial-elemental-effect-tuning) through the existing accepted-hit
path. Resolve the effect from the authorized Equipment's definition/finish IDs, never a display
name or client-supplied effect. Keep effect parameters in configuration and snapshot the accepted
effect's parameters and server deadlines into runtime state; Equipment changes cannot rewrite them.

- A miss, rejected hit, immunity rejection, or paid Shield block applies no new elemental effect,
  including Dark's refund. A final paid block remains a block even when its cost then forces the
  Shield down. Blocking never clears a negative effect already running on the defender.
- Fire, Water, Earth, and Light share one negative-effect slot per affected character. The first
  eligible accepted effect occupies it; later timed effects are ignored without replacing,
  extending, stacking, or queuing. A pending Earth root also occupies this slot. Ignoring the new
  effect does not reject the accepted hit's normal knockback or immunity.
- Fire drains Stamina through the shared accounting path while ordinary recovery still follows
  guard state. Water modifies voluntary walking speed. Light modifies the affected attacker's
  total outgoing horizontal weapon force. Initialize their rates and durations from GDD tuning.
- Earth reserves the slot until the first server-observed landing after that hit's knockback,
  then roots voluntary walking/jumping for 0.75 seconds. Do not interpret the pre-launch grounded
  frame as that landing. Its pending deadline is three seconds after the accepted hit; no landing
  by that deadline releases the slot without granting recovery protection. Later hits do not
  extend the pending deadline or pause/extend an active root.
- When an actual Earth root ends, release the negative-effect slot and start three seconds of
  Earth-only protection. Another Earth effect cannot queue during that window; other negative
  effects may occupy the free slot. Neither Water nor Earth blocks forced knockback, changes body
  collisions, or independently prohibits attack/guard. Derive movement restrictions from current
  guard/effect state when an effect expires; do not restore stale movement values over another rule.
- Air adds 15% horizontal force to the same unblocked hit. If its attacker is affected by Light,
  multiply the entire horizontal force by 0.80 after the Air bonus: `1.15 * 0.80 = 0.92` of normal.
  Neither changes vertical launch, blocked-hit slides, or Shield costs. Air does not create a
  second hit or bypass immunity.
- Dark returns three Stamina to the attacker once per accepted unblocked hit, capped at maximum,
  after the full 20-Stamina swing payment. Air and Dark are immediate benefits and remain eligible
  against a target whose negative-effect slot is occupied.
- Both participants must be inside the Arena for a new hit. Existing effects and their landing,
  expiry, and Earth recovery deadlines continue across either player's Arena transition or
  Equipment change. Fire may drain outside and a pending Earth root may activate there. Reset or
  disconnect clears the affected character's effect state and capture progress; removing the
  original attacker does not clear effects already on another character. Bind callbacks to the
  affected character identity so an old timer cannot modify its replacement.
- Publish confirmed active/pending status and relevant deadlines for presentation. Outside the
  Arena, retain readable effect feedback and Stamina while Fire remains; attack/guard stay disabled.
  Clients may render visuals and countdowns, but cannot authorize effects or determine expiry.

#### Elemental-effect runtime implementation

`CombatState` owns the one chronological Stamina/effect timeline. Its `negativeEffect` is an immutable
scalar snapshot with effect ID, kind, pending/active phase, unique monotonic token, accepted-hit start,
current deadline, and the relevant configured parameters. Expiry is resolved at the original deadline
even during a delayed update. `earthProtectedUntil` is separate from the one-effect slot. Effect-only
cleanup retains paid action deadlines and Stamina; a new actual character initializes its own state.

`Advance` integrates the net lowered-recovery-minus-Fire rate over each interval and splits at guard
transitions, effect expiry, and analytical guard-minimum crossings. A burn ending exactly at the guard
minimum does not force lowering; any subsequent positive burning interval does. The engine never
credits guarded time afterward or caps regeneration separately before subtracting the burn.
`ApplyNegative` rejects replacement/extension while any timed effect is pending or active and observes
Earth-only protection. `Refund` settles first and caps the accepted Dark credit at maximum.

Private `ElementalHits.ApplyAcceptedHit` is called only after eligibility, immunity, exact loadout,
contact-window, and distance checks consume the accepted sequence and paid-block resolution determines
that the hit is unblocked. It uses the authorized named sword's effect metadata, never a client effect
ID. Its returned multiplier changes only the existing horizontal launch; upward launch, tumble,
Shield slide, block cost, and immunity use their unchanged owners. The original sequence cannot grant
another effect or refund. Plain sword hits still receive an existing outgoing Light modifier.

`EarthLanding.Sample` observes the affected current character each Heartbeat while Earth is pending.
It uses self-excluded, collidable-only server raycasts in the root's collision group. The upright
probe covers HipHeight plus the root's vertical half-extent and configured allowance; tipping removes
unearned upright reach, with a short LowerTorso support fallback. A qualifying upward velocity or lack
of support supplies an airborne observation; ascending contact is not a landing. `ObserveEarth`
requires a strictly post-hit airborne sample and a later supported sample with the same effect token.
The fixed timeout wins at its exact deadline. Neither later hits nor Arena/equipment transitions
replace this token, delay the timeout, or refresh a root/recovery window. Configurable observation
parameters and publication cadence live in `Configurations/CombatRuntime`.

`MovementRestrictions` owns only the Humanoid properties it overrides. `CombatState.GetMovement`
composes guard, Water, and active Earth before applying a rule. Walking, jumping, and rotation baselines
are captured independently and restored only when their restriction ends; releasing guard while
Water remains never restores full speed over the slow. No PlatformStand, anchoring, velocity, or
collision override is added by effects. All affected-character death/removal/disconnect paths clear
effects and owned overrides; ClaimService independently clears that character's capture progress.
Original-attacker departure does not traverse another character's state.

Confirmed character attributes are `CombatEffectId`, `CombatEffectKind`, `CombatEffectPhase`,
`CombatEffectToken`, `CombatEffectStartedAt`, `CombatEffectExpiresAt`, `EarthProtectedUntil`, and
`HasStaminaBurn`. Empty effects use empty strings/zero/false. Published deadlines are converted to
server time for consumers without feeding those values back into monotonic `os.clock` accounting.
Publication continues outside the Arena. GUI/visual consumers remain separate work; no new remote,
model substitution, or crafted-asset readiness claim is made here. Deterministic
tests cover accounting, accepted-effect reduction, movement ownership, and support observations;
connected-player/tumbling behavior still needs multiplayer verification with approved assets.

### Target client and presentation

- The target client applies the relayed launch with a short eased force curve rather than a delayed
  velocity spike. Hit IDs prevent the same launch from being applied twice.
- Temporary knockback immunity starts after an accepted hit and rejects further accepted weapon
  knockback hits until its configured duration ends. It does not disable or counteract normal
  player-body collisions, and those contacts do not grant or refresh immunity.
- The attacker's locally rendered impact suppresses its duplicate server broadcast. Other clients
  render the server-confirmed impact.
- Visual and audio presentation is cosmetic. Failure to render an effect must not change hit
  validation, capture progress, temporary knockback immunity, or server-owned elemental effect state.

### Security boundary

Because the attacking client chooses the target, an exploit can fabricate plausible sword reports
within the server's distance, cooldown, Combat Loadout, Stamina, immunity, and Arena checks. This
risk is accepted for the MVP and must be revisited if competitive stakes increase. Lightweight rate
monitoring and server telemetry may be added without restoring an independent server hit scan.

The client-reported exception ends at the positional combat reaction. Capture Ring membership,
capture meters, contest resolution, Mythling awards, Stamina accounting, Shield eligibility,
elemental effect selection/limits/timing, persistent progression, and all rewards remain
server-authoritative. Approved elemental effects do not expand client authority beyond reporting
contact and applying the confirmed physical reaction.

The target client applies the relayed physical reaction; server-owned capture meters do not make
client physics tamper-proof. A client that ignores displacement can affect its position in a
contest. Do not describe this architecture as fully exploit-resistant. Any later mitigation must
preserve the approved contact-reporting boundary unless the design is explicitly revised.

## Stamina and guard accounting

The GDD's [Shield actions](GDD.md#shield-actions) define the guard threshold, full-cost defender
blocks, action exclusion, and the rule that Stamina does not regenerate while the Shield is raised.
Server runtime state owns Stamina and guard eligibility; animation, client input, and displayed
values cannot authorize protection.

The current implementation isolates deterministic accounting in
[CombatState](../src/ServerScriptService/Services/CombatService/CombatState.lua). A completed hit
does not shorten its independent swing deadline. Equipment defines the initial 0.72-second swing
lock and 1-second start interval separately. Initial guard transitions use a 0.2-second minimum
and a 0.8-second timeout for each direction. Early markers wait for the minimum; missing raise
markers force an unprotected lowering, and missing lower markers finish cleanup at the timeout.
Lazy settlement splits at those deadlines before adding any lowered-time recovery. These transition
values remain trial tuning; they do not change the approved Stamina costs or recovery rate.

- Initialize maximum Stamina and character-spawn Stamina to 100 and eligible regeneration to
  10 Stamina per second. A new character after reset receives the configured spawn value;
  entering/re-entering the Arena or changing Equipment must not refill the current character.
  Recovery continues during sword actions while the Shield is fully lowered. It stops throughout
  raising, guarding, and lowering, with no post-lowering delay or retroactive guarded-time credit.
- When processing guard requests, protection markers, and incoming hits, grant Shield protection
  only for an owned, equipped Shield and a compatible Loadout. Remove protection immediately if
  eligibility is lost, regardless of delayed callbacks. The future two-handed compatibility
  contract uses this same path; ordinary unshielded hits remain valid.
- Validate positive configured `impactStaminaCost` and `minimumGuardStamina`, with
  `impactStaminaCost <= minimumGuardStamina <= maximumStamina`. Resolve costs and the threshold from
  Equipment metadata and the maximum from combat configuration.
  Initialize the wooden Shield's cost and minimum to 30 each and the first-crafted Shield's to
  25 each, shared across all six variants and acquisition routes.
- Configure the initial full-Stamina guard targets through those existing values: three accepted
  paid blocks for the wooden starter Shield and four for the first-crafted Shield definition shared
  by all six elemental variants. Featured copies use the same definition and values. With maximum
  Stamina `M`, impact cost `C`, minimum guard threshold `G`, and target block count `N`, require
  `M - (N - 1) * C >= G` and `M - N * C < G`, alongside `C <= G <= M` and positive values.
  This permits the final full-cost block, then immediately removes protection and begins lowering.
  It does not require Stamina to reach zero. Validate using continuous guard with no recovery and
  accepted hits separated by immunity and no other drain, such as Fire; rejected hits cannot spend
  block Stamina. Do not add a
  durability field, hit allowance, or resettable block counter. Current Stamina determines every
  block's eligibility, including after re-equipping or raising from partial Stamina.
- Serialize Loadout changes, attack authorization, guard activation/release, elemental effect
  application/expiry, and incoming-hit resolution against the same combat state. Raising, raised, and lowering guard states reject
  attacks, independently of whether protection remains eligible. An active swing rejects guard
  activation until its action lock ends. An animation transition cannot leave Shield protection
  active during an attack.
- The server recognizes eligible protection at the authored `GuardRaised` marker and normally
  removes it at `GuardLowered`. A marker callback is timing input, not authority to override current
  eligibility. Insufficient Stamina, leaving the Arena, or unequipping removes protection
  immediately; delayed visuals must not extend it.
- Bound raise/lower transitions with configured server-owned timing. Missing markers, interrupted
  animations, or lost client callbacks must reach a valid lowered/cleanup state within that bound;
  they cannot leave an unprotected player permanently unable to attack or recover Stamina.
- Before reading or spending Stamina, settle elapsed recovery and active Fire drain together using
  the **previous** server-owned guard/effect state. Split accounting at effect and guard transitions,
  clamp elapsed time to nonnegative, and clamp Stamina between zero and maximum. Apply the net rate
  over each interval; separately capping recovery before subtracting Fire would produce the wrong
  result at full Stamina. Advance the last-accounted time even when no Stamina is added.
- Fire crossing the guard minimum immediately removes protection and starts normal forced lowering.
  Resolve that threshold crossing and the resulting guard transitions chronologically, including
  when settling elapsed time; Fire cannot leave an ineligible guard active until the next input.
  Dark's accepted-hit return uses this same settled balance and never refunds a miss or blocked hit.
- Before each guard-state transition, settle the interval up to the transition time under the old
  state, then change the state. Raising, raised, and lowering intervals grant zero recovery until
  the Shield is lowered; existing Fire drain still applies. Losing protection through depletion
  must not by itself classify a still-raised
  Shield as lowered for regeneration. Track raised lifecycle and protective eligibility distinctly
  when they differ. Regeneration starts at the transition into fully lowered, at the configured
  rate, with no additional recovery delay after either normal release or a guard break. Lazy updates
  must never credit time spent guarding retroactively after release, depletion, Arena exit, or
  unequip.
- An accepted Shield block deducts the complete cost from the defender after settling runtime
  accounting. Recheck eligibility immediately; remove protection if the remainder is below the
  threshold. A fresh eligible request is required to guard again. Do not use partial-cost spending
  or wait for a cosmetic effect to finish before removing an ineligible guard.
- Apply the same accounting path to regular refreshes, guard requests, incoming hits, action
  requests, effect application/expiry, and forced cleanup. Publish only the resulting server-confirmed values.

Keep the approved initial values configurable. At maximum 100, the wooden Shield leaves 10 after
three blocks and the crafted Shield leaves zero after four; both lose protection immediately.
With the Shield fully lowered and no spending or elemental Stamina changes, validate two seconds from zero to an affordable
20-Stamina attack and ten seconds from zero to full. For an action lock that permits one-second
starts, continuous eligible recovery supports attacks at seconds 0 through 8 from full Stamina,
rejects an unaffordable attack at second 9, and permits the next at second 10. Do not mistakenly
validate this as a five-attack allowance or suspend recovery during swings to force that result.
Guard transitions, attack contact/animation windows, immunity, and knockback remain to be tuned;
never shorten an active lock to satisfy the arithmetic example. These block counts describe guard
endurance, not guaranteed hits before leaving a ring; existing slide and body-collision rules apply.
Also verify Fire's fully lowered 100-to-90 reference over two seconds, forced lowering when its
drain crosses the guard minimum, and Dark charging 20 before returning three on an unblocked hit.
Neither effect may grant recovery during a guard phase or make full-rate attacks sustainable.

## Arena population lifecycle

The current services share a server-time clock. `ClaimService/ContestState` settles per-contest,
per-player meters and returns ordered completion candidates before expiry is finalized; ClaimService
rechecks character identity, profile availability, and Inventory capacity before granting once.
The same finite-height ring membership governs progress, uninterrupted visits, and overtime.
The client receives character-bound `ClaimUpdate` projections for the current ring or a retained
decaying meter; these projections do not replace the independent server meters. Timers render
the server's `State` and fixed `ExpireAt`, including an explicit overtime label.

The live lifecycle preserves the three existing prototype form IDs and their effective spawn
weights through explicit `prototypeRarityWeights`. The shared selection implementation and startup
validation also consume the separate [18-form business catalogue](#launch-mythling-form-catalogue)
and canonical 75%/20%/5% `rarityWeights`, without activating its absent model bindings. Ember Fang
and Shadow Satyr now use their configured 20/35-second captures; Stream Axolotl retains its prototype
10-second capture. All three decay one second of earned progress per second absent and use a
240-second lifetime. Author the launch assets and integrate the new catalogue into spawning before
release; do not infer live roster readiness from the 12-contest target or validated business metadata.

Capture grants now enforce the configured Mythling limits of 24/36/48, derived from optional saved
`inventoryUpgrades.mythlings` (absent means zero purchases). Existing owned entries, including those
assigned to Shrines or above capacity, are retained and counted. The server-only
[capacity-upgrade command](#atomic-inventory-capacity-upgrade-command) purchases the next category
limit. The [capture-grant boundary](#canonical-capture-grant-boundary) supports the
18 canonical forms without activating their live spawn pool. New canonical captures alone initialize
`level = 1`, `xp = 0`, and `pendingXp = 0`; existing progression is not reset or migrated.

Enforce the GDD's [population and availability
rules](GDD.md#server-population-and-spawn-availability) through server-owned contest state. The
deployed launch server limit is eight players, and shared configuration specifies a capturable
target initially set to 12 and a maximum refill delay initially set to three seconds. Use the
same target in quiet and full servers; player count does not scale availability.

- For every new contest, independently select the rarity with initial probabilities of 75% Common,
  20% Rare, and 5% Epic, then uniformly select one of its six elemental forms. Apply this to both
  initial fill and replacements; do not enforce fixed rarity counts or roll rarity onto an owned
  form. Retain the chosen form through placement retries so failed positions cannot bias selection.
- Separate capturable-contest registration from model lifetime. Only unclaimed contests with valid
  active Capture Rings contribute to availability; pending attempts, claimed/escort models,
  decoration, and ended contests do not. Overtime contests remain registered and capturable.
- Populate to all 12 before enabling capture on a fresh server. Claiming or despawning a contest
  unregisters its capturable capacity immediately and schedules replenishment; delayed model cleanup
  must not hold the slot. Reaching the countdown deadline alone does not free an overtime contest's
  slot or trigger replacement.
- Resolve each contest's spawn lifetime once: use the named form's optional override when present,
  otherwise its configured rarity's default. Initially all three launch defaults are 240 seconds
  and all 18 launch forms have no override. At the moment it becomes capturable, record the
  server start time and expiry deadline in runtime contest state. The initial population starts
  its countdowns together when capture opens; placement retries and prefill must consume no lifetime.
  Replacements start their own countdowns when registered as capturable. Entry, re-entry, and later
  configuration changes cannot reset or recompute an existing deadline. This is spawn state,
  not an owned Mythling attribute or player-save field; clients render the authoritative deadline.
- Measure each replacement deadline from the old contest's removal from capturable registration
  to the replacement's valid capturable registration, initially at most three seconds. Permit
  enough replenishment work to replace simultaneous removals within their individual deadlines;
  do not apply a three-second wait to each successive spawn in a serial queue.
  Validate non-overlap and ring placement before registering a new contest; a failed placement
  retries an alternative without counting as a spawn. Persistent placement failure is a
  map/configuration failure, not permission to overlap rings or extend the refill deadline.
- Capacity and exactly-one-award checks remain authoritative through contest resolution. Disconnect,
  reset, reaching Mythling capacity, and contest termination clear the relevant capture meters;
  entering overtime does not.
- Resolve progress, occupancy changes, countdown expiry, and awards through one ordered server
  contest lifecycle. Select the earliest eligible server-calculated completion time. For exact
  ties, use the server-recorded entry order for each player's current uninterrupted ring visit;
  leaving and re-entering starts a new visit. Record a unique entry sequence to resolve entries
  observed in the same update without using client timestamps.
- Resolve eligible completions through a lifecycle event's time before ending the contest. This
  includes a completion exactly at the countdown deadline or at the last occupant's departure.
  Award or despawn once; stale timers, entry events, and award requests cannot reopen an ended
  contest or produce a second result.
- At the countdown deadline, despawn an empty ring; otherwise enter overtime and preserve all
  meters. During overtime, continue normal capture and decay, allow new entrants, and end with
  capture or the first server-observed empty-ring state. There is no extra overtime timer.
- Track occupancy from connected players' current characters inside the ring independently of
  inventory capacity or meter existence. A full-inventory occupant keeps overtime active but
  cannot gain progress or receive an award. Reset/disconnect remove old-character occupancy; if
  this empties an overtime ring, end it. Delayed model cleanup does not preserve occupancy.
- Use one server membership test for capture progress/decay, uninterrupted visit and entry order,
  and overtime occupancy. Test the character root's horizontal position against the ring footprint,
  with a finite configured vertical allowance around the ring's floor that includes standing and
  the full normal-jump arc. A normal jump inside the footprint remains one uninterrupted visit;
  crossing the horizontal edge starts decay normally. Ground contact and airborne animation states
  do not determine membership. A character far above or below the ring must not count as inside.
- Store meters per contest and per player. Entering a different Capture Ring starts or resumes that
  contest's meter while previous meters decay normally; it does not reset them merely because the
  player's current target changed.
- Initialize every Common/Rare/Epic launch form to a 20/35/60-second uninterrupted capture
  respectively. Resolve rates from that form's configuration, not a runtime stage/rarity formula.
  For a meter normalized from zero to one, its progress rate is `1 / captureDurationSeconds` and
  its initial decay rate equals its progress rate. Scale both consistently if the representation
  uses percentages. Apply elapsed server time inside/outside the shared membership rule, clamp
  progress to its valid range, and award at completion through the ordered lifecycle above.
  Decay starts on leaving the ring, with no delay or immediate full reset; normal jumps inside
  retain progress. Re-entry retains remaining progress but receives new uninterrupted-visit priority.
- Validate authored island boundaries under walking, jumping, and configured knockback. Spawn
  placement must leave room to push players out of a Capture Ring before an outer barrier stops
  them; the population target does not justify rings pinned against boundaries.
- Wild Mythling presentation models must not physically block player movement or support standing
  on them. Keep Capture Ring membership detection independent of the model's physical collision.
  Player bodies retain [Roblox's default character collision behavior](https://create.roblox.com/docs/workspace/collisions#disable-character-collisions)
  in the Arena. Let the normal physics response handle body contact without extra push forces,
  custom contact resistance, or contact-specific Stamina costs. Do not change body-collision behavior
  when guarding or weapon-knockback-immune; the existing restriction on voluntary walking/jumping
  while guarding still applies. Ordinary contact never creates a sword-hit authorization, Shield
  block charge, combat-impact effect, or immunity event.
- A reset returns the player to the assigned Base spawn. Clear that player's capture meters and
  invalidate the old character's attack authorizations, guard state, forces, and pending reactions
  before rebuilding character presentation from the existing profile. Late messages from the old
  character must not affect its replacement. Reset is not a profile join or an online/offline
  production transition: it must not regrant starter items, replay offline accrual, or cancel Shrine
  assignments and Crafting Jobs.

### Canonical capture-grant boundary

`InventoryService.SaveWonMythling(player, params)` is a server-only award boundary used by
ClaimService, not a client-selectable acquisition or retryable purchase command. The existing
Inventory session must still refer to the player's loaded owned-Mythling collection. Private
`InventoryService.CaptureGrant` validates the closed selection payload and resolves the form from
the canonical launch catalogue or the retained known prototype definitions; arbitrary unknown
form IDs are rejected. The server creates the owned-instance ID and acquisition timestamp rather
than accepting either from the selection payload.

The selection is exactly `{ typeId, variantId }`, with nonempty IDs of at most 128 bytes and no
extra fields or metatable. Canonical forms accept only `variantId = "regular"`, the existing save
schema's ordinary-variant sentinel; it creates no cosmetic option or prototype model mapping.
Prototype compatibility requires an actual configured form and variant. Private
`CaptureGrant.new(dataSource, clock?, createId?).Grant(player, params)` returns the normal transaction
result with `values.instanceId` on success; the public wrapper retains its `string?` result.

Use one `DataService.Update` with operation `CaptureMythling` to recheck the current derived Mythling
capacity, reject an existing instance-ID collision, and install the newly owned entry. Retain the
exact selected canonical `typeId`, initialize `level = 1`, `xp = 0`, and `pendingXp = 0`, and save only
owned state and metadata IDs. Neither stage nor rarity supplies starting XP. Do not grant Luck or a
Trait, copy static rarity/Yield/sale values, assign a Shrine slot, or award Gold. Reject malformed input, invalid
server-generated identity/time, unavailable data, or full capacity without a partial grant.
The transaction retains all existing entries and their earned/legacy state.

The draft must use the current player-data schema and a plain owned collection with valid owned
IDs/records and form IDs. Optional Mythling capacity-upgrade state must be a valid configured
purchase count, never coerced from malformed data. Sample `workspace:GetServerTimeNow()` only inside
the transaction after these state, definition, and capacity checks; the default identity generator
then supplies a `myth_`-prefixed GUID. Reject nonfinite/negative time or a malformed/colliding generated
ID. Tests may inject those two dependencies; throwing/yielding callbacks retain the transaction
engine's rollback guarantees.
Adding a new unassigned worker changes no prior production input and grants no earlier work/XP.

ClaimService remains the source of award uniqueness: its ordered resolution rechecks the current
character/profile/capacity, marks the contest as claiming, calls this non-yielding grant, and closes
the contest after success. `DataService.Update` provides atomicity but does not make repeated
independent calls with fresh server request IDs idempotent. Do not expose this internal boundary as
a client retry endpoint or claim that its asynchronous save request acknowledges durable storage.

The three configured prototype forms retain their compatibility path while the live spawner still
uses them. Existing legacy records are not converted into canonical forms. Supporting canonical
grant records does not choose creative names/assets, map model templates, change the live spawn
distribution, or add UI/remotes. Complete that live integration separately; runtime tests of
injected dependencies and serialized data do not establish multiplayer capture or durable saves.

## Production accrual

The [production calculation](GDD.md#production-calculation) and [Mythling
progression](GDD.md#mythling-progression) rules in the GDD own Yield, XP, storage, and evolution
behavior. The server implements those rules as fixed chronological batches on a common schedule
across a profile's Shrines, using saved accrual time and mutable state. The initial configured batch
interval is **one second**; it does not require one save or network update per second. Worker changes
do not shift that schedule.

Set each launch Common/Rare/Epic form's initial unmodified base Yield to **12/18/32 Materials/hour**
respectively in Mythling metadata, shared across the six elements. These are fixed form values,
not an additional rarity multiplier. Convert rates consistently when accruing working seconds;
one unchanged worker earns one Material's worth of progress in 300/200/112.5 seconds respectively
before level scaling. These are nominal production times, not batch intervals or separate per-item
timers. Use the configured batch cadence for production and activity-based XP, including intervals
that advance unfinished progress without completing an item. Resolve completed whole output at the
normal batch boundary; clients cannot grant it from a displayed countdown.

Resolve level-adjusted Yield as `currentFormBaseYield * (1 + yieldGainPerLevel * (level - 1))`,
with shared initial `yieldGainPerLevel = 0.01` and a level cap of 100 across all launch forms.
Sum assigned workers' level-adjusted Yield. The same deterministic rate applies online and offline;
launch production has no Luck rolls, Lucky Yield bonus, or Passive Trait modifiers.
This is an additive base-Yield bonus, not compound growth. Derive it from current form metadata
and saved level, without persisting a copied rate or accumulated Yield bonus. Preserve fractional
rate precision until whole-output accounting. Evolution settles prior work first, then uses the
new form's base Yield at the retained level; levels gained in a batch affect later batches only.

Shrine storage and Material inventory contain non-negative whole quantities only. Track unfinished
production separately as progress toward the next completed Material; it is not a stored or
collectible item. Preserve enough progress for low Yield to eventually complete an item.

Unfinished progress belongs to the built Shrine instance. Swaps, removals, and evolution retain the
work already earned there; new Yield affects subsequent work only. A moved Mythling does not carry
production progress to another Shrine. With no assigned workers, retain progress without accruing
output or XP; resume when workers are assigned and never backfill the empty interval. Online/offline
transitions likewise retain progress and do not change production rates or worker eligibility.

The activity owns the XP earning rate. Launch has one shared Shrine-work `baseXpPerSecond = 1` in
production configuration, used across all elements and Mythlings. Shared progression metadata
sets the next-level requirement to `120 * currentLevel` XP, with cap 100; it does not set the
activity's earning rate. Cumulative XP from level 1 to level N is `60 * N * (N - 1)`.
Initial evolution links require level 6 for Common-to-Rare and level 40 for Rare-to-Epic.
At the initial activity rate, levels 6/40/100 take 1,800/93,600/594,000 eligible working seconds,
resolved at normal batch boundaries. Keep these values configurable; chronological accrual must
process every earned level before subsequent batches, including during offline settlement.
Reaching the level cap stops new XP accrual but not Material production when storage is available.
Preserve already-earned XP, including unresolved pending credit and the cap-reaching batch's
remainder. Capped working time does not bank additional XP. Yield, form,
rarity, and online/offline status do not modify the activity's XP rate. No additional activity system
or player XP is needed for launch.

Luck, Lucky Yield, and Passive Traits are deferred together. New launch captures neither roll nor
require Luck or a Trait. Preserve any existing saved Luck values and Trait IDs as inactive legacy
data; they affect neither production nor XP and are not exposed in launch UI. Their future
acquisition, effects, configuration, and migration behavior need a separate approved design.
Initial Shrine capacities are 300/1,200/3,600 whole Materials at levels 1/2/3 across all elements;
derive capacity solely from Shrine level, never from assigned workers or a target fill duration.

1. Resolve the Shrine's output Material, capacity, assigned Mythlings, and current form/level
   statistics from saved IDs and the current production configuration. On join, process unresolved
   offline time with that configuration; retaining old production-rule versions per player is not
   required. Keep the configuration consistent throughout
   one accrual transaction. Never reprice already settled output or awarded XP.
   Sum eligible workers' level-adjusted Yield without a Shrine-level production multiplier. Upgrading
   capacity does not increase individual Yield or the activity's XP rate, and empty slots produce
   nothing.
2. On join, collection, and any change to production conditions, settle the preceding interval under
   its saved assignments and form/level progression, using the configuration policy above. Perform
   this settlement before assignment/removal, evolution, or a Shrine upgrade mutates those inputs.
   Preserve earned contributions to an unfinished batch under the inputs that produced them;
   do not recalculate prior work using the replacement worker's stats.
   Changes do not restart batch timing or force an extra completion. The normal accounting schedule
   continues through empty intervals, which add no work.
3. Resolve working batches in chronological order across affected Shrines. Each Mythling earns
   `baseXpPerSecond * eligibleWorkingSeconds` for its own time assigned while storage is available,
   including work toward an unfinished Material. Concurrent workers each earn independently. Retain
   earned XP contributions by owned Mythling instance ID when workers change; never calculate the
   whole batch from its final roster. Award at the normal batch boundary, including credit earned by
   removed but still-owned workers. Pending credit belongs to the owned Mythling and survives
   dismantling its former Shrine. Resolve due credits on the profile schedule, including on join
   and before level-dependent actions, even if no source Shrine remains. Empty/full intervals add no
   credit; a level gained in one batch affects later batches only.
4. For each interval with unchanged inputs, accumulate new production work as
   `newWork += summedLevelAdjustedYieldPerHour * eligibleWorkingSeconds / 3600` for the current
   batch. Empty/full-storage intervals add no work. At the normal batch boundary, add `newWork`
   to prior unfinished progress, store the completed whole Materials that fit, and retain the
   remainder only while storage has space. Clear the resolved batch's new work together with its
   result. No random roll or additional multiplier is applied to new or retained work.
   The batch that fills storage grants each worker's normal time-earned XP even when some output
   cannot fit. Discard overflow rather than banking it as output or unfinished work. Subsequent
   full-storage time produces no Materials or XP.
5. Commit stored output, unfinished production progress, any unresolved batch work,
   pending XP contributions, level/XP changes, and the common accrual/batch cursors through DataService.
   Consume each pending credit once; moving, selling, or replacing a Mythling must not redirect its
   XP to a different instance. Retain sub-unit XP precision with the earned state instead of
   rounding each short interval independently.
   Retries and repeated collection requests must not award a resolved batch's output or XP twice.
   Full-storage time must not become deferred production or XP after space is freed.
6. Use the same accrual calculation online and offline, with server-authored timestamps; clients
   do not supply elapsed production time. Session boundaries are recovery bookkeeping, not modifiers.
   Settle online accrual before normal profile release and record `offlineSince`. At online
   checkpoints, settle each Shrine before advancing `lastOnlineCheckpointAt`; commit both together.
   After an unclean shutdown, the precise disconnect time may be unavailable: use the last persisted
   checkpoint as an estimated offline boundary. This recovery can treat unsaved online time as
   offline; it must never replay time before the profile's saved `lastAccruedAt`. On join, settle
   the saved offline interval before clearing `offlineSince` and starting online accounting.
7. Collection settles accrual, computes the whole quantity that fits in destination Material
   capacity after active crafting reservations, and atomically transfers that quantity. Keep the
   uncollected Materials in the Shrine and preserve unfinished production progress and batch timing.
   Zero available space produces a capacity rejection; a positive partial transfer returns its
   actual quantity and the remaining stored output. If no completed Material is stored, return the
   empty-storage state instead of misreporting an Inventory capacity problem.

Production and XP retain their working-batch cadence; completing an individual Material does not
create an extra XP award. Future Luck, Traits, and rare-Material output must preserve whole-output,
capacity, and settlement guarantees, but need no launch configuration or runtime support.

For accounting verification, 0.8 previously retained progress plus 0.2 newly earned work gives
one whole Material and zero remaining progress, assuming storage has space. Splitting an unchanged
interval into smaller settlements, swapping workers, or reconnecting must preserve already earned
work and XP rather than rounding each interval or replaying its result.

The server-shared `ShrineAccrual.Accrue` reducer implements this arithmetic with injected
form/Shrine metadata and a profile-wide `lastAccruedAt`/`nextBatchAt` schedule. Its returned ledger is
not a replacement PlayerDoc or owned-Mythling record. Its callers merge the accounting fields into
a single transaction, preserving identity and inactive legacy metadata. ProfileSchema
initializes the common schedule once under the [schema-7 foundation](#schema-7-shrine-accounting-foundation).
The server-shared [draft adapter](#shrine-accounting-draft-adapter) retains this schedule; live
callers must settle before changing inputs. Changing cadence requires explicit schedule
reconciliation, not resetting partially earned work.
Shrine-to-Material IDs are fixed by the [launch Material catalogue](#launch-material-catalogue).
Preserve these identities when integrating persistence so settled output cannot be reinterpreted.
Long intervals coalesce identical complete batches only as far as the next level or storage-fill
boundary; later work uses the changed inputs. There is no offline time cap. Empty/full intervals still
advance the cursor, and pending XP resolves even after its source Shrine is removed. Existing whole
output and progress are retained if current capacity is reduced below stored output; it earns no new
work until space is available. The [on-demand command](#on-demand-shrine-settlement) and
[automatic profile lifecycle](#automatic-shrine-production-lifecycle) use the adapter inside a
profile transaction. Player-facing integration remains separate work.

### Shrine-accounting draft adapter

`ServerScriptService.Shared.ShrineAccounting` is a server-only draft adapter shared by Production,
Base, and Inventory; consumers do not reach into another service's private children.
Its `SettleToDraft(draft, now, metadata?, production?, progression?)` returns `(boolean, code?)`.
Its input is a prepared current-schema player-document draft, not a client-supplied ledger. It
defaults to the real `MythlingForms` and `Shrines` metadata and shared production/progression tuning;
tests can inject them. It maps each participating owned record's existing `typeId` to the detached
engine's `formId`, using the owned dictionary key as worker identity. It neither renames `typeId`
nor persists a second worker map.

Known forms require explicit valid `level`, `xp`, and `pendingXp`; absent values are not acquisition
defaults. A known form with a legacy `standId` is rejected, preventing competing old/new accounting.
An unknown form may be skipped unchanged only when no Shrine references it and its `pendingXp` is
absent or zero. An unknown assigned form or unknown form with invalid/nonzero pending credit rejects
the operation rather than losing earned work or advancing its clock past unresolved credit.
Backdated time, unprepared/invalid state, and engine validation failures reject without changing
the supplied draft. This adapter does not migrate old saves, initialize clocks, or fix corrupt state.

`ReadSnapshot(data, metadata?, production?, progression?)` reuses that canonical adaptation for
server-only queries. It validates the complete ledger at its saved cursor without sampling time or
accruing work, returning `{ state, metadata }` plus an optional error. The state is detached and
deeply frozen; reading neither freezes nor modifies the source profile (already-frozen valid input
is accepted). Default metadata is immutable; injected metadata is borrowed read-only. Consumers
must explicitly project approved public fields, never replicate this internal ledger. There is no
Apply counterpart: mutations still use the narrow transactional bridges below and reject frozen
draft roots.

After successful detached accrual, stage cloned changed roots before assigning the complete result.
Merge only `productionClock.lastAccruedAt`/`nextBatchAt`, each Shrine's `stored`/`progress`/`newWork`,
and participating Mythlings' `level`/`xp`/`pendingXp`. Preserve clock extras, Shrine identity and
definition, build slots, assignment maps, the permanent Station, owned identity and `typeId`,
unknown legacy fields, inactive Luck/Trait data, prototype ledgers, and all unrelated profile state.
`SettleToDraft` performs no form change, worker move, collection, currency payment, or ownership grant.

`ChangeAssignmentsToDraft(draft, now, change, metadata?, production?, progression?)` is the narrow
assignment bridge. It builds and freezes a fresh accounting view, calls the trusted synchronous
assignment reducer, and validates its result before staging accounting/progression and slot maps
together. The result must retain the exact worker and Shrine key sets, each worker's form, each
Shrine's definition and level, and have `lastAccruedAt` equal to the supplied time. It is not a
general snapshot/apply API and does not support acquisition, evolution, sale, collection, upgrade,
or dismantling. Assignment policy remains in Base's reducer; the shared bridge owns adaptation.

`ChangeStorageToDraft(draft, now, change, metadata?, production?, progression?)` is the corresponding
narrow storage bridge. It supplies the same fresh frozen view to a trusted synchronous accounting
change and requires the exact worker/Shrine key sets, forms, Shrine definitions/levels, and
assignment maps to survive, with `lastAccruedAt` equal to the supplied time. After validation it
stages only accounting and progression fields; it cannot move workers or install arbitrary owned
state. Collection policy and the matching Inventory grant stay in Production's private collector,
which commits both together in the same DataService transaction.

`ChangeShrineLevelToDraft(draft, now, shrineInstanceId, change, metadata?, production?, progression?)`
is the narrow sequential-level bridge. It supplies the same fresh frozen view to a trusted
synchronous change, requiring the selected Shrine's result level to be exactly its prior level plus
one and every other Shrine level to remain unchanged. Exact worker/Shrine key sets, forms, Shrine
definitions, and all assignment maps must survive; `lastAccruedAt` must equal the supplied time.
Revalidate Base state before staging the selected level with accounting/progression fields. This
permits no new assignments or arbitrary replacement owned state. Base's upgrade reducer owns the
next-level configuration and payment policy; its private purchase adapter commits Materials and
Gold in the same transaction.

`RemoveShrineToDraft(draft, now, shrineInstanceId, change, metadata?, production?, progression?)`
is the narrow removal bridge. Its trusted synchronous reducer receives a fresh frozen accounting
view and must return exactly the original Shrine key set minus the selected instance, retaining
all workers and their forms. Every surviving Shrine retains its definition, level, and assignment
map, and `lastAccruedAt` must equal the supplied time. Validate the returned accounting and cloned
Base state before staging removal with the surviving accounting/progression fields. Preserve all
other canonical record fields; never replace surviving records with a reducer's ownership-only
Shrine map. Base's dismantling reducer owns empty-worker and completed-output checks, while the
shared bridge owns adaptation and the selected removal boundary.

`ChangeWorkerFormToDraft(draft, now, workerId, targetFormId, change, metadata?, production?, progression?)`
is the narrow form-change bridge. Its trusted synchronous reducer receives the same fresh frozen
accounting view and may change only the selected worker's form to the specified target. Exact
worker/Shrine key sets, every other worker form, and all Shrine definitions, levels, and assignment
maps must survive; `lastAccruedAt` must equal the supplied time. After validating the result, stage
the selected canonical `typeId` with normal accounting/progression fields, preserving every other
owned-record field. Inventory's evolution reducer owns link validation and eligibility.

`RemoveWorkerToDraft(draft, now, workerId, change, metadata?, production?, progression?)` is the
narrow worker-removal bridge. Its trusted synchronous reducer receives the same fresh frozen
accounting view and must return exactly the original worker key set minus the selected instance.
All surviving worker forms and every Shrine key, definition, level, and assignment map must remain
unchanged, with `lastAccruedAt` equal to the supplied time. Stage only the selected canonical owned
deletion and normal accounting/progression fields after validating the result, retaining every
other field on surviving records. Inventory's sale reducer owns eligibility and price validation;
its command credits the returned Gold inside the same transaction. None of these bridges is a
generic snapshot/apply API or a replacement for feature validation.

The optional `MythlingEntry.pendingXp` type field accommodates the retained legacy boundary; it
does not add defaults to existing captures. `Projection.Build` omits pending XP from Mythling views
while preserving their other existing projected fields; private Shrine accounting and the root
clock remain excluded by the current allowlist. No schema version change is required.

Service operations and lifecycle hooks must call this helper inside a DataService transaction, with
server-owned time, and commit the result with the rest of their mutation.
The helper itself supplies neither authorization, request receipts, persistence, nor a durable-save
acknowledgement. Production's profile lifecycle hook calls it at session/checkpoint boundaries;
the adapter itself owns no timer and is not a public service API, remote, or menu action. Tests
compose it with `Transactions.Run` and serialized state to check atomicity/continuation without
claiming live save durability. Its on-demand,
assignment, collection, upgrade, dismantling, evolution, and sale callers are described below; sharing
the adapter does not expose it to clients.

### Automatic Shrine production lifecycle

`ProductionService` registers `ProfileProduction.Settle` with
`DataService.RegisterProfileSettlement("Production", callback)` during initialization. The callback
receives `(draft, serverTimestamp, boundary)` and returns a normal transaction outcome; `boundary`
is `Ready`, `Checkpoint`, or `Release`. It is a pure profile mutation, not a connected-player API,
and remains callable after Production's runtime tasks stop. DataService owns session access and
does not reach into Production's private modules.

Private `DataService/ProfileSettlements` accepts each unique owner's hook before registration is
sealed at DataService startup. For each boundary it executes the registered hooks in registration
order inside one `Transactions.Run`, sampling `workspace:GetServerTimeNow()` once inside that
transaction. A rejected, invalid, yielding, or erroring hook rolls back all staged gameplay changes;
an active-session check guards the final commit. Hooks must not publish, save, load profiles, yield,
or perform outside effects. The runner owns its server-generated revision-bound operation
`Data.ProfileReady`, `Data.ProfileCheckpoint`, or `Data.ProfileRelease`; this is not a client request.

The Production hook delegates to `Shared.ShrineAccounting.SettleToDraft`, preserving chronological
accounting, worker contributions, full-storage pauses, and earned/pending XP. Its session markers
live on the private `productionClock` beside, not instead of, `lastAccruedAt` and `nextBatchAt`:

- `Ready` settles from the saved accrual cursor before the profile is published or `OnLoaded` fires,
  then sets `lastOnlineCheckpointAt` to the server timestamp and clears `offlineSince`.
- `Checkpoint` requires a ready online profile, settles to the server timestamp, and only then
  advances `lastOnlineCheckpointAt`. It does not reset the batch schedule or request a save itself.
- `Release` requires a ready online profile, settles to the server timestamp, and records
  `offlineSince` while retaining the last online checkpoint. DataService finalizes while the profile
  is still active, before ending its session.

`Shared.ProductionClockUtil.ValidateLifecycle` validates these optional fields in both schema
preparation and the accounting adapter. Both absent is the supported pre-lifecycle schema-7 state;
Ready initializes the hints without a schema bump or erased work. A present checkpoint must be a
valid timestamp no later than `lastAccruedAt`; an offline marker requires that checkpoint and must
fall between it and `lastAccruedAt`. Invalid partial/out-of-order hints reject instead of being
repaired. Checkpoint/Release cannot initialize missing readiness or clear an offline marker.

Online and offline work use identical rates, eligibility, and configuration. After an unclean stop,
the last persisted online checkpoint is only an estimated boundary; actual recovery still starts
at the saved `lastAccruedAt`, never replaying earlier work. No offline cap, multiplier, early XP
award, or collection is added. Character reset is not a profile boundary.

Private `ProductionService/ProfileCheckpoints` is driven by an owned Heartbeat connection. Its
configurable `Production.onlineCheckpointIntervalSeconds` initially equals 30 seconds, independent
of the one-second accounting batch. It calls `DataService.Checkpoint` only for already-loaded
profiles, never `Load` or `SaveNow`. A delayed tick performs one current-time catch-up per loaded
profile rather than replaying missed checkpoint ticks. Stop disconnects the scheduler while leaving
the pure registered hook available for DataService's finalization.

The normal ProfileStore save lifecycle persists committed checkpoints; an in-memory checkpoint is
not a save receipt. `SaveNow` must successfully checkpoint before requesting its asynchronous save.
ProfileStore's `OnLastSave` fallback covers Manual, External, and Shutdown session endings before
active ownership is dropped. Normal release and fallback share per-profile finalization so the
same profile is not settled twice. DataService Stop rejects new admissions/public mutations, then
finalizes active profiles before cleaning their listeners, even if other feature services already
stopped. A failed release logs the failure, retains
the last valid ledger/cursor, and still ends the session; it must not invent an offline marker or
advance past unresolved work. A failed Ready settlement never exposes the profile as loaded.

No new GUI, remote, capture grant, prototype-ledger migration, or durable-save guarantee is included.
The existing prototype stand accrual remains separate. Controlled hook/scheduler and serialized
continuation tests check atomicity and arithmetic; real join/leave/shutdown ordering, session loss,
and durable persistence still require playtesting outside the default ephemeral Studio mock.

### On-demand Shrine settlement

`ProductionService.SettleShrines(player)` exposes server-only settlement through the typed
`ProductionApi` and `MainServer` service facade. The public method requires a running service and a
connected player. It accepts no elapsed time, timestamp, metadata, or submitted ledger, and never
loads a profile automatically. Normal transaction failures/revisions are returned to the caller;
success includes `values = { settledAt = timestamp }`.

Private `ShrineProduction.new(DataService, clock?)` supplies `Settle(player)`, which calls
`DataService.Update(player, "Production.SettleShrines", callback)`. Read the server clock exactly
once inside that callback, after entering the transaction, and pass it with the detached draft to
`ShrineAccounting.SettleToDraft`. The default clock is `workspace:GetServerTimeNow()`; deterministic
tests may inject it. Use the loaded player's canonical state and default launch metadata; no caller
overrides are accepted by the public service method.

An accepted call participates in the existing DataService transaction/save machinery; it is not a
durable-save acknowledgement. Repeated calls at the same timestamp accrue no duplicate output or
XP, although each successful server-authored `Update` records its own receipt and revision. This
command adds no explicit `SaveNow`, new save/checkpoint loop, join/leave/timer settlement, automatic
profile load, assignment/capture action, remote, or UI. Existing stand production remains unchanged.
Controlled DataSource tests exercise the command boundary without claiming live persistence.

Assignment, evolution, upgrade, collection, and other production mutations must compose
settlement and their change inside one transaction draft. Do not call `SettleShrines` and then
change inputs in a separate transaction: this command is an on-demand settlement operation, not
the atomic mutation wrapper for another feature.

### Shrine management read view

`BaseService.GetShrine(player, { shrineInstanceId })` returns
`{ ok, code?, revision, view? }` for a genuine connected Player while running, using only an
already-loaded profile. Private `ShrineView` validates the loaded transaction revision, closed
one-field request, canonical accounting snapshot, currency, and Material capacity/reservations.
Its injected access guard runs after revision/request validation and before accounting projection.
Unavailable profiles return `DataUnavailable` with revision zero; invalid revisions return
`InvalidTransaction` with revision -1. Other failures retain the loaded revision and omit the view.
Unowned Shrine selections return `ShrineNotOwned`. No other owner, timestamp, or supplied ledger is
accepted; this revision is not the State packet sequence.

The detached public allowlist contains selected Shrine identity/definition/build slot, current and
maximum Shrine levels, element and Material ID, whole `stored` output and configured storage capacity.
`slots` lists only unlocked numeric slot IDs in order, with optional worker summaries containing
owned ID, form ID, XP level, confirmed XP, and derived Yield. `availableWorkers` is sorted by owned
ID and contains matching-element canonical workers not assigned anywhere; choosing one still requires
an empty unlocked slot. Opaque retained prototypes are excluded without being deleted or converted.
No internal form stage, inactive Luck/Trait data, pending XP, raw work accumulator, clock cursor,
receipt, or arbitrary saved field is exposed.

`yieldPerHour` is the current nominal assigned total, and `isProducing` is false at full storage or
zero Yield. `ShrineAccrual.ReadProduction` derives `productionProgress` (zero through one) from
retained unfinished work using the same near-integer correction as accounting. It never turns that
progress into a stored Material. Optional `estimatedSecondsToNextMaterial` is a nominal duration
relative to the committed accounting cursor, rounded to its next eligible fixed batch, not a
wall-clock countdown or promised completion time. It is absent when full or when unfinished work
cannot advance without workers; already-earned whole work awaiting a batch still has an estimate
after unassignment. Future level gains or roster changes can change the estimate. No read samples
time, advances a batch, settles a job, awards XP, or starts a transaction/save.

`collectable` is the whole quantity that fits now, protecting active crafting refund reservations;
`canCollect` and `collectCode` distinguish `NothingToCollect` from `InventoryFull`, with emptiness
taking precedence. Positive partial collection remains available. `canDismantle`/`dismantleCode`
report `ShrineOccupied` before `MaterialsStored`; unfinished work alone does not prohibit removal.
These are committed-state previews: a due batch can create stored output before a real dismantle,
and due-job settlement can release space before a real collection. The mutation still revalidates
after its normal atomic preparation and settlement.

The optional `upgrade` supplies the existing command's current-level and price quotes, matching
Material/owned quantity, target level, worker slots and storage, `canUpgrade`, and a specific shortage
code. Maximum level returns no further offer and `upgradeCode = "MaxLevel"`. Private
`ShrineUpgradePurchase.ReadOffer` supplies canonical metadata to `ShrineUpgrades.ReadOffer`, sharing
the mutation's path and pre-debit checks without calling it or changing its stale-quote ordering.
Only ordinary Gold/Material shortages remain offer reasons; malformed state/configuration rejects
the whole view. Stored production and reservations cannot pay a purchase.

The [Shrine endpoint](#shrine-request-endpoints-and-world-access) exposes this view with server-owned
world access checks. Authored placement, GUI, connected-player interaction, and durable retention
require separate work or verification.

### Atomic Shrine-assignment commands

`BaseService.AssignShrineWorker(player, request)` and `RemoveShrineWorker(player, request)` expose
assignment through the typed Base API and `MainServer` service facade. Both require a
running service and connected player; they do not auto-load a profile. Assignment takes `requestId`,
`expectedRevision`, `shrineInstanceId`, numeric `slotId`, and `workerId`. Removal substitutes
`expectedWorkerId` for `workerId`. The request ID is `<expectedRevision>:<unique token>`; retry the
original request unchanged. The server derives a length-delimited signature from the selected
identities/slot, so reusing an ID for different intent rejects rather than replaying another action.

Private `BaseService/ShrineWorkers.new(DataService, clock?, checkAccess?)` implements `Assign` and
`Remove` using `DataService.Transact`. Each fresh callback checks access, reads server time once, and calls
`Shared.ShrineAccounting.ChangeAssignmentsToDraft` with the appropriate private `ShrineAssignments`
reducer. The default clock is `workspace:GetServerTimeNow()` and the metadata is the real launch
catalogue; deterministic tests may inject the clock. Callers supply no ledger, timestamp, metadata,
or progression defaults. Canonical forms still assigned to prototype stands reject at the adapter
boundary. The reducer settles the preceding interval before changing slots, all inside the same
detached draft transaction. It never composes two separate service transactions.

Success returns `values = { shrineInstanceId, slotId, workerId, settledAt }`; removal reports the
removed worker. DataService owns revision-bound receipts, rollback, active-session checks, and
normal state publication/persistence. Rejected or duplicate commands do not independently advance
accounting; receipt replay does not resample time or rerun the reducer. Unassignment preserves the
owned instance, pending XP, all earned Shrine work, and the common batch schedule.

The retired `Inventory.DeleteMythling` endpoint now rejects all requests without reading ownership,
unassigning, or deleting anything; retained prototype and canonical entries remain untouched. The
private legacy removal helper also retains its canonical/pending-work protections. Assignment itself
adds no acquisition path, save schema, timer, `SaveNow` call, model, or menu. Its
[admitted endpoints](#shrine-request-endpoints-and-world-access) preserve the transaction boundary.
Controlled transaction tests establish in-session atomicity, not durable saves; actual
connected/disconnected-player dispatch and persistence still require a playtest.

### Atomic Shrine-collection command

`ProductionService.CollectShrine(player, request)` exposes collection through the typed
`ProductionApi` and `MainServer` service facade. It requires a running service, connected player,
and already-loaded profile. The strict request contains only `requestId`, `expectedRevision`,
`shrineInstanceId`, and `expectedMaterialId`. The request ID is
`<expectedRevision>:<unique token>`; retry the original request unchanged. The server derives a
length-delimited signature from the selected Shrine and expected Material identities and fixes the
operation as `Production.CollectShrine`. Clients cannot supply an amount, ledger, clock, metadata,
capacity, or reservations.

Private `ProductionService/ShrineCollector.new(DataService, clock?, checkAccess?)` implements `Collect`
using `DataService.GetLoadedData` and `Transact`. Inside the fresh callback, check access, read the
clock once, then call
`Shared.ShrineAccounting.ChangeStorageToDraft` with the private `ShrineCollection.Collect` reducer.
The default clock is `workspace:GetServerTimeNow()` and metadata resolves to the real launch
catalogue; tests may inject the clock. Build the reducer's Material view from that same draft's
Materials, Inventory upgrades, and crafting reservations. After the accounting bridge succeeds,
install the reducer's returned Material map in the same callback. Never use separate
`SettleShrines` and Material-grant transactions: the cursor, stored debit, earned work/XP, and grant
must commit or roll back together.

Success returns `values = { shrineInstanceId, materialId, collected, remaining, settledAt }`.
Transfer all whole Materials that fit, accepting a positive partial collection while retaining the
rest in Shrine storage. Preserve unfinished production, assignments, identities, inactive metadata,
jobs, and reservations. No whole output returns `NothingToCollect` even when Inventory is full;
positive stored output with no room returns `InventoryFull`. All domain rejections discard staged
gameplay changes, including accounting; DataService may still record a failure receipt and revision.
DataService owns active-session checks, rollback, revision-bound receipts, normal state publication,
and persistence. A matching retry replays the original result without resampling time, rerunning
accrual, or granting Materials again.

Its [admitted endpoint](#shrine-request-endpoints-and-world-access) adds no menu, model, new acquisition,
schema migration, automatic production lifecycle, profile auto-load, or explicit save request.
The prototype stand-collection path remains unchanged.
Controlled transaction tests establish in-session atomicity and serialized continuation, not durable
saves. Actual connected/disconnected-player dispatch and persistence still require a playtest.

### Atomic Shrine-upgrade command

`BaseService.UpgradeShrine(player, request)` exposes upgrades through the typed `BaseApi`
and `MainServer` service facade. It requires a running service, connected player, and already-loaded
profile. The strict `Types.UpgradeShrineRequest` contains only `requestId`, `expectedRevision`,
`shrineInstanceId`, `expectedLevel`, `expectedMaterialId`, `expectedGoldCost`, and
`expectedMaterialQuantity`. The request ID is `<expectedRevision>:<unique token>`; retry the original
request unchanged. The server fixes the operation as `Base.UpgradeShrine` and derives a
length-delimited signature binding the selected Shrine, current level, and every expected quote
field. The quote is a stale-selection check, not purchase authority. Callers cannot supply a target
level, ledger, timestamp, metadata, capacity, or reservations.

Private `BaseService/ShrineUpgradePurchase.new(DataService, clock?, checkAccess?)` implements `Upgrade`
using `DataService.GetLoadedData` and `Transact`. Check access and read the clock exactly once inside
the fresh callback, then call
`Shared.ShrineAccounting.ChangeShrineLevelToDraft` with the selected instance and private
`ShrineUpgrades.Upgrade` reducer. The default clock is `workspace:GetServerTimeNow()`; tests may
inject it. The accounting view uses canonical launch form/Shrine metadata; the purchase adapter
adds each Shrine definition's configured `maxLevel` for the reducer's complete path validation.
Build its resources from the same draft's Materials, Inventory upgrades, crafting reservations, and
Gold. After the bridge succeeds, install the returned Material map and Gold in the same callback,
preserving other currency fields. Do not call standalone settlement or separate payment mutations.

The reducer settles the entire profile at the old level/capacity before committing the selected
next level. Gold, matching owned Inventory Materials, accounting, level, and the revision-bound
receipt commit or roll back together. Uncollected Shrine output and crafting refunds cannot pay the
price, and jobs/reservations remain unchanged. Preserve identities, assignments, other Shrine levels,
stored output, unfinished work, earned/pending XP, and the common schedule. The new slot starts empty;
larger storage affects future work without backfilling time previously paused at full storage.

Success returns `values = { shrineInstanceId, previousLevel, level, materialId, goldSpent,
materialsSpent, settledAt }`. Stale quotes/levels, unaffordable costs, malformed state, and terminal
levels reject without committing staged gameplay changes; DataService may still record the failure
receipt and revision. DataService owns active-session checks, rollback, normal state publication,
and persistence. A matching retry replays the original result without resampling time, rerunning
accrual, or charging again.

Its [admitted endpoint](#shrine-request-endpoints-and-world-access) adds no menu, model, acquisition path,
schema migration, automatic lifecycle settlement, profile auto-load, or explicit `SaveNow` call.
Existing prototype paths remain unchanged. Controlled
transaction tests cover purchase and receipt safety, retained state, and rollback, not durable saves.
Actual connected/disconnected-player dispatch and persistence still require a playtest.

### Atomic Mythling-evolution command

`InventoryService.EvolveMythling(player, request)` supplies canonical evolution through the typed
`InventoryApi` and `MainServer` service facade. It requires a running service, connected player, and
already-loaded profile. The strict `Types.EvolveMythlingRequest` contains only `requestId`,
`expectedRevision`, `workerId`, `expectedFormId`, and `expectedTargetFormId`. The request ID is
`<expectedRevision>:<unique token>`; retry the original request unchanged. The server fixes the
operation as `Inventory.EvolveMythling` and derives a length-delimited signature binding the owned
identity, expected current form, and expected target. These expected IDs detect stale selections;
callers cannot supply eligibility, progression, metadata, accounting, or time.

Private `InventoryService/MythlingEvolutionCommand.new(DataService, clock?)` implements `Evolve`
using `DataService.GetLoadedData` and `Transact`. Read the clock exactly once inside the transaction
callback, then call `Shared.ShrineAccounting.ChangeWorkerFormToDraft` with the selected worker and
target and the private `MythlingEvolution.Evolve` reducer. The default clock is
`workspace:GetServerTimeNow()`; tests may inject it. Extend the shared accounting metadata with the
canonical `MythlingForms` evolution links, keeping each configured target and required level. Do
not call standalone settlement or mutate the form in a second transaction.

The reducer validates the chain and expected forms, then settles the whole profile under the old
form before checking the resulting level against the configured requirement. Due XP may make the
action eligible; partial-batch XP stays pending. Evolution is free, manual, and valid while assigned
or while storage is full. Each success follows exactly one link and preserves owned identity,
level, XP, pending credit, assignments, stored output, unfinished work, inactive legacy values, and
the common schedule. Consecutive eligible links need separate requests but no retraining. The
bridge merges only the selected `typeId` plus normal accounting/progression, never replacing owned
records or saving copied static metadata.

Success returns `values = { workerId, previousFormId, formId, level, xp, settledAt }`; pending XP
remains private. Form change, accounting, progression, and the revision-bound receipt commit or
roll back together. Stale forms/targets, insufficient level, terminal forms, and malformed state
reject without committing staged gameplay changes; DataService may still record the failure
receipt and revision. DataService owns active-session checks, rollback, normal state publication,
and persistence. A matching retry replays the original result without resampling time, repeating
settlement, or following another link.

The admitted [Inventory endpoint](#inventory-request-endpoints) delegates to this command without
adding a menu, capture grant, schema migration, automatic production lifecycle, profile auto-load,
or explicit `SaveNow` call. Controlled transaction
tests establish in-session and serialized-state behavior, not durable saves. Actual connected/
disconnected-player dispatch and persistence still require a playtest.

### Atomic Mythling-sale command

`InventoryService.SellMythling(player, request)` supplies canonical sales through the typed
`InventoryApi` and `MainServer` service facade. It requires a running service, connected player, and
already-loaded profile. The strict `Types.SellMythlingRequest` contains only `requestId`,
`expectedRevision`, `workerId`, `expectedFormId`, and `expectedGoldValue`. The request ID is
`<expectedRevision>:<unique token>`; retry the original request unchanged. The server fixes the
operation as `Inventory.SellMythling` and derives a length-delimited signature binding the owned
identity, expected current form, and quoted Gold value. The quote detects stale selections, not
payment authority; callers cannot supply owned records, progression, metadata, accounting, or time.

Private `InventoryService/MythlingSaleCommand.new(DataService, clock?)` implements `Sell` using
`DataService.GetLoadedData` and `Transact`. Read the clock exactly once inside the callback, then
call `Shared.ShrineAccounting.RemoveWorkerToDraft` with the selected worker and the private
`MythlingSales.Sell` reducer. The default clock is `workspace:GetServerTimeNow()`; tests may inject
it. Extend shared accounting metadata with canonical `MythlingForms` sale definitions and take Gold
from the same draft. After the bridge succeeds, install the returned Gold inside that callback,
preserving unrelated currency fields. Never delete, settle, and pay in separate transactions.

Require explicit unassignment before selling, even if the assigned Shrine is full. Final-copy sales
are allowed. The current form's configured value supplies the payout without a level, XP, rarity,
acquisition, or inactive legacy modifier. Settle the whole ledger on its normal schedule, remove
exactly the selected owned record, and credit its configured Gold together. Retain all Shrine output
and unfinished work, every other worker's earned/pending XP, the common schedule, Materials,
crafting jobs/reservations, and unrelated profile state. Pending XP remaining on the sold instance
retires with it rather than being awarded early or transferred. No copied price, metadata, or new
progression defaults are saved.

Success returns `values = { workerId, formId, goldGranted, settledAt }`. Deletion, accounting, Gold,
and the revision-bound receipt commit or roll back together. Stale forms/prices, assigned workers,
invalid state, or unsafe currency arithmetic reject without committing staged gameplay changes;
DataService may still record the failure receipt and revision. DataService owns active-session
checks, rollback, normal state publication, and persistence. A matching retry replays the original
result without resampling time, repeating settlement, or paying again.

The admitted [Inventory endpoint](#inventory-request-endpoints) delegates to this command without
adding a menu, capture grant, schema migration, automatic production lifecycle, profile auto-load,
or explicit `SaveNow` call. Legacy `DeleteMythling` rejects every request without side effects;
deletion is not a sale API. Controlled
transaction tests do not establish live durable saves. Actual connected/disconnected-player
dispatch and persistence still require a playtest.

### Atomic Shrine-dismantling command

`BaseService.DismantleShrine(player, request)` exposes removal through the typed
`BaseApi` and `MainServer` service facade. It requires a running service, connected player, and
already-loaded profile. The strict request contains only `requestId`, `expectedRevision`,
`shrineInstanceId`, and `expectedLevel`. The request ID is `<expectedRevision>:<unique token>`;
retry the original request unchanged. The server fixes the operation as `Base.DismantleShrine`
and derives a length-delimited signature binding the selected instance and expected level.
Callers cannot select a build slot or owner, supply accounting, metadata, or time, or request a refund.

Private `BaseService/ShrineRemoval.new(DataService, clock?, checkAccess?)` implements `Dismantle` using
`DataService.GetLoadedData` and `Transact`. Check access and read the clock exactly once inside the
fresh transaction callback, then call `Shared.ShrineAccounting.RemoveShrineToDraft` with the selected instance and
private `ShrineDismantling.Dismantle` reducer. The default clock is `workspace:GetServerTimeNow()`;
tests may inject it. Pass the same draft's Base ownership to the reducer and resolve accounting
against canonical launch metadata. The bridge merges surviving canonical accounting records and
removes only the selected record; it must not install the reducer's ownership-only Shrine map over
records containing saved work and assignments. Do not use a separate settlement transaction.

Reject assigned workers without automatically unassigning them. For an unoccupied Shrine, settle
the entire profile, then reject if it contains any whole output, including output completed by a
due batch. Require collection first. On success discard only the removed Shrine's unfinished
`progress` and `newWork`; do not resolve a partial batch early or shift its schedule. Keep every
owned worker, earned/pending XP, surviving Shrine's accounting and assignment, purchased build
slots, permanent Station, prototype stands, and unrelated profile state. The operation grants no
Gold, Materials, refund, or stored-building record and touches no crafting reservations. The
existing construction allocator can reuse the free slot with a new unique Shrine identity.

Success returns `values = { shrineInstanceId, shrineId, buildSlotId, level, settledAt }`. Removal,
surviving accounting, progression, and the revision-bound receipt commit or roll back together.
Stale identity/level, occupied/storage gates, or invalid state reject without committing staged
gameplay changes; DataService may still record the failure receipt and revision. DataService owns
active-session checks, rollback, normal state publication, and persistence. A matching retry replays
the original result without resampling time or touching a replacement occupying the old slot.

Its [admitted endpoint](#shrine-request-endpoints-and-world-access) adds no menu, model deletion,
migration, automatic production lifecycle, profile auto-load, or explicit save request.
Future presentation removes a runtime model only after a
successful transaction. Controlled transaction tests cover removal gates, receipt safety, retained
state, and rollback, not durable saves. Actual connected/disconnected-player dispatch and persistence
still require a playtest.

### Shrine operations over detached accounting

`ServerScriptService.Services.BaseService.ShrineAssignments.Assign` and `.Remove` compose that same
reducer with validated slot changes.
Their input is one server-selected profile's accounting view, not a client-submitted ownership map.
`workerIdsBySlot` uses canonical string keys (`"1"`, `"2"`, `"3"` for the launch levels), preserving
empty gaps and JSON round trips. It is the sole assignment map; worker records carry no mirrored
assignment authority. Accrual sums workers in numeric slot order and rejects duplicate ownership
links, locked/noncanonical slots, or element mismatches. The earlier detached dense `workerIds`
test-ledger shape was never saved or used by the live game; replacing it requires no save migration.

Assignment takes `workerId`, `shrineInstanceId`, and numeric `slotId`; it rejects any already-assigned
worker or occupied target. Removal takes `shrineInstanceId`, `slotId`, and `expectedWorkerId` and
rejects stale occupants. Both validate before accrual, then settle the preceding interval and change
only the selected slot in a detached result. Reject backdated changes; two accepted commands at the
same time do not earn additional work. Unassigning leaves the Mythling owned, retains its pending XP,
and preserves all Shrine output/progress and other slot identities. The caller must commit the whole
returned ledger, never only the slot change. The pure operations provide neither authentication nor
request receipts: the [assignment commands](#atomic-shrine-assignment-commands) now supply the
authenticated loaded profile, serialized DataService transaction, revision/receipt checks, and
server-authored time through the shared draft adapter. No new schema, remote, prototype
stand-assignment path, or creative content is introduced. The adapter also rejects canonical forms
still assigned to a legacy stand; the isolated Shrine view alone cannot prove no such conflict exists.

`ServerScriptService.Services.ProductionService.ShrineCollection.Collect` composes the same reducer
with whole-Material collection. Its accounting and Inventory views must come from the same
authenticated loaded profile. The request selects `shrineInstanceId` and `expectedMaterialId`;
reject an unowned Shrine, changed output ID, backdated time, malformed Material
quantities/reservations, or invalid purchased Material-capacity state without changing either input.
Settle all prior work before calculating the selected Shrine's transfer, preserving unfinished work,
pending XP, and the existing batch schedule. A previously full Shrine resumes work after collection
time, never retroactively during its full-storage pause.

The server-only shared `ServerScriptService/Shared/InventoryCapacity` owns per-type stack rounding,
derived category limits, and active crafting reservations. `ValidateMaterialState` adds strict
validation for new collection callers; the existing capacity methods and live prototype callers
retain their previous behavior. Refund reservations reduce available space but are never consumed
or released by collection, and unknown retained Material IDs still occupy capacity.
`NothingToCollect` takes precedence over `InventoryFull` when settlement leaves no whole output.
Otherwise transfer all that fits, retaining any excess in Shrine storage. Collection itself awards
no XP.

A successful result returns the detached accounting ledger, replacement Material map, actual
collected quantity, and remaining storage. The [collection command](#atomic-shrine-collection-command)
now commits both views together, preserving the profile's other fields and jobs; committing only
the grant or debit is invalid. Rejections return no staged result and leave both inputs unchanged.
The pure operation itself has no authentication, revision/receipt persistence, remote, or live save
integration; its command supplies those transaction guarantees using the fixed launch Material
references. Synthetic-content tests verify reducer behavior, while command tests exercise canonical
state and transaction composition. Neither replaces the prototype stand-collection path.

`ServerScriptService.Services.BaseService.ShrineUpgrades.Upgrade` performs detached payment and
sequential level changes over the same accounting engine. `Configurations/Shrines` shares one level
table across all six definitions: levels 1/2/3 own 1/2/3 worker slots and 300/1,200/3,600 storage.
`upgradeCost` belongs to the target level: level 2 costs 1,000 Gold plus 400 matching Materials;
level 3 costs 15,000 Gold plus 4,000.
Level 1 has no upgrade cost and retains its separate construction price. These static values are
not copied into saved Shrine records. The [upgrade command](#atomic-shrine-upgrade-command) resolves
the canonical launch Material IDs and forms; isolated reducer tests continue to use synthetic content.

The operation takes accounting and resource views from one authenticated profile, server time, and
the expected current level, Material ID, Gold cost, and Material quantity. It validates the selected
definition's explicit maximum, contiguous level path, one added slot per level, increasing storage,
and positive whole costs. Re-resolve the next level rather than accepting a requested target level.
Reject stale selections/quotes, malformed state, unaffordable costs, and terminal-level requests
without committing even the staged accounting. Reuse strict Inventory/reservation validation, but
spend only owned Inventory quantities; outstanding refunds and uncollected Shrine output are not
payment. Spending neither resolves a Crafting Job nor changes its reservations.

After validating the payment, settle prior production/XP under the old level, debit Gold and matching
Materials, and increase only the selected Shrine's level in a detached result. Remove the Material
entry when its owned quantity reaches zero. Retain assignments, other Shrines, unfinished production,
pending credit, and the batch schedule; new slots start empty. Increased storage changes future
eligibility without recovering full-storage time or multiplying worker Yield/XP. The
[upgrade command](#atomic-shrine-upgrade-command) now commits the returned ledger, Material map, and
Gold together with its revision-bound receipt, merging only those fields into the profile. The pure
reducer itself supplies no authentication, network request, durable save, or schema migration; its
command supplies the authenticated transaction boundary without adding player-facing integration.

`ServerScriptService.Services.BaseService.ShrineDismantling.Dismantle` pairs the accounting view
with the same loaded profile's Base ownership. Validate Base capacity/Station records and accounting
first, then require a one-to-one match of all built/accounting Shrine instance IDs, definition IDs,
and levels. A missing ledger must not be interpreted as an empty Shrine. This consistency check
does not authenticate either view; the [dismantling command](#atomic-shrine-dismantling-command)
selects both from the requesting player's loaded canonical draft with complete accounting for every
constructed Shrine. These are views of the same owned records, not separate persisted identity/level
authorities. The request selects a unique
instance ID and expected level, never a build-slot number; stale IDs cannot remove a replacement in
the same slot.

Reject occupied Shrines without automatically unassigning their workers. Otherwise settle the entire
profile before checking the selected Shrine's completed storage. If settlement produces any whole
Material, reject and require collection. Before the next batch boundary, unresolved work remains
unfinished and can be discarded; dismantling neither completes a batch early nor shifts the schedule.
Remove only the chosen Shrine's accounting and built record, discarding its progress/new work while
retaining every worker and its earned or pending XP. Due credit continues on the retained profile
schedule even when no source Shrine remains. Rejections return no staged state, including when a
detached settlement completed output or failed arithmetic validation.

The result supplies the complete replacement accounting ledger and built-Shrine map, not a whole Base
or PlayerDoc. The [dismantling command](#atomic-shrine-dismantling-command) now commits removal with
revision/receipt protection through the shared removal bridge. Merge surviving accounting into the
canonical records rather than overwriting them with the reducer's ownership-only map; preserve
purchased build slots, other Shrine slot identities, Station identity, prototype stands, and all
unrelated profile state. No refund or stored-building record is created. The existing lowest-free
allocation can reuse the released slot; reconstructed instances must receive new unique IDs. Future
presentation may remove the runtime model only after the transaction succeeds. The isolated reducer
itself adds no authentication, live endpoint, model deletion, persistence migration, or UI.

`ServerScriptService.Services.InventoryService.MythlingEvolution.Evolve` performs a manual, free
form change over the same detached accounting view. Its form definitions extend the accounting
metadata with optional `evolution = { targetFormId, requiredLevel }`. The link owns its required
level; there is no runtime rarity/stage formula or fallback threshold. Absence means terminal. The
separate [launch form catalogue](#launch-mythling-form-catalogue) supplies the configured links at
levels 6 and 40. This isolated reducer's tests inject synthetic definitions; the
[evolution command](#atomic-mythling-evolution-command) supplies those real links and canonical
owned-record adaptation. Legacy prototype-roster replacement remains separate work.

The request selects `workerId`, `expectedFormId`, and `expectedTargetFormId`. Validate ownership,
state, server-authored time, and both expected IDs, rejecting backdated or stale changes. Validate
the selected form's entire reachable chain for existing definitions, finite non-negative base Yield,
same element, whole required levels within the configured cap, and no self-links or cycles. This
generic safety check does not replace the full launch-catalogue validation below (six complete
chains, rarity/stage assignments, unique predecessors, and increasing base Yield).

Settle the whole accounting view with the **old** form before testing the settled level against the
link requirement. Due XP may satisfy eligibility; unresolved partial-batch XP is not granted early.
On success change only the selected worker's `formId`, then validate the result including the target
form's level-adjusted Yield. Retain owned identity, level, XP, pending credit, Shrine assignments,
stored output, unfinished work, and the batch schedule. Existing inactive legacy worker fields are
preserved, never required or rerolled. Same-element evolution remains valid while assigned; full
storage does not block an already-eligible request. Each action follows one link, so a sufficiently
leveled worker can take consecutive same-timestamp actions without retraining or extra settlement.

Rejections return no staged state and leave inputs unchanged, including after detached settlement or
target arithmetic failure. The evolution command commits the whole successful ledger through an
authenticated profile transaction with revision/receipt protection, merging changed accounting
fields and the selected form into owned records without replacing acquisition or legacy data.
Repeating a stale form request cannot evolve again, but the pure reducer itself supplies no durable
receipt, authentication, live endpoint, schema migration, or UI.

### Atomic Base-expansion command

`BaseService.ExpandBase(player, request)` is the command for the requesting connected
player's already-loaded profile while BaseService is running. Private
`BaseExpansionPurchase.new(dataSource, checkAccess?).Expand(player, request)` owns payment and the
sequential purchase through one revision-bound `DataService.Transact`; no profile auto-load, GUI,
model placement, or schema migration is introduced. Production supplies the mandatory world-access
guard described [below](#base-request-endpoints-and-world-access); headless tests may omit it.

The closed request carries `requestId`, `expectedRevision`, `expectedUpgradeCount`,
`expectedGoldCost`, and `expectedMaterialQuantity`. The final field quotes the whole quantity of
**each** of the six normal Materials. Resolve the next cost from
`Configurations.Bases.buildSlotUpgradeCosts` and fixed mix from `expansionMaterialIds`, not a
client-selected upgrade index, Material map, build slot, or target capacity. The initial four prices
are 10,000/50,000/150,000/500,000 Gold plus 50/100/150/200 of every normal Material respectively.
Each purchase adds one slot to the initial two; four purchases reach six unlocked slots.
The Material mix is shared with Inventory upgrades through `Configurations.UpgradeMaterials`;
`UpgradePaymentUtil` validates and pays both features' fixed recipes without sharing their prices.

Validate the current player-data schema, Base/Station ownership and slot assignments, saved expansion
count, current costs, Gold, collected Material quantities, Inventory-upgrade state, and crafting
reservations against the same draft. Reject stale quoted progression/prices, missing ingredients, malformed state, and
terminal-level requests without spending. Matching Shrine ownership and a particular element layout
are not prerequisites; an empty Base or duplicate-element layout remains eligible when affordable.
The included Station is unchanged and never costs Gold or occupies one of these slots.
The complete recipe plus active refund reservations must fit the existing Material capacity before
payment; unrelated retained holdings cannot substitute for ingredients. Configured costs must be
positive whole quantities and the fixed mix must contain exactly one enabled normal Material per
element. Reject capacity proof failure with `MaterialCapacityTooSmall`; stale purchase counts,
changed prices, and a fully expanded Base return `UpgradeCountChanged`, `PriceChanged`, and
`MaxBaseSlots` respectively.

Atomically debit Gold and all six owned Material quantities, advance `base.buildSlotUpgrades` by
exactly one, and commit the request receipt. Derive unlocked capacity from configuration and that
purchase count rather than saving copied limits or costs. Preserve every existing Shrine's stable
slot ID, workers, output, unfinished work, and XP; the new logical slot is empty. Adding unoccupied
build capacity changes no production input, so it must not restart or alter the accounting clock.
Do not consume Shrine storage, spend or release job refund reservations, create a Shrine, move a
worker, or add a waiting timer.

Use transaction operation `Base.Expand` and bind the receipt signature to every quoted field.
Success returns `previousUpgradeCount`, `upgradeCount`, `unlockedShrineSlots`, `maxShrineSlots`,
`goldSpent`, and `materialsSpentPerType`. The normal State projection carries derived Base status;
after a fresh success the service also refreshes capacity attributes on its existing runtime Base.
Replayed results do not perform that refresh or a second profile read. The private purchase arithmetic
remains headless; fresh public purchases require the caller's live Base and authored interaction anchor.

Retrying the original request returns its recorded result; reusing the ID with different quotes
conflicts, and stale/evicted requests cannot purchase again. Purchased slots remain owned through
dismantling, reset, reconnect, and later price changes
without retroactive payment. Runtime transaction success and serialized tests do not establish
durable-save acknowledgement.

### Base management read view

`BaseService.GetBase(player)` returns `{ ok, code?, revision, view? }` for a genuine
connected Player while the service is running. It reads only that caller's already-loaded profile;
unavailable callers/profiles return `DataUnavailable` with revision zero. Private `BaseView` validates
the transaction revision, current schema, Base/Station/slot ownership shape, Gold, owned Material
quantities, purchased Material capacity, and active refund reservations before returning any view.
An invalid revision returns `InvalidTransaction` with revision -1; other failures retain the
loaded transaction revision and omit the whole view. This revision is not the State packet sequence.
Production injects the same Base world-access guard used for fresh purchases; the read invokes it
after loaded-profile/revision validation and before projecting any offers.

The detached, allowlisted view contains:

- `status`: existing derived `BaseStatus`, including used/unlocked/maximum Shrine slots and the
  permanent Station identity, which never occupies a build slot;
- `buildSlotUpgradeCount` and `shrines` sorted by build-slot number (then ID), each containing only
  `id`, `shrineId`, `buildSlotId`, and `level`;
- `buildOffers` sorted by definition ID, with one row per configured launch Shrine containing
  `shrineId`, `goldCost`, `canBuild`, and optional `buildCode` (`BaseFull` or `InsufficientGold`);
- the next `expansion`, containing `expectedUpgradeCount`, `goldCost`, `materialQuantity`,
  `nextUnlockedSlots`, `canPurchase`, optional `purchaseCode`, and the six sorted `materials` rows
  with `materialId`, required `quantity`, and actual `ownedQuantity`;
- at maximum unlocked capacity, no expansion offer/price and `expansionCode = "MaxBaseSlots"`.

`ShrineConstruction.ReadOffer` shares its metadata and pre-ID slot/currency eligibility with Build.
`BaseExpansionPurchase.ReadOffer` shares schema/configuration/Base validation with Expand and uses
`UpgradePaymentUtil.CheckPayment`, the same nonmutating pre-debit check called by `PayToDraft`.
Expansion affordability/capacity failures remain visible as offer reasons; malformed state or
configuration fails the whole view. Duplicate-element and empty Base layouts do not restrict the
fixed Material recipe. Only owned Inventory inputs count, not Shrine output or refund reservations.
The recipe itself must fit pre-purchase capacity alongside unchanged reservations; unrelated retained
over-capacity holdings do not introduce a new purchase prohibition.

Reads never call a purchase, allocate a Shrine identity, settle production/crafting, modify a
reservation, sample time, load a profile, or save. Eligibility describes committed state, not a
simulation of mutation preparation: a due job may still reserve space in the view until its normal
settlement releases it. Every real action revalidates its quote and state after transactional
preparation. Private receipts, progress/XP ledgers, prototype stands, other inventory, and arbitrary
saved extras are omitted; returned rows never alias saved/configuration tables. The admitted
transport and world boundary follow below; no authored placement or GUI is added.

### Base request endpoints and world access

`Network.Base.GetBase`, `BuildShrine`, and `ExpandBase` are Rojo-declared RemoteFunctions returning
the existing `BaseViewResult` and `TransactionResult` shapes. Get takes no payload; the two purchases
forward their closed envelopes unchanged to the public Base service. Private `BaseRequests` admits
the genuine connected Player and running service before its shared token bucket, profile, or world
work. `Configurations.BaseRequests` initially allows twelve tokens and refills four per second.
Unavailable and limited calls return `DataUnavailable` or `RateLimited` with revision zero.
The existing prototype PlaceMythling/RemoveMythling routes retain their separate six/two bucket and
behavior. The five canonical Base-owned Shrine routes below share this same twelve/four bucket;
there are eight canonical routes total. Departures forget both buckets; Stop clears all ten
Base handlers and limiter state.
Retained callbacks reject after Stop.

Production initialization injects one access guard into BaseView, ShrineConstruction, and
BaseExpansionPurchase; their private constructors may omit it for headless tests. `BaseAccess`
validates saved Base state, resolves the caller's unique server-owned slot, and requires its Base
model to remain directly under the runtime Bases folder in Workspace. `Configurations.Bases`
owns `interactionAnchorPath`, initially `NameSign/BasePromptAttachment` beneath BaseLevel1, and
`interactionDistanceStuds`, initially four. Every path segment must be unique; its final Attachment
must be parented to a BasePart. Missing, detached, wrong-class, or ambiguous bindings return
`BaseUnavailable`; malformed saved ownership returns `InvalidBaseState`.

The current character must remain in Workspace with a living Humanoid and unique HumanoidRootPart.
Its finite three-dimensional root-to-anchor distance must be within the inclusive configured radius.
Missing/dead characters return `CharacterUnavailable`; outside or nonfinite positions return
`OutOfRange`. Private same-feature `WorldAccessUtil` supplies this rule and unique ownership/path
resolution to BaseAccess, CraftingAccess, and ShrineAccess. There is no client Instance, position, OwnerId
attribute, model-pivot fallback, or menu-open claim. These checks do not implement movement locking;
that remains the separate GUI's responsibility.

Read checks occur before projection. Fresh purchase checks occur only inside the transaction
callback, after receipt/revision admission and shared draft preparation, before costs, slots, or IDs
are changed. A fresh access denial rolls back preparation with the purchase. Exact recorded success
and rejection receipts replay without checking current character/anchor state, including after reset,
relocation, or Base removal. Public success replays also skip capacity-attribute refresh and its
profile reread. Payload signatures, due-job settlement, production, and durable-save semantics do
not change; automatic work never depends on proximity.

Studio inspection confirmed the existing NameSign Part but no BasePromptAttachment. The user reserved
anchor/prompt placement for asset/UI work, so no authored instance is added and missing bindings fail
closed. Verify those bindings and real connected-player dispatch before claiming playable Base
management; disposable transaction tests alone do not establish durable retention.

### Shrine request endpoints and world access

`Network.Base` declares `GetShrine`, `AssignShrineWorker`, `RemoveShrineWorker`, `UpgradeShrine`,
and `DismantleShrine`. These five RemoteFunctions share the existing configured twelve-token,
four-per-second canonical Base budget with GetBase/BuildShrine/ExpandBase. Private `BaseRequests`
forwards unchanged payloads and results to the corresponding public command owners. Production
separately owns `Network.Production.CollectShrine` through private `ProductionRequests`, with its
own twelve/four budget in `Configurations.ProductionRequests`. Legacy Base six/two and Production
eight/three budgets and payloads remain unchanged. Every new adapter admits a genuine connected
Player and running service before its budget or protected work; failure returns `DataUnavailable`
or `RateLimited` with revision zero. Stop clears the new handlers and limiter state; departures
forget the player's buckets and retained callbacks reject after Stop.

`BaseService.CheckShrineAccess` and private `ShrineAccess` resolve the selected owned Shrine from
validated saved Base state. Only its server-saved `buildSlotId` selects the permanent world binding:
the unique `ShrineSlots` Folder beneath the caller's own runtime Base, unique anchored `SlotN`
BasePart inside it, and unique direct `ShrinePromptAttachment` Attachment. N is the saved build slot
number, not a worker slot or client-selected position. `Configurations.ShrineInteractions` owns
these names and the initial four-stud inclusive three-dimensional range. All six build slots use
the same rule. These permanent parts are independent of temporary Shrine visuals and survive
upgrade, dismantle, and rebuild. A rebuilt Shrine receives a new saved identity, so a stale request
cannot select its replacement even when the world slot is reused.

Malformed saved ownership returns `InvalidBaseState`; a missing selected ID returns `ShrineNotOwned`.
Missing, duplicate, wrong-class, detached, or unanchored bindings return `ShrineUnavailable`.
`WorldAccessUtil` applies the same live-character, finite root position, and range checks used by
Base/Crafting: `CharacterUnavailable` or `OutOfRange`. No prototype Stands, Shrine model name/pivot,
OwnerId attribute, supplied Instance/position, or menu-open flag substitutes for this binding.
Asset/UI work owns its placement and prompts, and the GUI owns voluntary movement locking.

Production initialization always injects a guard into `ShrineView`, `ShrineWorkers`,
`ShrineUpgradePurchase`, `ShrineRemoval`, and `ShrineCollector`; private constructors may omit it
only for headless use. ProductionService asserts the public Base guard dependency. Read checks run
after loaded revision and closed request validation, before accounting projection. Each mutation
checks access first inside its fresh transaction callback, after receipt/revision admission and
shared draft preparation but before its feature clock, production settlement, or mutation.
Access denial rolls back preparation with the action. Exact success and rejection receipts replay
without current world checks, clock sampling, preparation, or repeated payment/output. This remains
true after relocation, reset, Base removal, or Shrine replacement. Successful fresh dismantling
refreshes Base capacity attributes from committed state; replay skips that refresh and profile reread.

Automatic Ready/Checkpoint/Release production, server settlement, and started Crafting Jobs never
require proximity. This adds no movement lock, GUI, authored models, new schema, or save guarantee.
The inspected Studio Base template has no `ShrineSlots` binding, so fresh Shrine interactions fail
closed until asset/UI work supplies it. Disposable tests cover routes, ordering, rollback/replay,
saved-slot resolution, range, and cleanup, not positive connected-player dispatch or durable saves.

### Atomic Inventory-capacity upgrade command

`InventoryService.UpgradeCapacity(player, request)` is the canonical command for a connected player's
already-loaded profile while InventoryService is running. Private
`CapacityUpgradePurchase.new(dataSource).Upgrade(player, request)` owns the sequential purchase in
one revision-bound `DataService.Transact`. It neither loads a profile nor
adds a GUI, timer, schema migration, or Shop stock mutation. The admitted
[Inventory endpoint](#inventory-request-endpoints) uses this same command.

The closed request carries `requestId`, `expectedRevision`, `category`, `expectedUpgradeCount`,
`expectedGoldCost`, and `expectedMaterialQuantity`. Categories are exactly `materials`, `mythlings`,
and `equipment`; the last field quotes the amount of each normal Material, not a combined total or
chosen substitute. Resolve the next upgrade and full fixed mix from server configuration. Each
category has two independent +12-slot purchases: Materials/Equipment 12/24/36 and Mythlings 24/36/48.
First purchases cost 20,000 Gold plus 50 of each normal Material; final purchases cost 300,000 Gold
plus 200 of each, defined by `Inventory.capacityUpgradeCosts`. The caller cannot buy multiple
upgrades at once or skip to a later one.

Validate the current player-data schema, category purchase state, quoted count/prices, owned Gold
and Material quantities, and all active refund reservations against the same draft. Check the full
fixed recipe plus those reservations against the Material capacity available **before** increasing
any purchased count. A Material-capacity upgrade cannot bootstrap space for its own ingredients.
A full category may still be upgraded when the player already owns a valid payment; no free output
slot is required because this action acquires capacity, not an item.
Absent saved category counts mean zero purchases. Validate every known category's present count as
a whole value from zero through two, retaining unknown saved upgrade fields. Validate the selected
owned collection's shape and bounded instance/Material IDs without deleting or rejecting entries
merely because their retained count is above the current limit.

`Shared.Configurations.UpgradeMaterials` owns the six-normal-Material mix, re-exported through
`Bases.expansionMaterialIds` and `Inventory.upgradeMaterialIds`. Feature configurations retain their
own prices. Server-shared `UpgradePaymentUtil.PayToDraft` supplies both Base expansion and Inventory
upgrades with the same whole-cost, pre-purchase Material-capacity, and reservation-safe payment
validation. Spend only owned collected Materials and Gold; never spend Shrine storage or reservations,
release reservations, or resolve a Crafting Job as a side effect of payment.

Commit the payment, exactly one increment to `inventoryUpgrades[category]`, and the request receipt
together. Derive capacity from configuration and the saved purchase count; save no copied static
limit, recipe, or price. Preserve other categories' counts, all owned Mythlings and Equipment,
Combat Loadout, purchased Base slots, Shrines/output/XP, production clock, and crafting receipts.
Bind the receipt to the category and all quotes so retries replay the original result and altered
payloads conflict; stale or evicted requests cannot buy capacity twice.
The transaction operation is `Inventory.UpgradeCapacity`; success returns `category`,
`previousUpgradeCount`, `upgradeCount`, `limit`, `maxLimit`, `goldSpent`, and `materialsSpentPerType`.
Changed progression/prices return `UpgradeCountChanged`/`PriceChanged`; a third purchase returns
`MaxCapacity`. Invalid saved upgrade state fails with `InvalidInventoryUpgrade` instead of being
coerced to a cheaper purchase. The payment helper's capacity/affordability/reservation failures roll
back both payment and the capacity grant.

These purchases consume no Shop allowance and depend on no stock period. Shop refresh, reconnect,
reset, and later price changes neither revoke purchased capacity nor charge retroactively. The
second purchase is that category's maximum, not an offer waiting to restock. Automated transaction
and serialized-state tests do not establish connected-player dispatch or durable-save acknowledgement.

### Atomic Material-sale and discard commands

Canonical `InventoryService.SellMaterial(player, request)` and `DiscardMaterial(player, request)`
require a running service, connected player, and already-loaded profile. Private
`MaterialDisposalCommand.new(dataSource).Sell`/`.Discard` use only `GetLoadedData` and `Transact`;
neither loads a profile, reads a clock, nor settles or collects production.

Both closed requests carry `requestId`, `expectedRevision`, `materialId`, `quantity`, and
`expectedOwnedQuantity`; `SellMaterialRequest` additionally requires `expectedUnitGold`.
IDs are bounded nonempty strings. Numeric fields are finite safe whole integers, with positive
`quantity` and sale quote; the expected owned total may be zero. The server fixes operations as
`Inventory.SellMaterial` and `Inventory.DiscardMaterial` and binds each receipt to the Material ID,
quantity, expected owned total, and sale quote when present. Use the standard revision-bound request
ID and retry unchanged; neither a changed payload nor switching sale/discard may reuse a receipt.

Inside one transaction, validate the current schema and `InventoryCapacity.ValidateMaterialState`,
including active refund reservations. Resolve a launch-enabled normal Material with a supported
element and matching configured stack limit. Prototype and unknown IDs are not eligible for either
new command, but their retained entries remain unchanged. Compare the actual owned total with
`expectedOwnedQuantity` before checking affordability; `QuantityChanged`, `NotOwned`, or
`InsufficientMaterials` rejects instead of removing a different amount. Existing valid overflow is
not a rejection: these removals can recover capacity without releasing a job's reservations.

Sale resolves positive safe whole `sellGold` from metadata and checks `expectedUnitGold`, returning
`InvalidSaleDefinition` or `PriceChanged` when appropriate. Validate current Gold and both payout
multiplication and balance addition before mutation. The exact-integer ceiling is `2^53 - 1`, a
numeric-safety bound rather than a gameplay Gold cap; invalid currency or unsafe arithmetic returns
`InvalidCurrency`/`ArithmeticOverflow`. Discard neither validates nor modifies Gold and always grants
zero. Both subtract only owned Inventory quantity, retain extra fields on a partially consumed
entry, and remove its map entry when the remaining total is zero.
The shared `GoldCreditUtil` also reserves headroom for active canonical jobs' recorded paid Gold;
a sale cannot make a later exact cancellation refund overflow. Mythling sales use the same guard.

Removal, sale Gold, and the receipt commit together. Both success results contain `materialId`,
`quantity`, `remainingQuantity`, and `goldGranted`; sale adds `unitGold` and `goldBalance`. Receipt
replays return that original outcome without another removal/payment, while normal revisioned
State supplies the current authoritative inventory. A rejection rolls back gameplay changes,
though DataService may retain its decision receipt and revision.

The requested sale/discard leaves Shrine storage, unfinished work, XP, production clocks, purchased
upgrades, Shop stock, and unrelated state unchanged. It never spends a Crafting Job reservation;
registered preparation may resolve a due job in that same atomic transaction. No reserved refund
or uncollected output can be sold/discarded; collect online/offline output separately first.
The [Inventory endpoints](#inventory-request-endpoints) add admission and dispatch only, with no GUI,
schema migration, timer, or `SaveNow` call. Controlled transaction tests
establish in-session atomicity, not connected-player dispatch or live durable persistence.

### Atomic Equipment-sale command

Canonical `InventoryService.SellEquipment` requires a running service, connected Player, and
loaded profile. Private `EquipmentSaleCommand` accepts only `requestId`, `expectedRevision`,
`instanceId`, `expectedDefinitionId`, optional `expectedFinishId`, and `expectedGold`, then submits
`Inventory.SellEquipment` through `DataService.Transact`. The signature binds the exact instance,
definition, optional-finish identity, and safe-integer quote; display names and rarity are not keys.

Inside the transaction, validate the schema, owned entry, starter-grant flag, and saved loadout.
Reject either-slot equipment until explicitly unequipped, protect original starter instances even
when their metadata would permit a sale, and reject changed definition/finish or price selections.
Resolve eligibility and price through `EquipmentCatalog`; crafted/Featured copies have the same
configured value (initially 25 Gold). There is no per-copy price or rarity multiplier.

Remove exactly one owned instance and credit its fixed value through `GoldCreditUtil` in the same
draft. This preserves safe-integer headroom for active crafting refunds. Retained over-capacity
Inventory may sell down; reservations are never owned items and cannot be sold or released by a
sale. Return `instanceId`, `definitionId`, `finishId` when present, `goldGranted`, and `goldBalance`.
Replays return the original receipt; failed actions roll back gameplay edits, including any shared
due-job preparation. A rejected domain action may retain its normal decision receipt/revision.

The sale itself leaves loadout, Materials, Mythlings, Shrine work, jobs, and reservations unchanged
apart from the selected item/Gold; DataService preparation may resolve due crafting first. No
auto-unequip, discard action, GUI, model binding, or combat change is introduced here. Its admitted
[Inventory endpoint](#inventory-request-endpoints) delegates to this same command.
Tests establish transaction behavior, not live durable persistence or connected-player dispatch.

### Space recovery transactions

- **Shrine construction:** accept a Shrine definition ID, quoted Gold cost, revision, and stable
  request ID for the requesting player's loaded profile. Re-resolve configuration inside the
  transaction; reject a stale quote rather than charging a different amount. Validate current Gold
  and Shrine-only build capacity, then select the lowest-numbered free unlocked slot. Atomically
  spend the configured Gold and create one unique level-1 Shrine with its slot and result receipt.
  The client cannot choose an owner, instance ID, slot, or starting level. Duplicate elements are
  allowed, with no Material, Mythling, or existing-Shrine requirement. Retries replay the original
  result even after a configuration change; conflicting or stale requests cannot charge again.
  Logical slot IDs are stable across reconnects and independent of authored placement geometry.
- **Base expansion:** validate the configured build-slot upgrade, progression eligibility, and
  sufficient Gold plus every collected Material in its fixed elemental mix. Only owned spendable
  Inventory quantities count; Shrine output and crafting refund reservations cannot pay costs.
  Require the requested upgrade to be the next unpurchased expansion and current
  unlocked capacity to be below the configured six-slot MVP limit. Atomically spend all costs and
  persist the purchase, adding exactly one unlocked Shrine slot. Reject stale, repeated, or
  over-limit purchases without another charge or capacity grant. Derive unlocked capacity from
  the two starting slots and saved expansion purchases, independently of current Shrine occupancy;
  dismantling, reset, and reconnect cannot remove a purchased slot.
  Price changes do not revoke purchased slots or require a retroactive payment.
  Base build capacity counts constructed Shrines only; the permanent Crafting Station is outside
  that capacity. Shrine construction must validate available build space against the same count.
  The [atomic command](#atomic-base-expansion-command) implements this purchase through the admitted
  Base endpoint without new model placement or GUI.
- **Shrine upgrade:** validate ownership, the expected current level, the next configured level,
  and sufficient Gold and collected matching normal Material. Launch permits only level 1 to 2
  and level 2 to 3. Settle production under the old level, then atomically spend the costs and
  update the saved level; derive the added assignment slot and increased storage from metadata.
  Retain the Shrine instance, existing assignments, stored Materials, unfinished production, and
  earned XP. The added slot is empty; upgrades never assign a Mythling automatically. A stale,
  duplicate, unaffordable, or level-3 upgrade request cannot spend costs or advance the level again.
  Changing storage does not backfill time previously spent full. Use one level field and one
  upgrade operation, with no independent storage or worker-slot purchase state.
- **Shrine dismantling:** validate owner and the built Shrine's instance ID, settle accrued state,
  and require no assigned Mythlings or stored whole Materials. Atomically remove that Shrine record
  and free its build slot, then remove its runtime model. Discard its unfinished production progress;
  do not issue a refund or create a stored-building record. A stale or repeated request cannot
  remove a replacement structure or generate value. The permanent Crafting Station cannot be
  sold, dismantled, or replaced through a construction request.
- **Mythling sale:** validate the selected owned instance, sell eligibility, and that it is
  unassigned. Resolve the fixed Gold value from its current form metadata; XP level, inactive legacy Luck/Traits,
  and acquisition route do not modify the payout. Do not use the originally captured form, an
  inferred rarity/stage multiplier, or a client-supplied payout as authority. If the selected form
  or quoted price changed before commit, reject the sale and refresh its details. Atomically remove
  that owned instance, grant its Gold value, and record the result. Serialize with assignment and
  evolution; retries return the recorded result without another removal or payment. Selling the
  final copy is allowed. Do not persist a second sale-price field on owned Mythlings.
- **Material sale:** validate a positive finite whole quantity, enabled Material metadata, and enough
  owned Inventory quantity. Resolve the fixed unit Gold value from server configuration and compute
  the total; the client cannot set the price or payout. Atomically remove the requested quantity,
  grant Gold, and record the request result through the existing per-profile transaction path.
  Reject stale or insufficient quantities rather than selling a different amount. Duplicate requests
  return the recorded result without repeating the sale. Shrine storage and crafting refund
  reservations are not owned Inventory quantity; the sale cannot consume either or release a job's
  reservations. Offline output must be collected before sale, using the same path as online output.
- **Material discard:** validate ownership and a positive whole quantity, then atomically remove
  only the requested owned amount. Return the actual authoritative inventory state. Do not touch job
  receipts, refund reservations, Shrine storage, or Gold. Stale quantities are rejected rather than
  silently discarding a different amount.
- Collection, sales, discard, assignment, upgrades, and dismantling share the per-profile transaction path.
  UI confirmations do not replace server validation, and retries must not repeat completed mutations.
  The [Material commands](#atomic-material-sale-and-discard-commands) implement launch sale/discard
  without their player-facing confirmation or remote integration.

### Isolated Mythling-sale reducer

`ServerScriptService.Services.InventoryService.MythlingSales.Sell` implements detached sale
accounting over the shared `ShrineAccrual.State` plus the same profile's Gold balance. Inventory
owns the removal/payout rule; the server-shared accrual engine owns settlement. The accounting view
must include every owned worker and Shrine assignment, not a client-provided selection. Per-form
optional `sale = { gold }` metadata provides eligibility and a positive safe whole-Gold value;
absence means not sellable. The separate [launch form catalogue](#launch-mythling-form-catalogue)
supplies and validates the approved per-form prices across all six elements. This reducer's tests
use synthetic metadata; neither the reducer nor the catalogue prices or enables the legacy forms.

The strict request is `{ workerId, expectedFormId, expectedGoldValue }`. Validate accounting,
configuration, Gold, server-authored time, ownership, and current form. Reject an assigned worker
without automatic unassignment, even at full storage. Validate the selected sale definition, compare
the quoted price against its authoritative value, and check addition against safe-integer overflow
before calculating the new balance. No minimum-copy protection or rarity/level/acquisition modifier
applies. No copied sale value is added to an owned record.

Settle the whole ledger on its normal schedule, then remove only the selected worker and return
`production`, `gold`, `workerId`, `formId`, and `goldGranted`. Preserve Shrine output, unfinished work,
other workers' earned/pending XP, and the accounting clock. Any unresolved XP on the sold worker
retires with that owned instance; it is neither forced into an early award nor transferred to another
worker. The sale does not collect Materials, change reservations, or create a replacement instance.
Rejections return no staged result and leave inputs unchanged, including settlement failures.

The [sale command](#atomic-mythling-sale-command) derives both views from one authenticated loaded
profile, serializes with assignment/evolution, and commits the ledger, canonical owned-record
deletion, Gold, and revision-bound receipt together. It merges only the affected fields and retains
unrelated profile/acquisition/legacy state for every remaining instance. A second request against
the resulting state cannot pay again because the worker is no longer owned; the reducer itself has
no durable retry receipt, live command, persistence migration, or UI. The retained prototype
`DeleteMythling` endpoint now rejects every request without unassignment or deletion; it grants no
sale payout. The private legacy removal helper retains its canonical/pending-work protections.

## Crafting transactions

The GDD's [crafting rules](GDD.md#crafting) define one included permanent Station per Base, one active
Equipment job, offline completion, and exact cancellation refunds. Implement those promises through
one server-authoritative transaction path while the profile session is active.

- **Start:** validate that the recipe and result are enabled for the launch scope, then validate
  its unlocks, the player's permanent Station, idle status, affordability, and Inventory capacity.
  The Station itself has no purchase or unlock requirement.
  All launch sword and Shield recipes initially use a configured 60-second duration. Resolve the
  completion timestamp from the server start time and snapshot that deadline in the receipt.
  Resolve the result definition and optional finish from the selected recipe on the server. Finish
  recipes have fixed matching-Material inputs; reject conflicting client-supplied result/finish
  values and do not substitute another recipe or its inputs.
  Atomically deduct the actual costs, create the receipt, and reserve both promised Equipment output
  space and enough Material capacity to return the paid inputs. A rejected start changes none of
  those fields. Repeated requests cannot create duplicate jobs or charges.
- **Receipt:** record job/recipe/station IDs, result definition ID, optional finish ID, promised
  quantity, actual paid Material quantities and Gold, start/completion times, resolution status,
  and output/refund reservations. Paid costs are transaction history, not a copied recipe.
- **Capacity:** every acquisition must account for all outstanding reservations, including
  compatible Material stack space. Reservations are not owned items and cannot be spent, equipped,
  or sold. Restore them with the saved job before processing acquisitions on join.
- **Resolution:** compare the server time with the recorded completion time. A due job completes
  before a cancellation is considered; an unfinished cancelled job returns exactly its recorded paid
  costs. Output/refund grant, status transition, and reservation release are atomic. A
  completion/cancellation race or retry cannot grant both outcomes or grant either twice.
- **Delivery:** completion automatically grants the recorded result and finish into its reserved
  Equipment capacity and makes the station idle. There is no separate awaiting-claim job state.
  On join, restore receipts/reservations and resolve due jobs before accepting acquisitions or
  another job start.
- **Offline:** resolve due jobs on a server tick, profile join, or station interaction. A live timer
  is a convenience, not the source of truth for completion. Reservations remain valid while the
  player is offline and until the job resolves.
- **Metadata changes:** later recipe edits must not change existing receipt costs, output/finish, or
  completion time. Definition and capacity migrations must preserve existing promises and
  reservations; metadata changes cannot silently strand a job or make its refund impossible.
- **Bounded history:** retain enough resolution/request information for duplicate-safe behavior
  without letting completed/cancelled job records grow without a bound in player saves.

Waiting queues, station levels, additional stations, and Consumable recipes are future additions.
Their migrations must extend these guarantees while preserving existing prototype player data.

### Headless crafting implementation

`CraftingService.StartJob` and `CancelJob` require a running service, connected Player,
and already-loaded profile. Private `CraftingCommands` validates closed envelopes and dispatches
`Crafting.Start`/`Crafting.Cancel` through `DataService.Transact`; it samples no independent clock.
Both requests contain the usual `requestId` and `expectedRevision`. Start additionally contains
`stationInstanceId`, `recipeId`, `expectedGoldCost`, `expectedMaterialId`,
`expectedMaterialQuantity`, `expectedDefinitionId`, `expectedFinishId`, `expectedQuantity`, and
`expectedDurationSeconds`; cancellation contains only `jobId`. Signatures bind all quoted fields,
using length-delimited IDs and exact safe-integer numeric formatting. Retry the original request
unchanged. Unknown fields, invalid IDs, and invalid numeric selections are rejected before admission.

`CraftingJobs.new` supplies pure `SettleDueToDraft`, `StartToDraft`, and `CancelToDraft` transitions.
They validate canonical receipt structure and current schema, rejecting multiple active canonical
receipts while preserving opaque legacy collections. New starts allow no other active job.
Start verifies the permanent Station, current recipe/result pair, exact quote, actual collected
inputs/Gold, valid purchased capacity, and output/refund capacity before allocating identities or
paying. Equipped items and protected starters count. Ingredients and retained refund reservations
must fit the pre-start Material bag; output quantity must fit unreserved Equipment capacity.
No Shrine output or reservation pays a recipe. Result IDs are generated and collision-checked at
start, not at completion. Launch recipes grant one item; the recorded result supports a positive
quantity with one unique instance ID per promised copy.

New `craftingJobs[jobId]` records retain `status` and `reservations` and add `receipt` containing:

- `version = 1`, `recipeId`, `stationId`, and `craftingStationId`;
- server `startedAt`/`completesAt`, plus `resolvedAt` after resolution;
- `result = { definitionId, finishId, quantity, instanceIds }`;
- `paid = { gold, materials }`, recording actual transaction costs rather than copied recipe metadata.

Active reservations equal the promised Equipment count and paid Material quantities. Completion
grants only the recorded identities and definition/finish, marks Completed, and releases both
reservations. It does not reread the recipe, require new free capacity, or equip the output.
Unfinished cancellation marks Cancelled, releases its claim, and returns the exact recorded costs
in the same draft. Material entry extras survive partial changes. `GoldCreditUtil` preserves
`current Gold + active paid-Gold refunds <= 2^53 - 1` for credits; cancelling releases its own claim
before crediting it, while retaining all other claims. This is a numeric-safety guarantee, not a
new gameplay currency cap. Metadata/capacity changes cannot silently replace existing promises.

Start returns `jobId`, Active `status`, `completesAt`, `resultDefinitionId`, `resultFinishId`,
`quantity`, `stationInstanceId`, and `goldSpent`. Cancel returns `jobId`, terminal `status`, and
`goldRefunded`. At/after the deadline it succeeds as Completed with zero refund; a new request for
an already-resolved retained job returns its status with zero further refund. An exact receipt
replay returns its original outcome, not a fresh grant.

Crafting registers the same pure due resolver for mutation preparation and Ready/Checkpoint/Release.
Preparation and the feature share one timestamp and rollback boundary; an unrelated rejected action
therefore also rolls back staged due delivery. A later scheduler/checkpoint can resolve it normally.
The configurable one-second `DueJobs` scheduler requests `DataService.Update("Crafting.Resolve")`
only for loaded profiles with due versioned jobs; its preliminary clock is only a scheduling hint.
The transaction timestamp and recorded deadline decide completion. Ready resolves before profile
publication, and Release resolves before final session save handling. Pure callbacks remain valid
after CraftingService stops. These are session-atomic guarantees, not durable-save acknowledgements.

`Configurations.Crafting` owns receipt version, scheduler cadence, and the 32-record resolved-history
bound. Pruning orders canonical resolved records by time then ID while protecting the just-resolved
record in that pass, so due cancellation can still report completion. Nil-receipt legacy records,
including multiple active prototype jobs, are preserved without inventing costs/results/deadlines.
They do not by their count prevent profile admission or a canonical due completion. Active legacy
jobs retain their reservations and block a new start, cancellation returns `UnsupportedLegacyJob`,
and automatic resolution skips them.
Malformed versioned receipts fail closed. Opaque legacy history is not pruned as canonical history.

The pure job layer adds no GUI, Station prompt, asset binding, auto-equip, or crafted-combat runtime.
Its admitted transport and world-access boundary are described below.
Saved receipts remain private. Existing prototype Base `MarkDirty` writes still bypass
transaction preparation; replace those writers separately rather than claiming global rollback.
Verify actual session/shutdown and durable retention independently of mocked/serialized tests.

### Crafting Station read view

`CraftingService.GetStation(player, request)` shares the running-service and genuine
connected-Player gate with crafting mutations. `request` is the closed
`{ stationInstanceId }` selection, with one nonempty ID of at most 128 bytes. Private
`CraftingCommands.GetStation` reads only an already-loaded profile, validates its transaction
revision, and samples `Workspace:GetServerTimeNow()` once, in the same fractional-epoch clock
domain as crafting transactions. It returns `{ ok, code?, revision, view? }`; unavailable
profiles return `DataUnavailable` with revision zero, malformed revisions return
`InvalidTransaction` with revision -1, and no failure returns a partial view.

`CraftingJobs.ReadStation` reuses receipt, Base, Inventory, currency, recipe, and capacity validation.
The nonmutating pre-allocation checks are shared with Start, which still settles due work before
checking fresh-start eligibility. Reads never call Start, settlement, ID generation, history
pruning, `Transact`, `Update`, or saving. A view reports current confirmed state rather than
simulating a grant or changing a job's promise.

The detached view contains `sampledAt`, `stationInstanceId`, `craftingStationId`, `busy`, optional
`blockingCode`, recipe rows sorted by `recipeId`, and an optional `activeJob`:

- Recipe rows contain `recipeId`, `goldCost`, `materialId`, `materialQuantity`,
  `resultDefinitionId`, `resultFinishId`, `quantity`, `durationSeconds`, `canStart`, and optional
  `startCode`. These quotes map to Start's expected fields; the server still revalidates mutations.
- A canonical active job contains its `jobId`, `recipeId`, `stationInstanceId`, Active `status`,
  recorded `startedAt`/`completesAt`, `remainingSeconds`, `completionPending`, result definition/finish
  IDs and quantity, `canCancel`, `cancelRefundGold`, and copied `cancelRefundMaterials`.
- Before the deadline, refund fields use actual recorded payment, never current recipe prices.
  At/after the deadline, the job remains busy until settlement, with zero remaining time,
  `completionPending = true`, `canCancel = false`, zero refund Gold, and an empty refund-Material map.
  No awaiting-claim or prematurely idle state is invented.
- Nil or resolved-only job collections are idle. Active opaque legacy records are busy with
  `UnsupportedLegacyJob` and no fabricated legacy-job summary. If a valid canonical active receipt
  coexists with retained legacy jobs, its summary remains visible while legacy work still blocks
  new starts. Invalid canonical receipts, multiple
  canonical active jobs, and active receipts bound to a different permanent Station fail closed.

Current recipe metadata supplies new quotes only. Existing jobs retain their recorded result,
payment, and deadline even when their former recipe is edited or removed. Shared/static tables and
saved tables never escape by reference; raw receipts, versions, promised output instance IDs,
reservations, private transaction history, stage fields, and unrecognized saved extras are omitted.
The projection itself adds no prompt or GUI. Its transport and world-access checks follow below.

### Crafting request endpoints and world access

`Network.Crafting.GetStation`, `StartJob`, and `CancelJob` are Rojo-declared RemoteFunctions using
the corresponding public CraftingService envelopes and results without extra snapshots. Private
`CraftingRequests` admits a genuine connected Player and running service, then one shared token
bucket, before profile, clock, or world work. `Configurations.CraftingRequests` initially allows
a burst of twelve and refills four tokens per second. Denials return a small `DataUnavailable` or
`RateLimited` result with revision zero. Inputs are forwarded unchanged; command parsing remains
the closed-envelope boundary. Stop clears all three handlers and buckets, and PlayerRemoving
forgets the departing player's bucket. Retained callbacks reject after Stop.

Production initialization requires `BaseService.CheckCraftingAccess`; private headless command
tests may omit this injected dependency. BaseService owns the world lookup and accepts the current
transaction draft's saved Base, not a client Instance, position, owner attribute, or menu flag.
Its private `CraftingAccess` resolves the caller's unique server-owned slot, a live Base under the
configured Bases folder in Workspace, and the saved permanent Station's configured model. It
requires the exact unique-child `interactionAnchorPath`, ending in an Attachment parented to a
BasePart. The initial authored contract is
`PB_CraftingStation_Root/PB_CraftingStation/PB_CraftingStation_Mesh/CraftingPromptAttachment`.
No light attachment, model pivot, bounding box, or another player's Station is a fallback.
Missing, ambiguous, or detached bindings return `StationUnavailable`; a changed selected Station
returns `StationChanged`. Presentation OwnerId/Station attributes do not grant authority.

The current character must be in Workspace with a living Humanoid and its own HumanoidRootPart.
Its finite three-dimensional distance to the configured anchor must be at most
`interactionDistanceStuds` (initially four). Unavailable characters return `CharacterUnavailable`
and outside/nonfinite positions return `OutOfRange`. These checks do not trust the client movement
lock, create a menu session token, or mutate character movement. The separate GUI work owns the
[approved menu movement lock](UI_GUIDELINES.md#accessibility-and-feedback).

GetStation checks access after profile/revision/payload validation and before its clock/projection.
Start and Cancel check access only inside the fresh transaction callback after receipt/revision
admission. Start uses the selected Station ID; Cancel resolves the saved permanent Station without
adding a payload field or changing existing signatures. Exact committed retries return their
original result even after displacement, reset, or Station/job removal. Fresh denied actions roll
back shared preparation with the command; automatic completion, Ready/Checkpoint/Release, and
the independent due scheduler never require proximity or an open menu.

This implements backend endpoints, not menu controls or an authored prompt. The inspected Station
template lacked the configured anchor; the user reserved placement for the separate asset/UI work.
Placement and connected-player interaction must be verified
before claiming playable crafting. Missing anchor data fails closed without preventing automatic
completion of an already-started job.

## Shop transactions

Implement the GDD's [Shop](GDD.md#shop) through the existing server-authoritative, per-profile
transaction path. The launch catalogue contains all six normal Materials, rotating first-crafted
Equipment, and eligible Inventory upgrades; purchases do not require the corresponding Shrine.
Initialize configurable schedule, stock, and pricing from the GDD's [Shop tuning](GDD.md#shop).
The initial refresh interval is one hour (60 minutes), shared by Materials and Featured. Featured
offers one matching sword and Shield pair per period, rotating Fire → Water → Earth → Air → Light
→ Dark → repeat over six hours. Clients display the server's schedule rather than hard-coding it.
Exhausted allowances remain unavailable until their scheduled restock.

- **Refresh authority:** use server time and one configured schedule to identify the current
  refresh period and its Featured selection consistently across servers. Resolve the fixed rotation
  from a shared configured epoch and period index, not from server start or player join. Opening the Shop,
  reconnecting, server hopping, and character reset do not reroll offers or restore stock. Period
  definitions and prices are stable within their window; publish changes at a scheduled boundary
  without granting an extra restock. Do not accept client time or a server-local random assortment
  as the authority. Unavailable current catalogue data blocks purchases until it can be resolved.
- **Personal stock:** save the current period ID and purchased quantities by stable stock key.
  Material stock keys identify the normal Material; Featured keys identify the configured offer.
  Derive remaining quantities from configured limits minus saved usage. When entering a newer
  period, replace previous usage with the new period's usage; do not accumulate missed allowances.
  A catalogue revision must not reset usage within a period. Inventory-upgrade ownership is separate
  and is never cleared by restocking. Persist stock usage with the same active profile session as Gold.
- **View:** return a client-safe snapshot with period/offer revision, exact item references, Gold
  prices, personal remaining stock, eligibility, and next refresh time. Material offers reference
  the Material's configured unit buy price; Featured offers own their premium Equipment price.
  Inventory upgrades include their configured Gold cost, fixed Material IDs/quantities, owned
  spendable amounts, and eligibility. The view reserves no stock, Gold, Materials, or Inventory space.
- **Purchase:** for Materials and Featured, validate a bounded request ID, current period and offer
  revision, offer ID, positive finite whole quantity, launch eligibility, remaining personal stock,
  affordability, and capacity.
  Resolve item/variant and price on the server; never accept a client-selected result or price.
  Use the shared Inventory calculation, including active crafting output/refund reservations.
  Atomically deduct the exact Gold cost, grant the exact owned quantity, increment stock usage,
  and record the result. Reject the entire request if anything is unavailable; do not silently
  reduce quantity, substitute an item, or release a Crafting Job's reservations.
- **Delivery:** purchased Materials enter ordinary Inventory stacks. Each purchased Equipment copy
  gets a unique owned instance with the offer's definition/finish IDs and normal fixed rarity;
  `isStarterGrant` is false. Delivery is immediate, uses one Equipment slot per copy, creates no
  Crafting Job, does not auto-equip, and awards no Shrine-work XP.
- **Inventory upgrades:** validate exactly one requested next upgrade, expected current level,
  eligibility, configured Gold cost, and every owned Material quantity in its fixed elemental mix;
  reject a requested quantity other than one, a skipped upgrade, or a purchase after that category's
  second upgrade. Each purchase adds 12 slots to its category only; track progression independently
  for Materials, Mythlings, and Equipment. Resolve the exact recipe on the server; do not accept
  substituted elements or silently change a quoted cost. Atomically spend Gold and collected
  Materials, grant the upgrade, and record the result. Protect crafting refund reservations.
  These purchases require no available item slot or stock period and consume no Shop restock
  allowance. A full Inventory can still upgrade when it already owns all required costs; those
  ingredients must fit before the upgrade. Preserve purchased capacity through later price changes
  without retroactive charges. The [server-only capacity command](#atomic-inventory-capacity-upgrade-command)
  implements the purchase independently of the remaining Shop view/endpoint work.
- **Races and retries:** serialize purchases with sales, crafting, and other profile mutations.
  For stock-limited offers, check the period at transaction commit, including requests arriving
  near refresh. An uncommitted expired offer is rejected with an updated view, never replaced by the
  new period's offer. A
  previously committed retry returns its recorded result without another grant or charge, including
  after refresh; do not erase its receipt merely because stock has restocked. Keep receipt history
  bounded under the existing duplicate-safe mutation rules and reject expired unresolved requests.

### Headless Shop implementation

Server-only `ShopService.GetShop(player)` and `BuyOffer(player, request)` require a running service,
a connected Player, and an already-loaded profile. `Init` validates the complete launch catalogue;
there is no refresh task, lifecycle stock mutation, or GUI binding. The transport endpoints below
delegate to these same public service methods. Private `ShopCatalog`
derives one period and eight offers from `Configurations/Shop`: six Materials and one Featured pair.
The launch epoch is Unix zero, with 3,600-second periods; period zero is Fire and the rotation is
Fire → Water → Earth → Air → Light → Dark. Material prices come from their owning definitions;
Featured references name the exact definition, finish, and matching recipe. Startup validation checks
launch references, stock, and resale economics. Empty crafted model bindings remain unchanged.

`GetShop` returns `{ ok, code?, revision, view? }`. The view includes `sampledAt`, `periodId`,
`startsAt`, `refreshAt`, `featuredElement`, `offers`, and `upgrades`. Each offer exposes `offerId`,
`offerRevision`, `stockKey`, `kind`, exact Material or Equipment references, `unitGold`, `stockLimit`,
`remainingStock`, `maxPurchasable`, and optional `purchaseCode`. Exhausted Materials remain listed.
These quotes reserve nothing and expose no raw save, private job receipt, or mutation history.
`ShopUpgrades` derives the current/maximum/next capacity, cost, owned spendable inputs, and eligibility
for each category using the existing payment rules on detached payment fields. Maximum capacity has
no further quote. `InventoryService.UpgradeCapacity` remains the only upgrade mutation owner.

Buy accepts only `requestId`, `expectedRevision`, `periodId`, `offerId`, `offerRevision`, and
`quantity`. IDs/revisions are bounded, quantities are positive safe whole numbers, and signatures
bind the exact envelope. The period and offer are resolved inside `DataService.Transact` using its
single admitted callback timestamp after shared mutation preparation. The lossless offer revision
binds category, stock key, exact result IDs, price, and stock limit; it is not saved in stock state.
An expired period or changed offer rejects without silently substituting a new item. Committed
receipt retries skip current catalogue validation and return the recorded result even after refresh.
Existing bounded receipt/revision rules govern stale requests after receipt eviction.

Success values include `offerId`, `offerRevision`, `periodId`, `quantity`, `unitGold`, `goldSpent`,
`goldBalance`, and `remainingStock`, plus `materialId` or `instanceId`/`definitionId`/`finishId`.
Headless rejection returns its code; the remote adapter pairs expired/changed-offer rejection
with a fresh `GetShop` result rather than embedding mutable catalogue data in the persisted receipt.

The optional saved shape is `shop = { periodId, purchased = { [stockKey] = quantity } }`. Absence
means no purchases yet. Stable keys are the Material IDs and `featured_sword`/`featured_shield`, not
variant IDs or catalogue revisions. `ShopStock.Read` returns detached effective usage: same-period
valid unknown keys and over-limit historical counts survive; a newer period has an empty virtual
allowance ledger. Only a successful purchase installs that newer period. A saved future period
rejects with `ShopClockBehind`; partial, malformed, or unknown-root records reject with
`InvalidShopState` rather than being repaired or discarded. No schema/store/template reset is added.

Buy validates exact stock, Gold, safe arithmetic, and unreserved category capacity before delivery.
Materials enter ordinary owned stacks. Featured grants one ordinary instance with exact definition
and finish, `isStarterGrant = false`, and a unique ID that cannot collide with owned Equipment or
retained crafting promises. It creates no job, XP, or automatic loadout change. Failed purchases roll
back both the purchase and any due-job preparation; receipts still follow normal rejection rules.
Inventory upgrades, unrelated ownership, Shrine work, and retained reservations remain independent
of stock rollover. Success is session-atomic, not a durable-save acknowledgement.

Offer revisions prevent accepting a different quote but do not synchronize rolling deployments by
themselves. Keep catalogue values stable within a window and publish future tuning at an agreed
shared boundary; changing a revision is never grounds for another allowance. Hot-reloaded catalogue
distribution is not introduced by this launch implementation.

### Shop request endpoints

Rojo declares `Network.Shop.GetShop` and `BuyOffer` as RemoteFunctions; `RemoteUtil.Resolve` validates
their classes without creating instances. `ShopService.Start` binds both handlers and owns their
cleanup. They accept only the engine-supplied calling Player; payloads cannot choose another account.
Shop access has no character-alive, Arena, Base-ownership, or proximity prerequisite. The permanent
Station and Shrine interaction rules do not apply to this globally available Shop.

Private `ShopRequests` rejects unavailable callers before rate admission, then spends one token from
the shared per-player Shop request budget before any profile read, view construction, or mutation.
`Configurations.ShopRequests` initially permits a burst of six requests and refills two per second.
Rejected requests return small `DataUnavailable`/`RateLimited` results with revision zero and no view.
The adapter neither loads profiles nor adds settlement, saving, or direct profile writes. Player
departure forgets the bucket; stopping clears handlers and all buckets. Retained callbacks reject
after shutdown before doing protected work.

`GetShop:InvokeServer()` returns `ShopViewResult`. `BuyOffer:InvokeServer(request)` returns
`BuyShopOfferResult = { transaction, shop? }`, where `transaction` is the original canonical
`TransactionResult`. Buy forwards the closed envelope described above to the existing command parser;
it does not accept prices, result IDs, player IDs, time, or arbitrary state mutations. It never
pre-rejects a stale period before transaction receipt lookup. Only unsuccessful `OfferExpired` or
`OfferChanged` responses add a fresh `ShopViewResult` under `shop`. That refresh is covered by the
already-admitted request and is separate from the recorded result, including when refreshing the
view itself fails. Replayed expired/changed rejections also receive current quotes; successful
replays and responses with other codes construct no extra view. No response rewrites a receipt.

The Shop view's `revision` is the persistent transaction revision used as `expectedRevision` on
purchases. It is not the State channel's packet sequence; projected `transactionRevision` is the
corresponding value. State updates confirm owned balances/items. No raw profile, purchase ledger,
crafting receipt, or transaction history is exposed. Inventory upgrade quotes remain read-only here;
`InventoryService.UpgradeCapacity` retains its separate mutation contract. GUI bindings, real-client
transport checks, and durable-save validation remain separate work.

## Content configuration

Content and balance data must be separate from game logic and versioned. At minimum, configuration
defines:

- Mythling: `id`, display name, element, fixed form rarity, `evolutionStage` (1, 2, or 3 for the
  launch roster, internal metadata only), visual assets, form-specific base Yield, shared acquisition
  and progression settings, one optional evolution target and its required level, lore, an optional
  spawn lifetime override, sell eligibility, and a fixed Gold sell value for that named form.
  XP level, inactive legacy Luck/Traits, and acquisition route do not
  modify the sell value; evolution resolves the new current form's value. Stage describes the
  form's position in its chain, not its level or rarity. Resolve rarity directly from each form;
  do not derive it from stage or roll an owned rarity variant.
  Initialize all six Common forms at 12 Materials/hour, all six Rare forms at 18/hour, and all six
  Epic forms at 32/hour before level scaling. Keep these trial values configurable and validate
  increasing base Yield within each chain.
- Mythling progression: shared configurable `yieldGainPerLevel = 0.01`, level cap 100, and next-level
  XP coefficient 120. All launch forms use the same curves above; level 1 has no Yield bonus.
  Launch evolution links initially require levels 6 and 40, with no additional time-in-form gate.
- Production: fixed batch interval and one shared Shrine-work `baseXpPerSecond`, initially 1.
  XP earning rates belong to activity configuration, not Mythling definitions. Add rates for other activities only
  when those activities are approved.
- Mythling acquisition: starting level 1 and 0 XP for every new capture, independent of captured
  stage, rarity, or element. Keep these defaults in shared configuration and validate the launch
  values; clients cannot supply starting progression. No Luck range, Trait pool, or acquisition
  roll is required for launch. Retained legacy Luck/Trait data remains inactive and must not make
  those definitions, effects, or APIs launch dependencies.
- Shrine: element, output Material, levels 1/2/3 with 1/2/3 assignment slots and increasing shared
  storage capacities initially 300/1,200/3,600, Gold-only level-1 build
  cost, and Gold/matching normal Material upgrade costs. All six elements use the same level
  structure. No Shrine production multiplier
  is needed for the MVP; validate the three-level limit, slot counts, increasing storage, and
  matching-Material costs before enabling construction or upgrades.
- Base: two initial build slots usable only by Shrines, four sequential Gold-and-Material expansions that
  permanently grant one slot each, and a maximum of six unlocked slots for the MVP. Keep these
  values, Gold costs, and fixed mixes of multiple normal Material IDs/quantities in configuration.
  The included permanent Crafting Station uses no build slot.
- Crafting Station: default definition, Base placement, and eligible Equipment recipe groups.
  Launch includes one permanent Station per Base with one active job; no build price or Station
  unlock requirement is configured.
- Material: id, element, display information, crafting uses, sell eligibility, fixed unit Gold
  sell and buy prices, stack limit, and optional rare variant. All six normal launch Materials are
  sellable and listed for purchase, with an initial stack limit of 1,000 each. Material metadata owns
  their unit prices; Shop offers reference
  these values without a second price override. Prices are static tuning, not market prices or
  saved per-player values; tune sales as supplementary Gold under the GDD economy rules.
- Arena spawn: eligible stationary Mythlings, rarity-weighted selection pool, valid positions/ring
  spacing, ring vertical membership allowance accommodating normal jumps, capturable-population
  target initially 12 for every server population, maximum refill delay initially three seconds,
  default spawn lifetimes keyed by rarity, references to named-form lifetime overrides, and per-Mythling
  `captureProgressPerSecond` and `captureDecayPerSecond`.
  The deployed server player limit must match the eight-player launch rule.
  Initial rarity probabilities are 75% Common, 20% Rare, and 5% Epic, with equal element weights
  within each group. Initialize per-form rates for 20/35/60-second captures respectively, with
  decay equal to capture growth. Spawn lifetimes remain separate from capture durations: resolve
  the form override first, then the rarity default. Set Common, Rare, and Epic lifetime defaults
  to 240 seconds for the first trial, with no overrides on the 18 launch forms. Retain optional
  named-form override support for future content; do not use capture duration as a lifetime default.
- Equipment: id, category, visuals, knockback/protection behavior, cooldown, weapon Stamina cost or
  Shield impact cost and minimum guard Stamina, Primary Weapon `handsRequired` (`1` for launch
  swords; `2` is reserved for future two-handed archetypes), sell eligibility/value, internal stage,
  Equipment type, and supported element variants. Each Stage 1 base
  Equipment definition owns the type's shared model and base gameplay values. Its variant metadata
  defines an ID, element, full item display name, fixed rarity, recolor, and, for swords, an approved
  elemental effect reference. All six swords retain the wooden sword's base statistics, timing,
  costs, reach, and contact geometry; effects are their only gameplay difference. Shield variants
  share the crafted Shield's values and have no elemental effect. Use the GDD's named pairs:
  Fire/Vulcan, Water/Triton, Earth/Atlas, Air/Aura, Light/Sol, and Dark/Nyx, each with Sword and Shield.
  These are element-variant names, not shared progression-stage identifiers.
  Equipment rarity is fixed static metadata for each named item, independent of stage. Resolve it
  from the named variant selected by `definitionId` and `finishId`, or from the base definition for
  plain items. Display names are presentation, not lookup keys. Every copy resolves the same rarity;
  do not roll rarity, accept a client-supplied rarity, or add an owned rarity field. Equipment uses
  the GDD's shared Common/Rare/Epic/Legendary/Mythical vocabulary as quality categories. Resolve gameplay
  values, recipe costs, and sell values from their owning definitions without a separate rarity
  multiplier. Preserve existing player data when aligning the implementation. Rarity must not bypass
  the shared base statistics or add another effect multiplier across element variants.
  When two-handed archetypes arrive in a future update, their configured knockback implements the
  GDD's [stronger-force tradeoff](GDD.md#equipment-compatibility) at the same Equipment stage. Handedness
  does not itself multiply attack Stamina cost, cooldown, or the defending Shield's impact cost,
  bypass eligible protection, or force a guard break; resolve those values from their owning
  definitions under the existing combat rules.
- Player combat: maximum Stamina, regeneration rate, immunity duration, swing/guard transition
  timing and fallbacks, configured spawn Stamina, and bounded validation tolerances.
  Initially set maximum/spawn Stamina to 100 and lowered-state recovery to 10 per second. Equipment
  definitions own the initial 20-Stamina sword cost, one-second start-to-start sword cooldown,
  wooden Shield cost/minimum of 30, and crafted Shield cost/minimum of 25. Variant metadata and
  acquisition routes cannot override these shared base gameplay values. Configured elemental effects
  are applied through the accepted-hit contract, not by changing an item's base Stamina cost.
- Elemental sword effect: stable ID, role, magnitude, duration, and applicable landing/recovery
  timings. Initialize Fire/Water/Earth/Air/Light/Dark from the GDD's
  [initial effect tuning](GDD.md#initial-elemental-effect-tuning). Only the six approved roles are
  launch-enabled. The timed-negative-effect limit and immediate Air/Dark behavior follow the
  [effect contract](#elemental-sword-effects). Store no effect definition or active timer in owned
  Equipment or player saves; presentation text and visuals reference the same effect metadata.
- Recipe: input Materials and Gold, result Equipment definition, optional result finish ID,
  quantity, duration, eligible Crafting Station, and unlocks. Each Stage 1 variant has a fixed
  recipe; its Material input comes from the matching element's normal Shrine output. The UI groups
  these recipes by base Equipment definition rather than requiring six separate catalogue entries.
  Initial duration is 60 seconds for every launch sword/Shield variant; active jobs retain the
  deadline recorded at start when configuration changes.
- Inventory upgrade: tab affected, slot increase, Gold cost, fixed mix of multiple normal Material
  IDs/quantities, eligibility, and prerequisite upgrade. Configure two sequential +12-slot upgrades for each
  launch category, independently purchased. Initial limits are Materials 12 → 24 → 36,
  Mythlings 24 → 36 → 48, and Equipment 12 → 24 → 36. Each category's first upgrade costs
  20,000 Gold plus 50 of each of the six normal Materials; its final upgrade costs 300,000 Gold
  plus 200 of each. Players cannot select alternative payment Materials.
- Shop: shared refresh schedule, stable period/offer revisions, all six normal Material references
  and personal quantity limits, and the Featured rotation with offer IDs, Equipment definition/finish
  references, premium Gold prices, and personal quantity limits. Inventory upgrades reference their
  existing definitions and do not participate in stock refresh. Static offers, limits, and schedules
  belong here, not in player saves; Material unit prices remain owned by Material metadata. Start
  with a 3,600-second shared period and the GDD's fixed six-element matching-pair rotation.
- New-player defaults: starting Gold, Inventory capacities, starter Equipment definition IDs, and
  initial Base/unlock state, including the permanent Crafting Station definition.

Initialize the owning configuration modules from the GDD's
[initial economy tuning](GDD.md#initial-economy-tuning). Keep new-player Gold, Mythling and Material
sell values, Shrine costs, recipe inputs, and Shop offers consistent with that budget. Starting Gold
is a once-only new-profile grant; do not overwrite existing balances on reconnect or migration.
Price changes apply through their existing metadata/refresh rules and cannot rewrite active Crafting
Job receipts or repeat a completed transaction. UI reads confirmed configured values without its own
hard-coded price table.

Mythling `evolutionStage` and Equipment stage describe internal progression positions for content
organization and validation. Do not generate player-facing labels, filters, or item/form name suffixes
from these fields. UI resolves actual display names, rarity, and statistics; evolution previews use
the configured next-form reference. Mythling XP levels and Shrine levels remain visible under the
[UI Guidelines](UI_GUIDELINES.md).

Validate configuration references and launch invariants before enabling their systems: starter
Equipment capacity must hold both protected items plus the first recipe's output (at least three
slots for a one-item recipe), guard thresholds must be affordable at maximum Stamina, evolution
targets must retain the element and form an acyclic progression, and enabled recipes, structures,
and spawn pools must resolve to valid launch definitions. Numeric values remain configurable;
invalid metadata must not create an unfinishable job or an invalid grant.

Validate the GDD's [launch Mythling roster](GDD.md#launch-mythling-roster) as an MVP catalogue
constraint: six chains, exactly one per element, with three distinct form IDs at stages 1/2/3.
Each Stage 1 target is that element's Stage 2 form; each Stage 2 target is its Stage 3 form; Stage 3
has no target. Reject branching, skipped stages, cross-element links, and incomplete enabled launch
chains. This catalogue's rarity mapping is Stage 1/Common, Stage 2/Rare, and Stage 3/Epic; it is not
a generic evolution rule. Every form is eligible for wild spawning. Initial aggregate probabilities
are 75% Common, 20% Rare, and 5% Epic, with equal chances for the six elements within each rarity;
keep these weights configurable. Validate normalized group probabilities and uniform within-group
selection for both initial fill and replacements, not exact population counts in a small sample.
All six forms within each launch rarity initially share the 20/35/60-second capture durations
respectively and equal progress/decay rates. Validate positive finite rates, consistent meter units,
and a positive finite resolved spawn lifetime that permits each form's uninterrupted capture
without requiring overtime. Require a valid default for every enabled rarity, reject invalid
configured overrides rather than silently falling back, and validate arrival time on the actual map.
For the initial trial, validate all 18 launch forms resolve to 240 seconds from their rarity
defaults without per-form overrides. Capture times remain 20/35/60 seconds; a shared lifetime
does not make capture progress rates equal. Later configuration changes affect new spawns only,
preserving active contests' recorded deadlines.
The roster does not require every form to be present simultaneously. Legendary and Mythical content
must not enter the launch spawn pool. Retain legacy owned form references when introducing the
approved launch roster.

Validate positive whole-Gold sell values for the launch forms: one equal value across all six
Common forms, one higher equal value across the six Rare forms, and one higher equal value across
the six Epic forms. These are configured catalogue values, not runtime rarity multipliers. Preserve
existing owned levels and inactive legacy Luck/Trait data; sale valuation does not rewrite progression. Resolve any
retained legacy forms through their metadata without enabling them as new launch acquisitions.

Evolution logic follows the current form's optional target and required level. Absence of a target
means no further evolution; do not infer this from rarity or a hard-coded Stage 3 check. The target
form supplies its own rarity, which may retain or change the previous rarity. This metadata model
also supports standalone Mythlings without evolution chains and shorter, two-form chains when
those future updates ship. They are excluded from the launch catalogue; a terminal form within one
of the six complete launch chains remains valid even though it has no next-evolution target.
Evolution is a requested player action, never an automatic consequence of offline accrual. Settle
due XP before checking its required level, preserve level/XP through the form change, and resolve
the new form's next link afterward. A sufficiently leveled Common can evolve twice through two
valid sequential actions; do not reset XP or add a training requirement after the first action.

Validate increasing base Yield through each launch chain. New launch captures receive no Luck or
Trait roll, and no retained legacy value modifies launch behavior. Evolution preserves any existing
legacy values without activating them. Resolve rarity from current form metadata, without a
separate owned rarity roll or production/XP multiplier. Production is determined by assigned forms,
levels, eligible working time, and Shrine storage, equally online and offline.

On a new capture grant, retain the captured form's metadata ID and initialize `level = 1`, `xp = 0`,
and no pending earned XP. Do not derive starting level from that form's evolution threshold.
Use these defaults only when creating the newly awarded owned instance; repeated award requests,
reconnect, character reset, evolution, and migrations must not reinitialize existing progression.
Captured launch Stage 2 forms use their own next-evolution requirement, while launch Stage 3 forms continue
earning levels under the normal cap without another evolution target.

Validate that enabled launch Equipment is limited to plain wooden gear and Stage 1 swords and
Shields. Enabled launch recipes produce Stage 1 sword or Shield variants. New crafting, Shop offers,
and rewards must not introduce Stage 2 or later Equipment or depend on Equipment upgrades. Apply
these acquisition restrictions to new requests; preserve existing owned Equipment records and
resolve recorded Crafting Jobs under their original receipts.

Each Stage 1 Equipment type must have all six supported element variants and matching fixed recipes.
Recipe results must reference a finish supported by that Equipment definition; all Stage 1 variants
resolve that type's same base gameplay values. Each sword variant references exactly its approved
elemental effect, while wooden starter gear and all Shields have none. Validate effect magnitudes
and durations against the GDD's starting values, finite positive timing parameters, matching
elements, first-effect-wins behavior, and Dark's unsustainable full-rate attack budget. Crafted and
Featured copies resolve identical effects. Each enabled named item or variant must resolve one
valid configured rarity: Common for the wooden starter definitions and Rare for all six first-crafted
variants of each launch Equipment type. Epic, Legendary, and Mythical Equipment are excluded from new
launch acquisitions; preserve existing owned records. These are catalogue assignments, not a generic
stage-to-rarity formula. Crafting grants take the named item from the recipe's result references;
there is no separate rarity selection or roll. Existing plain Equipment and legacy recipes may omit
the finish ID for compatibility; this does not enable additional plain recipes for launch.

Validate Shop offers against the same launch catalogue: all six normal Materials remain listed and
every Featured item is an existing craftable Stage 1 sword or Shield variant with its fixed recipe.
Validate a positive refresh interval, coherent period/offer references, and positive finite whole
stock quantities and Gold prices. Each Material's unit buy price must exceed its unit sell price.
For every enabled Equipment recipe, total output resale value must be below the cost of buying its
Material inputs plus its Gold cost. Each Featured price must exceed that purchased-input crafting
cost for the same output quantity, and exceed the output's resale value. Validate these inequalities
together when changing recipes, buy prices, or sell values; a stock limit is not a substitute for valid prices.
Check the configured Material allowances and prices make buying missing inputs a usable alternative,
while preserving the GDD's first-craft route through any one Shrine without Shop purchases.
For the initial tuning, validate each Material allowance against the inputs for one matching sword
and one matching Shield. Configure exactly one Featured sword and one Featured Shield of the same
element per hourly period, with one copy of each per player. Validate the shared Fire → Water →
Earth → Air → Light → Dark cycle, its six-hour repeat, and unchanged offers/stock after server changes.
Use the GDD's initial economy prices and validate their ratios
and every resale inequality. The initial recipe produces one Equipment copy, uses five matching
normal Materials, and requires a 10-Material allowance for a matching sword-and-Shield pair.
Changing recipe quantities requires rechecking the corresponding allowance and Equipment price.

Reference validation is insufficient for progression. Check cost/unlock dependencies against the
GDD's [Shrine and recovery rules](GDD.md#shrine-rules): required Materials must be obtainable through
already available Shrines or approved Shop stock before their cost is charged, and required inputs must
fit the Inventory capacity reachable before the relevant upgrade. Reserved Equipment output must fit
alongside items the player cannot sell. A full launch Mythling inventory must have a valid
space-recovery action. Initial spawn countdowns must allow an uninterrupted configured capture before
overtime is needed, including the initial 60-second Epic capture. Verify these paths with actual
launch configuration; valid IDs alone do not make them reachable.

Validate that all six elements' basic level-1 Shrines use the same Gold-only price, including
rebuilds. Starting Gold must cover one without selling the first capture. Validate Gold-and-Material Base
build-slot upgrades: two starting slots, one added per purchase, and six unlocked slots at most.
Validate initial access to one permanent Station outside the Shrine-only build slots. Equipment
recipes retain their Gold/Material costs. Check the first craft and evolution against the GDD's
[early progression targets](GDD.md#early-progression-targets) using
one Shrine and the included Station, with no Station purchase cost. Also check the route with two
starting Shrines; the Station must remain usable when both build slots are occupied.
Repeat this route for each first-Shrine element and its corresponding Stage 1 variant recipe;
no route may require a second element's Material to reach that first craft.
Baseline timing must work without rare captures. Derive the first
evolution target from the shared activity XP rate and that Mythling's eligible working time across
sessions; full-storage and unassigned intervals do not contribute.
Use the revised Common production baseline when validating this route: five recipe Materials take
25 minutes of unchanged base-rate work. Distinguish
time since joining from eligible production time and ingredient readiness from job completion.
Each initial craft adds 60 seconds after its start. Shop inputs can shorten acquisition time but
cannot substitute for validating each Shrine's independent route. Keep the roughly 30-minute
first-evolution work target independent of this lower Material throughput.

Validate all upgrade recipes against the GDD's [upgrade saving targets](GDD.md#upgrade-saving-targets),
including a first Shrine upgrade taking days. Base and Inventory recipes use equal quantities of
all six normal Materials; Shrine upgrades retain matching-element inputs. Required inputs must be reachable
with pre-purchase Shrine slots, realistic limited Shop stock, and pre-purchase Material capacity.
Do not use the capacity being purchased to justify fitting its own costs. Pacing calculations must
account for Materials retained for payment instead of treating them as simultaneous Gold-sale income.
Initialize the level-1-to-2 Shrine price at 1,000 Gold plus 400 matching normal Materials for all
six elements, following the GDD's initial economy values. The starting Material Inventory must
hold this payment without a capacity upgrade. Collect and accumulate it across Shrine visits;
do not raise the level-1 Shrine's 300 storage or spend uncollected output to make the recipe fit.
Initialize the level-2-to-3 Shrine price at 15,000 Gold plus 4,000 matching normal Materials for
all six elements. At the initial 1,000-per-type stack limit, the two Shrine upgrade payments need
one and four Material slots respectively; both fit the 12-slot starting Material Inventory when
that space is available. Accumulate collected output across visits while level-2 Shrine storage
remains 1,200. Validate each Inventory-capacity upgrade's own costs against the capacity available
before that purchase, including crafting reservations. The Material category's first and final
upgrades must fit 12 and 24 Material slots respectively; Mythling and Equipment upgrade costs must
fit Material capacity reachable beforehand. Round required stack slots up separately for every Material ID.
Six different elemental stores of 3,600 each require 24 slots, not 22; verify collection into the
first upgraded bag with sufficient free capacity and partial collection when existing stock or
reservations limit space. Validate the other categories' initial limits, both +12 grants, and
independent maximums against the GDD's [Inventory limits](GDD.md#inventory-capacity-and-overflow).
Initialize the four Base expansions at 10,000/50,000/150,000/500,000 Gold plus 50/100/150/200
of each normal Material respectively. Inventory upgrades use the two per-category prices above.
Every recipe occupies six Material stacks at the initial limits, before other owned quantities
and reservations are considered. Validate every required Material ID and quantity; an equal
total quantity of substituted elements is not a valid payment. Purchases do not require owning
the matching Shrines. Test missing-element acquisition at the existing 10-per-refresh allowance,
including duplicate-element Base layouts, without scaling Shop stock or requiring dismantling.
Gold sets most Base/Inventory saving time; missing-element Shop allowances can also constrain it.
Preserve existing paid upgrades through cost changes without retroactive charges.

Luck and Passive Trait acquisition/effect definitions, Consumable definitions, buff-stack rules, and
expanded Crafting Station queue/upgrade definitions are added with their future updates. They are
not required launch configuration, and launch validation must accept records without Luck or a Trait.

### Arena spawn selection and lifetime policy

Private `MythlingSpawnService/SpawnSelection.Build(forms, weights)` compiles a detached, recursively
frozen pool from the catalogue's explicit rarity metadata. It requires nonempty form IDs, plain
definition records, positive finite weights with exact group coverage, and a safe strictly increasing
total. A missing or extra weighted rarity, empty pool, zero/invalid weight, or unsafe accumulation
rejects instead of silently renormalizing the remaining content. Alphabetically sorted rarity names
and form IDs make intervals deterministic; no property is inferred from an ID, stage, or model.

`Choose(pool, rarityRoll, formRoll)` takes independent normalized rolls from zero through one,
chooses a weighted rarity and then a uniform form within that rarity, and returns only the selected
form ID. Internal intervals are half-open; the exact upper endpoint selects the final interval.
Invalid rolls return no selection. The six complete launch chains give one form of each element
per rarity, so uniform forms provide equal element probabilities. No rarity is rolled onto an
owned instance, no fixed Arena quota is imposed, and repeated forms remain possible.

`Configurations.MythlingSpawns.rarityWeights` holds the initial Common/Rare/Epic 75/20/5 weights;
the separate, explicitly temporary `prototypeRarityWeights` retains Common/Rare/Legendary 100/50/15.
The service validates both catalogues with the same compiler during Init and delegates its actual
picker to `Choose` using the prototype pool until approved assets are bound. No canonical names,
models, radius, or prototype substitutions are invented. `SpawnPopulation.QueueDeficits` invokes
the picker once per initial/replacement attempt and retains its result across placement retries.
Simultaneous deficits have independent selections/deadlines; overtime does not release capacity.

Private `SpawnLifetimeUtil.Resolve(formId, rarity, captureProgressPerSecond, tuning)` validates
the shared lifetime maps and the selected form's capture duration. Every enabled rarity requires
a positive finite default, even when that form has an override. A present override replaces the
default; malformed or nonpositive overrides never fall back. All configured keys/values are checked,
including currently unselected entries; well-formed override IDs may span the separate catalogues.
The retained `defaultExpireSeconds` field cannot substitute for a missing rarity default. Effective
lifetime must safely exceed `100 / captureProgressPerSecond` on the existing percentage scale.
This establishes positive arrival slack, not sufficient travel time on an authored map.

`Validate(forms, tuning, rateField)` runs for canonical `captureProgressPerSecond` and retained
prototype `fillRate` before startup. The service also resolves before each placement attempt and
again when the contest becomes capturable, using that contest's recorded rarity and capture rate.
`GetDeadline` rejects nonfinite/unsafe start times or sums and durations lost to clock precision.
Initial activation prepares every deadline after full prefill with one shared start time, opening
none if any is invalid. Failed initial activation retains the selected forms for retry and reports
`RefillFailed`; replacements validate before consuming capacity and retain their pending selection
on failure. Each replacement starts at its own activation. Existing runtime
`startedAt`, `lifetimeSeconds`, and `expireAt` stay fixed through later configuration changes and
overtime. No lifetime or copied rate is added to owned records. Initial-config tests check all 18
240-second lifetimes without overrides; validators still permit future valid per-form tuning.

Deterministic policy/population/grant tests and disposable service tests verify the selection,
validation, and activation boundaries, not live roster activation, map arrival, eight-player
refill performance, or durable capture delivery. Approved model/radius bindings and those live
checks remain release requirements. No GUI or authored asset is changed by this policy integration.

### Launch Mythling form catalogue

`Shared.Configurations.MythlingForms` is the read-only business catalogue for the 18 launch forms,
separate from the unchanged live prototype `Configurations.Mythlings`. It supplies permanent
neutral form IDs without inventing creature concepts, display names, lore, models, thumbnails, or
other presentation data. Those creative decisions remain open. Each key identifies one form:

| Element | Internal Stage 1 / Common | Internal Stage 2 / Rare | Internal Stage 3 / Epic |
| --- | --- | --- | --- |
| Fire | `mythling_0001` | `mythling_0002` | `mythling_0003` |
| Water | `mythling_0004` | `mythling_0005` | `mythling_0006` |
| Earth | `mythling_0007` | `mythling_0008` | `mythling_0009` |
| Air | `mythling_0010` | `mythling_0011` | `mythling_0012` |
| Light | `mythling_0013` | `mythling_0014` | `mythling_0015` |
| Dark | `mythling_0016` | `mythling_0017` | `mythling_0018` |

IDs use `mythling_` followed by a permanent positive identifier with at least four decimal digits,
zero-padded below 10,000. Continue with `mythling_10000` and beyond rather than truncating, renumbering,
or reusing IDs. The number encodes no element, rarity, evolution stage, ordering rule, or future
content limit; resolve those properties from metadata. Finalizing the same form's name or assets
retains its ID, while a distinct form receives a new ID. A form ID is separate from the unique owned-instance
ID of each captured copy. This increment neither renames the saved `typeId` field nor replaces its
existing prototype values; any future owned-record adaptation must be explicit and preserve identity.

Each form explicitly configures `element`, fixed `rarity`, internal `evolutionStage`,
`baseYieldPerHour`, `sale.gold`, `captureProgressPerSecond`, and `captureDecayPerSecond`.
The initial Common/Rare/Epic values are 12/18/32 Materials per hour and 25/100/300 Gold.
On the existing 100-point capture scale, progress rates are `100 / 20`, `100 / 35`, and `100 / 60`
per second respectively; decay equals progress for each form. Each first form links to the next
through `evolution = { targetFormId, requiredLevel = 6 }`, and each second form links to its final
form at level 40. Final forms have no `evolution` link, but still use the shared level cap.
These values belong to each explicit definition, not a runtime stage/rarity multiplier.
The shared spawn configuration retains 240-second rarity lifetimes and no overrides for these
IDs; the [spawn policy](#arena-spawn-selection-and-lifetime-policy) validates effective lifetimes
against their capture rates without activating the forms or copying rates into saves.

`ServerScriptService.Shared.MythlingCatalogUtil.ValidateLaunch(forms, levelCap)` runs from
`MainServer` before service startup. It checks the launch-specific cardinality, element/rarity/stage
coverage, complete same-element chains, safe configured values, capture-rate relationships, and
sale-price relationships. Valid tuning changes remain allowed; validation is not a hard-coded
copy of the initial numbers. This launch-catalogue contract does not narrow the generic accrual,
evolution, or sale reducers into a universal three-stage/rarity rule.

The catalogue is not passed into the prototype definition map in the live service context. Spawn
policy validation requires it directly; actual selection still uses the explicit prototype pool.
Existing live definitions/effective weights, models, save schema, prototype stand production, and
menus remain unchanged. The canonical
[capture-grant boundary](#canonical-capture-grant-boundary), Shrine commands, evolution, and sales
consume the relevant metadata directly. Capture grants retain the caught form with new-grant
progression defaults; evolution changes only the selected owned `typeId`, and sales remove only the
selected owned instance, through their protected transactions. Validation alone enables none of
these mutations. Activating the canonical live spawn pool and completing creative asset readiness
require separate increments; metadata and grant tests do not establish those features.

### Launch Material catalogue

`Shared.Configurations.Materials` defines the stable IDs `fire_material`, `water_material`,
`earth_material`, `air_material`, `light_material`, and `dark_material`, one per matching launch
element. Each has `launchEnabled = true`, `category = "material"`, its `element`, configured
`buyGold = 10` and `sellGold = 2`, and `stackLimit` derived from
`Shared.Configurations.Inventory.materialStackLimit` (initially 1,000). The key is the Material's
identity; display names are not lookup keys. Temporary names such as `Fire Material` and empty
thumbnails leave final creative names/icons open without delaying stable content references.
Each definition in `Shared.Configurations.Shrines` has a required `materialId` pointing to its
same-element launch Material. Future production, recipe, upgrade, Shop, and sale integrations must
use these shared references rather than inventing feature-specific IDs or copied prices.

`ServerScriptService.Shared.MaterialCatalogUtil.Validate(materials, shrines, stackLimit)` is a pure
validator called by `MainServer` before service startup. It requires one enabled normal Material
per launch element, valid same-element Shrine output references, positive safe-integer buy/sell
prices with buy greater than sell, and stack limits consistent with Inventory configuration.
Invalid catalogue metadata prevents service startup; validation does not grant items, charge Gold,
or implement production or trading. Deterministic tests cover the real catalogue and malformed
injected fixtures.

The prototype `essence`, `crystal`, and `shadow_dust` entries remain with `launchEnabled = false`
and otherwise retain their metadata. This flag is the launch-catalogue boundary, not a switch
disabling existing prototype runtime: current Mythling production references, owned quantities,
and stand production/collection remain unchanged. Catalogue validation itself supplies no save
migration, gameplay action, menu change, or Mythling-roster replacement. Canonical Shrine, upgrade,
[Material-disposal](#atomic-material-sale-and-discard-commands), headless crafting, and Shop commands
consume these references. Player-facing endpoints and menus remain separate integration work.

### Launch Equipment catalogue

`Shared.Configurations.Equipment.definitions` contains `wooden_sword`, `wooden_shield`,
`elemental_sword`, and `elemental_shield`. The compatibility `profiles` map still exposes only the
same two wooden objects to existing preview/VFX consumers. Server loadout/combat resolution and
non-GUI client input use canonical definitions and exact mounted identities; unbound items do not
gain combat eligibility.
The crafted definitions share base gameplay by type, with swords retaining
the wooden sword's values and crafted Shields owning their configured impact cost/guard minimum.

Each crafted definition has six named `finishes`, keyed `fire`, `water`, `earth`, `air`, `light`, and
`dark`. A finish owns its name, description, fixed rarity, element, optional thumbnail, and sword
effect reference—not independent gameplay overrides. Static rarity remains Common for the wooden
pair and Rare for the named crafted items. Stage is internal; no owned rarity, copied statistics,
new saved field, or automatic equip is introduced. Crafted model names/thumbnails remain explicitly
unbound until assets are approved; there is no implicit wooden-model substitution.

`Shared.EquipmentCatalog.Resolve(definitionId, finishId)` returns immutable derived item metadata
with its shared definition as `profile`, or nil for an unknown/invalid pair. Crafted definitions
require a valid finish; plain definitions reject unexpected finishes. The owning definition supplies
`sellGold` when sellable, while original starter protection remains an owned-instance rule.

`Configurations.EquipmentRecipes` contains twelve fixed matching-Material recipes, keyed by base
definition plus finish (for example `elemental_sword_fire`). Each references the included Station,
Gold/Material costs, exact result IDs, quantity, and duration. `ElementalSwordEffects` owns the six
approved effect roles, descriptions, and tuning. The headless crafting lifecycle consumes recipes
and snapshots agreed promises; Shop grants retain the same definition/finish identity. CombatService
consumes effect metadata only after accepting an unblocked hit. Client attack/guard input resolves
the same named variants, while approved asset bindings and live verification remain separate. The
catalogue never rewrites owned records or infers missing
historical receipts from today's recipes.

`ServerScriptService.Shared.EquipmentCatalogUtil.ValidateLaunch` checks launch coverage, compatible
base profiles, finish/effect roles, references, safe recipe arithmetic, and resale relationships
before services start. Balance values remain configurable; real-catalogue tests assert the GDD's
initial tuning separately. Catalogue verification does not prove asset readiness, accepted-hit
effect behavior, connected-player integration, or durable persistence, and adds no GUI behavior.

## Player save data

The persistent player document stores lightweight, mutable player state. It references static
metadata by ID rather than duplicating names, descriptions, models, recipes, visual assets, or
immutable base statistics.

At minimum, the target document shape is:

```text
version
profile                 -- user/profile timestamps and approved flags only
currency.gold           -- uncapped mutable Gold balance
materials[materialId]   -- whole quantity only; stack rules come from Material metadata
inventoryUpgrades[tabId] -- purchased upgrade IDs/levels; derive capacity from configuration
shop                    -- current refresh period ID and purchased quantities by stable stock key
equipment[instanceId]   -- definitionId, optional finishId, isStarterGrant, unique mutable state
combatLoadout           -- optional primaryWeaponInstanceId and shieldInstanceId
mythlings[instanceId]   -- owned Mythling schema below
base                    -- build-slot upgrades, constructed Shrines, permanent Station record
productionClock         -- common lastAccruedAt/nextBatchAt; future recovery metadata below
craftingJobs[jobId]     -- at most one active Crafting Job at launch; receipt and reservations below
unlocks                 -- approved progression/unlock flags
requestReceipts         -- bounded mutation IDs/results for duplicate-safe resolution
```

`shop` stores only mutable current-period usage. The implemented optional record is initialized
lazily by a successful purchase; a read returns an unused or refreshed virtual allowance without
writing the profile. Derive offers, prices, limits, and refresh times
from configuration. Reconnects restore usage before purchases are enabled; a new profile receives
an unused current-period allowance, and an existing profile advances only when the schedule reaches
a newer period. Keep completed purchase results in bounded `requestReceipts` independently of stock
rollover. Forward-only migrations preserve Gold, Inventory, upgrades, and any existing purchase usage.

`base` saves only player-specific state. Each built Shrine record contains a unique `id`, its static
`shrineId`, a unique `buildSlotId` within unlocked capacity, current level, whole `stored` output,
unfinished `progress`, unresolved batch `newWork`, and assigned Mythling instance IDs in
`workerIdsBySlot`. One profile-wide `productionClock.lastAccruedAt` and `nextBatchAt` schedule
all Shrines; do not save a copied cursor on each Shrine. Keep prior unfinished progress separate
from unresolved batch work so reconnects cannot replay it and worker changes cannot recalculate
work already earned. The required permanent Crafting Station record
contains a stable unique `id` and its static `craftingStationId`, independently of
Shrine build slots. Station levels are introduced with the future upgrade system. Structure
elements, Material output, capacities, slot grants, and Shrine build costs are resolved from metadata.

Initialize the permanent Station once per profile without charging currency or Materials. Base
allocation, reset, and reconnect reconstruct its world presentation from the same saved identity;
they must not create another Station or restart its job. Migrations reuse an existing Station
identity when present and preserve active-job links, promised result/finish, paid costs, deadline,
and reservations. Remove any legacy Station occupancy from the build-slot count without removing
Shrines or jobs. No separate purchased-Station flag or construction receipt is required at launch.

### Schema-7 Shrine accounting foundation

`ProfileSchema.Prepare(data, createStationId, now?)` adds the empty Shrine accounting foundation
within the configured namespace. Server time defaults to `os.time()` and may be injected for
deterministic tests. The schema-4/5 layout upgrades remain; schema-4–6 Shrine records with wholly
absent accounting receive `stored = 0`, `progress = 0`, `newWork = 0`, and `workerIdsBySlot = {}`.
The common clock is initialized once at preparation time with `lastAccruedAt = now` and
`nextBatchAt = now + Production.batchIntervalSeconds`, never from `lastLoginAt` or a prior feature's
cursor. Empty initialization grants no output or XP and introduces no pre-feature backfill.
`PlayerDataTemplate` contains no static production timestamps; load creates the clock.

Preparation preserves existing valid complete accounting and clocks, Station/Shrine identities,
and unrelated fields. Ambiguous partial accounting, invalid state, or existing Shrine accounting
without its clock is rejected without rewriting earned state. Current schema-7 profiles must
already contain the required fields; only a genuinely new empty template profile with its original
initialization sentinels may receive its first clock. Repeated preparation retains that clock.
`BaseService.BuildShrine` initializes the four empty accounting fields inside its existing
transaction without restarting or advancing the profile schedule.

The existing DataService persistence path owns these fields, and its explicit client projection
continues to omit the private Shrine accounting and root clock. This foundation creates no second
owned-Mythling/worker map and changes no Mythling progression or inactive Luck/Trait data. The
[draft adapter](#shrine-accounting-draft-adapter) now has on-demand settlement, atomic assignment,
collection, upgrade, dismantling, evolution, and sale callers. Automatic production lifecycle
settlement now uses the same adapter through the [profile hook](#automatic-shrine-production-lifecycle).
Player-facing actions remain separate work; prototype stand paths are untouched. Optional
`lastOnlineCheckpointAt`/`offlineSince` hints are validated and preserved during preparation; both
absent remains compatible. Preparation does not initialize those hints or award work: Ready,
Checkpoint, and Release update them with their successful settlements. Serialized-state tests do
not establish live durable-save behavior.

### One-time starter Equipment initialization

The recurring `PlayerDataTemplate` contains empty `equipment` and `combatLoadout` tables. Vendor
reconciliation therefore cannot recreate starter records or fill intentionally nil slot references.
After all schema/Base/production-clock validation succeeds, `ProfileSchema.Prepare` applies a
detached candidate from private `StarterEquipment.Stage`, preserving existing table identities.

Grant only clearly untouched data: all three profile timestamps/identity sentinels (`userId`,
`createdAt`, `lastLoginAt`) are zero; Gold equals configured starting Gold; Equipment, loadout,
Materials, Mythlings, jobs, stands, and Shrines are explicitly empty; purchased counts and transaction
revision are zero with no receipts. Missing bookkeeping or unknown retained fields makes this grant
ineligible, not grounds for erasing state or failing otherwise-valid schema preparation. A valid
pre-created permanent Station and zero-work clock may survive an interrupted initialization.
Existing Equipment, including old or partially missing starter kits, is always left unchanged.
No empty slot is filled as a reconnect repair, and established profiles receive no replacement items.

The grant creates `starter_wooden_sword` and `starter_wooden_shield` using the configured definition
IDs, marks both `isStarterGrant = true`, and sets both initial loadout references together. Failed
preparation installs none of it; a repeat before profile metadata initialization sees the existing
pair and grants nothing. ProfileStore session counters/timestamps are not new-player authority.
There is no additional saved marker, schema version, namespace, vendor change, or alternate template.

The originally granted sword and shield carry server-owned `isStarterGrant` identity in their
Equipment records. Retain it through migrations and reject sales or destructive removals of those
instances even after unequip or reconnect. Clients cannot set or clear this flag. Other instances
of the same definitions follow normal metadata eligibility. Character resets rebuild the saved
loadout presentation and never issue a new starter grant.

### Shrine assignments and retained ownership

The Shrine slot map is the sole persisted source of assignment. An owned Mythling may appear in at
most one slot across the Base. Build reverse lookup indexes from this map on load;
`assignedShrineId` and `assignedSlotId` may be derived for a client-safe view, but are not a second
saved authority. Validate ownership, matching elements, and valid slots before counting production.
Resolve invalid legacy links without deleting the owned Mythling. Assignment or removal settles
affected production and changes the slot map in one transaction.

Require explicit unassignment before assigning an already-working Mythling elsewhere. Assign only
to an empty unlocked slot; never move, swap, or replace workers as a side effect. Removal identifies
the selected Shrine, slot, and expected worker, rejecting a changed occupant instead of removing
someone else. Slot identities remain stable when another slot is emptied; do not compact the map.

Each owned Mythling occupies one Mythling slot whether assigned or unassigned. The initial 24-slot
capacity therefore supports 18 Shrine workers and six spares; assignment grants no extra capacity.
All launch Equipment remains in `equipment[instanceId]` and counts toward Equipment capacity whether
equipped or unequipped, including both protected starter instances. Each copy uses one slot, so the
starter pair occupies two of the initial 12 Equipment slots. The deferred storage box adds no launch
container schema or transfer path.

For the Stage 1 contract, `finishId` is the saved element-variant reference; the player-facing term
is **element variant**. Save it beside the base `definitionId`; resolve the internal stage, element,
full item name, fixed rarity, colors, shared model/base statistics, and sword effect from metadata. Crafting receipts
retain the promised definition/finish IDs; do not duplicate static rarity in owned items or receipts.
Stage 2 and later upgrades are outside the MVP and require their own approved progression contract
rather than adding arbitrary base-stat overrides to Stage 1 finish metadata. The approved launch
sword effect reference is the only gameplay-specific addition to that variant metadata.
The server sets the variant from the crafting receipt or validated Shop offer and retains it through
equip/unequip, reset, and reconnect. It is fixed on that instance. Each acquired copy uses one
Equipment slot; UI grouping introduces neither stackable Equipment nor a separate
cosmetic-unlock inventory. Missing finish IDs retain the plain appearance of starter and existing
prototype Equipment without regranting items or changing `isStarterGrant`.

Material quantities are aggregated by metadata ID; occupied stack slots are derived from quantity
and configured stack size, rounding up separately per Material ID (initially 1,000 units per slot).
Capacity checks also account for active reservations and purchased
per-tab upgrades. Inventory upgrades persist as ownership/level state, never as copied static prices
or slot-grant definitions.

Use one shared server-side capacity calculation for collection, capture awards, purchases, and
crafting. Feature services supply their intended changes; they must not maintain independent copies
of stack/slot or reservation arithmetic. Likewise, online, offline, and pre-mutation production use
the same accrual path so collection timing cannot change how much work has already been earned.

Active jobs store the receipt fields and reservations defined in [crafting
transactions](#crafting-transactions). Those amounts, IDs, and timestamps preserve each agreed
result, refund, and timing across metadata changes. Resolved history must remain bounded.

Consumable ownership, Hotbar assignments, and additional Crafting Station/queue state are future
schema additions through forward-only migrations. They are not required fields for a new launch
profile. Existing prototype fields must not be destructively removed merely because their features
are deferred. Accessible progression through ordinary Arena captures uses existing Mythling
ownership, Material, and Gold state; it adds no separate participation balance or
fallback-progression record.

The owned collection is keyed by unique instance ID. New canonical capture entries use the existing
saved field names rather than introducing duplicate IDs or renaming older records:

```text
mythlings[instanceId]
typeId             -- current Mythling-form metadata ID
variantId          -- ordinary "regular" sentinel for canonical launch forms
level
xp                 -- progress toward the next level, retaining earned precision
pendingXp          -- earned credit, awarded on the common profile batch schedule
claimedAt          -- server-authored acquisition timestamp
```

Evolution updates `typeId` to the evolved form's metadata ID. The saved entry stays small while
the game resolves the current form's base Yield and other immutable data from metadata. Resolve
`evolutionStage` from the current form definition; do not duplicate it or the chain's static data in
the owned record. Mythling Stage 2/3 support is part of launch and is independent of the deferred
Equipment-upgrade system. New records need no Luck or Trait fields. Preserve any existing `luck`
and `traitId` values through saves, evolution, and migration as inactive legacy data; do not delete,
overwrite, reroll, display, or apply them during the MVP.

When migrating legacy production state, retain already stored Materials, awarded/pending XP,
unfinished progress, and recorded unresolved new work exactly once. These are earned state;
do not reverse an already settled bonus. A legacy `luckWeightedWork` value is not production work
and must never become an additional grant, chance, or multiplier under launch accounting. Retain
that legacy value inertly if present, without requiring it in new Shrine records. Advance production
only from the saved cursor with the deterministic launch rules; do not reroll or reprice earlier
work. Use an explicit forward-only migration before resuming accrual if a prototype schema needs
translation; do not infer a missing work quantity from its former Luck weight.

Pending XP is earned mutable credit, not a saved copy of the activity's rate. Keep it on the owned
Mythling so unassignment, moving, or Shrine dismantling cannot erase it. Clear it once awarded or
when that owned instance is retired; never transfer it to a replacement instance.

## Data ownership matrix

Equipment rarity belongs to the named item's static metadata. Owned records retain the IDs needed
to resolve it, without a separate rarity roll or saved copy of the static value.

| Game data | Metadata (static, version-controlled) | DataService player document (mutable) | Runtime-only server state |
| --- | --- | --- | --- |
| Mythling form | `mythlingId`, name, element, rarity, evolution stage, visuals, base Yield, shared acquisition defaults and progression curves, evolution target/level, Arena eligibility, capture tuning, optional spawn lifetime override, sell eligibility and fixed form Gold value | Owned instance ID, current `mythlingId`, level, XP with retained precision, acquisition data; inactive legacy Luck/Trait values only if already present | Spawned contest, occupancy/entry order, per-player capture meters, countdown/overtime state; reverse Shrine-assignment index |
| Shrine-work XP | Shared activity `baseXpPerSecond` | Pending earned credit on each owned Mythling; awarded XP stays on that instance; timing uses the common production clock | Per-worker eligible time and resolved activity rate |
| Luck and Passive Traits (future) | No required launch definitions; future update needs an approved design | Existing legacy `luck` and `traitId` retained unchanged; absent on new launch captures | None at launch |
| Material | `materialId`, element, display data, stack limit, fixed unit Gold sell/buy prices, crafting use | Quantity by `materialId` | World pickup/claim state, if introduced in an approved system |
| Equipment | Base definition ID, stage/type, category, model, Primary Weapon hands required, base gameplay values, sell eligibility/value, supported variant IDs/elements/item names/recolors/sword effect references, fixed rarity per named item | Owned instance ID, definition ID, optional finish ID referencing the Stage 1 variant, starter-grant identity, Combat Loadout references, approved unique mutable state | Equipped selection and variant presentation, cooldowns, Shield state |
| Gold | None beyond balance presentation/configuration | Uncapped `currency.gold` balance | None |
| Inventory capacity | Initial per-tab limits, stack rules, upgrade IDs, slot grants, Gold costs and fixed Material mixes, eligibility | Purchased per-tab upgrade IDs/levels | Derived occupied/available capacity, including job reservations |
| Shop | Refresh schedule, period/offer revisions, Material references and limits, Featured selection, Equipment references/prices/limits; Inventory-upgrade references | Current period ID and purchased quantities by stable stock key; bounded purchase results in mutation receipts | Current catalogue view, derived personal remaining stock and next refresh time |
| Base | Build-slot upgrades with Gold costs and fixed Material mixes, slot grants/limits, Shrine eligibility, included Station definition/placement | Purchased build-slot upgrade state, constructed Shrine records, permanent Station record | Spawned Base model references and Shrine-only build-slot occupancy |
| Shrine | `shrineId`, element, output Material, levels 1–3, storage capacities, 1/2/3 assignment slots, upgrade costs | Instance ID, level, whole stored output, unfinished progress, unresolved batch new work, assigned Mythling IDs by slot | Current production resolution during accrual/collection |
| Production clock | Batch interval and approved accrual rules | One profile-wide `lastAccruedAt`/`nextBatchAt`, plus optional online checkpoint/offline-start bookkeeping initialized by Ready settlement | Active session/transition accounting |
| Crafting Station | `craftingStationId`, included Base placement, eligible recipes, single-job launch limit | Stable permanent instance ID and definition ID | World presentation and current menu/session references |
| Recipe and Crafting Job | `recipeId`, fixed inputs, Gold cost, result definition/finish/quantity, duration, unlock requirement | Job ID, recipe/station instance IDs, status, start/completion time, promised result including finish, actual paid costs, output/refund reservations | Completion scheduling while a server is live |
| Arena spawn rules | Rarity-weighted pool, capturable-population target, refill window, positions, rarity-default lifetimes and optional named-form overrides, capture rates | None | Capturable Mythlings and Capture Rings including start/expiry timestamps and overtime, initial-population readiness, pending replenishment |
| Player combat | Equipment/effect tuning and animation/VFX references | Equipment ownership and Combat Loadout | Stamina, hit sequence/recent hit IDs, immunity, cooldowns, active Shield, knockback, active/pending negative effect and deadlines, Earth recovery deadline |
| Mutation resolution | Request validation and retention rules | Bounded request IDs and recorded results | Per-profile serialization and pending save tracking |

The server validates every client request that changes inventory, currency, Equipment, production,
or capture. Persistence must use bounded document sizes, retry handling, periodic saves, safe
failure behavior, and forward-only schema migrations. Reconciliation only supplies missing defaults;
it does not migrate renamed fields or reinterpret old records. Use the [transaction and save
guarantees](#transaction-and-save-guarantees) for atomicity and durability.

## UI composition and ownership

Production GUI is Rojo-owned and composed under one Fusion-managed application lifetime. Screens may
use scoped Fusion composition or focused imperative component factories such as
`UI/Components/Panel`; both must register cleanup with the owning scope. Studio is a preview and
runtime-testing surface, not the source of truth for application UI. `UIController` owns one Fusion
scope and mounts one `UI/App` root after client state/network initialization.

### ScreenGui roots

- Create production `ScreenGui` roots from `StarterPlayerScripts.UI.Screens` and parent them
  directly to the local player's `PlayerGui` from the single `UI/App` composition root.
- Use stable `PascalCase` names for semantic instances such as `MainPanel`, `ItemList`, and
  `CloseButton`; code must not depend on incidental decorative wrappers.
- Set root lifecycle properties explicitly, including `ResetOnSpawn`, `DisplayOrder`, inset
  behavior, and `ZIndexBehavior`.
- Interactive application panels use `CoreUISafeInsets`, device-safe clipping, and no legacy
  fullscreen-extension transform. The persistent HUD may use a full-screen canvas only for
  deliberately top-bar-aligned chrome.
- Do not create a controller per visual widget. Add a component when it has a reusable visual
  contract; otherwise keep the element inside its owning screen.

### Visual ownership

- Define frames, labels, buttons, constraints, layouts, padding, fonts, gradients, strokes, corners,
  responsive layout, and selection navigation in repository-owned UI modules.
- Keep component-specific visual properties with the component. Put only genuinely shared colors,
  spacing, typography, responsive metrics, layer values, and animation durations in `UI/Theme.lua`.
- Use Studio to inspect and tune the runtime result. Any accepted visual change must be made in Rojo
  source so a clean build reproduces it.

### Behavior ownership

- Keep feature input and domain behavior in bootstrapped modules under
  `StarterPlayerScripts.Controllers`. Keep visual composition in `UI/Screens` and reusable
  presentation in `UI/Components`.
- A controller captures shared dependencies through `Init(context)`, resolves required UI
  descendants and subscribes to state/domain events in `Start()`, and releases every owned
  connection or task in `Stop()`.
- Controllers must update views from `LocalData` or a server-confirmed domain event. Do not use
  polling loops, duplicate remote listeners, or UI properties as authoritative game state.
- `UIController` coordinates replication and the single Fusion scope. Focused feature controllers
  own domain interactions; they do not rebuild visual hierarchies. Avoid both a monolithic UI router
  and controller-per-widget fragmentation.
- Adapt `LocalData` keys into Fusion state through `UI/State`. Do not create a second client cache:
  the adapter subscribes to `OnStateChanged` and exposes only the reactive value needed by a screen
  or component.

Inventory equipment requests and Stand interactions use controller-owned view sessions. A session
owns pending requests and refreshes, and invalidates their results when the screen closes, changes
selection, or is destroyed. Screens supply presentation callbacks and register session cleanup with
their Fusion scope. View-binding records are input props; their camelCase instance fields are not
public component handles.

`MenuState`, `ModalState`, and `ToastBus` share `UI/State/SubscriptionList`: callbacks run synchronously,
errors are isolated, each registration has an idempotent unsubscribe, and duplicate registrations are
independent. State subscriptions deliver an initial snapshot; event-only Toast subscriptions do not
replay. Listeners removed during dispatch are skipped, and listeners added during dispatch begin with
the next publication. Native `RBXScriptSignal` APIs retain Roblox connection semantics; callers own
their connections. `MainClient` stops controllers and the application scope before terminally
destroying the session-owned `LocalData` cache and its signal.

### Reusable components

- Put declarative visual components under `StarterPlayerScripts.UI.Components`. Reserve
  `ReplicatedStorage.Assets.UI` for client-visible image, model, and effect assets rather than
  executable UI composition.
- Give each component a small props-and-callback contract. Components never read or mutate server
  data directly and never create their own authoritative state store.
- Store published image, font, sound, and animation IDs in metadata/configuration rather than
  scattering IDs through view controllers.

### Mythling thumbnails

- Inventory and detail views render the `thumbnail` declared by the current Mythling form; clients
  never receive cloned gameplay models solely for UI previews. Existing prototype `variants.regular`
  entries are legacy metadata to align with form definitions, not approval for launch cosmetic
  Mythling variants.
- Generate thumbnails during authoring from the canonical model in
  `ServerStorage.ServerAssets.Mythlings`, using consistent camera framing, lighting, background, and
  output dimensions.
- Upload the generated image as a Roblox Image asset and record its `rbxassetid://` value in
  `ReplicatedStorage.Shared.Configurations.Mythlings`. API keys and upload credentials remain
  outside the repository and are never available to runtime scripts.
- Adding a Mythling requires its server model, configuration entry, and thumbnail asset ID; it must
  not require changes to UI controllers or server services.

### Security and presentation boundary

- The client may present input feedback, pending states, and cosmetic prediction, but it may not
  grant currency/items, approve purchases or crafting, or mutate persistent data.
- The server validates every intent and replicates the confirmed result that drives the final UI
  state.
- Presentation, mobile safe-area behavior, touch targets, legibility, and accessibility follow [UI
  guidelines](UI_GUIDELINES.md). Technical ownership does not change the approved UI rules.

## Roblox Studio and Rojo ownership

Rojo and Studio are complementary, but a given instance must have one clear owner. Never edit the
same instance hierarchy independently in both places and expect Rojo to merge it safely.

### Keep in the Rojo repository

- All Luau source, bootstraps, services, controllers, utilities, types, tests, and vendored
  packages.
- The canonical Explorer hierarchy, instance classes, important properties, and all network
  definitions in `default.project.json`.
- Static metadata, balance values, feature configuration, schema versions, and player-data
  templates. Mutable player state never belongs in source files.
- All production application UI composition, components, responsive rules, state bindings, and
  behavior.
- Published asset IDs and their configuration. Keep editable source assets such as `.blend` files in
  the repository when practical; do not treat a published Roblox asset as the only source copy.
- Toolchain configuration, documentation, and migration notes.

### Author in Roblox Studio

- Terrain and large spatially authored map composition.
- Spawn placement, lighting composition, attachments, particle emitters, and other content whose
  authoring depends on the 3D viewport.
- Complex Roblox models, rigs, and animations. UI may be explored in Studio, but accepted
  application layouts are implemented in Fusion source rather than retained as Studio-only
  instances.
- Instance properties that cannot be represented safely or ergonomically through the current Rojo
  source format.

Studio-authored production content should still be backed up or exported into version control when
practical. Reusable models can be checked in as model artifacts; external art source files belong
in the separate asset workspace and need their own backup strategy. Published animations, sounds,
meshes, and images must have their asset IDs recorded in metadata.

Keep production runtime templates under `ServerStorage.ServerAssets`. Put inactive source templates,
place backups, and future Mythling models under `ServerStorage.Authoring`; runtime services must
never search that folder. Keep editor-only model data such as `InitialPoses` and `AnimSaves` under
`ServerStorage.Authoring.Mythlings.<ModelName>` so it is not cloned into the runtime world.
`ServerStorage.ServerAssets.RBX_ANIMSAVES` is retained in place as Roblox Animation Clip Editor
authoring data and is not a production asset or legacy code.

### Environment model interiors

Use the following role folders inside each authored island, individual bridge, Arena structure,
and other substantial environment model. Create a folder only when it has content:

- `Visuals`: visible geometry, retaining imported model roots and reusable submodels intact.
- `Collision`: dedicated invisible collision parts. Existing visible meshes that also supply
  collision may stay in `Visuals`; moving a part into a folder never changes its physics settings.
- `Effects`: standalone effect carriers, beams, and ambient effect groups. Lights, emitters, and
  attachments that depend on visible geometry stay attached to that geometry under `Visuals`.
- `Markers`: invisible authored gameplay reference points.

Folders group roles; Models identify objects that can be moved as a unit. Apply this convention at
the environment model boundary, not recursively to every imported submodel or single-part prop.
Preserve model pivots, geometry transforms, attributes, tags, and effect attachment references when
reorganizing. Character rigs, Equipment, and runtime Base templates retain their own service
contracts rather than adopting the environment folder layout.

Base placement reads `World.BaseIslands.BaseIsland<N>.Collision.Grass`; loading readiness checks
the island's `Visuals` separately. The Arena's dedicated surfaces live under
`World.Arena.Collision`, with its imported geometry under `World.Arena.Visuals.RBX_Arena_Root`
and its floating foundation under `World.Arena.Visuals.FloatingIsland`. Its non-colliding gameplay
boundary is `World.Arena.Markers.Bounds`; `MainServer` passes that BasePart as
`context.Instances.Arena` so gameplay services continue using the same boundary geometry.

### Runtime-only content

- Objects created for a live server session belong under `Workspace.Runtime` and must never be
  authored, persisted, or synced back through Rojo.
- Player save data belongs only in the server data framework. Do not store it in replicated
  Instances, attributes, source modules, or Studio mock objects.
- Temporary combat state, cooldowns, capture progress, active effects, and spawned encounters remain
  server-owned memory unless the data contract explicitly marks a client-safe projection.

For mixed Studio/Rojo parents such as `Workspace.World`, its mapped collection folders, and
`ServerStorage.ServerAssets`, use `$ignoreUnknownInstances` deliberately so Rojo preserves
Studio-authored children. Rojo owns the mapped container and source-backed descendants; Studio owns
only the explicitly documented unknown descendants.

Rojo owns `TextChatService.AdminCommand`, including its enabled `/admin` alias. The service preserves
other chat descendants with `$ignoreUnknownInstances` so Roblox's chat configuration and default
commands remain intact. `AdminCommandService` owns its server handler; island landing markers stay
with the Studio-authored environment models and are not generated or repositioned by Rojo.

`ReplicatedStorage.Network`, `ReplicatedStorage.Shared`, `ReplicatedStorage.Packages`,
`ServerScriptService`, and `StarterPlayerScripts` are strict Rojo-owned code boundaries. Unknown
descendants there are architectural drift and are removed by a clean sync; Studio-authored content
belongs only in the documented mixed-ownership containers.

The generated root `Packages/` directory maps to `ReplicatedStorage.Packages` and contains shared
Wally dependencies. Server-only vendored libraries stay under `src/ServerScriptService/Packages`;
server-only Jest dependencies map under `ServerStorage.Tests` only in the disposable
`test.project.json` build. See [dependencies](#dependencies).

## Dependencies

These facts are verified from repository manifests, lockfiles, source headers, and Rojo mappings:

| Dependency | Repository record | Ownership |
| --- | --- | --- |
| Rojo 7.7.0, Wally 0.3.2, Selene 0.31.0, StyLua 2.5.2, luau-lsp 1.70.0, wally-package-types 1.6.2 | [aftman.toml](../aftman.toml) | Development toolchain |
| Fusion 0.3.0 and Trove 1.8.0 | [wally.toml](../wally.toml), [wally.lock](../wally.lock) | Generated shared `Packages/` |
| Jest and JestGlobals 3.20.0 | [test manifest](../tests/wally.toml), [test lockfile](../tests/wally.lock) | Server-only test packages |
| ProfileStore | [vendored source](../src/ServerScriptService/Packages/ProfileStore.luau) | Server-only package; its header credits MAD STUDIO / loleris |

An exact upstream revision and local-change history for the vendored ProfileStore file are not
established here. Do not infer either from its credit header. Generated packages and built place
files are not hand-edited; use the installation and verification workflow in the
[README](../README.md).

## Implementation alignment

This is a bounded list of prototype differences verified against source on 2026-09-08. Update or
remove each item when the implementation is aligned; these notes do not authorize new gameplay.

| Area | Current source | Target contract / required alignment |
| --- | --- | --- |
| Player document | [PlayerDataTemplate](../src/ServerStorage/Databases/PlayerDataTemplate.lua) uses schema 7 with initial Gold, Inventory upgrades, transactions, crafting reservations, and Base ownership; recurring Equipment/loadout defaults are empty. [ProfileSchema](../src/ServerScriptService/Services/DataService/ProfileSchema.lua) stages one-time protected starter grants only for clearly untouched initialization state, preserves established/ambiguous data and chosen empty slots, and retains the existing v4–v6 layout/accounting upgrades. New Crafting Jobs add versioned receipts without reconstructing legacy payment history. | Add remaining atomic feature mutations and replace prototype form consumers separately. Schema preparation awards no work and does not prove durable persistence. The deliberate fresh namespace is not permission to reset subsequent progress, regrant missing items, or invent job payments. |
| Base foundation | [BaseState](../src/ServerScriptService/Shared/BaseState.lua) derives two initial Shrine-only slots and four configurable one-slot expansions from purchased state. Load initializes one free, unique Station identity; [BaseRuntime](../src/ServerScriptService/Services/BaseService/BaseRuntime.lua) binds it to the existing authored `PB_CraftingStation_Root` model. `base.status`, allowlisted `base.shrines`, and world attributes expose presentation state, not purchase authority; headless crafting validates that saved Station identity. | Add Station interaction separately. Keep `base.stands` and its existing placement/collection paths functional until the replacement can preserve their earned work. Authored Shrine markers/models remain separate work; the Shrine asset is provisional. |
| Base expansion and build offers | `BaseService.GetBase` uses private [BaseView](../src/ServerScriptService/Services/BaseService/BaseView.lua) to return detached capacity, owned Shrine summaries, six build offers, and the next expansion quote or explicit maximum state. [BaseRequests](../src/ServerScriptService/Services/BaseService/BaseRequests.lua) admits GetBase/BuildShrine/ExpandBase; [BaseAccess](../src/ServerScriptService/Services/BaseService/BaseAccess.lua) checks fresh actions against the caller's live Base and configured anchor. Owning modules share read-only eligibility and revision-bound payments; ExpandBase preserves layout, accounting, Station identity, and reservations. | Place the explicit Base anchor and add prompt/GUI integration separately; verify connected-player dispatch and durable retention. Reads never settle or spend; retries never recheck world access or refresh attributes. No world placement, schema migration, Station charge, or production multiplier is added; duplicates remain valid and only collected Materials can pay. |
| Shrine construction | [ShrineConstruction](../src/ServerScriptService/Services/BaseService/ShrineConstruction.lua), exposed through admitted `Network.Base.BuildShrine`, atomically charges 100 configured Gold for any of six elemental level-1 Shrines and allocates the lowest free logical slot. Saved records contain identity, definition, slot, level, and empty `stored`/`progress`/`newWork`/`workerIdsBySlot` fields. Construction leaves the common clock unchanged; projection exposes only identity, definition, slot, and level. | No menu binding or Shrine model spawning is added. Supply the Base anchor and complete player-facing integration separately; assignment, collection, upgrade, dismantling, and the production lifecycle share its canonical records. |
| Profile transactions and durability | [DataService](../src/ServerScriptService/Services/DataService/init.lua) supplies detached, non-yielding `Transact`/`Update` commits and bounded revision-bound receipts. [MutationPreparations](../src/ServerScriptService/Services/DataService/MutationPreparations.lua) resolves registered draft work before an admitted mutation with one shared timestamp and rollback boundary. [ProfileSettlements](../src/ServerScriptService/Services/DataService/ProfileSettlements.lua) runs Ready/Checkpoint/Release hooks before publication or finalization. `SaveNow` checkpoints before requesting ProfileStore's asynchronous save. | Move remaining prototype Base writers when replacing their features; their `MarkDirty` writes run neither preparation nor rollback. Loadout changes now use transactions. Runtime success, an in-memory checkpoint, or `SaveNow == true` still does not prove durable persistence. Playtest real session/shutdown/save ordering. |
| Material catalogue | [Materials](../src/ReplicatedStorage/Shared/Configurations/Materials.lua) contains six launch-enabled element-based IDs, configured 10/2-Gold buy/sell prices, and the shared 1,000-unit stack limit. [Shrines](../src/ReplicatedStorage/Shared/Configurations/Shrines.lua) maps each output to its matching Material. [MaterialCatalogUtil](../src/ServerScriptService/Shared/MaterialCatalogUtil.lua) validates the catalogue before server services start. Prototype Material metadata remains with `launchEnabled = false`; prototype runtime paths are unchanged. | Final display names/icons remain open. Canonical production, collection, paid upgrades, Material-sale/discard, and crafting commands use these references; integrate Shop separately. Metadata alone adds none of those actions. |
| Material sales and discard | `InventoryService.SellMaterial`/`DiscardMaterial` and their matching admitted Inventory endpoints delegate to private [MaterialDisposalCommand](../src/ServerScriptService/Services/InventoryService/MaterialDisposalCommand.lua). One revision-bound `DataService.Transact` validates the exact owned quantity and configured sale quote, removes only the selected owned amount, and grants sale Gold or zero for discard. Receipts prevent repeated removal/payment, and [GoldCreditUtil](../src/ServerScriptService/Shared/GoldCreditUtil.lua) protects recorded cancellation headroom. | Add player-facing confirmation and verify connected-player dispatch and durable retention separately. Only enabled normal Materials are eligible; valid over-capacity inventories can recover space. The command never consumes reservations or uncollected output; shared preparation may resolve due jobs atomically before it. |
| Inventory capacity | Server-shared [InventoryCapacity](../src/ServerScriptService/Shared/InventoryCapacity.lua) derives category limits, per-type 1,000-unit stacks, and active job reservations. `InventoryService.UpgradeCapacity` and its admitted Inventory endpoint delegate to [CapacityUpgradePurchase](../src/ServerScriptService/Services/InventoryService/CapacityUpgradePurchase.lua), atomically purchasing the selected category's next +12 slots with Gold and the fixed six-Material mix. [UpgradePaymentUtil](../src/ServerScriptService/Shared/UpgradePaymentUtil.lua) shares Base/Inventory payment validation, including ingredient capacity before the grant and preserved refunds. | Add player-facing integration and validate connected-player dispatch/durable retention. Crafting consumes the same reservation accounting; capacity purchases themselves do not grant output or spend a reservation. No GUI, schema migration, Shop allowance use, or refresh reset is added. |
| Mythling form catalogue | [MythlingForms](../src/ReplicatedStorage/Shared/Configurations/MythlingForms.lua) defines 18 permanent neutral IDs, six complete launch chains, and explicit Yield, sale, capture, rarity, and evolution metadata. [MythlingCatalogUtil](../src/ServerScriptService/Shared/MythlingCatalogUtil.lua) validates the business catalogue; spawn initialization also compiles its configured 75/20/5 selection pool and validates every form's capture/lifetime policy. Canonical grants, Shrine commands, evolution, and sales consume these IDs. See [spawn selection and lifetime policy](#arena-spawn-selection-and-lifetime-policy). | Finalize creative names/concepts/assets and bind the live canonical pool separately. Validated asset-independent selection and lifetimes do not activate launch models or replace the three live prototype forms. No model/radius substitution or menu is supplied; ownership changes remain transactional. |
| Capture grants | Server-only `InventoryService.SaveWonMythling` retains its loaded Inventory-session gate and delegates to private [CaptureGrant](../src/ServerScriptService/Services/InventoryService/CaptureGrant.lua). It validates supported selection, generated identity/time, and capacity before granting the exact canonical form at level 1, XP 0, and pending XP 0 through `DataService.Update`. No Luck/Trait roll or static metadata is copied into the new record; configured prototype captures remain supported temporarily. | ClaimService supplies contest-level award uniqueness; the grant is not a retryable client endpoint. Canonical model bindings and live spawn selection remain separate work. Validate connected-player capture and durable saves; injected/serialized tests and asynchronous save requests do not establish them. No GUI, remote, or schema migration is added. |
| Mythling production | Existing [ProductionService/Accrual](../src/ServerScriptService/Services/ProductionService/Accrual.lua) retains prototype [ProductionLedger](../src/ServerScriptService/Shared/ProductionLedger.lua) behavior. Canonical [ProfileProduction](../src/ServerScriptService/Services/ProductionService/ProfileProduction.lua) settles Ready/Checkpoint/Release through shared [ShrineAccounting](../src/ServerScriptService/Shared/ShrineAccounting.lua), with [ProfileCheckpoints](../src/ServerScriptService/Services/ProductionService/ProfileCheckpoints.lua) initially scheduling loaded-profile checkpoints every 30 seconds. Server-only `SettleShrines` and atomic assignment/collection/upgrade/dismantling/evolution/sale commands use the same accounting engine in their own transactions. | Integrate remaining features and player-facing views separately. Keep settlement and input changes in one draft; legacy stand paths and inactive Luck/Traits remain unchanged. The private clock and pending XP stay out of projection. Mock/serialized tests and asynchronous save requests do not establish live durable persistence; validate join/leave/shutdown and reconnect behavior in play. |
| Shrine management view | `BaseService.GetShrine` and its admitted Base endpoint use [ShrineView](../src/ServerScriptService/Services/BaseService/ShrineView.lua) and the shared read-only accounting snapshot to return detached worker slots/candidates, committed storage/progress and nominal production estimates, collection room, upgrade quotes, and dismantle eligibility. World access follows revision/request validation and precedes projection; the read never settles or saves. | Supply permanent slot anchors and prompt/GUI integration separately; verify connected-player interaction and durable retention. Previews are not guaranteed mutation results: real actions settle and revalidate. No raw clock/work/XP ledger, inactive Luck/Traits, prototype conversion, authored placement, or menus are added. |
| Shrine assignment | `BaseService.AssignShrineWorker`/`RemoveShrineWorker` and their admitted Base endpoints delegate to private [ShrineWorkers](../src/ServerScriptService/Services/BaseService/ShrineWorkers.lua). It uses [ShrineAssignments](../src/ServerScriptService/Services/BaseService/ShrineAssignments.lua) and the shared adapter to check fresh world access, settle, and mutate canonical state in one revision-bound transaction. Explicit unassignment, empty matching slots, stable slot identities, expected-worker checks, and duplicate-safe receipts are enforced. | Complete authored slot bindings and player-facing integration separately; playtest connected-player dispatch and durable saves. No acquisition, schema migration, model, or presentation is added. Every admitted legacy `DeleteMythling` request returns nonmutating `UnsupportedAction`, without unassignment or deletion. |
| Shrine collection | `ProductionService.CollectShrine` and its admitted Production endpoint delegate to private [ShrineCollector](../src/ServerScriptService/Services/ProductionService/ShrineCollector.lua), with a required production Base-access guard and separate configured twelve/four admission budget. [ShrineCollection](../src/ServerScriptService/Services/ProductionService/ShrineCollection.lua) and the shared storage bridge settle work/XP and commit the stored debit with the Inventory grant in one revision-bound transaction. Partial transfers retain excess and unfinished work; receipts prevent replayed grants. | Complete authored slot bindings and player-facing integration separately; playtest connected-player dispatch and durable saves. No schema or presentation is added. Prototype collection, crafting reservations, and automatic production remain unchanged; automatic settlement never requires proximity. |
| Shrine upgrades | `BaseService.UpgradeShrine` and its admitted Base endpoint delegate to private [ShrineUpgradePurchase](../src/ServerScriptService/Services/BaseService/ShrineUpgradePurchase.lua). It composes fresh access checks, [ShrineUpgrades](../src/ServerScriptService/Services/BaseService/ShrineUpgrades.lua), and the shared sequential-level bridge inside one revision-bound transaction, settling at the old capacity and committing collected Material/Gold payment and exactly the next level together. Real launch metadata owns prices, capacity, slots, and output IDs; quote-bound receipts prevent replayed charges. | Complete authored slot bindings and player-facing integration separately; playtest connected-player dispatch and durable saves. No schema, automatic lifecycle, or presentation is added. Assignments, stored output, earned work/XP, other currency fields, and crafting reservations remain intact. |
| Shrine dismantling | `BaseService.DismantleShrine` and its admitted Base endpoint delegate to private [ShrineRemoval](../src/ServerScriptService/Services/BaseService/ShrineRemoval.lua). It composes fresh access checks, [ShrineDismantling](../src/ServerScriptService/Services/BaseService/ShrineDismantling.lua), and the shared removal bridge inside one revision-bound transaction, rejecting workers or settled whole output before removing the selected record. Unfinished work is discarded without erasing owned workers or pending XP; identity/level-bound receipts protect replacements. Fresh success refreshes Base capacity attributes; replay skips the refresh and profile reread. | Complete authored slot bindings and player-facing integration separately; playtest connected-player dispatch and durable saves. No schema, automatic lifecycle, or presentation/model deletion is added. Purchased slots, surviving accounting, Station identity, currency, Materials, and crafting reservations remain intact; no refund is granted. |
| Shrine world access | [ShrineAccess](../src/ServerScriptService/Services/BaseService/ShrineAccess.lua) resolves the saved Shrine `buildSlotId` to its own server-owned Base's unique `ShrineSlots/SlotN/ShrinePromptAttachment` binding, requiring an anchored slot part and living character within four studs. All six slots are supported, without prototype/model/client fallbacks. Fresh mutation guards run after receipt/revision admission and shared preparation, before feature clocks/accounting; committed retries skip world checks, preparation, and clocks/accounting. See [Shrine endpoints and world access](#shrine-request-endpoints-and-world-access). | The inspected Studio template lacks `ShrineSlots`; fresh interactions fail closed until asset/UI work supplies the permanent anchors. Prompt/menu movement locking and visual placement remain separate work. Disposable tests establish access/replay/rollback behavior, not positive connected-player dispatch or durable persistence. |
| Mythling evolution | `InventoryService.EvolveMythling` and its admitted Inventory endpoint delegate to private [MythlingEvolutionCommand](../src/ServerScriptService/Services/InventoryService/MythlingEvolutionCommand.lua). It composes [MythlingEvolution](../src/ServerScriptService/Services/InventoryService/MythlingEvolution.lua) with the shared form-change bridge and canonical launch links inside one revision-bound `DataService.Transact`. Old-form settlement, eligibility, selected `typeId`, and identity/form/target-bound receipts commit together. Assigned and consecutive eligible evolutions retain work, progression, inactive legacy fields, and batch timing. | Add player-facing integration separately and playtest connected-player dispatch and durable saves. No menu, acquisition grant, schema migration, or automatic lifecycle is added. Prototype capture/stand paths remain unchanged; pending XP stays private. |
| Mythling sales | `InventoryService.SellMythling` and its admitted Inventory endpoint delegate to private [MythlingSaleCommand](../src/ServerScriptService/Services/InventoryService/MythlingSaleCommand.lua). It composes [MythlingSales](../src/ServerScriptService/Services/InventoryService/MythlingSales.lua) and the shared worker-removal bridge with canonical sale definitions inside one revision-bound `DataService.Transact`. Unassignment and stale form/price checks protect the selected deletion and Gold grant; final-copy sales remain allowed. All earned Shrine work and surviving workers' XP are retained, while the sold instance's pending XP retires. | Add player-facing integration separately and playtest connected-player dispatch and durable saves. The legacy `DeleteMythling` endpoint returns nonmutating `UnsupportedAction` after admission, without unassignment or ownership access; it is not a sale API. Materials and crafting reservations remain unchanged. No menu, acquisition grant, or schema migration is added. |
| Equipment sales | `InventoryService.SellEquipment` and its admitted Inventory endpoint delegate to private [EquipmentSaleCommand](../src/ServerScriptService/Services/InventoryService/EquipmentSaleCommand.lua). One revision-bound transaction checks ownership, exact definition/finish/price, starter protection, and both loadout slots before removing the selected item and crediting configured Gold while preserving refund headroom. | Add player-facing confirmation and verify connected-player dispatch and durable retention separately. Equipped or protected starter items remain unsellable; no automatic unequip, GUI, asset binding, or schema migration is added. |
| Equipment catalogue | [Equipment](../src/ReplicatedStorage/Shared/Configurations/Equipment.lua) defines the wooden pair and twelve named elemental items through shared bases and explicit finishes. [EquipmentCatalog](../src/ReplicatedStorage/Shared/EquipmentCatalog.lua) resolves fixed item metadata by IDs; recipes/effects have separate static owners and startup validation. Headless crafting, Shop grants, server combat, and client attack/guard input use canonical definitions. Private [EquipmentSelection](../src/StarterPlayer/StarterPlayerScripts/Controllers/CombatController/EquipmentSelection.lua) binds predicted actions to exact replicated identities and mounted objects; preview/VFX consumers retain the compatibility map. | Bind approved assets separately; empty crafted model names cannot authorize combat and never select a wooden fallback. Live multiplayer and animation/replication behavior remain unverified. No GUI or saved-stat copy is added. |
| Atomic loadout | [LoadoutCommands](../src/ServerScriptService/Services/CombatService/LoadoutCommands.lua) implements revision-bound EquipEquipment/UnequipEquipment through the public CombatService API and matching canonical remotes. [LoadoutRequests](../src/ServerScriptService/Services/CombatService/LoadoutRequests.lua) shares admission across these routes, read-only GetLoadout, and legacy Equip; all three mutation routes share the configured cooldown. The legacy endpoint retains its snapshot response and server-generated request identity. [LoadoutUtil](../src/ServerScriptService/Services/CombatService/LoadoutUtil.lua) binds saved, mounted, guard, and swing identities to instance/definition/finish. Fresh changed commits retain Stamina, action deadlines, and elemental effects; replay/no-op results skip runtime reconciliation. | Add client command integration separately and verify connected-player dispatch, live transition/reset behavior, and durable selections. No GUI or playable crafted assets are supplied; unbound models fail closed. |
| Crafting Jobs | [CraftingService](../src/ServerScriptService/Services/CraftingService/init.lua) supplies admitted GetStation/StartJob/CancelJob remotes through [CraftingRequests](../src/ServerScriptService/Services/CraftingService/CraftingRequests.lua). Commands retain revision-bound receipt replay; BaseService checks fresh actions against the caller's live Base and configured Station anchor. [CraftingJobs](../src/ServerScriptService/Services/CraftingService/CraftingJobs.lua) owns detached views, recorded promises, capacity reservations, and exactly-once resolution. Automatic settlement never requires proximity. | Place the explicit authored Station anchor and add its prompt/menu integration separately. Legacy reservation-only jobs remain opaque and block starts when active; no refund history is invented. No GUI, model fallback, or auto-equip is added. Verify connected-player interactions and durable retention independently of session-atomic tests. |
| Stamina and Shield | [CombatService](../src/ServerScriptService/Services/CombatService/init.lua) uses server-owned guard phases and swing deadlines, lowered-only recovery, full-cost blocks, minimum guard Stamina, and immediate protection loss. [CombatState](../src/ServerScriptService/Services/CombatService/CombatState.lua) accounts for Fire drain alongside recovery and guard transitions. Marker sequences and transition timeouts bound cleanup; loadout changes retain these accounting deadlines and never refill Stamina. Client input resolves canonical variants and preserves release/lowering cleanup after a selection changes. | Tune authored animations and transition timing in multiplayer/touch playtests. Approved crafted asset bindings and live effect/guard interaction validation remain outstanding. |
| Elemental combat | [ElementalHits](../src/ServerScriptService/Services/CombatService/ElementalHits.lua) integrates the six configured effects after accepted-hit and block decisions. CombatState owns snapshotted deadlines, first-effect-wins occupancy, Earth landing/recovery state, and immediate Air/Light/Dark arithmetic. [EarthLanding](../src/ServerScriptService/Services/CombatService/EarthLanding.lua) supplies bounded server support observations; [MovementRestrictions](../src/ServerScriptService/Services/CombatService/MovementRestrictions.lua) composes current voluntary movement rules without changing forced motion or collisions. | Verify server-observed takeoff/landing, effect persistence, movement composition, and force/Stamina behavior in live multiplayer. Client effect presentation and approved crafted bindings remain separate; this implementation adds no GUI or asset activation. |
| Arena spawning | [MythlingSpawnService](../src/ServerScriptService/Services/MythlingSpawnService/init.lua) compiles detached canonical and prototype pools through [SpawnSelection](../src/ServerScriptService/Services/MythlingSpawnService/SpawnSelection.lua), with weighted rarity and uniform sorted forms. [SpawnLifetimeUtil](../src/ServerScriptService/Services/MythlingSpawnService/SpawnLifetimeUtil.lua) validates both catalogues' defaults/overrides, capture slack, and safe activation deadlines. Live selection still uses explicit prototype 100/50/15 weights. The service prefills 12 before capture, retains each replacement selection across retries with a three-second deadline, and fixes lifetimes at activation; ClaimService owns expiry/overtime. See [policy details](#arena-spawn-selection-and-lifetime-policy). | Author approved model/radius bindings, activate the neutral launch IDs, and verify their configured 75%/20%/5% distribution and equal element chances in play. Deadline and headless selection validation do not establish asset readiness or sufficient map arrival time. Configure the published experience for eight players; the inspected development place still allows 60. Validate full-server refill and boundary clearance before release. |
| Capture meters | [ClaimService](../src/ServerScriptService/Services/ClaimService/init.lua) retains independent meters with equal-rate decay, finite-height membership, visit tie priority, capacity checks, reset cleanup, and ordered completion/expiry. Full inventories retain occupancy without progress. | Validate multiplayer displacement and tie cases on the authored map alongside the launch roster. Connect the server-only capacity purchase to its player-facing flow and complete the remaining progression loop separately. |
| Menus and deferred features | [UI screens](../src/StarterPlayer/StarterPlayerScripts/UI/Screens) include `Stand` and `Hotbar`; the prototype inventory/data layer includes Consumables. | Launch UI follows [UI guidelines](UI_GUIDELINES.md): Shrine terminology, three Inventory categories, no Consumables/Hotbar placeholders, and jobs shown at their station. Preserve saved prototype data while deferring those surfaces. |
| Shop | [ShopService](../src/ServerScriptService/Services/ShopService/init.lua) returns read-only offers/eligibility/upgrade quotes and revision-bound atomic purchases through its public API and the declared `Shop.GetShop`/`BuyOffer` endpoints. [ShopRequests](../src/ServerScriptService/Services/ShopService/ShopRequests.lua) admits callers before protected work and keeps refreshed quotes separate from recorded transaction results. A shared hourly schedule rotates the matching Featured pair; saved personal usage is independent of catalogue revisions and purchased upgrades. | Add menu integration and verify connected-player dispatch, live refresh boundaries, and durable retention separately. No GUI, asset activation, automatic equip, XP, or refresh timer is added. Future tuning must be deployed at a shared period boundary. |
| Feature endpoints and transactions | [default.project.json](../default.project.json) exposes typed Shop and Crafting endpoints, eight canonical Base routes including Shrine read/assignment/removal/upgrade/dismantling, separate Production.CollectShrine, six Inventory actions, and retryable Combat EquipEquipment/UnequipEquipment resolved by [RemoteUtil](../src/ServerScriptService/Infrastructure/RemoteUtil.lua). All eight Base routes share twelve/four admission; canonical Production collection has its own twelve/four budget, with legacy budgets unchanged. Adapters admit genuine connected callers before protected work and forward unchanged requests/results to command owners; the retained delete endpoint never mutates. | Supply required authored access bindings and integrate GUI callers separately. Existing server commands and disposable endpoint tests do not by themselves establish positive connected-player dispatch or durable-save guarantees. Preserve bounded results without exposing private receipts, profiles, or extra loadout snapshots. |
| Authored gameplay assets | [MainServer](../src/ServerScriptService/MainServer.server.lua) requires authored `Workspace.World.Arena.Markers.Bounds`, Base Islands, and model templates that are not supplied by a clean source build. | Use the existing authored development place for gameplay checks. A successful Rojo build verifies source mappings, not asset completeness or playable readiness; see [README](../README.md#getting-started). |

`HUDGui`, `StaminaGui`, `InventoryGui`, `ShopGui`, `StandGui`, `HotbarGui`, `CombatActionGui`,
`ModalBackdropGui`, and `ToastGui` are current application-owned roots under `PlayerGui`.
`StaminaGui` is composed by the HUD; its display layer must not require an active Hotbar. Legacy
`StandGui`/`HotbarGui` names record prototype status rather than authorizing launch features.
`StarterGui` remains intentionally empty and strictly Rojo-owned.
