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
function Frame:EnableMouseWheel(enabled) self.mouseWheel = enabled end
function Frame:CreateTexture() return Frame:new(nil, self) end
function Frame:CreateFontString() return Frame:new(nil, self) end
function Frame:SetTexture(texture) self.texture = texture end
function Frame:SetTexCoord(...) self.texCoord = {...} end
function Frame:SetBlendMode(mode) self.blendMode = mode end
function Frame:SetVertexColor(...) self.vertexColor = {...} end
function Frame:SetScript(kind, callback) self.scripts[kind] = callback end
function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:RegisterForClicks(...) self.clicks = {...} end
function Frame:SetID(id) self.id = id end
function Frame:SetText(text) self.text = text end
function Frame:GetText() return self.text end
function Frame:Show() self.shown = true end
function Frame:Hide() self.shown = false end
function Frame:IsShown() return self.shown end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:SetChecked(value) self.checked = value end
function Frame:GetChecked() return self.checked end
function Frame:GetParent() return self.parent end
function Frame:GetObjectType() return self.objectType or "Frame" end
function Frame:GetRegions() return (table.unpack or unpack)(self.regions or {}) end
function Frame:HighlightText() self.highlighted = true end

local anonymousFrames = {}
function CreateFrame(_, name, parent)
    local frame = Frame:new(name, parent)
    if not name then table.insert(anonymousFrames, frame) end
    return frame
end

BankFrame = Frame:new("BankFrame")
BankFrame.frameLevel = 4
BankFrame:Hide()
BankFrameTitleText = Frame:new("BankFrameTitleText", BankFrame)
BankFrameTitleText.objectType = "FontString"
local itemLabel, bagLabel = Frame:new(nil, BankFrame), Frame:new(nil, BankFrame)
itemLabel.objectType, bagLabel.objectType = "FontString", "FontString"
BankFrame.regions = {BankFrameTitleText, itemLabel, bagLabel}
NUM_BANKGENERIC_SLOTS, NUM_BANKBAGSLOTS = 28, 7
for index = 1, NUM_BANKGENERIC_SLOTS do Frame:new("BankFrameItem" .. index, BankFrame) end
for index = 1, NUM_BANKBAGSLOTS do Frame:new("BankFrameBag" .. index, BankFrame) end
BankFrameMoneyFrame = Frame:new("BankFrameMoneyFrame", BankFrame)
BankFramePurchaseInfo = Frame:new("BankFramePurchaseInfo", BankFrame)
BankFramePurchaseButton = Frame:new("BankFramePurchaseButton", BankFrame)
BankFrameDetailMoneyFrame = Frame:new("BankFrameDetailMoneyFrame", BankFrame)

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

for slot = 1, 42 do assert(_G["NativeReagentsItem" .. slot], "missing reagent item button " .. slot) end
assert(NativeReagentsBankTab.points[1][1] == "BOTTOMLEFT", "Bank tab is not anchored below BankFrame")
assert(NativeReagentsBankTab.points[1][2] == BankFrame, "Bank tab lost its BankFrame anchor")

lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_OPENED")
assert(NativeReagentsBankTab.shown and NativeReagentsReagentTab.shown, "tabs are hidden at an open bank")
assert(NativeReagentsBankTab.selected and not NativeReagentsBankFrame.shown, "Bank must be the default page")

NativeReagentsReagentTab.scripts.OnClick()
assert(NativeReagentsBankFrame.shown and NativeReagentsReagentTab.selected, "Reagents page was not selected")
for index = 1, 28 do assert(not _G["BankFrameItem" .. index].shown, "stock bank slot leaked through") end
for index = 1, 7 do assert(not _G["BankFrameBag" .. index].shown, "stock bank bag leaked through") end
assert(not itemLabel.shown and not bagLabel.shown and BankFrameTitleText.shown, "stock labels or banker title visibility is wrong")
assert(NativeReagentsBankFrame.statusText.text == "No reagents stored", "empty state was not rendered")

for id = 1, 43 do NativeReagents.items[id] = id * 100 end
Fire("ITEMS_UPDATED")
assert(NativeReagentsBankFrame.pageText.text == "Page 1 of 2", "multi-page count is wrong")
NativeReagentsNext.scripts.OnClick()
assert(NativeReagentsBankFrame.pageText.text == "Page 2 of 2", "next-page navigation failed")
assert(NativeReagentsItem1.itemId == 43 and NativeReagentsItem1.itemCount == 4300, "second page did not render")

NativeReagentsBankTab.scripts.OnClick()
assert(not NativeReagentsBankFrame.shown and NativeReagentsBankTab.selected, "Bank page was not restored")
for index = 1, 28 do assert(_G["BankFrameItem" .. index].shown, "stock bank slot was not restored") end
for index = 1, 7 do assert(_G["BankFrameBag" .. index].shown, "stock bank bag was not restored") end
assert(itemLabel.shown and bagLabel.shown and BankFrameTitleText.shown, "stock labels were not restored")

NativeReagentsReagentTab.scripts.OnClick()
lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_CLOSED")
assert(not NativeReagentsBankTab.shown and not NativeReagentsReagentTab.shown, "tabs survived bank close")
lifecycle.scripts.OnEvent(lifecycle, "BANKFRAME_OPENED")
assert(NativeReagentsBankTab.selected and not NativeReagentsBankFrame.shown, "reopened bank did not default to Bank")

print("PASS Lua bank UI construction, empty/populated paging, switching, close/reopen restoration")
