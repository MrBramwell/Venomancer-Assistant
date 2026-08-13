--[[
	Cooldown Watcher

	Tracks the Venomancer's Beetle Form (tank) defensive cooldowns:

	  - Harden: a buff that decays over 10s, then a 3 min cooldown.
	  - Regrow Exoskeleton: clears Exposed Flesh, short 5s buff, 1 min CD.
	  - Vile Sting: taunt, simple cooldown.
	  - Expulsion: clears Exposed Flesh stacks, 10s cooldown.

	Some of these have both a "buff active" phase and a "cooldown" phase,
	so each ability widget needs to represent both states, not just
	ready/not-ready.

	Two display modes, chosen per the whole watcher (not per-ability):

	  - Icon mode: real Cooldown widgets (CooldownFrameTemplate), so
	    OmniCC (or any other cooldown-text addon) hooks in automatically -
	    we never draw our own countdown text over the swipe, we just call
	    SetCooldown like any action button would.
	  - Bar mode: a fill/drain bar per ability, colored by state.

	Spell IDs (for reference, not required at runtime - name-based lookups
	are used throughout so whichever rank is currently known just works):
	  Harden r1: 800892
	  Regrow Exoskeleton: 803197
	  Exposed Flesh (existing tracker's debuff): 92144

	(Carapace Regeneration tracking was removed - its charge/buff
	semantics never landed cleanly on this client, not worth chasing.)
]]

local ADDON_NAME = "VenomancerAssistant"
CooldownWatcherModule = CooldownWatcherModule or {}

local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function GetDB()
	VenomancerAssistantDB = VenomancerAssistantDB or BroodMarksDB or {}
	local d = VenomancerAssistantDB
	if d.cdPoint == nil then
		d.cdPoint, d.cdX, d.cdY = "CENTER", 220, -220
		d.cdLocked = false
		d.cdMode = "icon" -- "icon" or "bar"
		d.cdScale = 1.0
		d.cdGrowth = "RIGHT" -- "RIGHT", "LEFT", "UP", "DOWN"

		d.cdIconSize = 36
		d.cdIconSpacing = 8
		d.cdShowIconTimeText = true -- redundant if you run OmniCC, useful if you don't

		d.cdBarWidth = 170
		d.cdBarHeight = 20
		d.cdBarSpacing = 5

		d.cdHideOutOfCombat = false

		d.cdColorBuffActive = { 0.3, 0.85, 0.3 }  -- green: the defensive effect is currently up
		d.cdColorOnCooldown = { 0.6, 0.6, 0.65 }  -- grey: waiting to come back (also used while charging)
		d.cdColorReady      = { 1, 0.82, 0 }      -- gold: ready to use

		d.cdHardenEnabled   = true
		d.cdRegrowEnabled   = true
		d.cdVileStingEnabled  = true
		d.cdExpulsionEnabled  = true
	end
	-- Added after the block above was already shipped. Each guarded
	-- individually on ITS OWN key (not bundled behind one older flag's
	-- nil-check) so upgrading from any earlier version always picks up
	-- every field below, instead of silently staying nil forever the
	-- moment the "outer" flag it happened to be bundled with already
	-- existed. (This is what broke the mana bar: cdManaPoint/BarWidth/
	-- etc. were nested inside "if cdShowMana == nil", which never re-ran
	-- once cdShowMana already existed from an earlier version.)
	if d.cdVileStingEnabled == nil then d.cdVileStingEnabled = true end
	if d.cdExpulsionEnabled == nil then d.cdExpulsionEnabled = true end
	if d.cdShowMana == nil then d.cdShowMana = true end
	if d.cdManaWarnThreshold == nil then d.cdManaWarnThreshold = 20 end -- percent
	if d.cdColorMana == nil then d.cdColorMana = { 0.3, 0.4, 0.9 } end  -- blue
	if d.cdColorManaLow == nil then d.cdColorManaLow = { 1, 0.15, 0.15 } end -- red, once below the threshold
	if d.cdManaPoint == nil then d.cdManaPoint, d.cdManaX, d.cdManaY = "CENTER", 220, -280 end
	if d.cdManaLocked == nil then d.cdManaLocked = false end
	if d.cdManaBarWidth == nil then d.cdManaBarWidth = 180 end
	if d.cdManaBarHeight == nil then d.cdManaBarHeight = 22 end
	if d.cdManaHideOutOfCombat == nil then d.cdManaHideOutOfCombat = false end
	if d.cdManaDisplayFormat == nil then d.cdManaDisplayFormat = "numbers" end -- "numbers", "percent", "both"

	if d.cdShowSolo == nil then d.cdShowSolo = true end
	if d.cdShowParty == nil then d.cdShowParty = true end
	if d.cdShowRaid == nil then d.cdShowRaid = true end
	if d.cdShowBattleground == nil then d.cdShowBattleground = true end
	if d.cdRequireBeetleForm == nil then d.cdRequireBeetleForm = false end

	if d.cdManaShowSolo == nil then d.cdManaShowSolo = true end
	if d.cdManaShowParty == nil then d.cdManaShowParty = true end
	if d.cdManaShowRaid == nil then d.cdManaShowRaid = true end
	if d.cdManaShowBattleground == nil then d.cdManaShowBattleground = true end
	return d
end

--------------------------------------------------------------------------------
-- Ability definitions
--------------------------------------------------------------------------------

local ABILITIES = {
	{ key = "harden",   enabledKey = "cdHardenEnabled",   name = "Harden",                 spellName = "Harden",                 fallbackIcon = "Interface\\Icons\\Ability_Defend",              hasCharges = false, hasBuff = true },
	{ key = "regrow",   enabledKey = "cdRegrowEnabled",   name = "Regrow Exoskeleton",      spellName = "Regrow Exoskeleton",     fallbackIcon = "Interface\\Icons\\Ability_Rogue_Nervesofsteel", hasCharges = false, hasBuff = true },
	{ key = "vilesting",  enabledKey = "cdVileStingEnabled",  name = "Vile Sting", spellName = "Vile Sting", fallbackIcon = "Interface\\Icons\\Ability_Hunter_Pet_Wasp",   hasCharges = false, hasBuff = false },
	{ key = "expulsion",  enabledKey = "cdExpulsionEnabled",  name = "Expulsion",  spellName = "Expulsion",  fallbackIcon = "Interface\\Icons\\Ability_Creature_Poison_06", hasCharges = false, hasBuff = false },
}

-- Mana is a separate, independently-draggable readout (not part of the
-- ability grid above) since Beetle/Spider Form hide the normal mana bar
-- and this wants its own placement (e.g. near a unit frame) rather than
-- being locked to the cooldown watcher's layout.
local MANA_DEF = { key = "mana", enabledKey = "cdShowMana", name = "Mana", isMana = true, fallbackIcon = "Interface\\Icons\\INV_Elemental_Primal_Mana" }

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------

local function EnabledCount()
	local d = GetDB()
	local n = 0
	for _, a in ipairs(ABILITIES) do
		if d[a.enabledKey] then n = n + 1 end
	end
	return n
end

local anchorFrame = CreateFrame("Frame", "CooldownWatcherAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local main = CreateFrame("Frame", "CooldownWatcherFrame", UIParent)
main:SetSize(200, 40)
main:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
main:SetClampedToScreen(true)
main:EnableMouse(false)

local placeholder = main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
placeholder:SetPoint("LEFT", main, "LEFT", 0, 0)
placeholder:SetText("Cooldown Watcher (no abilities enabled)")
placeholder:Hide()

local dragHint = CreateFrame("Frame", nil, UIParent)
dragHint:SetSize(110, 22)
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
dragHint:SetScript("OnDragStart", function()
	anchorFrame:StartMoving()
end)
dragHint:SetScript("OnDragStop", function()
	anchorFrame:StopMovingOrSizing()
	local d = GetDB()
	d.cdPoint, _, _, d.cdX, d.cdY = anchorFrame:GetPoint()
end)
dragHint:Hide()

local function ApplyLockVisual()
	local d = GetDB()
	local unlocked = not d.cdLocked
	dragHint:EnableMouse(unlocked)
	dragHint:SetShown(unlocked and EnabledCount() > 0)
end

--------------------------------------------------------------------------------
-- Mana frame - independent anchor/drag from the ability watcher above
--------------------------------------------------------------------------------

local manaAnchorFrame = CreateFrame("Frame", "CooldownWatcherManaAnchor", UIParent)
manaAnchorFrame:SetSize(1, 1)
manaAnchorFrame:SetMovable(true)
manaAnchorFrame:SetClampedToScreen(true)

local manaFrame = CreateFrame("Frame", "CooldownWatcherManaFrame", UIParent)
manaFrame:SetPoint("LEFT", manaAnchorFrame, "LEFT", 0, 0)
manaFrame:SetClampedToScreen(true)
manaFrame:EnableMouse(false)

local manaDragHint = CreateFrame("Frame", nil, UIParent)
manaDragHint:SetSize(110, 22)
manaDragHint:SetMovable(true)
manaDragHint:SetClampedToScreen(true)
manaDragHint:RegisterForDrag("LeftButton")
manaDragHint:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
})
manaDragHint:SetBackdropColor(0, 0, 0, 0.8)
manaDragHint:SetBackdropBorderColor(1, 0.82, 0, 1)
local manaDragHintText = manaDragHint:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
manaDragHintText:SetAllPoints()
manaDragHintText:SetJustifyH("CENTER")
manaDragHintText:SetJustifyV("MIDDLE")
manaDragHintText:SetText("Drag Me")
manaDragHintText:SetTextColor(1, 0.82, 0)
manaDragHint:SetScript("OnDragStart", function()
	manaAnchorFrame:StartMoving()
end)
manaDragHint:SetScript("OnDragStop", function()
	manaAnchorFrame:StopMovingOrSizing()
	local d = GetDB()
	d.cdManaPoint, _, _, d.cdManaX, d.cdManaY = manaAnchorFrame:GetPoint()
end)
manaDragHint:Hide()

