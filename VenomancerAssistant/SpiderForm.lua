--[[
	Spider Form tab - hosts the Brood Marks tracker. Since this tab only
	has one feature, the tracker's own "Enable Brood Marks tracking"
	checkbox doubles as the tab's master switch - no separate flag needed.

	Hidden entirely if Spider Form (spell 800841) isn't learned; re-checks
	on spec swap, not just login.
]]

local Core = VenomancerAssistant

local tracker = Core.CreateStackTracker({
	namespaceKey = "spider",
	framePrefix = "VASpiderTracker",
	label = "Brood Marks",
	formLabel = "Spider Form",
	formKey = "spider",
	buffName = "Brood Mark",
	maxStacks = 5,
	defaultIcon = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
})

Core.SpiderFormTracker = tracker

function Core.BuildSpiderFormTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	if not Core.IsFormLearned("spider") then return end

	local sc = RegisterTab("spider", "Spider Form", "Interface\\Icons\\Ability_Hunter_Pet_Spider")
	tracker.BuildOptionsPage(sc, CreateLayoutHelpers, CreateSubTabPager)
end

