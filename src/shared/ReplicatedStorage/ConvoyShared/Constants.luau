--!strict
--[[
	Shared gameplay constants for Convoy Apocalypse.
]]

local Constants = {}

Constants.GAME_NAME = "ConvoyApocalypse"
Constants.DATASTORE_NAME = "ConvoyApocalypse_v1"

-- Scrap economy
Constants.SCRAP_PER_METERS = 2 -- 1 scrap per this many meters
Constants.SCRAP_PER_KILL = 12

-- Vehicle defaults (before parts)
Constants.BASE_MAX_HEALTH = 100
Constants.BASE_MAX_FUEL = 100
Constants.BASE_SPEED = 40
Constants.BASE_ACCEL = 20
Constants.BASE_HANDLING = 1
Constants.BASE_WEIGHT_CAP = 100
-- Fuel is spent per metre driven, so a tank's capacity is its range. The
-- starter tank (140 fuel) is good for exactly 500 m.
Constants.FUEL_PER_METER = 0.28
-- Sitting still still burns a little, so a stalled run cannot last forever.
Constants.IDLE_FUEL_DRAIN = 0.15
-- Fraction of the tank a fuel pickup refills.
Constants.FUEL_PICKUP_FRACTION = 0.12

-- Metres a tank of this capacity carries the car.
function Constants.FuelRange(fuel: number): number
	return fuel / Constants.FUEL_PER_METER
end

-- Run
Constants.BIOME_LENGTH = 500 -- studs per biome segment
Constants.BIOMES = { "WastelandHighways", "RuinedCity", "Desert", "SnowyMountains" }
Constants.ZOMBIE_SPAWN_INTERVAL = 1.2
Constants.ZOMBIE_BASE_HEALTH = 30
Constants.ZOMBIE_BASE_DAMAGE = 8
Constants.ZOMBIE_BASE_SPEED = 14
Constants.RAM_DAMAGE = 40
Constants.RAM_SELF_DAMAGE = 5

-- Progression
Constants.XP_PER_METERS = 10 -- 1 xp per this many meters
Constants.XP_PER_KILL = 2
Constants.XP_PER_BOSS = 100
Constants.BOSS_SCRAP = 150
Constants.LEVEL_UP_SCRAP = 100 -- per new level reached

function Constants.XpToNext(level: number): number
	return 100 + (level - 1) * 60
end

-- Garage
Constants.STARTING_SCRAP = 100
-- Scrap to buy what a lever landed on. Pulling is free.
Constants.LEVER_COSTS = {
	Body = 15,
	Drive = 30,
	Gear = 35,
	Weapons = 35,
}
-- What a lever's price is multiplied by for the tier it landed on, so a
-- Legendary costs far more than a Common from the same lever.
Constants.LEVER_TIER_MULT = {
	Scrap = 1,
	Common = 1,
	Uncommon = 2,
	Rare = 4.5,
	Epic = 10,
	Legendary = 22,
	Mythic = 48,
	Relic = 100,
}
Constants.STARTING_SLOTS = 1
Constants.MAX_SLOTS = 4
Constants.SLOT_UNLOCK_COSTS = { 0, 200, 500, 1000 }

-- Gamepasses: permanent perks bought with Robux. `effects` multiply together
-- and with the prestige bonus.
-- Create each pass on the Roblox site (Creator Hub > the experience >
-- Monetization > Passes) and paste its id into `passId`. While it is 0 the pass
-- is "coming soon" in a live server, and a free test toggle in Studio.
export type GamePass = {
	id: string,
	passId: number,
	name: string,
	desc: string,
	effects: { [string]: number },
}

Constants.GAMEPASSES = {
	{
		id = "pass_scrap", passId = 0, name = "2x Scrap",
		desc = "Double scrap from every run, forever", effects = { scrapMult = 2 },
	},
	{
		id = "pass_fuel", passId = 0, name = "2x Fuel",
		desc = "Double fuel tank capacity: twice the range", effects = { fuelMult = 2 },
	},
	{
		id = "pass_xp", passId = 0, name = "2x XP",
		desc = "Double XP from every run", effects = { xpMult = 2 },
	},
	{
		id = "pass_hull", passId = 0, name = "Iron Hide",
		desc = "+50% vehicle health", effects = { healthMult = 1.5 },
	},
	{
		id = "pass_magnet", passId = 0, name = "Super Magnet",
		desc = "Grab pickups from twice as far", effects = { pickupMult = 2 },
	},
} :: { GamePass }

