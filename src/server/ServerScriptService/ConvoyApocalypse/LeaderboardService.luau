--!strict
--[[
	Global leaderboards: the furthest distance and the most kills anyone has
	managed in a single run, across every server. Backed by OrderedDataStores,
	which an unpublished place cannot use; there the boards just stay empty.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Remotes = require(Shared:WaitForChild("Remotes"))

local LeaderboardService = {}

local BOARD_SIZE = 15
-- The sorted lists are cached this long; one fetch serves every player asking.
local CACHE_SECONDS = 60

local distanceStore: OrderedDataStore? = nil
local killsStore: OrderedDataStore? = nil

export type Entry = { name: string, value: number, userId: number }

local cache: { fetchedAt: number, distance: { Entry }, kills: { Entry }, available: boolean } = {
	fetchedAt = -math.huge,
	distance = {},
	kills = {},
	available = true,
}
local names: { [number]: string } = {}

local function nameFor(userId: number): string
	local known = names[userId]
	if known then
		return known
	end
	local ok, result = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local name = if ok then result else "Player " .. tostring(userId)
	names[userId] = name
	return name
end

local function fetch(store: OrderedDataStore): ({ Entry }, boolean)
	local ok, pages = pcall(function()
		return store:GetSortedAsync(false, BOARD_SIZE)
	end)
	if not ok then
		return {}, false
	end
	local entries: { Entry } = {}
	for _, item in pages:GetCurrentPage() do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, { name = nameFor(userId), value = item.value, userId = userId })
		end
	end
	return entries, true
end

local function refresh()
	if os.clock() - cache.fetchedAt < CACHE_SECONDS then
		return
	end
	cache.fetchedAt = os.clock()
	if not distanceStore or not killsStore then
		cache.available = false
		return
	end
	local distance, okA = fetch(distanceStore)
	local kills, okB = fetch(killsStore)
	cache.distance = distance
	cache.kills = kills
	cache.available = okA and okB
end

-- Records a finished run. Only a better score than the stored one is kept.
function LeaderboardService.Submit(player: Player, distance: number, kills: number)
	local key = tostring(player.UserId)
	local function submit(store: OrderedDataStore?, value: number)
		if not store or value <= 0 then
			return
		end
		task.spawn(function()
			local ok, err = pcall(function()
				store:UpdateAsync(key, function(old)
					if old and old >= value then
						return nil
					end
					return math.floor(value)
				end)
			end)
			if not ok then
				warn("[LeaderboardService] could not record score:", err)
			end
		end)
	end
	submit(distanceStore, distance)
	submit(killsStore, kills)
end

function LeaderboardService.Init()
	local ok, err = pcall(function()
		distanceStore = DataStoreService:GetOrderedDataStore("ConvoyBoard_Distance_v1")
		killsStore = DataStoreService:GetOrderedDataStore("ConvoyBoard_Kills_v1")
	end)
	if not ok then
		warn("[LeaderboardService] leaderboards unavailable:", err)
	end

	Remotes.Function("GetLeaderboards").OnServerInvoke = function(_player: Player)
		refresh()
		return { distance = cache.distance, kills = cache.kills, available = cache.available }
	end
end

return LeaderboardService