local function ApplyManaLockVisual()
	local d = GetDB()
	local unlocked = not d.cdManaLocked
	manaDragHint:EnableMouse(unlocked)
	manaDragHint:SetShown(unlocked)
	manaDragHint:ClearAllPoints()
	manaDragHint:SetPoint("BOTTOMLEFT", manaFrame, "TOPLEFT", 0, 8)
end

--------------------------------------------------------------------------------
-- Per-ability widgets (both icon and bar versions are created once and kept
-- around; layout just shows/hides whichever the current display mode needs)
--------------------------------------------------------------------------------

local widgets = {} -- [key] = { icon = frame, bar = frame }

local function CreateIconWidget(ability)
	local b = CreateFrame("Button", "CooldownWatcherIcon" .. ability.key, main)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetAllPoints()
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local border = CreateFrame("Frame", nil, b)
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
	border:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	b.border = border

	b.cooldown = CreateFrame("Cooldown", "CooldownWatcherIcon" .. ability.key .. "Cooldown", b, "CooldownFrameTemplate")
	b.cooldown:SetAllPoints()
	if b.cooldown.SetDrawBling then b.cooldown:SetDrawBling(false) end -- Cata+ only; guarded so it doesn't error on 3.3.5
	-- Real Cooldown widget with nothing custom drawn over it - this is
	-- what lets OmniCC (or any other cooldown-text addon) hook in and
	-- show its own countdown text with zero extra work on our part.

	b.chargeText = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	b.chargeText:SetPoint("BOTTOMRIGHT", -2, 2)

	b.timeText = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	-- Anchored inside the icon (opposite corner from the charge count),
	-- not below it - a below-icon label overlapped the next icon when
	-- stacked vertically (growth UP/DOWN) or packed tightly.
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

