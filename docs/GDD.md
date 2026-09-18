# Mythic Legends — Game Design Document

This document owns gameplay, launch scope, pacing goals, and acceptance criteria. [Technical
Design](TECHNICAL_DESIGN.md) owns implementation and [current implementation
gaps](TECHNICAL_DESIGN.md#implementation-alignment); [UI Guidelines](UI_GUIDELINES.md) owns
presentation; the [README](../README.md) owns setup. Rules here describe the target game, not a
claim that every feature is implemented.

## 1. Product vision

**Mythic Legends** is a mobile-first Roblox creature-collection and Base-progression game.

**Core loop:** capture Mythlings → assign them to matching Shrines → produce Materials and XP →
collect Materials → craft Equipment, upgrade the Base, and evolve Mythlings. Selling extra captures
is the main early Gold source; selling collected surplus Materials provides additional Gold.

Design first for landscape mobile, with keyboard/mouse at launch and gamepad later. The intended
audience is family-friendly Roblox Kids/Select players. Use bright, readable, low-poly fantasy: a
circular public Arena in a sky-island world with distinct elemental landmarks. Concept art guides
the visual direction; it does not require every depicted creature or structure.

## 2. Launch scope

### Included in the current MVP

- Arena capture: eight players maximum, with a target of 12 capturable Mythlings in both quiet
  and full servers; replace captured or despawned Mythlings within three seconds.
- Non-lethal positional combat: one-handed swords, separate Shields, Stamina, knockback, and
  temporary immunity. Swords and Shields are the only launch Equipment types; progression goes
  from the plain wooden starter pair to Stage 1 element variants. Equipment also has rarity,
  independent of its stage. Each first-crafted sword has one automatic elemental effect on an
  accepted, unblocked hit.
- Bases and upgradeable elemental Shrines with online/offline Material and XP production.
- Inventory, Gold, selling, a restocking Material Shop with rotating Equipment offers, and upgrades.
- Six Mythling chains, one per element, each with Stage 1, Stage 2, and Stage 3 forms: 18 forms total.
- Mythling levels and evolution, with predictable production based on the current form and level.
- One permanent Crafting Station included with every Base, separate from its Shrine-only build
  slots and running one time-based Equipment job at a time.

### Not part of the game

- Eggs, summoning, gacha, and Elemental Prism capture devices.

### Planned future updates

- Mythling Luck, Lucky Yield, and Passive Traits, including the Insomniac and Lucky concepts.
  Their acquisition rules, effects, and balancing require a later design; launch has no rolls,
  production bonuses, or UI placeholders for these systems.
- Standalone Mythlings with no evolution chain and shorter, two-form chains.
- Legendary and Mythical Mythling content beyond the launch Common, Rare, and Epic roster.
- Epic, Legendary, and Mythical Equipment beyond the launch Common and Rare items.
- Equipment upgrades beyond Stage 1, beginning with Stage 2 and element-specific stat progression.
- Additional weapon archetypes, including two-handed weapons under the retained
  [Equipment compatibility rules](#equipment-compatibility).
- Combat Consumables, their inventory tab, and the six-slot Consumable Hotbar.
- Expanded crafting with waiting-job queues, Crafting Station upgrades, additional stations, and
  Consumable recipes.
- Gamepad controls.

These remain on the roadmap. Add their systems, UI, and save requirements with their updates; launch
must not expose placeholders or depend on them. Retained crafting and Consumable design is in
[future crafting](#consumables-and-expanded-crafting--future-updates).

### Other post-launch concepts

- Divine Intervention live events.
- Rare-Material acquisition and production.
- Mythling Fusion and possible dual-element Mythlings.
- A separate health/damage-based PvP brawl mode, matchmaking, rankings, and ranked rewards.
- Mythling treats, health, and attack until a separate progression design is approved.

Launch PvP is about controlling Capture Rings through knockback and defense. It uses no health
damage.

## 3. Canonical terminology

| Term | Meaning |
| --- | --- |
| Mythling | A collectable mythological creature that can be captured and assigned to a shrine. |
| Mythling Chain | One linear evolution line of the same element. Each MVP chain contains three forms; rarity does not determine chain length. |
| Mythling Stage | Internal shorthand for a form's position in its chain: Stage 1, 2, or 3 in the MVP. Not a player-facing label or XP level. |
| Equipment Stage | Internal shorthand for an Equipment form's position in its upgrade progression. Separate from rarity and not a player-facing label. |
| Arena | The central public location where wild Mythlings spawn and players compete to capture them. |
| Capture Ring | The circular king-of-the-hill area surrounding one spawned Mythling. |
| Base | A player-owned area containing their Shrines and one permanent Crafting Station. |
| Base Build Slot | Space for one constructed Shrine. The included Crafting Station uses no build slot. |
| Shrine | An element-specific production building at a base. It has upgradeable slots and shared storage. |
| Shrine Slot | One assignment space in a shrine. It holds one matching-element Mythling. |
| Yield | A Mythling stat that contributes normal Material output per hour while assigned to a Shrine. |
| Evolution | Replacing a Mythling's current form with a new Mythling definition that has its own base statistics. |
| Material | A crafting and upgrade input produced by a Shrine; collected surplus can be sold for Gold. |
| Gold | The primary currency, earned principally from selling duplicate Mythlings and spent in shops and upgrades. |
| Primary Weapon | Equipment used to apply positional knockback in the Arena. |
| Shield | Equipment used to protect against or reduce positional knockback in the Arena. |
| Equipment | The inventory category containing Primary Weapons and Shields. |
| Consumable | A planned post-launch stackable Hotbar entry that grants a temporary Arena combat buff when consumed. |
| Crafting Station | A permanent facility included with every Base that runs one time-based Equipment job at a time at launch; expanded queues are planned for a future update. |
| Combat Loadout | The player's equipped selection of up to one Primary Weapon and one compatible Shield. |
| Hotbar | A planned post-launch set of six Consumable slots; it does not hold Equipment and is not displayed in the MVP. |
| Stamina | A player resource consumed by Arena weapon actions and Shield impacts; it recovers gradually only while the Shield is lowered. |

Stage numbers in this document and content configuration explain progression only. Players see
named Mythling forms and Equipment, their rarity, and relevant statistics. Evolution and future
Equipment-upgrade previews show the resulting named form/item and its changes, without a numbered
stage badge, stage filter, or stage suffix in its name. Mythling XP levels and Shrine levels remain
visible; they describe separate progression systems.

Do not use *forge*, *altar*, or *pet* as alternative names for shrines or Mythlings in player-facing
text.

## 4. Elements and rarity

### Elements

The only launch elements are **Fire, Water, Earth, Air, Light, and Dark**. Every Mythling and Shrine
has exactly one element. A Mythling can be assigned only to a shrine with the same element.

Possible dual-element Fusion is post-launch; it does not change the launch assignment rule.

### Rarities

Mythlings and Equipment share these rarity names, ordered from lowest to highest:

1. Common
2. Rare
3. Epic
4. Legendary
5. Mythical

The MVP Mythling roster uses **Common, Rare, and Epic**; Legendary and Mythical Mythlings are future
content. Launch Equipment uses Common and Rare as specified in the
[Equipment rules](#stage-1-equipment-variants). Mythling rarity is fixed on each form, not rolled
separately for each owned copy. It informs capture difficulty, spawn weighting, and presentation. Within each
launch chain, higher-stage forms have better base Yield; rarity adds no separate production or XP
multiplier. Capture success follows the progress rules in this document; it is not a random success
roll. Rarity does not imply a different element.

**Rarity and evolution are independent.** Each form defines its own rarity and an optional next
form. A next form may retain or change rarity; there is no universal rule that Stage 2 means Rare.
Five rarities do not require five evolution stages. A Mythling can have no evolution, one evolution,
or two evolutions, and a form with no next evolution can still level up and improve production.
Standalone Mythlings with no evolution chain and shorter, two-form chains are future content.
The MVP retains the six complete three-form chains below, including each chain's final form with
no further evolution.

The first release has no cosmetic Mythling variants. Every gameplay-relevant or visual
transformation is represented by a distinct evolved Mythling form.

### Launch Mythling roster

The MVP has **one Mythling chain per element**: Fire, Water, Earth, Air, Light, and Dark. Each
chain has three distinct forms: **Stage 1 (base form) → Stage 2 (first evolution) → Stage 3 (final
evolution)**. This is **six chains and 18 forms**, with no branching or fourth stage at launch.

All six chains use this specific launch mapping, rather than a universal stage-to-rarity rule:

| Internal Mythling stage | Rarity | Acquisition |
| --- | --- | --- |
| Stage 1 | Common | Frequent Arena captures |
| Stage 2 | Rare | Evolve Stage 1 or find a less frequent Arena spawn |
| Stage 3 | Epic | Evolve Stage 2 or find the least frequent launch Arena spawn |

All 18 forms are eligible to spawn, with six forms at each launch rarity. Multiple wild instances
of the same form may coexist; roster size does not replace the capturable-population rule or
require every form to be present simultaneously. Initial spawn chances and capture times are set
in [capture and spawn tuning](#initial-capture-and-spawn-tuning).

Each chain's three forms produce the same element's normal Material through its matching Shrine.
Higher stages improve base Yield. Capturing a higher-stage form skips its earlier evolution steps;
the ordinary Common-capture and evolution route must support complete MVP progression without a
rare capture. Copies of the same form at the same XP level produce at the same rate, whether
captured at that form or evolved into it. Launch captures have no random production-stat rolls.

Mythling stage, XP level, and rarity remain distinct properties despite this fixed launch mapping.
Mythling Stages 2 and 3 are included in the MVP; the Stage 2 deferral applies only to Equipment.

### Mythling concept principle

Every Mythling concept is a hybrid of two recognizable mythological creatures from distinct
traditions. Both source creatures must be visually legible in the first form and remain part of any
evolutions, including both evolutions in each launch chain. Mythling concepts must not use figures
from living religions.

### Visual language

- Fire: orange/red, lava, embers.
- Water: blue, ice, crystal, flowing water.
- Earth: green, wood, stone, foliage.
- Air: pale cyan, clouds, wind, floating rock.
- Light: white/gold, beams, wings, radiant stone.
- Dark: black/purple, shadow, violet crystals.

Keep the Arena and nearby contest indicators readable on mobile at the required population.

## 5. Mobile controls and accessibility

### Player start and flow

Players spawn at their own Base. From there, they may immediately enter the Arena to capture
Mythlings or manage their Base, Shrines, and Crafting Stations through nearby Proximity Prompts. The
first-release player flow does not require a fixed tutorial sequence.

Map boundaries prevent players from falling off the playable islands during normal movement and
knockback. Resetting returns a player to their assigned spawn point at their Base, clears their
active capture progress, and retains all owned possessions and progression. Resetting does not
restart their profile, regrant starter items, or interrupt their Shrine and Crafting Job ownership.

Beginners should progress by choosing less-contested Common captures, building a matching Shrine,
and selling extra captures for Gold. Every ring remains competitive, but winning a busy contest
should not be necessary for basic progression. Spawn availability, spacing, and element mix must
support this route. The MVP has no peaceful capture mode, participation currency, or consolation
payout; reconsider a fallback only if the ordinary Arena cannot meet the acceptance criteria.

### Early progression targets

Use these as initial tuning targets for a beginner following the ordinary Common-capture route.
Times are measured from the first join; aim toward the lower end of the first-capture window.
Production estimates assume one Common working from minutes 3–5 at its starting base Yield, with
available storage and no Shop purchases. Validate the route on touch devices, including beginners
who lose early contests; rare captures must not be required.

| Milestone | Initial planning time since joining |
| --- | --- |
| First Common capture | 1–3 minutes |
| Matching Shrine built and working | 3–5 minutes |
| First whole Material ready to collect | About 8–10 minutes |
| Five Materials ready for the first Equipment recipe, if prioritized | About 28–30 minutes |
| First crafted Equipment completed, if prioritized | About 29–31 minutes, with Gold ready and crafting started promptly |

These are progression goals, not a mandatory tutorial order or guaranteed contest outcomes.
The first Shrine upgrade is a later saving goal measured in **days**, with subsequent upgrades
requiring longer saving over days or weeks. It is not an early-session milestone. Crafting and
evolution provide the initial progression while players save. Additional workers, levels, and
evolution can shorten actual production times. Offline working time counts, so these goals can
span visits; actual collection occurs when the player returns and uses Collect.

A first craft takes **one minute** after its Materials and Gold are ready and the player starts
the job. Shop Materials provide an earlier Gold-funded route: five inputs cost 50 Gold,
equivalent to two Common sales, with another 50 Gold needed to craft. This shortcut does not change
the independent first-craft route through each starting Shrine. Validate actual completion timing
with the approved progression modifiers and ordinary return/collection behavior.

The initial XP curve unlocks the first evolution at **level 6**, after **30 minutes of that
Mythling's eligible Shrine work**. This can accumulate across sessions, including offline work;
unassigned time and full-storage time do not count. Reaching the required level makes evolution
available through its existing free action.

### Controls

- Launch movement uses only Roblox's standard walking and jumping. There is no sprint, dash, crouch,
  climbing ability, or other movement action.
- The game uses Roblox's default third-person follow camera. There is no camera lock or aim mode at
  launch.
- **Mobile:** the left thumb controls movement; the right side controls camera drag, a dedicated
  Attack button, and a dedicated Shield button.
- **Keyboard/mouse:** left click uses the equipped Primary Weapon; holding `F` holds the equipped
  Shield active. Right click remains available for Roblox's default camera controls. There are no
  launch Hotbar bindings.
- **Gamepad (later):** right-trigger attack and left-trigger Shield hold are planned for a future
  update. D-pad Hotbar cycling belongs to the later Consumables update.
- The Combat Loadout has one Primary Weapon slot and one Shield slot. Players choose these in the
  Inventory menu under the [Equipment compatibility rules](#equipment-compatibility); Equipment
  never occupies a Hotbar slot.
- In the Arena, the equipped sword is held in the right hand and an equipped Shield in the left
  hand. Outside the Arena, equipped items remain visibly sheathed on the character and equipped in
  saved state, but their combat actions are unavailable.
- Every new player receives a plain wooden sword and wooden shield in their Combat Loadout.
- The originally granted starter sword and shield cannot be sold or discarded. Players may unequip
  them and retain them in Equipment inventory; unequipped items are not displayed on the character.
  Starting Equipment capacity includes the two protected items and room to craft another item.
  Launch uses the existing Equipment inventory; the storage box is deferred to a later update.
- Gold and Inventory/Shop buttons are always visible. Base, Shrine, and Crafting Station menus use
  nearby Proximity Prompts. The Arena adds Attack/Shield controls and Stamina; the Shield control
  indicates insufficient Stamina. Active or pending elemental effects remain readable outside the
  Arena, and Stamina stays visible while an existing Fire effect continues there. Combat controls
  remain unavailable outside the Arena. No Hotbar is displayed at launch.
- Capture progress is displayed above the contested Mythling, with the player's own meter prominent
  and the leading rival's progress shown when contested. Arena actions must be reachable while
  moving and must not require precise taps on a Mythling.
- Ring, progress, and ownership indicators cannot rely on color alone. All presentation, including
  future events, follows the accessibility rules in [UI Guidelines](UI_GUIDELINES.md).

### Equipment compatibility

Launch Equipment types are one-handed swords and separate Shields, which can be equipped together.
Either Loadout slot may be empty; a Shield may be equipped with the Primary Weapon slot empty.

#### Two-handed weapons — future updates

- A two-handed weapon uses both hands and cannot be equipped alongside a Shield.
- Equipping a two-handed weapon automatically unequips the Shield. It remains owned in Equipment
  inventory and still counts toward capacity. Shield equip and guard are unavailable while the
  two-handed weapon is equipped, including when its model is sheathed.
- Switching to a one-handed weapon or unequipping the two-handed weapon allows the player to
  manually equip a Shield again; it does not automatically restore the previous Shield.
- At the same Equipment stage, two-handed weapons offer stronger knockback in exchange for losing
  Shield access. Start with that tradeoff; slower attacks or higher attack Stamina costs are not
  automatic requirements and should be added only if testing shows they are needed.
- Shields retain meaningful knockback protection against two-handed weapons. Stronger attack force
  does not automatically break guard or increase the Shield's configured impact Stamina cost.

Additional archetypes arrive after launch. Compatibility and the stronger-knockback benefit are
settled; the choice of archetypes, such as a staff or hammer, their update order, exact values, and
movesets remain open decisions.

## 6. Arena capture

### Server population and spawn availability

- Deploy with **eight players maximum** and an initial configurable target of **12 capturable
  Mythlings**, equally in quiet and full servers. Fill all 12 before enabling capture on a fresh
  server; do not reduce the target when fewer players are present.
- Count only unclaimed Mythlings with valid active Capture Rings. Captured/escort models,
  decoration, pending attempts, and ended contests do not count. Overtime contests remain active and
  count toward availability.
- Captures and despawns free capacity immediately. Replace each ended contest with a valid,
  capturable Mythling **within three seconds** of its removal from availability. This configurable
  maximum applies to simultaneous removals too, not to each successive spawn in a serial queue.
  Deficits are allowed only inside that window, regardless of delayed model cleanup.
- Rings never overlap. The map must fit the target; failed placements retry valid positions rather
  than overlap rings. Persistent refill failure must be resolved before release.
- Weight the pool primarily by rarity, with accessible Commons and elements that support a first
  Shrine. Space rings to limit one player disrupting several contests in rapid succession.
  Availability offers alternatives, not a guarantee of an uncontested capture.

The spawn lifecycle is defined in [Technical
Design](TECHNICAL_DESIGN.md#arena-population-lifecycle).

### Capture flow

1. A stationary Mythling plays its idle animation inside one visible Capture Ring; neither roams.
2. A player with Mythling inventory space gains their own progress while inside the ring. Outside
   the ring, their progress decays. Each Mythling defines its capture and decay rates.
3. Players use weapon knockback and Shield defense to hold position or push rivals out.
4. The player with the earliest server-verified completion at 100% receives the Mythling. Exact ties
   favor whoever began their current uninterrupted stay in the ring first.
5. When the countdown reaches zero, an empty ring despawns its Mythling; an occupied ring enters
   **Overtime**. Overtime continues until someone captures the Mythling or the ring becomes empty,
   with no additional deadline.
6. Capture or despawn ends the contest, clears all its meters, and triggers replacement under the
   availability rules above.

### Initial capture and spawn tuning

Use these configurable starting values across all six launch chains:

| Mythling rarity | Chance per new spawn | Uninterrupted capture time | Initial spawn lifetime |
| --- | --- | --- | --- |
| Common | 75% | 20 seconds | 4 minutes |
| Rare | 20% | 35 seconds | 4 minutes |
| Epic | 5% | 60 seconds | 4 minutes |

Each new spawn independently selects a rarity using these chances, then gives each of the six
elements an equal chance within that rarity. Apply the same selection to fresh-server population
and replacements. These are aggregate chances for the rarity, not separate chances for each form
or guaranteed counts among the 12 active Mythlings. Form rarity remains fixed metadata; spawning
selects an existing named form rather than rolling a different rarity for that form.

Capture times mean eligible time inside the ring from an empty meter with no interruptions.
Configure the same initial time for all six forms within each launch rarity; retain per-form
tuning rather than a universal rarity-to-duration formula. Outside the ring, progress decays
immediately at the same rate it builds: **one second outside removes one second of earned capture
progress**, down to zero. For example, 10 seconds earned followed by three seconds outside leaves
seven seconds earned. Re-entry continues the remaining meter but starts a new uninterrupted visit
for tie priority. Normal jumps inside the ring preserve progress under the existing membership rule.

**Spawn lifetime** is the countdown before despawn or overtime, separate from capture duration.
For the first trial, **all 18 launch forms use the same four-minute (240-second) lifetime**.
Set the Common, Rare, and Epic defaults to that value, with no named-form overrides in the initial
launch configuration. Retain optional custom lifetimes for named Mythling forms when needed in
future content; an explicitly configured override replaces its rarity's default.

Resolve the lifetime when the Mythling becomes capturable and keep its deadline fixed for that
spawn. On fresh servers, the initial population's timers begin when capture opens, not during
prefill. Entering, leaving, or returning to a ring does not restart its countdown. Each effective
lifetime should allow time to reach the Mythling and complete its configured uninterrupted capture.
At zero, an empty ring despawns and an occupied ring enters the existing overtime flow; a custom
lifetime does not override overtime rules.

The shared lifetime removes lifetime differences as a source of rarity imbalance in the first trial.
Player choices, capture times, and overtime still affect what remains visible; spawn chances
describe new selections, not fixed population shares. Contested captures can take longer,
including overtime. Validate these values alongside the 25/100/300-Gold sale payouts and evolution
route: more frequent Rare/Epic captures
can accelerate Gold earnings and acquisition of stronger Shrine workers, but every new capture
still starts at level 1 with 0 XP.

### Arena rules

- Wild Mythling models do not physically block players or provide a surface to stand on. Player
  bodies use Roblox's default physical collision behavior in the Arena, including normal blocking
  and displacement from contact. There is no custom walking-push mechanic, push strength, or contact
  Stamina cost. Guarding and temporary weapon-knockback immunity do not change these body collisions;
  ordinary contact does not count as a weapon hit, Shield block, or immunity trigger.
- Each Mythling is an independent contest; capture progress is never shared between players or
  between Mythlings. Moving to another ring leaves earlier meters decaying normally.
- Use one server-verified membership rule for capture progress, uninterrupted-visit tie priority,
  and overtime occupancy: horizontal ring bounds with a finite vertical allowance that accommodates
  normal jumps. A normal jump within those bounds counts as staying inside without requiring ground
  contact. Moving or being knocked beyond either bound counts as leaving and starts normal progress
  decay; a high airborne launch cannot keep a player inside indefinitely.
- Overtime preserves existing meters and normal progress, decay, and combat rules. New players may
  join while the ring stays occupied. Once an overtime ring becomes empty, that contest ends and
  cannot resume. A capture completed exactly at the countdown deadline still succeeds.
- Presence keeps overtime active even for players whose Mythling inventory is full; capture
  eligibility still applies. Disconnect and reset remove that character from ring occupancy.
- Disconnect, reset, or reaching Mythling capacity immediately clears that player's meters. Full
  inventory blocks new progress and shows a capacity warning. Recheck capacity before awarding.
- Rarity informs per-Mythling capture difficulty without imposing a universal formula.
- The server is authoritative for Capture Ring membership, capture progress, winner selection,
  inventory changes, and rewards. MVP sword contact uses the client-reported architecture defined
  below.
- Arena boundaries prevent falling but must still let knockback move players out of Capture Rings.
  Keep valid ring placements clear of outer barriers so a boundary cannot hold a player inside a
  contest they would otherwise be pushed out of. Falling is not a capture or combat outcome.

### MVP player combat system

New attacks and Shield guard are Arena-only. Both attacker and target must be inside the Arena
for a new hit to be accepted; already-applied effects follow their persistence rules below.
Combat is non-lethal: knockback, Shields, and temporary immunity replace health damage. Attack and
guard are mutually exclusive actions. A compatible weapon and Shield can remain equipped together,
but only one can be used at a time.
Players start with a plain wooden sword and Shield and craft **Stage 1** swords and Shields with
[element variants](#stage-1-equipment-variants). Stage describes the upgrade position internally;
names such as Atlas identify an element's version. All first-crafted swords share the wooden
sword's base statistics and differ through their [elemental effects](#elemental-sword-effects).
The six first-crafted Shield variants share gameplay values and have no elemental abilities.

Entering draws the equipped items; leaving sheathes them and disables weapon/Shield actions without
changing the saved Loadout or clearing existing elemental effects. The approved [client-reported sword
architecture](TECHNICAL_DESIGN.md#client-reported-sword-combat) prioritizes responsive visible
contact and is not fully exploit-resistant. Preserve that exception; do not substitute a server hit
scan. Capture, Stamina, eligibility, possessions, and rewards remain server-authoritative.

#### Weapon actions

- Left click and the mobile Attack button activate the same equipped weapon action. One input must
  produce only one swing.
- A player needs enough Stamina, a ready weapon cooldown, and no active Shield action to attack. An
  activated swing consumes its full Stamina cost even when it misses; rejected actions do not
  consume Stamina.
- Sword contact follows the visible blade during the swing's contact window. A swing can hit at most
  one opponent, chosen by closest valid blade contact. Merely approaching another player without
  swinging cannot produce a hit.
- Attacks produce immediate local swing and contact feedback. A confirmed hit applies one knockback
  reaction and temporary knockback immunity, with no health damage. Immunity prevents further
  accepted weapon-knockback hits for its configured duration; normal body collisions still apply.
- Cosmetic effects never change capture progress, hit eligibility, immunity, or rewards.

#### Elemental sword effects

Each first-crafted elemental sword has **one automatic effect on an accepted, unblocked hit**,
subject to the overlap rules below.
The plain wooden sword has no elemental effect. All swords retain the same base reach, contact
geometry, attack timing, Stamina cost, and horizontal/vertical knockback; an elemental effect is
the crafted sword's advantage. Equal base statistics do not mean identical final combat behavior.
Crafted and Featured copies of the same named sword have the same effect.

| Element | Effect | Combat role |
| --- | --- | --- |
| Fire | A brief burn drains the opponent's Stamina over time, with visible flames. | Pressure their ability to attack and guard. |
| Water | Briefly slows the opponent's walking. | Delay their return to a Capture Ring. |
| Earth | Vines briefly prevent walking and jumping after the opponent lands. They can still attack, guard, and be moved by knockback. | Temporarily hold the opponent's position without anchoring them against displacement. |
| Air | Adds horizontal push to the same accepted hit. | Push the opponent farther from the Capture Ring. |
| Light | Briefly reduces the opponent's outgoing horizontal weapon knockback. | Weaken their ability to displace other players. |
| Dark | Returns a small portion of the attacker's spent Stamina. | Reward successful hits with better endurance. |

- Effects use the existing Attack action, with no extra buttons or special reactions between elements.
  Misses, rejected hits, and hits rejected during knockback immunity grant no effect or Stamina
  return. A successful Shield block prevents the new effect, including Dark's benefit to the
  attacker; it does not cleanse an effect already applied by an earlier unblocked hit.
- Each player can have **one lingering negative effect at a time**: Fire, Water, Earth, or Light.
  The first accepted effect wins, regardless of element or attacker. Later timed effects are
  ignored; they cannot replace, stack with, extend, or queue behind the current effect. Ignoring
  a new timed effect does not cancel the accepted hit's normal knockback or immunity.
- Earth's pending root occupies this limit while waiting for landing and through the root itself.
  Repeated hits cannot extend its landing deadline or queue another root. After the root ends,
  a brief recovery window prevents another Earth root from any attacker. That window blocks Earth
  only; another timed effect can apply if the player has no active or pending negative effect.
- Air's extra push and Dark's Stamina return are immediate effects and do not occupy this limit.
  They can still apply when the target has a timed effect, subject to the same accepted,
  unblocked-hit requirement and knockback-immunity checks.
- Water and Earth restrict voluntary movement only. They do not stop forced knockback or change
  normal body collisions. Earth never prevents attacking or guarding. Ring membership and capture
  progress still follow the ordinary position and eligibility rules.
- Fire drains Stamina while normal recovery still follows the existing Shield rules. It can reduce
  net recovery while fully lowered; it does not independently switch regeneration off. Stamina
  cannot fall below zero, and falling below the guard minimum forces the Shield to lower normally.
- Air's additional push is part of the original hit's reaction, not a second hit or an immunity
  bypass. Light reduces the complete outgoing horizontal weapon force, including Air's bonus.
  Neither effect changes upward launch, Shield slides, or the defender's Shield block cost.
- Dark returns Stamina only after an accepted, unblocked hit and never above maximum. Its return
  must stay small enough that repeated successful attacks at the one-second cadence still consume
  Stamina overall after normal recovery; it cannot make continuous full-rate attacks sustainable.
- Leaving or re-entering the Arena does not clear, pause, or restart active or pending elemental
  effects or their timers. Fire continues ticking outside the Arena, and an already pending Earth
  root can activate on landing there. Earth's landing timeout and post-root recovery window also
  continue normally across the boundary. New attacks remain Arena-only.
- Equipment changes by either player do not remove or restart an effect already applied to its
  target. The original attacker's Arena exit also leaves that effect running normally. Resetting
  or disconnecting clears the affected character's active and pending effects and all of that
  player's capture progress; it cannot preserve a capture meter while clearing an effect.
- All effects remain non-lethal and have clear visual feedback, including pending Earth roots and
  effects that continue outside the Arena. Item previews in crafting, Shop, and Inventory briefly
  describe each sword's effect. Visuals communicate the gameplay result; they do not determine hit
  eligibility, capture membership, or effect duration.

For example, an Earth sword hitting a burning opponent still causes normal knockback but applies
no pending vines and does not refresh the burn. This deliberately limits combinations from multiple
attackers; Air and Dark retain their immediate benefits against an already affected target.

#### Initial elemental effect tuning

Use these configurable starting values for all six first-crafted swords, including Featured
copies. They are trial values to validate with actual knockback, ring sizes, and return movement.

| Element | Initial effect value | Timing |
| --- | --- | --- |
| Fire | Drain 15 Stamina per second; 30 total before regeneration. | 2 seconds from the accepted hit. |
| Water | Reduce walking speed by 25%. | 2 seconds from the accepted hit. |
| Earth | Prevent walking and jumping for 0.75 seconds. | Starts on landing after the hit's knockback. |
| Air | Add 15% to horizontal weapon knockback. | Part of the same accepted hit. |
| Light | Reduce outgoing horizontal weapon knockback by 20%, including any Air bonus. | 2 seconds from the accepted hit. |
| Dark | Return 3 Stamina to the attacker, capped at maximum Stamina. | Once per accepted, unblocked hit. |

- Fire, Water, and Light timers start on the hit and continue during airborne movement. Earth
  starts its root on the first landing after that hit's knockback, not on the grounded frame
  before launch. If the player does not land within **3 seconds of the hit**, the pending root
  expires. Later hits cannot postpone this deadline or pause/extend an active root.
- After Earth's root ends, **3 seconds of protection against another Earth root** begin. Other
  timed effects can still apply when the negative-effect limit is free. A pending root that
  expires without activating does not grant this post-root recovery window.
- Fire does not disable normal recovery. With no other actions or effects, a fully lowered player
  starting at 100 Stamina loses 30 to the burn and recovers 20 over its two seconds, ending at 90.
  Guard phases grant no recovery, and all existing guard-minimum and zero-Stamina limits apply.
- Light scales the total horizontal push after Air's bonus. An Air sword used while its attacker
  is affected by Light therefore produces `1.15 × 0.80 = 0.92` times the ordinary horizontal force.
  These percentages describe force; actual travel distance depends on movement and collisions.
- Dark still requires the full 20 Stamina to start the attack. Its 3-Stamina return makes an
  accepted, unblocked hit cost 17 before normal recovery; a miss or blocked hit costs 20. Recovery
  at 10 per second cannot sustain successful attacks costing 17 every second indefinitely.

Pay particular attention to Fire's Stamina pressure and Earth's movement restriction during
validation. The initial values do not establish that the six effects are equally strong.

#### Shield actions

- Guard requires an equipped Shield and a [compatible Loadout](#equipment-compatibility).
- Hold to raise; release to lower. Guard cannot start during a swing; attacks cannot start during
  raising, holding, or lowering, even after protection has ended.
- Guard requires a configured positive minimum Stamina, at least the full block cost. Below that
  threshold, the Shield cannot be raised or remain protective. No partial-cost or zero-Stamina
  block.
- **Stamina recovers only while fully lowered.** Raising, guarding, and lowering grant no recovery;
  time spent in those states can never be credited afterward. Recovery begins as soon as lowering
  finishes, including after a guard break, with no additional delay.
- Protection follows animation transitions, but insufficient Stamina, Arena exit, or unequip removes
  it immediately. The bubble reflects actual protection, not an unfinished lowering animation.
- An eligible Shield absorbs weapon hits from any direction. Each accepted block spends the **defender's**
  full impact cost, slides them away from the hit, grants temporary immunity, and sparks on the
  bubble. The attacker separately pays their weapon cost.
- A paid block that leaves too little Stamina immediately removes protection and lowers the Shield.
  Guard can resume only after recovery and a fresh input. Without eligible protection, normal
  unshielded knockback applies, subject to immunity.
- Guard prevents voluntary walking and jumping; forced sliding still applies.

Use these initial guard targets when starting at **full Stamina**, keeping the same Shield raised
continuously with no intervening recovery or other Stamina drain, such as an existing Fire burn:

| Shield | Accepted blocks before Stamina forces lowering |
| --- | --- |
| Wooden starter Shield | 3 |
| First-crafted elemental Shield, all six variants | 4 |

The final counted hit is still fully blocked and produces the normal reduced slide and temporary
immunity; its Stamina cost then leaves the player below the guard threshold, forcing the Shield
down. Hits rejected during immunity do not spend block Stamina or count toward these totals.
These are Stamina-balance targets, not Equipment durability or a separate block-charge system.
All six crafted Shield variants share the same values, including copies bought from Featured.
Blocking can still push a player out of a Capture Ring before reaching the stated count.
The initial values below produce these targets without adding a separate block allowance.

The server validates guard eligibility and enforces Stamina consumption and regeneration as
specified in [Technical Design](TECHNICAL_DESIGN.md#stamina-and-guard-accounting).

#### Initial Stamina and attack tuning

Use these configurable starting values for wooden starter Equipment and all six first-crafted
elemental variants, including Featured copies:

| Setting | Initial value |
| --- | --- |
| Maximum Stamina | 100 |
| Stamina on character spawn, including respawn after reset | 100 |
| Sword attack cost | 20 |
| Minimum interval between accepted sword attack starts | 1 second |
| Recovery while the Shield is fully lowered | 10 Stamina per second |
| Wooden Shield block cost and minimum guard Stamina | 30 each |
| First-crafted Shield block cost and minimum guard Stamina | 25 each |

The wooden Shield's three paid blocks leave 10 Stamina, below its 30-Stamina guard requirement;
the crafted Shield's four blocks leave zero. The final block still protects before the Shield
lowers. Raising or keeping a Shield active always requires enough Stamina for its next full block.

Recovery continues during sword attacks while the Shield is fully lowered. With no further
spending, recovering from zero takes two seconds to afford an attack and ten seconds to fill the
bar. These times begin once the Shield is fully lowered; raising, guarding, and lowering recover
nothing. A miss still spends the accepted swing's 20 Stamina, and rejected actions spend none.

At one accepted swing each second from full Stamina, with continuous recovery and no intervening
guard, other costs, or elemental Stamina changes, nine swings can start at seconds 0 through 8.
The next request at second 9 lacks Stamina; another swing becomes affordable at second 10.
This reference assumes the swing's
action lock permits that cadence. The one-second interval is measured start to start, not added
after the animation finishes, and never bypasses an unfinished action lock. Attacks at this
one-second cadence cannot continue indefinitely on recovery alone; slower, paced attacks can
remain sustainable.

Initialize Stamina on character spawn; Arena entry/re-entry and Equipment changes do not refill
it or reset action limits. Swing contact windows, guard transition durations, immunity, and
knockback still require tuning together in the Arena.

## 7. Bases, shrines, and production

### Shrine rules

- A Shrine has one element, one output Material, an upgradeable level, assignment slots, and shared
  storage. All six elements use one upgrade path, ending at level 3 in the MVP.
- Only matching-element Mythlings may be assigned. Each owned Mythling occupies at most one slot
  across the Base; the player must own both it and the Shrine.
- Assigned Mythlings supply Yield from their current form and level. The Shrine determines the
  Material produced.
- Players may build duplicate-element Shrines within Base build capacity.
- The Shrine's Proximity Prompt opens assignment, removal, collection, upgrading, and dismantling
  actions.
- Dismantle an empty Shrine to recover its build slot, with no refund or stored building. Remove
  assigned Mythlings and collect all completed Materials first. Unfinished production progress is
  discarded and cannot prevent dismantling.

| Shrine level | Mythling assignment slots | Initial shared Material capacity |
| --- | ---: | ---: |
| 1 | 1 | 300 |
| 2 | 2 | 1,200 |
| 3 | 3 | 3,600 |

Each upgrade adds one assignment slot and increases shared Material storage through a single
Upgrade action; there are no separate worker-slot or storage upgrade paths. The new slot starts
empty. Six fully upgraded Shrines support at most **18 working Mythlings**. Both upgrade starting
prices are set in [initial economy tuning](#initial-economy-tuning); validate them against the
[upgrade saving targets](#upgrade-saving-targets).

These are configurable starting capacities, fixed by Shrine level rather than its current workers.
The level-3 reference is three Epics starting at level 50 with no XP toward their next level.
At the initial 32-Material/hour Epic base Yield, including further leveling, they fill its 3,600
spaces in roughly **24.2 working hours**, online or offline. This supports approximately daily
collection. Less-developed teams take longer and higher-level teams fill sooner; storage is not
a fixed 24-hour timer or a crafting wait.

New players have a Base with **one permanent Crafting Station and two empty build slots for Shrines
only**, no Shrines/Mythlings/Materials, and configured starting Gold. The included Station uses no
build slot. The Base menu builds Shrines; basic level-1 Shrines for all six elements share the
**same Gold-only price**, including rebuilding with no owned Shrine or Materials. Shrine upgrades
use Gold plus that Shrine's matching normal Material. **Base build-slot upgrades cost Gold plus
fixed equal quantities of all six normal Materials** and add **one permanent Base build slot per
purchase**, up to **six unlocked slots in the MVP**. Starting with two slots means four expansion
purchases are available. Unlocked slots persist through Shrine dismantling, character reset, and
reconnect; dismantling frees space without undoing an expansion.
Players may use the six slots for one Shrine per element or choose duplicate-element Shrines.

Starting Gold must cover any one basic level-1 Shrine, so players can retain their first capture and
build a matching Shrine regardless of element. Ordinary capture sales fund later purchases and
rebuilds.
Verify a complete route through collection, the first Equipment recipe at the included Station, a
Shrine upgrade, and an evolution. Required inputs must be obtainable before the purchase that needs
them and fit the available Inventory capacity. Repeat recovery with no Shrine or Materials after
ordinary spending/selling choices; freeing space cannot solve a circular build or recipe cost.

### Production calculation

```text
Mythling Yield Per Hour = current form base Yield × (1 + 0.01 × (level − 1))
Total Yield Per Hour = sum(assigned Mythling Yield Per Hour)
```

The MVP has no additional Shrine production multiplier. Upgrading a Shrine increases assignment
capacity and storage, not each worker's Yield or XP rate. Higher output comes from filling the new
slots and the Mythlings' current forms and levels. Online and offline production use the same rate;
there are no random Yield rolls or Passive Trait modifiers at launch.

Use these approved **starting values for testing** across all six launch chains. Store the base
Yield on each named form; these are catalogue values, not a runtime rarity multiplier.

| Launch form | Base Materials/hour | Nominal working time per Material |
| --- | ---: | --- |
| Common | 12 | 5 minutes |
| Rare | 18 | 3 minutes 20 seconds |
| Epic | 32 | 1 minute 52.5 seconds |

These rates are before level scaling. At an unchanged Common base rate, two Materials take 10
working minutes and the five Materials for one first sword or Shield take 25.
Combined worker output and progression change the time to the next item. Level scaling follows
the [progression rules](#mythling-progression) below. The Epic trial rate preserves approximately
daily developed-team collection after deferring Luck and Traits; Common and Rare rates retain
their earlier crafting and progression baselines.

Production uses fixed server batches to accumulate each worker's earned output and XP. Add new
production work to unfinished progress carried from earlier batches. Only completed, whole Materials
enter Shrine storage; the remaining work stays internal progress toward the next item, never a
fractional Material in storage or Inventory. There is no random bonus step.

If workers or production inputs change within a batch, retain the work earned under each set of
inputs. A new worker or evolved form changes only later work; it cannot recalculate earlier progress.
Changing workers, collecting, or completing an item never creates extra output or XP.

- Production and working Mythling XP continue offline, calculated from elapsed time when needed. A
  player does not need a continuously running server. The same workers at the same levels earn
  identical production and XP for equal eligible working time online or offline.
- **Full Shrine storage stops both production and XP.** Output never exceeds capacity. Collecting or
  increasing storage lets production resume, without catching up for time spent full.
- The working batch that fills storage keeps only the whole Materials that fit and discards excess
  output. Each worker retains its normally earned XP for that batch; subsequent full-storage time
  earns none. Excess output cannot be banked as unfinished production for later collection.
- Inspect and Collect output through the Shrine menu. Offline output stays in that storage until
  collected; it is not automatically added to Material inventory. Collecting completed Materials
  preserves unfinished production progress and never restarts the production timer. Low Yield must
  still accumulate enough work to complete an item.
- Unprocessed offline time uses current production configuration with saved assignments and
  progression. Balance changes can affect unsettled time, but cannot reprice stored Materials or
  awarded XP.
- Assignment/removal, evolution, and Shrine upgrades settle prior work before changing its inputs.
  Unfinished progress stays at the Shrine when Mythlings are swapped, removed, or evolved. New Yield
  affects only the remaining work; moving a Mythling to another Shrine does not move that progress.
- Removing every worker pauses unfinished production; assigning workers resumes from that point.
  Time spent without workers grants no production or XP and cannot be caught up afterward.
- Online/offline transitions preserve unfinished progress without changing production rates. A
  level gained in one batch affects later batches only; completed output and XP cannot be awarded twice.

Accounting is specified in [Technical Design](TECHNICAL_DESIGN.md#production-accrual).

### Luck, Passive Traits, and rare Materials — future updates

Luck, Lucky Yield, and Passive Traits are deferred together. Insomniac and Lucky remain possible
Trait concepts; their previous rates, rolls, and accounting are not launch requirements. A future
rare-Material outcome, such as Fire's `Prismatic Ember`, also needs its own acquisition and storage
design. None of these systems is required to support the launch economy or implementation.

Existing prototype Luck values and Trait IDs remain preserved but inactive. New launch captures
receive no Luck or Trait rolls, and launch UI does not expose these fields or placeholders.

### Mythling progression

Each Mythling has a current form, level, and XP. Form supplies base statistics; individual
progression persists between sessions.

- **New captures:** every newly captured Mythling starts at **XP level 1 with 0 XP**, regardless of
  stage or rarity, and retains the form captured. In the launch roster, Rare and Epic captures
  immediately use their higher-stage base Yield; their stage does not grant starting levels or XP.
  A captured Stage 2 works toward its Stage 3 evolution requirement. Launch Stage 3 forms have no
  further evolution but can still gain levels up to the normal level cap.
- **Levels and Yield:** cap at level 100. Initially, every launch form gains **1% of its current
  form's base Yield per level above level 1**. The bonus adds linearly, without compounding:
  level 1 has no bonus, level 50 has +49%, and level 100 has +99%.
  Calculate `base Yield × (1 + 0.01 × (level − 1))`; keep the percentage configurable.
  Evolution retains the level and applies that same percentage bonus to the new
  form's base Yield. Fractional rates advance unfinished work; owned Materials remain whole items.
- **XP:** the activity sets the base earning rate. Launch Shrine work initially awards **1 XP per
  eligible working second** to each Mythling, shared across all forms and elements and independent
  of Mythling statistics or Material output. Each Mythling earns
  XP for its own time actively working, including work toward an unfinished item; concurrent workers
  earn independently. Award this XP at the normal batch boundary. If workers change within a batch,
  each keeps the XP earned during its own working time.
- **Evolution:** from Inventory, an owned Mythling with a configured next form can immediately evolve
  for free at its required level. The launch paths are Stage 1 to 2, then Stage 2 to 3; launch Stage 3
  forms have no next target. A form's evolution link determines whether it can evolve, independently
  of rarity. Evolution applies the target form's base statistics and level modifiers while retaining
  element, instance ID, level, and XP. Display the target form's configured rarity, whether it stays
  the same or changes. Any preserved legacy Luck/Trait data stays inactive and is not rerolled.

Initial progression uses **120 × current level XP** to advance one level. All launch forms share
this curve; evolving does not reset or spend earned progression. Cumulative XP from level 1 to
level `N` is `60 × N × (N − 1)`.

| Milestone | Required XP level | Total eligible work from level 1 |
| --- | ---: | --- |
| First evolution available | 6 | 30 minutes |
| Final evolution available | 40 | 26 hours |
| Level cap | 100 | 165 hours (6 days 21 hours) |

These are working-time milestones, resolved at normal batch boundaries. Full storage and
unassignment pause the clock; evolution stays manual and free. A Mythling already meeting both
thresholds can take its two evolution actions consecutively. Wild Rare/Epic captures still start at
level 1, so catching a later form skips earlier evolution steps without granting trained levels.
Keep these starting values configurable and validate their pacing in play.

## 8. Crafting, shop, and economy

### Crafting

Every Base comes with **one permanent Crafting Station, ready to use from the first join**. It
requires no purchase, construction, unlock, or Base build slot and cannot be sold or dismantled.
Its Proximity Prompt opens recipes and its one active Equipment job. Crafting Equipment still
costs the recipe's Gold and Materials. Launch has no waiting queue, station upgrades, additional
stations, or Jobs Inventory tab. Recipe fields and Equipment definitions belong in [Technical
Design](TECHNICAL_DESIGN.md#content-configuration).

Every launch sword and Shield recipe initially takes **60 seconds** once started, across all six
elements. Ingredient production is a separate wait; retain the configured duration on each recipe.

- Start spends the listed Materials/Gold and reserves Equipment output space plus Material refund
  space. Other acquisitions cannot use that space; the menu explains the reservation.
- Cancel before completion for exactly the costs paid. Once due, the job completes instead:
  Equipment is automatically granted and the station becomes idle, with no manual Claim step.
- Jobs continue offline. Resolve due jobs on return before starting another. Reconnects and balance
  changes cannot alter the recorded result, costs, timing, or capacity guarantee. Each job grants
  its output or refund once, never both.

Receipts, validation, and atomic resolution belong in [Technical
Design](TECHNICAL_DESIGN.md#crafting-transactions).

### Stage 1 Equipment variants

**Stage 1** is internal shorthand for the first crafted Equipment after the plain wooden starter
pair. The launch types, swords and Shields, each have six element variants: **Fire, Water, Earth,
Air, Light, and Dark**. Each variant has its own name and appearance. The launch names are:

| Element | Sword | Shield |
| --- | --- | --- |
| Fire | Vulcan Sword | Vulcan Shield |
| Water | Triton Sword | Triton Shield |
| Earth | Atlas Sword | Atlas Shield |
| Air | Aura Sword | Aura Shield |
| Light | Sol Sword | Sol Shield |
| Dark | Nyx Sword | Nyx Shield |

These names identify the elemental variants, not shared Equipment stages. The plain starter pair
remains **Wooden Sword** and **Wooden Shield**.

First-crafted swords improve on the wooden sword through their elemental effects while retaining
its base statistics. First-crafted Shields improve Stamina efficiency: four paid blocks from full
Stamina instead of three under the baseline conditions in [Shield actions](#shield-actions).
Tune these advantages to retain the beginner capture route in the acceptance criteria.
**Stage 1 is the MVP's highest Equipment stage.** Stage 2 and later upgrades arrive in future
updates; launch crafting produces new Stage 1 items and has no Equipment-upgrade action.

**Equipment rarity is included in the MVP** and shown alongside its name, type, and element.
**Each named Equipment item has one fixed rarity.** Every copy of an Atlas Sword, for example,
has that item's configured rarity; crafting does not roll different rarities for copies of the
same named item. This applies to swords, Shields, their named element variants, and plain starter gear.

Upgrade stage stays internal and is separate from rarity: an item can have a rarity even if it has
no upgrade path, and five rarities do not require five upgrade stages. Equipment rarity describes
the item's quality category. Statistics, recipe costs, and sell values come from the item's
configuration, without an additional rarity-based multiplier.
The wooden starter pair retains its plain appearance and starter protection while displaying rarity.

Launch assignments are:

| Equipment | Fixed rarity |
| --- | --- |
| Wooden starter sword and Shield | Common |
| All six first-crafted elemental swords | Rare |
| All six first-crafted elemental Shields | Rare |

Epic, Legendary, and Mythical Equipment are future content. These are assignments for the launch items,
not a universal formula linking upgrade position to rarity. Future upgrades need not increase rarity
at every step; their item definitions and rarity assignments require a separate content decision.

All six Stage 1 swords share the wooden sword's base statistics, timing, Stamina cost, and contact
geometry. Each adds its element's [sword effect](#elemental-sword-effects). All six Stage 1 Shields
share one set of gameplay values and behavior, with no elemental Shield abilities. Variants reuse
their Equipment type's base model with recolors and relevant effect visuals. Future upgraded stages
are intended to develop element-specific base statistics; their detailed progression remains open.

- Each variant has a fixed recipe using its matching Shrine's normal Material and the configured
  Gold cost. Other elements' Materials cannot substitute for or mix into that recipe. Every first
  Shrine element must provide a reachable Stage 1 Equipment craft through its matching variant.
- The element variant is chosen through its recipe and stays on the crafted item. Each crafted copy
  occupies an Equipment Inventory slot, including additional copies of the same item or variant.
- The launch crafting catalogue groups variants under **Swords** and **Shields**. Choosing an element
  shows that variant's name, fixed rarity, preview, and recipe requirements. Inventory and active
  jobs identify the named item, its element variant, and the same configured rarity. Stage numbers
  are not displayed; [UI Guidelines](UI_GUIDELINES.md) owns the presentation.
- The originally granted wooden sword and shield remain plain and protected by the starter rules.
  Equipment variants do not introduce cosmetic Mythling variants.

### Consumables and expanded crafting — future updates

Future Combat Consumables are crafted, equipped in up to six optional Hotbar slots along the bottom
of the screen, and consumed for temporary Arena buffs. They never occupy Equipment slots or change
the Combat Loadout. Duration, inventory stack limits, buff stacking/refresh, effect limits, cooldowns,
input bindings, and disconnect behavior must be settled before implementation; activation and expiry
stay authoritative.
Production/crafting Consumables are outside the approved scope.

Waiting queues, station levels that expand queues, additional stations, and Consumable recipes
arrive in future updates and must retain the launch job guarantees. Launch exposes none of these
systems or their Inventory/Hotbar placeholders.

### Gold and duplication

- Selling extra Mythlings is the main early Gold source. Common capture/sale throughput must support
  ordinary upgrades for beginners who lose busy contests, without a participation payout.
- Each named Mythling form has a fixed configured Gold sell value. At launch, all six Common forms
  share one value, all six Rare forms share a higher value, and all six Epic forms share a higher
  value again. These are launch catalogue assignments; resolve each form's value directly rather
  than applying a general rarity or stage multiplier.
- XP level and any inactive legacy Luck/Trait data do not change a Mythling's sell value. Evolution
  uses the new form's configured value; an evolved Mythling and a wild-captured copy of that same
  form sell for the same amount. Training benefits production and evolution without a separate sale-price bonus.
- All six normal launch Materials can be sold for Gold at a low, fixed configured price per unit.
  Players first collect Materials from Shrine storage, then choose a whole quantity to sell from
  Inventory. Offline production can therefore indirectly earn Gold through collection and sale;
  production never converts itself into Gold. Tune Material prices so duplicate Mythling captures
  remain the main early Gold source while surplus output stays useful after crafting and upgrades.
- Sell from the selected Inventory entry. Shop handles purchases and Inventory-slot upgrades;
  structure purchases/upgrades use their world menus and configured Gold/Material costs.
- Metadata determines sell eligibility/value. The original starter sword and shield are protected
  even when other instances of their definitions are sellable. Mythlings have no final-copy
  protection.
- Choose a quantity for stackable sales. Unequip Equipment or unassign Mythlings before selling;
  reservations are not owned items and cannot be sold or spent.
- A valid sale removes the owned entry/quantity and grants Gold together. The first capture requires
  no Gold; basic Shrine rebuilds follow the Gold-only rules above.

### Initial economy tuning

Use these approved **starting values for testing**, stored in configuration and shared across all
six elements. They establish an initial budget alongside the approved production, progression,
storage, and crafting values. Validate their combined pacing and capture throughput against the
[early progression targets](#early-progression-targets).

| Item or action | Starting amount |
| --- | --- |
| Sell a Common Mythling | 25 Gold |
| Sell a Rare Mythling | 100 Gold |
| Sell an Epic Mythling | 300 Gold |
| Starting Gold for a new player | 100 Gold |
| Build or rebuild a basic level-1 Shrine | 100 Gold |
| Upgrade a Shrine from level 1 to 2 | 1,000 Gold + 400 matching normal Materials |
| Upgrade a Shrine from level 2 to 3 | 15,000 Gold + 4,000 matching normal Materials |
| Unlock the third Shrine build slot | 10,000 Gold + 50 of each of the six normal Materials |
| Unlock the fourth Shrine build slot | 50,000 Gold + 100 of each of the six normal Materials |
| Unlock the fifth Shrine build slot | 150,000 Gold + 150 of each of the six normal Materials |
| Unlock the sixth Shrine build slot | 500,000 Gold + 200 of each of the six normal Materials |
| First Inventory-capacity upgrade, per category | 20,000 Gold + 50 of each of the six normal Materials |
| Final Inventory-capacity upgrade, per category | 300,000 Gold + 200 of each of the six normal Materials |
| Craft one first sword or Shield | 50 Gold + 5 matching normal Materials |
| Buy one normal Material | 10 Gold |
| Sell one normal Material | 2 Gold |
| Buy one finished Featured sword or Shield | 150 Gold |
| Sell one first-crafted sword or Shield | 25 Gold |

Each introductory recipe produces one Equipment copy. The same named Equipment has the same
25-Gold sale value whether crafted or bought from Featured. The originally granted wooden starter
pair retains its sale protection.

Starting Gold covers the first Shrine while the player keeps their first Mythling. Using produced
Materials, a craft requires two extra Common sales for its Gold cost; buying all five inputs and
crafting costs 100 Gold, while the Featured item costs 150 Gold. Shrine upgrades are separate
multi-day saving goals. Filling an upgrade's new worker slot requires another retained
matching Mythling; the upgrade itself does not increase worker production.

Material resale is 20% of the buy price, and Featured costs 50% above purchased-input crafting.
Selling bought Materials or reselling crafted/Featured Equipment loses Gold. Verify the ordinary
Common route and rare-capture windfalls with these values before treating the pacing as established.
Base and Inventory upgrade prices follow the saving targets below. Each Inventory category is
purchased independently; paying for one does not upgrade the other two.

### Upgrade saving targets

All paid launch upgrades require **both Gold and Materials**. Shrine upgrades use their matching
normal Material. Each Base expansion and Inventory-capacity upgrade has a **fixed recipe containing
equal quantities of all six elemental normal Materials**, at the amounts in
[initial economy tuning](#initial-economy-tuning). Players cannot substitute another element or
choose a payment Material.

Even the first Shrine upgrade should take days of ordinary saving, with fewer days than later
upgrades. Subsequent upgrades should represent days or weeks of Gold and Material accumulation.
These are affordability targets, not added construction timers or minimum account-age gates.
Keep initial Shrine construction/rebuilding at its Gold-only price, and keep the first Equipment
craft and free Mythling evolution accessible under their existing rules.

Gold sets most of the saving time for Base and Inventory upgrades; Shrine upgrades remain the
large Material-saving purchases. A developed Shrine may quickly produce its share of a Base or
Inventory recipe. Modest, equal quantities across all six elements let players keep their chosen
Shrines, including duplicates, and buy missing elements without requiring a particular layout.
At 10 of each Material per Shop allowance, an unproduced ingredient requires 5/10/15/20 allowances
for the four Base expansions, and 5/20 for the two Inventory upgrades. Players may buy all missing
types during the same visits. With one purchase visit per day, those are 5–20 days; visits in
additional refresh periods shorten the wait. Missed allowances do not accumulate.

The sixth Base slot takes approximately 14 full daily collections from five different-element
level-3 Shrines: 252,000 Materials produced, with 1,000 retained for their recipe shares and the
other 251,000 sold for 502,000 Gold. That covers the 500,000-Gold upgrade and 2,000 Gold to buy
200 of the missing element. This reference begins with all five Shrines built and staffed, no
prior savings or extra capture income, no other spending, and enough Shop visits to buy the
missing ingredient. It is a saving estimate, not a guaranteed timer. Each Base/Inventory recipe
occupies six Material slots, fitting the starting bag when enough unreserved space is available.

The first Shrine upgrade starts at **1,000 Gold plus 400 matching Materials** for every element.
With no prior savings or extra capture income, keeping 400 Materials and selling another 500 at
2 Gold each requires 900 produced Materials. That is roughly **2–3 daily collections** from two
or one productive level-1 Shrines respectively, assuming their 300-capacity stores fill between
visits and at least 400 of the collected Materials match the upgrade. Setup and other spending
can extend this estimate. Save the required Materials across collections in Inventory; its starting
capacity must hold the 400-Material payment without requiring a capacity upgrade first.

The level-2-to-3 Shrine upgrade starts at **15,000 Gold plus 4,000 matching Materials** for every
element. Keeping 4,000 Materials and selling another 7,500 at 2 Gold each requires 11,500 produced
Materials. With no prior savings, extra income, or other spending, that is roughly **five daily
collections from two productive level-2 Shrines**, or **ten from one**, assuming each 1,200-capacity
store fills between visits and enough of the output matches the recipe. These saving periods begin
with those Shrines already built and staffed by sufficiently developed workers. Newly evolved
level-6 Rare pairs take about 26.4 working hours to fill a level-2 store, so less-developed teams
may take longer to reach these budgets. Save the payment in Inventory across collections;
reachable pre-upgrade Inventory capacity must hold all 4,000 required Materials.

Set each price against a representative Base **before** that purchase: its available workers,
storage, element coverage, collection frequency, and capture income. Materials kept for an upgrade
cannot also count as sale income. Verify fixed mixes can be obtained through already available
Shrines and realistic Shop visits, without first needing the slot being purchased. Every recipe
must fit reachable pre-purchase Material capacity, including capacity upgrades' own ingredients.
Keep early fixed-mix requirements modest enough to obtain missing elements through limited Shop
stock; later recipes can require larger quantities as more Shrine slots become available.
More active collection, extra captures, specialization, and prior savings may shorten the wait.
Previously purchased upgrades remain owned after cost changes, with no retroactive charge.

### Shop

The launch Shop has three sections. Material and Featured item purchases use **Gold**;
Inventory upgrades require **Gold plus their fixed elemental Material mix**.

| Section | Launch offers | Availability |
| --- | --- | --- |
| Materials | All six normal elemental Materials | Always listed; limited personal quantities replenish each refresh |
| Featured | One matching pair of existing first-crafted elemental sword and Shield offers | The element rotates and personal stock replenishes hourly |
| Upgrades | Inventory-capacity upgrades paid with Gold and a fixed Material mix | Available according to their existing eligibility and progression rules |

Buying Materials lets players craft a specific element's Equipment before owning that elemental
Shrine. Keep all six craftable variants, including Earth's Atlas Sword and Atlas Shield; every first
Shrine still supports its own matching first craft without depending on Shop stock. Shrines remain
the ongoing production route and train their assigned Mythlings. Buying Materials or Equipment
does not award Shrine-work XP.

Restocking is intended to give players a reason to return for another purchase or craft. Waiting
until the next refresh after using a personal allowance is an accepted part of this pacing.
Players can continue capturing, producing Materials, and developing their Base while waiting.
Evaluate whether this timing encourages return visits during testing.

- Materials and Featured use one hourly refresh schedule shared across servers. Stock belongs to each
  player, so another player's purchases cannot exhaust it. Rejoining, changing servers, or resetting
  does not refresh an allowance. A refresh restores the configured allowance; unused quantities and
  missed refreshes do not accumulate extra stock. Inventory upgrades do not reset with Shop stock.
- All six Materials stay listed even when a player's allowance is exhausted. Players can buy a
  selected whole quantity up to the remaining stock, their Gold, and unreserved Inventory capacity.
- Featured Equipment is the same named, fixed-rarity item available through crafting. Its Gold
  price exceeds buying the Materials and paying the recipe's Gold cost for the same output.
  Players pay for immediate delivery; a purchase uses no Crafting Job, grants an ordinary Equipment
  copy into Inventory, and does not equip it automatically. Higher Equipment upgrades, additional
  archetypes, and Epic/Legendary/Mythical Equipment remain future content.
- Material buy prices exceed their sell prices. Buying Materials, crafting, and selling the result
  must also lose Gold; buying finished Equipment and reselling it cannot make a profit. Tune these
  routes together while keeping duplicate Mythling sales the main early Gold source.
- A Material or Featured purchase grants exactly the displayed item and requested quantity while
  spending Gold and personal stock together. Full Inventory, insufficient Gold/stock, or an expired offer rejects
  the purchase without charging Gold or consuming stock. A refresh cannot silently replace the
  selected offer or change the accepted price; update the view before another purchase attempt.
- An Inventory upgrade spends its full configured Gold and collected Material costs together with
  granting capacity. It uses no restock allowance and needs no empty item slot, but all required
  ingredients must already fit and be owned. Crafting refund reservations remain protected.

Use these **initial tuning values**, keeping them configurable:

| Setting | Starting value |
| --- | --- |
| Shared refresh interval | 1 hour (60 minutes), for both Materials and Featured |
| Stock of each normal Material | 10 per player per refresh at every Base size, enough for one matching sword plus one matching Shield at the initial recipe costs |
| Featured selection | One sword and one Shield of the same element, rotating together |
| Featured rotation | Fire → Water → Earth → Air → Light → Dark → repeat; one element per hour, a six-hour full cycle |
| Featured stock | One copy of each offer per player per refresh |
| Featured price | About 50% above buying the recipe Materials plus paying the crafting Gold cost for the same output |
| Material sell price | Around 20% of its unit Shop buy price |

The Material allowance is based on actual recipe requirements; it lets a player buy inputs for
one complete matching pair before that element's stock is exhausted. Further purchases may require
another refresh. [Initial economy tuning](#initial-economy-tuning) sets the starting quantities and
Gold amounts. Every server follows the same Featured element for the current hourly period;
joining or changing servers does not restart the cycle. Recheck stock and all resale routes when
changing recipes or prices, and validate affordability against ordinary Common capture income and
the early progression targets.

Purchase validation and persistence belong in [Technical Design](TECHNICAL_DESIGN.md#shop-transactions).

### Inventory capacity and overflow

Launch has **Materials, Mythlings, and Equipment** tabs with these initial configurable limits:

| Inventory category | Starting slots | After first upgrade | After final upgrade |
| --- | --- | --- | --- |
| Materials | 12 | 24 | 36 |
| Mythlings | 24 | 36 | 48 |
| Equipment | 12 | 24 | 36 |

Each category has **two sequential, independently purchased upgrades**, each adding **12 slots**
to that category only. The first costs 20,000 Gold plus 50 of each normal Material; the final costs
300,000 Gold plus 200 of each. All three categories use these same prices under the
[upgrade saving targets](#upgrade-saving-targets).

All six normal Materials stack to **1,000 per slot**, separately by Material type. Each owned
Mythling and Equipment copy uses one slot in its category, including assigned Mythlings, equipped
gear, and the protected wooden starter pair. Gold is uncapped and uses no slot. Acquisitions
require unreserved slot or compatible stack space; otherwise show the blocked category and how to
free space.

The 400- and 4,000-Material Shrine upgrade payments occupy one and four Material slots respectively,
so both fit the starting bag when that space is available. Six full level-3 Shrines of different
elements produce 3,600 Materials each: four slots per type, or **24 slots total**. The first Material
upgrade can hold that collection when enough unreserved space is free; existing stock and crafting
reservations still count. Starting Mythling capacity supports 18 assigned workers plus six spares.

- Full Mythling inventory blocks capture progress under the Arena rules.
- Crafting output/refund reservations count against capacity until resolution, including reconnects.
- Shrine Collect transfers only the whole Materials that fit; the remainder stays stored. If nothing
  fits, reject collection without removing output. A partial transfer is a success.
- Selling owned Materials frees their occupied Inventory capacity but does not release crafting
  refund reservations. A sale cannot consume output still in a Shrine or any reserved refund.
- Material Discard requires quantity confirmation, permanently removes that owned quantity, and
  gives no reward. It cannot touch a crafting refund reservation.

## 9. Live events

### Divine Intervention

**Divine Intervention** is the working name for post-launch, mythology-themed live events in which
gods or mythological forces visibly affect a server. Examples may include *Thor's Tempest*,
*Poseidon's Deluge*, or *Hades' Eclipse*.

This system is **not part of the first release and is not ready for implementation**. Its event
types, scheduling, permissions, monetization, rewards, server scope, Mythling-spawn controls, pickup
behavior, presentation, and accessibility rules must be designed and approved in a later GDD
revision. First-release systems must not depend on Divine Intervention or reserve implementation
work for it beyond using data-driven content patterns.

## 10. Player state and reliable actions

Owned Mythlings and progression, Materials, Gold, Equipment/Loadout, Inventory upgrades, current
Shop purchase allowances, Base/Shrine state, unlocks, and active Crafting Jobs persist. Offline
production and crafting follow their rules. Capture meters, Stamina, Shield state, immunity,
elemental combat effects, and live contests are temporary; disconnect or server shutdown clears
them. Reset follows the Base-spawn rule in player flow and clears that character's active and
pending elemental effects and all capture progress. Crossing the Arena boundary or changing
Equipment preserves existing elemental effects and their timers, as defined in
[elemental sword effects](#elemental-sword-effects).

The server validates possessions, currency, eligibility, and rewards. Pending UI is allowed;
unconfirmed grants cannot appear owned. Rejections do not spend costs or grant the requested result,
though normal elapsed production/Stamina accounting may advance. Retries cannot duplicate rewards or
refunds. Preserve the documented combat exception.

[Technical Design](TECHNICAL_DESIGN.md) owns configuration schemas, save data, transactions, and
synchronization. Runtime tuning stays in shared configuration; pacing goals and decisions stay here.

## 11. Acceptance criteria

Verify the rules above through these release scenarios. These checks stay in the GDD; implementation
checks belong in Technical Design and README.

1. **New-player progression and recovery:** begin with the included Crafting Station and two empty
   build slots for Shrines only. Complete a first capture, matching Shrine, collection, Equipment
   recipe, Shrine upgrade, and evolution. Check actual costs against available capacity, then
   recover from ordinary selling/spending and having no Shrine or
   Materials. Verify protected starter gear and enough room for the first craft. Evaluate the
   [early progression targets](#early-progression-targets) for crafting/evolution and the later
   [upgrade saving targets](#upgrade-saving-targets) with one Shrine and the included Station.
   The route charges no Station purchase cost; also check progression when the player
   builds a second Shrine in the other starting slot.
   Repeat the first-craft route for all six starting elements using their matching Stage 1 recipes.
   Verify the [initial economy values](#initial-economy-tuning), including two extra Common sales
   for the first craft's Gold cost while retaining the first worker and producing its five Materials.
   Check upgrade affordability from pre-upgrade production and realistic collection/Shop visits;
   fixed mixes and Inventory limits must not depend on capacity or slots granted by the purchase.
   Verify the 1,000-Gold/400-matching-Material first Shrine upgrade across all six elements and
   accumulation across multiple 300-capacity collections, with room to hold its payment before upgrading.
   Repeat for the 15,000-Gold/4,000-Material level-2-to-3 upgrade, accumulating in reachable
   pre-upgrade Inventory across 1,200-capacity collections. Do not count retained Materials as sale income.
   Check all acquisition/resale routes and the impact of Rare/Epic sale windfalls. Starting Gold
   applies once to new profiles; reconnects and migrations preserve the player's existing balance.
2. **Full and quiet servers:** verify 12 capturable Mythlings before capture opens and the same
   target with one through eight players, accessible Commons, first-Shrine element availability,
   and non-overlapping rings with boundary clearance. Replace each simultaneous capture/despawn
   within three seconds of that contest ending. Claimed models must not delay replacement; overtime
   contests remain counted and do not trigger an extra spawn at their countdown deadline. In
   eight-player sessions, beginners who lose busy contests must still make ordinary progression.
   Verify the initial 75%/20%/5% rarity probabilities and equal element chances within each rarity
   for both initial fill and replacements. Validate selection over many spawns, without requiring
   fixed rarity counts in an individual Arena or changing a form's configured rarity.
   Verify all 18 launch forms use a four-minute lifetime with no initial named-form overrides.
   Initial countdowns begin when capture opens; placement and prefill consume no lifetime. Entering
   or re-entering a ring and later configuration changes must not restart an active spawn's timer.
   Check empty-ring expiry at four minutes and occupied-ring overtime beyond that deadline.
3. **Capture and combat:** check independent meters, decay when switching rings, capacity rejection,
   20/35/60-second uninterrupted captures across all six chains, and equal-rate outside decay.
   Check three seconds outside removes three seconds of earned progress, clamps at zero, and does
   not reset a nonempty meter on re-entry; re-entry still begins a new visit for tie priority. Check
   reset/disconnect cleanup, exact ties, and exactly one award. Check completion at the countdown
   deadline, empty-ring despawn, overtime with preserved meters, new entrants, full-inventory
   occupants, and the last occupant leaving/resetting/disconnecting. Overtime still counts toward
   availability; ended contests cannot resume. Exercise misses, one-hit swings, full-cost blocks,
   and normal jumps within the ring, including the sole occupant jumping at expiry or in overtime.
   Verify that these jumps preserve capture progress and tie priority. Crossing the horizontal
   edge or exceeding the finite vertical allowance starts normal decay and ends that visit;
   the same membership result governs overtime occupancy. Re-entry begins a new uninterrupted visit.
   Exercise immunity, depletion, simultaneous inputs, and raise/lower transitions on mobile and keyboard/mouse.
   Confirm no guarded-time recovery, overlapping attack/protection, or health damage. Verify recovery
   starts as soon as lowering finishes after release or guard break, with fresh eligible input
   required to guard again.
   From full Stamina, with no existing Fire burn or other Stamina change, hold the same Shield
   continuously and verify automatic lowering after three
   accepted blocks with the wooden starter Shield or four with every first-crafted elemental
   variant, including Featured copies. Space valid hits beyond immunity; rejected hits must not
   charge Stamina. The final block still protects and slides normally before guard becomes
   unavailable. Repeat from partially spent Stamina; do not grant a fresh block allowance on raise
   or equip. Ring displacement remains independent of the full-Stamina block count.
   Verify the [initial Stamina values](#initial-stamina-and-attack-tuning): 100 maximum/spawn,
   20 per accepted sword swing, 30/25 block costs and matching guard thresholds, and 10 per second
   recovery only when fully lowered. Check recovery during attacks, paid misses, zero recovery
   during every guard phase, start-to-start cooldown enforcement, and no refill from Arena entry
   or Equipment changes. Check the nine-swing reference without elemental Stamina changes and with
   action timing that permits one-second starts, then verify animation locks and immunity separately;
   attempted swings are not guaranteed hits.
   Verify every [elemental sword effect](#elemental-sword-effects) on accepted unblocked hits,
   including identical behavior for crafted and Featured copies. Blocked/rejected hits grant no
   new effect or Dark Stamina return. Check Fire alongside normal recovery and guard depletion,
   Water/Earth without blocking forced movement, Earth after landing with no queued/repeated roots
   during its recovery window, Air as one hit reaction, Light weakening outgoing horizontal force
   without changing upward launch, Shield slides, or block costs, and Dark's cap and sustained-attack
   constraint. Verify the [initial elemental effect values](#initial-elemental-effect-tuning),
   including Fire's 100-to-90 fully lowered reference, Earth's landing deadline and post-root recovery,
   Light's reduction of Air's complete horizontal push, and Dark charging 20 before returning 3.
   Across different elements and attackers, verify only the first timed negative effect applies, with no replacement,
   stacking, extension, or queue; ignored effects must not cancel normal hit knockback or immunity.
   A pending Earth root occupies the same limit until it ends or times out. Its recovery window
   prevents another Earth root while allowing other timed effects when the limit is free. Air and
   Dark still apply on eligible hits against affected targets. Repeated Arena exits/re-entries near
   a Capture Ring and Equipment changes by either player must not clear, pause, or restart active
   effects, pending roots, landing timeouts, or root recovery windows. Check ongoing Fire and Earth
   landing outside the Arena, with readable status feedback and Stamina visible during Fire.
   Reject new hits when either participant is outside the Arena; guard remains unavailable outside.
   Reset/disconnect must clear the affected character's active and pending effects and all capture
   progress.
4. **Production and evolution:** compare online/offline accrual, full storage, partial collection,
   assignment changes, evolution, and balance updates. Verify chronological XP/levels, deterministic Yield,
   current-rate unresolved offline time, and preserved individual identity/progression through
   both evolutions in each of the six chains, with no further evolution at Stage 3. Check that
   swaps and evolution preserve Shrine progress, moving workers does not
   transfer that progress, and removing/reassigning all workers pauses/resumes without catch-up.
   Verify activity-based XP for simultaneous workers and mid-batch swaps, including unfinished-item
   work and the normal XP award for the batch that fills storage; no overflow is banked. Earned XP
   remains with an owned Mythling when its former Shrine is dismantled.
   Check all six Common forms at the initial 12-Material/hour base Yield. With level scaling disabled,
   verify one Material per five eligible working minutes and five in 25 minutes, resolved through
   the normal batch schedule. Check all six Rare forms at 18/hour and all six Epic forms at 32/hour:
   nominally one Material per 200 and 112.5 working seconds respectively, using that same schedule.
   Item completion must not introduce extra output or XP awards.
   XP continues while an item is unfinished; the first evolution still targets roughly 30 eligible
   working minutes. Do not require a completed Material before earning XP.
   Verify linear level scaling at levels 1, 2, 50, and 100: 1.00, 1.01, 1.49, and 1.99 times the
   current form's base Yield. Evolution retains the level and applies
   the bonus to the new base Yield without compounding or recalculating already earned work.
   Verify the shared 1-XP/second rate and 120-times-current-level XP cost: level 6 after 30 working
   minutes, level 40 after 26 working hours, and level 100 after 165 working hours, subject to batch
   boundaries. Multiple levels earned offline must affect later work in chronological order.
   Evolution remains manual, preserves progression, and permits consecutive eligible evolutions.
   New captures receive no Luck or Trait rolls. Equal forms and levels produce equally online and
   offline, including when preserved legacy Luck/Trait data differs. Verify that worker changes
   preserve earned work without recalculating it from the final roster. Stored Materials remain
   whole; unfinished progress and activity-based XP remain independent. Repeated requests must not
   grant output or XP twice.
   Verify the 1/2/3-slot Shrine levels and 300/1,200/3,600 storage, matching-Material/Gold upgrade costs,
   and rejection at level 3. An empty new slot grants no output; an upgrade preserves existing
   assignments, stored output, unfinished work, and earned XP without multiplying worker rates.
   Verify Common/Rare/Epic form mapping and higher base Yield at each stage, with every form
   eligible for its configured Arena spawn. Acquisitions at different stages in the same chain
   grant no random production bonuses; evolution changes form and rarity without awarding an extra
   rarity-based production or XP multiplier.
   New captures at all three stages retain their caught form and start at level 1 with 0 XP.
   Evolution and reconnect retain earned levels/XP; Stage 3 still levels up to the normal cap.
5. **Crafting:** start with near-full inventories; verify reservations, exact cancellation refunds,
   automatic completion, and the completion/cancellation boundary. Repeat after reconnect and recipe
   changes. Exactly one output/refund is granted and the station becomes available afterward.
   All launch recipes start with a 60-second duration; existing jobs retain their recorded deadline.
   Verify fixed variant recipes, matching Material costs, equal base sword statistics with the
   correct elemental effect, equal Shield gameplay values across variants, and the promised variant
   surviving completion, equip/unequip, reset, and reconnect.
   Repeated copies of the same named Equipment have the same configured rarity, consistent across
   recipe preview, active job, completion feedback, and Inventory.
   Reject new Stage 2 or later crafting/upgrading requests without spending costs or changing items.
6. **Inventory and dismantling:** exercise allowed sales, final-copy Mythling sales, protected
   starter gear, partial collection, confirmed Material discard, and empty-Shrine removal. Invalid
   actions retain owned/stored items; unfinished production cannot strand an otherwise empty Shrine.
   Mythlings of the same form sell for the same fixed amount across levels, inactive legacy data, and
   acquisition routes. Verify equal launch values within each rarity and increasing Common/Rare/Epic
   values. Evolution switches to the target form's value; stale form/price requests and sale retries
   cannot remove a different Mythling, grant the wrong payout, or pay twice. Final-copy sales remain
   allowed.
   Collect online/offline Materials and sell selected whole quantities for the configured Gold
   amount. Verify retries cannot duplicate Gold, stale quantities are rejected, and sales never
   consume Shrine output or release crafting reservations. Discard still grants no Gold.
   Verify that only Shrines occupy Base build slots, two built Shrines leave the Station usable,
   and each expansion spends its Gold and fixed Material mix together to permanently add one slot,
   from two up to six. At the limit, another purchase must spend no resources or grant capacity.
   Verify the four prices in [initial economy tuning](#initial-economy-tuning), including equal
   quantities of all six normal Materials. Repeat with duplicate-element Shrines and Shop-sourced
   missing ingredients; no expansion may require dismantling a Shrine or owning every producer.
   Dismantling, reset, reconnect, and later price changes retain purchased slots. The permanent
   Station cannot be removed.
7. **Shop:** buy each normal Material without its matching Shrine, and verify all six remain listed
   after stock is exhausted. Restock personal quantities and rotate eligible Featured Equipment on
   the shared schedule; one player's purchase must not affect another's allowance. Reconnect, reset,
   and server changes preserve consumption until refresh; missed refreshes do not accumulate stock.
   Check exact charges, named Equipment variants, immediate delivery, and no automatic equip or XP.
   Insufficient Gold/stock, full or reserved Inventory, and expired offers consume no Gold or stock.
   Exercise concurrent purchases, retries, and a purchase crossing refresh without duplicate grants
   or a substituted item/price. Inventory upgrades retain their purchased state through refresh.
   Verify their Gold and fixed Material mixes, rejection of missing ingredients or substitutions,
   protected crafting reservations, and a full Inventory upgrading when it already holds every cost.
   Required ingredients must fit pre-upgrade capacity; cost changes cannot revoke or recharge paid levels.
   Check the [Inventory limits](#inventory-capacity-and-overflow): two sequential +12-slot purchases
   per category, independent ownership, and rejection without spending at the maximum. Verify
   the 20,000-Gold/50-of-each and 300,000-Gold/200-of-each costs separately for every category,
   1,000-per-type Material stacks, assigned/equipped ownership counting, and the protected starter pair.
   Collect six different full level-3 Shrine stores into 24 free Material slots; repeat with existing
   stock and crafting reservations to verify partial collection without overflow or lost output.
   Check Material purchase/resale, purchased-input craft/resale, and Equipment purchase/resale prices
   together, alongside the existing first-craft route from every Shrine element.
   Verify the hourly schedule for both Materials and Featured, one matching sword and Shield pair,
   one-copy Featured limits, and Material allowances covering one matching pair. Check the shared
   Fire → Water → Earth → Air → Light → Dark rotation, its six-hour repeat, and consistent offers
   across servers without restarting the cycle on join. After exhausting stock, players can continue
   ordinary gameplay and return at refresh; assess return visits and whether the wait supports pacing.
8. **Persistence and reset:** retain owned progress, jobs, and reservations across sessions. Reset
   returns to Base, clears capture/old-character combat state, and never regrants starter items.
   Recreating the Base preserves the same Station and job without duplicating either.
   Delayed requests and stale UI cannot duplicate or alter another operation's result.
9. **Launch presentation:** inspect included menus, empty/full/loading/error states, touch controls,
   safe areas, and accessible feedback against UI Guidelines. Excluded/deferred systems have no
   launch actions or placeholders. Mythling and Equipment presentation uses names and rarity without
   stage numbers; Mythling XP levels remain visible. Evolution previews identify the named next form
   and its changes. Boundaries contain normal movement and configured knockback.

## 12. Open decisions

### Launch content and tuning

- Creature concepts, names, visuals, and statistics for the [six launch Mythling
  chains](#launch-mythling-roster). One chain per element and three stages per chain are decided;
  the roster does not require a separate chain for every element/rarity combination.
- Names and icons for the six normal Materials, with each elemental Shrine's output mapped to its
  matching Material. Use the same named Material consistently in production, recipes, upgrades,
  Shop offers, and Inventory.
- Equipment colors and assets for the approved [named sword and Shield pairs](#stage-1-equipment-variants).
  The introductory craftable Equipment stage requires all six element variant routes; recipe
  quantities and Gold costs are set in [initial economy tuning](#initial-economy-tuning), with a
  60-second initial craft duration.
- Ring spacing and boundary clearance under both full and quiet server conditions. Validate the
  layout against the 12-Mythling population and arrival time before the shared four-minute lifetime
  ends. Initial spawn probabilities, capture times, decay, and lifetimes are set in
  [capture and spawn tuning](#initial-capture-and-spawn-tuning).
- Validate the approved capture/spawn tuning, sale payouts, 12/18/32 base Yield, XP curve,
  deterministic online/offline production, storage, and craft duration together against the early
  progression targets, upgrade saving targets, and approximately daily developed-Epic collection.
- Equipment knockback/protection values, attack contact windows, full swing and guard transition
  durations, temporary immunity, and cosmetic effects. Validate them with the approved
  [initial Stamina and attack tuning](#initial-stamina-and-attack-tuning) and three/four-block
  Shield targets. Initial Stamina, costs, thresholds, recovery rate, and sword cooldown are set.
- Validate the [initial elemental effect values](#initial-elemental-effect-tuning), including
  Earth's landing timeout and recovery window, alongside ordinary combat and capture timing. Keep
  the approved six effect roles, unblocked-hit requirement, first-effect-wins limit for timed
  negative effects (including pending Earth roots), immediate Air/Dark benefits, and Dark's
  sustained-attack constraint. Arena transitions and Equipment changes preserve existing effects
  and their timers.
- Validate the starting Mythling payouts, Material prices, Equipment prices, and recipe quantities
  in [initial economy tuning](#initial-economy-tuning). The [Shop's initial tuning](#shop) fixes an
  hourly shared refresh, 10 of each Material, and a matching sword and Shield pair with one copy of
  each per player. The fixed Fire → Water → Earth → Air → Light → Dark rotation repeats every six
  hours. Revisit the starting values during pacing tests and recheck the purchase/craft/resale
  constraints together.
- Tune actual costs, rates, and capacities against the
  [early progression targets](#early-progression-targets) for beginners choosing less-contested
  captures; also check players pursuing competitive targets.

### Future-update design

- Luck, Lucky Yield, and Passive Traits: whether and how to introduce individual variation,
  acquisition rolls, production effects, and player presentation. Their earlier prototype values
  are not approved launch tuning; revisit the design before activating preserved legacy data.
- Equipment upgrades beginning with Stage 2: costs, item and variant identity preservation, and
  element-specific statistics and rarity assignments. These upgrades are outside the MVP; exact
  rules and update timing remain to be designed. Any progression of elemental effects beyond the
  approved launch set needs its own design; an upgrade does not automatically require a rarity increase.
- Additional weapon archetype selection, update order, movesets, and exact tuning. Launch uses
  swords and separate Shields only; [two-handed weapons trading Shield access for stronger
  knockback](#equipment-compatibility) is already decided for later updates.
- Equipment storage box: whether it opens the existing inventory or introduces separate storage,
  including any additional capacity and transfer rules.
- Combat Consumable catalogue, six-slot Hotbar activation bindings, stacking/refresh behavior,
  cooldowns, and disconnect behavior.
- Waiting-job queues, Crafting Station upgrade benefits, acquisition and placement of additional
  stations outside Shrine build slots, and Consumable recipes.
- Gamepad controls and accessibility verification.
- Mythling treats, combat health/attack, and a separate brawl/PvP mode.
- Rare-Material acquisition, recipes, scarcity, and storage-unit costs, including whether a future
  Luck system supplies them.
