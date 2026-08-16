--[[
	Beetle Form tab - hosts two independently-draggable features:
	Exposed Flesh (stack tracker) and Beetle Defenses (cooldown watcher).
	A single master toggle here can turn both off at once without losing
	either one's individual on/off preference.
]]

local Core = VenomancerAssistant

local masterDB = Core.RegisterModuleDB("beetleTab", { enabled = true })

function Core.IsBeetleFormTabEnabled()
	return masterDB().enabled
end

local tracker = Core.CreateStackTracker({
	namespaceKey = "beetle",
	framePrefix = "VABeetleTracker",
	label = "Exposed Flesh",
	formLabel = "Beetle Form",
	formKey = "beetle",
	buffName = "Exposed Flesh",
	maxStacks = 10,
	defaultIcon = "Interface\\Icons\\INV_Misc_MonsterScales_03",
	masterEnabledFn = Core.IsBeetleFormTabEnabled,
	-- Exposed Flesh leans "more urgent" than Brood Marks by default:
	-- warned earlier (relative to its higher max) and redder at max.
	defaultsOverride = {
		maxColor = { 1, 0.15, 0.15 },
		maxSustain = true,
		warnEnabled = true,
		warnThreshold = 7,
		warnColor = { 1, 0.55, 0.1 },
	},
})

Core.BeetleFormTracker = tracker

function Core.BuildBeetleFormTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	if not Core.IsFormLearned("beetle") then return end

	local sc = RegisterTab("beetle", "Beetle Form", "Interface\\Icons\\INV_Misc_MonsterScales_03")
	local L = CreateLayoutHelpers(sc, masterDB, function()
		tracker.Update()
		Core.BeetleDefenses.Update()
	end)
	L.CheckboxRow("Enable Beetle Form tracking", "enabled", "Master switch for this tab - turns off both Exposed Flesh and Beetle Defenses at once, without losing either one's individual settings.")

	local outer, SelectOuter = CreateSubTabPager(sc, {
		{ key = "ef", label = "Exposed Flesh" },
		{ key = "defenses", label = "Beetle Defenses" },
	}, L.GetY())

	tracker.BuildOptionsPage(outer.ef, CreateLayoutHelpers, CreateSubTabPager)
	Core.BeetleDefenses.BuildOptionsPage(outer.defenses, CreateLayoutHelpers, CreateSubTabPager)

	SelectOuter("ef")
end