local function CreateBarWidget(ability, parent)
	local f = CreateFrame("Frame", nil, parent or main)

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

	local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	label:SetText(ability.name)
	f.label = label

	local timeText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	timeText:SetPoint("RIGHT", -4, 0)
	f.timeText = timeText

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
CreateBarWidget(MANA_DEF, manaFrame) -- its own frame, not part of the ability grid

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local GROWTH_INFO = {
	RIGHT = { point = "LEFT",   relPoint = "LEFT" },
	LEFT  = { point = "RIGHT",  relPoint = "LEFT" },
	DOWN  = { point = "TOP",    relPoint = "LEFT" },
	UP    = { point = "BOTTOM", relPoint = "LEFT" },
}
local DRAG_HINT_INFO = {
	RIGHT = { hintPoint = "BOTTOMLEFT",  mainPoint = "TOPLEFT",  x = 0, y = 8 },
	LEFT  = { hintPoint = "BOTTOMRIGHT", mainPoint = "TOPRIGHT", x = 0, y = 8 },
	DOWN  = { hintPoint = "BOTTOMLEFT",  mainPoint = "TOPLEFT",  x = 0, y = 8 },
	UP    = { hintPoint = "TOPLEFT",     mainPoint = "BOTTOMLEFT", x = 0, y = -8 },
}

