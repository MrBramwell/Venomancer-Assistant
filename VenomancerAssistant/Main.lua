--[[
	Main - assembles the options panel chrome (topBar/sidebar) from every
	module's BuildXTab function, in sidebar order. The panel is destroyed
	and rebuilt fresh every time it's opened rather than reused, so a form
	learned/unlearned via a spec swap is reflected immediately without a
	/reload.
]]

local Core = VenomancerAssistant

local PANEL_WIDTH, PANEL_HEIGHT = Core.PANEL_WIDTH, Core.PANEL_HEIGHT
local SIDEBAR_WIDTH, TOPBAR_HEIGHT, MARGIN = Core.SIDEBAR_WIDTH, Core.TOPBAR_HEIGHT, Core.MARGIN
local CONTENT_WIDTH = Core.CONTENT_WIDTH
local C_BG, C_SIDEBAR_BG, C_TOPBAR_BG, C_BORDER = Core.C_BG, Core.C_SIDEBAR_BG, Core.C_TOPBAR_BG, Core.C_BORDER
local C_GOLD, C_TEXT, C_ROW_ACTIVE = Core.C_GOLD, Core.C_TEXT, Core.C_ROW_ACTIVE
local FlatTexture, GradientTexture = Core.FlatTexture, Core.GradientTexture
local MEDIA_CLOSE, MEDIA_HIGHLIGHT = Core.MEDIA_CLOSE, Core.MEDIA_HIGHLIGHT

