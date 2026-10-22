--!strict
--[[
	All vehicle parts: stats, unlock costs, categories, tiers.
	Permanent unlocks — once unlocked, equip anytime.
]]

-- One gun on the car: what it fires and where it is bolted on (block centre,
-- in the car's own space).
export type WeaponMount = {
	partId: string,
	kind: string,
	damage: number,
	fireRate: number,
	x: number,
	y: number,
	z: number,
}

export type PartDef = {
	id: string,
	name: string,
	category: string,
	tier: string,
	weight: number,
	unlockCost: number,
	stats: { [string]: number },
	description: string,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("ConvoyShared"):WaitForChild("Constants"))

local PartsCatalog = {}

PartsCatalog.Categories = {
	"Block",
	"Engine",
	"Wheels",
	"FuelTank",
	"Seat",
	"Weapon",
	"Armor",
	"Utility",
	"Chassis",
}

-- The frame is free, plus the handful of pieces the starter car is built from.
-- The lever is for upgrades, not for getting off the pad the first time.
PartsCatalog.StarterUnlocks = {
	"chassis_scrap",
	"plate_common",
	"engine_common",
	"wheels_common",
	"fuel_common",
	"seat_common",
}

--[[
	The car a new player finds already sitting on their pad.

	Laid out against the rules in BlockInBounds / BlocksOverlap /
	BlockSupported: y is the *bottom* of a block, the plate is the floor
	everything else rests on, and the wheels sit on the ground just clear of
	the plate's footprint. Covers every category in RequiredToRun, so START RUN
	works the moment someone joins.
]]
PartsCatalog.StarterBlocks = {
	{ partId = "plate_common", x = 0, y = 0, z = 0, rot = 0 },
	{ partId = "engine_common", x = 0, y = 1, z = -2, rot = 0 },
	{ partId = "seat_common", x = 0, y = 1, z = 1, rot = 0 },
	{ partId = "fuel_common", x = 2, y = 1, z = 2, rot = 0 },
	{ partId = "wheels_common", x = -4, y = 0, z = -2, rot = 0 },
	{ partId = "wheels_common", x = 4, y = 0, z = -2, rot = 0 },
	{ partId = "wheels_common", x = -4, y = 0, z = 2, rot = 0 },
	{ partId = "wheels_common", x = 4, y = 0, z = 2, rot = 0 },
}

-- Guns that fire at once. Extra weapons past this still weigh the car down.
PartsCatalog.MAX_MOUNTED_WEAPONS = 12

PartsCatalog.RequiredToRun = { "Engine", "Wheels", "FuelTank", "Seat" }

PartsCatalog.SocketLabel = {
	Block = "Brick",
	Engine = "Engine",
	Wheels = "Wheels",
	FuelTank = "Fuel Can",
	Seat = "Driver Seat",
	Weapon = "Weapon",
	Armor = "Armor",
	Utility = "Utility",
	Chassis = "Frame",
}

export type LeverTarget = {
	id: string,
	label: string,
	short: string,
	category: string,
	prefix: string,
}

-- One lever per group. A pull only rolls parts from the target selected on
-- that lever, so each category can be farmed on its own.
PartsCatalog.LeverKinds = {
	{ kind = "Body", title = "BODY", color = Color3.fromRGB(255, 150, 50) },
	{ kind = "Drive", title = "DRIVETRAIN", color = Color3.fromRGB(80, 170, 255) },
	{ kind = "Gear", title = "ARMOR & GEAR", color = Color3.fromRGB(110, 220, 130) },
	{ kind = "Weapons", title = "WEAPONS", color = Color3.fromRGB(255, 70, 70) },
}

PartsCatalog.BodyTargets = {
	{ id = "brick", label = "Brick", short = "BRICK", category = "Block", prefix = "brick" },
	{ id = "long", label = "Long Brick", short = "LONG", category = "Block", prefix = "long" },
	{ id = "plate", label = "Plate", short = "PLATE", category = "Block", prefix = "plate" },
	{ id = "slab", label = "Slab", short = "SLAB", category = "Block", prefix = "slab" },
	{ id = "wedge", label = "Slope", short = "SLOPE", category = "Block", prefix = "wedge" },
	{ id = "pillar", label = "Pillar", short = "PILLAR", category = "Block", prefix = "pillar" },
} :: { LeverTarget }

PartsCatalog.DriveTargets = {
	{ id = "engine", label = "Engine", short = "ENGINE", category = "Engine", prefix = "engine" },
	{ id = "turbo", label = "Turbo Engine", short = "TURBO", category = "Engine", prefix = "engine_turbo" },
	{ id = "diesel", label = "Diesel Engine", short = "DIESEL", category = "Engine", prefix = "engine_diesel" },
	{ id = "rotary", label = "Rotary Engine", short = "ROTARY", category = "Engine", prefix = "engine_rotary" },
	{ id = "wheels", label = "Wheels", short = "WHEELS", category = "Wheels", prefix = "wheels" },
	{ id = "mud", label = "Mud Tires", short = "MUD", category = "Wheels", prefix = "wheels_mud" },
	{ id = "racing", label = "Racing Slicks", short = "SLICKS", category = "Wheels", prefix = "wheels_race" },
	{ id = "fuel", label = "Fuel Can", short = "FUEL", category = "FuelTank", prefix = "fuel" },
	{ id = "barrel", label = "Fuel Barrel", short = "BARREL", category = "FuelTank", prefix = "fuel_barrel" },
	{ id = "cell", label = "Light Cell", short = "CELL", category = "FuelTank", prefix = "fuel_cell" },
	{ id = "seat", label = "Driver Seat", short = "SEAT", category = "Seat", prefix = "seat" },
} :: { LeverTarget }

PartsCatalog.GearTargets = {
	{ id = "chassis", label = "Frame", short = "FRAME", category = "Chassis", prefix = "chassis" },
	{ id = "armor", label = "Armor", short = "ARMOR", category = "Armor", prefix = "armor" },
	{ id = "spiked", label = "Spiked Armor", short = "SPIKED", category = "Armor", prefix = "armor_spiked" },
	{ id = "heavy", label = "Heavy Armor", short = "HEAVY", category = "Armor", prefix = "armor_heavy" },
	{ id = "repair", label = "Repair Kit", short = "REPAIR", category = "Utility", prefix = "utility_repair" },
	{ id = "boost", label = "Nitro", short = "NITRO", category = "Utility", prefix = "utility_boost" },
	{ id = "magnet", label = "Scrap Magnet", short = "MAGNET", category = "Utility", prefix = "utility_magnet" },
	{ id = "salvage", label = "Salvage Rig", short = "SALVAGE", category = "Utility", prefix = "utility_salvage" },
	{ id = "shield", label = "Shield Generator", short = "SHIELD", category = "Utility", prefix = "utility_shield" },
	{ id = "siphon", label = "Fuel Siphon", short = "SIPHON", category = "Utility", prefix = "utility_siphon" },
} :: { LeverTarget }

PartsCatalog.WeaponTargets = {
	{ id = "minigun", label = "Minigun", short = "GUN", category = "Weapon", prefix = "weapon_minigun" },
	{ id = "tesla", label = "Tesla", short = "TESLA", category = "Weapon", prefix = "weapon_tesla" },
	{ id = "flame", label = "Flamethrower", short = "FLAME", category = "Weapon", prefix = "weapon_flame" },
	{ id = "rail", label = "Rail Cannon", short = "RAIL", category = "Weapon", prefix = "weapon_rail" },
	{ id = "ram", label = "Ram", short = "RAM", category = "Weapon", prefix = "weapon_ram" },
	{ id = "shotgun", label = "Shotgun", short = "SHOT", category = "Weapon", prefix = "weapon_shotgun" },
	{ id = "rocket", label = "Rocket Pod", short = "ROCKET", category = "Weapon", prefix = "weapon_rocket" },
	{ id = "mine", label = "Mine Layer", short = "MINE", category = "Weapon", prefix = "weapon_mine" },
} :: { LeverTarget }

local Parts: { [string]: PartDef } = {
	-- Chassis
	chassis_scrap = {
		id = "chassis_scrap",
		name = "Scrap Frame",
		category = "Chassis",
		tier = "Scrap",
		weight = 20,
		unlockCost = 0,
		stats = { health = 100, weightCap = 80, hardpoints = 1 },
		description = "Rusty welded frame. Barely holds together.",
	},
	chassis_common = {
		id = "chassis_common",
		name = "Steel Chassis",
		category = "Chassis",
		tier = "Common",
		weight = 25,
		unlockCost = 40,
		stats = { health = 140, weightCap = 110, hardpoints = 2 },
		description = "Bolted steel rails. Reliable starter upgrade.",
	},
	chassis_rare = {
		id = "chassis_rare",
		name = "Reinforced Rig",
		category = "Chassis",
		tier = "Rare",
		weight = 30,
		unlockCost = 120,
		stats = { health = 200, weightCap = 150, hardpoints = 3 },
		description = "Cross-braced truck frame with extra mounts.",
	},
	chassis_epic = {
		id = "chassis_epic",
		name = "War Rig",
		category = "Chassis",
		tier = "Epic",
		weight = 40,
		unlockCost = 300,
		stats = { health = 280, weightCap = 200, hardpoints = 4 },
		description = "Convoy-grade armored platform.",
	},
	chassis_legendary = {
		id = "chassis_legendary",
		name = "Apocalypse Hull",
		category = "Chassis",
		tier = "Legendary",
		weight = 50,
		unlockCost = 700,
		stats = { health = 400, weightCap = 280, hardpoints = 5 },
		description = "Military surplus beast. Survives anything.",
	},

	-- Engines
	engine_scrap = {
		id = "engine_scrap",
		name = "Lawnmower Motor",
		category = "Engine",
		tier = "Scrap",
		weight = 10,
		unlockCost = 0,
		stats = { speed = 35, accel = 15 },
		description = "Sputters, but it moves.",
	},
	engine_common = {
		id = "engine_common",
		name = "Inline Four",
		category = "Engine",
		tier = "Common",
		weight = 14,
		unlockCost = 35,
		stats = { speed = 50, accel = 22 },
		description = "Salvaged sedan engine.",
	},
	engine_rare = {
		id = "engine_rare",
		name = "V6 Turbo",
		category = "Engine",
		tier = "Rare",
		weight = 18,
		unlockCost = 100,
		stats = { speed = 70, accel = 32 },
		description = "Forced induction for the wasteland.",
	},
	engine_epic = {
		id = "engine_epic",
		name = "Diesel Hauler",
		category = "Engine",
		tier = "Epic",
		weight = 24,
		unlockCost = 250,
		stats = { speed = 85, accel = 28 },
		description = "Torque monster. Pulls through anything.",
	},
	engine_legendary = {
		id = "engine_legendary",
		name = "Jet Core",
		category = "Engine",
		tier = "Legendary",
		weight = 30,
		unlockCost = 600,
		stats = { speed = 110, accel = 45 },
		description = "Experimental thruster. Pure speed.",
	},

	-- Wheels
	wheels_scrap = {
		id = "wheels_scrap",
		name = "Bald Tires",
		category = "Wheels",
		tier = "Scrap",
		weight = 8,
		unlockCost = 0,
		stats = { handling = 0.8, offroad = 0.5 },
		description = "Smooth as ice. Pray for pavement.",
	},
	wheels_common = {
		id = "wheels_common",
		name = "All-Season",
		category = "Wheels",
		tier = "Common",
		weight = 10,
		unlockCost = 30,
		stats = { handling = 1.1, offroad = 0.9 },
		description = "Decent grip on most terrain.",
	},
	wheels_rare = {
		id = "wheels_rare",
		name = "Off-Road Knobbies",
		category = "Wheels",
		tier = "Rare",
		weight = 12,
		unlockCost = 90,
		stats = { handling = 1.2, offroad = 1.4 },
		description = "Eats dirt, sand, and rubble.",
	},
	wheels_epic = {
		id = "wheels_epic",
		name = "Combat Tracks",
		category = "Wheels",
		tier = "Epic",
		weight = 20,
		unlockCost = 220,
		stats = { handling = 1.0, offroad = 1.8 },
		description = "Tracked drive. Unstoppable off-road.",
	},
	wheels_legendary = {
		id = "wheels_legendary",
		name = "Mag-Grip",
		category = "Wheels",
		tier = "Legendary",
		weight = 14,
		unlockCost = 500,
		stats = { handling = 1.6, offroad = 1.6 },
		description = "Experimental magnetic traction.",
	},

	-- Fuel tanks
	fuel_scrap = {
		id = "fuel_scrap",
		name = "Jerry Can",
		category = "FuelTank",
		tier = "Scrap",
		weight = 5,
		unlockCost = 0,
		stats = { fuel = 80 },
		description = "Small can strapped to the bed.",
	},
	fuel_common = {
		id = "fuel_common",
		name = "Drum Tank",
		category = "FuelTank",
		tier = "Common",
		weight = 10,
		unlockCost = 30,
		stats = { fuel = 140 },
		description = "55-gallon drum. Smells like hope.",
	},
	fuel_rare = {
		id = "fuel_rare",
		name = "Dual Cell",
		category = "FuelTank",
		tier = "Rare",
		weight = 16,
		unlockCost = 90,
		stats = { fuel = 220 },
		description = "Twin sealed cells under the bed.",
	},
	fuel_epic = {
		id = "fuel_epic",
		name = "Long-Haul Reservoir",
		category = "FuelTank",
		tier = "Epic",
		weight = 24,
		unlockCost = 220,
		stats = { fuel = 320 },
		description = "Convoy tanker capacity.",
	},
	fuel_legendary = {
		id = "fuel_legendary",
		name = "Fusion Cell",
		category = "FuelTank",
		tier = "Legendary",
		weight = 18,
		unlockCost = 550,
		stats = { fuel = 500 },
		description = "Near-endless range. Hot to the touch.",
	},

	-- Armor
	armor_scrap = {
		id = "armor_scrap",
		name = "Sheet Metal",
		category = "Armor",
		tier = "Scrap",
		weight = 12,
		unlockCost = 0,
		stats = { damageReduction = 0.05 },
		description = "Thin plating. Better than nothing.",
	},
	armor_common = {
		id = "armor_common",
		name = "Plate Panels",
		category = "Armor",
		tier = "Common",
		weight = 18,
		unlockCost = 40,
		stats = { damageReduction = 0.12 },
		description = "Welded steel plates on doors.",
	},
	armor_rare = {
		id = "armor_rare",
		name = "Slat Cage",
		category = "Armor",
		tier = "Rare",
		weight = 22,
		unlockCost = 110,
		stats = { damageReduction = 0.22 },
		description = "Cage armor deflects zombie piles.",
	},
	armor_epic = {
		id = "armor_epic",
		name = "Composite Shell",
		category = "Armor",
		tier = "Epic",
		weight = 30,
		unlockCost = 280,
		stats = { damageReduction = 0.35 },
		description = "Layered ceramic-steel hybrid.",
	},
	armor_legendary = {
		id = "armor_legendary",
		name = "Reactive Plating",
		category = "Armor",
		tier = "Legendary",
		weight = 35,
		unlockCost = 650,
		stats = { damageReduction = 0.5 },
		description = "Explodes outward to shed attackers.",
	},

	-- Weapons
	weapon_ram_scrap = {
		id = "weapon_ram_scrap",
		name = "Scrap Ram",
		category = "Weapon",
		tier = "Scrap",
		weight = 8,
		unlockCost = 0,
		stats = { ramDamage = 40, gunDamage = 0, fireRate = 0 },
		description = "Pointy junk welded to the bumper.",
	},
	weapon_gun_common = {
		id = "weapon_gun_common",
		name = "Hood Mount MG",
		category = "Weapon",
		tier = "Common",
		weight = 10,
		unlockCost = 50,
		stats = { ramDamage = 20, gunDamage = 12, fireRate = 4 },
		description = "Forward-firing machine gun.",
	},
	weapon_turret_rare = {
		id = "weapon_turret_rare",
		name = "Roof Turret",
		category = "Weapon",
		tier = "Rare",
		weight = 14,
		unlockCost = 140,
		stats = { ramDamage = 25, gunDamage = 18, fireRate = 5 },
		description = "360° light turret.",
	},
	weapon_flame_epic = {
		id = "weapon_flame_epic",
		name = "Flamethrower",
		category = "Weapon",
		tier = "Epic",
		weight = 16,
		unlockCost = 320,
		stats = { ramDamage = 15, gunDamage = 30, fireRate = 8 },
		description = "Short-range inferno. Clears packs.",
	},
	weapon_rail_legendary = {
		id = "weapon_rail_legendary",
		name = "Rail Cannon",
		category = "Weapon",
		tier = "Legendary",
		weight = 22,
		unlockCost = 750,
		stats = { ramDamage = 50, gunDamage = 60, fireRate = 1.5 },
		description = "Slow, devastating kinetic lance.",
	},

	-- Utility
	utility_combo_epic = {
		id = "utility_combo_epic",
		name = "Field Workshop",
		category = "Utility",
		tier = "Epic",
		weight = 10,
		unlockCost = 300,
		stats = { repairPerSec = 4, boostMult = 1.25 },
		description = "Repair + mild boost combined.",
	},
}

local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic", "Relic" }
local TIER_MULT = { Common = 1, Uncommon = 1.2, Rare = 1.45, Epic = 2.05, Legendary = 2.8, Mythic = 3.7, Relic = 4.8 }
local TIER_INDEX = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Relic = 7 }

