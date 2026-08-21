--[[
	Beetle Defenses - tracks the Venomancer's Beetle Form defensive
	cooldowns/buffs: Harden, Regrow Exoskeleton, Vile Sting, Expulsion,
	and Carapace Regeneration. Lives as a sub-tab under Beetle Form.

	Can be positioned two ways (see "groupMode"):
	  - Grouped: one frame, one drag handle, abilities laid out in a row/
	    column relative to each other - the original behavior.
	  - Ungrouped: each ability gets its own independent drag handle and
	    saved position.
	Both modes share the same scale/size/color/enable settings - only the
	positioning differs.
]]

local Core = VenomancerAssistant
local FALLBACK_ICON = Core.FALLBACK_ICON

local dbFn = Core.RegisterModuleDB("beetleDefenses", {
	point = "CENTER", x = 220, y = -220,
	locked = false,
	mode = "icon", -- "icon" or "bar"
	groupMode = "grouped", -- "grouped" or "ungrouped"
	scale = 1.0,
	growth = "RIGHT",

	iconSize = 36,
	iconSpacing = 8,
	showIconTimeText = true,

	barWidth = 170,
	barHeight = 20,
	barSpacing = 5,

	hideOutOfCombat = false,

	colorBuffActive = { 0.3, 0.85, 0.3 },
	colorOnCooldown = { 0.6, 0.6, 0.65 },
	colorReady      = { 1, 0.82, 0 },

	hardenEnabled  = true,
	regrowEnabled  = true,
	vileStingEnabled = true,
	expulsionEnabled = true,
	carapaceEnabled = true,

	showSolo = true, showParty = true, showRaid = true, showBattleground = true,

	-- Multi-mob / Carapace Regeneration warning
	mobWarnEnabled = false,
	mobWarnThreshold = 3,
	mobWarnSound = true,
	colorMobWarn = { 1, 0.15, 0.15 },
})

