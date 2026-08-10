--[[
	Venom Bar

	A small, non-action-bar row of your known "Venom" spells (Debilitating,
	Nullifying, Blight, Weakening, Rejuvenating, etc.) plus a "Remove
	Venoms" utility - whatever you actually know, scanned from your
	spellbook by name rather than hardcoded, so new venoms Ascension adds
	later show up automatically without needing an addon update.

	Interaction model:
	  - Expanded: left-click a venom to set it as your 1st selection,
	    right-click for your 2nd. Selected icons get a colored border and
	    a small "1"/"2" badge so it's obvious at a glance.
	  - A keybind (Key Bindings > Venomancer Assistant > Apply Selected
	    Venom) applies your 1st selection on the first press, your 2nd
	    selection on the next press, then wraps back to the 1st - so
	    applying both takes two presses.
	  - Minimized: the bar collapses to a single button showing whichever
	    selection is "next up". Clicking it does the same apply-and-
	    advance as the keybind.

	Shares its lock state with the stack tracker (same "locked" setting,
	toggled from the General tab) and follows the same drag-handle/
	bounding-box pattern.

	IMPORTANT CAVEAT: applying a venom here works by casting the spell
	directly (the same thing that happens when you click it in your
	spellbook), via a secure button whose target spell is set dynamically
	right before each click. That's a well-established addon pattern, but
	I don't have a live client to confirm Ascension's venoms apply this
	simply (vs. requiring some other targeting step) - worth testing
	somewhere low-stakes first. Also, changing which spell that button
	targets can only happen outside combat lockdown (a hard WoW
	restriction on secure frames), which normally isn't an issue since
	you'd select venoms before a pull, not mid-fight - but if you change
	your selection while in combat, don't be surprised if it doesn't take
	effect until combat ends.
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
	-- Keys added in later versions get their own standalone check rather
	-- than joining the block above - that block only runs once, ever,
	-- the very first time this addon loads for a character, so anyone
	-- who already has saved data from before a given key existed would
	-- otherwise never get its default and hit a nil-index error the
	-- first time something tries to read it.
	if d.warnTextBorderColor == nil then
		d.warnTextBorderColor = { 0, 0, 0 }
	end
	if d.warnTextPoint == nil then
		d.warnTextPoint, d.warnTextX, d.warnTextY = "TOP", 0, -160
	end
	return d
end

-- Called once immediately, right here at file-load time rather than only
-- from inside event handlers - guarantees every default key above
-- (including the ones VenomancerAssistant.lua's shared UI widgets like
-- ColorSwatch need to read, e.g. warnTextColor) exists in the saved
-- table as early as physically possible, rather than depending on
-- ADDON_LOADED/PLAYER_ENTERING_WORLD having fired first. GetDB() is
-- idempotent and cheap, so calling it an extra time here costs nothing.
GetDB()

--------------------------------------------------------------------------------
-- Venom scanning - by name rather than a hardcoded list, so anything
-- added to the spellbook later (per Kian: "other venoms may become
-- available later") shows up automatically.
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
	["withering venom"] = true,
}

-- Hidden scanning tooltip, used only to read a venom's actual mechanical
-- effect out of its real tooltip text (e.g. "30% chance to poison an
-- enemy dealing 249 Shadow Damage over 6 sec.") so hover tooltips on the
-- bar can show just that line instead of the full flavor+duration+
-- reminder text. If the spell-lookup call this needs doesn't exist on
-- this client either, GetSpellTooltipText just returns nil and the
-- venom's tooltip falls back to showing its plain name - never errors.
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

-- Every venom tooltip so far follows the same shape: flavor/duration
-- text, then the actual mechanical effect as an "N% chance to ..."
-- clause ending in a period, then a shared "max 2 unique venoms"
-- reminder. Pulling out just that middle clause via pattern match (not
-- hardcoded per-venom) means it keeps working for venoms with different
-- percentages/damage/effects, including ones added later - as long as
-- they follow the same "N% chance to ... ." shape. If a given venom's
-- tooltip doesn't match (a differently-worded effect), this just
-- returns nil and the tooltip falls back to the plain name - not a
-- crash, just less detail for that one venom.
local function ExtractKeyEffect(fullText)
	if not fullText then return nil end
	return fullText:match("%d+%%%s+chance[^.]+%.")
end

local function ScanVenoms()
	wipe(knownVenoms)
	-- Spellbook indices list every rank of a spell separately under the
	-- same display name, highest rank last - keep only the last (i.e.
	-- highest-rank) entry per name rather than showing every rank as its
	-- own button.
	local byName = {}
	local order = {}
	for i = 1, 1024 do
		local name = GetSpellBookItemName(i, BOOKTYPE_SPELL)
		if not name then break end
		if name:lower():find("venom") and not VENOM_EXCLUDE[name:lower()] then
			-- GetSpellBookItemTexture doesn't exist on this client -
			-- GetSpellTexture(index, bookType) is the equivalent here.
			-- Guarded with a fallback in case that's not it either, so a
			-- missing API function doesn't take down the whole scan again.
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
-- Frame setup - same anchor-frame/drag-handle/bounding-box pattern as
-- the stack tracker, but with its own independent saved position.
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
-- Apply button - the one real, secure, spell-casting button. Reused for
-- both the keybind and the minimized-mode click; see the file header
-- caveat about combat lockdown.
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

-- 1 = next left-click applies selection 1, 2 = selection 2. Plain
-- Lua-side counter, advanced in PreClick right alongside setting the
-- spell attribute - both in the same insecure script, so there's no
-- window where the click resolves against a stale value.
--
-- (Earlier this used a secure "_onclick" snippet instead of PreClick,
-- on a theory that PreClick's attribute write might not be seen by
-- that same click's resolution. That turned out to be the wrong fix -
-- _onclick fully replaces the button's default type="spell" dispatch
-- rather than supplementing it, so setting "spell" from inside it never
-- actually triggered a cast at all, which is why clicking stopped doing
-- anything. PreClick is the standard, correct mechanism for this -
-- it's specifically designed to run before the built-in dispatch reads
-- the attribute, which is what "Poisoner"-style classic addons already
-- rely on for exactly this dual-poison-swap pattern.)
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
-- Venom selection buttons (expanded mode) - plain, non-secure buttons;
-- they only ever set which spell name is selected, never cast anything
-- themselves.
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

	-- Badge: small filled square with a thin dark border, tucked into
	-- the bottom-right corner - the same spot WoW's own item/buff stack
	-- counts sit, so it reads as "a count/marker" at a glance rather
	-- than a separate blob competing with the icon for attention.
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
		-- SetSpellBookItem doesn't exist on this client for a direct
		-- tooltip either (same pattern as GetSpellBookItemTexture
		-- earlier), so this just shows the name plus whichever
		-- mechanical-effect line was pulled out via the scanning
		-- tooltip in ScanVenoms - not the full flavor/duration/reminder
		-- text. Falls back to just the name if that extraction didn't
		-- find a match for this particular venom.
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
-- Warnings - three generic Venomancer conditions, each independently
-- configurable to show as a small icon and/or big screen-center text,
-- plus an optional sound on the moment it starts. Kept simple compared
-- to the stack trackers' effect engine (no particles/screen-flash/
-- sustain-repeat) since these are persistent on/off states rather than
-- stack-count triggers - the icon and text already stay up for as long
-- as the condition holds, which covers the "keep alerting me" need
-- without needing a separate repeat mechanism.
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

-- Big text banner, shared across all three warnings (each active,
-- text-enabled warning contributes one line rather than each getting
-- its own banner). Draggable and lockable using the same shared "locked"
-- setting as the tracker and Venom Bar.
local warnAnchor = CreateFrame("Frame", "VenomBarWarnTextAnchor", UIParent)
warnAnchor:SetSize(1, 1)
warnAnchor:SetMovable(true)
warnAnchor:SetClampedToScreen(true)

local warnTextFrame = CreateFrame("Frame", "VenomBarWarnTextFrame", UIParent)
warnTextFrame:SetSize(500, 60)
warnTextFrame:SetPoint("TOP", warnAnchor, "TOP", 0, 0)
warnTextFrame:Hide()

-- The built-in SetFont "OUTLINE"/"THICKOUTLINE" flags always render
-- black and can't be recolored, so a custom-colored border is faked the
-- classic way: several copies of the same text offset by a pixel or two
-- in every direction, colored as the border, sitting behind the real
-- (foreground-colored) text on top. NONE uses zero copies, OUTLINE uses
-- the 4 cardinal offsets, THICKOUTLINE uses all 8.
local WARN_TEXT_OFFSETS = {
	{ 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
	{ 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}
local warnTextShadows = {}
for i = 1, #WARN_TEXT_OFFSETS do
	-- ARTWORK is a strictly lower draw layer than OVERLAY (used by the
	-- main text below) - explicit layer separation, not just creation
	-- order, guarantees the colored main text renders on top of these
	-- border copies rather than leaving it to same-layer z-ordering
	-- (which is what main+shadows both being "OVERLAY" relied on
	-- before, and which is the most likely reason border color/outline
	-- appeared to do nothing - the shadows may have been drawing over
	-- the main text instead of behind it).
	local fs = warnTextFrame:CreateFontString(nil, "ARTWORK")
	fs:SetJustifyH("CENTER")
	warnTextShadows[i] = fs
end
local warnText = warnTextFrame:CreateFontString(nil, "OVERLAY")
warnText:SetPoint("CENTER")
warnText:SetJustifyH("CENTER")

-- A single immediate SetFont call doesn't always visibly take on this
-- client - re-applying it again a beat later (rather than only when
-- some unrelated control happens to be touched afterward) reliably
-- finishes the job. Harmless no-op if the first application already
-- worked.
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

	-- No built-in OUTLINE/THICKOUTLINE flag here at all anymore - always
	-- plain, since the border is hand-drawn via the offset copies above.
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

	-- SetFont alone doesn't always force a visible re-render on this
	-- client until something else touches the string - re-applying the
	-- current text after every style change works around that reliably.
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
				-- Deliberately not calling RefreshWarnTextStyle() again
				-- here (that would recurse forever) - just re-applying
				-- the font/color/text one more time directly.
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

-- Shared helper: sets the same text on the foreground and all visible
-- border-shadow copies together, so nothing has to remember to do this
-- in more than one place.
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

-- Preview swatch so the drag handle/position is visible even before any
-- warning has ever actually fired - shown together with the drag hint
-- while unlocked.
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

-- Small icon row, one icon per warning type, shown only while that
-- specific warning is both enabled and currently active.
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

-- Fallbacks only - RefreshWarnIcons (below, called alongside ScanVenoms)
-- replaces these with the real spell icons as soon as they're found:
-- Blight Venom's own icon for the missing-venom warning, Spider
-- Pheromones' for the pheromone warning, and Envenomed Weapons' own icon
-- for that warning. These generic guesses only stick around if the
-- character doesn't know the relevant spell yet.
local warnIcons = {
	venom = CreateWarnIcon("Interface\\Icons\\Ability_Poisons"),
	pheromone = CreateWarnIcon("Interface\\Icons\\Spell_Nature_Regenerate"),
	envenomed = CreateWarnIcon("Interface\\Icons\\INV_Sword_04"),
}
warnIcons.venom:SetPoint("LEFT", warnIconFrame, "LEFT", 0, 0)
warnIcons.pheromone:SetPoint("LEFT", warnIcons.venom, "RIGHT", 8, 0)
warnIcons.envenomed:SetPoint("LEFT", warnIcons.pheromone, "RIGHT", 8, 0)

-- Scans the spellbook for an exact name match and returns its icon -
-- used for warning icons that aren't already covered by the venom scan
-- (Spider Pheromones, Envenomed Weapons). Same GetSpellTexture caveat as
-- ScanVenoms: falls back to nil (caller supplies the generic icon
-- instead) if the character doesn't know the spell, or if that API call
-- isn't available.
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
-- Layout - lays out either the full row (expanded) or just castButton
-- (minimized), plus a small toggle arrow either way.
--------------------------------------------------------------------------------

local toggleButton = CreateFrame("Button", "VenomBarToggleButton", bar, "UIPanelButtonTemplate")
toggleButton:SetSize(16, 20)

local emptyLabel = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
emptyLabel:SetPoint("LEFT", bar, "LEFT", 2, 0)
emptyLabel:SetText("No Venom spells known yet")
emptyLabel:Hide()

local relayoutQueued = false

-- Direction the toggle button's own edge sits at (this is what gets
-- pinned to anchorFrame, so the toggle - not bar's arbitrary corner -
-- is the one fixed, unmoving reference point everything else grows
-- away from), and the arrow glyph shown in each state. Minimized shows
-- the direction it will expand toward; expanded shows the direction
-- that collapses back toward the toggle.
local GROWTH_INFO = {
	RIGHT = { point = "LEFT", relPoint = "LEFT", minArrow = ">", expArrow = "<" },
	LEFT  = { point = "RIGHT", relPoint = "LEFT", minArrow = "<", expArrow = ">" },
	DOWN  = { point = "TOP", relPoint = "LEFT", minArrow = "v", expArrow = "^" },
	UP    = { point = "BOTTOM", relPoint = "LEFT", minArrow = "^", expArrow = "v" },
}

local function RelayoutBar()
	-- Repositioning/resizing castButton (a secure frame) is a protected
	-- operation while in combat - WoW blocks it outright ("prevented the
	-- call of the secure function..."). Defer until combat ends instead
	-- of crashing.
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

	-- Re-anchor bar itself so whichever edge the toggle sits on is the
	-- one pinned to the saved drag position - not always bar's left
	-- edge regardless of direction, which was the source of the
	-- inconsistency (minimized mode never respected growth direction at
	-- all before this). Content always extends away from that same
	-- fixed point afterward, so the toggle button never visually moves
	-- no matter how many icons are shown or which direction is chosen.
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
-- Lock state - shared with the stack tracker's "locked" setting. Polled
-- rather than event-driven, since that setting can change from a
-- checkbox or slash command this file has no direct hook into; a cheap
-- once-a-second check is simpler and more robust than trying to wire a
-- cross-file callback for it.
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
	-- Piggybacking the warnings check on the same half-second poll
	-- rather than adding a second OnUpdate frame - cheap enough, and
	-- keeps everything in one place.
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
--
-- Standard "CLICK <frame>:<button>" binding convention - shows up in the
-- Key Bindings UI under a "Venomancer Assistant" header, and the user
-- can bind any key to it there. No hardcoded default key.
--------------------------------------------------------------------------------

BINDING_HEADER_VENOMANCERASSISTANT = "Venomancer Assistant"
_G["BINDING_NAME_CLICK VenomBarCastButton:LeftButton"] = "Apply Selected Venom (1st press = selection 1, 2nd = selection 2)"

--------------------------------------------------------------------------------
-- Options tab - hooked into VenomancerAssistant.lua's options panel via
-- RegisterTab, passed in when it builds its own tabs (see
-- VenomBarModule.BuildOptionsTab below).
--------------------------------------------------------------------------------

function VenomBarModule.BuildOptionsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers)
	local sc = RegisterTab("venombar", "Venom Bar", "Interface\\Icons\\INV_Potion_04")
	local L = CreateLayoutHelpers(sc)

	L.Note("Shows your known Venom spells (scanned from your spellbook, so new ones show up automatically). Left-click selects slot 1, right-click selects slot 2. Lock state is shared with the tracker's Lock setting on the General tab.")
	L.Section("Layout")
	L.Slider("Icon size", "vbIconSize", 16, 48, 1, function() RelayoutBar() end)
	L.Slider("Icon spacing", "vbSpacing", -8, 16, 1, function() RelayoutBar() end)

	local growthLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	L.PlaceLeft(growthLabel, 2)
	growthLabel:SetText("Growth direction:")
	L.AdvanceY(20)

	local growthButtons = {}
	local growthOrder = { "RIGHT", "LEFT", "UP", "DOWN" }
	local growthLabels = { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }
	for i, dir in ipairs(growthOrder) do
		local btn = CreateFrame("CheckButton", "VenomBarGrowth" .. dir, sc, "UIRadioButtonTemplate")
		L.PlaceLeft(btn, 2 + (i - 1) * 80)
		_G[btn:GetName() .. "Text"]:SetText(growthLabels[dir])
		growthButtons[dir] = btn
	end

	local function RefreshGrowthRadios()
		local current = GetDB().vbGrowth
		for dir, btn in pairs(growthButtons) do
			btn:SetChecked(dir == current)
		end
	end
	for dir, btn in pairs(growthButtons) do
		btn:SetScript("OnClick", function()
			GetDB().vbGrowth = dir
			RefreshGrowthRadios()
			RelayoutBar()
		end)
	end
	RefreshGrowthRadios()
	table.insert(optionsRefreshers, RefreshGrowthRadios)
	L.AdvanceY(24 + 6)

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
	-- No need to also register a refresher for minimizeCheck here - the
	-- Checkbox() helper already registers one automatically.

	local rescanBtn = L.Button("Rescan Spellbook", function()
		ScanVenoms()
		RefreshWarnIcons()
		RelayoutBar()
		RefreshSelectionLabels()
	end)

	sc:SetHeight(-L.GetY() + 20)
end

function VenomBarModule.BuildWarningsTab(RegisterTab, CreateLayoutHelpers, optionsRefreshers)
	local sc = RegisterTab("warnings", "Warnings", "Interface\\Icons\\Ability_Poisons")
	local L = CreateLayoutHelpers(sc)

	L.Note("Generic alerts, each shown as a small icon and/or big screen-center text - pick whichever combination actually catches your eye. All checked once every half-second, plus immediately on any of your own aura changes.")

	L.Section("Text Appearance")
	L.Note("Applies to all three warnings' big text - they share one style, just different lines. Drag the \"Drag Me\" handle above it (visible while unlocked, same Lock setting as the tracker) to reposition it.")
	L.ColorSwatch("Text color:", "warnTextColor", function() RefreshWarnTextStyle() end)
	L.ColorSwatch("Border color:", "warnTextBorderColor", function() RefreshWarnTextStyle() end)
	L.Slider("Font size", "warnTextSize", 12, 48, 1, function() RefreshWarnTextStyle() end)

	local outlineLabel = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	L.PlaceLeft(outlineLabel, 2)
	outlineLabel:SetText("Border:")

	local outlineNone = CreateFrame("CheckButton", "VenomBarOutlineNone", sc, "UIRadioButtonTemplate")
	outlineNone:SetPoint("LEFT", outlineLabel, "RIGHT", 10, 0)
	_G[outlineNone:GetName() .. "Text"]:SetText("None")
	local outlineThin = CreateFrame("CheckButton", "VenomBarOutlineThin", sc, "UIRadioButtonTemplate")
	outlineThin:SetPoint("LEFT", outlineNone, "RIGHT", 60, 0)
	_G[outlineThin:GetName() .. "Text"]:SetText("Outline")
	local outlineThick = CreateFrame("CheckButton", "VenomBarOutlineThick", sc, "UIRadioButtonTemplate")
	outlineThick:SetPoint("LEFT", outlineThin, "RIGHT", 74, 0)
	_G[outlineThick:GetName() .. "Text"]:SetText("Thick")

	local function RefreshOutlineRadios()
		local o = GetDB().warnTextOutline
		outlineNone:SetChecked(o == "NONE")
		outlineThin:SetChecked(o == "OUTLINE")
		outlineThick:SetChecked(o == "THICKOUTLINE")
	end
	outlineNone:SetScript("OnClick", function() GetDB().warnTextOutline = "NONE"; RefreshOutlineRadios(); RefreshWarnTextStyle() end)
	outlineThin:SetScript("OnClick", function() GetDB().warnTextOutline = "OUTLINE"; RefreshOutlineRadios(); RefreshWarnTextStyle() end)
	outlineThick:SetScript("OnClick", function() GetDB().warnTextOutline = "THICKOUTLINE"; RefreshOutlineRadios(); RefreshWarnTextStyle() end)
	RefreshOutlineRadios()
	table.insert(optionsRefreshers, RefreshOutlineRadios)
	L.AdvanceY(24 + 6)

	-- Must declare-then-assign in two statements, not "local x = f(function() x end)" -
	-- in Lua, the RHS of a local declaration is evaluated before the new
	-- local comes into scope, so a closure created inside that RHS would
	-- otherwise capture a (nonexistent) global "previewBtn" instead of
	-- this local, which is exactly what threw here.
	local previewBtn
	previewBtn = L.Button("Preview Text Style", function()
		SetWarnText("SAMPLE WARNING TEXT")
		warnTextFrame.hasRealContent = true
		warnTextFrame:Show()
		if previewBtn.hideTimer then previewBtn.hideTimer:SetScript("OnUpdate", nil) end
		local elapsed = 0
		local hideFrame = CreateFrame("Frame")
		hideFrame:SetScript("OnUpdate", function(self, e)
			elapsed = elapsed + e
			if elapsed > 2 then
				warnTextFrame.hasRealContent = false
				if GetDB().locked then warnTextFrame:Hide() end
				self:SetScript("OnUpdate", nil)
			end
		end)
		previewBtn.hideTimer = hideFrame
	end)

	local function WarningSection(title, prefix, note)
		L.Section(title)
		L.Note(note)
		L.CheckboxRow("Enable", prefix .. "Enabled", "Turn this warning on or off entirely.")
		L.CheckboxPair(
			"Icon", prefix .. "Icon", "Show a small icon near the top of the screen while this is active.",
			"Text", prefix .. "Text", "Show text near the top of the screen while this is active - size, color, and border are all set above in Text Appearance."
		)
		L.CheckboxRow("Sound", prefix .. "Sound", "Play a sound the moment this warning starts (not while it continues).")
	end

	WarningSection("Missing Venom", "warnMissingVenom", "Warns if fewer than 2 of your known venoms are currently applied.")
	WarningSection("Missing Pheromone", "warnPheromone", "Warns if no buff with \"Pheromone\" in its name is currently active.")
	WarningSection("Envenomed Weapons", "warnEnvenomed", "Warns if the \"Envenomed Weapons\" buff is not currently active.")

	sc:SetHeight(-L.GetY() + 20)
end
