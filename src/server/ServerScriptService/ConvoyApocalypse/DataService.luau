--!strict
--[[
	Player data load/save via DataStoreService.
	Profile: scrap, unlocked parts, vehicle slots/loadouts, high score.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local PartsCatalog = require(Shared:WaitForChild("PartsCatalog"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type PlacedBlock = {
	partId: string,
	x: number,
	y: number,
	z: number,
	rot: number,
}

export type SlotData = {
	loadout: { [string]: string },
	blocks: { PlacedBlock },
}

export type PlayerProfile = {
	scrap: number,
	unlockedParts: { [string]: boolean },
	unlockedSlots: number,
	activeSlot: number,
	slots: { SlotData },
	highScore: number,
	boosts: { [string]: number }, -- shop boosts: item id -> runs left
	xp: number,
	level: number,
	totalKills: number,
	totalRuns: number,
	ownedParts: { [string]: number }, -- inventory counts for tradeable extras (prototype: 1 per unlock)
}

local DataService = {}
DataService._profiles = {} :: { [number]: PlayerProfile }
DataService._store = nil :: DataStore?
-- Gamepasses a player owns, by Constants.GAMEPASSES id. Roblox is the record of
-- what was bought, so this is never saved; GamepassService fills it on join.
DataService._passes = {} :: { [number]: { [string]: boolean } }

local function deepCopy<T>(value: T): T
	if typeof(value) ~= "table" then
		return value
	end
	local result = {}
	for k, v in value :: any do
		result[k] = deepCopy(v)
	end
	return result :: any
end

local function defaultProfile(): PlayerProfile
	local unlocked: { [string]: boolean } = {}
	local owned: { [string]: number } = {}

	-- Own at least as many of each piece as the starter car uses, or taking one
	-- off the pad would leave the player unable to put it back on.
	local used: { [string]: number } = {}
	for _, block in PartsCatalog.StarterBlocks do
		used[block.partId] = (used[block.partId] or 0) + 1
	end

	for _, id in PartsCatalog.StarterUnlocks do
		unlocked[id] = true
		owned[id] = math.max(1, used[id] or 0)
	end
	for id, count in used do
		unlocked[id] = true
		owned[id] = math.max(owned[id] or 0, count)
	end

	local starterBlocks: { PlacedBlock } = {}
	for _, block in PartsCatalog.StarterBlocks do
		table.insert(starterBlocks, {
			partId = block.partId,
			x = block.x,
			y = block.y,
			z = block.z,
			rot = block.rot,
		})
	end

	local slots: { SlotData } = {}
	for i = 1, Constants.MAX_SLOTS do
		-- Only the slot they spawn into gets the car; the rest are blank canvases.
		slots[i] = {
			loadout = PartsCatalog.DefaultLoadout(),
			blocks = if i == 1 then starterBlocks else {},
		}
	end

	return {
		scrap = Constants.STARTING_SCRAP,
		unlockedParts = unlocked,
		unlockedSlots = Constants.STARTING_SLOTS,
		activeSlot = 1,
		slots = slots,
		highScore = 0,
		boosts = {},
		xp = 0,
		level = 1,
		totalKills = 0,
		totalRuns = 0,
		ownedParts = owned,
	}
end

local function keyFor(userId: number): string
	return "player_" .. tostring(userId)
end

function DataService.Init()
	Remotes.Init()
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Constants.DATASTORE_NAME)
	end)
	if ok then
		DataService._store = store
	else
		-- Unpublished places cannot use DataStores; in-memory profiles still work for Studio playtests.
		warn("[DataService] Using in-memory profiles (publish place to enable DataStores):", store)
	end

	Players.PlayerAdded:Connect(function(player)
		DataService.Load(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		DataService.Save(player)
		DataService._profiles[player.UserId] = nil
	end)
	game:BindToClose(function()
		for _, player in Players:GetPlayers() do
			DataService.Save(player)
		end
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(DataService.Load, player)
	end

	Remotes.Function("GetPlayerData").OnServerInvoke = function(player: Player)
		return DataService.GetPublic(player)
	end
end

function DataService.Load(player: Player)
	local profile = defaultProfile()
	if DataService._store then
		local ok, data = pcall(function()
			return DataService._store:GetAsync(keyFor(player.UserId))
		end)
		if ok and typeof(data) == "table" then
			-- Merge saved fields onto defaults for forward compatibility
			for k, v in data do
				if profile[k] ~= nil then
					(profile :: any)[k] = v
				end
			end
			-- Ensure slot table length
			while #profile.slots < Constants.MAX_SLOTS do
				table.insert(profile.slots, { loadout = PartsCatalog.DefaultLoadout(), blocks = {} })
			end
			for _, slot in profile.slots do
				if typeof(slot.blocks) ~= "table" then
					slot.blocks = {}
				end
				if typeof(slot.loadout) ~= "table" then
					slot.loadout = PartsCatalog.DefaultLoadout()
				end
			end
		elseif not ok then
			warn("[DataService] Load failed for", player.Name, data)
		end
	end

	DataService._profiles[player.UserId] = profile
	Remotes.Event("DataUpdated"):FireClient(player, DataService.GetPublic(player))
end

function DataService.Save(player: Player)
	local profile = DataService._profiles[player.UserId]
	if not profile or not DataService._store then
		return
	end
	local ok, err = pcall(function()
		DataService._store:SetAsync(keyFor(player.UserId), profile)
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
	end
end

function DataService.Get(player: Player): PlayerProfile?
	return DataService._profiles[player.UserId]
end

function DataService.GetPublic(player: Player): any
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return nil
	end
	local copy: any = deepCopy(profile)
	copy.passes = deepCopy(DataService._passes[player.UserId] or {})
	return copy
end

function DataService.SetPass(player: Player, passKey: string, owned: boolean)
	local passes = DataService._passes[player.UserId]
	if not passes then
		passes = {}
		DataService._passes[player.UserId] = passes
	end
	passes[passKey] = if owned then true else nil
	DataService.Replicate(player)
end

function DataService.HasPass(player: Player, passKey: string): boolean
	local passes = DataService._passes[player.UserId]
	return passes ~= nil and passes[passKey] == true
end

function DataService.ClearPasses(player: Player)
	DataService._passes[player.UserId] = nil
end

function DataService.Replicate(player: Player)
	local public = DataService.GetPublic(player)
	if public then
		Remotes.Event("DataUpdated"):FireClient(player, public)
	end
end

function DataService.AddScrap(player: Player, amount: number)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return
	end
	profile.scrap = math.max(0, profile.scrap + math.floor(amount))
	DataService.Replicate(player)
end

function DataService.TrySpendScrap(player: Player, amount: number): boolean
	local profile = DataService._profiles[player.UserId]
	if not profile or profile.scrap < amount then
		return false
	end
	profile.scrap -= amount
	DataService.Replicate(player)
	return true
end

function DataService.UnlockPart(player: Player, partId: string): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	local part = PartsCatalog.Get(partId)
	if not profile or not part then
		return false, "Invalid part"
	end
	if profile.unlockedParts[partId] then
		return false, "Already unlocked"
	end
	if not DataService.TrySpendScrap(player, part.unlockCost) then
		return false, "Not enough scrap"
	end
	profile.unlockedParts[partId] = true
	profile.ownedParts[partId] = (profile.ownedParts[partId] or 0) + 1
	DataService.Replicate(player)
	DataService.Save(player)
	return true, nil
end

function DataService.EquipPart(player: Player, category: string, partId: string): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return false, "No profile"
	end
	if partId ~= "" then
		local part = PartsCatalog.Get(partId)
		if not part then
			return false, "Unknown part"
		end
		if part.category ~= category then
			return false, "Wrong category"
		end
		if not profile.unlockedParts[partId] then
			return false, "Not unlocked"
		end
		-- Must own at least one unequipped OR it's the currently equipped one
		local owned = profile.ownedParts[partId] or 0
		if owned < 1 and profile.slots[profile.activeSlot].loadout[category] ~= partId then
			return false, "Not owned"
		end
	end

	local slot = profile.slots[profile.activeSlot]
	slot.loadout[category] = partId
	DataService.Replicate(player)
	return true, nil
end

function DataService.SelectSlot(player: Player, slotIndex: number): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return false, "No profile"
	end
	if slotIndex < 1 or slotIndex > profile.unlockedSlots then
		return false, "Slot locked"
	end
	profile.activeSlot = slotIndex
	DataService.Replicate(player)
	return true, nil
end

function DataService.GetActiveLoadout(player: Player): { [string]: string }?
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return nil
	end
	return profile.slots[profile.activeSlot].loadout
end

function DataService.UpdateHighScore(player: Player, distance: number)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return
	end
	if distance > profile.highScore then
		profile.highScore = math.floor(distance)
		DataService.Replicate(player)
	end
end

-- Adds XP, rolling over levels. Each new level pays a scrap bonus.
function DataService.AddRunProgress(player: Player, xp: number, kills: number): (number, number)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return 1, 0
	end
	profile.totalRuns += 1
	profile.totalKills += kills
	profile.xp += math.floor(xp)
	local levelsGained = 0
	while profile.xp >= Constants.XpToNext(profile.level) do
		profile.xp -= Constants.XpToNext(profile.level)
		profile.level += 1
		levelsGained += 1
		profile.scrap += Constants.LEVEL_UP_SCRAP * profile.level
	end
	DataService.Replicate(player)
	return profile.level, levelsGained
end

-- Shop boosts last a number of runs. The effects of every active boost with
-- the given key multiply together.
function DataService.BuyBoost(player: Player, itemId: string): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	local item = Constants.ShopItem(itemId)
	if not profile or not item then
		return false, "Unknown item"
	end
	local current = profile.boosts[itemId] or 0
	if current >= Constants.SHOP_MAX_RUNS then
		return false, "Already stocked up"
	end
	if not DataService.TrySpendScrap(player, item.price) then
		return false, "Need " .. tostring(item.price) .. " scrap"
	end
	profile.boosts[itemId] = math.min(Constants.SHOP_MAX_RUNS, current + item.runs)
	DataService.Replicate(player)
	DataService.Save(player)
	return true, nil
end

function DataService.BoostEffect(player: Player, key: string): number
	local profile = DataService._profiles[player.UserId]
	local total = 1
	if not profile then
		return total
	end
	for id, left in profile.boosts do
		local item = Constants.ShopItem(id)
		if item and left > 0 and item.effects[key] then
			total *= item.effects[key]
		end
	end
	for passKey in DataService._passes[player.UserId] or {} do
		local pass = Constants.GamePass(passKey)
		if pass and pass.effects[key] then
			total *= pass.effects[key]
		end
	end
	return total
end

function DataService.ActiveBoostNames(player: Player): { string }
	local profile = DataService._profiles[player.UserId]
	local names = {}
	if profile then
		for id, left in profile.boosts do
			local item = Constants.ShopItem(id)
			if item and left > 0 then
				table.insert(names, item.name)
			end
		end
	end
	for passKey in DataService._passes[player.UserId] or {} do
		local pass = Constants.GamePass(passKey)
		if pass then
			table.insert(names, pass.name)
		end
	end
	table.sort(names)
	return names
end

-- One run used up on every active boost.
function DataService.ConsumeBoosts(player: Player)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return
	end
	for id, left in table.clone(profile.boosts) do
		profile.boosts[id] = if left > 1 then left - 1 else nil
	end
	DataService.Replicate(player)
end

-- Trading helpers: only unequipped owned parts
function DataService.GetUnequippedCount(player: Player, partId: string): number
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return 0
	end
	local owned = profile.ownedParts[partId] or 0
	local equipped = 0
	local loadout = profile.slots[profile.activeSlot].loadout
	for _, id in loadout do
		if id == partId then
			equipped += 1
		end
	end
	return math.max(0, owned - equipped)
end

function DataService.RemoveOwnedPart(player: Player, partId: string): boolean
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return false
	end
	if DataService.GetUnequippedCount(player, partId) < 1 then
		return false
	end
	profile.ownedParts[partId] = (profile.ownedParts[partId] or 0) - 1
	if profile.ownedParts[partId] <= 0 then
		profile.ownedParts[partId] = nil
		-- Keep unlock so they can re-buy; design says permanent unlocks
	end
	return true
end

function DataService.GrantPart(player: Player, partId: string): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	local part = PartsCatalog.Get(partId)
	if not profile or not part then
		return false, nil
	end
	profile.unlockedParts[partId] = true
	profile.ownedParts[partId] = (profile.ownedParts[partId] or 0) + 1
	local slot = profile.slots[profile.activeSlot]
	if typeof(slot.blocks) ~= "table" then
		slot.blocks = {}
	end
	DataService.Replicate(player)
	return true, "stored"
end

function DataService.GetActiveBlocks(player: Player): { PlacedBlock }?
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return nil
	end
	local slot = profile.slots[profile.activeSlot]
	if typeof(slot.blocks) ~= "table" then
		slot.blocks = {}
	end
	return slot.blocks
end

local function placedCount(blocks: { PlacedBlock }, partId: string): number
	local count = 0
	for _, block in blocks do
		if block.partId == partId then
			count += 1
		end
	end
	return count
end

function DataService.PlaceBlock(player: Player, partId: string, x: number, y: number, z: number, rot: number): (boolean, string?)
	local profile = DataService._profiles[player.UserId]
	local part = PartsCatalog.Get(partId)
	local blocks = DataService.GetActiveBlocks(player)
	if not profile or not part or not blocks then
		return false, "No profile"
	end
	if rot ~= 0 and rot ~= 90 and rot ~= 180 and rot ~= 270 then
		return false, "Bad rotation"
	end
	if (profile.ownedParts[partId] or 0) <= placedCount(blocks, partId) then
		return false, "None left in the bin"
	end
	local block: PlacedBlock = {
		partId = partId,
		x = math.round(x),
		y = math.round(y),
		z = math.round(z),
		rot = rot,
	}
	if not PartsCatalog.BlockInBounds(block) then
		return false, "Off the pad"
	end
	for _, other in blocks do
		if PartsCatalog.BlocksOverlap(block, other) then
			return false, "That spot is taken"
		end
	end
	if not PartsCatalog.BlockSupported(block, blocks) then
		return false, "It needs a block under it"
	end
	table.insert(blocks, block)
	DataService.Replicate(player)
	return true, nil
end

function DataService.RemoveBlock(player: Player, index: number): (boolean, string?)
	local blocks = DataService.GetActiveBlocks(player)
	if not blocks or index < 1 or index > #blocks then
		return false, "No block there"
	end
	table.remove(blocks, index)
	DataService.Replicate(player)
	return true, nil
end

function DataService.AddOwnedPart(player: Player, partId: string)
	local profile = DataService._profiles[player.UserId]
	if not profile then
		return
	end
	profile.unlockedParts[partId] = true
	profile.ownedParts[partId] = (profile.ownedParts[partId] or 0) + 1
end

return DataService