function Constants.GamePass(id: string): GamePass?
	for _, pass in Constants.GAMEPASSES do
		if pass.id == id then
			return pass
		end
	end
	return nil
end

function Constants.GamePassByPassId(passId: number): GamePass?
	for _, pass in Constants.GAMEPASSES do
		if pass.passId == passId and passId > 0 then
			return pass
		end
	end
	return nil
end

-- Daily login rewards: day 1 to 7 of a streak, then it loops. Miss a day and it
-- starts over.
Constants.DAILY_REWARDS = {
	{ scrap = 100, xp = 20 },
	{ scrap = 150, xp = 30 },
	{ scrap = 250, xp = 50 },
	{ scrap = 350, xp = 70 },
	{ scrap = 500, xp = 100 },
	{ scrap = 750, xp = 150 },
	{ scrap = 2000, xp = 400 },
}

-- Daily quests: QUESTS_PER_DAY are drawn from the pool each day. `stat` is what
-- progress counts: kills, bosses, runs and pickups add up across the day,
-- distance is the best single run.
export type Quest = {
	id: string,
	stat: string,
	target: number,
	scrap: number,
	xp: number,
	text: string,
}
Constants.QUESTS_PER_DAY = 3
Constants.QUEST_POOL = {
	{ id = "kills40", stat = "kills", target = 40, scrap = 120, xp = 40, text = "Kill 40 zombies" },
	{ id = "kills120", stat = "kills", target = 120, scrap = 300, xp = 90, text = "Kill 120 zombies" },
	{ id = "kills300", stat = "kills", target = 300, scrap = 700, xp = 200, text = "Kill 300 zombies" },
	{ id = "dist400", stat = "distance", target = 400, scrap = 100, xp = 40, text = "Drive 400 m in one run" },
	{ id = "dist1200", stat = "distance", target = 1200, scrap = 320, xp = 100, text = "Drive 1,200 m in one run" },
	{ id = "dist2500", stat = "distance", target = 2500, scrap = 800, xp = 220, text = "Drive 2,500 m in one run" },
	{ id = "runs3", stat = "runs", target = 3, scrap = 150, xp = 50, text = "Finish 3 runs" },
	{ id = "runs6", stat = "runs", target = 6, scrap = 350, xp = 110, text = "Finish 6 runs" },
	{ id = "pick8", stat = "pickups", target = 8, scrap = 140, xp = 40, text = "Grab 8 pickups" },
	{ id = "pick20", stat = "pickups", target = 20, scrap = 360, xp = 100, text = "Grab 20 pickups" },
	{ id = "boss1", stat = "bosses", target = 1, scrap = 400, xp = 150, text = "Take down a Juggernaut" },
} :: { Quest }

function Constants.QuestById(id: string): Quest?
	for _, quest in Constants.QUEST_POOL do
		if quest.id == id then
			return quest
		end
	end
	return nil
end

-- Achievements: one-off goals that pay once. `stat` is read from the profile:
-- kills, runs, distance (best run), level, bosses, pickups, prestige.
Constants.ACHIEVEMENTS = {
	{ id = "kills100", stat = "kills", target = 100, scrap = 200, xp = 50, text = "Kill 100 zombies" },
	{ id = "kills1000", stat = "kills", target = 1000, scrap = 1500, xp = 400, text = "Kill 1,000 zombies" },
	{ id = "kills10000", stat = "kills", target = 10000, scrap = 12000, xp = 3000, text = "Kill 10,000 zombies" },
	{ id = "runs10", stat = "runs", target = 10, scrap = 250, xp = 60, text = "Finish 10 runs" },
	{ id = "runs50", stat = "runs", target = 50, scrap = 1200, xp = 300, text = "Finish 50 runs" },
	{ id = "runs250", stat = "runs", target = 250, scrap = 6000, xp = 1500, text = "Finish 250 runs" },
	{ id = "dist1000", stat = "distance", target = 1000, scrap = 300, xp = 80, text = "Reach 1,000 m in a run" },
	{ id = "dist5000", stat = "distance", target = 5000, scrap = 2000, xp = 500, text = "Reach 5,000 m in a run" },
	{ id = "dist20000", stat = "distance", target = 20000, scrap = 10000, xp = 2500, text = "Reach 20,000 m in a run" },
	{ id = "level10", stat = "level", target = 10, scrap = 800, xp = 0, text = "Reach level 10" },
	{ id = "level25", stat = "level", target = 25, scrap = 3000, xp = 0, text = "Reach level 25" },
	{ id = "boss10", stat = "bosses", target = 10, scrap = 1500, xp = 400, text = "Take down 10 Juggernauts" },
	{ id = "pick100", stat = "pickups", target = 100, scrap = 800, xp = 200, text = "Grab 100 pickups" },
	{ id = "prestige1", stat = "prestige", target = 1, scrap = 3000, xp = 0, text = "Prestige once" },
} :: { Quest }

