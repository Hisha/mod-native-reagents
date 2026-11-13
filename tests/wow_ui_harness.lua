local Frame = {}
Frame.__index = Frame

function Frame:new(name, parent)
    local value = setmetatable({name = name, parent = parent, shown = true, enabled = true,
        scripts = {}, events = {}, points = {}, frameLevel = 1}, self)
    if name then _G[name] = value end
    return value
end
function Frame:ClearAllPoints() self.points = {} end
function Frame:SetPoint(...) table.insert(self.points, {...}) end
function Frame:SetAllPoints() self.allPoints = true end
function Frame:SetSize(width, height) self.width, self.height = width, height end
function Frame:SetFrameLevel(level) self.frameLevel = level end
function Frame:GetFrameLevel() return self.frameLevel end
function Frame:GetName() return self.name end
function Frame:GetWidth() return self.width end
function Frame:GetHeight() return self.height end
function Frame:GetEffectiveScale() return 1 end
function Frame:GetFrameStrata() return "MEDIUM" end
function Frame:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function Frame:CreateTexture() return Frame:new(nil, self) end
function Frame:CreateFontString() return Frame:new(nil, self) end
function Frame:SetTexture(...) self.texture = {...} end
function Frame:GetNormalTexture() return self.normalTexture end
function Frame:SetTexCoord(...) self.texCoord = {...} end
function Frame:SetBlendMode(mode) self.blendMode = mode end
function Frame:SetVertexColor(...) self.vertexColor = {...} end
function Frame:SetScript(kind, callback) self.scripts[kind] = callback end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:RegisterForClicks(...) self.clicks = {...} end
function Frame:SetID(id) self.id = id end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text end
function Frame:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown then
        if self.scripts.OnShow then self.scripts.OnShow(self) end
        for _, callback in ipairs((self.hooks and self.hooks.OnShow) or {}) do callback(self) end
    end
end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetChecked(value) self.checked = value end
function Frame:GetChecked() return self.checked end
function Frame:GetParent() return self.parent end
function Frame:SetParent(parent) self.parent = parent end
function Frame:GetObjectType() return self.objectType or "Frame" end
function Frame:GetRegions() return (table.unpack or unpack)(self.regions or {}) end
function Frame:HighlightText() self.highlighted = true end
function Frame:HookScript(kind, callback)
    self.hooks = self.hooks or {}
    self.hooks[kind] = self.hooks[kind] or {}
    table.insert(self.hooks[kind], callback)
end

local anonymousFrames = {}
function CreateFrame(_, name, parent)
    local frame = Frame:new(name, parent)
    frame.normalTexture = Frame:new(nil, frame)
    if not name then table.insert(anonymousFrames, frame) end
    return frame
end

