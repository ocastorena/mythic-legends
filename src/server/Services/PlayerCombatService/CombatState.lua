-- Server-owned transient combat resources and Shield stance.
-- Static balance comes from Metadata/Weapons; this module owns only per-player state.

local CombatState = {}

type MovementSnapshot = {
	character: Model,
	humanoid: Humanoid,
	walkSpeed: number,
	jumpPower: number,
	jumpHeight: number,
	autoRotate: boolean,
}

type PlayerState = {
	stamina: number,
	lastStaminaUpdate: number,
	immunityUntil: number,
	shieldTool: Tool?,
	movement: MovementSnapshot?,
}

local states: { [Player]: PlayerState } = {}
local maximumStamina = 100
local staminaRegenPerSecond = 18

local STAMINA_ATTRIBUTE = "CombatStamina"
local MAX_STAMINA_ATTRIBUTE = "CombatMaxStamina"
local SHIELD_ACTIVE_ATTRIBUTE = "ShieldActive"
local IMMUNE_ATTRIBUTE = "KnockbackImmune"

local function setShieldPresentation(tool: Tool?, active: boolean)
	if not tool then
		return
	end

	tool:SetAttribute(SHIELD_ACTIVE_ATTRIBUTE, active)
	local highlight = tool:FindFirstChild("ShieldActiveHighlight", true)
	if highlight and highlight:IsA("Highlight") then
		-- Guard state is communicated by the pose. Keep the persistent outline off;
		-- the short ShieldImpactFlash still communicates a successful block.
		highlight.Enabled = false
	end
end

local function restoreMovement(state: PlayerState)
	local movement = state.movement
	state.movement = nil
	if not movement then
		return
	end

	local humanoid = movement.humanoid
	if humanoid.Parent and humanoid.Health > 0 and humanoid.Parent == movement.character then
		humanoid.WalkSpeed = movement.walkSpeed
		humanoid.JumpPower = movement.jumpPower
		humanoid.JumpHeight = movement.jumpHeight
		humanoid.AutoRotate = movement.autoRotate
	end
end

local function refreshStamina(player: Player, state: PlayerState, now: number)
	local elapsed = math.max(0, now - state.lastStaminaUpdate)
	state.lastStaminaUpdate = now
	if elapsed > 0 and state.stamina < maximumStamina then
		state.stamina = math.min(maximumStamina, state.stamina + elapsed * staminaRegenPerSecond)
	end

	player:SetAttribute(STAMINA_ATTRIBUTE, state.stamina)
	player:SetAttribute(MAX_STAMINA_ATTRIBUTE, maximumStamina)

	if state.immunityUntil > 0 and now >= state.immunityUntil then
		state.immunityUntil = 0
		player:SetAttribute(IMMUNE_ATTRIBUTE, false)
	end
end

local function getState(player: Player): PlayerState
	local state = states[player]
	if state then
		return state
	end

	state = {
		stamina = maximumStamina,
		lastStaminaUpdate = os.clock(),
		immunityUntil = 0,
		shieldTool = nil,
		movement = nil,
	}
	states[player] = state
	player:SetAttribute(STAMINA_ATTRIBUTE, maximumStamina)
	player:SetAttribute(MAX_STAMINA_ATTRIBUTE, maximumStamina)
	player:SetAttribute(SHIELD_ACTIVE_ATTRIBUTE, false)
	player:SetAttribute(IMMUNE_ATTRIBUTE, false)
	return state
end

function CombatState.Configure(config: any)
	local stamina = type(config) == "table" and config.stamina or nil
	if type(stamina) == "table" then
		if type(stamina.maximum) == "number" then
			maximumStamina = math.max(1, stamina.maximum)
		end
		if type(stamina.regenPerSecond) == "number" then
			staminaRegenPerSecond = math.max(0, stamina.regenPerSecond)
		end
	end
end

function CombatState.AddPlayer(player: Player)
	getState(player)
end

