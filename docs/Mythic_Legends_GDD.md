# Mythic Legends — Game Design & Implementation Specification

## 1. Product vision

**Mythic Legends** is a mobile-first Roblox creature-collection, base-production, and competitive arena game. Players win Mythlings through a public king-of-the-hill capture arena, assign them to elemental shrines at their bases, collect produced resources, craft arena equipment and consumables, and upgrade their shrines.

The intended visual style is bright, readable, low-poly fantasy: a circular public arena sits at the center of a sky-island world, surrounded by highly distinct elemental landmarks. The supplied concept art is visual direction, not a requirement to reproduce every depicted creature or structure.

## 2. Launch scope

### Included in the current MVP

- Central-arena Mythling capture through king-of-the-hill contests.
- Elemental player bases and upgradeable shrines.
- Online and offline shrine production.
- Mythling levels, evolutions, and one rolled Passive Trait per acquired Mythling.
- Crafting Stations with queued, time-based recipes for arena weapons, shields, and approved consumables.
- Shop purchases and shrine upgrades paid for with gold and required resources.
- Developer-run live events.
- Limited player-initiated Divine Intervention events for players with a verified Event Caller entitlement.

### Explicitly excluded

- Eggs, summoning, gacha, and Elemental Prism capture items.
- A separate health/damage-based PvP brawl mode, matchmaking, rankings, and ranked rewards.
- Mythling treats, health, and attack until a separate progression design is approved.

Arena capture is launch PvP, but it is **non-lethal positional PvP**: the goal is to control a capture ring through knockback and defense, not to defeat another player through health damage.

## 3. Canonical terminology

| Term | Meaning |
| --- | --- |
| Mythling | A collectable mythological creature that can be captured and assigned to a shrine. |
| Arena | The central public location where wild Mythlings spawn and players compete to capture them. |
| Capture Ring | The circular king-of-the-hill area surrounding one spawned Mythling. |
| Base | A player-owned area containing their shrines. |
| Shrine | An element-specific production building at a base. It has upgradeable slots and shared storage. |
| Shrine Slot | One assignment space in a shrine. It holds one matching-element Mythling. |
| Yield | A Mythling stat that contributes normal resource output per hour while assigned to a shrine. |
| Luck | A Mythling stat that contributes to a shrine's combined Lucky Yield chance. |
| Passive Trait | One random, persistent passive assigned when a Mythling is acquired. |
| Evolution | Replacing a Mythling's current form with a new Mythling definition that has its own base statistics. |
| Resource | A crafting and upgrade material produced by a shrine. |
| Gold | The primary currency, earned principally from selling duplicate Mythlings and spent in shops and upgrades. |
| Weapon | Arena equipment that applies positional knockback. |
| Shield | Arena equipment that protects against or reduces positional knockback. |
| Crafting Station | A base building that runs a level-limited queue of time-based crafting jobs. |
| Hotbar | The player's six equipment slots, including the default weapon and shield. |
| Stamina | A player resource consumed by arena weapon actions and by shield impacts; it recovers gradually over time. |

Do not use *forge*, *altar*, or *pet* as alternative names for shrines or Mythlings in player-facing text.

## 4. Elements and rarity

### Elements

The only launch elements are **Fire, Water, Earth, Air, Light, and Dark**. Every Mythling and Shrine has exactly one element. A Mythling can be assigned only to a shrine with the same element.

### Rarities

Rarities are ordered from lowest to highest:

1. Common
2. Rare
3. Epic
4. Mythical
5. Divine

Rarity affects content balance and presentation only as specified in content configuration. It must not imply a different element.

### Visual language

- Fire: orange/red, lava, embers.
- Water: blue, ice, crystal, flowing water.
- Earth: green, wood, stone, foliage.
- Air: pale cyan, clouds, wind, floating rock.
- Light: white/gold, beams, wings, radiant stone.
- Dark: black/purple, shadow, violet crystals.

The central arena must remain visually readable on mobile. Launch tuning should keep only a small number of simultaneous contested Mythlings active, even if the environment contains many decorative Mythlings or landmarks.

## 5. Mobile controls and accessibility

