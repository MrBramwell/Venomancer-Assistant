--[[
	Venomancer Assistant 3.0.0
	(formerly "Brood Marks" - renamed as it's expanded beyond just the
	stack trackers to include the Venom Bar and future Venomancer tools)

	Per-stack icon tracker for two Ascension form-based resources:

	  - Brood Marks: the Venomancer's Spider Form stacking self-buff.
	  - Exposed Flesh: a tank-form (Beetle Form) stacking debuff that
	    needs clearing before it caps.

	Both are detected via UnitBuff("player", i) rather than the native
	GetComboPoints() API (custom Ascension classes generally aren't wired
	into that), and both are gated to the matching shapeshift form - so
	Brood Marks only tracks while you're actually in Spider Form, and
	Exposed Flesh only while in Beetle Form. Only one can be relevant at
	a time anyway, since you can't be in both forms at once, so the
	tracker frame just shows whichever one currently applies and hides
	otherwise.

	The exact buff names and form names are all configurable in the
	options panel rather than hardcoded, since that's the one thing most
	likely to be slightly off if Ascension's actual text differs from
	what's assumed here - fixing that shouldn't require another addon
	update.
]]

local ADDON_NAME = "VenomancerAssistant"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PIP_POOL_MAX = 15 -- generous ceiling; both trackers' max-stack sliders are clamped under this

-- Shown in place of a red question mark before the real buff/debuff icon
-- has ever been seen this session (which is always the case in test
-- mode, unless you've also encountered the real thing). These are
-- thematic placeholders, not necessarily the exact real spell icons -
-- I don't have a reliable way to confirm the literal icon texture path
-- Ascension uses for these two without seeing it live.
local DEFAULT_TRACKER_ICON = {
	bm = "Interface\\Icons\\Ability_Hunter_Pet_Spider",
	ef = "Interface\\Icons\\INV_Misc_MonsterScales_03",
}

local defaults = {
	point = "CENTER", x = 0, y = -220,
	locked = false,
	scale = 1.0,
	iconSize = 28,
	spacing = 4,
	growth = "RIGHT",       -- "RIGHT" or "LEFT"
	showEmpty = true,       -- show dim placeholder slots for marks not yet gained
	-- testMode/testTracker/testCount are internal only now, driven by the
	-- Preview buttons on the Brood Marks/Exposed Flesh tabs (DoPreview) -
	-- no longer exposed as a standalone toggle+picker in their own tab,
	-- since that was a second, inconsistent path to the same "show the
	-- tracker at a given count" behavior Preview already needed.
	testMode = false,
	testCount = 3,
	testTracker = "bm",
	bmPreviewCount = 3,     -- per-tab preview stack count, independent of each other
	efPreviewCount = 7,
	hideOutOfCombat = false,
	minimapButtonShown = true,
	minimapAngle = 225, -- position around the minimap, in degrees

	-- Brood Marks (Spider Form)
	bmEnabled = true, -- turn the whole tracker off, e.g. if only the Venom Bar is wanted
	spiderFormName = "Spider Form",
	buffName = "Brood Mark",
	maxMarks = 5, -- fixed - not user-adjustable, same as Exposed Flesh's cap

	-- Brood Marks max-stack effects. "flashAtMax" (glow) and
	-- "effectPulse" run continuously for as long as you're at max
	-- stacks. The rest fire once, the moment you hit max, and don't
	-- repeat until you drop below and hit it again.
	flashAtMax = true,
	effectPulse = false,
	effectColorFlash = false,
	effectParticleBurst = false,
	effectScreenFlash = false,
	effectSound = false,
	maxColor = { 1, 0.85, 0.2 },  -- gold; used for glow/pulse/color flash/particles/screen flash
	maxSustain = false,           -- keep repeating color flash/particle burst/screen flash every ~0.8s while at max, instead of firing once

	-- Brood Marks early warning tier: fires before you hit max, so you
	-- have time to react. Independent toggle set from the max-stack one.
	bmWarnEnabled = false,
	bmWarnThreshold = 3,
	bmWarnGlow = true,
	bmWarnPulse = false,
	bmWarnColorFlash = false,
	bmWarnParticleBurst = false,
	bmWarnScreenFlash = false,
	bmWarnSound = false,
	bmWarnColor = { 0.3, 0.75, 1 }, -- cyan
	bmWarnSustain = false,

	-- Exposed Flesh (Beetle Form)
	efEnabled = true, -- turn the whole tracker off, e.g. if only the Venom Bar is wanted
	beetleFormName = "Beetle Form",
	efBuffName = "Exposed Flesh",
	efMaxStacks = 10, -- fixed by the game (tooltip confirms "stacking 10 times") - not user-adjustable

	-- Exposed Flesh max-stack effects (same six, own toggles - defaults
	-- lean more "noticeable" than Brood Marks since this one's a warning
	-- to clear, not a reward for stacking).
	efFlashAtMax = true,
	efEffectPulse = false,
	efEffectColorFlash = true,
	efEffectParticleBurst = false,
	efEffectScreenFlash = true,
	efEffectSound = true,
	efMaxColor = { 1, 0.15, 0.15 }, -- red - "clear this now"
	efMaxSustain = true,            -- on by default: this state is urgent enough to keep flashing until it's gone

	-- Exposed Flesh early warning tier: fires before you hit max, so you
	-- have time to react. Independent toggle set from the max-stack one.
	efWarnEnabled = true,
	efWarnThreshold = 7,
	efWarnGlow = true,
	efWarnPulse = false,
	efWarnColorFlash = false,
	efWarnParticleBurst = false,
	efWarnScreenFlash = false,
	efWarnSound = false,
	efWarnColor = { 1, 0.55, 0.1 }, -- orange
	efWarnSustain = false,
}

local function GetDB()
	-- VenomancerAssistant is a rename/expansion of the old "Brood Marks"
	-- addon - if someone's upgrading, pick up their existing settings
	-- from the old saved variable name rather than starting them fresh.
	VenomancerAssistantDB = VenomancerAssistantDB or BroodMarksDB or {}
	for k, v in pairs(defaults) do
		if VenomancerAssistantDB[k] == nil then VenomancerAssistantDB[k] = v end
	end
	-- maxMarks used to be an adjustable slider (1-10) before the real cap
	-- was confirmed at 5 - force it here rather than just defaulting it,
	-- so anyone who'd already customized it away from 5 doesn't keep a
	-- stale value now that it's meant to be fixed.
	VenomancerAssistantDB.maxMarks = 5
	return VenomancerAssistantDB
end

--------------------------------------------------------------------------------
-- Main frame
--------------------------------------------------------------------------------

-- A separate, never-resized anchor holds the actual saved screen
-- position. main (the pip container) always pins its LEFT edge to this
-- anchor's LEFT edge with zero offset - so no matter how wide main gets
-- (5 pips for Brood Marks vs 10 for Exposed Flesh, or any icon size/
-- scale change), the row always starts from the exact same fixed point.
-- Without this indirection, main's own single-point anchor (e.g.
-- "CENTER") would keep that center fixed while resizing, which shifts
-- the left edge - and therefore the whole row - every time the pip
-- count differs between the two trackers.
local anchorFrame = CreateFrame("Frame", "BroodMarksAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local main = CreateFrame("Frame", "BroodMarksFrame", UIParent)
main:SetSize(200, 40)
main:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
main:SetClampedToScreen(true)
main:EnableMouse(false) -- the pip area itself is never the drag handle - see dragHint below

-- A persistent outline around the exact pip area, so while positioning
-- it there's no ambiguity about where the tracker actually sits or how
-- big it is - separate from each individual pip's own small border.
-- Only visible while unlocked; toggled in ApplyLockVisual via alpha
-- rather than Show/Hide, since main's own Show/Hide is already driven
-- by Update()'s tracker logic and shouldn't be fought over by two
-- different systems.
main:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
main:SetBackdropColor(0, 0, 0, 0)
main:SetBackdropBorderColor(1, 0.82, 0, 0)

-- The actual drag handle. Drags anchorFrame (not main directly) - main
-- just follows along live since it's permanently pinned to anchorFrame.
-- Its own anchor point isn't set here (LayoutPips positions it, since
-- where it belongs depends on growth direction - see DRAG_HINT_INFO
-- below).
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
	d.point, _, _, d.x, d.y = anchorFrame:GetPoint()