-- Spell IDs (reference only - name-based lookups are used at runtime):
--   Harden r1: 800892 | Regrow Exoskeleton: 803197
--   Exposed Flesh (debuff): 92144 | Carapace Regeneration: 805931
local ABILITIES = {
	{ key = "harden",    enabledKey = "hardenEnabled",    name = "Harden",                 spellName = "Harden",                 fallbackIcon = "Interface\\Icons\\Ability_Defend",              hasBuff = true },
	{ key = "regrow",    enabledKey = "regrowEnabled",    name = "Regrow Exoskeleton",      spellName = "Regrow Exoskeleton",     fallbackIcon = "Interface\\Icons\\Ability_Rogue_Nervesofsteel", hasBuff = true },
	{ key = "vilesting", enabledKey = "vileStingEnabled", name = "Vile Sting",              spellName = "Vile Sting",             fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",     hasBuff = false },
	{ key = "expulsion", enabledKey = "expulsionEnabled", name = "Expulsion",               spellName = "Expulsion",              fallbackIcon = "Interface\\Icons\\Ability_Creature_Poison_06",  hasBuff = false },
	{ key = "carapace",  enabledKey = "carapaceEnabled",  name = "Carapace Regeneration",   spellName = "Carapace Regeneration",  buffName = "Carapace Regeneration", fallbackIcon = "Interface\\Icons\\Ability_Rogue_Recuperate", hasBuff = true, maxStacks = 3 },
}

local ABILITY_DEFAULT_OFFSET = {
	harden = { x = -180, y = -300 }, regrow = { x = -90, y = -300 }, vilesting = { x = 0, y = -300 },
	expulsion = { x = 90, y = -300 }, carapace = { x = 180, y = -300 },
}

local function EnabledCount()
	local d = dbFn()
	local n = 0
	for _, a in ipairs(ABILITIES) do if d[a.enabledKey] then n = n + 1 end end
	return n
end

--------------------------------------------------------------------------------
-- Frames: shared group anchor + one per-ability anchor (used only in
-- ungrouped mode, but always created so switching modes is instant).
--------------------------------------------------------------------------------

local anchorFrame = CreateFrame("Frame", "VABeetleDefensesAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local main = CreateFrame("Frame", "VABeetleDefensesFrame", UIParent)
main:SetFrameStrata("FULLSCREEN_DIALOG") -- above normal game UI; the options panel itself is set even higher
main:SetSize(200, 40)
main:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
main:SetClampedToScreen(true)
main:EnableMouse(false)

local placeholder = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
placeholder:SetPoint("LEFT", main, "LEFT", 0, 0)
placeholder:SetText("Beetle Defenses (no abilities enabled)")
placeholder:Hide()

local function CreateDragHint(width)
	local hint = CreateFrame("Frame", nil, UIParent)
	hint:SetSize(width or 170, 20)
	hint:SetMovable(true)
	hint:SetClampedToScreen(true)
	hint:RegisterForDrag("LeftButton")
	hint:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	hint:SetBackdropColor(0, 0, 0, 0.8)
	hint:SetBackdropBorderColor(1, 0.82, 0, 1)
	local text = hint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	text:SetAllPoints()
	text:SetJustifyH("CENTER")
	text:SetJustifyV("MIDDLE")
	text:SetWordWrap(false)
	text:SetTextColor(1, 0.82, 0)
	hint:Hide()
	hint.text = text
	return hint
end

local dragHint = CreateDragHint(170)
dragHint.text:SetText("Drag: Beetle Defenses")
dragHint:SetScript("OnDragStart", function() anchorFrame:StartMoving() end)
dragHint:SetScript("OnDragStop", function()
	anchorFrame:StopMovingOrSizing()
	local d = dbFn()
	d.point, _, _, d.x, d.y = anchorFrame:GetPoint()
end)

local abilityAnchors, abilityDragHints = {}, {}
for _, ability in ipairs(ABILITIES) do
	local af = CreateFrame("Frame", "VABeetleDefenses" .. ability.key .. "Anchor", UIParent)
	af:SetSize(1, 1)
	af:SetMovable(true)
	af:SetClampedToScreen(true)
	abilityAnchors[ability.key] = af

	local hint = CreateDragHint(150)
	hint.text:SetText("Drag: " .. ability.name)
	hint:SetScript("OnDragStart", function() af:StartMoving() end)
	hint:SetScript("OnDragStop", function()
		af:StopMovingOrSizing()
		local d = dbFn()
		d.abilityPositions = d.abilityPositions or {}
		local pos = d.abilityPositions[ability.key] or {}
		pos.point, _, _, pos.x, pos.y = af:GetPoint()
		d.abilityPositions[ability.key] = pos
	end)
	abilityDragHints[ability.key] = hint
end

local function ApplyLockVisual()
	local d = dbFn()
	local unlocked = not d.locked
	if d.groupMode == "ungrouped" then
		dragHint:Hide()
		for _, ability in ipairs(ABILITIES) do
			local hint = abilityDragHints[ability.key]
			local shouldShow = unlocked and d[ability.enabledKey]
			hint:EnableMouse(shouldShow)
			hint:SetShown(shouldShow)
		end
	else
		for _, hint in pairs(abilityDragHints) do hint:Hide() end
		dragHint:EnableMouse(unlocked)
		dragHint:SetShown(unlocked and EnabledCount() > 0)
	end
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local widgets = {}

local function CreateIconWidget(ability)
	local b = CreateFrame("Button", "VABeetleDefensesIcon" .. ability.key, main)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = CreateFrame("Frame", nil, b)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
	border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	b.border = border

	b.cooldown = CreateFrame("Cooldown", "VABeetleDefensesIcon" .. ability.key .. "Cooldown", b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	if b.cooldown.SetDrawBling then b.cooldown:SetDrawBling(false) end

	b.chargeText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.chargeText:SetPoint("BOTTOMRIGHT", -2, 2)

	b.timeText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	b.timeText:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 2, 2)
	do
		local font, height = b.timeText:GetFont()
		if font then b.timeText:SetFont(font, height, "OUTLINE") end
	end

	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ability.name)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	widgets[ability.key] = widgets[ability.key] or {}
	widgets[ability.key].icon = b
	return b
end

local function CreateBarWidget(ability)
	local f = CreateFrame("Frame", nil, main)
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture("Interface\\Buttons\\WHITE8x8")
	bg:SetVertexColor(0, 0, 0, 0.55)

	local border = CreateFrame("Frame", nil, f)
	border:SetAllPoints()
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	border:SetBackdropBorderColor(0.16, 0.16, 0.18, 1)

	local fill = f:CreateTexture(nil, "ARTWORK")
	fill:SetTexture("Interface\\Buttons\\WHITE8x8")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMLEFT", 1, 1)
	f.fill = fill

	local icon = f:CreateTexture(nil, "OVERLAY")
	icon:SetPoint("LEFT", 2, 0)
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon = icon

	local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("RIGHT", -4, 0)
	f.timeText = timeText

	-- Bounded on both sides (icon and timeText) rather than just anchored
	-- left, so a long ability name clips at the boundary instead of
	-- drawing straight through the time/stack text on the right.
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	label:SetPoint("RIGHT", timeText, "LEFT", -6, 0)
	label:SetJustifyH("LEFT")
	label:SetWordWrap(false)
	label:SetText(ability.name)
	f.label = label

	f:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(ability.name)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)

	widgets[ability.key] = widgets[ability.key] or {}
	widgets[ability.key].bar = f
	return f