local function scaled(base: number, tier: string): number
	return math.floor(base * TIER_MULT[tier] + 0.5)
end

local function addPart(def: PartDef)
	Parts[def.id] = def
end

-- The hand-written families (chassis, engine, wheels, fuel, armor) run
-- Common..Legendary. The tiers around them are derived instead of typed out:
-- Uncommon sits halfway between Common and Rare, Mythic is a boosted
-- Legendary and Relic a boosted Mythic.
local EXTRA_NAMES = {
	Uncommon = {
		chassis = "Welded Frame",
		engine = "Tuned Four",
		wheels = "Grip Tires",
		fuel = "Twin Drum",
		armor = "Bolted Panels",
	},
	Mythic = {
		chassis = "Doomsday Hull",
		engine = "Quantum Drive",
		wheels = "Hover Rings",
		fuel = "Singularity Cell",
		armor = "Void Plating",
	},
	Relic = {
		chassis = "Ancient Colossus",
		engine = "Reactor Core",
		wheels = "Gravity Rollers",
		fuel = "Star Core",
		armor = "Aegis Plate",
	},
}

local function boosted(from: PartDef, family: string, tier: string, factor: number)
	local stats: { [string]: number } = {}
	for key, value in from.stats do
		-- Hardpoints are a count, not a magnitude.
		stats[key] = if key == "hardpoints" then value + 1 else value * factor
	end
	addPart({
		id = family .. "_" .. string.lower(tier),
		name = EXTRA_NAMES[tier][family],
		category = from.category,
		tier = tier,
		weight = math.floor(from.weight * 1.1),
		unlockCost = from.unlockCost * 2,
		stats = stats,
		description = from.description,
	})
