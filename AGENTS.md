# Mythic Legends — Agent Guidance

## Product context

- Read `docs/Mythic_Legends_GDD.md` before changing gameplay, economy, progression, Arena, Shrine, crafting, inventory, or live-event systems.
- Do not add excluded systems—eggs, summoning, gacha, Elemental Prism capture, or health-based combat—without explicit approval.
- Keep the MVP's arena combat non-lethal and positional: server-validated knockback, ragdoll, stamina, shields, and Capture Rings.

## Architecture

- Follow the Rojo structure and naming conventions in `README.md`.
- Keep capture, currency, production, crafting, inventory, event rewards, and permission checks server-authoritative.
- Store static content and balance data in `src/shared/Metadata`.
- Persist only mutable player state and metadata IDs. Do not duplicate static metadata in player saves.
- Keep player-created or randomly rolled values, such as Mythling Luck and Passive Trait IDs, in saved player state.
- Keep tuning values configurable; do not hard-code economy, production, cooldown, spawn, or event-balance values into client logic.

## Verification and generated files

- Run the relevant Rojo build and Selene lint checks when the tools are available before handing off implementation work.
- Do not commit or edit generated artifacts such as `sourcemap.json` or built Roblox place files unless explicitly requested.
- Preserve unrelated user changes in the worktree.