-- Sidebar order. Each entry's Build function may choose not to register a
-- tab at all (form-gated tabs return early if the form isn't learned).
local TAB_BUILDERS = {
	{ key = "general", fn = function(...) Core.BuildGeneralTab(...) end },
	{ key = "spider", fn = function(...) Core.BuildSpiderFormTab(...) end },
	{ key = "beetle", fn = function(...) Core.BuildBeetleFormTab(...) end },
	{ key = "weaver", fn = function(...) Core.BuildWeaverFormTab(...) end },
	{ key = "vizier", fn = function(...) Core.BuildVizierFormTab(...) end },
	{ key = "bufftracking", fn = function(...) Core.BuildBuffTrackingTab(...) end },
	{ key = "venombar", fn = function(...) Core.BuildVenomBarTab(...) end },
	{ key = "manabar", fn = function(...) Core.BuildManaBarTab(...) end },
}

local panel

local function DestroyPanel()
	if panel then
		panel:Hide()
		panel:SetParent(nil)
		panel = nil
	end
end

-- GameTooltip defaults to TOOLTIP strata too - same tier as the options
-- panel, and same bug class as the dropdown list: a shared global frame
-- parented straight to UIParent has a low frame level, so it was losing
-- to the panel's own nested children. Only touch its level when the
-- tooltip actually belongs to something inside our own panel, so
-- tooltips everywhere else in the game are untouched.
GameTooltip:HookScript("OnShow", function(self)
	if not (panel and panel:IsShown()) then return end
	local owner = self:GetOwner()
	local f = owner
	while f do
		if f == panel then
			self:SetFrameLevel(panel:GetFrameLevel() + 100)
			return
		end
		f = f:GetParent()
	end
end)

-- Rebuild on the next open if a spec swap may have changed form
-- availability, instead of tearing the panel down mid-use.
local panelDirty = false
Core.OnFormsMaybeChanged(function() panelDirty = true end)

local generalDB = function() return Core.GetRootDB().general end
local minimapButton -- forward-declared so BuildGeneralTab's closure captures this local, not a global

local lastSelectedTabKey
local RebuildPreservingTab -- forward-declared so lockPill's OnClick (built inside CreateOptionsPanel, defined below) captures this local, not a global

--------------------------------------------------------------------------------
-- Alignment grid - shown whenever anything is unlocked, to help line up
-- trackers/bars against each other and screen center. Center lines are
-- bold red; everything else is a light grey line every 50px, spaced
-- outward symmetrically from center rather than from a screen edge.
--------------------------------------------------------------------------------

local GRID_SPACING = 50

local gridFrame = CreateFrame("Frame", "VAAlignmentGrid", UIParent)
gridFrame:SetAllPoints(UIParent)
gridFrame:SetFrameStrata("FULLSCREEN_DIALOG") -- same tier as the trackers it's meant to help align
gridFrame:EnableMouse(false)
gridFrame:Hide()

local gridLines = {}

local function BuildGrid()
	for _, line in ipairs(gridLines) do line:Hide() end
	wipe(gridLines)

	local w, h = UIParent:GetWidth(), UIParent:GetHeight()
	local centerX, centerY = w / 2, h / 2

	local function VLine(x, isCenter)
		local line = gridFrame:CreateTexture(nil, "OVERLAY")
		line:SetTexture("Interface\\Buttons\\WHITE8x8")
		if isCenter then
			line:SetVertexColor(1, 0.15, 0.15, 0.95)
			line:SetWidth(3)
		else
			line:SetVertexColor(1, 1, 1, 0.15)
			line:SetWidth(1)
		end
		line:SetPoint("TOP", gridFrame, "TOPLEFT", x, 0)
		line:SetPoint("BOTTOM", gridFrame, "BOTTOMLEFT", x, 0)
		gridLines[#gridLines + 1] = line
	end

	local function HLine(y, isCenter)
		local line = gridFrame:CreateTexture(nil, "OVERLAY")
		line:SetTexture("Interface\\Buttons\\WHITE8x8")
		if isCenter then
			line:SetVertexColor(1, 0.15, 0.15, 0.95)
			line:SetHeight(3)
		else
			line:SetVertexColor(1, 1, 1, 0.15)
			line:SetHeight(1)
		end
		line:SetPoint("LEFT", gridFrame, "TOPLEFT", 0, -y)
		line:SetPoint("RIGHT", gridFrame, "TOPRIGHT", 0, -y)
		gridLines[#gridLines + 1] = line
	end

	VLine(centerX, true)
	local x = centerX + GRID_SPACING
	while x <= w do VLine(x, false); x = x + GRID_SPACING end
	x = centerX - GRID_SPACING
	while x >= 0 do VLine(x, false); x = x - GRID_SPACING end

	HLine(centerY, true)
	local y = centerY + GRID_SPACING
	while y <= h do HLine(y, false); y = y + GRID_SPACING end
	y = centerY - GRID_SPACING
	while y >= 0 do HLine(y, false); y = y - GRID_SPACING end
end

local function AnyUnlocked()
	for _, entry in ipairs(Core.LockableModules) do
		if not entry.dbFn().locked then return true end
	end
	return false
end

local gridResizeFrame = CreateFrame("Frame")
gridResizeFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
gridResizeFrame:RegisterEvent("UI_SCALE_CHANGED")
gridResizeFrame:SetScript("OnEvent", BuildGrid)

local gridWasShown = false
local gridTicker = CreateFrame("Frame")
local gridElapsed = 0
gridTicker:SetScript("OnUpdate", function(self, e)
	gridElapsed = gridElapsed + e
	if gridElapsed < 0.3 then return end
	gridElapsed = 0
	local shouldShow = generalDB().showGridWhenUnlocked and AnyUnlocked()
	if shouldShow and not gridWasShown then
		-- Rebuild right as it's about to show, using whatever UIParent
		-- reports right now - building once at ADDON_LOADED (very early,
		-- before the UI has necessarily settled to its true resolution/
		-- scale) was the actual bug behind the grid being off-center.
		BuildGrid()
	end
	gridWasShown = shouldShow
	gridFrame:SetShown(shouldShow)
end)

local function CreateOptionsPanel()
	local p = CreateFrame("Frame", "VenomancerAssistantOptionsFrame", UIParent)
	p:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
	p:SetPoint("CENTER")
	p:SetFrameStrata("TOOLTIP") -- above the HUD frames (FULLSCREEN_DIALOG), so it's never covered by them
	p:SetMovable(true)
	p:EnableMouse(true)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", p.StartMoving)
	p:SetScript("OnDragStop", p.StopMovingOrSizing)
	tinsert(UISpecialFrames, "VenomancerAssistantOptionsFrame")

	local bg = FlatTexture(p, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetVertexColor(C_BG[1], C_BG[2], C_BG[3], C_BG[4])
	local outerBorder = CreateFrame("Frame", nil, p)
	outerBorder:SetAllPoints()
	outerBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	outerBorder:SetBackdropBorderColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

	local topBar = CreateFrame("Frame", nil, p)
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

	local title = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("LEFT", MARGIN, 0)
	title:SetText("Venomancer Assistant")
	title:SetTextColor(C_GOLD[1], C_GOLD[2], C_GOLD[3])

	local closeBtn = CreateFrame("Button", nil, topBar)
	closeBtn:SetSize(24, 24)
	closeBtn:SetPoint("RIGHT", -MARGIN, 0)
	local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
	closeTex:SetAllPoints()
	closeTex:SetTexture(MEDIA_CLOSE)
	local closeHighlight = closeBtn:CreateTexture(nil, "HIGHLIGHT")
	closeHighlight:SetAllPoints()
	closeHighlight:SetTexture(MEDIA_CLOSE)
	closeHighlight:SetVertexColor(0.9, 0.25, 0.25, 1)
	closeBtn:SetHighlightTexture(closeHighlight)
	closeBtn:SetScript("OnClick", function() p:Hide() end)

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
		local locked = generalDB().masterLocked
		lockBG:SetVertexColor(locked and C_GOLD[1] or 1, locked and C_GOLD[2] or 1, locked and C_GOLD[3] or 1, locked and 0.85 or 0.08)
		lockText:SetText(locked and "Locked" or "Unlocked")
		lockText:SetTextColor(locked and 0 or C_TEXT[1], locked and 0 or C_TEXT[2], locked and 0 or C_TEXT[3])
	end
	RefreshLockPill()
	lockPill:SetScript("OnClick", function()
		local newLocked = not generalDB().masterLocked
		generalDB().masterLocked = newLocked
		for _, entry in ipairs(Core.LockableModules) do
			entry.dbFn().locked = newLocked
			entry.apply()
		end
		-- Rebuild the panel so every "Locked" checkbox across every tab
		-- reflects the new state too, not just the frames themselves.
		RebuildPreservingTab()
	end)

	local sidebar = CreateFrame("Frame", nil, p)
	sidebar:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, 0)
	sidebar:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 0, 0)
	sidebar:SetWidth(SIDEBAR_WIDTH)
	local sidebarBG = FlatTexture(sidebar, "BACKGROUND")
	sidebarBG:SetAllPoints()
	sidebarBG:SetVertexColor(C_SIDEBAR_BG[1], C_SIDEBAR_BG[2], C_SIDEBAR_BG[3], 1)
	local sidebarLine = FlatTexture(sidebar, "ARTWORK")
	sidebarLine:SetPoint("TOPRIGHT", 0, 0)
	sidebarLine:SetPoint("BOTTOMRIGHT", 0, 0)
	sidebarLine:SetWidth(1)
	sidebarLine:SetVertexColor(C_BORDER[1], C_BORDER[2], C_BORDER[3], 1)

	local navButtons, tabContents, tabOrder, tabLabels, tabIcons = {}, {}, {}, {}, {}

	local function SelectTab(tabKey)
		lastSelectedTabKey = tabKey
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

		local scrollFrame = CreateFrame("ScrollFrame", "VenomancerAssistantOptTab" .. key .. "Scroll", p, "UIPanelScrollFrameTemplate")
		scrollFrame:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", MARGIN, -12)
		scrollFrame:SetSize(CONTENT_WIDTH, contentHeight)
		scrollFrame:Hide()
		Core.SkinScrollBar(scrollFrame)

		local scrollChild = CreateFrame("Frame", nil, scrollFrame)
		scrollChild:SetWidth(CONTENT_WIDTH)
		scrollChild:SetHeight(1)
		scrollFrame:SetScrollChild(scrollChild)

		tabContents[key] = scrollChild
		return scrollChild
	end

	for _, entry in ipairs(TAB_BUILDERS) do
		entry.fn(RegisterTab, Core.CreateLayoutHelpers, Core.CreateSubTabPager)
	end

	local navY = -10
	for _, key in ipairs(tabOrder) do
		local btn = CreateFrame("Button", nil, sidebar)
		btn:RegisterForClicks("LeftButtonUp")
		btn:SetPoint("TOPLEFT", 0, navY)
		btn:SetPoint("TOPRIGHT", 0, navY)
		btn:SetHeight(32)

		local bg2 = FlatTexture(btn, "BACKGROUND")
		bg2:SetAllPoints()
		bg2:SetVertexColor(0, 0, 0, 0)

		local stripe = FlatTexture(btn, "ARTWORK")
		stripe:SetPoint("TOPLEFT", 0, 0)
		stripe:SetPoint("BOTTOMLEFT", 0, 0)
		stripe:SetWidth(2)
		stripe:SetVertexColor(C_GOLD[1], C_GOLD[2], C_GOLD[3], 1)
		stripe:Hide()

		local icon = btn:CreateTexture(nil, "ARTWORK")
		icon:SetSize(18, 18)
		icon:SetPoint("LEFT", 12, 0)
		icon:SetTexture(tabIcons[key])
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

		local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		text:SetPoint("LEFT", icon, "RIGHT", 8, 0)
		text:SetText(tabLabels[key])
		text:SetTextColor(C_TEXT[1], C_TEXT[2], C_TEXT[3])

		local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetTexture(MEDIA_HIGHLIGHT)
		highlight:SetAllPoints()
		highlight:SetBlendMode("ADD")
		highlight:SetAlpha(0.12)
		btn:SetHighlightTexture(highlight)

		btn.bg, btn.stripe, btn.text = bg2, stripe, text
		navButtons[key] = btn
		btn:SetScript("OnClick", function() SelectTab(key) end)

		navY = navY - 32
	end

	if tabOrder[1] then
		if lastSelectedTabKey and tabContents[lastSelectedTabKey] then
			SelectTab(lastSelectedTabKey)
		else
			SelectTab(tabOrder[1])
		end
	end

	return p
end

local function OpenPanel()
	if panel and panelDirty then
		DestroyPanel()
		panelDirty = false
	end
	if not panel then
		panel = CreateOptionsPanel()
	end
	panel:Show()
end

local function TogglePanel()
	if panel and panel:IsShown() then
		panel:Hide()
	else
		OpenPanel()
	end
end

-- Used by the master Lock pill: rebuilds the panel immediately (so every
-- "Locked" checkbox on every tab reflects the new state) while staying on
-- whichever tab was open, at whichever position it was dragged to.
function RebuildPreservingTab()
	local wasShown = panel and panel:IsShown()
	local point, relativeTo, relativePoint, x, y
	if panel then
		point, relativeTo, relativePoint, x, y = panel:GetPoint()
	end
	DestroyPanel()
	panel = CreateOptionsPanel()
	if point then
		panel:ClearAllPoints()
		panel:SetPoint(point, relativeTo or UIParent, relativePoint, x, y)
	end
	if wasShown then panel:Show() end
end

Core.TogglePanel = TogglePanel

function Core.BuildGeneralTab(RegisterTab, CreateLayoutHelpers, CreateSubTabPager)
	local sc = RegisterTab("general", "General", "Interface\\Icons\\Trade_Engineering")
	local L = CreateLayoutHelpers(sc, generalDB, function() end)

	local credits = sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	credits:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, L.GetY())
	credits:SetWidth(Core.CONTENT_WIDTH)
	credits:SetJustifyH("LEFT")
	credits:SetTextColor(Core.C_TEXT_DIM[1], Core.C_TEXT_DIM[2], Core.C_TEXT_DIM[3])
	credits:SetText("Venomancer Assistant - Made by Falliia ~ Rexxar.\n\nFor bug reports or feature requests, please reach out ingame, or via:")
	L.AdvanceY(48)

	-- A read-only, auto-select EditBox so the link is actually copyable
	-- (Ctrl+C) - plain FontString text can't be selected/copied at all.
	local LINK_TEXT = "https://github.com/MrBramwell/Venomancer-Assistant"
	local linkBox = CreateFrame("EditBox", nil, sc)
	linkBox:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, L.GetY())
	linkBox:SetSize(Core.CONTENT_WIDTH - 4, 20)
	linkBox:SetAutoFocus(false)
	linkBox:SetFontObject(GameFontHighlightSmall)
	linkBox:SetText(LINK_TEXT)
	linkBox:SetCursorPosition(0)
	local linkBoxBG = Core.FlatTexture(linkBox, "BACKGROUND")
	linkBoxBG:SetAllPoints()
	linkBoxBG:SetVertexColor(1, 1, 1, 0.05)
	local linkBoxBorder = CreateFrame("Frame", nil, linkBox)
	linkBoxBorder:SetAllPoints()
	linkBoxBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
	linkBoxBorder:SetBackdropBorderColor(Core.C_BORDER[1], Core.C_BORDER[2], Core.C_BORDER[3], 1)
	linkBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
	linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	linkBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	-- Actually read-only: any edit snaps straight back to the real link,
	-- so typing + Enter can never leave it changed, this session or not.
	linkBox:SetScript("OnTextChanged", function(self)
		if self:GetText() ~= LINK_TEXT then
			self:SetText(LINK_TEXT)
			self:HighlightText()
		end
	end)
	L.AdvanceY(30)

	L.CheckboxRow("Show minimap button", "minimapButtonShown", "Show or hide the draggable minimap icon that opens these options.", function()
		minimapButton:SetShown(generalDB().minimapButtonShown)
	end)
	L.CheckboxRow("Draw grid when unlocked", "showGridWhenUnlocked", "Shows an alignment grid across the screen whenever anything is unlocked for repositioning. Center lines are bold red; the rest are a light grey, every 50px.")
	sc:SetHeight(-L.GetY() + 20)
