--!strict
-- StarterPlayer/StarterPlayerScripts/Types
-- Client presentation and controller contracts. Authoritative payloads remain shared.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SharedTypes = require(ReplicatedStorage.Shared.Types)

export type ProductionStatus = SharedTypes.ProductionStatus
export type ProductionCollection = SharedTypes.ProductionCollection
export type LocalDataApi = {
	OnStateChanged: RBXScriptSignal,
	Peek: (string) -> any?,
	GetRevision: () -> number,
}
export type InventoryEquipmentEntry = {
	quantity: number,
	equipped: boolean,
	textureId: string,
	instanceId: string?,
	previewModel: Instance?,
}
export type InventoryEquipmentMap = { [string]: InventoryEquipmentEntry }
export type InventoryEquipmentViewProps = {
	isVisible: () -> boolean,
	onSnapshot: (InventoryEquipmentMap) -> (),
}
export type InventoryEquipmentSession = {
	Close: () -> (),
	Refresh: () -> (),
	Equip: (string) -> (),
	Destroy: () -> (),
}
export type InventoryControllerApi = {
	OnEquipmentChanged: RBXScriptSignal,
	RequestEquipmentSnapshot: () -> InventoryEquipmentMap,
	Equip: (string) -> boolean,
	DeleteMythling: (string) -> boolean,
	BindEquipmentView: (InventoryEquipmentViewProps) -> InventoryEquipmentSession,
}
export type StandSessionProps = {
	onPending: (boolean) -> (),
	onStatus: (ProductionStatus?) -> (),
	onAssigned: (string?) -> (),
	onCollection: (ProductionCollection?) -> (),
}
export type StandSession = {
	Open: (number) -> (),
	Close: () -> (),
	Refresh: () -> (),
	Collect: () -> (),
	Assign: (string, string?) -> (),
	Remove: (string) -> (),
	Destroy: () -> (),
}
export type StandControllerApi = {
	OnStandRequested: RBXScriptSignal,
	GetProductionStatus: (number) -> ProductionStatus?,
	Collect: (number) -> ProductionCollection?,
	Place: (number, string) -> boolean,
	Remove: (number, string) -> boolean,
	BindSession: (StandSessionProps) -> StandSession,
}
export type HotbarSlotView = {
	button: ImageButton,
	icon: ImageLabel,
	label: TextLabel,
	keyLabel: TextLabel,
	ring: UIStroke,
}
export type HotbarView = {
	screenGui: ScreenGui,
	tray: Frame,
	slots: { HotbarSlotView },
}
export type HotbarControllerApi = { BindView: (HotbarView) -> () -> () }
export type StaminaView = { container: Frame, fill: Frame }
export type CombatActionView = {
	root: Frame,
	attackButton: ImageButton,
	attackIcon: Frame,
	shieldButton: ImageButton,
	shieldIcon: Frame,
	relayout: () -> (),
}
export type CombatControllerApi = {
	BindView: (CombatActionView) -> () -> (),
	BindStaminaView: (StaminaView) -> () -> (),
}
export type ClientContext = { PlayerScripts: Instance, LocalData: LocalDataApi }
export type Controller = {
	Init: (ClientContext) -> (),
	Start: () -> (),
	Stop: () -> (),
}

return {}
