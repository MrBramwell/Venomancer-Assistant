--[[
	Buff Tracking tab - buff-uptime tracking that isn't tied to any one
	form: the Tome of Ahn'kahet proc icon, and Buff Alerts (renamed from
	"Warnings" - it only ever tracked buff uptime, so the new name says
	what it actually does).
]]

local Core = VenomancerAssistant
local FALLBACK_ICON = Core.FALLBACK_ICON

--------------------------------------------------------------------------------
-- Tome of Ahn'kahet - single buff-icon tracker, own drag/lock/scale.
--------------------------------------------------------------------------------

local tomeDB = Core.RegisterModuleDB("tome", {
	point = "CENTER", x = -220, y = -220,
	locked = false,
	enabled = true,
	scale = 1.0,
	iconSize = 36,
	hideOutOfCombat = false,
	showCountdownText = true,
	colorActive = { 0.3, 0.85, 0.9 },
	colorReady = { 0.5, 0.5, 0.55 },
})

local TOME_BUFF_NAME = "Tome of Ahn'kahet"
local TOME_FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Book_09"

local tomeAnchor = CreateFrame("Frame", "VATomeAnchor", UIParent)
tomeAnchor:SetSize(1, 1)
tomeAnchor:SetMovable(true)
tomeAnchor:SetClampedToScreen(true)

local tomeFrame = CreateFrame("Button", "VATomeFrame", UIParent)
tomeFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel (DIALOG), so it's never hidden behind it
tomeFrame:SetPoint("CENTER", tomeAnchor, "CENTER", 0, 0)
tomeFrame:SetClampedToScreen(true)

local tomeIcon = tomeFrame:CreateTexture(nil, "ARTWORK")
tomeIcon:SetAllPoints()
tomeIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
tomeIcon:SetTexture(TOME_FALLBACK_ICON)

local tomeBorder = CreateFrame("Frame", nil, tomeFrame)
tomeBorder:SetPoint("TOPLEFT", -2, 2)
tomeBorder:SetPoint("BOTTOMRIGHT", 2, -2)
tomeBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
tomeBorder:SetBackdropBorderColor(0.5, 0.5, 0.55, 1)

local tomeCooldown = CreateFrame("Cooldown", "VATomeFrameCooldown", tomeFrame, "CooldownFrameTemplate")
tomeCooldown:SetAllPoints()
if tomeCooldown.SetDrawBling then tomeCooldown:SetDrawBling(false) end

local tomeTimeText = tomeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tomeTimeText:SetPoint("BOTTOM", tomeFrame, "BOTTOM", 0, 2)
do
	local font, height = tomeTimeText:GetFont()
	if font then tomeTimeText:SetFont(font, height, "OUTLINE") end
end

tomeFrame:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(TOME_BUFF_NAME)
	GameTooltip:Show()
end)
tomeFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

local tomeDragHint = CreateFrame("Frame", nil, UIParent)
tomeDragHint:SetSize(170, 20)
tomeDragHint:SetMovable(true)
tomeDragHint:SetClampedToScreen(true)
tomeDragHint:RegisterForDrag("LeftButton")
tomeDragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
tomeDragHint:SetBackdropColor(0, 0, 0, 0.8)
tomeDragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local tomeDragHintText = tomeDragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
tomeDragHintText:SetAllPoints()
tomeDragHintText:SetJustifyH("CENTER")
tomeDragHintText:SetJustifyV("MIDDLE")
tomeDragHintText:SetWordWrap(false)
tomeDragHintText:SetText("Drag: Tome of Ahn'kahet")
tomeDragHintText:SetTextColor(1, 0.82, 0)
tomeDragHint:SetPoint("BOTTOM", tomeFrame, "TOP", 0, 8)
tomeDragHint:SetScript("OnDragStart", function() tomeAnchor:StartMoving() end)
tomeDragHint:SetScript("OnDragStop", function()
	tomeAnchor:StopMovingOrSizing()
	local d = tomeDB()
	d.point, _, _, d.x, d.y = tomeAnchor:GetPoint()
end)
tomeDragHint:Hide()

local function ApplyTomeLockVisual()
	local d = tomeDB()
	local unlocked = not d.locked
	tomeDragHint:EnableMouse(unlocked)
	tomeDragHint:SetShown(unlocked)
end

local function GetTomeBuff()
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime = UnitBuff("player", i)
		if not name then break end
		if name == TOME_BUFF_NAME then return true, icon, duration, expirationTime end
	end
	return false