end

--------------------------------------------------------------------------------
-- Minimap button
--------------------------------------------------------------------------------

minimapButton = CreateFrame("Button", "VenomancerAssistantMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(20, 20)
mmIcon:SetPoint("CENTER", 0, 0)
mmIcon:SetTexture("Interface\\Icons\\Ability_Hunter_Pet_Spider")
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local mmBorder = minimapButton:CreateTexture(nil, "OVERLAY")
mmBorder:SetSize(53, 53)
mmBorder:SetPoint("TOPLEFT", 0, 0)
mmBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function UpdateMinimapPosition()
	local d = generalDB()
	local angle = math.rad(d.minimapAngle or 225)
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
		local d = generalDB()
		d.minimapAngle = math.deg(math.atan2(py - my, px - mx))
		UpdateMinimapPosition()
	end)
end)
minimapButton:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
minimapButton:SetScript("OnClick", function() TogglePanel() end)
minimapButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText("Venomancer Assistant")
	GameTooltip:AddLine("Click to open settings", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("ADDON_LOADED")
loadFrame:SetScript("OnEvent", function(self, event, arg1)
	if arg1 ~= Core.ADDON_NAME then return end
	UpdateMinimapPosition()
	minimapButton:SetShown(generalDB().minimapButtonShown)
	self:UnregisterEvent("ADDON_LOADED")
end)