local function LayoutWidgets()
	local d = GetDB()
	local mode = d.cdMode
	local growth = d.cdGrowth or "RIGHT"
	local vertical = (growth == "UP" or growth == "DOWN")
	local info = GROWTH_INFO[growth] or GROWTH_INFO.RIGHT

	main:ClearAllPoints()
	main:SetPoint(info.point, anchorFrame, info.relPoint, 0, 0)
	main:SetScale(d.cdScale)

	local spacing = mode == "icon" and d.cdIconSpacing or d.cdBarSpacing

	local prev, count = nil, 0
	local totalLength, maxThickness = 0, 0

	local function PlaceItem(def, widgetMode, w, h)
		local shown = widgets[def.key][widgetMode]
		shown:SetSize(w, h)
		if widgetMode == "bar" then
			shown.icon:SetSize(h - 4, h - 4)
		end
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
		local length = vertical and h or w
		local thickness = vertical and w or h
		totalLength = totalLength + length + (count > 1 and spacing or 0)
		if thickness > maxThickness then maxThickness = thickness end
	end

	for _, ability in ipairs(ABILITIES) do
		local w = widgets[ability.key]
		w[mode == "icon" and "bar" or "icon"]:Hide() -- the mode we're NOT using this pass
		if d[ability.enabledKey] then
			if mode == "icon" then
				PlaceItem(ability, "icon", d.cdIconSize, d.cdIconSize)
			else
				PlaceItem(ability, "bar", d.cdBarWidth, d.cdBarHeight)
			end
		else
			w.icon:Hide()
			w.bar:Hide()
		end
	end

	-- Mana is a separate frame now - not part of this layout pass.

	if count == 0 then
		placeholder:Show()
		main:SetSize(math.max(1, placeholder:GetStringWidth()), 20)
	else
		placeholder:Hide()
		if vertical then
			main:SetSize(maxThickness, totalLength)
		else
			main:SetSize(totalLength, maxThickness)
		end
	end

	local hintInfo = DRAG_HINT_INFO[growth] or DRAG_HINT_INFO.RIGHT
	dragHint:ClearAllPoints()
	dragHint:SetPoint(hintInfo.hintPoint, main, hintInfo.mainPoint, hintInfo.x, hintInfo.y)
	ApplyLockVisual()
end

local function LayoutManaBar()
	local d = GetDB()
	local barW, barH = d.cdManaBarWidth or 180, d.cdManaBarHeight or 22
	manaFrame:ClearAllPoints()
	manaFrame:SetPoint("LEFT", manaAnchorFrame, "LEFT", 0, 0)

	local w = widgets[MANA_DEF.key].bar
	w:SetSize(barW, barH)
	w.icon:SetSize(barH - 4, barH - 4)
	w:ClearAllPoints()
	w:SetPoint("TOPLEFT", manaFrame, "TOPLEFT", 0, 0)
	manaFrame:SetSize(barW, barH)

	ApplyManaLockVisual()
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

local function GetBuffTiming(buffName)
	for i = 1, 40 do
		local name, _, icon, count, _, duration, expirationTime = UnitBuff("player", i)
		if not name then break end
		if name == buffName then
			return true, icon, duration, expirationTime, count
		end
	end
	-- Some "active effect" abilities (e.g. a self-channeled regen tick)
	-- don't put up a discrete buff icon at all - they're a channel. Catch
	-- that case too, since UnitBuff alone would never see it.
	local channelName, _, channelIcon, startTime, endTime = UnitChannelInfo("player")
	if channelName == buffName and startTime and endTime then
		local duration = (endTime - startTime) / 1000
		return true, channelIcon, duration, endTime / 1000, nil
	end
	return false
end

local previewUntil = nil

-- "solo", "party", "raid", or "battleground" - checked against the
-- cdShow*/cdManaShow* visibility toggles. Uses the WotLK-era group APIs
-- (GetNumPartyMembers/GetNumRaidMembers), not the later unified
-- GetNumGroupMembers, since this is a 3.3.5 client.
local function GetGroupContext()
	local inInstance, instanceType = IsInInstance()
	if inInstance and (instanceType == "pvp" or instanceType == "arena") then
		return "battleground"
	end
	if GetNumRaidMembers and GetNumRaidMembers() > 0 then
		return "raid"
	end
	if GetNumPartyMembers and GetNumPartyMembers() > 0 then
		return "party"
	end
	return "solo"
end

-- Generic form check, kept separate from any particular watcher so it can
-- be reused later for a Spider Form (caster/healer) cooldown set, etc. -
-- each future watcher would just call IsInForm() with its own form name.
local function IsInForm(formName)
	local form = GetShapeshiftForm and GetShapeshiftForm()
	if form and form > 0 then
		local _, name = GetShapeshiftFormInfo(form)
		return name == formName
	end
	return false
end

