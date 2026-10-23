--!strict
--[[
	Global lighting, atmosphere, and sky for the apocalypse look.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local WorldTheme = {}

-- Always midday. The clock never moves and no biome changes it, so every
-- player sees the same bright sky wherever they are in a run.
local DAYLIGHT_CLOCK = 13

local DAY_AMBIENT = Color3.fromRGB(150, 155, 165)

function WorldTheme.Apply()
	Lighting.Brightness = 3
	Lighting.Ambient = DAY_AMBIENT
	Lighting.OutdoorAmbient = Color3.fromRGB(165, 170, 180)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 235, 200)
	Lighting.ColorShift_Bottom = Color3.fromRGB(60, 55, 50)
	Lighting.EnvironmentDiffuseScale = 0.55
	Lighting.EnvironmentSpecularScale = 0.4
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.35
	Lighting.ClockTime = DAYLIGHT_CLOCK
	Lighting.GeographicLatitude = 25
	Lighting.ExposureCompensation = 0.15
	Lighting.FogColor = Color3.fromRGB(196, 226, 248)
	Lighting.FogStart = 140
	Lighting.FogEnd = 460

	for _, name in { "Atmosphere", "Sky", "Bloom", "ColorCorrection", "SunRays", "DepthOfField" } do
		local old = Lighting:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name = "Atmosphere"
	atmosphere.Density = 0.22
	atmosphere.Offset = 0.3
	atmosphere.Color = Color3.fromRGB(180, 215, 245)
	atmosphere.Decay = Color3.fromRGB(110, 165, 235) -- the horizon haze; a warm tint made distant grass look like sand
	atmosphere.Glare = 0.1
	atmosphere.Haze = 0.5
	atmosphere.Parent = Lighting

	local sky = Instance.new("Sky")
	sky.Name = "Sky"
	sky.CelestialBodiesShown = true
	sky.StarCount = 2000
	sky.SunAngularSize = 21
	sky.MoonAngularSize = 9
	sky.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Name = "Bloom"
	bloom.Intensity = 0.25
	bloom.Size = 28
	bloom.Threshold = 1.1
	bloom.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ColorCorrection"
	cc.Brightness = 0.02
	cc.Contrast = 0.18
	cc.Saturation = 0.25
	cc.TintColor = Color3.fromRGB(255, 248, 238)
	cc.Parent = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name = "SunRays"
	sunRays.Intensity = 0.05
	sunRays.Spread = 0.6
	sunRays.Parent = Lighting

end

-- The fog closes in before the road ends (about 390 studs ahead), so the plain
-- beyond it is never seen.
-- Biomes differ by fog, haze and colour grade only; the time of day stays put.
-- The change eases in so crossing a biome border is not a sudden pop.
local BIOME_LOOK = {
	RuinedCity = { fog = Color3.fromRGB(200, 222, 242), fogEnd = 430, tint = Color3.fromRGB(250, 250, 255), haze = Color3.fromRGB(190, 215, 240), saturation = 0.2 },
	Desert = { fog = Color3.fromRGB(252, 226, 176), fogEnd = 460, tint = Color3.fromRGB(255, 245, 220), haze = Color3.fromRGB(250, 215, 160), saturation = 0.25 },
	SnowyMountains = { fog = Color3.fromRGB(205, 225, 248), fogEnd = 440, tint = Color3.fromRGB(240, 248, 255), haze = Color3.fromRGB(200, 222, 248), saturation = 0.15 },
	WastelandHighways = { fog = Color3.fromRGB(196, 226, 248), fogEnd = 460, tint = Color3.fromRGB(255, 250, 238), haze = Color3.fromRGB(180, 215, 245), saturation = 0.25 },
}

function WorldTheme.SetBiome(biome: string)
	local look = BIOME_LOOK[biome] or BIOME_LOOK.WastelandHighways
	local info = TweenInfo.new(3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(Lighting, info, { FogColor = look.fog, FogEnd = look.fogEnd }):Play()
	local cc = Lighting:FindFirstChild("ColorCorrection")
	if cc then
		TweenService:Create(cc, info, { TintColor = look.tint, Saturation = look.saturation }):Play()
	end
	local atmosphere = Lighting:FindFirstChild("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, { Color = look.haze }):Play()
	end
end

return WorldTheme