end

local function RefreshTome()
	local d = tomeDB()
	tomeFrame:SetScale(d.scale)
	tomeFrame:SetSize(d.iconSize, d.iconSize)

	if not d.enabled then
		tomeFrame:Hide()
		return
	end

	local active, icon, duration, expirationTime = GetTomeBuff()

	if not active then
		tomeCooldown:Clear()
		tomeTimeText:SetText("")
		if d.locked then
			-- Only shown while the buff is actually active, per request -
			-- no idle/greyed-out icon sitting on screen the rest of the time.
			tomeFrame:Hide()
		else
			-- Stay visible while unlocked so there's still something to
			-- drag/position - shows in its "ready" color for that purpose only.
			tomeIcon:SetTexture(icon or TOME_FALLBACK_ICON)
			tomeIcon:SetDesaturated(true)
			tomeBorder:SetBackdropBorderColor(d.colorReady[1], d.colorReady[2], d.colorReady[3], 1)
			tomeFrame:Show()
		end
		return
	end

	if d.hideOutOfCombat and d.locked and not UnitAffectingCombat("player") then
		tomeCooldown:Clear()
		tomeTimeText:SetText("")
		tomeFrame:Hide()
		return
	end

	tomeIcon:SetTexture(icon or TOME_FALLBACK_ICON)
	tomeIcon:SetDesaturated(false)
	tomeBorder:SetBackdropBorderColor(d.colorActive[1], d.colorActive[2], d.colorActive[3], 1)
	if duration and duration > 0 and expirationTime then
		tomeCooldown:SetReverse(true)
		tomeCooldown:SetCooldown(expirationTime - duration, duration)
		if d.showCountdownText then
			local remain = expirationTime - GetTime()
			tomeTimeText:SetText(remain > 0 and string.format("%.0f", remain) or "")
		else
			tomeTimeText:SetText("")
		end
	else
		tomeCooldown:Clear()
		tomeTimeText:SetText("")
	end
	tomeFrame:Show()
end

Core.RegisterLockable({ dbFn = tomeDB, apply = function() ApplyTomeLockVisual(); RefreshTome() end })

local tomeTicker = CreateFrame("Frame")
local tomeElapsed = 0
tomeTicker:SetScript("OnUpdate", function(self, e)
	tomeElapsed = tomeElapsed + e
	if tomeElapsed >= 0.2 then tomeElapsed = 0; RefreshTome() end
end)

local tomeEvents = CreateFrame("Frame")
tomeEvents:RegisterEvent("ADDON_LOADED")
tomeEvents:RegisterEvent("UNIT_AURA")
tomeEvents:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= Core.ADDON_NAME then return end
		local d = tomeDB()
		tomeAnchor:ClearAllPoints()
		tomeAnchor:SetPoint(d.point, UIParent, d.point, d.x, d.y)
		ApplyTomeLockVisual()
	elseif arg1 == "player" then
		RefreshTome()
	end
end)

local function BuildTomeSubTab(container, CreateLayoutHelpers)
	local L = CreateLayoutHelpers(container, tomeDB, function() RefreshTome(); ApplyTomeLockVisual() end)
	L.CheckboxRow("Enable Tome of Ahn'kahet tracking", "enabled")
	L.CheckboxRow("Locked", "locked", "Lock/unlock this icon's position. While unlocked, drag its \"Drag Me\" handle to move it. Only shown at all while the buff is active, except while unlocked for positioning.")
	L.CheckboxRow("Hide when not in combat", "hideOutOfCombat")
	L.CheckboxRow("Show countdown text", "showCountdownText", "Turn off if you use OmniCC or a similar addon that already shows a countdown on cooldown-swipe icons - otherwise you'll get two overlapping numbers.")
	L.Slider("Scale", "scale", 0.5, 2.5, 0.05)
	L.Slider("Icon size", "iconSize", 20, 64, 1)
	L.ColorSwatch("Active color:", "colorActive")
	L.ColorSwatch("Ready color:", "colorReady")
	container:SetHeight(-L.GetY() + 20)
end

--------------------------------------------------------------------------------
-- Buff Alerts (renamed from "Warnings") - generic buff-uptime alerts,
-- each shown as a small icon and/or big screen-center text.
--------------------------------------------------------------------------------

