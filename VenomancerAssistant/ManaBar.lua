--[[
	Mana Bar - Beetle/Spider/Weaver/Vizier Form all hide the normal mana
	bar. One shared frame that shows whenever any of them is active,
	rather than a separate copy per form - own drag/lock/scale, following
	the previous Beetle-Defenses-attached mana bar's behavior.
]]

local Core = VenomancerAssistant

local dbFn = Core.RegisterModuleDB("manaBar", {
	point = "CENTER", x = 220, y = -280,
	locked = false,
	enabled = true,
	barWidth = 180,
	barHeight = 22,
	hideOutOfCombat = false,
	warnThreshold = 20, -- percent
	colorMana = { 0.3, 0.4, 0.9 },
	colorManaLow = { 1, 0.15, 0.15 },
	displayFormat = "numbers", -- "numbers", "percent", "both"
	showSolo = true, showParty = true, showRaid = true, showBattleground = true,
})

local anchorFrame = CreateFrame("Frame", "VAManaBarAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local frame = CreateFrame("Frame", "VAManaBarFrame", UIParent)
frame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel (DIALOG), so it's never hidden behind it
frame:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
frame:SetClampedToScreen(true)

local bg = frame:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
bg:SetTexture("Interface\\Buttons\\WHITE8x8")
bg:SetVertexColor(0, 0, 0, 0.55)

local border = CreateFrame("Frame", nil, frame)
border:SetAllPoints()
border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
border:SetBackdropBorderColor(0.16, 0.16, 0.18, 1)

local fill = frame:CreateTexture(nil, "ARTWORK")
fill:SetTexture("Interface\\Buttons\\WHITE8x8")
fill:SetPoint("TOPLEFT", 1, -1)
fill:SetPoint("BOTTOMLEFT", 1, 1)

local icon = frame:CreateTexture(nil, "OVERLAY")
icon:SetPoint("LEFT", 2, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
icon:SetTexture("Interface\\Icons\\INV_Elemental_Primal_Mana")

local timeText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
timeText:SetPoint("RIGHT", -4, 0)

local dragHint = CreateFrame("Frame", nil, UIParent)
dragHint:SetSize(170, 20)
dragHint:SetMovable(true)
dragHint:SetClampedToScreen(true)
dragHint:RegisterForDrag("LeftButton")
dragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
dragHint:SetBackdropColor(0, 0, 0, 0.8)
dragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local dragHintText = dragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dragHintText:SetAllPoints()
dragHintText:SetJustifyH("CENTER")
dragHintText:SetWordWrap(false)
dragHintText:SetJustifyV("MIDDLE")
dragHintText:SetText("Drag: Mana Bar")
dragHintText:SetTextColor(1, 0.82, 0)
dragHint:SetScript("OnDragStart", function() anchorFrame:StartMoving() end)
dragHint:SetScript("OnDragStop", function()
	anchorFrame:StopMovingOrSizing()
	local d = dbFn()
	d.point, _, _, d.x, d.y = anchorFrame:GetPoint()
end)
dragHint:Hide()

local function ApplyLockVisual()
	local d = dbFn()
	local unlocked = not d.locked
	dragHint:EnableMouse(unlocked)
	dragHint:SetShown(unlocked)
	dragHint:ClearAllPoints()
	dragHint:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 8)
end

local function GetGroupContext()
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "pvp" or instanceType == "arena") then return "battleground" end
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "raid" end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "party" end
	return "solo"
end

local function Refresh()
	local d = dbFn()
	frame:SetSize(d.barWidth, d.barHeight)
	frame:SetScale(1)
	icon:SetSize(d.barHeight - 4, d.barHeight - 4)

	local mana = UnitPower("player", 0)
	local maxMana = UnitPowerMax("player", 0)
	local fraction = maxMana > 0 and (mana / maxMana) or 0
	local percent = math.floor(fraction * 100 + 0.5)
	local low = percent <= (d.warnThreshold or 20)
	local color = low and d.colorManaLow or d.colorMana

	local text
	if d.displayFormat == "percent" then text = percent .. "%"
	elseif d.displayFormat == "both" then text = mana .. " / " .. maxMana .. "  (" .. percent .. "%)"
	else text = mana .. " / " .. maxMana end

	fill:SetVertexColor(color[1], color[2], color[3], 1)
	fill:SetWidth(math.max(1, (d.barWidth - 2) * math.max(0, math.min(1, fraction))))
	timeText:SetText(text)

	local ctx = GetGroupContext()
	local contextOK = (ctx == "solo" and d.showSolo) or (ctx == "party" and d.showParty)
		or (ctx == "raid" and d.showRaid) or (ctx == "battleground" and d.showBattleground)
	local formActive = Core.GetActiveFormKey() ~= nil -- any tracked form that hides the normal mana bar

	if not d.enabled and d.locked then
		frame:Hide()
	elseif d.locked and (not formActive or (d.hideOutOfCombat and not UnitAffectingCombat("player")) or not contextOK) then
		frame:Hide()
	else
		frame:Show()
	end
end

local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, e)
	elapsed = elapsed + e
	if elapsed >= 0.2 then elapsed = 0; Refresh() end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("UNIT_POWER")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= Core.ADDON_NAME then return end
		local d = dbFn()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
		ApplyLockVisual()
	elseif event == "UNIT_POWER" then
		if arg1 == "player" or arg1 == nil then Refresh() end
	else
		Refresh()
	end
end)

Core.RegisterLockable({ dbFn = dbFn, apply = function() ApplyLockVisual(); Refresh() end })

function Core.BuildManaBarTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	local sc = RegisterTab("manabar", "Mana", "Interface\\Icons\\INV_Elemental_Primal_Mana")
	local L = CreateLayoutHelpers(sc, dbFn, Refresh)
	L.CheckboxRow("Show Mana bar while shapeshifted", "enabled", "Beetle/Spider/Weaver/Vizier Form all hide your normal mana bar - shows whenever any of them is active, so this doesn't need one copy per form.")
	L.CheckboxRow("Locked", "locked", "Lock/unlock this bar's position. While unlocked, drag its \"Drag Me\" handle to move it.", function() ApplyLockVisual() end)
	L.CheckboxRow("Hide when not in combat", "hideOutOfCombat")
	L.Slider("Bar width", "barWidth", 80, 320, 5)
	L.Slider("Bar height", "barHeight", 14, 36, 1)
	L.Slider("Low-mana warning threshold (%)", "warnThreshold", 0, 100, 1)
	L.Dropdown("Display format", "displayFormat", {
		{ value = "numbers", label = "Numbers" }, { value = "percent", label = "Percent" }, { value = "both", label = "Both" },
	})
	L.ColorSwatch("Mana color:", "colorMana")
	L.ColorSwatch("Low-mana color:", "colorManaLow")
	L.Section("Visibility")
	L.CheckboxRow("Show in solo play", "showSolo")
	L.CheckboxRow("Show in a party", "showParty")
	L.CheckboxRow("Show in a raid", "showRaid")
	L.CheckboxRow("Show in battlegrounds/arenas", "showBattleground")
	sc:SetHeight(-L.GetY() + 20)
end