end)
dragHint:Hide()

local function ApplyLockVisual()
	local d = GetDB()
	local unlocked = not d.locked
	dragHint:EnableMouse(unlocked)
	dragHint:SetShown(unlocked)
	main:SetBackdropColor(0, 0, 0, unlocked and 0.25 or 0)
	main:SetBackdropBorderColor(1, 0.82, 0, unlocked and 0.9 or 0)
end

-- Forward-declared: the actual minimap button is built near the bottom
-- of the file (it needs CreateOptionsPanel, defined later, for its
-- click handler), but the options panel checkbox that toggles it is
-- built here, well before that - referencing minimapButton itself (not
-- yet assigned) is fine since it's only read at click-time, by which
-- point the whole file has finished loading.
local minimapButton
local function ApplyMinimapVisual()
	if minimapButton then
		minimapButton:SetShown(GetDB().minimapButtonShown)
	end
end

--------------------------------------------------------------------------------
-- Icon pips (shared pool - whichever tracker is active lays out however
-- many pips its max stack count needs)
--------------------------------------------------------------------------------

local pips = {}
local lastKnownIcon = {} -- [trackerKey] = icon, remembered per-tracker so test mode has something to show

local function CreatePip(i)
	local p = CreateFrame("Frame", nil, main)
	p:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = false, edgeSize = 8,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	p:SetBackdropColor(0, 0, 0, 0.4)
	p:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

	p.icon = p:CreateTexture(nil, "ARTWORK")
	p.icon:SetPoint("TOPLEFT", 2, -2)
	p.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) -- trim the default icon border artifact

	-- Pulsing glow border, shown for either the max-stack or the
	-- early-warning state; color is set per-frame depending on which.
	p.glow = p:CreateTexture(nil, "OVERLAY")
	p.glow:SetPoint("TOPLEFT", -3, 3)
	p.glow:SetPoint("BOTTOMRIGHT", 3, -3)
	p.glow:SetTexture("Interface\\Cooldown\\star4")
	p.glow:SetBlendMode("ADD")
	p.glow:Hide()

	pips[i] = p
	return p
end

-- Which edge of main is pinned to anchorFrame, matched to growth
-- direction - mirrors the same fixed-anchor-point approach used for the
-- Venom Bar, so the pip row always starts from the same fixed point
-- regardless of direction, pip count, or size.
local TRACKER_GROWTH_INFO = {
	RIGHT = { point = "LEFT", relPoint = "LEFT" },
	LEFT  = { point = "RIGHT", relPoint = "LEFT" },
	DOWN  = { point = "TOP", relPoint = "LEFT" },
	UP    = { point = "BOTTOM", relPoint = "LEFT" },
}

-- Where the drag handle sits relative to main, per direction - always
-- anchored to a corner of main that's entirely fixed for that direction
-- (never a center-point like "TOP", which drifts as the frame resizes),
-- and always at the base the pips grow away from rather than the end
-- that keeps moving. For RIGHT/LEFT growth the row's height never
-- changes, so "above, at the fixed side" works. For UP growth
-- specifically, the base is the *bottom* (pips grow upward from there),
-- so the handle sits below, not above - anchoring it above there would
-- both drift as stack count changed and sit at the wrong end entirely.
local DRAG_HINT_INFO = {
	RIGHT = { hintPoint = "BOTTOMLEFT", mainPoint = "TOPLEFT", x = 0, y = 8 },
	LEFT  = { hintPoint = "BOTTOMRIGHT", mainPoint = "TOPRIGHT", x = 0, y = 8 },
	DOWN  = { hintPoint = "BOTTOMLEFT", mainPoint = "TOPLEFT", x = 0, y = 8 },
	UP    = { hintPoint = "TOPLEFT", mainPoint = "BOTTOMLEFT", x = 0, y = -8 },
}

local function LayoutPips(maxCount)
	local d = GetDB()
	local size = d.iconSize
	local spacing = d.spacing
	local growth = d.growth or "RIGHT"
	local vertical = (growth == "UP" or growth == "DOWN")
	local info = TRACKER_GROWTH_INFO[growth] or TRACKER_GROWTH_INFO.RIGHT

	main:ClearAllPoints()
	main:SetPoint(info.point, anchorFrame, info.relPoint, 0, 0)

	for i = 1, maxCount do
		local p = pips[i] or CreatePip(i)
		p:SetSize(size, size)
		p:ClearAllPoints()
		if i == 1 then
			p:SetPoint(info.point, main, info.point, 0, 0)
		elseif growth == "LEFT" then
			p:SetPoint("RIGHT", pips[i - 1], "LEFT", -spacing, 0)
		elseif growth == "UP" then
			p:SetPoint("BOTTOM", pips[i - 1], "TOP", 0, spacing)
		elseif growth == "DOWN" then
			p:SetPoint("TOP", pips[i - 1], "BOTTOM", 0, -spacing)
		else
			p:SetPoint("LEFT", pips[i - 1], "RIGHT", spacing, 0)
		end
	end
	-- Hide any leftover pips from a previously higher max stack count
	-- (either from switching trackers, or a max-stack slider change).
	for i = maxCount + 1, #pips do
		pips[i]:Hide()
	end
	if vertical then
		main:SetSize(size, math.max(1, maxCount * size + (maxCount - 1) * spacing))
	else
		main:SetSize(math.max(1, maxCount * size + (maxCount - 1) * spacing), size)
	end
	main:SetScale(d.scale)

	local hintInfo = DRAG_HINT_INFO[growth] or DRAG_HINT_INFO.RIGHT
	dragHint:ClearAllPoints()
	dragHint:SetPoint(hintInfo.hintPoint, main, hintInfo.mainPoint, hintInfo.x, hintInfo.y)
end

--------------------------------------------------------------------------------
-- Max/warning effects engine
--
-- Two independent "tiers" can be active at once conceptually (though in
-- practice only one applies per frame): the max-stack tier (both
-- trackers) and the early-warning tier (Exposed Flesh only). Each tier
-- has its own color and its own set of six effect toggles; the engine
-- itself doesn't care which tracker or tier triggered it, it just plays
-- the requested effect in the requested color.
--------------------------------------------------------------------------------

local NORMAL_BORDER = { 1, 1, 1, 1 }
local SOUND_FILE_MAX = "Sound\\Interface\\RaidWarning.wav"
local SOUND_FILE_WARN = "Sound\\Interface\\RaidWarning.wav"
local SUSTAIN_INTERVAL = 0.8 -- how often "sustain until cleared" re-fires color flash/particle burst/screen flash

local colorFlash = { active = false, t = 0, duration = 0.4, color = NORMAL_BORDER }
local screenFlashState = { active = false, t = 0, duration = 0.5, color = NORMAL_BORDER }
local NUM_PARTICLES = 14
local particles = {}

local screenFlashFrame = CreateFrame("Frame", "BroodMarksScreenFlash", UIParent)
screenFlashFrame:SetAllPoints(UIParent)
screenFlashFrame:SetFrameStrata("FULLSCREEN_DIALOG")
screenFlashFrame:EnableMouse(false)
screenFlashFrame:Hide()

local function CreateEdgeBar(setPointsFn)
	local t = screenFlashFrame:CreateTexture(nil, "OVERLAY")
	t:SetTexture(1, 1, 1, 0)
	setPointsFn(t)
	return t
end
local edgeTop = CreateEdgeBar(function(t)
	t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
	t:SetHeight(64)
end)
local edgeBottom = CreateEdgeBar(function(t)
	t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	t:SetHeight(64)
end)
local edgeLeft = CreateEdgeBar(function(t)
	t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
	t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	t:SetWidth(64)
end)
local edgeRight = CreateEdgeBar(function(t)
	t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
	t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
	t:SetWidth(64)
end)
local edgeBars = { edgeTop, edgeBottom, edgeLeft, edgeRight }