end

for _, ability in ipairs(ABILITIES) do
	CreateIconWidget(ability)
	CreateBarWidget(ability)
end

local GROWTH_INFO = {
	RIGHT = { point = "LEFT", relPoint = "LEFT" }, LEFT = { point = "RIGHT", relPoint = "LEFT" },
	DOWN = { point = "TOP", relPoint = "LEFT" }, UP = { point = "BOTTOM", relPoint = "LEFT" },
}
local DRAG_HINT_INFO = {
	RIGHT = { hintPoint = "BOTTOMLEFT", mainPoint = "TOPLEFT", x = 0, y = 8 },
	LEFT  = { hintPoint = "BOTTOMRIGHT", mainPoint = "TOPRIGHT", x = 0, y = 8 },
	DOWN  = { hintPoint = "BOTTOMLEFT", mainPoint = "TOPLEFT", x = 0, y = 8 },
	UP    = { hintPoint = "TOPLEFT", mainPoint = "BOTTOMLEFT", x = 0, y = -8 },
}

-- Grouped: everything laid out in one row/column relative to `main`,
-- which itself carries the shared scale for all the widget children.
local function LayoutGrouped(d)
	local mode = d.mode
	local growth = d.growth or "RIGHT"
	local vertical = (growth == "UP" or growth == "DOWN")
	local info = GROWTH_INFO[growth] or GROWTH_INFO.RIGHT

	main:ClearAllPoints()
	main:SetPoint(info.point, anchorFrame, info.relPoint, 0, 0)
	main:SetScale(d.scale)

	local spacing = mode == "icon" and d.iconSpacing or d.barSpacing
	local prev, count = nil, 0
	local totalLength, maxThickness = 0, 0

	for _, ability in ipairs(ABILITIES) do
		local w = widgets[ability.key]
		w[mode == "icon" and "bar" or "icon"]:Hide()
		if d[ability.enabledKey] then
			local shown, size1, size2
			if mode == "icon" then
				shown, size1, size2 = w.icon, d.iconSize, d.iconSize
			else
				shown, size1, size2 = w.bar, d.barWidth, d.barHeight
			end
			shown:SetSize(size1, size2)
			if mode == "bar" then shown.icon:SetSize(size2 - 4, size2 - 4) end
			shown:Show()
			shown:ClearAllPoints()
			if not prev then
				shown:SetPoint(info.point, main, info.point, 0, 0)
			elseif growth == "LEFT" then
				shown:SetPoint("RIGHT", prev, "LEFT", -spacing, 0)
			elseif growth == "UP" then
				shown:SetPoint("BOTTOM", prev, "TOP", 0, spacing)
			elseif growth == "DOWN" then
				shown:SetPoint("TOP", prev, "BOTTOM", 0, -spacing)
			else
				shown:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
			end
			prev = shown
			count = count + 1
			local length = vertical and size2 or size1
			local thickness = vertical and size1 or size2
			totalLength = totalLength + length + (count > 1 and spacing or 0)
			if thickness > maxThickness then maxThickness = thickness end
		else
			w.icon:Hide(); w.bar:Hide()
		end
	end

	if count == 0 then
		placeholder:Show()
		main:SetSize(math.max(1, placeholder:GetStringWidth()), 20)
	else
		placeholder:Hide()
		if vertical then main:SetSize(maxThickness, totalLength) else main:SetSize(totalLength, maxThickness) end
	end

	local hintInfo = DRAG_HINT_INFO[growth] or DRAG_HINT_INFO.RIGHT
	dragHint:ClearAllPoints()
	dragHint:SetPoint(hintInfo.hintPoint, main, hintInfo.mainPoint, hintInfo.x, hintInfo.y)