-- Returns: state ("buff"/"charging"/"cooldown"/"ready"), remain, total,
-- charges, maxCharges, icon
local function GetAbilityState(ability)
	local icon = select(3, GetSpellInfo(ability.spellName)) or ability.fallbackIcon

	if previewUntil and previewUntil > GetTime() then
		local remain = previewUntil - GetTime()
		if ability.hasBuff then
			return (remain > 2.5 and "buff" or "cooldown"), remain, 5, ability.hasCharges and 1 or nil, ability.hasCharges and 3 or nil, icon
		elseif ability.hasCharges then
			return "charging", remain, 5, 1, 3, icon
		else
			return "cooldown", remain, 5, nil, nil, icon
		end
	end

	-- Fetch charges first (if applicable) so they can be shown alongside
	-- the buff state below too - some abilities can have BOTH: charges
	-- gate how many times you can use it, but using one also puts up an
	-- active buff/channel that "runs out" on its own.
	local charges, maxCharges, chargeStart, chargeDuration
	if ability.hasCharges then
		-- Try by ID first (if we have one) then by name. A result is only
		-- trusted if maxCharges is a sane positive number - GetSpellCharges
		-- returning 0,0 (not nil) for an unresolved lookup is indistinguishable
		-- from "truly 0 charges" otherwise, since 0 is truthy in Lua.
		local function TryCharges(idOrName)
			if not idOrName then return nil end
			local ok, c, m, s, dur = pcall(GetSpellCharges, idOrName)
			if ok and c and m and m > 0 then
				return c, m, s, dur
			end
			return nil
		end
		local c, m, s, dur = TryCharges(ability.spellID)
		if not c then c, m, s, dur = TryCharges(ability.spellName) end
		if c then charges, maxCharges, chargeStart, chargeDuration = c, m, s, dur end
	end

	if ability.hasBuff then
		local active, buffIcon, duration, expirationTime, buffCount = GetBuffTiming(ability.buffName or ability.spellName)
		if active then
			local remain = (expirationTime or 0) - GetTime()
			-- While the effect is actively up, show the buff's own stack
			-- count (matches the in-game buff icon's "x2" etc.) rather
			-- than the recharge-pool "charges remaining" number - those
			-- answer different questions, and the stack count is what's
			-- wanted here. maxCharges is passed as nil to signal "this is
			-- a raw stack count, not a charges/max fraction" downstream.
			return "buff", math.max(remain, 0), duration or math.max(remain, 0), buffCount or charges, nil, buffIcon or icon
		end
	end

	if ability.hasCharges then
		if charges then
			if charges >= maxCharges or not chargeStart or chargeStart == 0 or not chargeDuration or chargeDuration == 0 then
				return "ready", 0, 0, charges, maxCharges, icon
			else
				local remain = (chargeStart + chargeDuration) - GetTime()
				return "charging", math.max(remain, 0), chargeDuration, charges, maxCharges, icon
			end
		end
		-- GetSpellCharges missing/erroring on this client - fall back to
		-- treating it as always-ready rather than breaking the watcher.
		return "ready", 0, 0, nil, nil, icon
	end

	local start, duration, enabled = GetSpellCooldown(ability.spellName)
	-- duration > 1.5 filters out the global cooldown so it doesn't read
	-- as "on cooldown" every time you use anything else.
	if start and duration and duration > 1.5 and enabled ~= 0 then
		local remain = (start + duration) - GetTime()
		if remain > 0 then
			return "cooldown", remain, duration, nil, nil, icon
		end
	end
	return "ready", 0, 0, nil, nil, icon
end

local function StateColor(d, state)
	if state == "buff" then return d.cdColorBuffActive end
	if state == "ready" then return d.cdColorReady end
	return d.cdColorOnCooldown -- "cooldown" or "charging"
end

local function FormatTime(t)
	if t >= 60 then
		return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60))
	end
	return string.format("%.0f", t)
end