- **Left thumb:** Roblox movement thumbstick and a stationary Interact/Utility button.
- **Right thumb:** follow-camera drag and a primary arena-action button for equipped weapon or shield actions.
- Every new player receives a plain wooden sword and wooden shield. The player hotbar has six equipment slots.
- The Hotbar is displayed along the bottom of the screen, consistent with familiar Roblox inventory placement.
- Arena actions must be reachable while moving and must not require precise taps on a Mythling.
- The HUD provides Inventory and Shop buttons. Players access Base, Shrine, and Crafting Station interactions through nearby Proximity Prompts.
- All important capture state is communicated through legible ring, progress, and ownership indicators; color is never the only signal.
- Live events must respect Reduce Motion and sound settings. Reduce Motion replaces screen shake and flashing with static, non-flashing notifications.

## 6. Arena capture

### Capture flow

1. Wild Mythlings spawn in the central Arena.
2. Each spawned Mythling creates one visible Capture Ring around itself. Capture Rings must never overlap.
3. A player whose Mythling inventory has available space may build their own capture meter while inside the Capture Ring. A player with full Mythling inventory cannot begin or gain capture progress for that Mythling.
4. A player's meter increases at `CaptureProgressPerSecond` while that player is inside the ring.
5. A player's meter decays at `CaptureDecayPerSecond` while that player is outside the ring.
6. Arena weapons consume Stamina and can knock competing players out of a Capture Ring. Shields greatly reduce knockback, but an incoming shield impact consumes Stamina.
7. The first player whose meter reaches 100% captures the Mythling. The server grants that Mythling to the winner, removes the contested spawn, and clears all other progress for that contest.
8. An unclaimed Mythling despawns after its configured lifetime.

### Arena rules

- Each Mythling is an independent contest; capture progress is never shared between players or between Mythlings.
- The Arena spawn system must select a different valid position or delay a spawn rather than create an overlapping Capture Ring.
- Mythling inventory capacity is checked by the server before capture progress begins and again before capture is awarded.
- The server is authoritative for player position, Capture Ring membership, progress, weapon/shield effects, winner selection, and rewards.
- Arena combat does not deal damage or cause player death. Knockback, ragdoll, and configured elemental effects create the positional disruption used in Capture Ring contests.
- The client may display predicted feedback, but it may never award a Mythling or determine a winner.
- Capture progress, ring radius, spawn frequency, active-spawn cap, despawn time, knockback strength, shield behavior, and equipment cooldowns are balance configuration—not hard-coded client values.

## 7. Bases, shrines, and production

### Shrine rules

- A Shrine has one `elementId` and one assigned `resourceId`.
- A Shrine accepts only Mythlings with the same `elementId`.
- A Shrine has an upgradeable level, a maximum number of slots, and one shared storage capacity.
- Each occupied Shrine Slot adds the assigned Mythling's Yield and Luck to that Shrine.
- A Shrine upgrade may increase its slot count, shared storage capacity, and configured production multiplier.

Every new player starts with a Base, no Shrines, no Mythlings, no resources, and a configured amount of Gold. Shrines are added through Base upgrades; the player must be able to buy or unlock their first Shrine using the starting state.

The Shrine owns the produced resource. Mythlings provide the speed and Lucky Yield chance; they do not independently decide which resource the Shrine produces.

### Production calculation

```text
Total Yield Per Hour = sum(assigned Mythling Effective Yield) × Shrine Production Multiplier
Total Luck Chance = min(sum(assigned Mythling Effective Luck), Shrine Luck Cap)
```

Production is calculated in fixed, server-authoritative batches. While a shrine has available storage capacity, each batch adds its normal output. The shrine makes one Lucky Yield roll per batch using `Total Luck Chance`.

- At launch, a successful Lucky Yield roll doubles that batch's normal resource output.
- Production accrues while the player is offline.
- On join or collection, the server calculates elapsed batches from the saved accrual time, applies production and Lucky Yield rolls, clamps the result to shared Shrine capacity, and updates the saved state.
- Output never exceeds capacity. A full shrine stops accruing until the player collects output or increases capacity.

### Planned rare-resource extension

The launch implementation must preserve a configurable future outcome for a successful Lucky Yield roll. A later update may let the roll award a rare version of the Shrine's elemental resource instead of double normal output. For example, a Fire Shrine could produce a rare Fire-aligned material such as `Prismatic Ember`.

This is a **rare resource variant**, not a new element. It must use the Shrine's shared storage according to a configured storage-unit cost and must not bypass the capacity limit.

### Mythling progression and Passive Traits