local alertDB = Core.RegisterModuleDB("buffAlerts", {
	locked = false,

	missingVenomEnabled = true, missingVenomIcon = true, missingVenomText = false, missingVenomSound = true,
	pheromoneEnabled = true, pheromoneIcon = true, pheromoneText = false, pheromoneSound = false,
	envenomedEnabled = true, envenomedIcon = true, envenomedText = false, envenomedSound = false,

	textColor = { 1, 0.2, 0.2 },
	textBorderColor = { 0, 0, 0 },
	textSize = 26,
	textOutline = "OUTLINE",
	textPoint = "TOP", textX = 0, textY = -160,
})

local function IsBuffActive(buffName)
	for i = 1, 40 do
		local name = UnitBuff("player", i)
		if not name then break end
		if name == buffName then return true end
	end
	return false
end

-- Pheromone buff IDs, once known - populate this and PHEROMONE_NAMES
-- below stops being needed as the primary check. Left empty for now:
-- I don't have confirmed spell IDs for these buffs (only their names,
-- from prior context) - drop them in here if you have them and this
-- switches straight to ID-based checking.
local PHEROMONE_BUFF_IDS = {
	-- [800xxx] = true,
}
local PHEROMONE_NAMES = {
	["Spider Pheromones"] = true,
	["Beetle Pheromones"] = true,
}

local function IsPheromoneActive()
	for i = 1, 40 do
		local name, _, _, _, _, _, _, _, _, _, spellId = UnitBuff("player", i)
		if not name then break end
		if (spellId and PHEROMONE_BUFF_IDS[spellId]) or PHEROMONE_NAMES[name] then
			return true
		end
	end
	return false
end

local function CountActiveKnownVenoms()
	local count = 0
	local venoms = VenomBarModule and VenomBarModule.GetKnownVenoms and VenomBarModule.GetKnownVenoms() or {}
	for _, v in ipairs(venoms) do
		if IsBuffActive(v.name) then count = count + 1 end
	end
	return count
end

local warnAnchor = CreateFrame("Frame", "VABuffAlertsTextAnchor", UIParent)
warnAnchor:SetSize(1, 1)
warnAnchor:SetMovable(true)
warnAnchor:SetClampedToScreen(true)

local warnTextFrame = CreateFrame("Frame", "VABuffAlertsTextFrame", UIParent)
warnTextFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel (DIALOG), so it's never hidden behind it
warnTextFrame:SetSize(500, 60)
warnTextFrame:SetPoint("TOP", warnAnchor, "TOP", 0, 0)
warnTextFrame:Hide()

local WARN_TEXT_OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local warnTextShadows = {}
for i = 1, #WARN_TEXT_OFFSETS do
	local fs = warnTextFrame:CreateFontString(nil, "ARTWORK")
	fs:SetJustifyH("CENTER")
	warnTextShadows[i] = fs
end
local warnText = warnTextFrame:CreateFontString(nil, "OVERLAY")
warnText:SetPoint("CENTER")
warnText:SetJustifyH("CENTER")

local function RefreshWarnTextStyle()
	local d = alertDB()
	local size, c, bc = d.textSize, d.textColor, d.textBorderColor
	local thickness = d.textOutline
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
		for _, fs in ipairs(warnTextShadows) do if fs:IsShown() then fs:SetText(currentText) end end
	end
end
RefreshWarnTextStyle()

local function SetWarnText(text)
	warnText:SetText(text)
	for _, fs in ipairs(warnTextShadows) do if fs:IsShown() then fs:SetText(text) end end
end

local warnDragHint = CreateFrame("Frame", nil, UIParent)
warnDragHint:SetSize(170, 20)
warnDragHint:SetPoint("BOTTOM", warnTextFrame, "TOP", 0, 8)
warnDragHint:SetMovable(true)
warnDragHint:SetClampedToScreen(true)
warnDragHint:RegisterForDrag("LeftButton")
warnDragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
warnDragHint:SetBackdropColor(0, 0, 0, 0.8)
warnDragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local warnDragHintText = warnDragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
warnDragHintText:SetAllPoints()
warnDragHintText:SetJustifyH("CENTER")
warnDragHintText:SetJustifyV("MIDDLE")
warnDragHintText:SetWordWrap(false)
warnDragHintText:SetText("Drag: Buff Alerts")
warnDragHintText:SetTextColor(1, 0.82, 0)
warnDragHint:SetScript("OnDragStart", function() warnAnchor:StartMoving() end)
warnDragHint:SetScript("OnDragStop", function()
	warnAnchor:StopMovingOrSizing()
	local d = alertDB()
	d.textPoint, _, _, d.textX, d.textY = warnAnchor:GetPoint()
end)
warnDragHint:Hide()