local function UpdateIconWidget(w, ability, d, state, remain, total, charges, maxCharges, icon)
	w.icon:SetTexture(icon or FALLBACK_ICON)

	if state == "cooldown" or state == "charging" then
		w.icon:SetDesaturated(true)
	else
		w.icon:SetDesaturated(false)
	end

	w.border:SetBackdropBorderColor(unpack(StateColor(d, state)))

	if total > 0 and (state == "buff" or state == "cooldown" or state == "charging") then
		w.cooldown:SetReverse(state == "buff") -- buff draining sweeps the opposite way from a cooldown filling back in
		w.cooldown:SetCooldown(GetTime() - (total - remain), total)
	else
		-- Also covers "buff" with no real duration signal (some abilities'
		-- active-use buff has no expiration - a swipe would be meaningless).
		w.cooldown:Clear()
	end

	if ability.hasCharges then
		w.chargeText:SetShown(true)
		w.chargeText:SetText(charges or "")
		w.chargeText:SetTextColor(unpack(StateColor(d, state)))
	else
		w.chargeText:Hide()
	end

	if d.cdShowIconTimeText and total > 0 and (state == "buff" or state == "cooldown" or state == "charging") then
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
	-- maxCharges is nil specifically to signal "charges holds a raw stack
	-- count (buff state), not a charges/max fraction" - see GetAbilityState.
	local chargeStr = ability.hasCharges and charges and (maxCharges and (charges .. "/" .. maxCharges) or tostring(charges)) or nil

	if state == "ready" then
		fraction = 1
		w.timeText:SetText(chargeStr or "Ready")
	elseif state == "buff" then
		if total > 0 then
			fraction = remain / total -- drains from full as the buff runs out
			w.timeText:SetText(chargeStr and (chargeStr .. "  " .. FormatTime(remain)) or FormatTime(remain))
		else
			-- No real duration signal for this buff (e.g. a static
			-- stack-indicator rather than a timed aura) - show it as lit
			-- up/active rather than an empty bar, since "empty" reads as
			-- "not active" which would be backwards here.
			fraction = 1
			w.timeText:SetText(chargeStr or "Active")
		end
	else -- cooldown / charging
		fraction = total > 0 and (1 - (remain / total)) or 0 -- fills up as it recharges
		w.timeText:SetText(chargeStr and (chargeStr .. "  " .. FormatTime(remain)) or FormatTime(remain))
	end

	fraction = math.max(0, math.min(1, fraction))
	w.fill:SetVertexColor(color[1], color[2], color[3], 1)
	w.fill:SetWidth(math.max(1, (d.cdBarWidth - 2) * fraction))
end

local function UpdateManaBar(w, d)
	local mana = UnitPower("player", 0)
	local maxMana = UnitPowerMax("player", 0)
	local fraction = maxMana > 0 and (mana / maxMana) or 0
	local percent = math.floor(fraction * 100 + 0.5)
	local low = percent <= (d.cdManaWarnThreshold or 20)
	local color = low and d.cdColorManaLow or d.cdColorMana

	local text
	if d.cdManaDisplayFormat == "percent" then
		text = percent .. "%"
	elseif d.cdManaDisplayFormat == "both" then
		text = mana .. " / " .. maxMana .. "  (" .. percent .. "%)"
	else -- "numbers"
		text = mana .. " / " .. maxMana
	end

	w.icon:SetTexture(MANA_DEF.fallbackIcon)
	w.fill:SetVertexColor(color[1], color[2], color[3], 1)
	w.fill:SetWidth(math.max(1, (d.cdManaBarWidth - 2) * math.max(0, math.min(1, fraction))))
	w.timeText:SetText(text)
end

local function Refresh()
	local d = GetDB()
	LayoutWidgets()

	for _, ability in ipairs(ABILITIES) do
		if d[ability.enabledKey] then
			local w = widgets[ability.key]
			local state, remain, total, charges, maxCharges, icon = GetAbilityState(ability)
			if d.cdMode == "icon" then
				UpdateIconWidget(w.icon, ability, d, state, remain, total, charges, maxCharges, icon)
			else
				UpdateBarWidget(w.bar, ability, d, state, remain, total, charges, maxCharges, icon)
			end
		end
	end

	local ctx = GetGroupContext()
	local contextOK = (ctx == "solo" and d.cdShowSolo)
		or (ctx == "party" and d.cdShowParty)
		or (ctx == "raid" and d.cdShowRaid)
		or (ctx == "battleground" and d.cdShowBattleground)
	local roleOK = (not d.cdRequireBeetleForm) or IsInForm("Beetle Form")

	if d.cdLocked and ((d.cdHideOutOfCombat and not UnitAffectingCombat("player")) or not contextOK or not roleOK) then
		main:Hide()
	else
		main:Show()
	end

	-- Mana: independent frame, independent lock, independent visibility.
	LayoutManaBar()
	if d.cdShowMana then
		UpdateManaBar(widgets[MANA_DEF.key].bar, d)
	end

	local manaContextOK = (ctx == "solo" and d.cdManaShowSolo)
		or (ctx == "party" and d.cdManaShowParty)
		or (ctx == "raid" and d.cdManaShowRaid)
		or (ctx == "battleground" and d.cdManaShowBattleground)

	if not d.cdShowMana and d.cdManaLocked then
		manaFrame:Hide()
	elseif d.cdManaLocked and ((d.cdManaHideOutOfCombat and not UnitAffectingCombat("player")) or not manaContextOK) then
		manaFrame:Hide()
	else
		manaFrame:Show()
	end
end

local function StartPreview()
	previewUntil = GetTime() + 5
end

