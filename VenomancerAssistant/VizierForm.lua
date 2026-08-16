--[[
	Vizier Form tab - placeholder, same reasoning as Weaver Form.
]]

local Core = VenomancerAssistant

local masterDB = Core.RegisterModuleDB("vizierTab", { enabled = true })

function Core.BuildVizierFormTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	if not Core.IsFormLearned("vizier") then return end

	local sc = RegisterTab("vizier", "Vizier Form", "Interface\\Icons\\INV_Misc_MonsterScales_09")
	local L = CreateLayoutHelpers(sc, masterDB, function() end)
	L.CheckboxRow("Enable Vizier Form tracking", "enabled", "Reserved for when Vizier Form tracking is built - nothing to track here yet.")
	L.Note("Vizier Form doesn't have a stack tracker or cooldown watcher built yet. This tab exists so it's ready to fill in once that content is mapped out.", 40)
end