end

for family in EXTRA_NAMES.Mythic do
	local legendary = Parts[family .. "_legendary"]
	if legendary then
		boosted(legendary, family, "Mythic", 1.3)
		boosted(Parts[family .. "_mythic"], family, "Relic", 1.25)
	end
	local common, rare = Parts[family .. "_common"], Parts[family .. "_rare"]
	if common and rare then
		local stats: { [string]: number } = {}
		for key, value in common.stats do
			stats[key] = (value + (rare.stats[key] or value)) / 2
		end
		addPart({
			id = family .. "_uncommon",
			name = EXTRA_NAMES.Uncommon[family],
			category = common.category,
			tier = "Uncommon",
			weight = math.floor((common.weight + rare.weight) / 2),
			unlockCost = math.floor((common.unlockCost + rare.unlockCost) / 2),
			stats = stats,
			description = common.description,
		})
	end
end

-- Variants trade one stat for another so a category has real choices in it.
-- Each entry scales the matching base part (engine_<tier> etc.) tier by tier.
local variantFamilies: {
	{
		base: string,
		prefix: string,
		label: string,
		weight: number,
		scale: { [string]: number },
		extra: ((string) -> { [string]: number })?,
		desc: string,
	}
} = {
	{
		base = "engine", prefix = "engine_turbo", label = "Turbo", weight = 1,
		scale = { speed = 1.15, accel = 0.8 },
		desc = "Top speed over punch.",
	},
	{
		base = "engine", prefix = "engine_diesel", label = "Diesel", weight = 1.3,
		scale = { speed = 0.85, accel = 1.3 },
		desc = "Heavy torque, lower top end.",
	},
	{
		base = "engine", prefix = "engine_rotary", label = "Rotary", weight = 0.8,
		scale = { speed = 1.05, accel = 1.2 },
		desc = "Light, revvy and thirsty for punch.",
	},
	{
		base = "wheels", prefix = "wheels_mud", label = "Mud", weight = 1.2,
		scale = { offroad = 1.4, handling = 0.85 },
		desc = "Digs through anything, wanders on tarmac.",
	},
	{
		base = "wheels", prefix = "wheels_race", label = "Slick", weight = 0.9,
		scale = { handling = 1.3, offroad = 0.7 },
		desc = "Razor handling on the road only.",
	},
	{
		base = "fuel", prefix = "fuel_barrel", label = "Barrel", weight = 1.4,
		scale = { fuel = 1.3 },
		desc = "More range, more mass.",
	},
	{
		base = "fuel", prefix = "fuel_cell", label = "Light", weight = 0.55,
		scale = { fuel = 0.85 },
		desc = "A little less fuel for almost no weight.",
	},
	{
		base = "armor", prefix = "armor_spiked", label = "Spiked", weight = 1,
		scale = { damageReduction = 0.8 },
		extra = function(tier: string): { [string]: number }
			return { ramDamage = 5 * TIER_INDEX[tier] }
		end,
		desc = "Less protection, but the spikes hurt to ram.",
	},
	{
		base = "armor", prefix = "armor_heavy", label = "Heavy", weight = 1.4,
		scale = { damageReduction = 1.25 },
		desc = "Thick plating. Slows you down.",
	},
}

