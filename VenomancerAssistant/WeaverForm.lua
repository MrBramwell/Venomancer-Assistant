--[[
	Weaver Form tab - placeholder. Nothing's built for this form yet since
	its resource/cooldowns haven't been played/mapped out. Shows once the
	form is learned so the tab exists and can be filled in later, but
	there's no tracker behind it yet.
]]

local Core = VenomancerAssistant

local masterDB = Core.RegisterModuleDB("weaverTab", { enabled = true })

function Core.BuildWeaverFormTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	if not Core.IsFormLearned("weaver") then return end

	local sc = RegisterTab("weaver", "Weaver Form", "Interface\\Icons\\INV_Misc_MonsterScales_15")
	local L = CreateLayoutHelpers(sc, masterDB, function() end)
	L.CheckboxRow("Enable Weaver Form tracking", "enabled", "Reserved for when Weaver Form tracking is built - nothing to track here yet.")
	L.Note("Weaver Form doesn't have a stack tracker or cooldown watcher built yet. This tab exists so it's ready to fill in once that content is mapped out.", 40)
end
