--[[
	Venom Bar - applies weapon venoms. Global, not tied to any form, since
	venom application isn't form-locked.
]]

local Core = VenomancerAssistant
VenomBarModule = VenomBarModule or {}

local dbFn = Core.RegisterModuleDB("venomBar", {
	point = "CENTER", x = 0, y = -300,
	locked = false,
	minimized = false,
	iconSize = 32,
	spacing = 4,
	growth = "RIGHT",
	selected1 = nil,
	selected2 = nil,
})

VenomBarModule.dbFn = dbFn

--------------------------------------------------------------------------------
-- Venom scanning - by name rather than a hardcoded list
--------------------------------------------------------------------------------

-- Known venom spell IDs (name-based spellbook scan below still runs too,
-- as a fallback in case Ascension adds more venoms later - this list just
-- guarantees these specific ones are always found reliably.)
local KNOWN_VENOM_IDS = {
	["Nullifying Venom"] = 805777,
	["Debilitating Venom"] = 805731,
	["Blight Venom"] = 805776,
	["Weakening Venom"] = 805778,
	["Rejuvenating Venom"] = 630868,
	["Withering Venom"] = 707090,
}

local knownVenoms = {}

local VENOM_EXCLUDE = {
	["venom bolt"] = true, ["venomtip poison"] = true, ["venom fang"] = true,
	["venomwing form"] = true, ["envenomed weapons"] = true, ["remove venoms"] = true, ["antivenom"] = true,
}

local scanTip = CreateFrame("GameTooltip", "VenomBarScanTooltip", nil, "GameTooltipTemplate")
scanTip:SetOwner(UIParent, "ANCHOR_NONE")