for _, family in variantFamilies do
	for _, tier in TIER_NAMES do
		local base = Parts[family.base .. "_" .. string.lower(tier)]
		if base then
			local stats: { [string]: number } = {}
			for key, value in base.stats do
				stats[key] = value * (family.scale[key] or 1)
			end
			local extra = family.extra
			if extra then
				for key, value in extra(tier) do
					stats[key] = (stats[key] or 0) + value
				end
			end
			addPart({
				id = family.prefix .. "_" .. string.lower(tier),
				name = family.label .. " " .. base.name,
				category = base.category,
				tier = tier,
				weight = math.floor(base.weight * family.weight + 0.5),
				unlockCost = 0,
				stats = stats,
				description = family.desc,
			})
		end
	end
end

local utilityFamilies = {
	{
		prefix = "utility_repair", name = "Patch Kit", weight = 4,
		desc = "Slow auto-repair while driving.",
		stats = function(tier: string): { [string]: number }
			return { repairPerSec = scaled(2, tier) }
		end,
	},
	{
		prefix = "utility_boost", name = "Nitro Canister", weight = 6,
		desc = "A speed burst on demand.",
		stats = function(tier: string): { [string]: number }
			return { boostMult = 1 + 0.2 * TIER_INDEX[tier] }
		end,
	},
	{
		prefix = "utility_magnet", name = "Scrap Magnet", weight = 8,
		desc = "Pulls pickups in from further away.",
		stats = function(tier: string): { [string]: number }
			return { pickupMult = 1.4 + 0.4 * TIER_INDEX[tier] }
		end,
	},
	{
		prefix = "utility_shield", name = "Shield Generator", weight = 10,
		desc = "A rechargeable shield that soaks damage before the hull does.",
		stats = function(tier: string): { [string]: number }
			return { shieldMax = scaled(25, tier), shieldRegen = 2 + TIER_INDEX[tier] }
		end,
	},
	{
		prefix = "utility_siphon", name = "Fuel Siphon", weight = 9,
		desc = "Every kill drains a little fuel back into the tank.",
		stats = function(tier: string): { [string]: number }
			return { fuelPerKill = 1 + 0.8 * TIER_INDEX[tier] }
		end,
	},
	{
		prefix = "utility_salvage", name = "Salvage Rig", weight = 12,
		desc = "Strips every kill and mile for extra scrap.",
		stats = function(tier: string): { [string]: number }
			return { scrapMult = 1 + 0.15 * TIER_INDEX[tier] }
		end,
	},
}