local function CreateParticlePool()
	for i = 1, NUM_PARTICLES do
		local p = main:CreateTexture(nil, "OVERLAY")
		p:SetTexture("Interface\\Cooldown\\star4")
		p:SetBlendMode("ADD")
		p:SetSize(16, 16)
		p:SetPoint("CENTER", main, "CENTER", 0, 0)
		particles[i] = { tex = p, active = false, t = 0, duration = 0.55, angle = 0, dist = 0, color = NORMAL_BORDER, originX = 0, originY = 0 }
	end
end
CreateParticlePool()

-- OnUpdate doesn't run on a hidden frame, so any one-shot effect still
-- mid-animation right when main gets hidden (a particle burst, color
-- flash, or screen flash that hasn't finished fading yet) would freeze
-- rather than complete, then reappear still frozen mid-animation the
-- next time main shows again - e.g. a screen-edge flash getting stuck
-- on permanently after a Preview ends. Every main:Hide() call site
-- should call this first so there's nothing left to freeze.
local function ClearInProgressEffects()
	colorFlash.active = false
	screenFlashState.active = false
	screenFlashFrame:Hide()
	for i = 1, NUM_PARTICLES do
		particles[i].active = false
		particles[i].tex:Hide()
	end
end

local function StartParticleBurst(color, maxCount)
	maxCount = math.max(maxCount or 1, 1)
	-- Spread across however many pips are actually shown, spawning from
	-- each pip's own position rather than always bursting from main's
	-- center - a wide multi-mark bar previously looked like the burst
	-- only came from a single mark near the middle, since the burst
	-- radius couldn't reach the outer pips.
	local perPip = math.max(1, math.floor(NUM_PARTICLES / maxCount))
	local mainX, mainY = main:GetCenter()
	local scale = main:GetEffectiveScale()
	local idx = 1
	for pipIndex = 1, maxCount do
		local pip = pips[pipIndex]
		if pip and idx <= NUM_PARTICLES then
			local pipX, pipY = pip:GetCenter()
			-- GetCenter() returns screen-space coordinates, but SetPoint
			-- offsets get multiplied by the parent's effective scale
			-- internally - dividing here converts back to "main's own"
			-- coordinate space so the offset lands in the right spot
			-- regardless of the tracker's current scale setting.
			local offsetX = (pipX and mainX and scale and scale ~= 0) and (pipX - mainX) / scale or 0
			local offsetY = (pipY and mainY and scale and scale ~= 0) and (pipY - mainY) / scale or 0
			for j = 1, perPip do
				if idx > NUM_PARTICLES then break end
				local pt = particles[idx]
				pt.active = true
				pt.t = 0
				pt.color = color
				pt.angle = math.random() * 2 * math.pi
				pt.dist = 18 + math.random() * 18
				pt.originX, pt.originY = offsetX, offsetY
				pt.tex:Show()
				idx = idx + 1
			end
		end
	end
	-- Any leftover particles beyond maxCount*perPip (e.g. NUM_PARTICLES
	-- doesn't divide evenly) just don't get activated this burst - fine,
	-- they're simply unused for this particular trigger.
end

-- flags: { colorFlash=bool, particleBurst=bool, screenFlash=bool, sound=bool }
local function TriggerEffectSet(flags, color, soundFile, maxCount)
	if flags.colorFlash then
		colorFlash.active = true
		colorFlash.t = 0
		colorFlash.color = color
	end
	if flags.particleBurst then
		StartParticleBurst(color, maxCount)
	end
	if flags.screenFlash then
		screenFlashState.active = true
		screenFlashState.t = 0
		screenFlashState.color = color
		screenFlashFrame:Show()
	end
	if flags.sound then
		PlaySoundFile(soundFile, "Master")
	end
end

--------------------------------------------------------------------------------
-- Tracker definitions - the two form-gated resources this addon tracks
--------------------------------------------------------------------------------

local TRACKERS = {
	bm = {
		key = "bm",
		label = "Brood Marks",
		formNameKey = "spiderFormName",
		buffNameKey = "buffName",
		maxKey = "maxMarks",
		maxFlagPrefix = "", -- flashAtMax, effectPulse, effectColorFlash, ...
		hasWarning = true,
		warnFlagPrefix = "bmWarn", -- bmWarnGlow, bmWarnPulse, ...
		warnThresholdKey = "bmWarnThreshold",
		warnEnabledKey = "bmWarnEnabled",
	},
	ef = {
		key = "ef",
		label = "Exposed Flesh",
		formNameKey = "beetleFormName",
		buffNameKey = "efBuffName",
		maxKey = "efMaxStacks",
		maxFlagPrefix = "ef", -- efFlashAtMax, efEffectPulse, efEffectColorFlash, ...
		hasWarning = true,
		warnFlagPrefix = "efWarn", -- efWarnGlow, efWarnPulse, ...
		warnThresholdKey = "efWarnThreshold",
		warnEnabledKey = "efWarnEnabled",
	},
}

local function GetActiveTrackerKey()
	local d = GetDB()
	local function IsEnabled(trackerKey)
		return (trackerKey == "bm" and d.bmEnabled) or (trackerKey == "ef" and d.efEnabled)
	end

	if d.testMode then
		return IsEnabled(d.testTracker) and d.testTracker or nil
	end
	local numForms = GetNumShapeshiftForms()
	for i = 1, numForms do
		local _, name, isActive = GetShapeshiftFormInfo(i)
		if isActive then
			if name == d.spiderFormName then return d.bmEnabled and "bm" or nil end
			if name == d.beetleFormName then return d.efEnabled and "ef" or nil end
			return nil -- some other form entirely, nothing to track
		end
	end
	if not d.locked then
		-- Nothing to actually track right now, but stay visible (showing
		-- all-empty pips, since the real stack count comes back 0) while
		-- unlocked - otherwise there's nothing to see or drag into
		-- position without also flipping test mode on first.
		return IsEnabled(d.testTracker) and d.testTracker or nil
	end
	return nil
end

-- Scans both buffs and debuffs, since not every tracked resource is
-- necessarily coded as a "buff" even if it's beneficial to track -
-- Exposed Flesh in particular is a debuff (it increases damage taken),
-- while Brood Marks is a genuine buff. Trying both means neither tracker
-- needs to hardcode which list its aura lives in.
local function GetStackCount(auraName)
	for i = 1, 40 do
		local name, _, icon, count = UnitBuff("player", i)
		if not name then break end
		if name == auraName then
			return count or 1, icon
		end
	end
	for i = 1, 40 do
		local name, _, icon, count = UnitDebuff("player", i)
		if not name then break end
		if name == auraName then
			return count or 1, icon
		end
	end
	return 0, nil
end

--------------------------------------------------------------------------------
-- Update / effect state machine
--------------------------------------------------------------------------------

local glowElapsed = 0
local currentTrackerKey = nil
local wasAtMax = false
local wasAtWarn = false

-- Re-lays-out using whichever tracker is currently active, for options
-- controls (scale/icon size/spacing/growth) that need to re-flow the
-- pips without necessarily changing max stack count. If no tracker is
-- active right now (e.g. you're not in either form), this is a no-op -
-- Update() will lay out correctly the next time one becomes active.
local function LayoutPipsForCurrent()
	if currentTrackerKey then
		LayoutPips(GetDB()[TRACKERS[currentTrackerKey].maxKey])
	end
end

local function Update()
	local d = GetDB()
	local trackerKey = GetActiveTrackerKey()

	if not trackerKey then
		ClearInProgressEffects()
		main:Hide()
		currentTrackerKey = nil
		main.atMax, main.atWarn = false, false
		return
	end

	local tracker = TRACKERS[trackerKey]
	local buffName = d[tracker.buffNameKey]
	local maxCount = d[tracker.maxKey]
	local count, icon

	if d.testMode then
		count = d.testCount
		icon = lastKnownIcon[trackerKey] or DEFAULT_TRACKER_ICON[trackerKey] or FALLBACK_ICON
	else
		count, icon = GetStackCount(buffName)
		-- Only cache a real, non-empty icon path - a blank/invalid value
		-- coming back from UnitBuff/UnitDebuff (which has happened for
		-- Exposed Flesh specifically) would otherwise get remembered and
		-- render as a blank white square instead of falling through to
		-- a sensible placeholder.
		if icon and icon ~= "" then lastKnownIcon[trackerKey] = icon end
	end

	-- Always re-lay-out for the current max count/icon size/spacing/
	-- growth, not just when the tracker itself changes - otherwise a
	-- settings change (max stacks, icon size, etc.) that doesn't also
	-- happen to switch trackers can leave the bounding box sized for
	-- whatever it was before, out of sync with the pips actually shown.
	LayoutPips(maxCount)

	if trackerKey ~= currentTrackerKey then
		-- Switched trackers (changed form, or test-mode preview changed) -
		-- reset one-shot state so a stale "was at max" from the other
		-- tracker can't suppress the next real trigger.
		wasAtMax = false
		wasAtWarn = false
		currentTrackerKey = trackerKey
	end

	local showIcon = icon or lastKnownIcon[trackerKey] or DEFAULT_TRACKER_ICON[trackerKey] or FALLBACK_ICON

	for i = 1, maxCount do
		local p = pips[i]
		if not p then break end
		local active = i <= count
		if active or d.showEmpty then
			p:Show()
			if active then
				p.icon:SetTexture(showIcon)
				p.icon:Show()
				if not colorFlash.active then
					p:SetBackdropBorderColor(unpack(NORMAL_BORDER))
				end
			else
				p.icon:Hide()
				p:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)
			end
		else
			p:Hide()
		end
	end

	local atMax = count >= maxCount and maxCount > 0
	local atWarn = false
	if tracker.hasWarning and d[tracker.warnEnabledKey] and not atMax then
		atWarn = count >= d[tracker.warnThresholdKey]
	end

	local maxFlags, maxColor, maxSustain
	if trackerKey == "bm" then
		maxFlags = {
			colorFlash = d.effectColorFlash,
			particleBurst = d.effectParticleBurst,
			screenFlash = d.effectScreenFlash,
			sound = d.effectSound,
		}
		maxColor = d.maxColor
		maxSustain = d.maxSustain
	else
		maxFlags = {
			colorFlash = d.efEffectColorFlash,
			particleBurst = d.efEffectParticleBurst,
			screenFlash = d.efEffectScreenFlash,
			sound = d.efEffectSound,
		}
		maxColor = d.efMaxColor
		maxSustain = d.efMaxSustain
	end

	local warnFlags, warnColor, warnSustain
	if tracker.hasWarning then
		if trackerKey == "bm" then
			warnFlags = {
				colorFlash = d.bmWarnColorFlash,
				particleBurst = d.bmWarnParticleBurst,
				screenFlash = d.bmWarnScreenFlash,
				sound = d.bmWarnSound,
			}
			warnColor = d.bmWarnColor
			warnSustain = d.bmWarnSustain
		else
			warnFlags = {
				colorFlash = d.efWarnColorFlash,
				particleBurst = d.efWarnParticleBurst,
				screenFlash = d.efWarnScreenFlash,
				sound = d.efWarnSound,
			}
			warnColor = d.efWarnColor
			warnSustain = d.efWarnSustain
		end
	end

	if atMax and not wasAtMax then
		TriggerEffectSet(maxFlags, maxColor, SOUND_FILE_MAX, maxCount)
	end
	if atWarn and not wasAtWarn then
		TriggerEffectSet(warnFlags, warnColor, SOUND_FILE_WARN, maxCount)
	end
	wasAtMax = atMax
	wasAtWarn = atWarn

	-- Handed to OnUpdate so it can re-fire color flash/particle
	-- burst/screen flash on a timer for as long as the state holds, when
	-- "sustain until cleared" is enabled for that tier.
	main.atMax, main.maxFlags, main.maxColor, main.maxSustain = atMax, maxFlags, maxColor, maxSustain
	main.atWarn, main.warnFlags, main.warnColor, main.warnSustain = atWarn, warnFlags, warnColor, warnSustain

	local glowOn, glowColor, bounceOn
	if trackerKey == "bm" then
		if d.flashAtMax and atMax then
			glowOn, glowColor = true, maxColor
		elseif d.bmWarnGlow and atWarn then
			glowOn, glowColor = true, warnColor
		end
		bounceOn = (d.effectPulse and atMax) or (d.bmWarnPulse and atWarn)
	else
		if d.efFlashAtMax and atMax then
			glowOn, glowColor = true, maxColor
		elseif d.efWarnGlow and atWarn then
			glowOn, glowColor = true, warnColor
		end
		bounceOn = (d.efEffectPulse and atMax) or (d.efWarnPulse and atWarn)
	end

	main.glowing = glowOn
	main.glowColor = glowColor
	main.bouncing = bounceOn
	if not main.glowing then
		for i = 1, maxCount do
			if pips[i] then pips[i].glow:Hide() end
		end
	end
	if not main.bouncing and main.bounceApplied then
		main:SetScale(d.scale)
		main.bounceApplied = false
	end

	-- "Hide when not in combat" stays overridden while unlocked (so you
	-- can still drag/position the frame at will) or while previewing via
	-- test mode - the whole point of that mode is seeing it outside of
	-- combat.
	if d.hideOutOfCombat and d.locked and not d.testMode and not UnitAffectingCombat("player") then
		-- Force-clear any in-progress one-shot effect before hiding, for
		-- the same reason as the early-return path above.
		ClearInProgressEffects()
		main:Hide()
	else
		main:Show()
	end
end

-- Preview shows a tracker at a chosen stack count regardless of real
-- lock/form state, by temporarily borrowing the same test-mode path
-- Update() already uses for that. Reusing that exact pipeline (rather
-- than a separate hand-rolled "just trigger the effects" function, which
-- is what this used to be) is what actually fixes the inconsistency
-- between "preview" and "test" - there's only one rendering/effect path
-- now, so whatever count you preview at naturally produces the same
-- warn/max effects the real thing would at that count, no separate
-- logic to keep in sync.
local previewExpireFrame = CreateFrame("Frame")
local previewExpireElapsed = 0

local function ExpirePreview()
	previewExpireFrame:SetScript("OnUpdate", nil)
	GetDB().testMode = false
	Update()
end

local function DoPreview(trackerKey)
	local d = GetDB()
	local countKey = (trackerKey == "bm") and "bmPreviewCount" or "efPreviewCount"
	d.testMode = true
	d.testTracker = trackerKey
	d.testCount = d[countKey]
	-- Force a fresh rising-edge check every time Preview is clicked, even
	-- if the last preview left things already "at max" - otherwise a
	-- repeat click at the same count wouldn't re-trigger the one-shot
	-- effects, since as far as the tracker's concerned nothing changed.
	wasAtMax = false
	wasAtWarn = false
	Update()

	previewExpireElapsed = 0
	previewExpireFrame:SetScript("OnUpdate", function(self, elapsed)
		previewExpireElapsed = previewExpireElapsed + elapsed
		if previewExpireElapsed >= 2.5 then
			ExpirePreview()
		end
	end)
end

main:SetScript("OnUpdate", function(self, elapsed)
	local d = GetDB()
	glowElapsed = glowElapsed + elapsed
	local maxCount = currentTrackerKey and d[TRACKERS[currentTrackerKey].maxKey] or 0

	-- Glow (continuous)
	if self.glowing and self.glowColor then
		local alpha = 0.5 + 0.5 * math.abs(math.sin(glowElapsed * 3))
		for i = 1, maxCount do
			local p = pips[i]
			if p and p:IsShown() then
				p.glow:Show()
				p.glow:SetVertexColor(self.glowColor[1], self.glowColor[2], self.glowColor[3], 1)
				p.glow:SetAlpha(alpha)
			end
		end
	end

	-- Pulse / scale bounce (continuous)
	if self.bouncing then
		local factor = 1 + 0.06 * math.abs(math.sin(glowElapsed * 4))
		self:SetScale(d.scale * factor)
		self.bounceApplied = true
	end

	-- Color flash (one-shot)
	if colorFlash.active then
		colorFlash.t = colorFlash.t + elapsed
		local progress = math.min(colorFlash.t / colorFlash.duration, 1)
		local c = colorFlash.color
		local r = c[1] + (NORMAL_BORDER[1] - c[1]) * progress
		local g = c[2] + (NORMAL_BORDER[2] - c[2]) * progress
		local b = c[3] + (NORMAL_BORDER[3] - c[3]) * progress
		for i = 1, maxCount do
			local p = pips[i]
			if p and p:IsShown() and p.icon:IsShown() then
				p:SetBackdropBorderColor(r, g, b, 1)
			end
		end
		if progress >= 1 then
			colorFlash.active = false
		end
	end

	-- Particle burst (one-shot, per particle)
	for i = 1, NUM_PARTICLES do
		local pt = particles[i]
		if pt.active then
			pt.t = pt.t + elapsed
			local progress = math.min(pt.t / pt.duration, 1)
			local dist = pt.dist * progress
			pt.tex:ClearAllPoints()
			pt.tex:SetPoint("CENTER", main, "CENTER", pt.originX + math.cos(pt.angle) * dist, pt.originY + math.sin(pt.angle) * dist)
			pt.tex:SetVertexColor(pt.color[1], pt.color[2], pt.color[3], 1 - progress)
			if progress >= 1 then
				pt.active = false
				pt.tex:Hide()
			end
		end
	end

	-- Screen-edge flash (one-shot)
	if screenFlashState.active then
		screenFlashState.t = screenFlashState.t + elapsed
		local progress = math.min(screenFlashState.t / screenFlashState.duration, 1)
		local alpha
		if progress < 0.3 then
			alpha = (progress / 0.3) * 0.8
		else
			alpha = (1 - (progress - 0.3) / 0.7) * 0.8
		end
		local c = screenFlashState.color
		for _, bar in ipairs(edgeBars) do
			bar:SetTexture(c[1], c[2], c[3], alpha)
		end
		if progress >= 1 then
			screenFlashState.active = false
			screenFlashFrame:Hide()
		end
	end

	-- "Sustain until cleared": while a tier's condition holds and its
	-- sustain toggle is on, keep re-firing color flash/particle
	-- burst/screen flash every SUSTAIN_INTERVAL seconds instead of just
	-- once. Sound is deliberately excluded from repeats - a repeating
	-- alarm sound gets old fast; the one initial cue from Update() is
	-- enough.
	if self.atMax and self.maxSustain and self.maxFlags then
		self.maxSustainT = (self.maxSustainT or 0) + elapsed
		if self.maxSustainT >= SUSTAIN_INTERVAL then
			self.maxSustainT = 0
			TriggerEffectSet({
				colorFlash = self.maxFlags.colorFlash,
				particleBurst = self.maxFlags.particleBurst,
				screenFlash = self.maxFlags.screenFlash,
				sound = false,
			}, self.maxColor, SOUND_FILE_MAX, maxCount)
		end
	else
		self.maxSustainT = 0
	end

	if self.atWarn and self.warnSustain and self.warnFlags then
		self.warnSustainT = (self.warnSustainT or 0) + elapsed
		if self.warnSustainT >= SUSTAIN_INTERVAL then
			self.warnSustainT = 0
			TriggerEffectSet({
				colorFlash = self.warnFlags.colorFlash,
				particleBurst = self.warnFlags.particleBurst,
				screenFlash = self.warnFlags.screenFlash,
				sound = false,
			}, self.warnColor, SOUND_FILE_WARN, maxCount)
		end
	else
		self.warnSustainT = 0
	end
end)

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UNIT_AURA")
events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
events:RegisterEvent("PLAYER_REGEN_DISABLED") -- entering combat
events:RegisterEvent("PLAYER_REGEN_ENABLED")  -- leaving combat
events:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then return end
		local d = GetDB()
		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
		ApplyLockVisual()
		ApplyMinimapVisual()
	elseif event == "UNIT_AURA" then
		if arg1 == "player" then Update() end
	else
		Update()
	end
end)

--------------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------------

local PANEL_WIDTH = 520
local PANEL_HEIGHT = 620
local MARGIN = 20
local SCROLLBAR_GUTTER = 26 -- room for UIPanelScrollFrameTemplate's scrollbar
local CONTENT_WIDTH = PANEL_WIDTH - MARGIN * 2 - SCROLLBAR_GUTTER
local COL_WIDTH = (CONTENT_WIDTH - 16) / 2

local ROW_H = 24
local ROW_GAP = 6
local SLIDER_H = 44
local SECTION_HEADER_GAP = 22
local SECTION_HEADER_H = 12

local TAB_ICONS = {
	general = "Interface\\Icons\\Trade_Engineering",
	bm = DEFAULT_TRACKER_ICON.bm,
	ef = DEFAULT_TRACKER_ICON.ef,
}

-- Builds an isolated set of layout helpers targeting a specific content
-- frame, each with its own vertical cursor - so each tab lays itself out
-- independently without stepping on the others.
-- Registered by every interactive control below; re-run each time the
-- options panel is shown, so it reflects state that may have changed
-- through another path (slash commands, form changes, etc.) since it was
-- last open - otherwise a control only ever reflects whatever GetDB()
-- held at the moment it was first created.
local optionsRefreshers = {}

local function CreateLayoutHelpers(target)
	local y = -10

	local function AdvanceY(amount)
		y = y - amount
	end

	local function PlaceLeft(frame, xOffset)
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", target, "TOPLEFT", (xOffset or 0), y)
	end

	local function Section(label)
		AdvanceY(SECTION_HEADER_GAP)
		local header = target:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		PlaceLeft(header)
		header:SetTextColor(1, 0.82, 0)
		header:SetText(label)
		AdvanceY(15)

		local divider = target:CreateTexture(nil, "ARTWORK")
		divider:SetTexture("Interface\\Common\\UI-TooltipDivider-Transparent")
		PlaceLeft(divider, -2)
		divider:SetPoint("RIGHT", target, "RIGHT", 0, 0)
		divider:SetHeight(8)
		AdvanceY(SECTION_HEADER_H)
		return header
	end

	local function Note(text, height)
		local fs = target:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		PlaceLeft(fs, 2)
		fs:SetWidth(CONTENT_WIDTH)
		fs:SetJustifyH("LEFT")
		fs:SetText(text)
		AdvanceY(height or 28)
		return fs
	end

	local function Checkbox(label, key, tooltip, xOffset)
		local check = CreateFrame("CheckButton", "BroodMarksOpt" .. key .. tostring(target), target, "InterfaceOptionsCheckButtonTemplate")
		PlaceLeft(check, xOffset)
		_G[check:GetName() .. "Text"]:SetText(label)
		check:SetChecked(GetDB()[key])
		check:SetScript("OnClick", function(self)
			GetDB()[key] = self:GetChecked() and true or false
			if key == "locked" then ApplyLockVisual() end
			if key == "minimapButtonShown" then ApplyMinimapVisual() end
			Update()
		end)
		if tooltip then
			check:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		table.insert(optionsRefreshers, function() check:SetChecked(GetDB()[key]) end)
		return check
	end

	local function CheckboxRow(label, key, tooltip)
		local check = Checkbox(label, key, tooltip, 0)
		AdvanceY(ROW_H + ROW_GAP)
		return check
	end

	local function CheckboxPair(labelA, keyA, tipA, labelB, keyB, tipB)
		local a = Checkbox(labelA, keyA, tipA, 0)
		local b = Checkbox(labelB, keyB, tipB, COL_WIDTH + 16)
		AdvanceY(ROW_H + ROW_GAP)
		return a, b
	end

	local function Slider(label, key, min, max, step, onChange)
		-- Falls back to min rather than erroring if this key belongs to
		-- another module whose defaults haven't been merged into the
		-- shared saved-variables table yet by the time this tab gets
		-- built - same defensive pattern as ColorSwatch above.
		local function GetVal()
			return GetDB()[key] or min
		end

		local sliderLabel = target:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		PlaceLeft(sliderLabel, 2)
		sliderLabel:SetText(label .. ": " .. tostring(GetVal()))
		AdvanceY(16)

		local slider = CreateFrame("Slider", "BroodMarksOpt" .. key .. tostring(target), target, "OptionsSliderTemplate")
		PlaceLeft(slider, 8)
		slider:SetWidth(CONTENT_WIDTH - 16)
		slider:SetMinMaxValues(min, max)
		if slider.SetValueStep then slider:SetValueStep(step) end
		_G[slider:GetName() .. "Low"]:SetText(tostring(min))
		_G[slider:GetName() .. "High"]:SetText(tostring(max))
		_G[slider:GetName() .. "Text"]:SetText("")
		slider:SetValue(GetVal())
		slider:SetScript("OnValueChanged", function(self, value)
			if step >= 1 then value = math.floor(value + 0.5) else value = math.floor(value / step + 0.5) * step end
			GetDB()[key] = value
			sliderLabel:SetText(label .. ": " .. tostring(value))
			if onChange then onChange(value) end
			Update()
		end)
		AdvanceY(SLIDER_H - 16)
		table.insert(optionsRefreshers, function()
			slider:SetValue(GetVal())
			sliderLabel:SetText(label .. ": " .. tostring(GetVal()))
		end)
		return slider
	end

	local function EditBox(label, key, width)
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		PlaceLeft(lbl, 2)
		lbl:SetText(label)
		AdvanceY(20)

		local box = CreateFrame("EditBox", "BroodMarksOpt" .. key .. tostring(target), target, "InputBoxTemplate")
		box:SetSize(width or 200, 20)
		PlaceLeft(box, 8)
		box:SetAutoFocus(false)
		box:SetText(GetDB()[key] or "")
		box:SetScript("OnEnterPressed", function(self)
			local text = self:GetText()
			if text and text ~= "" then
				GetDB()[key] = text
				Update()
			end
			self:ClearFocus()
		end)
		box:SetScript("OnEscapePressed", function(self) self:SetText(GetDB()[key] or ""); self:ClearFocus() end)
		AdvanceY(28)
		table.insert(optionsRefreshers, function() box:SetText(GetDB()[key] or "") end)
		return box
	end

	local function Button(label, onClick)
		local btn = CreateFrame("Button", nil, target, "UIPanelButtonTemplate")
		btn:SetSize(180, 22)
		PlaceLeft(btn, 0)
		btn:SetText(label)
		btn:SetScript("OnClick", onClick)
		AdvanceY(22 + ROW_GAP)
		return btn
	end

	local function ColorSwatch(label, key, onChange)
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		PlaceLeft(lbl, 2)
		lbl:SetText(label)

		local swatch = CreateFrame("Button", nil, target)
		swatch:SetSize(20, 20)
		swatch:SetPoint("LEFT", lbl, "RIGHT", 12, 0)
		swatch:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 8,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		swatch:SetBackdropBorderColor(0.8, 0.8, 0.8, 1)
		-- Falls back to white rather than erroring if this key belongs to
		-- another module (e.g. the Venom Bar's warning colors) whose own
		-- defaults haven't been merged into the shared saved-variables
		-- table by the time this particular tab gets built - a defensive
		-- safety net, not something that should normally trigger.
		local c = GetDB()[key] or { 1, 1, 1 }
		swatch:SetBackdropColor(c[1], c[2], c[3], 1)

		swatch:SetScript("OnClick", function()
			local original = GetDB()[key] or { 1, 1, 1 }
			local function ApplyColor()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				GetDB()[key] = { r, g, b }
				swatch:SetBackdropColor(r, g, b, 1)
				if onChange then onChange(r, g, b) end
				Update()
			end
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.func = ApplyColor
			ColorPickerFrame.cancelFunc = function()
				GetDB()[key] = original
				swatch:SetBackdropColor(original[1], original[2], original[3], 1)
				if onChange then onChange(original[1], original[2], original[3]) end
				Update()
			end
			ColorPickerFrame:SetColorRGB(original[1], original[2], original[3])
			ShowUIPanel(ColorPickerFrame)
		end)
		swatch:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:SetText("Click to choose a color", nil, nil, nil, nil, true)
			GameTooltip:Show()
		end)
		swatch:SetScript("OnLeave", function() GameTooltip:Hide() end)

		AdvanceY(ROW_H + ROW_GAP)
		table.insert(optionsRefreshers, function()
			local col = GetDB()[key] or { 1, 1, 1 }
			swatch:SetBackdropColor(col[1], col[2], col[3], 1)
		end)
		return swatch
	end

	return {
		AdvanceY = AdvanceY, PlaceLeft = PlaceLeft, Section = Section, Note = Note,
		Checkbox = Checkbox, CheckboxRow = CheckboxRow, CheckboxPair = CheckboxPair,
		Slider = Slider, EditBox = EditBox, Button = Button, ColorSwatch = ColorSwatch,
		GetY = function() return y end,
	}
end

local optionsPanel
local function CreateOptionsPanel()
	if optionsPanel then return optionsPanel end

	local panel = CreateFrame("Frame", "BroodMarksOptionsFrame", UIParent)
	panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true, tileSize = 32, edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("DIALOG")
	panel:Hide()
	tinsert(UISpecialFrames, "BroodMarksOptionsFrame")

	local titleBar = CreateFrame("Frame", nil, panel)
	titleBar:SetPoint("TOPLEFT", 12, -10)
	titleBar:SetPoint("TOPRIGHT", -32, -10)
	titleBar:SetHeight(24)
	titleBar:EnableMouse(true)
	titleBar:RegisterForDrag("LeftButton")
	titleBar:SetScript("OnDragStart", function() panel:StartMoving() end)
	titleBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

	local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	closeBtn:SetPoint("TOPRIGHT", -4, -4)
	closeBtn:SetScript("OnClick", function() panel:Hide() end)

	local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", 4, 0)
	title:SetText("Venomancer Assistant")

	local dragHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dragHint:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 4, -2)
	dragHint:SetText("Drag the title bar to move this window")

	--------------------------------------------------------------------
	-- Tab bar - built dynamically: the tab row's width/positions can't
	-- be finalized until the full tab set is known, and that set now
	-- includes whatever other modules (namely the Venom Bar) register
	-- via RegisterTab below. Content-building happens per-tab as each
	-- is registered; the visual button row is laid out once at the end.
	--------------------------------------------------------------------
	local tabBarY = -68
	local contentTop = tabBarY - 44
	local contentHeight = PANEL_HEIGHT + contentTop - 30

	local tabButtons = {}
	local tabContents = {}
	local tabOrder = {}
	local tabLabels = {}
	local tabIcons = {}

	local function SelectTab(tabKey)
		for key, btn in pairs(tabButtons) do
			local selected = key == tabKey
			btn.selected = selected
			btn.bg:SetTexture(selected and 0.25 or 0.1, selected and 0.22 or 0.1, selected and 0.05 or 0.1, selected and 0.9 or 0.55)
			btn.underline:SetShown(selected)
			btn.label:SetTextColor(selected and 1 or 0.75, selected and 0.82 or 0.75, selected and 0 or 0.75)
			tabContents[key]:GetParent():SetShown(selected)
		end
	end

	-- Registers a tab's metadata and content area (scrollframe + scroll
	-- child), returning the scroll child to build that tab's controls
	-- into. Exposed to other modules via VenomBarModule.BuildOptionsTab
	-- below, so a tab can be added without this file needing to know
	-- about that module ahead of time.
	-- Reskins a UIPanelScrollFrameTemplate's default scrollbar (a fairly
	-- blocky grey Blizzard widget) to something closer to the rest of
	-- this panel's look: the up/down step buttons are hidden (mousewheel
	-- still scrolls fine without them), and the thumb is replaced with a
	-- slim gold bar. Every lookup is nil-guarded - if a sub-widget name
	-- doesn't match what's expected on this client, that piece is just
	-- skipped rather than erroring, consistent with how the rest of this
	-- addon handles uncertain client-specific naming.
	local function SkinScrollBar(scrollFrame)
		local barName = scrollFrame:GetName() .. "ScrollBar"
		local scrollBar = _G[barName]
		if not scrollBar then return end

		local upButton = _G[barName .. "ScrollUpButton"]
		local downButton = _G[barName .. "ScrollDownButton"]
		if upButton then
			upButton:EnableMouse(false)
			upButton:SetAlpha(0)
		end
		if downButton then
			downButton:EnableMouse(false)
			downButton:SetAlpha(0)
		end

		local track = scrollBar:CreateTexture(nil, "BACKGROUND")
		track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
		track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
		track:SetWidth(4)
		track:SetTexture(0, 0, 0, 0.35)

		local thumb = _G[barName .. "ThumbTexture"]
		if thumb then
			thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
			thumb:SetVertexColor(1, 0.82, 0, 0.9)
			thumb:SetWidth(6)
		end
	end

	local function RegisterTab(key, label, icon)
		tabOrder[#tabOrder + 1] = key
		tabLabels[key] = label
		tabIcons[key] = icon

		local scrollFrame = CreateFrame("ScrollFrame", "VenomancerAssistantOptTab" .. key .. "Scroll", panel, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", MARGIN, contentTop)
		scrollFrame:SetSize(CONTENT_WIDTH, contentHeight)
		scrollFrame:Hide()
		SkinScrollBar(scrollFrame)

		local scrollChild = CreateFrame("Frame", nil, scrollFrame)
		scrollChild:SetWidth(CONTENT_WIDTH)
		scrollChild:SetHeight(1) -- grown to fit once the tab's content is laid out
		scrollFrame:SetScrollChild(scrollChild)

		tabContents[key] = scrollChild
		return scrollChild
	end

	--------------------------------------------------------------------
	-- Tab: General (shared frame settings)
	--------------------------------------------------------------------
	do
		local sc = RegisterTab("general", "General", TAB_ICONS.general)
		local L = CreateLayoutHelpers(sc)
		L.Note("Tracks whichever resource matches your current form, and shows one icon per stack. Drag the tracker frame itself to move it while unlocked.")
		L.Section("General")
		L.CheckboxRow("Lock frame position", "locked", "Prevents dragging the tracker and Venom Bar around, and hides the drag handles and bounding box.")
		L.CheckboxRow("Show minimap button", "minimapButtonShown", "Show or hide the draggable minimap icon that opens these options.")

		L.Section("Tracker Appearance (Brood Marks & Exposed Flesh)")
		L.Note("Applies to both trackers - they share one appearance, just like they share the Lock setting above.")
		L.CheckboxRow("Show empty slots (dim placeholders)", "showEmpty", "Show dim, empty pip slots for stacks you haven't gained yet, instead of only showing filled ones.")
		L.CheckboxRow("Hide when not in combat", "hideOutOfCombat", "Hide the tracker entirely while out of combat, even if a tracked form is active. Ignored while unlocked or in test mode, so you can still see it to position it.")
		L.AdvanceY(4)
		L.Slider("Scale", "scale", 0.5, 2.5, 0.05, LayoutPipsForCurrent)
		L.Slider("Icon size", "iconSize", 12, 64, 1, LayoutPipsForCurrent)
		L.Slider("Icon spacing", "spacing", -8, 20, 1, LayoutPipsForCurrent)

		local growthLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		L.PlaceLeft(growthLabel, 2)
		growthLabel:SetText("Growth direction:")
		L.AdvanceY(20)

		local trackerGrowthButtons = {}
		local trackerGrowthOrder = { "RIGHT", "LEFT", "UP", "DOWN" }
		local trackerGrowthLabels = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
		for i, dir in ipairs(trackerGrowthOrder) do
			local btn = CreateFrame("CheckButton", "BroodMarksGrowth" .. dir, sc, "UIRadioButtonTemplate")
			L.PlaceLeft(btn, 2 + (i - 1) * 80)
			_G[btn:GetName() .. "Text"]:SetText(trackerGrowthLabels[dir])
			trackerGrowthButtons[dir] = btn
		end

		local function RefreshGrowthRadios()
			local current = GetDB().growth
			for dir, btn in pairs(trackerGrowthButtons) do
				btn:SetChecked(dir == current)
			end
		end
		for dir, btn in pairs(trackerGrowthButtons) do
			btn:SetScript("OnClick", function()
				GetDB().growth = dir
				RefreshGrowthRadios()
				LayoutPipsForCurrent()
			end)
		end
		RefreshGrowthRadios()
		table.insert(optionsRefreshers, RefreshGrowthRadios)
		sc:SetHeight(-L.GetY() + 20)
	end

	--------------------------------------------------------------------
	-- Tab: Brood Marks
	--------------------------------------------------------------------
	do
		local sc = RegisterTab("bm", "Brood Marks", TAB_ICONS.bm)
		local L = CreateLayoutHelpers(sc)
		L.Note("Tracked while Spider Form is active.")
		L.CheckboxRow("Enable Brood Marks tracking", "bmEnabled", "Turn the whole Brood Marks tracker on or off - useful if you only want the Venom Bar and/or Exposed Flesh.")

		L.Section("Early Warning")
		L.Note("Fires before you hit max, so you have time to react. Independent from the max-stack effects below.")
		L.CheckboxRow("Enable early warning", "bmWarnEnabled", "Turn the whole early-warning tier on or off. When off, only the max-stack effects below will fire.")
		L.Slider("Warn at stack count", "bmWarnThreshold", 1, 4, 1)
		L.ColorSwatch("Warning color:", "bmWarnColor")
		L.CheckboxRow("Sustain until cleared", "bmWarnSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're past the warning threshold, instead of firing once.")
		L.CheckboxPair(
			"Glow border", "bmWarnGlow", "Pulses a glow around each pip once you cross the warning threshold.",
			"Pulse / scale bounce", "bmWarnPulse", "Gentle scale \"breathing\" on the tracker once you cross the warning threshold."
		)
		L.CheckboxPair(
			"Color flash", "bmWarnColorFlash", "Flashes the pip borders when you cross the threshold.",
			"Particle burst", "bmWarnParticleBurst", "Bursts particles from the tracker when you cross the threshold."
		)
		L.CheckboxPair(
			"Screen-edge flash", "bmWarnScreenFlash", "Flashes along the screen edges when you cross the threshold.",
			"Sound cue", "bmWarnSound", "Plays a sound once when you cross the warning threshold."
		)

		L.Section("Max Stack Effects")
		L.Note("Pick any combination. Glow and Pulse run for as long as you're at max stacks; Color flash/Particle burst/Screen flash fire once when you reach it, or keep repeating if \"Sustain\" is on.")
		L.ColorSwatch("Effect color:", "maxColor")
		L.CheckboxRow("Sustain until cleared", "maxSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're at max stacks, instead of firing once.")
		L.CheckboxPair(
			"Glow border", "flashAtMax", "Pulses a glow around each pip while at max stacks.",
			"Pulse / scale bounce", "effectPulse", "Gentle scale \"breathing\" on the tracker while at max stacks."
		)
		L.CheckboxPair(
			"Color flash", "effectColorFlash", "Flashes the pip borders when you reach max stacks.",
			"Particle burst", "effectParticleBurst", "Bursts particles from the tracker when you reach max stacks."
		)
		L.CheckboxPair(
			"Screen-edge flash", "effectScreenFlash", "Flashes along the screen edges when you reach max stacks.",
			"Sound cue", "effectSound", "Plays a sound once when you reach max stacks."
		)

		L.Section("Preview")
		L.Note("Shows the tracker at the chosen count for a few seconds, regardless of form or lock state. Below the warning threshold shows plain stacks, at or past it triggers the warning effects, and reaching 5 triggers the max-stack effects.", 40)
		L.Slider("Preview stack count", "bmPreviewCount", 0, 5, 1)
		L.Button("Preview", function() DoPreview("bm") end)
		sc:SetHeight(-L.GetY() + 20)
	end

	--------------------------------------------------------------------
	-- Tab: Exposed Flesh
	--------------------------------------------------------------------
	do
		local sc = RegisterTab("ef", "Exposed Flesh", TAB_ICONS.ef)
		local L = CreateLayoutHelpers(sc)
		L.Note("Tracked while Beetle Form is active.")
		L.CheckboxRow("Enable Exposed Flesh tracking", "efEnabled", "Turn the whole Exposed Flesh tracker on or off - useful if you only want the Venom Bar and/or Brood Marks.")

		L.Section("Early Warning")
		L.Note("Fires before you hit max, so you have time to clear it. Independent from the max-stack effects below.")
		L.CheckboxRow("Enable early warning", "efWarnEnabled", "Turn the whole early-warning tier on or off. When off, only the max-stack effects below will fire.")
		L.Slider("Warn at stack count", "efWarnThreshold", 1, 9, 1)
		L.ColorSwatch("Warning color:", "efWarnColor")
		L.CheckboxRow("Sustain until cleared", "efWarnSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're past the warning threshold, instead of firing once.")
		L.CheckboxPair(
			"Glow border", "efWarnGlow", "Pulses a glow around each pip once you cross the warning threshold.",
			"Pulse / scale bounce", "efWarnPulse", "Gentle scale \"breathing\" on the tracker once you cross the warning threshold."
		)
		L.CheckboxPair(
			"Color flash", "efWarnColorFlash", "Flashes the pip borders when you cross the threshold.",
			"Particle burst", "efWarnParticleBurst", "Bursts particles from the tracker when you cross the threshold."
		)
		L.CheckboxPair(
			"Screen-edge flash", "efWarnScreenFlash", "Flashes along the screen edges when you cross the threshold.",
			"Sound cue", "efWarnSound", "Plays a sound once when you cross the warning threshold."
		)

		L.Section("Max Stack Effects")
		L.Note("Fires once you actually hit max - time to clear it now.")
		L.ColorSwatch("Max color:", "efMaxColor")
		L.CheckboxRow("Sustain until cleared", "efMaxSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're at max stacks, instead of firing once.")
		L.CheckboxPair(
			"Glow border", "efFlashAtMax", "Pulses a glow around each pip while at max stacks.",
			"Pulse / scale bounce", "efEffectPulse", "Gentle scale \"breathing\" on the tracker while at max stacks."
		)
		L.CheckboxPair(
			"Color flash", "efEffectColorFlash", "Flashes the pip borders when you reach max stacks.",
			"Particle burst", "efEffectParticleBurst", "Bursts particles from the tracker when you reach max stacks."
		)
		L.CheckboxPair(
			"Screen-edge flash", "efEffectScreenFlash", "Flashes along the screen edges when you reach max stacks.",
			"Sound cue", "efEffectSound", "Plays a sound once when you reach max stacks."
		)

		L.Section("Preview")
		L.Note("Shows the tracker at the chosen count for a few seconds, regardless of form or lock state. Below the warning threshold shows plain stacks, at or past it triggers the warning effects, and reaching 10 triggers the max-stack effects.", 40)
		L.Slider("Preview stack count", "efPreviewCount", 0, 10, 1)
		L.Button("Preview", function() DoPreview("ef") end)
		sc:SetHeight(-L.GetY() + 20)
	end

	-- Let other modules (the Venom Bar, and anything added later) add
	-- their own tab now that the built-in ones exist and both this file
	-- and theirs have fully loaded.
	if VenomBarModule and VenomBarModule.BuildOptionsTab then
		VenomBarModule.BuildOptionsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers)
	end
	if VenomBarModule and VenomBarModule.BuildWarningsTab then
		VenomBarModule.BuildWarningsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers)
	end

	-- Now that the full tab set is known, lay out the tab button row.
	local tabWidth = (CONTENT_WIDTH - (#tabOrder - 1) * 6) / #tabOrder
	for i, key in ipairs(tabOrder) do
		local btn = CreateFrame("Button", nil, panel)
		btn:SetSize(tabWidth, 36)
		btn:SetPoint("TOPLEFT", MARGIN + (i - 1) * (tabWidth + 6), tabBarY)

		local bg = btn:CreateTexture(nil, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetTexture(0.1, 0.1, 0.1, 0.55)
		btn.bg = bg

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetSize(18, 18)
		icon:SetPoint("TOP", 0, -4)
		icon:SetTexture(tabIcons[key])
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("BOTTOM", 0, 4)
		label:SetText(tabLabels[key])
		btn.label = label

		local underline = btn:CreateTexture(nil, "OVERLAY")
		underline:SetHeight(2)
		underline:SetPoint("BOTTOMLEFT", 2, 0)
		underline:SetPoint("BOTTOMRIGHT", -2, 0)
		underline:SetTexture(1, 0.82, 0, 1)
		btn.underline = underline

		btn:SetScript("OnEnter", function(self)
			if not self.selected then self.bg:SetTexture(0.18, 0.18, 0.18, 0.7) end
		end)
		btn:SetScript("OnLeave", function(self)
			if not self.selected then self.bg:SetTexture(0.1, 0.1, 0.1, 0.55) end
		end)
		btn:SetScript("OnClick", function() SelectTab(key) end)

		tabButtons[key] = btn
	end

	SelectTab("general")
	panel:SetScript("OnShow", function()
		for _, refresh in ipairs(optionsRefreshers) do
			refresh()
		end
	end)
	optionsPanel = panel
	return panel
end

--------------------------------------------------------------------------------
-- Slash commands
--------------------------------------------------------------------------------

SLASH_VENOMANCERASSISTANT1 = "/venomancer"
SLASH_VENOMANCERASSISTANT2 = "/va"
SLASH_VENOMANCERASSISTANT3 = "/broodmarks" -- legacy aliases, kept for muscle memory
SLASH_VENOMANCERASSISTANT4 = "/bm"
SlashCmdList.VENOMANCERASSISTANT = function(msg)
	msg = (msg or ""):lower()
	local d = GetDB()
	if msg == "lock" then
		d.locked = true
		ApplyLockVisual()
		Update()
		DEFAULT_CHAT_FRAME:AddMessage("|cff40c0ffVenomancer Assistant:|r locked.")
	elseif msg == "unlock" then
		d.locked = false
		ApplyLockVisual()
		Update()
		DEFAULT_CHAT_FRAME:AddMessage("|cff40c0ffVenomancer Assistant:|r unlocked, drag to move.")
	elseif msg == "preview bm" or msg == "previewbm" then
		DoPreview("bm")
		DEFAULT_CHAT_FRAME:AddMessage("|cff40c0ffVenomancer Assistant:|r previewing Brood Marks.")
	elseif msg == "preview ef" or msg == "previewef" then
		DoPreview("ef")
		DEFAULT_CHAT_FRAME:AddMessage("|cff40c0ffVenomancer Assistant:|r previewing Exposed Flesh.")
	elseif msg == "options" or msg == "config" then
		local panel = CreateOptionsPanel()
		if panel:IsShown() then panel:Hide() else panel:Show() end
	else
		DEFAULT_CHAT_FRAME:AddMessage("|cff40c0ffVenomancer Assistant:|r /va lock, /va unlock, /va preview bm, /va preview ef, /va options")
	end
end

-- Deliberately NOT calling CreateOptionsPanel() eagerly here. It's built
-- lazily on first actual open (slash command or minimap click) instead -
-- both of which only happen after every addon file has finished loading,
-- which is what lets VenomBarModule.BuildOptionsTab (in VenomBar.lua,
-- loaded after this file per the .toc) safely add its own tab the very
-- first time the panel is constructed.

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

minimapButton = CreateFrame("Button", "BroodMarksMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("AnyUp")
minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetClampedToScreen(true)

local minimapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("CENTER", 0, 1)
minimapIcon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Spider")
minimapIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetSize(53, 53)
minimapBorder:SetPoint("TOPLEFT")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

-- SetHighlightTexture is a native Button behavior - shows automatically
-- on mouseover and hides on leave, no OnEnter/OnLeave scripting needed.
-- Same texture Blizzard's own minimap tracking buttons use, so it
-- matches the highlight style of everything else around the minimap.
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local highlight = minimapButton:GetHighlightTexture()
highlight:SetSize(30, 30)
highlight:SetPoint("CENTER", 0, 1)

local function UpdateMinimapPosition()
	local angle = math.rad(GetDB().minimapAngle or 225)
	local radius = 80
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

minimapButton:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		GetDB().minimapAngle = math.deg(math.atan2(py - my, px - mx))
		UpdateMinimapPosition()
	end)
end)
minimapButton:SetScript("OnDragStop", function(self)
	self:SetScript("OnUpdate", nil)
end)
minimapButton:SetScript("OnClick", function()
	local panel = CreateOptionsPanel()
	if panel:IsShown() then panel:Hide() else panel:Show() end
end)
minimapButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Venomancer Assistant")
	GameTooltip:AddLine("Click to open options", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Drag to move this button", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

UpdateMinimapPosition()
ApplyMinimapVisual()
