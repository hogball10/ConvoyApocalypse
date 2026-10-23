--!strict
--[[
	Daily rewards, daily quests, achievements, prestige, cosmetics and the
	first-run tutorial flag. Everything here lives on the player's saved profile
	(see DataService); this module only decides what counts and what pays.

	Clients ask for things with the ProgressAction remote:
	  ClaimDaily | ClaimQuest <id> | ClaimAchievement <id> | Prestige
	  BuyCosmetic <id> | EquipCosmetic <slot> <id> | TutorialDone
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("ConvoyShared")
local Constants = require(Shared:WaitForChild("Constants"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local ProgressService = {}

-- Set by ConvoyRunService and GarageService (they require this module, so it
-- cannot require them back).
ProgressService.IsInRun = nil :: ((Player) -> boolean)?
ProgressService.OnCosmeticsChanged = nil :: ((Player) -> ())?

local function notify(player: Player, message: string)
	Remotes.Event("Notification"):FireClient(player, message)
end

local function rollQuests(player: Player, profile: DataService.PlayerProfile)
	local today = DataService.Today()
	if profile.quests.day == today and #profile.quests.list > 0 then
		return
	end
	local rng = Random.new(today * 7919 + player.UserId)
	local pool = table.clone(Constants.QUEST_POOL)
	local usedStats: { [string]: boolean } = {}
	local list = {}
	-- One quest per kind, so the three of the day are always different goals.
	while #list < Constants.QUESTS_PER_DAY and #pool > 0 do
		local quest = table.remove(pool, rng:NextInteger(1, #pool)) :: Constants.Quest
		if not usedStats[quest.stat] then
			usedStats[quest.stat] = true
			table.insert(list, { id = quest.id, progress = 0, claimed = false })
		end
	end
	profile.quests = { day = today, list = list }
end

-- Today's quests exist and the profile has every progress field.
function ProgressService.Ensure(player: Player)
	local profile = DataService.Get(player)
	if profile then
		rollQuests(player, profile)
	end
end

-- Where a stat stands, for achievements.
local function statValue(profile: DataService.PlayerProfile, stat: string): number
	if stat == "kills" then
		return profile.totalKills
	elseif stat == "runs" then
		return profile.totalRuns
	elseif stat == "distance" then
		return profile.highScore
	elseif stat == "level" then
		return profile.level
	elseif stat == "bosses" then
		return profile.stats.bossKills
	elseif stat == "pickups" then
		return profile.stats.pickups
	elseif stat == "prestige" then
		return profile.prestige
	end
	return 0
end

local function addQuestProgress(profile: DataService.PlayerProfile, stat: string, amount: number, asMax: boolean?)
	for _, entry in profile.quests.list do
		local quest = Constants.QuestById(entry.id)
		if quest and quest.stat == stat and not entry.claimed then
			if asMax then
				entry.progress = math.min(quest.target, math.max(entry.progress, amount))
			else
				entry.progress = math.min(quest.target, entry.progress + amount)
			end
		end
	end
end

function ProgressService.OnKill(player: Player, boss: boolean)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	rollQuests(player, profile)
	addQuestProgress(profile, "kills", 1)
	if boss then
		profile.stats.bossKills += 1
		addQuestProgress(profile, "bosses", 1)
	end
end

function ProgressService.OnPickup(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	rollQuests(player, profile)
	profile.stats.pickups += 1
	addQuestProgress(profile, "pickups", 1)
end

-- Called once a run is over and its results are on the profile.
function ProgressService.OnRunEnd(player: Player, distance: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	rollQuests(player, profile)
	addQuestProgress(profile, "runs", 1)
	addQuestProgress(profile, "distance", math.floor(distance), true)

	local ready = 0
	for _, entry in profile.quests.list do
		local quest = Constants.QuestById(entry.id)
		if quest and not entry.claimed and entry.progress >= quest.target then
			ready += 1
		end
	end
	for _, achievement in Constants.ACHIEVEMENTS do
		if not profile.achievements[achievement.id] and statValue(profile, achievement.stat) >= achievement.target then
			ready += 1
		end
	end
	if ready > 0 then
		notify(player, string.format("%d reward%s ready to claim in the QUESTS menu!", ready, if ready == 1 then "" else "s"))
	end
	DataService.Replicate(player)
end

local function pay(player: Player, scrap: number, xp: number)
	if scrap > 0 then
		DataService.AddScrap(player, scrap)
	end
	if xp > 0 then
		local _, levels = DataService.GrantXp(player, xp)
		if levels > 0 then
			notify(player, "LEVEL UP!")
		end
	end
	DataService.Replicate(player)
	DataService.Save(player)
end

local function claimDaily(player: Player, profile: DataService.PlayerProfile)
	local today = DataService.Today()
	if profile.daily.lastDay >= today then
		notify(player, "Daily reward already claimed. Come back tomorrow!")
		return
	end
	local streak = if profile.daily.lastDay == today - 1 then profile.daily.streak + 1 else 1
	local index = ((streak - 1) % #Constants.DAILY_REWARDS) + 1
	local reward = Constants.DAILY_REWARDS[index]
	profile.daily = { lastDay = today, streak = streak }
	notify(player, string.format("Day %d reward: +%d scrap, +%d XP", streak, reward.scrap, reward.xp))
	pay(player, reward.scrap, reward.xp)
end

local function claimQuest(player: Player, profile: DataService.PlayerProfile, id: string)
	for _, entry in profile.quests.list do
		if entry.id == id then
			local quest = Constants.QuestById(id)
			if not quest or entry.claimed or entry.progress < quest.target then
				return
			end
			entry.claimed = true
			notify(player, string.format("Quest done: +%d scrap, +%d XP", quest.scrap, quest.xp))
			pay(player, quest.scrap, quest.xp)
			return
		end
	end
end

local function claimAchievement(player: Player, profile: DataService.PlayerProfile, id: string)
	for _, achievement in Constants.ACHIEVEMENTS do
		if achievement.id == id then
			if profile.achievements[id] or statValue(profile, achievement.stat) < achievement.target then
				return
			end
			profile.achievements[id] = true
			notify(player, string.format("Achievement: %s  +%d scrap", achievement.text, achievement.scrap))
			pay(player, achievement.scrap, achievement.xp)
			return
		end
	end
end

local function doPrestige(player: Player, profile: DataService.PlayerProfile)
	if ProgressService.IsInRun and ProgressService.IsInRun(player) then
		notify(player, "Finish your run first")
		return
	end
	if profile.level < Constants.PRESTIGE_LEVEL then
		notify(player, string.format("Reach level %d to prestige", Constants.PRESTIGE_LEVEL))
		return
	end
	if profile.prestige >= Constants.PRESTIGE_MAX then
		notify(player, "You are already at max prestige")
		return
	end
	profile.prestige += 1
	profile.level = 1
	profile.xp = 0
	profile.scrap = Constants.STARTING_SCRAP
	notify(player, string.format("PRESTIGE %d! Permanent +%d%% scrap and XP", profile.prestige, math.round(Constants.PRESTIGE_BONUS * 100 * profile.prestige)))
	DataService.Replicate(player)
	DataService.Save(player)
end

local function equip(player: Player, profile: DataService.PlayerProfile, slot: string, id: string)
	local cosmetics = profile.cosmetics :: any
	if id ~= "" then
		local item = Constants.CosmeticById(id)
		if not item or item.slot ~= slot or not profile.cosmetics.owned[id] then
			return
		end
	elseif slot ~= "paint" and slot ~= "trail" and slot ~= "flag" then
		return
	end
	cosmetics[slot] = id
	DataService.Replicate(player)
	DataService.Save(player)
	if ProgressService.OnCosmeticsChanged then
		ProgressService.OnCosmeticsChanged(player)
	end
end

local function buyCosmetic(player: Player, profile: DataService.PlayerProfile, id: string)
	local item = Constants.CosmeticById(id)
	if not item or profile.cosmetics.owned[id] then
		return
	end
	if not DataService.TrySpendScrap(player, item.price) then
		notify(player, "Need " .. tostring(item.price) .. " scrap")
		return
	end
	profile.cosmetics.owned[id] = true
	notify(player, "Bought " .. item.name)
	equip(player, profile, item.slot, id)
end

function ProgressService.Init()
	Remotes.Event("ProgressAction").OnServerEvent:Connect(function(player, action, a, b)
		local profile = DataService.Get(player)
		if not profile or typeof(action) ~= "string" then
			return
		end
		rollQuests(player, profile)
		if action == "ClaimDaily" then
			claimDaily(player, profile)
		elseif action == "ClaimQuest" and typeof(a) == "string" then
			claimQuest(player, profile, a)
		elseif action == "ClaimAchievement" and typeof(a) == "string" then
			claimAchievement(player, profile, a)
		elseif action == "Prestige" then
			doPrestige(player, profile)
		elseif action == "BuyCosmetic" and typeof(a) == "string" then
			buyCosmetic(player, profile, a)
		elseif action == "EquipCosmetic" and typeof(a) == "string" and typeof(b) == "string" then
			equip(player, profile, a, b)
		elseif action == "TutorialDone" then
			profile.tutorialDone = true
			DataService.Save(player)
		end
	end)

	-- Give every joining player today's quests once their profile has loaded.
	local function onJoin(player: Player)
		for _ = 1, 120 do
			if DataService.Get(player) then
				ProgressService.Ensure(player)
				DataService.Replicate(player)
				return
			end
			task.wait(0.5)
			if player.Parent == nil then
				return
			end
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return ProgressService