for _, family in utilityFamilies do
	for _, tier in TIER_NAMES do
		addPart({
			id = family.prefix .. "_" .. string.lower(tier),
			name = tier .. " " .. family.name,
			category = "Utility",
			tier = tier,
			weight = family.weight,
			unlockCost = 0,
			stats = family.stats(tier),
			description = family.desc,
		})
	end
end

local bodyPieces = {
	{ prefix = "brick", name = "Brick", category = "Block", weight = 4, health = 16, cap = 0, desc = "A 2x1 building brick." },
	{ prefix = "long", name = "Long Brick", category = "Block", weight = 6, health = 26, cap = 0, desc = "A long building brick." },
	{ prefix = "plate", name = "Plate", category = "Block", weight = 3, health = 10, cap = 0, desc = "A flat plate." },
	{ prefix = "slab", name = "Slab", category = "Block", weight = 7, health = 30, cap = 0, desc = "A broad, sturdy deck panel." },
	{ prefix = "pillar", name = "Pillar", category = "Block", weight = 6, health = 22, cap = 0, desc = "A tall post for cabs and roll cages." },
	{ prefix = "wedge", name = "Slope", category = "Block", weight = 4, health = 14, cap = 0, desc = "A sloped brick." },
	{ prefix = "seat", name = "Seat", category = "Seat", weight = 3, health = 4, cap = 0, desc = "Driver seat. Place it wherever you sit." },
}

for _, piece in bodyPieces do
	for _, tier in TIER_NAMES do
		local stats: { [string]: number } = {
			health = scaled(piece.health, tier),
			handling = if piece.category == "Seat" then 0.06 * TIER_INDEX[tier] else 0,
		}
		if piece.cap > 0 then
			stats.weightCap = scaled(piece.cap, tier)
		end
		addPart({
			id = piece.prefix .. "_" .. string.lower(tier),
			name = tier .. " " .. piece.name,
			category = piece.category,
			tier = tier,
			weight = piece.weight,
			unlockCost = 0,
			stats = stats,
			description = piece.desc,
		})
	end
end