local function ApplyWarnTextLockVisual()
	local d = alertDB()
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

local warnIconFrame = CreateFrame("Frame", "VABuffAlertsIconFrame", UIParent)
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
		if name == exactName then return GetSpellTexture(i, BOOKTYPE_SPELL) end
	end
	return nil
end

local function RefreshWarnIcons()
	local blightIcon
	local venoms = VenomBarModule and VenomBarModule.GetKnownVenoms and VenomBarModule.GetKnownVenoms() or {}
	for _, v in ipairs(venoms) do if v.name == "Blight Venom" then blightIcon = v.icon end end
	warnIcons.venom.tex:SetTexture(blightIcon or "Interface\\Icons\\Ability_Poisons")
	warnIcons.pheromone.tex:SetTexture(FindSpellIcon("Spider Pheromones") or "Interface\\Icons\\Spell_Nature_Regenerate")
	warnIcons.envenomed.tex:SetTexture(FindSpellIcon("Envenomed Weapons") or "Interface\\Icons\\INV_Sword_04")
end

local function PlayWarnSound() PlaySoundFile("Sound\\Interface\\RaidWarning.wav", "Master") end

local warnWasActive = { venom = false, pheromone = false, envenomed = false }
local alertSettleUntil = 0 -- see PLAYER_ENTERING_WORLD handling below