local function GetSpellTooltipText(spellIndex)
	scanTip:ClearLines()
	local ok = pcall(function() scanTip:SetSpell(spellIndex, BOOKTYPE_SPELL) end)
	if not ok or scanTip:NumLines() == 0 then
		scanTip:ClearLines()
		ok = pcall(function() scanTip:SetSpellBookItem(spellIndex, BOOKTYPE_SPELL) end)
	end
	if not ok or scanTip:NumLines() == 0 then return nil end
	local lines = {}
	for i = 1, scanTip:NumLines() do
		local fs = _G["VenomBarScanTooltipTextLeft" .. i]
		local text = fs and fs:GetText()
		if text and text ~= "" then lines[#lines + 1] = text end
	end
	return table.concat(lines, " ")
end

local function ExtractKeyEffect(fullText)
	if not fullText then return nil end
	return fullText:match("%d+%%%s+chance[^.]+%.")
end

local function ScanVenoms()
	wipe(knownVenoms)
	local byName, order = {}, {}
	for i = 1, 1024 do
		local name = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name:lower():find("venom") and not VENOM_EXCLUDE[name:lower()] then
			local texture
			if type(GetSpellTexture) == "function" then texture = GetSpellTexture(i, BOOKTYPE_SPELL) end
			if not byName[name] then order[#order + 1] = name end
			byName[name] = {
				name = name, icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
				index = i, keyEffect = ExtractKeyEffect(GetSpellTooltipText(i)),
			}
		end
	end
	-- Cross-check against the known venom IDs so a naming quirk or a
	-- spellbook-index edge case can't silently drop one of these six -
	-- if the name scan above already found it, this changes nothing.
	for name, id in pairs(KNOWN_VENOM_IDS) do
		if not byName[name] and IsSpellKnown and IsSpellKnown(id) then
			local specName, _, icon = GetSpellInfo(id)
			if specName then
				order[#order + 1] = name
				byName[name] = { name = name, icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark", index = nil, keyEffect = nil }
			end
		end
	end
	for _, name in ipairs(order) do table.insert(knownVenoms, byName[name]) end
end

function VenomBarModule.GetKnownVenoms() return knownVenoms end

--------------------------------------------------------------------------------
-- Frame setup
--------------------------------------------------------------------------------

local anchorFrame = CreateFrame("Frame", "VenomBarAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local bar = CreateFrame("Frame", "VenomBarFrame", UIParent)
bar:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel (DIALOG), so it's never hidden behind it
bar:SetSize(200, 36)
bar:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
bar:SetClampedToScreen(true)
bar:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
bar:SetBackdropColor(0, 0, 0, 0)
bar:SetBackdropBorderColor(1, 0.82, 0, 0)

local dragHint = CreateFrame("Frame", nil, UIParent)
dragHint:SetSize(170, 20)
dragHint:SetPoint("BOTTOM", bar, "TOP", 0, 8)
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
dragHintText:SetText("Drag: Venom Bar")
dragHintText:SetTextColor(1, 0.82, 0)
dragHint:SetScript("OnDragStart", function() anchorFrame:StartMoving() end)
dragHint:SetScript("OnDragStop", function()
	anchorFrame:StopMovingOrSizing()
	local d = dbFn()
	d.point, _, _, d.x, d.y = anchorFrame:GetPoint()
end)
dragHint:Hide()

--------------------------------------------------------------------------------
-- Apply button
--------------------------------------------------------------------------------

local castButton = CreateFrame("Button", "VenomBarCastButton", bar, "SecureActionButtonTemplate")
castButton:RegisterForClicks("LeftButtonDown", "MiddleButtonDown")
castButton:SetAttribute("type", "spell")
castButton:SetSize(32, 32)

local castIcon = castButton:CreateTexture(nil, "ARTWORK")
castIcon:SetAllPoints()
castIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local castButtonBorder = CreateFrame("Frame", nil, castButton)
castButtonBorder:SetPoint("TOPLEFT", -2, 2)
castButtonBorder:SetPoint("BOTTOMRIGHT", 2, -2)
castButtonBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
castButtonBorder:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)

local applyCycleStep = 1

local function RefreshCastIcon()
	local d = dbFn()
	local venomName = (applyCycleStep == 1) and d.selected1 or d.selected2
	for _, v in ipairs(knownVenoms) do
		if v.name == venomName then
			castIcon:SetTexture(v.icon)
			castButton.venomName = v.name
			return
		end
	end
	castIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
	castButton.venomName = nil
end

castButton:SetScript("PreClick", function(self, button)
	if button == "MiddleButton" then
		self:SetAttribute("spell", "Remove Venoms")
	else
		local d = dbFn()
		local venomName = (applyCycleStep == 1) and d.selected1 or d.selected2
		self:SetAttribute("spell", venomName)
		applyCycleStep = (applyCycleStep == 1) and 2 or 1
	end
end)
castButton:SetScript("PostClick", function() RefreshCastIcon() end)
castButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText("Apply Venom")
	GameTooltip:AddLine(" ")
	GameTooltip:AddLine("Left-click / keybind: apply selection 1, then 2 (alternates)", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Middle-click: Remove Venoms", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
castButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

--------------------------------------------------------------------------------
-- Venom selection buttons (expanded mode)
--------------------------------------------------------------------------------

local venomButtons = {}

local function CreateVenomButton(i)
	local b = CreateFrame("Button", "VenomBarSelectButton" .. i, bar)
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

	local glow = b:CreateTexture(nil, "BACKGROUND")
	glow:SetPoint("TOPLEFT", -4, 4)
	glow:SetPoint("BOTTOMRIGHT", 4, -4)
	glow:SetTexture("Interface\\Cooldown\\star4")
	glow:SetBlendMode("ADD")
	glow:SetVertexColor(1, 1, 1, 0)
	b.glow = glow

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetAllPoints()
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon = icon

	local border = CreateFrame("Frame", nil, b)
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 })
	border:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
	b.border = border

	local badgeBG = CreateFrame("Frame", nil, b)
	badgeBG:SetSize(15, 15)
	badgeBG:SetPoint("BOTTOMRIGHT", 1, -1)
	badgeBG:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 6, insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	badgeBG:SetBackdropBorderColor(0, 0, 0, 1)
	badgeBG:Hide()
	b.badgeBG = badgeBG

	local badge = badgeBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	badge:SetPoint("CENTER", 0, 0)
	badge:Hide()
	b.badge = badge

	b:SetScript("OnClick", function(self, mouseButton)
		local d = dbFn()
		if mouseButton == "LeftButton" then d.selected1 = self.venomName
		elseif mouseButton == "RightButton" then d.selected2 = self.venomName end
		VenomBarModule.RefreshSelectionVisuals()
		RefreshCastIcon()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.venomName or "")
		if self.keyEffect then GameTooltip:AddLine(self.keyEffect, 1, 0.82, 0, true) end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: set as selection 1", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: set as selection 2", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	venomButtons[i] = b
	return b
end

local SELECTED_COLOR_1 = { 1, 0.82, 0 }
local SELECTED_COLOR_2 = { 0.3, 0.75, 1 }

function VenomBarModule.RefreshSelectionVisuals()
	local d = dbFn()
	for _, b in ipairs(venomButtons) do
		if b.venomName and b.venomName == d.selected1 then
			local c = SELECTED_COLOR_1
			b.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			b.glow:SetVertexColor(c[1], c[2], c[3], 0.8)
			b.badgeBG:SetBackdropColor(c[1], c[2], c[3], 1)
			b.badgeBG:Show(); b.badge:SetText("1"); b.badge:SetTextColor(0, 0, 0); b.badge:Show()
		elseif b.venomName and b.venomName == d.selected2 then
			local c = SELECTED_COLOR_2
			b.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			b.glow:SetVertexColor(c[1], c[2], c[3], 0.8)
			b.badgeBG:SetBackdropColor(c[1], c[2], c[3], 1)
			b.badgeBG:Show(); b.badge:SetText("2"); b.badge:SetTextColor(0, 0, 0); b.badge:Show()
		else
			b.border:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
			b.glow:SetVertexColor(1, 1, 1, 0)
			b.badgeBG:Hide(); b.badge:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local toggleButton = CreateFrame("Button", "VenomBarToggleButton", bar, "UIPanelButtonTemplate")
toggleButton:SetSize(16, 20)

local emptyLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
emptyLabel:SetPoint("LEFT", bar, "LEFT", 2, 0)
emptyLabel:SetText("No Venom spells known yet")
emptyLabel:Hide()

local relayoutQueued = false
local GROWTH_INFO = {
	RIGHT = { point = "LEFT", relPoint = "LEFT", minArrow = ">", expArrow = "<" },
	LEFT  = { point = "RIGHT", relPoint = "LEFT", minArrow = "<", expArrow = ">" },
	DOWN  = { point = "TOP", relPoint = "LEFT", minArrow = "v", expArrow = "^" },
	UP    = { point = "BOTTOM", relPoint = "LEFT", minArrow = "^", expArrow = "v" },
}

local function RelayoutBar()
	if InCombatLockdown and InCombatLockdown() then
		relayoutQueued = true
		return
	end
	relayoutQueued = false

	local d = dbFn()
	local size = d.iconSize
	local spacing = d.spacing
	local growth = d.growth or "RIGHT"
	local vertical = (growth == "UP" or growth == "DOWN")
	local info = GROWTH_INFO[growth] or GROWTH_INFO.RIGHT

	bar:ClearAllPoints()
	bar:SetPoint(info.point, anchorFrame, info.relPoint, 0, 0)

	toggleButton:ClearAllPoints()
	toggleButton:SetPoint(info.point, bar, info.point, 0, 0)
	toggleButton:SetSize(vertical and 20 or 16, vertical and 16 or 20)

	local function AnchorAfter(frame, anchorTo, gap)
		frame:ClearAllPoints()
		if growth == "LEFT" then frame:SetPoint("RIGHT", anchorTo, "LEFT", -gap, 0)
		elseif growth == "UP" then frame:SetPoint("BOTTOM", anchorTo, "TOP", 0, gap)
		elseif growth == "DOWN" then frame:SetPoint("TOP", anchorTo, "BOTTOM", 0, -gap)
		else frame:SetPoint("LEFT", anchorTo, "RIGHT", gap, 0) end
	end

	if d.minimized then
		emptyLabel:Hide()
		for _, b in ipairs(venomButtons) do b:Hide() end
		AnchorAfter(castButton, toggleButton, 4)
		castButton:SetSize(size, size)
		castButton:Show()
		toggleButton:SetText(info.minArrow)
		if vertical then bar:SetSize(size, size + 4 + 16) else bar:SetSize(size + 4 + 16, size) end
	elseif #knownVenoms == 0 then
		castButton:Hide()
		for _, b in ipairs(venomButtons) do b:Hide() end
		emptyLabel:Show()
		AnchorAfter(emptyLabel, toggleButton, 6)
		toggleButton:SetText(info.expArrow)
		if vertical then bar:SetSize(math.max(20, emptyLabel:GetStringWidth()), 20 + 6 + 16)
		else bar:SetSize(emptyLabel:GetStringWidth() + 6 + 16 + 4, 20) end
	else
		emptyLabel:Hide()
		castButton:Hide()
		for i, v in ipairs(knownVenoms) do
			local b = venomButtons[i] or CreateVenomButton(i)
			b.venomName = v.name
			b.spellIndex = v.index
			b.keyEffect = v.keyEffect
			b.icon:SetTexture(v.icon)
			b:SetSize(size, size)
			if i == 1 then AnchorAfter(b, toggleButton, spacing) else AnchorAfter(b, venomButtons[i - 1], spacing) end
			b:Show()
		end
		for i = #knownVenoms + 1, #venomButtons do venomButtons[i]:Hide() end
		toggleButton:SetText(info.expArrow)
		if vertical then
			local colHeight = math.max(#knownVenoms, 1) * size + math.max(#knownVenoms - 1, 0) * spacing
			bar:SetSize(size, colHeight + 6 + 16)
		else
			local rowWidth = math.max(#knownVenoms, 1) * size + math.max(#knownVenoms - 1, 0) * spacing
			bar:SetSize(rowWidth + 6 + 16, size)
		end
	end
	VenomBarModule.RefreshSelectionVisuals()
	RefreshCastIcon()
end

toggleButton:SetScript("OnClick", function()
	local d = dbFn()
	d.minimized = not d.minimized
	RelayoutBar()
end)

--------------------------------------------------------------------------------
-- Lock state
--------------------------------------------------------------------------------

local function ApplyLockVisual()
	local d = dbFn()
	local unlocked = not d.locked
	dragHint:EnableMouse(unlocked)
	dragHint:SetShown(unlocked)
	bar:SetBackdropColor(0, 0, 0, unlocked and 0.25 or 0)
	bar:SetBackdropBorderColor(1, 0.82, 0, unlocked and 0.9 or 0)
end

local lockPollElapsed = 0
local lastKnownLocked = nil
bar:SetScript("OnUpdate", function(self, elapsed)
	lockPollElapsed = lockPollElapsed + elapsed
	if lockPollElapsed < 0.5 then return end
	lockPollElapsed = 0
	local d = dbFn()
	if d.locked ~= lastKnownLocked then
		lastKnownLocked = d.locked
		ApplyLockVisual()
	end
end)

Core.RegisterLockable({ dbFn = dbFn, apply = function() ApplyLockVisual(); RelayoutBar() end })

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= Core.ADDON_NAME then return end
		local d = dbFn()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
		ScanVenoms()
		RelayoutBar()
	elseif event == "PLAYER_REGEN_ENABLED" then
		if relayoutQueued then RelayoutBar() end
	end
end)

--------------------------------------------------------------------------------
-- Keybinding
--------------------------------------------------------------------------------

BINDING_HEADER_VENOMANCERASSISTANT = "Venomancer Assistant"
_G["BINDING_NAME_CLICK VenomBarCastButton:LeftButton"] = "Apply Selected Venom (1st press = selection 1, 2nd = selection 2)"

--------------------------------------------------------------------------------
-- Options tab
--------------------------------------------------------------------------------

local function GetVenomBarTabIcon()
	for _, v in ipairs(knownVenoms) do
		if v.name == "Blight Venom" then return v.icon end
	end
	if knownVenoms[1] then return knownVenoms[1].icon end
	return "Interface\\Icons\\INV_Potion_04"
end

function Core.BuildVenomBarTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	local sc = RegisterTab("venombar", "Venom Bar", GetVenomBarTabIcon())
	local L = CreateLayoutHelpers(sc, dbFn, RelayoutBar)

	L.Note("Button Behaviour: Minimized Left Click = apply venoms - Middle Click = Clear all venoms")
	L.Note("Maximized: Left Click Selects Poison 1, Right Click Selects Poison 2")
	L.CheckboxRow("Locked", "locked", "Lock/unlock this bar's position. While unlocked, drag its \"Drag Me\" handle to move it.")
	L.Section("Layout")
	L.Slider("Icon size", "iconSize", 16, 48, 1)
	L.Slider("Icon spacing", "spacing", -8, 16, 1)
	L.Dropdown("Growth direction", "growth", {
		{ value = "RIGHT", label = "Right" }, { value = "LEFT", label = "Left" },
		{ value = "UP", label = "Up" }, { value = "DOWN", label = "Down" },
	})
	L.CheckboxRow("Minimized", "minimized", "Collapse the bar to a single button that applies your selections in sequence when clicked.")

	L.Section("Selected Venoms")
	local sel1Label = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sel1Label:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, L.GetY())
	sel1Label:SetTextColor(1, 0.82, 0)
	sel1Label:SetText("Selection 1: " .. (dbFn().selected1 or "|cff888888none|r"))
	L.AdvanceY(16)
	local sel2Label = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sel2Label:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, L.GetY())
	sel2Label:SetTextColor(0.3, 0.75, 1)
	sel2Label:SetText("Selection 2: " .. (dbFn().selected2 or "|cff888888none|r"))
	L.AdvanceY(16)

	L.Button("Rescan Spellbook", function()
		ScanVenoms()
		RelayoutBar()
	end)

	sc:SetHeight(-L.GetY() + 20)
end
