--[[
	Venomancer Assistant - Stack Tracker factory

	Produces one independent, separately-draggable pip tracker per call.
	SpiderForm.lua and BeetleForm.lua each call this once (for Brood Marks
	and Exposed Flesh respectively) - same engine, two fully independent
	frames/SavedVariables/locks, instead of two copies of this file.
]]

local Core = VenomancerAssistant
local FALLBACK_ICON = Core.FALLBACK_ICON

local NORMAL_BORDER = { 1, 1, 1, 1 }
local SOUND_FILE = "Sound\\Interface\\RaidWarning.wav"
local SUSTAIN_INTERVAL = 0.8
local NUM_PARTICLES = 14

-- cfg = {
--   namespaceKey   = "spider" / "beetle"  (SavedVariables sub-table name)
--   framePrefix    = "VASpiderTracker"    (must be globally unique)
--   label          = "Brood Marks"
--   buffName       = "Brood Mark"
--   maxStacks      = 5
--   defaultIcon    = "Interface\\Icons\\..."
--   formKey        = "spider"             (Core.FORMS key that gates visibility)
--   defaultsOverride = { ... }            (optional - override specific
--                        factory defaults below, e.g. a more urgent max
--                        color for a faster-filling tracker. Declarative
--                        and guarded the same way as everything else -
--                        no ADDON_LOADED patching, no partial overrides.)
-- }
function Core.CreateStackTracker(cfg)
	local baseDefaults = {
		point = "CENTER", x = 0, y = -220,
		locked = false,
		enabled = true,
		scale = 1.0,
		iconSize = 28,
		spacing = 4,
		growth = "RIGHT",
		showEmpty = true,
		hideOutOfCombat = false,
		testMode = false,
		testCount = math.floor((cfg.maxStacks or 5) * 0.6 + 0.5),

		-- Both tiers default to color flash + screen flash on, since
		-- those are the two effects that are actually impossible to
		-- miss - glow alone is easy to overlook, and leaving every
		-- effect off by default makes a freshly-configured tier look
		-- broken when it's just silent.
		flashAtMax = true,
		effectPulse = false,
		effectColorFlash = true,
		effectParticleBurst = false,
		effectScreenFlash = true,
		effectScreenColor = { 1, 0.85, 0.2 },
		effectSound = false,
		maxColor = { 1, 0.85, 0.2 },
		maxSustain = false,

		warnEnabled = true,
		warnThreshold = math.max(1, math.floor((cfg.maxStacks or 5) * 0.6)),
		warnGlow = true,
		warnPulse = false,
		warnColorFlash = true,
		warnParticleBurst = false,
		warnScreenFlash = true,
		warnScreenColor = { 0.3, 0.75, 1 },
		warnSound = false,
		warnColor = { 0.3, 0.75, 1 },
		warnSustain = false,
	}
	if cfg.defaultsOverride then
		for k, v in pairs(cfg.defaultsOverride) do baseDefaults[k] = v end
	end
	local dbFn = Core.RegisterModuleDB(cfg.namespaceKey, baseDefaults)

	local anchorFrame = CreateFrame("Frame", cfg.framePrefix .. "Anchor", UIParent)
	anchorFrame:SetSize(1, 1)
	anchorFrame:SetMovable(true)
	anchorFrame:SetClampedToScreen(true)

	local main = CreateFrame("Frame", cfg.framePrefix .. "Frame", UIParent)
	main:SetFrameStrata("FULLSCREEN_DIALOG") -- above the options panel (DIALOG), so it's never hidden behind it
	main:SetSize(200, 40)
	main:SetPoint("LEFT", anchorFrame, "LEFT", 0, 0)
	main:SetClampedToScreen(true)
	main:EnableMouse(false)
	main:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	main:SetBackdropColor(0, 0, 0, 0)
	main:SetBackdropBorderColor(1, 0.82, 0, 0)

	local dragHint = CreateFrame("Frame", nil, UIParent)
	dragHint:SetSize(170, 20)
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
	dragHintText:SetWordWrap(false)
	dragHintText:SetJustifyV("MIDDLE")
	dragHintText:SetText("Drag: " .. cfg.label)
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
		main:SetBackdropColor(0, 0, 0, unlocked and 0.25 or 0)
		main:SetBackdropBorderColor(1, 0.82, 0, unlocked and 0.9 or 0)
	end

	----------------------------------------------------------------------
	-- Pips
	----------------------------------------------------------------------

	local pips = {}
	local lastKnownIcon

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
		p.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		p.glow = p:CreateTexture(nil, "OVERLAY")
		p.glow:SetPoint("TOPLEFT", -7, 7)
		p.glow:SetPoint("BOTTOMRIGHT", 7, -7)
		p.glow:SetTexture("Interface\\Cooldown\\star4")
		p.glow:SetBlendMode("ADD")
		p.glow:Hide()

		pips[i] = p
		return p
	end

	local GROWTH_INFO = {
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

	local function LayoutPips()
		local d = dbFn()
		local maxCount = cfg.maxStacks
		local size = d.iconSize
		local spacing = d.spacing
		local growth = d.growth or "RIGHT"
		local vertical = (growth == "UP" or growth == "DOWN")
		local info = GROWTH_INFO[growth] or GROWTH_INFO.RIGHT

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
		for i = maxCount + 1, #pips do pips[i]:Hide() end

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

	----------------------------------------------------------------------
	-- Effects engine (glow/pulse/color-flash/particles/screen-flash)
	----------------------------------------------------------------------

	local colorFlash = { active = false, t = 0, duration = 0.4, color = NORMAL_BORDER }
	local screenFlashState = { active = false, t = 0, duration = 0.5, color = NORMAL_BORDER }
	local particles = {}

	local screenFlashFrame = CreateFrame("Frame", cfg.framePrefix .. "ScreenFlash", UIParent)
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
		t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0); t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0); t:SetHeight(64)
	end)
	local edgeBottom = CreateEdgeBar(function(t)
		t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0); t:SetHeight(64)
	end)
	local edgeLeft = CreateEdgeBar(function(t)
		t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0); t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0); t:SetWidth(64)
	end)
	local edgeRight = CreateEdgeBar(function(t)
		t:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0); t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0); t:SetWidth(64)
	end)
	local edgeBars = { edgeTop, edgeBottom, edgeLeft, edgeRight }

	for i = 1, NUM_PARTICLES do
		local p = main:CreateTexture(nil, "OVERLAY")
		p:SetTexture("Interface\\Cooldown\\star4")
		p:SetBlendMode("ADD")
		p:SetSize(16, 16)
		p:SetPoint("CENTER", main, "CENTER", 0, 0)
		particles[i] = { tex = p, active = false, t = 0, duration = 0.55, angle = 0, dist = 0, color = NORMAL_BORDER, originX = 0, originY = 0 }
	end

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

	local function TriggerEffectSet(flags, color, screenColor, maxCount)
		if flags.colorFlash then
			colorFlash.active, colorFlash.t, colorFlash.color = true, 0, color
		end
		if flags.particleBurst then StartParticleBurst(color, maxCount) end
		if flags.screenFlash then
			screenFlashState.active, screenFlashState.t, screenFlashState.color = true, 0, screenColor or color
			screenFlashFrame:Show()
		end
		if flags.sound then PlaySoundFile(SOUND_FILE, "Master") end
	end

	----------------------------------------------------------------------
	-- State / Update
	----------------------------------------------------------------------

	local wasAtMax, wasAtWarn = false, false
	local glowElapsed = 0
	local settleUntil = 0 -- see PLAYER_ENTERING_WORLD handling below
	local previewForceWarn = false -- lets Preview show Early Warning even while its own "Enable" toggle is off

	local function GetStackCount()
		local d = dbFn()
		for i = 1, 40 do
			local name, _, icon, count = UnitBuff("player", i)
			if not name then break end
			if name == cfg.buffName then return count or 1, icon end
		end
		for i = 1, 40 do
			local name, _, icon, count = UnitDebuff("player", i)
			if not name then break end
			if name == cfg.buffName then return count or 1, icon end
		end
		return 0, nil
	end

	local api = {}

	local function IsActive()
		local d = dbFn()
		if d.testMode then return true end -- preview overrides everything below, always
		if cfg.masterEnabledFn and not cfg.masterEnabledFn() then return false end
		if not d.enabled then return false end
		return Core.GetActiveFormKey() == cfg.formKey
	end

	function api.Update()
		local d = dbFn()

		-- Blocks every caller during the post-zone settle window, not
		-- just the one that triggered it - UNIT_AURA can still fire with
		-- a transient bad read during this window and would otherwise
		-- slip past a delay on just the PLAYER_ENTERING_WORLD handler.
		-- Preview explicitly bypasses this - it's not a real aura read,
		-- there's nothing for it to be wrong about.
		if GetTime() < settleUntil and not d.testMode then return end

		if not IsActive() then
			if not d.locked then
				-- stay visible while unlocked so there's something to drag
			else
				ClearInProgressEffects()
				main:Hide()
				main.atMax, main.atWarn = false, false
				return
			end
		end

		local maxCount = cfg.maxStacks
		local count, icon
		if d.testMode then
			count = d.testCount
			icon = lastKnownIcon or cfg.defaultIcon or FALLBACK_ICON
		else
			count, icon = GetStackCount()
			if icon and icon ~= "" then lastKnownIcon = icon end
		end

		LayoutPips()

		local showIcon = icon or lastKnownIcon or cfg.defaultIcon or FALLBACK_ICON

		for i = 1, maxCount do
			local p = pips[i]
			if not p then break end
			local active = i <= count
			if active or d.showEmpty then
				p:Show()
				if active then
					p.icon:SetTexture(showIcon)
					p.icon:Show()
					if not colorFlash.active then p:SetBackdropBorderColor(unpack(NORMAL_BORDER)) end
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
		if (d.warnEnabled or previewForceWarn) and not atMax then
			atWarn = count >= d.warnThreshold
		end

		local maxFlags = {
			colorFlash = d.effectColorFlash, particleBurst = d.effectParticleBurst,
			screenFlash = d.effectScreenFlash, sound = d.effectSound,
		}
		local warnFlags = {
			colorFlash = d.warnColorFlash, particleBurst = d.warnParticleBurst,
			screenFlash = d.warnScreenFlash, sound = d.warnSound,
		}

		if atMax and not wasAtMax then TriggerEffectSet(maxFlags, d.maxColor, d.effectScreenColor, maxCount) end
		if atWarn and not wasAtWarn then TriggerEffectSet(warnFlags, d.warnColor, d.warnScreenColor, maxCount) end
		wasAtMax, wasAtWarn = atMax, atWarn

		main.atMax, main.maxFlags, main.maxColor, main.maxScreenColor, main.maxSustain = atMax, maxFlags, d.maxColor, d.effectScreenColor, d.maxSustain
		main.atWarn, main.warnFlags, main.warnColor, main.warnScreenColor, main.warnSustain = atWarn, warnFlags, d.warnColor, d.warnScreenColor, d.warnSustain

		local glowOn, glowColor
		if d.flashAtMax and atMax then
			glowOn, glowColor = true, d.maxColor
		elseif d.warnGlow and atWarn then
			glowOn, glowColor = true, d.warnColor
		end
		local bounceOn = (d.effectPulse and atMax) or (d.warnPulse and atWarn)

		main.glowing, main.glowColor, main.bouncing = glowOn, glowColor, bounceOn
		if not main.glowing then
			for i = 1, maxCount do if pips[i] then pips[i].glow:Hide() end end
		end
		if not main.bouncing and main.bounceApplied then
			main:SetScale(d.scale)
			main.bounceApplied = false
		end

		-- Don't let "hide out of combat" suppress an active warning/max
		-- state - that's exactly when you most need to see it. Without
		-- this, a threshold crossed while not flagged in combat would
		-- fire the trigger and immediately wipe it in the same pass.
		if d.hideOutOfCombat and d.locked and not d.testMode and not atMax and not atWarn and not UnitAffectingCombat("player") then
			ClearInProgressEffects()
			main:Hide()
		else
			main:Show()
		end
	end

	local previewExpireFrame = CreateFrame("Frame")
	local previewExpireElapsed = 0

	-- Previews at a specific stack count, running through the exact same
	-- Update() logic real gameplay does - so "Preview Early Warning"
	-- genuinely triggers the configured warning effects (glow, color
	-- flash, sound, etc.) rather than simulating them separately.
	-- forceWarn=true bypasses the tier's own "Enable" toggle, since a
	-- preview should show what it WOULD look like even while it's off.
	function api.DoPreview(targetCount, forceWarn)
		local d = dbFn()
		d.testMode = true
		d.testCount = targetCount
		wasAtMax, wasAtWarn = false, false
		previewForceWarn = forceWarn or false
		settleUntil = 0 -- preview should never be blocked by the post-zone settle window either
		api.Update()

		previewExpireElapsed = 0
		previewExpireFrame:SetScript("OnUpdate", function(self, elapsed)
			previewExpireElapsed = previewExpireElapsed + elapsed
			if previewExpireElapsed >= 3 then
				previewExpireFrame:SetScript("OnUpdate", nil)
				dbFn().testMode = false
				previewForceWarn = false
				api.Update()
			end
		end)
	end

	main:SetScript("OnUpdate", function(self, elapsed)
		local d = dbFn()
		glowElapsed = glowElapsed + elapsed
		local maxCount = cfg.maxStacks

		if self.glowing and self.glowColor then
			local alpha = 0.65 + 0.35 * math.abs(math.sin(glowElapsed * 3))
			for i = 1, maxCount do
				local p = pips[i]
				if p and p:IsShown() then
					p.glow:Show()
					p.glow:SetVertexColor(self.glowColor[1], self.glowColor[2], self.glowColor[3], 1)
					p.glow:SetAlpha(alpha)
				end
			end
		end

		if self.bouncing then
			local factor = 1 + 0.06 * math.abs(math.sin(glowElapsed * 4))
			self:SetScale(d.scale * factor)
			self.bounceApplied = true
		end

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
			if progress >= 1 then colorFlash.active = false end
		end

		for i = 1, NUM_PARTICLES do
			local pt = particles[i]
			if pt.active then
				pt.t = pt.t + elapsed
				local progress = math.min(pt.t / pt.duration, 1)
				local dist = pt.dist * progress
				pt.tex:ClearAllPoints()
				pt.tex:SetPoint("CENTER", main, "CENTER", pt.originX + math.cos(pt.angle) * dist, pt.originY + math.sin(pt.angle) * dist)
				pt.tex:SetVertexColor(pt.color[1], pt.color[2], pt.color[3], 1 - progress)
				if progress >= 1 then pt.active = false; pt.tex:Hide() end
			end
		end

		if screenFlashState.active then
			screenFlashState.t = screenFlashState.t + elapsed
			local progress = math.min(screenFlashState.t / screenFlashState.duration, 1)
			local alpha
			if progress < 0.3 then alpha = (progress / 0.3) * 0.8
			else alpha = (1 - (progress - 0.3) / 0.7) * 0.8 end
			local c = screenFlashState.color
			for _, bar in ipairs(edgeBars) do bar:SetTexture(c[1], c[2], c[3], alpha) end
			if progress >= 1 then screenFlashState.active = false; screenFlashFrame:Hide() end
		end

		if self.atMax and self.maxSustain and self.maxFlags then
			self.maxSustainT = (self.maxSustainT or 0) + elapsed
			if self.maxSustainT >= SUSTAIN_INTERVAL then
				self.maxSustainT = 0
				TriggerEffectSet({ colorFlash = self.maxFlags.colorFlash, particleBurst = self.maxFlags.particleBurst, screenFlash = self.maxFlags.screenFlash, sound = false }, self.maxColor, self.maxScreenColor, maxCount)
			end
		else
			self.maxSustainT = 0
		end

		if self.atWarn and self.warnSustain and self.warnFlags then
			self.warnSustainT = (self.warnSustainT or 0) + elapsed
			if self.warnSustainT >= SUSTAIN_INTERVAL then
				self.warnSustainT = 0
				TriggerEffectSet({ colorFlash = self.warnFlags.colorFlash, particleBurst = self.warnFlags.particleBurst, screenFlash = self.warnFlags.screenFlash, sound = false }, self.warnColor, self.warnScreenColor, maxCount)
			end
		else
			self.warnSustainT = 0
		end
	end)

	----------------------------------------------------------------------
	-- Options page - one "Enable" + Appearance on the module tab itself,
	-- Early Warning / Max Stacks as sub-tabs, each with its own preview
	-- button that triggers that tab's configured effects for real.
	----------------------------------------------------------------------

	function api.BuildOptionsPage(container, CreateLayoutHelpers, CreateSubTabPager)
		local L = CreateLayoutHelpers(container, dbFn, api.Update)
		L.CheckboxRow("Enable " .. cfg.label .. " tracking", "enabled", "Turn this tracker on or off.")
		L.CheckboxRow("Locked", "locked", "Lock/unlock this tracker's position. While unlocked, drag its \"Drag Me\" handle to move it.", function() ApplyLockVisual() end)

		local subs, SelectSub = CreateSubTabPager(container, {
			{ key = "appearance", label = "Appearance" },
			{ key = "warn", label = "Early Warning" },
			{ key = "max", label = "Max Stacks" },
		}, L.GetY())

		do
			local L2 = CreateLayoutHelpers(subs.appearance, dbFn, api.Update)
			L2.CheckboxRow("Show empty slots (dim placeholders)", "showEmpty")
			L2.CheckboxRow("Hide when not in combat", "hideOutOfCombat")
			L2.Slider("Scale", "scale", 0.5, 2.5, 0.05)
			L2.Slider("Icon size", "iconSize", 12, 64, 1)
			L2.Slider("Icon spacing", "spacing", -8, 20, 1)
			L2.Dropdown("Growth direction", "growth", {
				{ value = "RIGHT", label = "Right" }, { value = "LEFT", label = "Left" },
				{ value = "UP", label = "Up" }, { value = "DOWN", label = "Down" },
			})
			subs.appearance:SetHeight(-L2.GetY() + 20)
		end
		do
			local L2 = CreateLayoutHelpers(subs.warn, dbFn, function()
				-- The trigger is edge-triggered (fires once per crossing,
				-- not continuously) - so if you're already at/above the
				-- threshold when you change a setting here, resetting
				-- this makes it re-fire immediately with the new
				-- settings instead of silently doing nothing until the
				-- next actual crossing.
				wasAtWarn = false
				api.Update()
			end)
			L2.CheckboxRow("Enable early warning", "warnEnabled")
			L2.Slider("Warn at stack count", "warnThreshold", 1, math.max(1, cfg.maxStacks - 1), 1)
			L2.ColorSwatch("Warning color:", "warnColor")
			L2.ColorSwatch("Screen flash color:", "warnScreenColor")
			L2.CheckboxRow("Sustain until cleared", "warnSustain", "Keep repeating color flash/particle burst/screen flash every ~0.8s while past the warning threshold, instead of firing once.")
			L2.CheckboxPair("Glow border", "warnGlow", nil, "Pulse / scale bounce", "warnPulse", nil)
			L2.CheckboxPair("Color flash", "warnColorFlash", nil, "Particle burst", "warnParticleBurst", nil)
			L2.CheckboxPair("Screen-edge flash", "warnScreenFlash", nil, "Sound cue", "warnSound", nil)
			L2.Button("Preview Early Warning", function() api.DoPreview(dbFn().warnThreshold, true) end)
			subs.warn:SetHeight(-L2.GetY() + 20)
		end
		do
			local L2 = CreateLayoutHelpers(subs.max, dbFn, function()
				wasAtMax = false -- same reasoning as warn tier above
				api.Update()
			end)
			L2.ColorSwatch("Effect color:", "maxColor")
			L2.ColorSwatch("Screen flash color:", "effectScreenColor")
			L2.CheckboxRow("Sustain until cleared", "maxSustain")
			L2.CheckboxPair("Glow border", "flashAtMax", nil, "Pulse / scale bounce", "effectPulse", nil)
			L2.CheckboxPair("Color flash", "effectColorFlash", nil, "Particle burst", "effectParticleBurst", nil)
			L2.CheckboxPair("Screen-edge flash", "effectScreenFlash", nil, "Sound cue", "effectSound", nil)
			L2.Button("Preview Max Stacks", function() api.DoPreview(cfg.maxStacks) end)
			subs.max:SetHeight(-L2.GetY() + 20)
		end
		SelectSub("warn")
	end

	local events = CreateFrame("Frame")
	events:RegisterEvent("PLAYER_ENTERING_WORLD")
	events:RegisterEvent("UNIT_AURA")
	events:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
	events:RegisterEvent("PLAYER_REGEN_DISABLED")
	events:RegisterEvent("PLAYER_REGEN_ENABLED")
	events:SetScript("OnEvent", function(self, event, arg1)
		if event == "UNIT_AURA" then
			if arg1 == "player" then api.Update() end
		elseif event == "PLAYER_ENTERING_WORLD" then
			-- Don't trust an immediate read right as you zone in - see
			-- Core.After's comment. Block every Update() call (including
			-- ones from other events firing during this window) until
			-- things settle, then force one clean read.
			settleUntil = GetTime() + 1.5
			Core.After(1.5, api.Update)
		else
			api.Update()
		end
	end)

	local loadFrame = CreateFrame("Frame")
	loadFrame:RegisterEvent("ADDON_LOADED")
	loadFrame:SetScript("OnEvent", function(self, event, arg1)
		if arg1 ~= Core.ADDON_NAME then return end
		local d = dbFn()

		-- One-time migration: colorFlash/screenFlash used to default to
		-- false on both tiers, which made a freshly-configured warning
		-- or max-stacks tier look broken (nothing visible fired). Since
		-- nobody could have deliberately set these to false through the
		-- UI without them already working, force the new sensible
		-- defaults once for anyone who ran an earlier version.
		if not d._effectDefaultsMigrated then
			d.warnColorFlash, d.warnScreenFlash = true, true
			d.effectColorFlash, d.effectScreenFlash = true, true
			d.warnEnabled = true
			d._effectDefaultsMigrated = true
		end

		anchorFrame:ClearAllPoints()
		anchorFrame:SetPoint(d.point, UIParent, d.point, d.x, d.y)
		ApplyLockVisual()
		self:UnregisterEvent("ADDON_LOADED")
	end)

	api.anchorFrame = anchorFrame
	api.main = main
	api.dbFn = dbFn
	api.ApplyLockVisual = ApplyLockVisual

	Core.RegisterLockable({ dbFn = dbFn, apply = function() ApplyLockVisual(); api.Update() end })

	return api
end