end

-- Ungrouped: each enabled ability positioned independently at its own
-- saved anchor. Widgets stay parented to `main`, so they still inherit
-- its shared scale - only where they're anchored to changes.
local function LayoutUngrouped(d)
	local mode = d.mode
	main:SetScale(d.scale)
	main:SetSize(1, 1)
	placeholder:Hide()

	for _, ability in ipairs(ABILITIES) do
		local w = widgets[ability.key]
		w[mode == "icon" and "bar" or "icon"]:Hide()
		if d[ability.enabledKey] then
			local shown, size1, size2
			if mode == "icon" then
				shown, size1, size2 = w.icon, d.iconSize, d.iconSize
			else
				shown, size1, size2 = w.bar, d.barWidth, d.barHeight
			end
			shown:SetSize(size1, size2)
			if mode == "bar" then shown.icon:SetSize(size2 - 4, size2 - 4) end
			shown:ClearAllPoints()
			shown:SetPoint("CENTER", abilityAnchors[ability.key], "CENTER", 0, 0)
			shown:Show()

			local hint = abilityDragHints[ability.key]
			hint:ClearAllPoints()
			hint:SetPoint("BOTTOM", shown, "TOP", 0, 8)
		else
			w.icon:Hide(); w.bar:Hide()
		end
	end
end

local function LayoutWidgets()
	local d = dbFn()
	if d.groupMode == "ungrouped" then
		LayoutUngrouped(d)
	else
		LayoutGrouped(d)
	end
	ApplyLockVisual()
end

--------------------------------------------------------------------------------
-- Ability state reading
--------------------------------------------------------------------------------

local function GetBuffTiming(buffName)
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime = UnitBuff("player", i)
		if not name then break end
		if name == buffName then return true, icon, duration, expirationTime, count end
	end
	local channelName, _, channelIcon, startTime, endTime = UnitChannelInfo("player")
	if channelName == buffName and startTime and endTime then
		local duration = (endTime - startTime) / 1000
		return true, channelIcon, duration, endTime / 1000, nil
	end
	return false
end

local previewUntil = nil

local function GetGroupContext()
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "pvp" or instanceType == "arena") then return "battleground" end
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "raid" end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "party" end
	return "solo"
end

local function GetAbilityState(ability)
	local icon = select(3, GetSpellInfo(ability.spellName)) or ability.fallbackIcon

	if previewUntil and previewUntil > GetTime() then
		local remain = previewUntil - GetTime()
		if ability.hasBuff then
			local charges = ability.maxStacks and math.min(ability.maxStacks, 2) or nil
			return (remain > 2.5 and "buff" or "cooldown"), remain, 5, charges, nil, icon
		else
			return "cooldown", remain, 5, nil, nil, icon
		end
	end

	if ability.hasBuff then
		local active, buffIcon, duration, expirationTime, buffCount = GetBuffTiming(ability.buffName or ability.spellName)
		if active then
			local remain = (expirationTime or 0) - GetTime()
			return "buff", math.max(remain, 0), duration or math.max(remain, 0), buffCount, nil, buffIcon or icon
		end
	end

	local start, duration, enabled = GetSpellCooldown(ability.spellName)
	if start and duration and duration > 1.5 and enabled ~= 0 then
		local remain = (start + duration) - GetTime()
		if remain > 0 then return "cooldown", remain, duration, nil, nil, icon end
	end
	return "ready", 0, 0, nil, nil, icon
end

local function StateColor(d, state)
	if state == "buff" then return d.colorBuffActive end
	if state == "ready" then return d.colorReady end
	return d.colorOnCooldown
end

local function FormatTime(t)
	if t >= 60 then return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60)) end
	return string.format("%.0f", t)
end

--------------------------------------------------------------------------------
-- Multi-mob warning (Carapace Regeneration not active while surrounded)
--
-- 3.3.5a has no "count nearby enemies" API, so this approximates it via
-- the combat log: any hostile source that's landed a hit on you in the
-- last few seconds counts as "currently on you". This only catches mobs
-- actively attacking you, not ones simply standing nearby that haven't
-- swung yet - the closest reasonably reliable approximation available.
--------------------------------------------------------------------------------

local recentAttackers = {}
local ATTACKER_TIMEOUT = 4