-- Called by the title-bar "Locked" pill (the addon-wide master lock) so
-- it can override both this frame's and the mana bar's independent
-- locks at once, syncing them together.
function CooldownWatcherModule.SetAllLocked(locked)
	local d = GetDB()
	d.cdLocked = locked
	d.cdManaLocked = locked
	ApplyLockVisual()
	ApplyManaLockVisual()
	Refresh()
end

--------------------------------------------------------------------------------
-- Events / ticker
--------------------------------------------------------------------------------

local ticker = CreateFrame("Frame")
local elapsed = 0
ticker:SetScript("OnUpdate", function(self, e)
	elapsed = elapsed + e
	if elapsed >= 0.2 then
		elapsed = 0
		Refresh()
	end
end)

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
events:RegisterEvent("UNIT_POWER")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("SPELL_UPDATE_CHARGES")
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		local d = GetDB()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.cdPoint or "CENTER", UIParent, d.cdPoint or "CENTER", d.cdX or 0, d.cdY or 0)
		manaAnchorFrame:ClearAllPoints()
		manaAnchorFrame:SetPoint(d.cdManaPoint or "CENTER", UIParent, d.cdManaPoint or "CENTER", d.cdManaX or 0, d.cdManaY or 0)
		ApplyLockVisual()
		ApplyManaLockVisual()
		Refresh()
	elseif event == "UNIT_AURA" or event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_POWER" then
		if arg1 == "player" or arg1 == nil then Refresh() end
	else
		Refresh()
	end
end)

--------------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------------

local function GetTabIcon()
	return select(3, GetSpellInfo("Harden")) or "Interface\\Icons\\Ability_Defend"
end

function CooldownWatcherModule.BuildOptionsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers, CreateSubTabPager)
	local sc = RegisterTab("cdwatcher", "Cooldown Watcher", GetTabIcon())
	local L = CreateLayoutHelpers(sc)
	L.Note("Tracks Harden, Regrow Exoskeleton, Vile Sting, and Expulsion. This frame has its own Lock and position, independent of the tracker/Venom Bar. See the separate Mana tab for the mana bar. The big Locked pill in the title bar overrides this (and the Mana bar's) lock when clicked.")
	L.CheckboxRow("Locked", "cdLocked", "Lock/unlock this frame's position. While unlocked, drag the \"Drag Me\" handle above it to move it.")

	local subs, SelectSub = CreateSubTabPager(sc, {
		{ key = "general", label = "General" },
		{ key = "display", label = "Display" },
		{ key = "abilities", label = "Abilities" },
		{ key = "colors", label = "Colors" },
	}, L.GetY())

	do
		local L2 = CreateLayoutHelpers(subs.general)
		L2.CheckboxRow("Hide when not in combat", "cdHideOutOfCombat", "Hide the whole watcher outside of combat. Ignored while unlocked, so you can still position it.")
		L2.Dropdown("Display style", "cdMode", {
			{ value = "icon", label = "Icons (OmniCC-compatible)" },
			{ value = "bar", label = "Bars (fill / drain)" },
		}, LayoutWidgets)
		L2.Dropdown("Growth direction", "cdGrowth", {
			{ value = "RIGHT", label = "Right" },
			{ value = "LEFT", label = "Left" },
			{ value = "UP", label = "Up" },
			{ value = "DOWN", label = "Down" },
		}, LayoutWidgets)
		L2.Slider("Scale", "cdScale", 0.5, 2.5, 0.05, LayoutWidgets)
		L2.Section("Visibility")
		L2.Note("All checked by default (visible everywhere). Uncheck any of these to hide the watcher in that situation. Ignored while unlocked.", 30)
		L2.CheckboxRow("Show in solo play", "cdShowSolo")
		L2.CheckboxRow("Show in a party", "cdShowParty")
		L2.CheckboxRow("Show in a raid", "cdShowRaid")
		L2.CheckboxRow("Show in battlegrounds/arenas", "cdShowBattleground")
		L2.CheckboxRow("Only show while in Beetle Form", "cdRequireBeetleForm", "Off by default. Beetle Form is where these abilities live, so this hides the watcher any time you're not in it.")
		subs.general:SetHeight(-L2.GetY() + 20)
	end

	do
		local L2 = CreateLayoutHelpers(subs.display)
		L2.Section("Icon Mode")
		L2.Slider("Icon size", "cdIconSize", 20, 64, 1, LayoutWidgets)
		L2.Slider("Icon spacing", "cdIconSpacing", -8, 20, 1, LayoutWidgets)
		L2.CheckboxRow("Show time/charge text on icons", "cdShowIconTimeText", "Small text overlaid in the corner of each icon with seconds remaining (or charge count, for abilities that have charges). Redundant if you run OmniCC, useful if you don't.")
		L2.Section("Bar Mode")
		L2.Slider("Bar width", "cdBarWidth", 80, 320, 5, LayoutWidgets)
		L2.Slider("Bar height", "cdBarHeight", 14, 36, 1, LayoutWidgets)
		L2.Slider("Bar spacing", "cdBarSpacing", -4, 16, 1, LayoutWidgets)
		subs.display:SetHeight(-L2.GetY() + 20)
	end

	do
		local L2 = CreateLayoutHelpers(subs.abilities)
		L2.Note("Turn individual abilities on or off in the watcher.")
		L2.CheckboxRow("Harden", "cdHardenEnabled", "45% damage reduction, decaying over 10 sec; heals 1% max health per stack removed. 3 min cooldown.")
		L2.CheckboxRow("Regrow Exoskeleton", "cdRegrowEnabled", "Clears Exposed Flesh stacks, 20% damage reduction for 5 sec. 1 min cooldown.")
		L2.CheckboxRow("Vile Sting", "cdVileStingEnabled", "Taunts for 3 sec; if tauntable and not already targeting you, also triggers your current venoms.")
		L2.CheckboxRow("Expulsion", "cdExpulsionEnabled", "Primary way to clear Exposed Flesh stacks. 10 sec cooldown.")
		L2.AdvanceY(6)
		L2.Note("Fakes a 5-second buff/cooldown cycle on every enabled ability so you can see and position the watcher without waiting on real cooldowns.", 26)
		L2.Button("Preview (5s)", StartPreview)
		subs.abilities:SetHeight(-L2.GetY() + 20)
	end

	do
		local L2 = CreateLayoutHelpers(subs.colors)
		L2.ColorSwatch("Buff active:", "cdColorBuffActive")
		L2.ColorSwatch("On cooldown / charging:", "cdColorOnCooldown")
		L2.ColorSwatch("Ready:", "cdColorReady")
		subs.colors:SetHeight(-L2.GetY() + 20)
	end

	SelectSub("general")