Each Mythling has a current form, a level, XP, an individually saved Luck value, and one Passive Trait rolled when it is acquired. The current form's immutable base statistics come from Mythling metadata; only the Mythling's lightweight mutable state is saved to the player document.

- **Yield** starts from the current form's configured base Yield and increases through level-based configuration.
- **XP** is earned while a Mythling is assigned to and working in a Shrine. XP is awarded from server-authoritative production batches.
- The level cap is 100. Each level applies the same small, configurable Yield percentage increase to that Mythling's current form base Yield.
- **Evolution** replaces the Mythling's current form with a different Mythling definition. The evolved form has its own configured base Yield and other base statistics.
- Evolution requires reaching that Mythling form's configured target level. It never changes the Mythling's element, and its Passive Trait persists.
- **Luck** is an individually saved Mythling stat. Trait and level effects modify it into Effective Luck before the Shrine combines it with the other assigned Mythlings' Luck.
- A Mythling's Passive Trait applies only while the Mythling is assigned to an eligible Shrine, unless the Trait definition explicitly says otherwise.

Traits are production-focused only. Trait effects must be server-authoritative and data-driven. Launch examples:

| Trait | Effect |
| --- | --- |
| Insomniac | This Mythling contributes 20% more Yield while its owner is offline. |
| Lucky | Adds 3 percentage points to this Mythling's base Luck before combined Shrine Luck is calculated. |

Traits are selected from one universal, element-agnostic weighted pool. Traits must define their trigger, eligibility, and numerical effect. Do not let client-side code select, roll, or apply a trait.

## 8. Crafting, shop, and economy

### Crafting

Crafting Stations use Shrine resources to create approved weapons, shields, and consumables. All recipes are time-based Crafting Jobs. A Crafting Station's level determines its maximum job-queue capacity. Every recipe must define:

- `itemId` and category.
- Required resource quantities and required gold, if any.
- Unlock requirement.
- Stack or ownership behavior.
- Craft duration, eligible Crafting Station, and queue behavior.
- Arena effect, cooldown, and numerical tuning for weapons or shields.

Players may cancel a Crafting Job at any time for a full refund of every resource and Gold amount spent to start that job. Crafting is server-authoritative: the server verifies the recipe, affordability, unlock state, inventory capacity, queue capacity, cancellation/refund behavior, and result before deducting resources or granting an item.

### Gold and duplication

- Selling duplicate Mythlings is the main early-game source of Gold.
- Gold is spent in the shop and as part of Shrine upgrades.
- Shrine upgrades also require the relevant configured resources.
- A player must be able to capture a first Mythling without Gold.

### Inventory capacity and overflow

Every inventory category has a configured capacity. A player cannot receive a Mythling, item, weapon, resource, currency, or other inventory entry when its destination inventory has no available space.

- A player at Mythling capacity cannot begin or gain Capture Ring progress. The server sends an `InventoryFull` warning that identifies Mythlings as the blocked inventory category.
- A proximity pickup is not collected when the recipient's relevant inventory is full. It remains available according to that pickup's normal despawn and claim rules.
- Crafting checks and reserves output inventory space when a Crafting Job begins. A player cannot start a job if its output cannot be received.
- Shrine collection is rejected when the destination resource inventory is full; the Shrine retains its stored output.
- Every blocked acquisition produces a clear, server-authoritative warning that identifies the full inventory category and, when possible, the action needed to create space.

## 9. Live events

### Divine Intervention

**Divine Intervention** is the in-world name for high-energy, mythology-themed live events. Each event represents a god or mythological force showing its power, such as *Thor's Tempest*, *Poseidon's Deluge*, or *Hades' Eclipse*. The individual event name, rewards, effects, and presentation are configuration-driven.

Events can be started in two ways:

- **Scheduled events:** each server's `EventSchedulerService` independently selects one eligible event at random from a configured pool every hour.
- **Manual events:** players with the Event Caller Game Pass may start only caller-enabled events in their current server, no more than once every 30 minutes. The experience owner has additional controls to start an event in either their current server or all live servers.

### Event permissions and scope

| Role | Allowed activation scope | Allowed actions |
| --- | --- | --- |
| Scheduler | Its current server | Starts only configured scheduled events. |
| Event Caller | Their current server only | Starts only caller-enabled event definitions; one call per 30-minute cooldown. |
| Experience owner | Their current server or all live servers | Starts owner-only and caller-enabled events; may spawn a configured Mythling with explicitly selected rolled Luck and Passive Trait values. |