-- Prestige: at this level you can reset level, XP and scrap for a permanent
-- bonus to scrap and XP. Parts, cars and cosmetics are kept.
Constants.PRESTIGE_LEVEL = 15
Constants.PRESTIGE_BONUS = 0.10 -- per prestige, added to scrap and XP gains
Constants.PRESTIGE_MAX = 20

-- Cosmetics, bought with scrap. slot: paint (tints the plain building blocks),
-- trail (a ribbon behind the car), flag (a pennant on the roof).
export type Cosmetic = {
	id: string,
	slot: string,
	name: string,
	price: number,
	color: Color3,
	rainbow: boolean?,
}
Constants.COSMETIC_SLOTS = { "paint", "trail", "flag" }
Constants.COSMETICS = {
	{ id = "paint_orange", slot = "paint", name = "Rust Orange", price = 250, color = Color3.fromRGB(226, 120, 44) },
	{ id = "paint_pink", slot = "paint", name = "Hot Pink", price = 400, color = Color3.fromRGB(255, 92, 170) },
	{ id = "paint_lime", slot = "paint", name = "Lime Zest", price = 400, color = Color3.fromRGB(150, 230, 60) },
	{ id = "paint_sky", slot = "paint", name = "Sky Blue", price = 500, color = Color3.fromRGB(80, 170, 255) },
	{ id = "paint_night", slot = "paint", name = "Midnight", price = 800, color = Color3.fromRGB(28, 30, 52) },
	{ id = "paint_gold", slot = "paint", name = "Solid Gold", price = 2500, color = Color3.fromRGB(255, 205, 60) },
	{ id = "trail_fire", slot = "trail", name = "Flame Trail", price = 600, color = Color3.fromRGB(255, 120, 30) },
	{ id = "trail_neon", slot = "trail", name = "Neon Trail", price = 900, color = Color3.fromRGB(70, 220, 255) },
	{ id = "trail_toxic", slot = "trail", name = "Toxic Trail", price = 900, color = Color3.fromRGB(120, 255, 70) },
	{ id = "trail_rainbow", slot = "trail", name = "Rainbow Trail", price = 3000, color = Color3.fromRGB(255, 255, 255), rainbow = true },
	{ id = "flag_skull", slot = "flag", name = "Black Flag", price = 300, color = Color3.fromRGB(20, 20, 24) },
	{ id = "flag_red", slot = "flag", name = "Red Pennant", price = 300, color = Color3.fromRGB(220, 50, 50) },
	{ id = "flag_pink", slot = "flag", name = "Pink Banner", price = 500, color = Color3.fromRGB(255, 120, 190) },
	{ id = "flag_gold", slot = "flag", name = "Gold Standard", price = 1500, color = Color3.fromRGB(255, 205, 60) },
} :: { Cosmetic }

function Constants.CosmeticById(id: string): Cosmetic?
	for _, item in Constants.COSMETICS do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Trading
-- Seconds a trade can sit untouched before it is cancelled.
Constants.TRADE_TIMEOUT = 120
-- Seconds the other player has to answer a trade request.
Constants.TRADE_REQUEST_TIMEOUT = 20
-- Parts one side can put on the table at once.
Constants.TRADE_MAX_PARTS = 24

-- Lever rolls. Weights are relative chances.
Constants.RARITY_ODDS = {
	{ tier = "Common", weight = 92 },
	{ tier = "Uncommon", weight = 50 },
	{ tier = "Rare", weight = 30 },
	{ tier = "Epic", weight = 16 },
	{ tier = "Legendary", weight = 8 },
	{ tier = "Mythic", weight = 3 },
	{ tier = "Relic", weight = 1 },
}

-- Tiers
Constants.TIERS = { "Scrap", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Relic" }
Constants.TIER_COLORS = {
	Scrap = Color3.fromRGB(140, 140, 140),
	Common = Color3.fromRGB(180, 200, 220),
	Uncommon = Color3.fromRGB(110, 205, 120),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	Mythic = Color3.fromRGB(255, 60, 120),
	Relic = Color3.fromRGB(110, 255, 235),
}

return Constants
