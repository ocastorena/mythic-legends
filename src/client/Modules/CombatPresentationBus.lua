-- A local-only presentation channel shared by the combat and VFX controllers.
-- It renders attacker feedback at blade contact without waiting for the server relay.

local CombatPresentationBus = Instance.new("BindableEvent")
CombatPresentationBus.Name = "CombatPresentationBus"

return CombatPresentationBus