local weaponFamilies = {
	{
		prefix = "weapon_minigun",
		name = "Minigun",
		weight = 14,
		desc = "Spinning barrels. Holds the trigger.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 8, gunDamage = scaled(3, tier), fireRate = 28 + 2 * TIER_INDEX[tier] }
		end,
	},
	{
		prefix = "weapon_tesla",
		name = "Tesla",
		weight = 12,
		desc = "Coil that jumps between zombies.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 4, gunDamage = scaled(10, tier), fireRate = 4 }
		end,
	},
	{
		prefix = "weapon_flame",
		name = "Flamethrower",
		weight = 16,
		desc = "Short-range fire. Clears a pack.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 10, gunDamage = scaled(20, tier), fireRate = 8 }
		end,
	},
	{
		prefix = "weapon_rail",
		name = "Rail Cannon",
		weight = 22,
		desc = "Slow shot. Punches a hole through the road.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 20, gunDamage = scaled(36, tier), fireRate = 1.2 }
		end,
	},
	{
		prefix = "weapon_shotgun",
		name = "Shotgun",
		weight = 13,
		desc = "Close-range blast that shreds everything in the cone.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 8, gunDamage = scaled(14, tier), fireRate = 1.6 }
		end,
	},
	{
		prefix = "weapon_rocket",
		name = "Rocket Pod",
		weight = 20,
		desc = "Long-range rockets with a big splash.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 6, gunDamage = scaled(30, tier), fireRate = 0.9 }
		end,
	},
	{
		prefix = "weapon_mine",
		name = "Mine Layer",
		weight = 15,
		desc = "Drops mines behind you. Best against a chasing swarm.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = 4, gunDamage = scaled(26, tier), fireRate = 1.4 }
		end,
	},
	{
		prefix = "weapon_ram",
		name = "Ram",
		weight = 10,
		desc = "Bumper blade. Damage is the drive.",
		stats = function(tier: string): { [string]: number }
			return { ramDamage = scaled(28, tier), gunDamage = 0, fireRate = 0 }
		end,
	},
}

for _, family in weaponFamilies do
	for _, tier in TIER_NAMES do
		addPart({
			id = family.prefix .. "_" .. string.lower(tier),
			name = tier .. " " .. family.name,
			category = "Weapon",
			tier = tier,
			weight = family.weight,
			unlockCost = 0,
			stats = family.stats(tier),
			description = family.desc,
		})
	end
end

-- Store prices. Every purchasable part is priced from its tier, so a higher
-- rarity always costs more than the one below it, whatever the category. Parts
-- at cost 0 are lever drops and stay that way.
local TIER_PRICE = {
	Common = 40,
	Uncommon = 85,
	Rare = 180,
	Epic = 380,
	Legendary = 800,
	Mythic = 1700,
	Relic = 3600,
}
-- Some categories run a little cheaper or dearer than the tier baseline.
local CATEGORY_PRICE = {
	Wheels = 0.85,
	FuelTank = 0.85,
	Weapon = 1.25,
}

for _, part in Parts do
	local price = TIER_PRICE[part.tier]
	if part.unlockCost > 0 and price then
		local scaledPrice = price * (CATEGORY_PRICE[part.category] or 1)
		part.unlockCost = math.floor(scaledPrice / 5 + 0.5) * 5
	end
end

function PartsCatalog.Get(id: string): PartDef?
	return Parts[id]
end

function PartsCatalog.GetAll(): { [string]: PartDef }
	return Parts
end

function PartsCatalog.GetByCategory(category: string): { PartDef }
	local list = {}
	for _, part in Parts do
		if part.category == category then
			table.insert(list, part)
		end
	end
	table.sort(list, function(a, b)
		return a.unlockCost < b.unlockCost
	end)
	return list
end

function PartsCatalog.ComputeLoadoutStats(loadout: { [string]: string }): {
	health: number,
	fuel: number,
	speed: number,
	accel: number,
	handling: number,
	offroad: number,
	damageReduction: number,
	weight: number,
	weightCap: number,
	hardpoints: number,
	ramDamage: number,
	gunDamage: number,
	fireRate: number,
	repairPerSec: number,
	boostMult: number,
	pickupMult: number,
	scrapMult: number,
	shieldMax: number,
	shieldRegen: number,
	fuelPerKill: number,
	weaponKind: string,
	weapons: { WeaponMount },
	overweight: boolean,
}
	local stats = {
		health = 0,
		fuel = 0,
		speed = 0,
		accel = 0,
		handling = 0,
		offroad = 0,
		damageReduction = 0,
		weight = 0,
		weightCap = 80,
		hardpoints = 1,
		ramDamage = 0,
		gunDamage = 0,
		fireRate = 0,
		repairPerSec = 0,
		boostMult = 1,
		pickupMult = 1,
		scrapMult = 1,
		shieldMax = 0,
		shieldRegen = 0,
		fuelPerKill = 0,
		weaponKind = "",
		weapons = {},
		overweight = false,
	}

	for _, partId in loadout do
		local part = Parts[partId]
		if part then
			stats.weight += part.weight
			for key, value in part.stats do
				if key == "boostMult" then
					stats.boostMult = math.max(stats.boostMult, value)
				elseif key == "pickupMult" then
					stats.pickupMult = math.max(stats.pickupMult, value)
				elseif key == "scrapMult" then
					stats.scrapMult = math.max(stats.scrapMult, value)
				elseif typeof(stats[key]) == "number" then
					stats[key] = (stats[key] :: number) + value
				end
			end
		end
	end

	if stats.health <= 0 then
		stats.health = 100
	end
	if stats.fuel <= 0 then
		stats.fuel = 80
	end
	if stats.speed <= 0 then
		stats.speed = 35
	end
	if stats.accel <= 0 then
		stats.accel = 15
	end
	if stats.handling <= 0 then
		stats.handling = 0.8
	end

	stats.overweight = stats.weight > stats.weightCap
	if stats.overweight then
		local penalty = math.clamp(1 - (stats.weight - stats.weightCap) / stats.weightCap, 0.5, 1)
		stats.speed *= penalty
		stats.accel *= penalty
		stats.handling *= penalty
	end

	return stats
