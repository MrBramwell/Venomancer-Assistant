--[[
	Venomancer Assistant - Core

	Shared framework used by every other file in this addon:
	  - Form detection (spellbook-based, spec-swap aware)
	  - The options panel chrome (topBar/sidebar/tabs/minimap button)
	  - Generic layout helpers used to build every options page
	  - CreateStackTracker(): a factory that produces one independent,
	    separately-draggable pip tracker per call - Brood Marks and
	    Exposed Flesh are each one instance of this, not copy-pasted code.

	Load this file FIRST (see the .toc) - everything else reads from the
	VenomancerAssistant global table this file sets up.
]]

VenomancerAssistant = VenomancerAssistant or {}
local Core = VenomancerAssistant
Core.ADDON_NAME = "VenomancerAssistant"

local ADDON_NAME = Core.ADDON_NAME
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
Core.FALLBACK_ICON = FALLBACK_ICON

--------------------------------------------------------------------------------
-- SavedVariables: one root table, one guarded sub-table per module. Each
-- module owns its own key namespace entirely, so two trackers never share
-- position/lock/scale/appearance the way the old single-table version did.
--------------------------------------------------------------------------------

local function InitSubTable(root, key)
	root[key] = root[key] or {}
	return root[key]
end

function Core.GetRootDB()
	VenomancerAssistantDB = VenomancerAssistantDB or {}
	local root = VenomancerAssistantDB
	root.general = root.general or {}
	local GENERAL_DEFAULTS = { minimapButtonShown = true, minimapAngle = 225, masterLocked = false }
	for k, v in pairs(GENERAL_DEFAULTS) do
		if root.general[k] == nil then root.general[k] = v end
	end
	return root
end

-- Each module calls this once at load with its own namespace key and a
-- defaults table. Returns an accessor that always returns that module's
-- current, fully-populated SavedVariables sub-table.
--
-- IMPORTANT: WoW loads the real SavedVariables data from disk AFTER all
-- of an addon's files have executed, and ASSIGNS it wholesale to the
-- global table name - overwriting whatever's already in memory at that
-- point, including any sub-tables built here at file-load time. So the
-- accessor re-checks and re-guards on every call rather than trusting
-- the one-time setup above to have survived - it can't assume nothing
-- has replaced VenomancerAssistantDB since then.
function Core.RegisterModuleDB(namespaceKey, defaults)
	local root = Core.GetRootDB()
	InitSubTable(root, namespaceKey)

	return function()
		local sub = VenomancerAssistantDB[namespaceKey]
		if not sub then
			sub = InitSubTable(VenomancerAssistantDB, namespaceKey)
		end
		for k, v in pairs(defaults) do
			if sub[k] == nil then
				sub[k] = v
			end
		end
		return sub
	end
end

--------------------------------------------------------------------------------
-- Form detection - spellbook based, so it reacts correctly to dual-spec
-- swaps without needing a /reload.
--------------------------------------------------------------------------------

Core.FORMS = {
	spider = { spellID = 800841, name = "Spider Form" },
	beetle = { spellID = 803183, name = "Beetle Form" },
	weaver = { spellID = 804980, name = "Weaver Form" },
	vizier = { spellID = 800912, name = "Vizier Form" },
}

-- IsSpellKnown is the fast path; if a custom Ascension spell ID doesn't
-- resolve cleanly through it, fall back to a spellbook name scan so a
-- learned form never gets hidden just because one API didn't recognize it.
function Core.IsFormLearned(formKey)
	local def = Core.FORMS[formKey]
	if not def then return false end

	if IsSpellKnown then
		local ok, known = pcall(IsSpellKnown, def.spellID)
		if ok and known then return true end
	end

	return Core.IsSpellLearnedByName(def.name)
end

