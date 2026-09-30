--!strict
-- ReplicatedStorage/Shared/Configurations/ShrineInteractions

local FreezeUtil = require(script.Parent.Parent.FreezeUtil)

-- Permanent Base slot anchors are authored separately from replaceable Shrine visuals.
return FreezeUtil.DeepFreeze({
	slotsFolderName = "ShrineSlots",
	slotNamePrefix = "Slot",
	promptAttachmentName = "ShrinePromptAttachment",
	interactionDistanceStuds = 4,
})