end

function CooldownWatcherModule.BuildManaTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers, CreateSubTabPager)
	local sc = RegisterTab("mana", "Mana", MANA_DEF.fallbackIcon)
	local L = CreateLayoutHelpers(sc)
	L.Note("Beetle Form and Spider Form hide your normal mana bar - handy to still see it in dungeons and PvP. Own frame, own Lock/position/size, independent of the Cooldown Watcher - though the title bar's big Locked pill overrides both at once.", 40)
	L.CheckboxRow("Enable mana bar", "cdShowMana", "Turn the whole mana bar module on or off.")
	L.CheckboxRow("Locked", "cdManaLocked", "Lock/unlock the mana bar's position. While unlocked, drag its \"Drag Me\" handle to move it.")

	local subs, SelectSub = CreateSubTabPager(sc, {
		{ key = "general", label = "General" },
		{ key = "display", label = "Display" },
	}, L.GetY())

	do
		local L2 = CreateLayoutHelpers(subs.general)
		L2.CheckboxRow("Hide when not in combat", "cdManaHideOutOfCombat", "Hide the mana bar outside of combat. Ignored while unlocked, so you can still position it.")
		L2.Section("Visibility")
		L2.Note("All checked by default (visible everywhere). Uncheck any of these to hide the mana bar in that situation. Ignored while unlocked.", 30)
		L2.CheckboxRow("Show in solo play", "cdManaShowSolo")
		L2.CheckboxRow("Show in a party", "cdManaShowParty")
		L2.CheckboxRow("Show in a raid", "cdManaShowRaid")
		L2.CheckboxRow("Show in battlegrounds/arenas", "cdManaShowBattleground")
		subs.general:SetHeight(-L2.GetY() + 20)
	end

	do
		local L2 = CreateLayoutHelpers(subs.display)
		L2.Slider("Bar width", "cdManaBarWidth", 80, 320, 5, LayoutManaBar)
		L2.Slider("Bar height", "cdManaBarHeight", 14, 36, 1, LayoutManaBar)
		L2.Dropdown("Value display", "cdManaDisplayFormat", {
			{ value = "numbers", label = "Numbers (1234 / 5678)" },
			{ value = "percent", label = "Percent (56%)" },
			{ value = "both", label = "Both" },
		})
		L2.Slider("Low mana warning threshold (%)", "cdManaWarnThreshold", 0, 50, 1)
		L2.ColorSwatch("Normal color:", "cdColorMana")
		L2.ColorSwatch("Low mana color:", "cdColorManaLow")
		subs.display:SetHeight(-L2.GetY() + 20)
	end

	SelectSub("general")
end