The owner role belongs to one configured Roblox `OwnerUserId`, stored in private server configuration. Event Caller Game Pass ownership and each caller's 30-minute cooldown are tracked separately from the owner role and validated server-side without trusting a client flag.

All event commands and owner overrides are server-side only. The client cannot supply an event ID, scope, Mythling ID, Luck, Trait, or reward value that bypasses the server's role, entitlement, allowlist, and content validation.

An owner Mythling spawn may choose a valid `mythlingId`, a valid individually rolled Luck value, and a valid `traitId`. It cannot override immutable base statistics such as element, rarity, visuals, or base Yield; those always resolve from the selected Mythling metadata. If a player wins the spawned Mythling, the selected Luck and Trait are saved on that owned Mythling entry.

### Event effects and rewards

An event may combine one or more configured effects:

- Spawn specific Mythlings, including temporary increases to rare-spawn odds.
- Add resource, currency, item, or weapon pickups to the Arena.
- Change Capture Ring conditions, such as ring size, capture speed, decay speed, or temporary environmental hazards.
- Grant temporary player or Shrine boosts.
- Grant permanent rewards, including Mythlings, rare Traits, and rare resources, only through configured and validated reward paths.
- Apply approved lighting, particles, special effects, sounds, and music.

Mythling rewards remain contested: players must win the spawned Mythling through the normal Capture Ring rules. Item, weapon, resource, and currency pickups are proximity-collected by walking over them. The server validates each collection, enforces a per-pickup claim policy, and prevents duplicate rewards.

Every event definition must declare its event name, enabled roles, activation scope, selection weight, duration, cooldown, scheduled eligibility, reward table, pickup rules, Mythling spawn table, Capture Ring modifiers, and presentation assets. Presentation effects run client-side, are optional, and must honor sound and Reduce Motion settings. Audio assets must be approved for use in the experience.

### Scheduler and cross-server behavior

`EventSchedulerService` runs on the server and selects only eligible, off-cooldown events. It must record an event instance ID, start/end time, and resolved reward/spawn configuration so every client in that server sees the same event state.

Scheduled events are independent per server. Players who join after an event begins receive the active event state and may participate normally until the event ends, subject to the same capture, pickup, and claim rules as other players.

All-server owner events require a server-to-server broadcast with an idempotent event instance ID. Each receiving server validates the owner-issued command and starts the same configured event exactly once. An Event Caller may never use an all-server scope, start an owner-only event, or set a Mythling's rolled Luck or Passive Trait.

Events may overlap. Events with dedicated music are mutually exclusive with other dedicated-music events; the Event Scheduler and manual activation controls must reject or defer a conflicting music event. Non-music presentation effects must use an explicit priority and cleanup rule so they restore the previous lighting and environment state when their event ends.

## 10. Content and technical contracts

### Content configuration

Content and balance data must be separate from game logic and versioned. At minimum, configuration defines:

- Mythling: `id`, display name, element, rarity, visual assets, form-specific base Yield, level-scaling data, evolution targets, and lore.
- Trait: `id`, acquisition weight, trigger, eligibility, numerical effect, and evolution-persistence behavior.
- Shrine: element, output resource, base storage, slot count by level, production multiplier by level, Luck cap, upgrade costs.
- Resource: id, element, display information, crafting uses, sell/buy values, and optional rare variant.
- Arena spawn: eligible Mythlings, rarity weights, ring radius, active cap, lifetime, and progress rates.
- Item and recipe: effect, crafting costs, unlocks, cooldowns, knockback/protection behavior.
- Live event: mythology-themed name, enabled roles, caller eligibility, scope, selection weight, schedule eligibility, duration, cooldown, reward/pickup tables, Mythling-spawn overrides, Capture Ring modifiers, and accessibility-safe presentation profile.

### Player save data

The persistent player document stores lightweight, mutable player state. It references static metadata by ID rather than duplicating names, descriptions, models, recipes, visual assets, or immutable base statistics.

An owned Mythling entry must contain at least:

```text
id                 -- unique owned-Mythling instance ID
mythlingId         -- current Mythling-form metadata ID
level
xp
luck               -- individually rolled, mutable Luck value
traitId            -- Passive Trait metadata ID
acquiredAt
assignedShrineId   -- optional
assignedSlotId     -- optional
```

