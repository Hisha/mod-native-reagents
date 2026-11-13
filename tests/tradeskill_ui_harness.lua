local sent, frames, hooks = {}, {}, {}

local function Widget(shown)
    local widget = { shown = shown ~= false, enabled = true, text = "", width = 20, scripts = {}, events = {} }
    function widget:IsShown() return self.shown end
    function widget:Show() self.shown = true end
    function widget:Hide() self.shown = false end
    function widget:Enable() self.enabled = true end
    function widget:Disable() self.enabled = false end
    function widget:SetText(value) self.text = tostring(value or ""); self.width = #self.text * 6 end
    function widget:GetText() return self.text end
    function widget:GetWidth() return self.width end
    function widget:SetWidth(value) self.setWidth = value; self.width = value end
    function widget:SetNumber(value) self.number = value end
    function widget:GetNumber() return self.number or 1 end
    function widget:ClearFocus() self.focusCleared = true end
    function widget:SetScript(name, callback) self.scripts[name] = callback end
    function widget:RegisterEvent(event) self.events[event] = true end
    return widget
end

function CreateFrame()
    local frame = Widget()
    table.insert(frames, frame)
    return frame
end
function hooksecurefunc(name, callback) hooks[name] = callback end
function SendAddonMessage(prefix, payload, channel, target)
    table.insert(sent, { prefix=prefix, payload=payload, channel=channel, target=target })
end
function UnitName() return "Tester" end
function GetTime() return 100 end
function IsTradeSkillLinked() return false end
function FauxScrollFrame_GetOffset() return 0 end
function DoTradeSkill(index, count) _G.lastStockCraft = { index, count } end

TRADE_SKILLS_DISPLAYED, TRADE_SKILL_TEXT_WIDTH = 8, 275
TradeSkillListScrollFrame = Widget()
TradeSkillFrame = Widget()
TradeSkillFrame.selectedSkill = 4
TradeSkillCreateButton = Widget()
TradeSkillCreateAllButton = Widget()
TradeSkillInputBox = Widget()
TradeSkillFrameDummyString = Widget()
DEFAULT_CHAT_FRAME = { AddMessage = function() end }

local recipes = {
    [1] = { name="Metal", kind="header", stock=0, reagents={} },
    [2] = { name="Inventory Recipe", kind="optimal", stock=5,
        reagents={{ id=100, required=2, carried=10 }} },
    [3] = { name="Bank Recipe", kind="optimal", stock=0,
        reagents={{ id=101, required=2, carried=0 }} },
    [4] = { name="Split Recipe", kind="optimal", stock=0,
        reagents={{ id=102, required=3, carried=4 }, { id=103, required=2, carried=1 }} },
    [5] = { name="Duplicate Recipe", kind="optimal", stock=0,
        reagents={{ id=104, required=2, carried=3 }, { id=104, required=2, carried=3 }} },
}

function GetTradeSkillInfo(index)
    local recipe = recipes[index]
    if not recipe then return nil end
    return recipe.name, recipe.kind, recipe.stock, true
end
function GetTradeSkillNumReagents(index) return recipes[index] and #recipes[index].reagents or 0 end
function GetTradeSkillReagentInfo(index, reagent)
    local row = recipes[index].reagents[reagent]
    return "Reagent", "Texture", row.required, row.carried
end
function GetTradeSkillReagentItemLink(index, reagent)
    return "|Hitem:" .. recipes[index].reagents[reagent].id .. ":0:0:0|h[item]|h"
end
function GetTradeSkillRecipeLink(index) return "|Henchant:" .. (1000 + index) .. "|h[recipe]|h" end
function GetTradeSkillSelectionIndex() return TradeSkillFrame.selectedSkill end
function GetTradeSkillCooldown(index) return recipes[index] and recipes[index].cooldown end

for row = 1, TRADE_SKILLS_DISPLAYED do
    _G["TradeSkillSkill" .. row] = Widget(recipes[row] ~= nil)
    _G["TradeSkillSkill" .. row .. "Text"] = Widget()
    _G["TradeSkillSkill" .. row .. "Text"]:SetText(recipes[row] and recipes[row].name or "")
    _G["TradeSkillSkill" .. row .. "Count"] = Widget()
end
for reagent = 1, 8 do _G["TradeSkillReagent" .. reagent .. "Count"] = Widget() end