local combatLogFrame = CreateFrame("Frame")
combatLogFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
combatLogFrame:SetScript("OnEvent", function(self, event, timestamp, subEvent, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
	if destGUID ~= UnitGUID("player") then return end
	if subEvent ~= "SWING_DAMAGE" and subEvent ~= "SPELL_DAMAGE" and subEvent ~= "RANGE_DAMAGE" and subEvent ~= "SPELL_PERIODIC_DAMAGE" then return end
	if not sourceGUID or sourceGUID == "" then return end
	recentAttackers[sourceGUID] = GetTime()
end)

local function GetRecentAttackerCount()
	local now = GetTime()
	local n = 0
	for guid, seenAt in pairs(recentAttackers) do
		if now - seenAt > ATTACKER_TIMEOUT then
			recentAttackers[guid] = nil
		else
			n = n + 1
		end
	end
	return n
end

local mobWarnWasActive = false
local mobWarnSettleUntil = 0 -- see PLAYER_ENTERING_WORLD handling below

local function UpdateMobWarning(d, carapaceStacks)
	if not d.mobWarnEnabled then return false end
	-- Same reasoning as StackTracker/BuffTracking's settle windows -
	-- carapaceStacks can transiently misread right as you zone in, and
	-- combat-log attacker entries from just before a zone transition can
	-- still be within the timeout window on the other side of it. Block
	-- the whole check (not just the sound) until things settle.
	if GetTime() < mobWarnSettleUntil then return false end
	local mobCount = GetRecentAttackerCount()
	local active = UnitAffectingCombat("player") and mobCount >= d.mobWarnThreshold and (not carapaceStacks or carapaceStacks == 0)
	if active and not mobWarnWasActive and d.mobWarnSound then
		PlaySoundFile("Sound\\Interface\\RaidWarning.wav", "Master")
	end
	mobWarnWasActive = active
	return active
end

--------------------------------------------------------------------------------
-- Widget update
--------------------------------------------------------------------------------

local function UpdateIconWidget(w, ability, d, state, remain, total, charges, maxCharges, icon, warnActive)
	w.icon:SetTexture(icon or FALLBACK_ICON)
	w.icon:SetDesaturated(state == "cooldown" or state == "charging")
	if warnActive then
		w.border:SetBackdropBorderColor(d.colorMobWarn[1], d.colorMobWarn[2], d.colorMobWarn[3], 1)
	else
		w.border:SetBackdropBorderColor(unpack(StateColor(d, state)))
	end

	if total > 0 and (state == "buff" or state == "cooldown" or state == "charging") then
		w.cooldown:SetReverse(state == "buff")
		w.cooldown:SetCooldown(GetTime() - (total - remain), total)
	else
		w.cooldown:Clear()
	end

	if charges and charges > 0 then
		w.chargeText:SetText(tostring(charges))
		w.chargeText:Show()
	else
		w.chargeText:Hide()
	end

	if d.showIconTimeText and total > 0 and (state == "buff" or state == "cooldown" or state == "charging") then
		w.timeText:Show()
		w.timeText:SetText(FormatTime(remain))
	else
		w.timeText:Hide()
	end
end

local function UpdateBarWidget(w, ability, d, state, remain, total, charges, maxCharges, icon)
	w.icon:SetTexture(icon or FALLBACK_ICON)
	local color = StateColor(d, state)
	local fraction
	local stackSuffix = (charges and charges > 0) and (" x" .. charges) or ""

	if state == "ready" then
		fraction = 1
		w.timeText:SetText("Ready")
	elseif state == "buff" then
		if total > 0 then
			fraction = remain / total
			w.timeText:SetText(FormatTime(remain) .. stackSuffix)
		else
			fraction = 1
			w.timeText:SetText("Active" .. stackSuffix)
		end
	else
		fraction = total > 0 and (1 - (remain / total)) or 0
		w.timeText:SetText(FormatTime(remain))
	end

	fraction = math.max(0, math.min(1, fraction))
	w.fill:SetVertexColor(color[1], color[2], color[3], 1)
	w.fill:SetWidth(math.max(1, (d.barWidth - 2) * fraction))
end

local function IsBeetleFormActive()
	return Core.GetActiveFormKey() == "beetle"
end

local function Refresh()
	local d = dbFn()
	LayoutWidgets()

	local carapaceStacks = nil

	for _, ability in ipairs(ABILITIES) do
		if d[ability.enabledKey] then
			local w = widgets[ability.key]
			local state, remain, total, charges, maxCharges, icon = GetAbilityState(ability)
			if ability.key == "carapace" then
				carapaceStacks = (state == "buff") and (charges or 1) or 0
			end
			if d.mode == "icon" then
				local warnActive = (ability.key == "carapace") and UpdateMobWarning(d, carapaceStacks)
				UpdateIconWidget(w.icon, ability, d, state, remain, total, charges, maxCharges, icon, warnActive)
			else
				UpdateBarWidget(w.bar, ability, d, state, remain, total, charges, maxCharges, icon)
			end
		end
	end

	local isPreviewing = previewUntil and previewUntil > GetTime()
	local ctx = GetGroupContext()
	local contextOK = (ctx == "solo" and d.showSolo) or (ctx == "party" and d.showParty)
		or (ctx == "raid" and d.showRaid) or (ctx == "battleground" and d.showBattleground)
	local formOK = IsBeetleFormActive() or isPreviewing

	if isPreviewing then
		main:Show() -- preview overrides every other gate below, always
	elseif not Core.IsBeetleFormTabEnabled() then
		main:Hide()
	elseif d.locked and ((d.hideOutOfCombat and not UnitAffectingCombat("player")) or not contextOK or not formOK) then
		main:Hide()
	else
		main:Show()
	end
end

local function StartPreview() previewUntil = GetTime() + 5 end

local Beetle = {}
Beetle.dbFn = dbFn
Beetle.main = main
Beetle.anchorFrame = anchorFrame
Beetle.Update = Refresh
Beetle.ApplyLockVisual = ApplyLockVisual

local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, e)
	elapsed = elapsed + e
	if elapsed >= 0.2 then elapsed = 0; Refresh() end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "UNIT_AURA" or event == "UNIT_SPELLCAST_SUCCEEDED" then
		if arg1 == "player" or arg1 == nil then Refresh() end
	elseif event == "PLAYER_ENTERING_WORLD" then
		wipe(recentAttackers) -- old attackers from before the zone transition shouldn't carry over
		mobWarnSettleUntil = GetTime() + 1.5
		mobWarnWasActive = false
		Core.After(1.5, Refresh)
		Refresh()
	else
		Refresh()
	end
