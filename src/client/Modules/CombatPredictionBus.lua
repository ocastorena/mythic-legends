-- A local-only presentation channel shared by the combat input and VFX controllers.
-- Predictions never cross the network through this object and cannot apply gameplay.

local CombatPredictionBus = Instance.new("BindableEvent")
CombatPredictionBus.Name = "CombatPredictionBus"

return CombatPredictionBus
