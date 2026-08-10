--[[
	Venomancer Assistant 1.1.0
	Per-stack icon tracker for two Ascension form-based resources:

	  - Brood Marks: the Venomancer's Spider Form stacking self-buff.
	  - Exposed Flesh: a tank-form (Beetle Form) stacking debuff that
	    needs clearing before it caps.
]]

local ADDON_NAME = "VenomancerAssistant"
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PIP_POOL_MAX = 15 -- generous ceiling; both trackers' max-stack sliders are clamped under this

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

local anchorFrame = CreateFrame("Frame", "BroodMarksAnchor", UIParent)
anchorFrame:SetSize(1, 1)
anchorFrame:SetMovable(true)
anchorFrame:SetClampedToScreen(true)

local main = CreateFrame("Frame", "BroodMarksFrame", UIParent)
main:SetSize(200, 40)
main:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
main:SetClampedToScreen(true)
main:EnableMouse(false) -- the pip area itself is never the drag handle - see dragHint below

main:SetBackdrop({
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	edgeSize = 8,
	insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
main:SetBackdropColor(0, 0, 0, 0)
main:SetBackdropBorderColor(1, 0.82, 0, 0)

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


local TRACKER_GROWTH_INFO = {
	RIGHT = { point = "LEFT", relPoint = "LEFT" },
	LEFT  = { point = "RIGHT", relPoint = "LEFT" },
	DOWN  = { point = "TOP", relPoint = "LEFT" },
	UP    = { point = "BOTTOM", relPoint = "LEFT" },
}

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
	local perPip = math.max(1, math.floor(NUM_PARTICLES / maxCount))
	local mainX, mainY = main:GetCenter()
	local scale = main:GetEffectiveScale()
	local idx = 1
	for pipIndex = 1, maxCount do
		local pip = pips[pipIndex]
		if pip and idx <= NUM_PARTICLES then
			local pipX, pipY = pip:GetCenter()
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

		if icon and icon ~= "" then lastKnownIcon[trackerKey] = icon end
	end

	LayoutPips(maxCount)

	if trackerKey ~= currentTrackerKey then

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

	if d.hideOutOfCombat and d.locked and not d.testMode and not UnitAffectingCombat("player") then
		-- Force-clear any in-progress one-shot effect before hiding, for
		-- the same reason as the early-return path above.
		ClearInProgressEffects()
		main:Hide()
	else
		main:Show()
	end
end

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

local PANEL_WIDTH = 780
local PANEL_HEIGHT = 660 -- tall enough that General's content (currently ~504px) fits with headroom to spare for future additions, without needing the scrollbar it still has by default
local SIDEBAR_WIDTH = 170
local TOPBAR_HEIGHT = 56
local MARGIN = 16
local SCROLLBAR_GUTTER = 20
local CONTENT_WIDTH = PANEL_WIDTH - SIDEBAR_WIDTH - MARGIN * 2 - SCROLLBAR_GUTTER
local COL_WIDTH = (CONTENT_WIDTH - 16) / 2

local ROW_H = 22
local ROW_GAP = 8
local SLIDER_H = 40
local SECTION_HEADER_GAP = 22
local SECTION_HEADER_H = 14

local C_BG = { 0.035, 0.035, 0.04, 0.98 }
local C_SIDEBAR_BG = { 0.06, 0.06, 0.07, 1 }
local C_TOPBAR_BG = { 0.05, 0.05, 0.06, 1 }
local C_BORDER = { 0.16, 0.16, 0.18, 1 }
local C_GOLD = { 1, 0.72, 0.15 }
local C_TEXT = { 0.88, 0.88, 0.9 }
local C_TEXT_DIM = { 0.5, 0.5, 0.54 }
local C_ROW_ACTIVE = { 1, 0.72, 0.15, 0.13 }

local TAB_ICONS = {
	general = "Interface\\Icons\\Trade_Engineering",
	bm = DEFAULT_TRACKER_ICON.bm,
	ef = DEFAULT_TRACKER_ICON.ef,
}

local MEDIA_NORM_TEX = "Interface\\AddOns\\VenomancerAssistant\\Media\\normTex.tga"
local MEDIA_CLOSE = "Interface\\AddOns\\VenomancerAssistant\\Media\\close.tga"
local MEDIA_HIGHLIGHT = "Interface\\AddOns\\VenomancerAssistant\\Media\\Highlight.tga"
local MEDIA_ARROW = "Interface\\AddOns\\VenomancerAssistant\\Media\\arrow.tga"


local optionsRefreshers = {}

-- A flat SOLID-color rectangle (borders, dividers, hard backgrounds).
local function FlatTexture(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture("Interface\\Buttons\\WHITE8x8")
	return tex
end


local function GradientTexture(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture(MEDIA_NORM_TEX)
	return tex
end

local function CreateLayoutHelpers(target)
	local y = -8

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
		header:SetWidth(CONTENT_WIDTH)
		header:SetJustifyH("LEFT")
		header:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
		header:SetText(label:upper())

		AdvanceY(28)

		local divider = FlatTexture(target)
		divider:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
		PlaceLeft(divider, -2)
		divider:SetPoint("RIGHT", target, "RIGHT", 0, 0)
		divider:SetHeight(1)
		AdvanceY(SECTION_HEADER_H)
		return header
	end

	local function Note(text, height)
		local fs = target:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
		PlaceLeft(fs, 2)
		fs:SetWidth(CONTENT_WIDTH)
		fs:SetJustifyH("LEFT")
		fs:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])
		fs:SetText(text)
		AdvanceY(height or 28)
		return fs
	end

	-- Flat square toggle: solid gold fill when checked, dark outline
	-- when not - replaces Blizzard's default checkmark-texture checkbox.
	local function Checkbox(label, key, tooltip, xOffset, widthOverride)
		local check = CreateFrame("Button", "VenomancerAssistantOpt" .. key .. tostring(target), target)
		check:SetSize(ROW_H, ROW_H)
		check:RegisterForClicks("LeftButtonUp")
		PlaceLeft(check, xOffset)

		local box = GradientTexture(check, "ARTWORK")
		box:SetPoint("LEFT", 0, 0)
		box:SetSize(15, 15)
		check.box = box

		local boxBorder = CreateFrame("Frame", nil, check)
		boxBorder:SetPoint("TOPLEFT", box, "TOPLEFT", -1, 1)
		boxBorder:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 1, -1)
		boxBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		boxBorder:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", box, "RIGHT", 8, 0)
		text:SetText(label)
		text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])

		check:SetWidth(math.max(widthOverride or (CONTENT_WIDTH - (xOffset or 0)), box:GetWidth() + 8))

		local function Refresh()
			local checked = GetDB()[key]
			if checked then
				box:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
			else
				box:SetVertexColor(0, 0, 0, 0.4)
			end
		end
		Refresh()

		check:SetScript("OnClick", function()
			local d = GetDB()
			d[key] = not d[key]
			Refresh()
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
		table.insert(optionsRefreshers, Refresh)
		return check
	end

	local function CheckboxRow(label, key, tooltip)
		local check = Checkbox(label, key, tooltip, 0)
		AdvanceY(ROW_H + ROW_GAP)
		return check
	end

	local function CheckboxPair(labelA, keyA, tipA, labelB, keyB, tipB)
		local a = Checkbox(labelA, keyA, tipA, 0, COL_WIDTH)
		local b = Checkbox(labelB, keyB, tipB, COL_WIDTH + 16, COL_WIDTH)
		AdvanceY(ROW_H + ROW_GAP)
		return a, b
	end

	-- Thin flat track + small gold square thumb, replacing
	-- OptionsSliderTemplate's dated beveled look.
	local function Slider(label, key, min, max, step, onChange)
		local function GetVal()
			return GetDB()[key] or min
		end

		local sliderLabel = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(sliderLabel, 2)
		sliderLabel:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		sliderLabel:SetText(label .. ": " .. tostring(GetVal()))
		AdvanceY(16)

		local slider = CreateFrame("Slider", "VenomancerAssistantOpt" .. key .. tostring(target), target)
		slider:SetOrientation("HORIZONTAL")
		PlaceLeft(slider, 2)
		slider:SetWidth(CONTENT_WIDTH - 4)
		slider:SetHeight(14)
		slider:SetHitRectInsets(0, 0, -6, -6)
		slider:SetMinMaxValues(min, max)
		if slider.SetValueStep then slider:SetValueStep(step) end

		local track = FlatTexture(slider, "BACKGROUND")
		track:SetPoint("LEFT", 0, 0)
		track:SetPoint("RIGHT", 0, 0)
		track:SetHeight(3)
		track:SetVertexColor(1, 1, 1, 0.12)

		local thumb = GradientTexture(slider, "OVERLAY")
		thumb:SetSize(12, 12)
		thumb:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
		slider:SetThumbTexture(thumb)

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
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(lbl, 2)
		lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		lbl:SetText(label)
		AdvanceY(20)

		local box = CreateFrame("EditBox", "VenomancerAssistantOpt" .. key .. tostring(target), target, "InputBoxTemplate")
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

	-- Flat pill button: dark fill, thin border, gold text, subtle
	-- lighten-on-hover - replacing UIPanelButtonTemplate's 3D bevel.
	local function Button(label, onClick)
		local btn = CreateFrame("Button", nil, target)
		btn:SetSize(180, 24)
		btn:RegisterForClicks("LeftButtonUp")
		PlaceLeft(btn, 0)

		local bg = GradientTexture(btn, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetVertexColor(1, 1, 1, 0.05)
		btn.bg = bg

		local border = CreateFrame("Frame", nil, btn)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture(MEDIA_HIGHLIGHT)
		highlight:SetAllPoints()
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(0.25)
		btn:SetHighlightTexture(highlight)

		local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
		text:SetText(label)
		text:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])

		btn:SetScript("OnClick", onClick)

		AdvanceY(24 + ROW_GAP)
		return btn
	end

	local function ColorSwatch(label, key, onChange)
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(lbl, 2)
		lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		lbl:SetText(label)

		local swatch = CreateFrame("Button", nil, target)
		swatch:SetSize(18, 18)
		swatch:RegisterForClicks("LeftButtonUp")
		swatch:SetPoint("LEFT", lbl, "RIGHT", 12, 0)

		local fill = FlatTexture(swatch, "ARTWORK")
		fill:SetAllPoints()
		local border = CreateFrame("Frame", nil, swatch)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		-- Falls back to white rather than erroring if this key belongs to
		-- another module whose defaults haven't been merged into the
		-- shared saved-variables table yet by the time this tab is built.
		local c = GetDB()[key] or { 1, 1, 1 }
		fill:SetVertexColor(c[1], c[2], c[3], 1)

		swatch:SetScript("OnClick", function()
			local original = GetDB()[key] or { 1, 1, 1 }
			local function ApplyColor()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				GetDB()[key] = { r, g, b }
				fill:SetVertexColor(r, g, b, 1)
				if onChange then onChange(r, g, b) end
				Update()
			end
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.func = ApplyColor
			ColorPickerFrame.cancelFunc = function()
				GetDB()[key] = original
				fill:SetVertexColor(original[1], original[2], original[3], 1)
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
			fill:SetVertexColor(col[1], col[2], col[3], 1)
		end)
		return swatch
	end


	local function Dropdown(label, key, options, onChange)
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(lbl, 2)
		lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		lbl:SetText(label)
		AdvanceY(18)

		local ddButton = CreateFrame("Button", nil, target)
		ddButton:SetSize(200, 24)
		ddButton:RegisterForClicks("LeftButtonUp")
		PlaceLeft(ddButton, 2)

		local bg = GradientTexture(ddButton, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetVertexColor(1, 1, 1, 0.07)

		local border = CreateFrame("Frame", nil, ddButton)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local ddHighlight = ddButton:CreateTexture(nil, "HIGHLIGHT")
		ddHighlight:SetTexture(MEDIA_HIGHLIGHT)
		ddHighlight:SetAllPoints()
		ddHighlight:SetBlendMode("ADD")
		ddHighlight:SetAlpha(0.15)
		ddButton:SetHighlightTexture(ddHighlight)

		local selectedText = ddButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		selectedText:SetPoint("LEFT", 10, 0)
		selectedText:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])

		local arrow = ddButton:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(10, 10)
		arrow:SetPoint("RIGHT", -8, 0)
		arrow:SetTexture(MEDIA_ARROW)
		arrow:SetTexCoord(0, 1, 1, 0) -- arrow.tga points up; flip vertically so closed = points down
		arrow:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)

		local rowHeight = 22
		local listFrame = CreateFrame("Frame", nil, UIParent)
		listFrame:SetFrameStrata("TOOLTIP")
		listFrame:SetWidth(200)
		listFrame:SetHeight(rowHeight * #options)
		listFrame:Hide()
		local listBG = FlatTexture(listFrame, "BACKGROUND")
		listBG:SetAllPoints()
		listBG:SetVertexColor(C_BG[1], C_BG[2], C_BG[3], 1)
		local listBorder = CreateFrame("Frame", nil, listFrame)
		listBorder:SetAllPoints()
		listBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		listBorder:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local function CloseList()
			listFrame:Hide()
			arrow:SetTexCoord(0, 1, 1, 0)
		end

		for i, opt in ipairs(options) do
			local row = CreateFrame("Button", nil, listFrame)
			row:SetSize(200, rowHeight)
			row:SetPoint("TOP", 0, -(i - 1) * rowHeight)
			row:RegisterForClicks("LeftButtonUp")

			local rowHighlight = row:CreateTexture(nil, "HIGHLIGHT")
			rowHighlight:SetTexture(MEDIA_HIGHLIGHT)
			rowHighlight:SetAllPoints()
			rowHighlight:SetBlendMode("ADD")
			rowHighlight:SetAlpha(0.2)
			row:SetHighlightTexture(rowHighlight)

			local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			rowText:SetPoint("LEFT", 10, 0)
			rowText:SetText(opt.label)
			rowText:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])

			row:SetScript("OnClick", function()
				GetDB()[key] = opt.value
				selectedText:SetText(opt.label)
				CloseList()
				if onChange then onChange(opt.value) end
				Update()
			end)
		end

		ddButton:SetScript("OnClick", function()
			if listFrame:IsShown() then
				CloseList()
			else
				listFrame:ClearAllPoints()
				listFrame:SetPoint("TOP", ddButton, "BOTTOM", 0, -2)
				listFrame:Show()
				arrow:SetTexCoord(0, 1, 0, 1) -- open = points up
			end
		end)

		local function Refresh()
			local current = GetDB()[key]
			for _, opt in ipairs(options) do
				if opt.value == current then selectedText:SetText(opt.label) end
			end
		end
		Refresh()
		table.insert(optionsRefreshers, Refresh)
		-- Close along with the whole options panel, rather than leaving
		-- an orphaned floating list up if the panel gets hidden while a
		-- dropdown happens to be open.
		table.insert(optionsRefreshers, CloseList)

		AdvanceY(24 + ROW_GAP)
		return ddButton
	end

	return {
		AdvanceY = AdvanceY, PlaceLeft = PlaceLeft, Section = Section, Note = Note,
		Checkbox = Checkbox, CheckboxRow = CheckboxRow, CheckboxPair = CheckboxPair,
		Slider = Slider, EditBox = EditBox, Button = Button, ColorSwatch = ColorSwatch,
		Dropdown = Dropdown,
		GetY = function() return y end,
	}
