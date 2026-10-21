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
Constants.FUEL_DRAIN_PER_SECOND = 0.35
Constants.IDLE_FUEL_DRAIN = 0.08

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
Constants.STARTING_SLOTS = 1
Constants.MAX_SLOTS = 4
Constants.SLOT_UNLOCK_COSTS = { 0, 200, 500, 1000 }

-- Trading
Constants.TRADE_TIMEOUT = 60

-- Lever rolls. Weights are relative chances.
Constants.RARITY_ODDS = {
	{ tier = "Common", weight = 52 },
	{ tier = "Rare", weight = 27 },
	{ tier = "Epic", weight = 13 },
	{ tier = "Legendary", weight = 6 },
	{ tier = "Mythic", weight = 2 },
}

-- Tiers
Constants.TIERS = { "Scrap", "Common", "Rare", "Epic", "Legendary", "Mythic" }
Constants.TIER_COLORS = {
	Scrap = Color3.fromRGB(140, 140, 140),
	Common = Color3.fromRGB(180, 200, 220),
	Rare = Color3.fromRGB(70, 140, 255),
	Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	Mythic = Color3.fromRGB(255, 60, 120),
}

return Constants
