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
-- starter tank (140 fuel) is good for exactly 1000 m.
Constants.FUEL_PER_METER = 0.14
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
Constants.OVERWHELM_GRACE = 4 -- seconds without fuel before overwhelm ends run

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
Constants.STARTING_SCRAP = 5000
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

-- Boost shop. A boost lasts a number of runs; `effects` multiply together when
-- several are active. Keys: scrapMult, xpMult, fuelMult, healthMult, pickupMult.
export type ShopItem = {
	id: string,
	name: string,
	desc: string,
	price: number,
	runs: number,
	effects: { [string]: number },
}

Constants.SHOP_MAX_RUNS = 9
Constants.SHOP_ITEMS = {
	{
		id = "scrap2x", name = "Double Scrap", desc = "2x scrap from every run",
		price = 400, runs = 3, effects = { scrapMult = 2 },
	},
	{
		id = "xp2x", name = "Double XP", desc = "2x XP from every run",
		price = 300, runs = 3, effects = { xpMult = 2 },
	},
	{
		id = "bigTank", name = "Extended Tank", desc = "+40% fuel capacity",
		price = 250, runs = 3, effects = { fuelMult = 1.4 },
	},
	{
		id = "hardHull", name = "Hardened Hull", desc = "+30% vehicle health",
		price = 250, runs = 3, effects = { healthMult = 1.3 },
	},
	{
		id = "magnet", name = "Pickup Magnet", desc = "Grab pickups from twice as far",
		price = 200, runs = 3, effects = { pickupMult = 2 },
	},
} :: { ShopItem }

function Constants.ShopItem(id: string): ShopItem?
	for _, item in Constants.SHOP_ITEMS do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Trading
Constants.TRADE_TIMEOUT = 60

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