end


local function CreateSubTabPager(container, defs, startY)
	startY = startY or 0
	local PILL_HEIGHT = 26
	local PILL_GAP = 6
	local pillWidth = (CONTENT_WIDTH - (#defs - 1) * PILL_GAP) / #defs

	local subButtons = {}
	local subContents = {}

	for i, def in ipairs(defs) do
		local btn = CreateFrame("Button", nil, container)
		btn:SetSize(pillWidth, PILL_HEIGHT)
		btn:SetPoint("TOPLEFT", (i - 1) * (pillWidth + PILL_GAP), startY)
		btn:RegisterForClicks("LeftButtonUp")

		local bg = GradientTexture(btn, "BACKGROUND")
		bg:SetAllPoints()

		local border = CreateFrame("Frame", nil, btn)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture(MEDIA_HIGHLIGHT)
		highlight:SetAllPoints()
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(0.15)
		btn:SetHighlightTexture(highlight)

		local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("CENTER")
		text:SetText(def.label)

		btn.bg = bg
		btn.text = text
		subButtons[def.key] = btn

		local content = CreateFrame("Frame", nil, container)
		content:SetPoint("TOPLEFT", 0, startY - (PILL_HEIGHT + 14))
		content:SetWidth(CONTENT_WIDTH)
		content:SetHeight(1) -- grown to fit once that sub-tab's content is laid out
		content:Hide()
		subContents[def.key] = content
	end

	local function SelectSub(key)
		for k, btn in pairs(subButtons) do
			local selected = k == key
			if selected then
				btn.bg:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.85)
				btn.text:SetTextColor(0, 0, 0)
			else
				btn.bg:SetVertexColor(1, 1, 1, 0.06)
				btn.text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
			end
			subContents[k]:SetShown(selected)
		end

		container:SetHeight(-startY + PILL_HEIGHT + 14 + subContents[key]:GetHeight() + 20)
	end

	for key, btn in pairs(subButtons) do
		btn:SetScript("OnClick", function() SelectSub(key) end)
	end

	return subContents, SelectSub
end

local function SkinScrollBar(scrollFrame)
	local barName = scrollFrame:GetName() .. "ScrollBar"
	local scrollBar = _G[barName]
	if not scrollBar then return end

	local upButton = _G[barName .. "ScrollUpButton"]
	local downButton = _G[barName .. "ScrollDownButton"]
	if upButton then upButton:EnableMouse(false); upButton:SetAlpha(0) end
	if downButton then downButton:EnableMouse(false); downButton:SetAlpha(0) end

	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
	track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
	track:SetWidth(3)
	track:SetTexture(1, 1, 1, 0.08)

	local thumb = _G[barName .. "ThumbTexture"]
	if thumb then
		thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
		thumb:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.85)
		thumb:SetWidth(5)
	end