end)

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
	if arg1 ~= Core.ADDON_NAME then return end
	local d = dbFn()
	d.abilityPositions = d.abilityPositions or {}
	for _, ability in ipairs(ABILITIES) do
		local pos = d.abilityPositions[ability.key]
		if not pos then
			local off = ABILITY_DEFAULT_OFFSET[ability.key] or { x = 0, y = -300 }
			pos = { point = "CENTER", x = off.x, y = off.y }
			d.abilityPositions[ability.key] = pos
		end
		local af = abilityAnchors[ability.key]
		af:ClearAllPoints()
		af:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
	end
	anchorFrame:ClearAllPoints()
	anchorFrame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
	ApplyLockVisual()
	self:UnregisterEvent("ADDON_LOADED")
end)

function Beetle.BuildOptionsPage(container, CreateLayoutHelpers, CreateSubTabPager)
	local L = CreateLayoutHelpers(container, dbFn, Refresh)
	L.CheckboxRow("Locked", "locked", "Lock/unlock position(s). While unlocked, drag the \"Drag Me\" handle(s) to move.", function() ApplyLockVisual() end)
	L.Dropdown("Positioning", "groupMode", {
		{ value = "grouped", label = "Grouped (one drag handle)" },
		{ value = "ungrouped", label = "Ungrouped (each ability moves independently)" },
	}, function() ApplyLockVisual() end)

	local subs, SelectSub = CreateSubTabPager(container, {
		{ key = "general", label = "General" },
		{ key = "display", label = "Display" },
		{ key = "abilities", label = "Abilities" },
		{ key = "colors", label = "Colors" },
		{ key = "mobwarn", label = "Multi-Mob Warning" },
	}, L.GetY())

	do
		local L2 = CreateLayoutHelpers(subs.general, dbFn, Refresh)
		L2.CheckboxRow("Hide when not in combat", "hideOutOfCombat")
		L2.Dropdown("Display style", "mode", {
			{ value = "icon", label = "Icons (OmniCC-compatible)" }, { value = "bar", label = "Bars (fill / drain)" },
		})
		L2.Note("Growth direction only applies in Grouped positioning.", 22)
		L2.Dropdown("Growth direction", "growth", {
			{ value = "RIGHT", label = "Right" }, { value = "LEFT", label = "Left" },
			{ value = "UP", label = "Up" }, { value = "DOWN", label = "Down" },
		})
		L2.Slider("Scale", "scale", 0.5, 2.5, 0.05)
		L2.Section("Visibility")
		L2.CheckboxRow("Show in solo play", "showSolo")
		L2.CheckboxRow("Show in a party", "showParty")
		L2.CheckboxRow("Show in a raid", "showRaid")
		L2.CheckboxRow("Show in battlegrounds/arenas", "showBattleground")
		subs.general:SetHeight(-L2.GetY() + 20)
	end
	do
		local L2 = CreateLayoutHelpers(subs.display, dbFn, Refresh)
		L2.Section("Icon Mode")
		L2.Slider("Icon size", "iconSize", 20, 64, 1)
		L2.Slider("Icon spacing", "iconSpacing", -8, 20, 1)
		L2.Note("Icon spacing only applies in Grouped positioning.", 22)
		L2.CheckboxRow("Show time/charge text on icons", "showIconTimeText")
		L2.Section("Bar Mode")
		L2.Slider("Bar width", "barWidth", 80, 320, 5)
		L2.Slider("Bar height", "barHeight", 14, 36, 1)
		L2.Slider("Bar spacing", "barSpacing", -4, 16, 1)
		subs.display:SetHeight(-L2.GetY() + 20)
	end
	do
		local L2 = CreateLayoutHelpers(subs.abilities, dbFn, Refresh)
		L2.Note("Turn individual abilities on or off in the watcher.")
		L2.CheckboxRow("Harden", "hardenEnabled", "45% damage reduction, decaying over 10 sec; heals 1% max health per stack removed. 3 min cooldown.")
		L2.CheckboxRow("Regrow Exoskeleton", "regrowEnabled", "Clears Exposed Flesh stacks, 20% damage reduction for 5 sec. 1 min cooldown.")
		L2.CheckboxRow("Vile Sting", "vileStingEnabled", "Taunts for 3 sec; if tauntable and not already targeting you, also triggers your current venoms.")
		L2.CheckboxRow("Expulsion", "expulsionEnabled", "Primary way to clear Exposed Flesh stacks. 10 sec cooldown.")
		L2.CheckboxRow("Carapace Regeneration", "carapaceEnabled", "Stacking buff, up to 3 - shows a stack count on its icon while active.")
		L2.AdvanceY(6)
		L2.Note("Fakes a 5-second buff/cooldown cycle on every enabled ability so you can see and position the watcher without waiting on real cooldowns.", 26)
		L2.Button("Preview (5s)", StartPreview)
		subs.abilities:SetHeight(-L2.GetY() + 20)
	end
	do
		local L2 = CreateLayoutHelpers(subs.colors, dbFn, Refresh)
		L2.ColorSwatch("Buff active:", "colorBuffActive")
		L2.ColorSwatch("On cooldown:", "colorOnCooldown")
		L2.ColorSwatch("Ready:", "colorReady")
		L2.ColorSwatch("Multi-mob warning:", "colorMobWarn")
		subs.colors:SetHeight(-L2.GetY() + 20)
	end
	do
		local L2 = CreateLayoutHelpers(subs.mobwarn, dbFn, Refresh)
		L2.Note("Tints the Carapace Regeneration icon's border and optionally plays a sound while you're in combat, at/above the mob threshold below, and Carapace Regeneration isn't currently active. Requires Carapace Regeneration to be enabled above.", 40)
		L2.Note("Mob count is approximated from the combat log - anything that's hit you in the last few seconds counts as \"on you\". There's no reliable way to count nearby-but-not-yet-attacking mobs in this client.", 40)
		L2.CheckboxRow("Enable multi-mob warning", "mobWarnEnabled")
		L2.Slider("Warn at this many attackers", "mobWarnThreshold", 2, 10, 1)
		L2.CheckboxRow("Sound cue", "mobWarnSound")
		subs.mobwarn:SetHeight(-L2.GetY() + 20)
	end
	SelectSub("general")
end

Core.BeetleDefenses = Beetle
Core.RegisterLockable({ dbFn = dbFn, apply = function() ApplyLockVisual(); Refresh() end })