end

function PartsCatalog.DefaultLoadout(): { [string]: string }
	return {
		Chassis = "chassis_scrap",
		Hood = "",
		Cab = "",
		Bed = "",
		Engine = "",
		Wheels = "",
		FuelTank = "",
		Seat = "",
		Armor = "",
		Weapon = "",
		Utility = "",
	}
end

function PartsCatalog.MissingPieces(loadout: { [string]: string }): { string }
	local missing = {}
	for _, category in PartsCatalog.RequiredToRun do
		if (loadout[category] or "") == "" then
			table.insert(missing, PartsCatalog.SocketLabel[category] or category)
		end
	end
	return missing
end

function PartsCatalog.TargetsFor(kind: string): { LeverTarget }
	if kind == "Weapons" then
		return PartsCatalog.WeaponTargets
	elseif kind == "Drive" then
		return PartsCatalog.DriveTargets
	elseif kind == "Gear" then
		return PartsCatalog.GearTargets
	end
	return PartsCatalog.BodyTargets
end

function PartsCatalog.IsLeverKind(kind: string): boolean
	for _, entry in PartsCatalog.LeverKinds do
		if entry.kind == kind then
			return true
		end
	end
	return false
end

function PartsCatalog.FindTarget(kind: string, targetId: string): LeverTarget?
	for _, target in PartsCatalog.TargetsFor(kind) do
		if target.id == targetId then
			return target
		end
	end
	return nil
end

function PartsCatalog.PartIdFor(prefix: string, tier: string): string
	return prefix .. "_" .. string.lower(tier)
end

export type PlacedBlock = {
	partId: string,
	x: number,
	y: number,
	z: number,
	rot: number,
}

local SHAPES: { [string]: { size: Vector3, kind: string } } = {
	brick = { size = Vector3.new(4, 2, 2), kind = "brick" },
	long = { size = Vector3.new(8, 2, 2), kind = "brick" },
	plate = { size = Vector3.new(6, 1, 6), kind = "plate" },
	slab = { size = Vector3.new(8, 1, 4), kind = "plate" },
	pillar = { size = Vector3.new(2, 4, 2), kind = "brick" },
	armor = { size = Vector3.new(4, 1, 2), kind = "armor" },
	utility = { size = Vector3.new(2, 2, 2), kind = "utility" },
	wedge = { size = Vector3.new(4, 2, 4), kind = "wedge" },
	engine = { size = Vector3.new(4, 2, 4), kind = "engine" },
	wheels = { size = Vector3.new(2, 2, 2), kind = "wheel" },
	fuel = { size = Vector3.new(2, 2, 2), kind = "fuel" },
	seat = { size = Vector3.new(2, 2, 2), kind = "seat" },
	weapon_minigun = { size = Vector3.new(2, 2, 4), kind = "minigun" },
	weapon_tesla = { size = Vector3.new(2, 3, 2), kind = "tesla" },
	weapon_flame = { size = Vector3.new(2, 2, 4), kind = "flame" },
	weapon_rail = { size = Vector3.new(2, 2, 6), kind = "rail" },
	weapon_ram = { size = Vector3.new(6, 2, 2), kind = "ram" },
	weapon_shotgun = { size = Vector3.new(2, 2, 4), kind = "shotgun" },
	weapon_rocket = { size = Vector3.new(4, 2, 4), kind = "rocket" },
	weapon_mine = { size = Vector3.new(4, 2, 2), kind = "mine" },
}

local SHAPE_PREFIXES = {
	"weapon_minigun",
	"weapon_tesla",
	"weapon_flame",
	"weapon_rail",
	"weapon_ram",
	"weapon_shotgun",
	"weapon_rocket",
	"weapon_mine",
	"long",
	"brick",
	"plate",
	"slab",
	"pillar",
	"armor",
	"utility",
	"wedge",
	"engine",
	"wheels",
	"fuel",
	"seat",
}