end

local optionsPanel
local function CreateOptionsPanel()
	if optionsPanel then return optionsPanel end

	local panel = CreateFrame("Frame", "BroodMarksOptionsFrame", UIParent)
	panel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	panel:SetPoint("CENTER")
	panel:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	panel:SetBackdropColor(C_BG[1], C_BG[2], C_BG[3], C_BG[4])
	panel:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)
	panel:SetMovable(true)
	panel:SetClampedToScreen(true)
	panel:SetFrameStrata("DIALOG")
	panel:Hide()
	tinsert(UISpecialFrames, "BroodMarksOptionsFrame")

	--------------------------------------------------------------------
	-- Top bar: title (draggable), Lock toggle pill, close button
	--------------------------------------------------------------------
	local topBar = CreateFrame("Frame", nil, panel)
	topBar:SetPoint("TOPLEFT", 0, 0)
	topBar:SetPoint("TOPRIGHT", 0, 0)
	topBar:SetHeight(TOPBAR_HEIGHT)
	local topBarBG = FlatTexture(topBar, "BACKGROUND")
	topBarBG:SetAllPoints()
	topBarBG:SetVertexColor(C_TOPBAR_BG[1], C_TOPBAR_BG[2], C_TOPBAR_BG[3], 1)
	local topBarLine = FlatTexture(topBar, "ARTWORK")
	topBarLine:SetPoint("BOTTOMLEFT", 0, 0)
	topBarLine:SetPoint("BOTTOMRIGHT", 0, 0)
	topBarLine:SetHeight(1)
	topBarLine:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

	topBar:EnableMouse(true)
	topBar:RegisterForDrag("LeftButton")
	topBar:SetScript("OnDragStart", function() panel:StartMoving() end)
	topBar:SetScript("OnDragStop", function() panel:StopMovingOrSizing() end)

	local title = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -8)
	title:SetText("Venomancer Assistant")
	title:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])

	local dragHintText = topBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	dragHintText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
	dragHintText:SetText("Drag the title bar to move this window")
	dragHintText:SetTextColor(C_TEXT_DIM[1], C_TEXT_DIM[2], C_TEXT_DIM[3])

	local closeBtn = CreateFrame("Button", nil, topBar)
	closeBtn:SetSize(20, 20)
	closeBtn:RegisterForClicks("LeftButtonUp")
	closeBtn:SetPoint("RIGHT", -12, 0)
	local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
	closeIcon:SetAllPoints()
	closeIcon:SetTexture(MEDIA_CLOSE)
	closeIcon:SetVertexColor(0.7, 0.7, 0.72, 1)
	local closeHighlight = closeBtn:CreateTexture(nil, "HIGHLIGHT")
	closeHighlight:SetAllPoints()
	closeHighlight:SetTexture(MEDIA_CLOSE)
	closeHighlight:SetVertexColor(0.9, 0.25, 0.25, 1)
	closeBtn:SetHighlightTexture(closeHighlight)
	closeBtn:SetScript("OnClick", function() panel:Hide() end)


	local lockPill = CreateFrame("Button", nil, topBar)
	lockPill:SetSize(84, 24)
	lockPill:RegisterForClicks("LeftButtonUp")
	lockPill:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
	local lockBG = GradientTexture(lockPill, "ARTWORK")
	lockBG:SetAllPoints()
	local lockHighlight = lockPill:CreateTexture(nil, "HIGHLIGHT")
	lockHighlight:SetTexture(MEDIA_HIGHLIGHT)
	lockHighlight:SetAllPoints()
	lockHighlight:SetBlendMode("ADD")
	lockHighlight:SetAlpha(0.2)
	lockPill:SetHighlightTexture(lockHighlight)
	local lockText = lockPill:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	lockText:SetPoint("CENTER")

	local function RefreshLockPill()
		local locked = GetDB().locked
		lockBG:SetVertexColor(locked and C_GOLD[1] or 1, locked and C_GOLD[2] or 1, locked and C_GOLD[3] or 1, locked and 0.85 or 0.08)
		lockText:SetText(locked and "Locked" or "Unlocked")
		lockText:SetTextColor(locked and 0 or C_TEXT[1], locked and 0 or C_TEXT[2], locked and 0 or C_TEXT[3])
	end
	RefreshLockPill()
	lockPill:SetScript("OnClick", function()
		local d = GetDB()
		d.locked = not d.locked
		ApplyLockVisual()
		Update()
		RefreshLockPill()
	end)
	table.insert(optionsRefreshers, RefreshLockPill)

	--------------------------------------------------------------------
	-- Sidebar navigation
	--------------------------------------------------------------------
	local sidebar = CreateFrame("Frame", nil, panel)
	sidebar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, 0)
	sidebar:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, 0)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	local sidebarBG = FlatTexture(sidebar, "BACKGROUND")
	sidebarBG:SetAllPoints()
	sidebarBG:SetVertexColor(C_SIDEBAR_BG[1], C_SIDEBAR_BG[2], C_SIDEBAR_BG[3], 1)
	local sidebarLine = FlatTexture(sidebar, "ARTWORK")
	sidebarLine:SetPoint("TOPRIGHT", 0, 0)
	sidebarLine:SetPoint("BOTTOMRIGHT", 0, 0)
	sidebarLine:SetWidth(1)
	sidebarLine:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

	local navButtons = {}
	local tabContents = {}
	local tabOrder = {}
	local tabLabels = {}
	local tabIcons = {}

	local function SelectTab(tabKey)
		for key, btn in pairs(navButtons) do
			local selected = key == tabKey
			btn.selected = selected
			if selected then
				btn.bg:SetVertexColor(C_ROW_ACTIVE[1], C_ROW_ACTIVE[2], C_ROW_ACTIVE[3], C_ROW_ACTIVE[4])
				btn.stripe:Show()
				btn.text:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])
			else
				btn.bg:SetVertexColor(0, 0, 0, 0)
				btn.stripe:Hide()
				btn.text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
			end
			tabContents[key]:GetParent():SetShown(selected)
		end
	end

	local contentHeight = PANEL_HEIGHT - TOPBAR_HEIGHT - 24


	local function RegisterTab(key, label, icon)
		tabOrder[#tabOrder + 1] = key
		tabLabels[key] = label
		tabIcons[key] = icon

		local scrollFrame = CreateFrame("ScrollFrame", "VenomancerAssistantOptTab" .. key .. "Scroll", panel, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", MARGIN, -12)
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

	-- Tab: General (shared frame settings)
	--------------------------------------------------------------------
	do
		local sc = RegisterTab("general", "General", TAB_ICONS.general)
		local L = CreateLayoutHelpers(sc)
		L.Note("Tracks whichever resource matches your current form, and shows one icon per stack. Drag the tracker frame itself to move it while unlocked.")
		L.Section("General")
		L.Note("Lock/unlock is now the pill button at the top of this window, next to Close - it applies to the tracker, the Venom Bar, and the warning text all at once.")
		L.CheckboxRow("Show minimap button", "minimapButtonShown", "Show or hide the draggable minimap icon that opens these options.")

		L.Section("Tracker Appearance (Brood Marks & Exposed Flesh)")
		L.Note("Applies to both trackers - they share one appearance, just like they share the Lock setting above.")
		L.CheckboxRow("Show empty slots (dim placeholders)", "showEmpty", "Show dim, empty pip slots for stacks you haven't gained yet, instead of only showing filled ones.")
		L.CheckboxRow("Hide when not in combat", "hideOutOfCombat", "Hide the tracker entirely while out of combat, even if a tracked form is active. Ignored while unlocked or in test mode, so you can still see it to position it.")
		L.AdvanceY(4)
		L.Slider("Scale", "scale", 0.5, 2.5, 0.05, LayoutPipsForCurrent)
		L.Slider("Icon size", "iconSize", 12, 64, 1, LayoutPipsForCurrent)
		L.Slider("Icon spacing", "spacing", -8, 20, 1, LayoutPipsForCurrent)

		L.Dropdown("Growth direction", "growth", {
			{ value = "RIGHT", label = "Right" },
			{ value = "LEFT", label = "Left" },
			{ value = "UP", label = "Up" },
			{ value = "DOWN", label = "Down" },
		}, LayoutPipsForCurrent)
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

		local subs, SelectSub = CreateSubTabPager(sc, {
			{ key = "warn", label = "Early Warning" },
			{ key = "max", label = "Max Stacks" },
			{ key = "preview", label = "Preview" },
		}, L.GetY())

		do
			local L2 = CreateLayoutHelpers(subs.warn)
			L2.Note("Fires before you hit max, so you have time to react. Independent from the max-stack effects on the other tab.")
			L2.CheckboxRow("Enable early warning", "bmWarnEnabled", "Turn the whole early-warning tier on or off. When off, only the max-stack effects will fire.")
			L2.Slider("Warn at stack count", "bmWarnThreshold", 1, 4, 1)
			L2.ColorSwatch("Warning color:", "bmWarnColor")
			L2.CheckboxRow("Sustain until cleared", "bmWarnSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're past the warning threshold, instead of firing once.")
			L2.CheckboxPair(
				"Glow border", "bmWarnGlow", "Pulses a glow around each pip once you cross the warning threshold.",
				"Pulse / scale bounce", "bmWarnPulse", "Gentle scale \"breathing\" on the tracker once you cross the warning threshold."
			)
			L2.CheckboxPair(
				"Color flash", "bmWarnColorFlash", "Flashes the pip borders when you cross the threshold.",
				"Particle burst", "bmWarnParticleBurst", "Bursts particles from the tracker when you cross the threshold."
			)
			L2.CheckboxPair(
				"Screen-edge flash", "bmWarnScreenFlash", "Flashes along the screen edges when you cross the threshold.",
				"Sound cue", "bmWarnSound", "Plays a sound once when you cross the warning threshold."
			)
			subs.warn:SetHeight(-L2.GetY() + 20)
		end

		do
			local L2 = CreateLayoutHelpers(subs.max)
			L2.Note("Pick any combination. Glow and Pulse run for as long as you're at max stacks; Color flash/Particle burst/Screen flash fire once when you reach it, or keep repeating if \"Sustain\" is on.")
			L2.ColorSwatch("Effect color:", "maxColor")
			L2.CheckboxRow("Sustain until cleared", "maxSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're at max stacks, instead of firing once.")
			L2.CheckboxPair(
				"Glow border", "flashAtMax", "Pulses a glow around each pip while at max stacks.",
				"Pulse / scale bounce", "effectPulse", "Gentle scale \"breathing\" on the tracker while at max stacks."
			)
			L2.CheckboxPair(
				"Color flash", "effectColorFlash", "Flashes the pip borders when you reach max stacks.",
				"Particle burst", "effectParticleBurst", "Bursts particles from the tracker when you reach max stacks."
			)
			L2.CheckboxPair(
				"Screen-edge flash", "effectScreenFlash", "Flashes along the screen edges when you reach max stacks.",
				"Sound cue", "effectSound", "Plays a sound once when you reach max stacks."
			)
			subs.max:SetHeight(-L2.GetY() + 20)
		end

		do
			local L2 = CreateLayoutHelpers(subs.preview)
			L2.Note("Shows the tracker at the chosen count for a few seconds, regardless of form or lock state. Below the warning threshold shows plain stacks, at or past it triggers the warning effects, and reaching 5 triggers the max-stack effects.", 54)
			L2.Slider("Preview stack count", "bmPreviewCount", 0, 5, 1)
			L2.Button("Preview", function() DoPreview("bm") end)
			subs.preview:SetHeight(-L2.GetY() + 20)
		end

		SelectSub("warn")
	end

	--------------------------------------------------------------------
	-- Tab: Exposed Flesh
	--------------------------------------------------------------------
	do
		local sc = RegisterTab("ef", "Exposed Flesh", TAB_ICONS.ef)
		local L = CreateLayoutHelpers(sc)
		L.Note("Tracked while Beetle Form is active.")
		L.CheckboxRow("Enable Exposed Flesh tracking", "efEnabled", "Turn the whole Exposed Flesh tracker on or off - useful if you only want the Venom Bar and/or Brood Marks.")

		local subs, SelectSub = CreateSubTabPager(sc, {
			{ key = "warn", label = "Early Warning" },
			{ key = "max", label = "Max Stacks" },
			{ key = "preview", label = "Preview" },
		}, L.GetY())

		do
			local L2 = CreateLayoutHelpers(subs.warn)
			L2.Note("Fires before you hit max, so you have time to clear it. Independent from the max-stack effects on the other tab.")
			L2.CheckboxRow("Enable early warning", "efWarnEnabled", "Turn the whole early-warning tier on or off. When off, only the max-stack effects will fire.")
			L2.Slider("Warn at stack count", "efWarnThreshold", 1, 9, 1)
			L2.ColorSwatch("Warning color:", "efWarnColor")
			L2.CheckboxRow("Sustain until cleared", "efWarnSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're past the warning threshold, instead of firing once.")
			L2.CheckboxPair(
				"Glow border", "efWarnGlow", "Pulses a glow around each pip once you cross the warning threshold.",
				"Pulse / scale bounce", "efWarnPulse", "Gentle scale \"breathing\" on the tracker once you cross the warning threshold."
			)
			L2.CheckboxPair(
				"Color flash", "efWarnColorFlash", "Flashes the pip borders when you cross the threshold.",
				"Particle burst", "efWarnParticleBurst", "Bursts particles from the tracker when you cross the threshold."
			)
			L2.CheckboxPair(
				"Screen-edge flash", "efWarnScreenFlash", "Flashes along the screen edges when you cross the threshold.",
				"Sound cue", "efWarnSound", "Plays a sound once when you cross the warning threshold."
			)
			subs.warn:SetHeight(-L2.GetY() + 20)
		end

		do
			local L2 = CreateLayoutHelpers(subs.max)
			L2.Note("Fires once you actually hit max - time to clear it now.")
			L2.ColorSwatch("Max color:", "efMaxColor")
			L2.CheckboxRow("Sustain until cleared", "efMaxSustain", "Keep repeating color flash, particle burst, and screen flash every ~0.8s for as long as you're at max stacks, instead of firing once.")
			L2.CheckboxPair(
				"Glow border", "efFlashAtMax", "Pulses a glow around each pip while at max stacks.",
				"Pulse / scale bounce", "efEffectPulse", "Gentle scale \"breathing\" on the tracker while at max stacks."
			)
			L2.CheckboxPair(
				"Color flash", "efEffectColorFlash", "Flashes the pip borders when you reach max stacks.",
				"Particle burst", "efEffectParticleBurst", "Bursts particles from the tracker when you reach max stacks."
			)
			L2.CheckboxPair(
				"Screen-edge flash", "efEffectScreenFlash", "Flashes along the screen edges when you reach max stacks.",
				"Sound cue", "efEffectSound", "Plays a sound once when you reach max stacks."
			)
			subs.max:SetHeight(-L2.GetY() + 20)
		end

		do
			local L2 = CreateLayoutHelpers(subs.preview)
			L2.Note("Shows the tracker at the chosen count for a few seconds, regardless of form or lock state. Below the warning threshold shows plain stacks, at or past it triggers the warning effects, and reaching 10 triggers the max-stack effects.", 54)
			L2.Slider("Preview stack count", "efPreviewCount", 0, 10, 1)
			L2.Button("Preview", function() DoPreview("ef") end)
			subs.preview:SetHeight(-L2.GetY() + 20)
		end

		SelectSub("warn")
	end

	-- Let other modules (the Venom Bar, and anything added later) add
	-- their own tab now that the built-in ones exist and both this file
	-- and theirs have fully loaded.
	if VenomBarModule and VenomBarModule.BuildOptionsTab then
		VenomBarModule.BuildOptionsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers, CreateSubTabPager)
	end
	if VenomBarModule and VenomBarModule.BuildWarningsTab then
		VenomBarModule.BuildWarningsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers, CreateSubTabPager)
	end

	-- Now that the full nav set is known (built-in pages plus whatever
	-- other modules added above), lay out the sidebar buttons themselves.
	local navY = -10
	for _, key in ipairs(tabOrder) do
		local btn = CreateFrame("Button", nil, sidebar)
		btn:RegisterForClicks("LeftButtonUp")
		btn:SetPoint("TOPLEFT", 0, navY)
		btn:SetPoint("TOPRIGHT", 0, navY)
		btn:SetHeight(34)

		local bg = GradientTexture(btn, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetVertexColor(0, 0, 0, 0)
		btn.bg = bg

		local stripe = FlatTexture(btn, "ARTWORK")
		stripe:SetPoint("TOPLEFT", 0, 0)
		stripe:SetPoint("BOTTOMLEFT", 0, 0)
		stripe:SetWidth(2)
		stripe:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
		stripe:Hide()
		btn.stripe = stripe

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetSize(18, 18)
		icon:SetPoint("LEFT", 14, 0)
		icon:SetTexture(tabIcons[key])
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		text:SetText(tabLabels[key])
		btn.text = text

		local navHighlight = btn:CreateTexture(nil, "HIGHLIGHT")
		navHighlight:SetTexture(MEDIA_HIGHLIGHT)
		navHighlight:SetAllPoints()
		navHighlight:SetBlendMode("ADD")
		navHighlight:SetAlpha(0.15)
		btn:SetHighlightTexture(navHighlight)

		btn:SetScript("OnClick", function() SelectTab(key) end)

		navButtons[key] = btn
		navY = navY - 34
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