Evolution updates `mythlingId` to the evolved form's metadata ID. The saved entry stays small while the game resolves the current form's base Yield and other immutable data from metadata.

Other inventory entries follow the same rule: store an instance ID, a metadata ID, and only mutable state such as quantity, durability, acquisition data, equipped state, or unique rolled values.

The player document must also contain:
- Base and Shrine state, including levels, slots, stored resources, and last production-accrual time.
- Resource and Gold balances.
- Crafted equipment and consumables.
- Event Caller Game Pass ownership and the caller's most recent event-call time.
- Unlock and tutorial flags.
- A schema version and forward-only migrations.

The server validates every client request that changes inventory, currency, equipment, production, capture, or event rewards. Persistence must use bounded document sizes, retry handling, periodic saves, safe failure behavior, and schema migrations; it cannot assume DataStore limits or network calls never fail.

## 11. Acceptance criteria

1. A player standing in a Mythling's Capture Ring gains only their own capture progress; leaving the ring causes that progress to decay.
2. The server awards exactly one Mythling to the first verified player to reach 100% capture progress.
3. A Mythling cannot be assigned to a Shrine with a different element.
4. Multiple matching Mythlings in one Shrine increase its combined Effective Yield and combined Effective Luck.
5. Production continues while the player is offline, cannot exceed Shrine capacity, and produces the same result regardless of client device or frame rate.
6. A Lucky Yield roll doubles normal output at launch and is calculated by the server.
7. Crafting, selling, upgrades, and event rewards cannot be granted by a client without a valid server-side affordability and eligibility check.
8. No launch UI or game system offers eggs, summons, gacha, or Elemental Prisms.
9. An acquired Mythling has one server-rolled Passive Trait, and that Trait cannot be supplied or changed by a client request.
10. A Mythling evolution resolves its new base statistics through its evolved Mythling metadata ID rather than duplicating those base statistics into the player save.
11. A scheduled Divine Intervention event starts only from an eligible, off-cooldown event definition and exposes the same server-verified event state to every player in that server.
12. An Event Caller cannot start an owner-only or all-server event, nor override a Mythling's rolled Luck or Passive Trait; only an owner-issued all-server command can activate the same configured event across live servers.
13. A player joining an active event receives its verified current state and may participate until it ends.
14. A new player has a Base, no Shrine/Mythling/resources, a configured Gold grant, a wooden sword, and a wooden shield.
15. Capture Rings do not overlap, and the Arena spawn system does not create an overlapping contest.
16. A Mythling earns XP only from verified Shrine production, caps at level 100, and retains its Passive Trait and element after evolution.
17. An Event Caller must own the Game Pass and satisfy the 30-minute cooldown; dedicated-music events cannot overlap another dedicated-music event.
18. A player at Mythling capacity cannot gain Capture Ring progress, and any blocked pickup, collection, or crafting start produces an inventory-capacity warning without granting the item.
19. Arena weapons and shield impacts consume Stamina; Arena combat uses knockback, ragdoll, and elemental effects but never player health or death.
20. All Passive Traits affect production only, and cancelling a Crafting Job refunds all of its spent resources and Gold.

## 12. Open decisions for later design passes

- Exact starting-Gold amount, first-Shrine cost/unlock, Base upgrade path, and Crafting Station unlock path.
- Numerical balance for spawn rates, capture/decay rates, Yield, Luck, capacities, upgrades, prices, and recipes.
- Weapon and shield catalogue, effects, cooldowns, six-slot hotbar equip/loadout rules, Stamina costs, regeneration rate, and maximum Stamina.
- Exact shop inventory and non-duplicate Gold sources, if needed after playtesting.
- XP requirements, exact per-level Yield percentage, evolution target levels, and trait acquisition weights.
- Mythling treats, combat health/attack, and a separate brawl/PvP mode.
- Rare-resource recipes, scarcity, storage-unit costs, and enabled Lucky Yield outcome when that extension ships.
- Event selection weights and the exact behavior when a server's hourly scheduled-event time arrives with no eligible event or no players.
- Event Caller Game Pass price, caller-enabled event catalogue, and behavior when a caller attempts to start an event while another event is active.
- Inventory capacity values by category and the permitted player actions for creating space.