-- Generic spellbook-name scan, for anything we don't have a reliable
-- spell ID for (e.g. a talent whose ID hasn't been confirmed yet).
function Core.IsSpellLearnedByName(name)
	for i = 1, 500 do
		local spellName = GetSpellBookItemName and GetSpellBookItemName(i, "spell")
		if not spellName then break end
		if spellName == name then return true end
	end
	return false
end

-- Returns the FORMS key ("spider"/"beetle"/...) of whichever tracked form
-- is currently active, or nil if none is (or an untracked form is).
function Core.GetActiveFormKey()
	local numForms = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0
	for i = 1, numForms do
		local _, name, isActive = GetShapeshiftFormInfo(i)
		if isActive then
			for key, def in pairs(Core.FORMS) do
				if def.name == name then return key end
			end
			return nil -- an active form, but not one this addon tracks
		end
	end
	return nil
end

-- Modules register here to be told "a form may have been learned/unlearned,
-- re-check your visibility" - fired on spec swaps, not just login.
local formChangeCallbacks = {}
function Core.OnFormsMaybeChanged(fn)
	formChangeCallbacks[#formChangeCallbacks + 1] = fn
end

local formEvents = CreateFrame("Frame")
formEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
formEvents:RegisterEvent("SPELLS_CHANGED")
formEvents:RegisterEvent("PLAYER_TALENT_UPDATE")
formEvents:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
formEvents:SetScript("OnEvent", function()
	for _, fn in ipairs(formChangeCallbacks) do
		local ok, err = pcall(fn)
		if not ok then
			-- one module's callback erroring shouldn't take the others down
			geterrorhandler()(err)
		end
	end
end)

--------------------------------------------------------------------------------
-- Options panel chrome (colors, media, layout constants)
--------------------------------------------------------------------------------

Core.PANEL_WIDTH = 780
Core.PANEL_HEIGHT = 720
Core.SIDEBAR_WIDTH = 170
Core.TOPBAR_HEIGHT = 56
Core.MARGIN = 16
Core.SCROLLBAR_GUTTER = 20
Core.CONTENT_WIDTH = Core.PANEL_WIDTH - Core.SIDEBAR_WIDTH - Core.MARGIN * 2 - Core.SCROLLBAR_GUTTER
Core.COL_WIDTH = (Core.CONTENT_WIDTH - 16) / 2

Core.ROW_H = 20
Core.ROW_GAP = 6
Core.SLIDER_H = 34
Core.SECTION_HEADER_GAP = 16
Core.SECTION_HEADER_H = 12

Core.C_BG = { 0.035, 0.035, 0.04, 0.98 }
Core.C_SIDEBAR_BG = { 0.06, 0.06, 0.07, 1 }
Core.C_TOPBAR_BG = { 0.05, 0.05, 0.06, 1 }
Core.C_BORDER = { 0.16, 0.16, 0.18, 1 }
Core.C_GOLD = { 1, 0.72, 0.15 }
Core.C_TEXT = { 0.88, 0.88, 0.9 }
Core.C_TEXT_DIM = { 0.5, 0.5, 0.54 }
Core.C_ROW_ACTIVE = { 1, 0.72, 0.15, 0.13 }

Core.MEDIA_NORM_TEX = "Interface\\AddOns\\VenomancerAssistant\\Media\\normTex.tga"
Core.MEDIA_CLOSE = "Interface\\AddOns\\VenomancerAssistant\\Media\\close.tga"
Core.MEDIA_HIGHLIGHT = "Interface\\AddOns\\VenomancerAssistant\\Media\\Highlight.tga"
Core.MEDIA_ARROW = "Interface\\AddOns\\VenomancerAssistant\\Media\\arrow.tga"

local C_BORDER, C_GOLD, C_TEXT, C_TEXT_DIM = Core.C_BORDER, Core.C_GOLD, Core.C_TEXT, Core.C_TEXT_DIM
local CONTENT_WIDTH, COL_WIDTH = Core.CONTENT_WIDTH, Core.COL_WIDTH
local ROW_H, ROW_GAP, SLIDER_H = Core.ROW_H, Core.ROW_GAP, Core.SLIDER_H
local SECTION_HEADER_GAP, SECTION_HEADER_H = Core.SECTION_HEADER_GAP, Core.SECTION_HEADER_H

function Core.FlatTexture(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture("Interface\\Buttons\\WHITE8x8")
	return tex
end

function Core.GradientTexture(parent, layer)
	local tex = parent:CreateTexture(nil, layer or "ARTWORK")
	tex:SetTexture(Core.MEDIA_NORM_TEX)
	return tex
end
local FlatTexture, GradientTexture = Core.FlatTexture, Core.GradientTexture

--------------------------------------------------------------------------------
-- CreateLayoutHelpers: same widget set as before (Section/Note/Checkbox/
-- Slider/Dropdown/ColorSwatch/Button), but now takes the db accessor and
-- change callback as parameters instead of assuming one global table -
-- this is what lets the same helper build pages for four independent
-- modules with four independent SavedVariables tables.
--------------------------------------------------------------------------------

local uidCounter = 0
local function NextUID()
	uidCounter = uidCounter + 1
	return uidCounter
end

function Core.CreateLayoutHelpers(target, dbFn, onChange)
	dbFn = dbFn or Core.GetRootDB
	onChange = onChange or function() end
	local y = -8

	local function AdvanceY(amount) y = y - amount end
	local function GetY() return y end

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

	local function Checkbox(label, key, tooltip, xOffset, widthOverride, extraOnClick)
		local uid = NextUID()
		local check = CreateFrame("Button", "VenomancerAssistantOpt" .. uid, target)
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
			local checked = dbFn()[key]
			if checked then
				box:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
			else
				box:SetVertexColor(0, 0, 0, 0.4)
			end
		end
		Refresh()

		check:SetScript("OnClick", function()
			local d = dbFn()
			d[key] = not d[key]
			Refresh()
			if extraOnClick then extraOnClick(d[key]) end
			onChange()
		end)
		if tooltip then
			check:SetScript("OnEnter", function(self)
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
				GameTooltip:Show()
			end)
			check:SetScript("OnLeave", function() GameTooltip:Hide() end)
		end
		return check, Refresh
	end

	local function CheckboxRow(label, key, tooltip, extraOnClick)
		local check = Checkbox(label, key, tooltip, 0, nil, extraOnClick)
		AdvanceY(ROW_H + ROW_GAP)
		return check
	end

	local function CheckboxPair(labelA, keyA, tipA, labelB, keyB, tipB)
		local a = Checkbox(labelA, keyA, tipA, 0, COL_WIDTH)
		local b = Checkbox(labelB, keyB, tipB, COL_WIDTH + 16, COL_WIDTH)
		AdvanceY(ROW_H + ROW_GAP)
		return a, b
	end

	local function Slider(label, key, min, max, step, onChangeExtra)
		local function GetVal() return dbFn()[key] or min end

		local sliderLabel = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(sliderLabel, 2)
		sliderLabel:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		sliderLabel:SetText(label .. ": " .. tostring(GetVal()))
		AdvanceY(16)

		local slider = CreateFrame("Slider", "VenomancerAssistantOpt" .. NextUID(), target)
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
			dbFn()[key] = value
			sliderLabel:SetText(label .. ": " .. tostring(value))
			if onChangeExtra then onChangeExtra(value) end
			onChange()
		end)
		AdvanceY(SLIDER_H - 16)
		return slider
	end

	local function Button(label, onClick)
		local btn = CreateFrame("Button", nil, target)
		btn:SetSize(180, 24)
		btn:RegisterForClicks("LeftButtonUp")
		PlaceLeft(btn, 0)

		local bg = GradientTexture(btn, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetVertexColor(1, 1, 1, 0.05)
		local border = CreateFrame("Frame", nil, btn)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture(Core.MEDIA_HIGHLIGHT)
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

	local function ColorSwatch(label, key)
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

		local function Refresh()
			local c = dbFn()[key] or { 1, 1, 1 }
			fill:SetVertexColor(c[1], c[2], c[3], 1)
		end
		Refresh()

		swatch:SetScript("OnClick", function()
			local original = dbFn()[key] or { 1, 1, 1 }
			local function ApplyColor()
				local r, g, b = ColorPickerFrame:GetColorRGB()
				dbFn()[key] = { r, g, b }
				Refresh()
				onChange()
			end
			ColorPickerFrame.hasOpacity = false
			ColorPickerFrame.func = ApplyColor
			ColorPickerFrame.cancelFunc = function()
				dbFn()[key] = original
				Refresh()
				onChange()
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
		return swatch
	end

	local function Dropdown(label, key, choices, onChangeExtra)
		local lbl = target:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		PlaceLeft(lbl, 2)
		lbl:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
		lbl:SetText(label)
		AdvanceY(18)

		local ddButton = CreateFrame("Button", nil, target)
		ddButton:SetSize(CONTENT_WIDTH, 22)
		PlaceLeft(ddButton, 0)
		local bg = GradientTexture(ddButton, "BACKGROUND")
		bg:SetAllPoints()
		bg:SetVertexColor(1, 1, 1, 0.07)
		local border = CreateFrame("Frame", nil, ddButton)
		border:SetAllPoints()
		border:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		border:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local ddHighlight = ddButton:CreateTexture(nil, "HIGHLIGHT")
		ddHighlight:SetTexture(Core.MEDIA_HIGHLIGHT)
		ddHighlight:SetAllPoints()
		ddHighlight:SetBlendMode("ADD")
		ddHighlight:SetAlpha(0.15)
		ddButton:SetHighlightTexture(ddHighlight)

		local ddText = ddButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		ddText:SetPoint("LEFT", 10, 0)
		ddText:SetPoint("RIGHT", -22, 0)
		ddText:SetJustifyH("LEFT")
		ddText:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])

		local arrow = ddButton:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(10, 10)
		arrow:SetPoint("RIGHT", -8, 0)
		arrow:SetTexture(Core.MEDIA_ARROW)
		arrow:SetTexCoord(0, 1, 1, 0) -- arrow.tga points up; flip vertically so closed = points down
		arrow:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)

		local function CurrentLabel()
			local val = dbFn()[key]
			for _, c in ipairs(choices) do
				if c.value == val then return c.label end
			end
			return tostring(val)
		end
		ddText:SetText(CurrentLabel())

		local listFrame = CreateFrame("Frame", nil, UIParent)
		listFrame:SetFrameStrata("TOOLTIP")
		-- Same strata as the options panel itself (both TOOLTIP, the
		-- highest available) - being parented straight to UIParent gives
		-- this a low frame level by default, so it was losing to the
		-- panel's own nested sub-tab buttons. Force it comfortably above
		-- whatever level this panel's content has reached.
		listFrame:SetFrameLevel((target:GetFrameLevel() or 1) + 50)
		listFrame:SetWidth(CONTENT_WIDTH)
		listFrame:SetHeight(#choices * 20 + 4)
		listFrame:SetPoint("TOP", ddButton, "BOTTOM", 0, -2)
		listFrame:Hide()
		local listBG = FlatTexture(listFrame, "BACKGROUND")
		listBG:SetAllPoints()
		listBG:SetVertexColor(0.05, 0.05, 0.06, 1)
		local listBorder = CreateFrame("Frame", nil, listFrame)
		listBorder:SetAllPoints()
		listBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
		listBorder:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

		local function CloseList()
			listFrame:Hide()
			arrow:SetTexCoord(0, 1, 1, 0)
		end

		for i, c in ipairs(choices) do
			local row = CreateFrame("Button", nil, listFrame)
			row:SetSize(CONTENT_WIDTH, 20)
			row:SetPoint("TOPLEFT", 0, -(i - 1) * 20 - 2)
			local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			rowText:SetPoint("LEFT", 6, 0)
			rowText:SetText(c.label)
			rowText:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])
			local rowHL = row:CreateTexture(nil, "HIGHLIGHT")
			rowHL:SetAllPoints()
			rowHL:SetTexture(Core.MEDIA_HIGHLIGHT)
			rowHL:SetBlendMode("ADD")
			rowHL:SetAlpha(0.2)
			row:SetScript("OnClick", function()
				dbFn()[key] = c.value
				ddText:SetText(c.label)
				CloseList()
				if onChangeExtra then onChangeExtra(c.value) end
				onChange()
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
		AdvanceY(22 + ROW_GAP)
		return ddButton
	end

	return {
		AdvanceY = AdvanceY, GetY = GetY,
		Section = Section, Note = Note,
		CheckboxRow = CheckboxRow, CheckboxPair = CheckboxPair,
		Slider = Slider, Button = Button, ColorSwatch = ColorSwatch, Dropdown = Dropdown,
	}
end

--------------------------------------------------------------------------------
-- CreateSubTabPager - unchanged in behavior, works for any nesting depth
-- since it only ever touches the `container` frame it's given.
--------------------------------------------------------------------------------

function Core.CreateSubTabPager(container, defs, startY)
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
		highlight:SetTexture(Core.MEDIA_HIGHLIGHT)
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
		content:SetHeight(1)
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

--------------------------------------------------------------------------------
-- Lockable module registry - each independently-draggable frame registers
-- itself here so the title bar's master Lock pill can override every
-- individual lock at once and refresh each frame's visuals immediately.
--------------------------------------------------------------------------------

Core.LockableModules = {}

-- entry = { dbFn = function() ... end, apply = function() ... end }
-- `apply` should re-check dbFn().locked and refresh both the drag handle
-- visibility and the frame's own display - called right after the master
-- pill changes the value, so it can't wait for that module's own poller.
function Core.RegisterLockable(entry)
	Core.LockableModules[#Core.LockableModules + 1] = entry
end

-- Minimal one-shot timer (3.3.5a has no C_Timer). Used to debounce checks
-- right after zoning, since UnitBuff/UnitDebuff can briefly return
-- nothing while the aura cache is still populating - reading that as a
-- real "zero" would look like a fresh state change the moment the
-- correct read comes through a beat later.
function Core.After(seconds, fn)
	local frame = CreateFrame("Frame")
	local elapsed = 0
	frame:SetScript("OnUpdate", function(self, e)
		elapsed = elapsed + e
		if elapsed >= seconds then
			self:SetScript("OnUpdate", nil)
			fn()
		end
	end)
end

function Core.SkinScrollBar(scrollFrame)
	local barName = scrollFrame:GetName() and (scrollFrame:GetName() .. "ScrollBar")
	local scrollBar = barName and _G[barName]
	if not scrollBar then return end

	local upButton = _G[barName .. "ScrollUpButton"]
	local downButton = _G[barName .. "ScrollDownButton"]
	if upButton then upButton:EnableMouse(false); upButton:Hide() end
	if downButton then downButton:EnableMouse(false); downButton:Hide() end

	if scrollBar.SetBackdrop then scrollBar:SetBackdrop(nil) end

	local track = scrollBar:CreateTexture(nil, "BACKGROUND")
	track:SetPoint("TOP", scrollBar, "TOP", 0, 0)
	track:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, 0)
	track:SetWidth(3)
	track:SetTexture(1, 1, 1, 0.08)

	-- The Blizzard scrollbar is a native Slider widget under the hood.
	-- Try the native GetThumbTexture() first (the guessed global name
	-- _G[barName.."ThumbTexture"] doesn't exist for this built-in
	-- template, which is why every previous attempt silently did nothing
	-- to the thumb and left the default Blizzard knob in place) - fall
	-- back to the global name too, in case this client build differs.
	local thumb = (scrollBar.GetThumbTexture and scrollBar:GetThumbTexture()) or _G[barName .. "ThumbTexture"]
	if thumb then
		thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
		thumb:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 0.85)
		thumb:SetWidth(5)
	end
end
