--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Signal = require(script.Parent.Signal)

local PlayerFlags = {}

type flagValue = number | string | boolean | {}

export type PlayerFlag<V = flagValue> = {
	Id: string,
	Value: V,
	Player: Player,

	_value: V,

	Remove: (self: any) -> ()
}

local PlayerFlag = {}
PlayerFlag.__index = function(self: PlayerFlag<any>, index)
	if PlayerFlag[index] then
		return PlayerFlag[index]
	elseif index == "Value" then
		storeFlag(self)
		return getFlagValue(self)
	else
		error(`{index} is not a valid member of PlayerFlag {self.Id}`)
	end
end

PlayerFlag.__newindex = function(self: PlayerFlag, index, value)
	if index == "Value" then
		self._value = value
		storeFlag(self)
	end
end

local Config = {
	FlagAttributePrefix = "__Flag__"
}

--[[
	PlayerFlags module
	
	Allows to add 'Flags' to players to temporarily store states and values.
]]

function storeFlag(flag: PlayerFlag)
	local player = flag.Player
	local attributeName = `{Config.FlagAttributePrefix}{flag.Id}`

	if typeof(flag._value) == "table" then
		local encodedValue = HttpService:JSONEncode(flag._value)
		player:SetAttribute(attributeName, encodedValue)
	else
		player:SetAttribute(attributeName, flag._value)
	end
end

function getFlagValue(flag: PlayerFlag)
	local player = flag.Player
	local value = flag._value
	if type(value) == "string" and (string.sub(value, 1, 1) == "{" or string.sub(value, 1, 1) == "[") then
		local success, decoded = pcall(HttpService.JSONDecode, HttpService, value)
		if success then
			return decoded
		end
	end
	return value
end

function createFlag<V>(player: Player, flag_id: string, value: V): PlayerFlag<V>
	local flag = setmetatable({
		Id = flag_id,
		Player = player,
		_value = value
	}, PlayerFlag) :: PlayerFlag

	return flag
end

function PlayerFlags.ClearFlags(player: Player)
	for name, value in pairs(player:GetAttributes()) do
		local prefix = string.sub(name, 1, #Config.FlagAttributePrefix)
		if prefix == Config.FlagAttributePrefix then
			player:SetAttribute(name, nil)
		end
	end
end

function PlayerFlags.HasFlag(player: Player, flag_id: string): boolean
	local attributeName = `{Config.FlagAttributePrefix}{flag_id}`
	return player:GetAttribute(attributeName) ~= nil
end

-- Get flag value directly without creating flag object
-- If flag not present will return nil
function PlayerFlags.GetFlagValue(player: Player, flag_id: string): flagValue?
	if not PlayerFlags.HasFlag(player, flag_id) then
		return nil
	end

	local attributeName = `{Config.FlagAttributePrefix}{flag_id}`
	local value = player:GetAttribute(attributeName)

	-- Try JSON decode
	if type(value) == "string" and (string.sub(value, 1, 1) == "{" or string.sub(value, 1, 1) == "[") then
		local success, decoded = pcall(HttpService.JSONDecode, HttpService, value)
		if success then
			return decoded
		end
	end

	return value
end

-- Create a flag if not present yet, if it exists returns the existing one
-- To change the flag's value, use Flag.Value
-- When a flag is created its value defaults to true, change default_value to override this
function PlayerFlags.Flag<V>(player: Player, flag_id: string, default_value: V?): PlayerFlag<V>
	assert(player and player:IsA("Player"), "First argument must be a Player")
	assert(type(flag_id) == "string" and #flag_id > 0, "Flag ID must be a non-empty string")
	default_value = if default_value == nil then true else default_value

	if PlayerFlags.HasFlag(player, flag_id) then
		local attributeName = `{Config.FlagAttributePrefix}{flag_id}`
		local flagValue = player:GetAttribute(attributeName)

		-- Handle JSON decoding for tables
		if typeof(default_value) == "table" and type(flagValue) == "string" then
			local success, decoded = pcall(HttpService.JSONDecode, HttpService, flagValue)
			flagValue = if success then decoded else default_value
		end

		return createFlag(player, flag_id, flagValue)
	end
	return createFlag(player, flag_id, default_value)
end

function PlayerFlags.GetFlags(player: Player): {[string]: PlayerFlag<flagValue>}
	local flags = {}
	for name, value in pairs(player:GetAttributes()) do
		local prefix = string.sub(name, 1, #Config.FlagAttributePrefix)
		if prefix == Config.FlagAttributePrefix then
			local flagId = string.sub(name, #Config.FlagAttributePrefix + 1)

			-- Try to decode JSON if it looks like JSON
			if type(value) == "string" and (string.sub(value, 1, 1) == "{" or string.sub(value, 1, 1) == "[") then
				local success, decoded = pcall(HttpService.JSONDecode, HttpService, value)
				if success then
					value = decoded
				end
			end

			flags[flagId] = createFlag(player, flagId, value)
		end
	end
	return flags
end

-- Returns a signal that fires when the given flag_id is added
-- If the flag is already present it will fire immediately
-- This is slightly expensive to use
-- The signal will fire with the PlayerFlag object as its only argument
function PlayerFlags.GetFlagAddedSignal(player: Player, flag_id: string): typeof(Signal.New())
	local signal = Signal.New()
	local attributeName = `{Config.FlagAttributePrefix}{flag_id}`

	-- Fire immediately if flag already exists
	if player:GetAttribute(attributeName) ~= nil then
		task.defer(function()
			signal:Fire(PlayerFlags.Flag(player, flag_id))
		end)
	end

	-- Connect to attribute changes
	local conn
	conn = player:GetAttributeChangedSignal(attributeName):Connect(function()
		local value = player:GetAttribute(attributeName)
		if value ~= nil then
			-- Only fire when the attribute *appears* (not when removed)
			signal:Fire(PlayerFlags.Flag(player, flag_id))
		end
	end)

	return signal
end

-- Fires when the given flag_id's value gets set to nil (Removed)
-- Will NOT fire instantly if not present (unlike GetFlagAddedSignal)
function PlayerFlags.GetFlagRemovedSignal(player: Player, flag_id: string): typeof(Signal.New())
	local signal = Signal.New()
	local attributeName = `{Config.FlagAttributePrefix}{flag_id}`

	local conn
	conn = player:GetAttributeChangedSignal(attributeName):Connect(function()
		local value = player:GetAttribute(attributeName)
		if value == nil then
			signal:Fire()
		end
	end)

	return signal
end


function PlayerFlag:Remove()
	local attributeName = `{Config.FlagAttributePrefix}{self.Id}`
	self.Player:SetAttribute(attributeName, nil)
end

return PlayerFlags