function CombatState.Step(player: Player, now: number)
	local state = getState(player)
	refreshStamina(player, state, now)

	-- Movement can be changed by character scripts after the stance starts. Reassert the
	-- GDD contract while active instead of relying on one assignment at toggle time.
	local movement = state.movement
	if movement and movement.humanoid.Parent == movement.character and movement.humanoid.Health > 0 then
		movement.humanoid.WalkSpeed = 0
		movement.humanoid.JumpPower = 0
		movement.humanoid.JumpHeight = 0
		movement.humanoid.AutoRotate = false
	end
end

function CombatState.HasStamina(player: Player, amount: number): boolean
	local state = getState(player)
	refreshStamina(player, state, os.clock())
	return state.stamina + 0.001 >= math.max(0, amount)
end

function CombatState.TrySpendStamina(player: Player, amount: number): boolean
	local state = getState(player)
	refreshStamina(player, state, os.clock())
	local cost = math.max(0, amount)
	if state.stamina + 0.001 < cost then
		return false
	end

	state.stamina = math.max(0, state.stamina - cost)
	player:SetAttribute(STAMINA_ATTRIBUTE, state.stamina)
	return true
end

function CombatState.SpendStaminaUpTo(player: Player, amount: number): number
	local state = getState(player)
	refreshStamina(player, state, os.clock())
	local spent = math.min(state.stamina, math.max(0, amount))
	state.stamina = math.max(0, state.stamina - spent)
	player:SetAttribute(STAMINA_ATTRIBUTE, state.stamina)
	return state.stamina
end

function CombatState.GetStamina(player: Player): number
	local state = getState(player)
	refreshStamina(player, state, os.clock())
	return state.stamina
end

function CombatState.IsImmune(player: Player, now: number?): boolean
	local state = getState(player)
	local currentTime = now or os.clock()
	refreshStamina(player, state, currentTime)
	return currentTime < state.immunityUntil
end

function CombatState.GrantImmunity(player: Player, durationSeconds: number)
	local state = getState(player)
	state.immunityUntil = math.max(state.immunityUntil, os.clock() + math.max(0, durationSeconds))
	player:SetAttribute(IMMUNE_ATTRIBUTE, state.immunityUntil > os.clock())
end

function CombatState.IsShieldActive(player: Player): boolean
	return getState(player).shieldTool ~= nil
end

function CombatState.GetShieldTool(player: Player): Tool?
	return getState(player).shieldTool
end

function CombatState.SetShieldActive(player: Player, tool: Tool?, active: boolean): boolean
	local state = getState(player)
	if not active then
		setShieldPresentation(state.shieldTool, false)
		state.shieldTool = nil
		restoreMovement(state)
		player:SetAttribute(SHIELD_ACTIVE_ATTRIBUTE, false)
		return true
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not (tool and character and tool.Parent == character and humanoid and humanoid.Health > 0) then
		return false
	end

	if state.shieldTool == tool then
		return true
	end

	if state.shieldTool and state.shieldTool ~= tool then
		setShieldPresentation(state.shieldTool, false)
		restoreMovement(state)
	end

	state.shieldTool = tool
	state.movement = {
		character = character,
		humanoid = humanoid,
		walkSpeed = humanoid.WalkSpeed,
		jumpPower = humanoid.JumpPower,
		jumpHeight = humanoid.JumpHeight,
		autoRotate = humanoid.AutoRotate,
	}
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
	setShieldPresentation(tool, true)
	player:SetAttribute(SHIELD_ACTIVE_ATTRIBUTE, true)
	return true
end

function CombatState.RemovePlayer(player: Player)
	local state = states[player]
	if state then
		setShieldPresentation(state.shieldTool, false)
		restoreMovement(state)
	end
	states[player] = nil
	player:SetAttribute(SHIELD_ACTIVE_ATTRIBUTE, false)
	player:SetAttribute(IMMUNE_ATTRIBUTE, false)
end

return CombatState