function TradeSkillFrame_SetSelection(index) TradeSkillFrame.selectedSkill = index end
function TradeSkillFrame_Update() end

assert(loadfile("content/client/Interface/FrameXML/NativeReagents.lua"))()

local lifecycle
for _, frame in ipairs(frames) do
    if frame.events.CHAT_MSG_ADDON then lifecycle = frame end
end
assert(lifecycle, "Native Reagents event frame was not created")

local function Event(event, ...)
    lifecycle.scripts.OnEvent(lifecycle, event, ...)
end
local function LastRequest(command)
    for index = #sent, 1, -1 do
        local version, request, found, arguments = string.match(sent[index].payload, "^(%d+)|(%d+)|([^|]+)|?(.*)$")
        if found == command then return tonumber(version), tonumber(request), arguments end
    end
    error("missing request " .. command)
end
local function Reply(request, kind, body)
    Event("CHAT_MSG_ADDON", "NRB", "2|" .. request .. "|" .. kind .. (body and "|" .. body or ""), "WHISPER", "Tester")
end
local function CompleteLatestSync(rows)
    local _, request, arguments = LastRequest("SYNC")
    local syncId = tonumber(string.match(arguments, "^(%d+)|0$"))
    assert(syncId, "initial sync page request missing")
    Reply(request, "DATA", syncId .. "|0|1|" .. rows)
end

Event("PLAYER_LOGIN")
local _, helloRequest = LastRequest("HELLO")
Reply(helloRequest, "HELLO", "1|1")
CompleteLatestSync("101:10,102:5,103:10,104:5")

assert(TradeSkillSkill2Count.text == "[5]", "inventory-only list count is wrong")
assert(TradeSkillSkill3Count.text == "[5]", "bank-only list count is wrong")
assert(TradeSkillSkill4Count.text == "[3]", "multi-reagent limiting count is wrong")
assert(TradeSkillSkill5Count.text == "[2]", "duplicate reagent requirements were not aggregated")
assert(TradeSkillFrame.numAvailable == 3, "selected combined maximum is wrong")
assert(TradeSkillReagent1Count.text == "9 /3" and TradeSkillReagent2Count.text == "11 /2",
    "selected reagent totals are wrong")
assert(TradeSkillCreateButton.enabled and TradeSkillCreateAllButton.enabled, "combined materials did not enable crafting")

TradeSkillFrame.selectedSkill = 3
hooks.TradeSkillFrame_SetSelection(3)
assert(TradeSkillFrame.numAvailable == 5 and TradeSkillCreateButton.enabled, "bank-only selection is unavailable")

TradeSkillCreateAllButton.scripts.OnClick()
local _, _, craftArguments = LastRequest("CRAFT")
assert(craftArguments == "1003|5", "Create All did not use the combined maximum")

recipes[3].reagents[1].carried = 1
Event("BAG_UPDATE")
CompleteLatestSync("102:5,103:10,104:5")
assert(TradeSkillSkill3Count.text == "", "insufficient combined materials still show craftable")
assert(TradeSkillFrame.numAvailable == 0, "selected count did not refresh after storage changed")
assert(not TradeSkillCreateButton.enabled and not TradeSkillCreateAllButton.enabled,
    "Create buttons remained enabled with insufficient combined materials")

Event("BANKFRAME_OPENED")
assert(NativeReagents.Withdraw(101, 1), "withdraw request was rejected by the client API")
local _, withdrawRequest = LastRequest("WITHDRAW")
Reply(withdrawRequest, "WITHDRAWN", "101|1")
CompleteLatestSync("101:9,102:5,103:10,104:5")
assert(TradeSkillSkill3Count.text == "[5]", "withdrawal sync did not refresh the recipe count")

assert(NativeReagents.DepositAll(), "deposit request was rejected by the client API")
local _, depositRequest = LastRequest("DEPOSIT")
Reply(depositRequest, "DEPOSITED", "1")
CompleteLatestSync("101:10,102:5,103:10,104:5")
assert(TradeSkillSkill3Count.text == "[5]", "deposit sync did not refresh the recipe count")

recipes[4].cooldown = 30
TradeSkillFrame.selectedSkill = 4
hooks.TradeSkillFrame_SetSelection(4)
assert(TradeSkillSkill4Count.text == "" and TradeSkillFrame.numAvailable == 0,
    "recipe cooldown restriction was not preserved")

print("PASS profession combined craftable counts and refresh behavior")
