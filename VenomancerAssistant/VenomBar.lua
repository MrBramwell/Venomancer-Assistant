--[[
	Venom Bar
]]

local ADDON_NAME = "VenomancerAssistant"
VenomBarModule = VenomBarModule or {}

local function GetDB()
	VenomancerAssistantDB = VenomancerAssistantDB or BroodMarksDB or {}
	local d = VenomancerAssistantDB
	if d.vbPoint == nil then
		d.vbPoint, d.vbX, d.vbY = "CENTER", 0, -300
		d.vbMinimized = false
		d.vbIconSize = 32
		d.vbSpacing = 4
		d.vbGrowth = "RIGHT" -- "RIGHT" or "LEFT"
		d.vbSelected1 = nil
		d.vbSelected2 = nil
	end
	if d.warnMissingVenomEnabled == nil then
		-- Missing Venom: warns if fewer than 2 known venoms are applied
		d.warnMissingVenomEnabled = true
		d.warnMissingVenomIcon = true
		d.warnMissingVenomText = false
		d.warnMissingVenomSound = true

		-- Missing Pheromone: warns if no buff with "Pheromone" in the
		-- name is active
		d.warnPheromoneEnabled = true
		d.warnPheromoneIcon = true
		d.warnPheromoneText = false
		d.warnPheromoneSound = false

		-- Envenomed Weapons: warns if that exact buff isn't active
		d.warnEnvenomedEnabled = true
		d.warnEnvenomedIcon = true
		d.warnEnvenomedText = false
		d.warnEnvenomedSound = false

		-- Shared appearance for the big-text warning banner (all active
		-- warnings' text uses the same style, just different lines)
		d.warnTextColor = { 1, 0.2, 0.2 }
		d.warnTextBorderColor = { 0, 0, 0 }
		d.warnTextSize = 26
		d.warnTextOutline = "OUTLINE" -- "NONE", "OUTLINE", or "THICKOUTLINE"
		d.warnTextPoint, d.warnTextX, d.warnTextY = "TOP", 0, -160
	end

	if d.warnTextBorderColor == nil then
		d.warnTextBorderColor = { 0, 0, 0 }
	end
	if d.warnTextPoint == nil then
		d.warnTextPoint, d.warnTextX, d.warnTextY = "TOP", 0, -160
	end
	return d
end


GetDB()

--------------------------------------------------------------------------------
-- Venom scanning - by name rather than a hardcoded list
--------------------------------------------------------------------------------

local knownVenoms = {} -- { {name=.., icon=.., index=.., keyEffect=..}, ... }

-- Spells that match "venom" but aren't actually a weapon coating you'd
-- select into a slot - a damage spell, a proc buff, a shapeshift form,
-- the "are venoms applied" status buff, and the cleanse utility spell
-- (now bound to middle-click on the apply button instead) all happen to
-- have "venom" in the name without being a coating.
local VENOM_EXCLUDE = {
	["venom bolt"] = true,
	["venomtip poison"] = true,
	["venom fang"] = true,
	["venomwing form"] = true,
	["envenomed weapons"] = true,
	["remove venoms"] = true,
	["antivenom"] = true,
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

	local byName = {}
	local order = {}
	for i = 1, 1024 do
		local name = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name:lower():find("venom") and not VENOM_EXCLUDE[name:lower()] then

			local texture
			if type(GetSpellTexture) == "function" then
				texture = GetSpellTexture(i, BOOKTYPE_SPELL)
			end
			if not byName[name] then
				order[#order + 1] = name
			end
			byName[name] = {
				name = name,
				icon = texture or "Interface\\Icons\\INV_Misc_QuestionMark",
				index = i,
				keyEffect = ExtractKeyEffect(GetSpellTooltipText(i)),
			}
		end
	end
	for _, name in ipairs(order) do
		table.insert(knownVenoms, byName[name])
	end
end

--------------------------------------------------------------------------------
-- Frame setup
--------------------------------------------------------------------------------

local anchorFrame = CreateFrame("Frame", "VenomBarAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local bar = CreateFrame("Frame", "VenomBarFrame", UIParent)
bar:SetSize(200, 36)
bar:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
bar:SetClampedToScreen(true)
bar:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
bar:SetBackdropColor(0, 0, 0, 0)
bar:SetBackdropBorderColor(1, 0.82, 0, 0)

local dragHint = CreateFrame("Frame", nil, UIParent)
dragHint:SetSize(110, 22)
dragHint:SetPoint("BOTTOM", bar, "TOP", 0, 8)
dragHint:SetMovable(true)
dragHint:SetClampedToScreen(true)
dragHint:RegisterForDrag("LeftButton")
dragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
dragHint:SetBackdropColor(0, 0, 0, 0.8)
dragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local dragHintText = dragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dragHintText:SetAllPoints()
dragHintText:SetJustifyH("CENTER")
dragHintText:SetJustifyV("MIDDLE")
dragHintText:SetText("Drag Me")
dragHintText:SetTextColor(1, 0.82, 0)
dragHint:SetScript("OnDragStart", function() anchorFrame:StartMoving() end)
dragHint:SetScript("OnDragStop", function()
	anchorFrame:StopMovingOrSizing()
	local d = GetDB()
	d.vbPoint, _, _, d.vbX, d.vbY = anchorFrame:GetPoint()
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
castButtonBorder:SetBackdrop({
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
})
castButtonBorder:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)

local applyCycleStep = 1

local function RefreshCastIcon()
	local d = GetDB()
	local venomName = (applyCycleStep == 1) and d.vbSelected1 or d.vbSelected2
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
		local d = GetDB()
		local venomName = (applyCycleStep == 1) and d.vbSelected1 or d.vbSelected2
		self:SetAttribute("spell", venomName)
		applyCycleStep = (applyCycleStep == 1) and 2 or 1
	end
end)
castButton:SetScript("PostClick", function()
	RefreshCastIcon()
end)
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

	-- Selection glow: a soft colored halo behind the icon, using an ADD
	-- blend so it reads as a gentle glow rather than a flat colored
	-- square sitting behind everything.
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
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 6,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	badgeBG:SetBackdropBorderColor(0, 0, 0, 1)
	badgeBG:Hide()
	b.badgeBG = badgeBG

	local badge = badgeBG:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	badge:SetPoint("CENTER", 0, 0)
	badge:Hide()
	b.badge = badge

	b:SetScript("OnClick", function(self, mouseButton)
		local d = GetDB()
		if mouseButton == "LeftButton" then
			d.vbSelected1 = self.venomName
		elseif mouseButton == "RightButton" then
			d.vbSelected2 = self.venomName
		end
		VenomBarModule.RefreshSelectionVisuals()
		RefreshCastIcon()
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")

		GameTooltip:SetText(self.venomName or "")
		if self.keyEffect then
			GameTooltip:AddLine(self.keyEffect, 1, 0.82, 0, true)
		end
		GameTooltip:AddLine(" ")
		GameTooltip:AddLine("Left-click: set as selection 1", 0.8, 0.8, 0.8)
		GameTooltip:AddLine("Right-click: set as selection 2", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	venomButtons[i] = b
	return b
end

local SELECTED_COLOR_1 = { 1, 0.82, 0 }    -- gold, matches the "1" badge
local SELECTED_COLOR_2 = { 0.3, 0.75, 1 }  -- cyan, matches the "2" badge

function VenomBarModule.RefreshSelectionVisuals()
	local d = GetDB()
	for _, b in ipairs(venomButtons) do
		if b.venomName and b.venomName == d.vbSelected1 then
			local c = SELECTED_COLOR_1
			b.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			b.glow:SetVertexColor(c[1], c[2], c[3], 0.8)
			b.badgeBG:SetBackdropColor(c[1], c[2], c[3], 1)
			b.badgeBG:Show()
			b.badge:SetText("1")
			b.badge:SetTextColor(0, 0, 0)
			b.badge:Show()
		elseif b.venomName and b.venomName == d.vbSelected2 then
			local c = SELECTED_COLOR_2
			b.border:SetBackdropBorderColor(c[1], c[2], c[3], 1)
			b.glow:SetVertexColor(c[1], c[2], c[3], 0.8)
			b.badgeBG:SetBackdropColor(c[1], c[2], c[3], 1)
			b.badgeBG:Show()
			b.badge:SetText("2")
			b.badge:SetTextColor(0, 0, 0)
			b.badge:Show()
		else
			b.border:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
			b.glow:SetVertexColor(1, 1, 1, 0)
			b.badgeBG:Hide()
			b.badge:Hide()
		end
	end
end

--------------------------------------------------------------------------------
-- Warnings
--------------------------------------------------------------------------------

local function IsBuffActive(buffName)
	for i = 1, 40 do
		local name = UnitBuff("player", i)
		if not name then break end
		if name == buffName then return true end
	end
	return false
end

local function IsPheromoneActive()
	for i = 1, 40 do
		local name = UnitBuff("player", i)
		if not name then break end
		if name:lower():find("pheromone") then return true end
	end
	return false
end

local function CountActiveKnownVenoms()
	local count = 0
	for _, v in ipairs(knownVenoms) do
		if IsBuffActive(v.name) then count = count + 1 end
	end
	return count
end

local warnAnchor = CreateFrame("Frame", "VenomBarWarnTextAnchor", UIParent)
warnAnchor:SetSize(1, 1)
warnAnchor:SetMovable(true)
warnAnchor:SetClampedToScreen(true)

local warnTextFrame = CreateFrame("Frame", "VenomBarWarnTextFrame", UIParent)
warnTextFrame:SetSize(500, 60)
warnTextFrame:SetPoint("TOP", warnAnchor, "TOP", 0, 0)
warnTextFrame:Hide()

local WARN_TEXT_OFFSETS = {
	{ 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
	{ 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}
local warnTextShadows = {}
for i = 1, #WARN_TEXT_OFFSETS do

	local fs = warnTextFrame:CreateFontString(nil, "ARTWORK")
	fs:SetJustifyH("CENTER")
	warnTextShadows[i] = fs
end
local warnText = warnTextFrame:CreateFontString(nil, "OVERLAY")
warnText:SetPoint("CENTER")
warnText:SetJustifyH("CENTER")

local refreshRetryFrame = CreateFrame("Frame")
local refreshRetryElapsed = 0
local refreshRetryPending = false

local function RefreshWarnTextStyle()
	local d = GetDB()
	local size = d.warnTextSize
	local c = d.warnTextColor
	local bc = d.warnTextBorderColor
	local thickness = d.warnTextOutline -- "NONE", "OUTLINE", "THICKOUTLINE"
	local shadowCount = (thickness == "THICKOUTLINE" and 8) or (thickness == "OUTLINE" and 4) or 0

	warnText:SetFont("Fonts\\FRIZQT__.TTF", size, "")
	warnText:SetTextColor(c[1], c[2], c[3])

	for i, fs in ipairs(warnTextShadows) do
		fs:SetFont("Fonts\\FRIZQT__.TTF", size, "")
		fs:SetTextColor(bc[1], bc[2], bc[3])
		fs:ClearAllPoints()
		if i <= shadowCount then
			local off = WARN_TEXT_OFFSETS[i]
			fs:SetPoint("CENTER", off[1], off[2])
			fs:Show()
		else
			fs:Hide()
		end
	end

	local currentText = warnText:GetText()
	if currentText then
		warnText:SetText(currentText)
		for _, fs in ipairs(warnTextShadows) do
			if fs:IsShown() then fs:SetText(currentText) end
		end
	end

	if not refreshRetryPending then
		refreshRetryPending = true
		refreshRetryElapsed = 0
		refreshRetryFrame:SetScript("OnUpdate", function(self, elapsed)
			refreshRetryElapsed = refreshRetryElapsed + elapsed
			if refreshRetryElapsed >= 0.15 then
				refreshRetryPending = false
				self:SetScript("OnUpdate", nil)
				local d2 = GetDB()
				warnText:SetFont("Fonts\\FRIZQT__.TTF", d2.warnTextSize, "")
				warnText:SetTextColor(d2.warnTextColor[1], d2.warnTextColor[2], d2.warnTextColor[3])
				for _, fs in ipairs(warnTextShadows) do
					if fs:IsShown() then
						fs:SetFont("Fonts\\FRIZQT__.TTF", d2.warnTextSize, "")
						fs:SetTextColor(d2.warnTextBorderColor[1], d2.warnTextBorderColor[2], d2.warnTextBorderColor[3])
					end
				end
				local t = warnText:GetText()
				if t then
					warnText:SetText(t)
					for _, fs in ipairs(warnTextShadows) do
						if fs:IsShown() then fs:SetText(t) end
					end
				end
			end
		end)
	end
end
RefreshWarnTextStyle()

local function SetWarnText(text)
	warnText:SetText(text)
	for _, fs in ipairs(warnTextShadows) do
		if fs:IsShown() then fs:SetText(text) end
	end
end

-- Drag handle, same pattern as the tracker/bar - only shown+interactive
-- while unlocked.
local warnDragHint = CreateFrame("Frame", nil, UIParent)
warnDragHint:SetSize(110, 22)
warnDragHint:SetPoint("BOTTOM", warnTextFrame, "TOP", 0, 8)
warnDragHint:SetMovable(true)
warnDragHint:SetClampedToScreen(true)
warnDragHint:RegisterForDrag("LeftButton")
warnDragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
warnDragHint:SetBackdropColor(0, 0, 0, 0.8)
warnDragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local warnDragHintText = warnDragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
warnDragHintText:SetAllPoints()
warnDragHintText:SetJustifyH("CENTER")
warnDragHintText:SetJustifyV("MIDDLE")
warnDragHintText:SetText("Drag Me")
warnDragHintText:SetTextColor(1, 0.82, 0)
warnDragHint:SetScript("OnDragStart", function() warnAnchor:StartMoving() end)
warnDragHint:SetScript("OnDragStop", function()
	warnAnchor:StopMovingOrSizing()
	local d = GetDB()
	d.warnTextPoint, _, _, d.warnTextX, d.warnTextY = warnAnchor:GetPoint()
end)
warnDragHint:Hide()


local function ApplyWarnTextLockVisual()
	local d = GetDB()
	local unlocked = not d.locked
	warnDragHint:EnableMouse(unlocked)
	warnDragHint:SetShown(unlocked)
	if unlocked then
		SetWarnText(warnText:GetText() or "WARNING TEXT PREVIEW")
		warnTextFrame:Show()
	elseif not warnTextFrame.hasRealContent then
		warnTextFrame:Hide()
	end
end


local warnIconFrame = CreateFrame("Frame", "VenomBarWarnIconFrame", UIParent)
warnIconFrame:SetSize(120, 36)
warnIconFrame:SetPoint("TOP", warnTextFrame, "BOTTOM", 0, -6)

local function CreateWarnIcon(iconPath)
	local f = CreateFrame("Frame", nil, warnIconFrame)
	f:SetSize(32, 32)
	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexture(iconPath)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.tex = tex
	local border = CreateFrame("Frame", nil, f)
	border:SetPoint("TOPLEFT", -2, 2)
	border:SetPoint("BOTTOMRIGHT", 2, -2)
	border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
	border:SetBackdropBorderColor(1, 0.2, 0.2, 1)
	f:Hide()
	return f
end


local warnIcons = {
	venom = CreateWarnIcon("Interface\\Icons\\Ability_Poisons"),
	pheromone = CreateWarnIcon("Interface\\Icons\\Spell_Nature_Regenerate"),
	envenomed = CreateWarnIcon("Interface\\Icons\\INV_Sword_04"),
}
warnIcons.venom:SetPoint("LEFT", warnIconFrame, "LEFT", 0, 0)
warnIcons.pheromone:SetPoint("LEFT", warnIcons.venom, "RIGHT", 8, 0)
warnIcons.envenomed:SetPoint("LEFT", warnIcons.pheromone, "RIGHT", 8, 0)


local function FindSpellIcon(exactName)
	if type(GetSpellTexture) ~= "function" then return nil end
	for i = 1, 1024 do
		local name = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name == exactName then
			return GetSpellTexture(i, BOOKTYPE_SPELL)
		end
	end
	return nil
end

local function RefreshWarnIcons()
	local blightIcon
	for _, v in ipairs(knownVenoms) do
		if v.name == "Blight Venom" then blightIcon = v.icon end
	end
	warnIcons.venom.tex:SetTexture(blightIcon or "Interface\\Icons\\Ability_Poisons")
	warnIcons.pheromone.tex:SetTexture(FindSpellIcon("Spider Pheromones") or "Interface\\Icons\\Spell_Nature_Regenerate")
	warnIcons.envenomed.tex:SetTexture(FindSpellIcon("Envenomed Weapons") or "Interface\\Icons\\INV_Sword_04")
end

local function PlayWarnSound()
	PlaySoundFile("Sound\\Interface\\RaidWarning.wav", "Master")
end

local warnWasActive = { venom = false, pheromone = false, envenomed = false }

local function UpdateWarnings()
	local d = GetDB()

	local venomActive = d.warnMissingVenomEnabled and #knownVenoms > 0 and CountActiveKnownVenoms() < 2
	local pheromoneActive = d.warnPheromoneEnabled and not IsPheromoneActive()
	local envenomedActive = d.warnEnvenomedEnabled and not IsBuffActive("Envenomed Weapons")

	if venomActive and not warnWasActive.venom and d.warnMissingVenomSound then PlayWarnSound() end
	if pheromoneActive and not warnWasActive.pheromone and d.warnPheromoneSound then PlayWarnSound() end
	if envenomedActive and not warnWasActive.envenomed and d.warnEnvenomedSound then PlayWarnSound() end
	warnWasActive.venom, warnWasActive.pheromone, warnWasActive.envenomed = venomActive, pheromoneActive, envenomedActive

	warnIcons.venom:SetShown(venomActive and d.warnMissingVenomIcon)
	warnIcons.pheromone:SetShown(pheromoneActive and d.warnPheromoneIcon)
	warnIcons.envenomed:SetShown(envenomedActive and d.warnEnvenomedIcon)

	local lines = {}
	if venomActive and d.warnMissingVenomText then lines[#lines + 1] = "MISSING VENOM" end
	if pheromoneActive and d.warnPheromoneText then lines[#lines + 1] = "NO PHEROMONE ACTIVE" end
	if envenomedActive and d.warnEnvenomedText then lines[#lines + 1] = "WEAPONS NOT ENVENOMED" end
	if #lines > 0 then
		SetWarnText(table.concat(lines, "\n"))
		warnTextFrame.hasRealContent = true
		warnTextFrame:Show()
	else
		warnTextFrame.hasRealContent = false
		if d.locked then warnTextFrame:Hide() end
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

	local d = GetDB()
	local size = d.vbIconSize
	local spacing = d.vbSpacing
	local growth = d.vbGrowth or "RIGHT"
	local vertical = (growth == "UP" or growth == "DOWN")
	local info = GROWTH_INFO[growth] or GROWTH_INFO.RIGHT

	bar:ClearAllPoints()
	bar:SetPoint(info.point, anchorFrame, info.relPoint, 0, 0)

	toggleButton:ClearAllPoints()
	toggleButton:SetPoint(info.point, bar, info.point, 0, 0)
	toggleButton:SetSize(vertical and 20 or 16, vertical and 16 or 20)

	-- Helper: anchor `frame` just past `anchorTo` in the growth
	-- direction, with the given gap.
	local function AnchorAfter(frame, anchorTo, gap)
		frame:ClearAllPoints()
		if growth == "LEFT" then
			frame:SetPoint("RIGHT", anchorTo, "LEFT", -gap, 0)
		elseif growth == "UP" then
			frame:SetPoint("BOTTOM", anchorTo, "TOP", 0, gap)
		elseif growth == "DOWN" then
			frame:SetPoint("TOP", anchorTo, "BOTTOM", 0, -gap)
		else
			frame:SetPoint("LEFT", anchorTo, "RIGHT", gap, 0)
		end
	end

	if d.vbMinimized then
		emptyLabel:Hide()
		for _, b in ipairs(venomButtons) do b:Hide() end
		AnchorAfter(castButton, toggleButton, 4)
		castButton:SetSize(size, size)
		castButton:Show()
		toggleButton:SetText(info.minArrow)
		if vertical then
			bar:SetSize(size, size + 4 + 16)
		else
			bar:SetSize(size + 4 + 16, size)
		end
	elseif #knownVenoms == 0 then
		castButton:Hide()
		for _, b in ipairs(venomButtons) do b:Hide() end
		emptyLabel:Show()
		AnchorAfter(emptyLabel, toggleButton, 6)
		toggleButton:SetText(info.expArrow)
		if vertical then
			bar:SetSize(math.max(20, emptyLabel:GetStringWidth()), 20 + 6 + 16)
		else
			bar:SetSize(emptyLabel:GetStringWidth() + 6 + 16 + 4, 20)
		end
	else
		emptyLabel:Hide()
		castButton:Hide() -- still receives the keybind click while hidden - Hide() doesn't block scripted :Click() calls
		for i, v in ipairs(knownVenoms) do
			local b = venomButtons[i] or CreateVenomButton(i)
			b.venomName = v.name
			b.spellIndex = v.index
			b.keyEffect = v.keyEffect
			b.icon:SetTexture(v.icon)
			b:SetSize(size, size)
			if i == 1 then
				AnchorAfter(b, toggleButton, spacing)
			else
				AnchorAfter(b, venomButtons[i - 1], spacing)
			end
			b:Show()
		end
		for i = #knownVenoms + 1, #venomButtons do
			venomButtons[i]:Hide()
		end
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
	local d = GetDB()
	d.vbMinimized = not d.vbMinimized
	RelayoutBar()
end)

--------------------------------------------------------------------------------
-- Lock state
--------------------------------------------------------------------------------

local lockPollElapsed = 0
local lastKnownLocked = nil
bar:SetScript("OnUpdate", function(self, elapsed)
	lockPollElapsed = lockPollElapsed + elapsed
	if lockPollElapsed < 0.5 then return end
	lockPollElapsed = 0
	local d = GetDB()
	if d.locked ~= lastKnownLocked then
		lastKnownLocked = d.locked
		local unlocked = not d.locked
		dragHint:EnableMouse(unlocked)
		dragHint:SetShown(unlocked)
		bar:SetBackdropColor(0, 0, 0, unlocked and 0.25 or 0)
		bar:SetBackdropBorderColor(1, 0.82, 0, unlocked and 0.9 or 0)
		ApplyWarnTextLockVisual()
	end

	UpdateWarnings()
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD") -- unlike PLAYER_LOGIN, this fires on every /reload too, not just first login
events:RegisterEvent("SPELLS_CHANGED")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("PLAYER_REGEN_ENABLED") -- leaving combat - retries any relayout that got deferred while locked down
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		local d = GetDB()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.vbPoint, UIParent, d.vbPoint, d.vbX, d.vbY)
		warnAnchor:ClearAllPoints()
		warnAnchor:SetPoint(d.warnTextPoint, UIParent, d.warnTextPoint, d.warnTextX, d.warnTextY)
	elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
		ScanVenoms()
		RefreshWarnIcons()
		RelayoutBar()
		UpdateWarnings()
	elseif event == "UNIT_AURA" then
		if arg1 == "player" then UpdateWarnings() end
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

function VenomBarModule.BuildOptionsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers)
	local sc = RegisterTab("venombar", "Venom Bar", GetVenomBarTabIcon())
	local L = CreateLayoutHelpers(sc)

	L.Note("Shows your known Venom spells (scanned from your spellbook, so new ones show up automatically). Left-click selects slot 1, right-click selects slot 2. Lock state is shared with the tracker's Lock setting on the General tab.")
	L.Section("Layout")
	L.Slider("Icon size", "vbIconSize", 16, 48, 1, function() RelayoutBar() end)
	L.Slider("Icon spacing", "vbSpacing", -8, 16, 1, function() RelayoutBar() end)

	L.Dropdown("Growth direction", "vbGrowth", {
		{ value = "RIGHT", label = "Right" },
		{ value = "LEFT", label = "Left" },
		{ value = "UP", label = "Up" },
		{ value = "DOWN", label = "Down" },
	}, function() RelayoutBar() end)

	local minimizeCheck = L.Checkbox("Minimized", "vbMinimized", "Collapse the bar to a single button that applies your selections in sequence when clicked.", 0)
	L.AdvanceY(24 + 6)
	minimizeCheck:SetScript("OnClick", function(self)
		GetDB().vbMinimized = self:GetChecked() and true or false
		RelayoutBar()
	end)

	L.Section("Selected Venoms")
	local sel1Label = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	L.PlaceLeft(sel1Label, 2)
	sel1Label:SetTextColor(1, 0.82, 0)
	L.AdvanceY(16)
	local sel2Label = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	L.PlaceLeft(sel2Label, 2)
	sel2Label:SetTextColor(0.3, 0.75, 1)
	L.AdvanceY(16)

	local function RefreshSelectionLabels()
		local d = GetDB()
		sel1Label:SetText("Selection 1: " .. (d.vbSelected1 or "|cff888888none|r"))
		sel2Label:SetText("Selection 2: " .. (d.vbSelected2 or "|cff888888none|r"))
	end
	RefreshSelectionLabels()
	table.insert(optionsRefreshers, RefreshSelectionLabels)

	local rescanBtn = L.Button("Rescan Spellbook", function()
		ScanVenoms()
		RefreshWarnIcons()
		RelayoutBar()
		RefreshSelectionLabels()
	end)

	sc:SetHeight(-L.GetY() + 20)
end

function VenomBarModule.BuildWarningsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers, CreateSubTabPager)
	local sc = RegisterTab("warnings", "Warnings", "Interface\\GossipFrame\\AvailableQuestIcon")
	local L = CreateLayoutHelpers(sc)

	L.Note("Generic alerts, each shown as a small icon and/or big screen-center text - pick whichever combination actually catches your eye. All checked once every half-second, plus immediately on any of your own aura changes.")

	local subs, SelectSub = CreateSubTabPager(sc, {
		{ key = "text", label = "Text Appearance" },
		{ key = "venom", label = "Missing Venom" },
		{ key = "pheromone", label = "Missing Pheromone" },
		{ key = "envenomed", label = "Envenomed Weapons" },
	}, L.GetY())

	do
		local L2 = CreateLayoutHelpers(subs.text)
		L2.Note("Applies to all three warnings' big text - they share one style, just different lines. Drag the \"Drag Me\" handle above it (visible while unlocked, same Lock setting as the tracker) to reposition it.", 40)
		L2.ColorSwatch("Text color:", "warnTextColor", function() RefreshWarnTextStyle() end)
		L2.ColorSwatch("Border color:", "warnTextBorderColor", function() RefreshWarnTextStyle() end)
		L2.Slider("Font size", "warnTextSize", 12, 48, 1, function() RefreshWarnTextStyle() end)

		L2.Dropdown("Border", "warnTextOutline", {
			{ value = "NONE", label = "None" },
			{ value = "OUTLINE", label = "Outline" },
			{ value = "THICKOUTLINE", label = "Thick" },
		}, function() RefreshWarnTextStyle() end)

		local previewBtn
		previewBtn = L2.Button("Preview Text Style", function()
			SetWarnText("SAMPLE WARNING TEXT")
			warnTextFrame.hasRealContent = true
			warnTextFrame:Show()
			if previewBtn.hideTimer then previewBtn.hideTimer:SetScript("OnUpdate", nil) end
			local elapsed = 0
			local hideFrame = CreateFrame("Frame")
			hideFrame:SetScript("OnUpdate", function(self, e)
				elapsed = elapsed + e
				if elapsed > 5 then
					warnTextFrame.hasRealContent = false
					if GetDB().locked then warnTextFrame:Hide() end
					self:SetScript("OnUpdate", nil)
				end
			end)
			previewBtn.hideTimer = hideFrame
		end)
		subs.text:SetHeight(-L2.GetY() + 20)
	end

	local function WarningSubTab(content, note, prefix)
		local L2 = CreateLayoutHelpers(content)
		L2.Note(note, 40)
		L2.CheckboxRow("Enable", prefix .. "Enabled", "Turn this warning on or off entirely.")
		L2.CheckboxPair(
			"Icon", prefix .. "Icon", "Show a small icon near the top of the screen while this is active.",
			"Text", prefix .. "Text", "Show text near the top of the screen while this is active - size, color, and border are all set in Text Appearance."
		)
		L2.CheckboxRow("Sound", prefix .. "Sound", "Play a sound the moment this warning starts (not while it continues).")
		content:SetHeight(-L2.GetY() + 20)
	end

	WarningSubTab(subs.venom, "Warns if fewer than 2 of your known venoms are currently applied.", "warnMissingVenom")
	WarningSubTab(subs.pheromone, "Warns if no buff with \"Pheromone\" in its name is currently active.", "warnPheromone")
	WarningSubTab(subs.envenomed, "Warns if the \"Envenomed Weapons\" buff is not currently active.", "warnEnvenomed")

	SelectSub("text")
end