BankFrame = Frame:new("BankFrame")
BankFrame.frameLevel = 4
BankFrame:SetSize(425, 512)
BankFrame:Hide()
BankPortraitTexture = Frame:new("BankPortraitTexture", BankFrame)
BankPortraitTexture.objectType = "Texture"
local stockArtwork = Frame:new(nil, BankFrame)
stockArtwork.objectType = "Texture"
stockArtwork:SetTexture("Interface\\BankFrame\\UI-BankFrame")
BankFrameTitleText = Frame:new("BankFrameTitleText", BankFrame)
BankFrameTitleText.objectType = "FontString"
local itemLabel, bagLabel = Frame:new(nil, BankFrame), Frame:new(nil, BankFrame)
itemLabel.objectType, bagLabel.objectType = "FontString", "FontString"
ITEMSLOTTEXT, BAGSLOTTEXT = "Item Slots", "Bag Slots"
itemLabel:SetText(ITEMSLOTTEXT); bagLabel:SetText(BAGSLOTTEXT)
BankFrame.regions = {BankPortraitTexture, stockArtwork, BankFrameTitleText, itemLabel, bagLabel}
BankCloseButton = Frame:new("BankCloseButton", BankFrame)
NUM_BANKGENERIC_SLOTS, NUM_BANKBAGSLOTS = 28, 7
local stockButtonRegions = {}
for index = 1, NUM_BANKGENERIC_SLOTS do
    local button = Frame:new("BankFrameItem" .. index, BankFrame)
    local normal, icon = Frame:new(nil, button), Frame:new(nil, button)
    normal.objectType, icon.objectType = "Texture", "Texture"
    button.regions = {normal, icon}; stockButtonRegions[#stockButtonRegions + 1] = normal
end
for index = 1, NUM_BANKBAGSLOTS do
    local button = Frame:new("BankFrameBag" .. index, BankFrame)
    local normal, icon = Frame:new(nil, button), Frame:new(nil, button)
    normal.objectType, icon.objectType = "Texture", "Texture"
    button.regions = {normal, icon}; stockButtonRegions[#stockButtonRegions + 1] = normal
end
BankFrameMoneyFrame = Frame:new("BankFrameMoneyFrame", BankFrame)
BankFramePurchaseInfo = Frame:new("BankFramePurchaseInfo", BankFrame)
BankFramePurchaseButton = Frame:new("BankFramePurchaseButton", BankFramePurchaseInfo)
BankFrameDetailMoneyFrame = Frame:new("BankFrameDetailMoneyFrame", BankFramePurchaseInfo)

function BankFrameItemButton_Update(button) button.updated = (button.updated or 0) + 1 end
function UpdateBagSlotStatus() BankFramePurchaseInfo:Show() end
function BankFrame_OnShow()
    for index = 1, NUM_BANKGENERIC_SLOTS do BankFrameItemButton_Update(_G["BankFrameItem" .. index]) end
    for index = 1, NUM_BANKBAGSLOTS do BankFrameItemButton_Update(_G["BankFrameBag" .. index]) end
    UpdateBagSlotStatus()
end
function BankFrame_OnEvent(_, event)
    if event == "PLAYERBANKSLOTS_CHANGED" then BankFrameItemButton_Update(BankFrameItem1) end
end
function hooksecurefunc(name, callback)
    local original = _G[name]
    _G[name] = function(...)
        original(...)
        callback(...)
    end
end

function PanelTemplates_TabResize() end
function PanelTemplates_SelectTab(frame) frame.selected = true end
function PanelTemplates_DeselectTab(frame) frame.selected = false end
function SetItemButtonTexture(frame, texture) frame.itemTexture = texture end
function SetItemButtonCount(frame, count) frame.itemCount = count end
function GetItemIcon(id) return "icon-" .. id end
function GetItemInfo(id) return string.format("Item %05d", id), "item:" .. id, id % 6, 1, 1, "Trade Goods", "", 20 end
function IsShiftKeyDown() return false end
function StaticPopup_Show() return nil end
function GameTooltip_Hide() end
GameTooltip = {SetOwner = function() end, SetHyperlink = function() end, AddLine = function() end, Show = function() end}
StaticPopupDialogs = {}
ACCEPT, CANCEL = "Accept", "Cancel"

NativeReagents = {items = {}, callbacks = {}, ready = true, available = true, bankOpen = true, auto = false}
function NativeReagents.GetItems() return NativeReagents.items end
function NativeReagents.IsReady() return NativeReagents.ready end
function NativeReagents.GetStatus() return NativeReagents.ready and "ready" or "loading" end
function NativeReagents.GetLastError() return nil end
function NativeReagents.IsAvailable() return NativeReagents.available end
function NativeReagents.IsBankOpen() return NativeReagents.bankOpen end
function NativeReagents.GetAutoDeposit() return NativeReagents.auto end
function NativeReagents.SetAutoDeposit(value) NativeReagents.auto = value; return true end
function NativeReagents.DepositAll() return true end
function NativeReagents.Withdraw() return true end
function NativeReagents.RequestSync() NativeReagents.syncRequests = (NativeReagents.syncRequests or 0) + 1 end
function NativeReagents.GetPresentation() return nil end
function NativeReagents.RegisterCallback(callback) table.insert(NativeReagents.callbacks, callback) end
local function Fire(event) for _, callback in ipairs(NativeReagents.callbacks) do callback(event) end end

dofile("content/client/Interface/FrameXML/NativeReagentsBank.lua")

local lifecycle
for _, frame in ipairs(anonymousFrames) do
    if frame.events.BANKFRAME_OPENED then lifecycle = frame end
end
assert(lifecycle and lifecycle.scripts.OnEvent, "bank lifecycle frame was not initialized")
lifecycle.scripts.OnEvent(lifecycle, "PLAYER_LOGIN")

for slot = 1, 35 do assert(_G["NativeReagentsItem" .. slot], "missing reagent item button " .. slot) end
assert(not _G.NativeReagentsItem36, "sixth reagent row was unexpectedly created")
assert(NativeReagentsTabAnchor.points[1][1] == "BOTTOMLEFT", "tab anchor lost its BankFrame edge")
assert(NativeReagentsTabAnchor.points[1][2] == BankFrame, "tab anchor lost BankFrame parent geometry")
assert(NativeReagentsTabAnchor.points[1][3] == "BOTTOMLEFT", "tab anchor is not based on BankFrame bottom")
assert(NativeReagentsTabAnchor.points[1][4] == 11, "tab anchor lost the stock horizontal inset")
assert(NativeReagentsTabAnchor.points[1][5] == 92, "tab anchor is not flush with the bottom-border junction")
assert(NativeReagentsBankTab.points[1][2] == NativeReagentsTabAnchor, "Bank tab is not attached to the visible-border anchor")
assert(NativeReagentsBankTab.points[1][3] == "BOTTOMLEFT", "Bank tab is not attached beneath the visible border")
for slot = 1, 35 do
    local button = _G["NativeReagentsItem" .. slot]
    assert(button.width == 37 and button.height == 37, "reagent slot dimensions changed")
    assert(button.normalTexture.texture[1] == "Interface\\Buttons\\UI-Quickslot2", "reagent slot lost stock artwork")
end
assert(NativeReagentsItem2.points[1][4] - NativeReagentsItem1.points[1][4] == 49, "horizontal slot pitch is not stock geometry")
assert(NativeReagentsItem8.points[1][5] - NativeReagentsItem1.points[1][5] == -44, "vertical slot pitch is not stock geometry")
assert(NativeReagentsPrevious.points[1][5] > NativeReagentsDepositButton.points[1][5], "pagination overlaps deposit controls")
assert(NativeReagentsDepositButton.parent == NativeReagentsBankFrame.controls, "deposit button is outside bottom controls")
assert(NativeReagentsAutoDeposit.parent == NativeReagentsBankFrame.controls, "auto-deposit is outside bottom controls")
assert(NativeReagentsBankFrame.controls.points[1][5] == 8, "bottom controls are not inset from the visible border")
assert(NativeReagentsBankFrame.points[1][5] == -68 and NativeReagentsBankFrame.points[2][5] == 92,
    "reagent page is not bounded by the stock artwork interior")
assert(#NativeReagentsBankFrame.backgroundTiles == 5, "stock bank background does not cover the reagent page")
for index, tile in ipairs(NativeReagentsBankFrame.backgroundTiles) do
    assert(tile.texture[1] == "Interface\\BankFrame\\UI-BankFrame", "background tile lost stock bank artwork")
    assert(tile.width == 360 and tile.height == (index < 5 and 72 or 64),
        "background tile changed the stock crop proportions")
    assert(tile.texCoord[1] == 22 / 512 and tile.texCoord[2] == 382 / 512 and tile.texCoord[3] == 318 / 512,
        "background tile changed the stock crop coordinates")
end

BankFrame:Show()
lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_OPENED")
assert(NativeReagentsBankTab.shown and NativeReagentsReagentTab.shown, "tabs are hidden at an open bank")
assert(NativeReagentsBankTab.selected and not NativeReagentsBankFrame.shown, "Bank must be the default page")

NativeReagentsReagentTab.scripts.OnClick()
assert(NativeReagentsBankFrame.shown and NativeReagentsReagentTab.selected, "Reagents page was not selected")
for index = 1, 28 do assert(not _G["BankFrameItem" .. index].shown, "stock bank slot leaked through") end
for index = 1, 7 do assert(not _G["BankFrameBag" .. index].shown, "stock bank bag leaked through") end
for _, region in ipairs(stockButtonRegions) do assert(not region:IsVisible(), "inherited stock button artwork leaked through") end
assert(not itemLabel.shown and not bagLabel.shown and BankFrameTitleText.shown, "stock labels or banker title visibility is wrong")
assert(stockArtwork:IsVisible(), "shared monolithic BankFrame artwork was hidden")
assert(BankPortraitTexture:IsVisible() and BankCloseButton:IsVisible(), "shared BankFrame controls were hidden")
assert(NativeReagentsBankFrame.statusText.text == "No reagents stored", "empty state was not rendered")

BankFrameItemButton_Update(BankFrameItem1)
UpdateBagSlotStatus()
BankFrame_OnShow()
BankFrame_OnEvent(BankFrame, "PLAYERBANKSLOTS_CHANGED")
for index = 1, 28 do assert(not _G["BankFrameItem" .. index].shown, "stock bank refresh restored item slot " .. index) end
for index = 1, 7 do assert(not _G["BankFrameBag" .. index].shown, "stock bank refresh restored bag slot " .. index) end
assert(not BankFramePurchaseInfo.shown and not BankFrameMoneyFrame.shown, "stock bank controls escaped reagent page")
assert(not itemLabel.shown and not bagLabel.shown, "stock bank labels escaped reagent page")

for id = 1, 36 do NativeReagents.items[id] = id * 100 end
Fire("ITEMS_UPDATED")
assert(NativeReagentsBankFrame.pageText.text == "Page 1 of 2", "multi-page count is wrong")
NativeReagentsNext.scripts.OnClick()
assert(NativeReagentsBankFrame.pageText.text == "Page 2 of 2", "next-page navigation failed")
assert(NativeReagentsItem1.itemId == 36 and NativeReagentsItem1.itemCount == 3600, "second page did not render")

NativeReagentsBankTab.scripts.OnClick()
assert(not NativeReagentsBankFrame.shown and NativeReagentsBankTab.selected, "Bank page was not restored")
for index = 1, 28 do assert(_G["BankFrameItem" .. index].shown, "stock bank slot was not restored") end
for index = 1, 7 do assert(_G["BankFrameBag" .. index].shown, "stock bank bag was not restored") end
assert(itemLabel.shown and bagLabel.shown and BankFrameTitleText.shown, "stock labels were not restored")
assert(BankFramePurchaseInfo.shown and BankFrameMoneyFrame.shown, "stock bank controls were not restored")

for iteration = 1, 3 do
    NativeReagentsReagentTab.scripts.OnClick()
    BankFrame_OnShow()
    assert(not BankFrameItem1.shown and not BankFrameBag1.shown, "stock content escaped on repeated switch " .. iteration)
    NativeReagentsBankTab.scripts.OnClick()
    assert(BankFrameItem1.shown and BankFrameBag1.shown, "stock content failed to restore on repeated switch " .. iteration)
end

NativeReagentsReagentTab.scripts.OnClick()
lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_CLOSED")
assert(not NativeReagentsBankTab.shown and not NativeReagentsReagentTab.shown, "tabs survived bank close")
lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_OPENED")
assert(NativeReagentsBankTab.selected and not NativeReagentsBankFrame.shown, "reopened bank did not default to Bank")

print("PASS Lua bank UI construction, paging, refresh guards, repeated switching, close/reopen restoration")