local function UpdateWarnings()
	-- Blocks every caller (including the 0.5s ticker) during the
	-- post-zone settle window - UnitBuff can transiently read "nothing"
	-- right as you zone in, which would otherwise look like a fresh
	-- alert activation the moment the real read comes through.
	if GetTime() < alertSettleUntil then return end
	local d = alertDB()
	local venoms = VenomBarModule and VenomBarModule.GetKnownVenoms and VenomBarModule.GetKnownVenoms() or {}

	local venomActive = d.missingVenomEnabled and #venoms > 0 and CountActiveKnownVenoms() < 2
	local pheromoneActive = d.pheromoneEnabled and not IsPheromoneActive()
	local envenomedActive = d.envenomedEnabled and not IsBuffActive("Envenomed Weapons")

	if venomActive and not warnWasActive.venom and d.missingVenomSound then PlayWarnSound() end
	if pheromoneActive and not warnWasActive.pheromone and d.pheromoneSound then PlayWarnSound() end
	if envenomedActive and not warnWasActive.envenomed and d.envenomedSound then PlayWarnSound() end
	warnWasActive.venom, warnWasActive.pheromone, warnWasActive.envenomed = venomActive, pheromoneActive, envenomedActive

	warnIcons.venom:SetShown(venomActive and d.missingVenomIcon)
	warnIcons.pheromone:SetShown(pheromoneActive and d.pheromoneIcon)
	warnIcons.envenomed:SetShown(envenomedActive and d.envenomedIcon)

	local lines = {}
	if venomActive and d.missingVenomText then lines[#lines + 1] = "MISSING VENOM" end
	if pheromoneActive and d.pheromoneText then lines[#lines + 1] = "NO PHEROMONE ACTIVE" end
	if envenomedActive and d.envenomedText then lines[#lines + 1] = "WEAPONS NOT ENVENOMED" end
	if #lines > 0 then
		SetWarnText(table.concat(lines, "\n"))
		warnTextFrame.hasRealContent = true
		warnTextFrame:Show()
	else
		warnTextFrame.hasRealContent = false
		if d.locked then warnTextFrame:Hide() end
	end
end

Core.RegisterLockable({ dbFn = alertDB, apply = function() ApplyWarnTextLockVisual(); UpdateWarnings() end })

local alertTicker = CreateFrame("Frame")
local alertElapsed = 0
alertTicker:SetScript("OnUpdate", function(self, e)
	alertElapsed = alertElapsed + e
	if alertElapsed >= 0.5 then alertElapsed = 0; UpdateWarnings() end
end)

local alertEvents = CreateFrame("Frame")
alertEvents:RegisterEvent("ADDON_LOADED")
alertEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
alertEvents:RegisterEvent("SPELLS_CHANGED")
alertEvents:RegisterEvent("UNIT_AURA")
alertEvents:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= Core.ADDON_NAME then return end
		local d = alertDB()
		warnAnchor:ClearAllPoints()
		warnAnchor:SetPoint(d.textPoint, UIParent, d.textPoint, d.textX, d.textY)
		ApplyWarnTextLockVisual()
	elseif event == "PLAYER_ENTERING_WORLD" or event == "SPELLS_CHANGED" then
		if event == "PLAYER_ENTERING_WORLD" then
			alertSettleUntil = GetTime() + 1.5
			Core.After(1.5, UpdateWarnings)
		end
		RefreshWarnIcons()
		UpdateWarnings()
	elseif event == "UNIT_AURA" then
		if arg1 == "player" then UpdateWarnings() end
	end
end)

local function BuildAlertsSubTab(container, CreateLayoutHelpers, CreateSubTabPager)
	local L = CreateLayoutHelpers(container, alertDB, UpdateWarnings)
	L.Note("Buff-uptime alerts, each shown as a small icon and/or big screen-center text. Checked every half-second, plus immediately on any of your own aura changes.")
	L.CheckboxRow("Locked", "locked", "Lock/unlock the alert text's position. While unlocked, drag its \"Drag Me\" handle to move it.", function() ApplyWarnTextLockVisual() end)

	local subs, SelectSub = CreateSubTabPager(container, {
		{ key = "text", label = "Text Appearance" },
		{ key = "venom", label = "Missing Venom" },
		{ key = "pheromone", label = "Missing Pheromone" },
		{ key = "envenomed", label = "Envenomed Weapons" },
	}, L.GetY())

	do
		local L2 = CreateLayoutHelpers(subs.text, alertDB, function() RefreshWarnTextStyle() end)
		L2.ColorSwatch("Text color:", "textColor")
		L2.ColorSwatch("Border color:", "textBorderColor")
		L2.Slider("Font size", "textSize", 12, 48, 1)
		L2.Dropdown("Border", "textOutline", {
			{ value = "NONE", label = "None" }, { value = "OUTLINE", label = "Outline" }, { value = "THICKOUTLINE", label = "Thick" },
		})
		L2.Button("Preview Text Style", function()
			SetWarnText("SAMPLE WARNING TEXT")
			warnTextFrame.hasRealContent = true
			warnTextFrame:Show()
			local elapsed = 0
			local hideFrame = CreateFrame("Frame")
			hideFrame:SetScript("OnUpdate", function(self, e)
				elapsed = elapsed + e
				if elapsed > 5 then
					warnTextFrame.hasRealContent = false
					if alertDB().locked then warnTextFrame:Hide() end
					self:SetScript("OnUpdate", nil)
				end
			end)
		end)
		subs.text:SetHeight(-L2.GetY() + 20)
	end

	local function AlertSubTab(content, note, prefix)
		local L2 = CreateLayoutHelpers(content, alertDB, UpdateWarnings)
		L2.Note(note, 40)
		L2.CheckboxRow("Enable", prefix .. "Enabled", "Turn this alert on or off entirely.")
		L2.CheckboxPair(
			"Icon", prefix .. "Icon", "Show a small icon near the top of the screen while this is active.",
			"Text", prefix .. "Text", "Show text near the top of the screen while this is active."
		)
		L2.CheckboxRow("Sound", prefix .. "Sound", "Play a sound the moment this alert starts.")
		content:SetHeight(-L2.GetY() + 20)
	end

	AlertSubTab(subs.venom, "Warns if fewer than 2 of your known venoms are currently applied.", "missingVenom")
	AlertSubTab(subs.pheromone, "Warns if no Pheromone buff is active.", "pheromone")
	AlertSubTab(subs.envenomed, "Warns if the \"Envenomed Weapons\" buff is not currently active.", "envenomed")

	SelectSub("text")
end

--------------------------------------------------------------------------------
-- Tab assembly
--------------------------------------------------------------------------------

function Core.BuildBuffTrackingTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	local sc = RegisterTab("bufftracking", "Buff Tracking", TOME_FALLBACK_ICON)

	local outer, SelectOuter = CreateSubTabPager(sc, {
		{ key = "tome", label = "Tome of Ahn'kahet" },
		{ key = "alerts", label = "Buff Alerts" },
	}, -8)

	BuildTomeSubTab(outer.tome, CreateLayoutHelpers)
	BuildAlertsSubTab(outer.alerts, CreateLayoutHelpers, CreateSubTabPager)

	SelectOuter("tome")
end
