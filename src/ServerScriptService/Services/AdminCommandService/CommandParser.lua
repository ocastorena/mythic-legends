--!strict
-- ServerScriptService/Services/AdminCommandService/CommandParser

local CommandParser = {}

export type Command = { name: "teleport" | "event", argument: string }

local USAGE = "Use /admin teleport <element|base> or /admin event blockstorm."

function CommandParser.Parse(text: string): (Command?, string?)
	local tokens = {}
	for token in string.gmatch(string.lower(text), "%S+") do
		table.insert(tokens, token)
		if #tokens > 3 then
			return nil, USAGE
		end
	end
	if tokens[1] ~= "/admin" then
		return nil, USAGE
	end
	if tokens[2] == "teleport" then
		if not tokens[3] then
			return nil, "Use /admin teleport <element|base>."
		end
		return { name = "teleport", argument = tokens[3] }, nil
	end
	if tokens[2] == "event" then
		if tokens[3] ~= "blockstorm" then
			return nil, "Use /admin event blockstorm."
		end
		return { name = "event", argument = tokens[3] }, nil
	end
	return nil, USAGE
end

return CommandParser