function PartsCatalog.ShapeOf(partId: string): { size: Vector3, kind: string }
	for _, prefix in SHAPE_PREFIXES do
		if string.sub(partId, 1, #prefix) == prefix then
			local shape = SHAPES[prefix]
			if shape then
				return shape
			end
		end
	end
	return { size = Vector3.new(2, 2, 2), kind = "brick" }
end

function PartsCatalog.BlockKind(partId: string): string
	return PartsCatalog.ShapeOf(partId).kind
end

function PartsCatalog.BlockSize(partId: string, rot: number): Vector3
	local size = PartsCatalog.ShapeOf(partId).size
	local turns = math.floor((((rot % 360) + 360) % 360) / 90 + 0.5) % 4
	if turns == 1 or turns == 3 then
		return Vector3.new(size.Z, size.Y, size.X)
	end
	return size
end

local function xzOverlap(a: PlacedBlock, sa: Vector3, b: PlacedBlock, sb: Vector3): boolean
	return math.abs(a.x - b.x) < (sa.X + sb.X) / 2 - 0.05 and math.abs(a.z - b.z) < (sa.Z + sb.Z) / 2 - 0.05
end

function PartsCatalog.BlocksOverlap(a: PlacedBlock, b: PlacedBlock): boolean
	local sa = PartsCatalog.BlockSize(a.partId, a.rot)
	local sb = PartsCatalog.BlockSize(b.partId, b.rot)
	local ay = a.y + sa.Y / 2
	local by = b.y + sb.Y / 2
	return xzOverlap(a, sa, b, sb) and math.abs(ay - by) < (sa.Y + sb.Y) / 2 - 0.05
end

function PartsCatalog.BlockInBounds(block: PlacedBlock): boolean
	local size = PartsCatalog.BlockSize(block.partId, block.rot)
	local minX = block.x - size.X / 2
	local maxX = block.x + size.X / 2
	local minZ = block.z - size.Z / 2
	local maxZ = block.z + size.Z / 2
	return minX >= -14 and maxX <= 14 and minZ >= -16 and maxZ <= 16 and block.y >= -0.05 and block.y + size.Y <= 16
end

function PartsCatalog.BlockSupported(block: PlacedBlock, others: { PlacedBlock }): boolean
	if block.y <= 0.05 then
		return block.y >= -0.05
	end
	local size = PartsCatalog.BlockSize(block.partId, block.rot)
	for _, other in others do
		local osize = PartsCatalog.BlockSize(other.partId, other.rot)
		if math.abs(block.y - (other.y + osize.Y)) < 0.2 and xzOverlap(block, size, other, osize) then
			return true
		end
	end
	return false
end

function PartsCatalog.ComputeBlockStats(blocks: { PlacedBlock })
	local rank = { Scrap = 0, Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6, Relic = 7 }
	-- Same tier: prefer the part with the bigger stats, so which variant counts
	-- does not depend on table iteration order.
	local function power(part: PartDef): number
		local total = 0
		for _, value in part.stats do
			total += value
		end
		return total
	end
	local best: { [string]: PartDef } = {}
	local extraHealth = 0
	local extraWeight = 0
	local mounts: { WeaponMount } = {}
	local weaponWeight = 0
	local strongestRam = 0
	for _, block in blocks do
		local part = PartsCatalog.Get(block.partId)
		if part then
			if part.category == "Weapon" then
				-- Every weapon on the car fires and weighs, not just the best one.
				weaponWeight += part.weight
				strongestRam = math.max(strongestRam, part.stats.ramDamage or 0)
				local damage, rate = part.stats.gunDamage or 0, part.stats.fireRate or 0
				if damage > 0 and rate > 0 then
					local size = PartsCatalog.BlockSize(block.partId, block.rot)
					table.insert(mounts, {
						partId = block.partId,
						kind = PartsCatalog.BlockKind(block.partId),
						damage = damage,
						fireRate = rate,
						x = block.x,
						y = block.y + size.Y / 2,
						z = block.z,
					})
				end
			end
			if part.category == "Block" then
				extraHealth += part.stats.health or 0
				extraWeight += part.weight
			else
				local current = best[part.category]
				local better = current ~= nil
					and ((rank[part.tier] or 0) > (rank[current.tier] or 0)
						or ((rank[part.tier] or 0) == (rank[current.tier] or 0) and power(part) > power(current)))
				if not current or better then
					best[part.category] = part
				end
			end
		end
	end
	local loadout = PartsCatalog.DefaultLoadout()
	for category, part in best do
		loadout[category] = part.id
	end
	local stats = PartsCatalog.ComputeLoadoutStats(loadout)
	if best.Weapon then
		stats.weaponKind = PartsCatalog.BlockKind(best.Weapon.id)
	end
	if stats.overweight then
		local penalty = math.clamp(1 - (stats.weight - stats.weightCap) / math.max(stats.weightCap, 1), 0.5, 1)
		if penalty > 0 then
			stats.speed /= penalty
			stats.accel /= penalty
			stats.handling /= penalty
		end
	end
	-- The best weapon's weight is already in the loadout; add the rest.
	extraWeight += weaponWeight - (if best.Weapon then best.Weapon.weight else 0)
	-- Too many guns would cost the server more than they are worth.
	table.sort(mounts, function(a, b)
		return a.damage * a.fireRate > b.damage * b.fireRate
	end)
	while #mounts > PartsCatalog.MAX_MOUNTED_WEAPONS do
		table.remove(mounts)
	end
	stats.weapons = mounts
	if best.Weapon then
		stats.ramDamage = strongestRam
	end
	stats.weight += extraWeight
	stats.health += extraHealth
	stats.overweight = stats.weight > stats.weightCap
	if stats.overweight then
		local penalty = math.clamp(1 - (stats.weight - stats.weightCap) / math.max(stats.weightCap, 1), 0.5, 1)
		stats.speed *= penalty
		stats.accel *= penalty
		stats.handling *= penalty
	end
	return stats
end

function PartsCatalog.MissingFromBlocks(blocks: { PlacedBlock }): { string }
	local have: { [string]: boolean } = {}
	for _, block in blocks do
		local part = PartsCatalog.Get(block.partId)
		if part then
			have[part.category] = true
		end
	end
	local missing = {}
	for _, category in PartsCatalog.RequiredToRun do
		if not have[category] then
			table.insert(missing, PartsCatalog.SocketLabel[category] or category)
		end
	end
	return missing
end

function PartsCatalog.RollTier(): string
	local total = 0
	for _, entry in Constants.RARITY_ODDS do
		total += entry.weight
	end
	local roll = math.random(1, total)
	local acc = 0
	for _, entry in Constants.RARITY_ODDS do
		acc += entry.weight
		if roll <= acc then
			return entry.tier
		end
	end
	return "Common"
end

return PartsCatalog
