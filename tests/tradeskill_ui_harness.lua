local sent, frames, hooks = {}, {}, {}
local Event
local unpackValues = table.unpack or unpack
local recipeRowHookDepth = 0

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
    function widget:SetID(value) self.id = value end
    function widget:GetID() return self.id end
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
function hooksecurefunc(target, name, callback)
    if type(target) == "table" then
        local original = target[name]
        target[name] = function(...)
            local results = { original(...) }
            recipeRowHookDepth = recipeRowHookDepth + 1
            callback(...)
            recipeRowHookDepth = recipeRowHookDepth - 1
            return unpackValues(results)
        end
        return
    end
    callback = name
    local original = _G[target]
    hooks[target] = callback
    _G[target] = function(...)
        local results = { original(...) }
        callback(...)
        return unpackValues(results)
    end
end
function SendAddonMessage(prefix, payload, channel, target)
    assert(recipeRowHookDepth == 0, "recipe-row calculation sent an addon message")
    table.insert(sent, { prefix=prefix, payload=payload, channel=channel, target=target })
end
function UnitName() return "Tester" end
function GetTime() return 100 end
function IsTradeSkillLinked() return false end
function FauxScrollFrame_GetOffset() return 0 end
function DoTradeSkill(index, count) _G.lastStockCraft = { index, count } end

TRADE_SKILLS_DISPLAYED, TRADE_SKILL_TEXT_WIDTH = 8, 275
TradeSkillListScrollFrame = Widget()
TradeSkillFrame = Widget(false)
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
    [6] = { name="Runed Copper Pants", kind="optimal", stock=0,
        reagents={{ id=105, required=8, carried=100 }, { id=106, required=2, carried=8 },
            { id=107, required=3, carried=2 }} },
}

function GetItemInfo(id)
    for _, recipe in pairs(recipes) do
        for _, reagent in ipairs(recipe.reagents) do
            if reagent.id == id then return "Reagent" .. id end
        end
    end
end
function GetItemIcon(id) return "Texture" .. id end

function GetTradeSkillInfo(index)
    local recipe = recipes[index]
    if not recipe then return nil end
    return recipe.name, recipe.kind, recipe.stock, true
end
function GetTradeSkillNumReagents(index) return recipes[index] and #recipes[index].reagents or 0 end
function GetTradeSkillReagentInfo(index, reagent)
    local row = recipes[index].reagents[reagent]
    return "Reagent" .. row.id, "Texture" .. row.id, row.required, row.carried
end
local emitTradeSkillUpdate = false
function GetTradeSkillReagentItemLink(index, reagent)
    if emitTradeSkillUpdate and index ~= TradeSkillFrame.selectedSkill then Event("TRADE_SKILL_UPDATE") end
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

local stockUpdateCalls = 0
function TradeSkillFrame_SetSelection(index)
    assert(recipeRowHookDepth == 0, "recipe-row calculation called TradeSkillFrame_SetSelection")
    local name, skillType = GetTradeSkillInfo(index)
    if not name or skillType == "header" then return end
    TradeSkillFrame.selectedSkill = index
    for reagent = 1, GetTradeSkillNumReagents(index) do GetTradeSkillReagentInfo(index, reagent) end
end
function TradeSkillFrame_Update()
    assert(recipeRowHookDepth == 0, "recipe-row calculation called TradeSkillFrame_Update")
    stockUpdateCalls = stockUpdateCalls + 1
    assert(stockUpdateCalls < 100, "Blizzard trade-skill update lifecycle did not terminate")
    local offset = FauxScrollFrame_GetOffset(TradeSkillListScrollFrame)
    for row = 1, TRADE_SKILLS_DISPLAYED do
        local index = offset + row
        local name, skillType, stockMaximum = GetTradeSkillInfo(index)
        local button = _G["TradeSkillSkill" .. row]
        local count = _G["TradeSkillSkill" .. row .. "Count"]
        if name then
            button:SetID(index)
            button:Show()
            if skillType == "header" then
                button:SetText(name)
                count:SetText("")
            elseif stockMaximum > 0 then
                count:SetText("[" .. stockMaximum .. "]")
                _G["TradeSkillSkill" .. row .. "Text"]:SetText(name)
            else
                button:SetText(name)
                count:SetText("")
            end
        else
            button:Hide()
        end
    end
    for index = 1, #recipes do
        local _, _, stockMaximum = GetTradeSkillInfo(index)
        if index == TradeSkillFrame.selectedSkill then TradeSkillFrame.numAvailable = math.abs(stockMaximum or 0) end
    end
end
function TradeSkillFrame_Show()
    TradeSkillFrame:Show()
    TradeSkillFrame_SetSelection(GetTradeSkillSelectionIndex())
    TradeSkillFrame_Update()
end

assert(loadfile("content/client/Interface/FrameXML/NativeReagents.lua"))()

local lifecycle
for _, frame in ipairs(frames) do
    if frame.events.CHAT_MSG_ADDON then lifecycle = frame end
end
assert(lifecycle, "Native Reagents event frame was not created")

Event = function(event, ...)
    assert(recipeRowHookDepth == 0, "recipe-row calculation dispatched a profession event")
    if event == "TRADE_SKILL_UPDATE" and TradeSkillFrame:IsShown() then
        TradeSkillFrame_SetSelection(GetTradeSkillSelectionIndex())
        TradeSkillFrame_Update()
    end
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
TradeSkillFrame_Show()
CompleteLatestSync("101:10,102:5,103:10,104:5,105:17,106:10,107:5")
assert(NativeReagents.GetQuantity(102) == 5, "sync did not populate stored reagents")
TradeSkillFrame_Update()

assert(TradeSkillSkill2Text.text == "Inventory Recipe [5]", "inventory-only list count is wrong")
assert(TradeSkillSkill3Text.text == "Bank Recipe [5]", "bank-only list count is wrong")
assert(TradeSkillSkill4Text.text == "Split Recipe [3]", "mixed inventory/bank limiting count is wrong")
assert(TradeSkillSkill5Text.text == "Duplicate Recipe [2]", "duplicate reagent requirements were not aggregated")
assert(TradeSkillSkill6Text.text == "Runed Copper Pants [2]",
    "117 Copper Bars, 18 Fine Thread, and 7 Rough Grinding Stones did not produce [2]")
assert(TradeSkillSkill6Count.text == "", "corrected quantity remained on Blizzard's separate count font string")
assert(TradeSkillFrame.numAvailable == 3, "selected combined maximum is wrong: " .. tostring(TradeSkillFrame.numAvailable))
assert(TradeSkillReagent1Count.text == "9 /3" and TradeSkillReagent2Count.text == "11 /2",
    "selected reagent totals are wrong")
assert(TradeSkillCreateButton.enabled and TradeSkillCreateAllButton.enabled, "combined materials did not enable crafting")

TradeSkillFrame.selectedSkill = 3
TradeSkillFrame_SetSelection(3)
assert(TradeSkillFrame.numAvailable == 5 and TradeSkillCreateButton.enabled, "bank-only selection is unavailable")

TradeSkillCreateAllButton.scripts.OnClick()
local _, _, craftArguments = LastRequest("CRAFT")
assert(craftArguments == "1003|5", "Create All did not use the combined maximum")

recipes[3].reagents[1].carried = 1
Event("BAG_UPDATE")
CompleteLatestSync("102:5,103:10,104:5,105:17,106:10,107:5")
TradeSkillFrame_Update()
assert(TradeSkillSkill3Text.text == "Bank Recipe", "insufficient combined materials still show craftable")
assert(TradeSkillFrame.numAvailable == 0, "selected count did not refresh after storage changed")
assert(not TradeSkillCreateButton.enabled and not TradeSkillCreateAllButton.enabled,
    "Create buttons remained enabled with insufficient combined materials")

Event("BANKFRAME_OPENED")
assert(NativeReagents.Withdraw(101, 1), "withdraw request was rejected by the client API")
local _, withdrawRequest = LastRequest("WITHDRAW")
Reply(withdrawRequest, "WITHDRAWN", "101|1")
CompleteLatestSync("101:9,102:5,103:10,104:5,105:17,106:10,107:5")
TradeSkillFrame_Update()
assert(TradeSkillSkill3Text.text == "Bank Recipe [5]", "withdrawal sync did not refresh the recipe count")

assert(NativeReagents.DepositAll(), "deposit request was rejected by the client API")
local _, depositRequest = LastRequest("DEPOSIT")
Reply(depositRequest, "DEPOSITED", "1")
CompleteLatestSync("101:10,102:5,103:10,104:5,105:17,106:10,107:5")
TradeSkillFrame_Update()
assert(TradeSkillSkill3Text.text == "Bank Recipe [5]", "deposit sync did not refresh the recipe count")

recipes[4].cooldown = 30
TradeSkillFrame.selectedSkill = 4
TradeSkillFrame_SetSelection(4)
TradeSkillFrame_Update()
assert(TradeSkillSkill4Text.text == "Split Recipe" and TradeSkillFrame.numAvailable == 0,
    "recipe cooldown restriction was not preserved")

local function RequestCount(command)
    local count = 0
    for _, message in ipairs(sent) do
        local found = string.match(message.payload, "^%d+|%d+|([^|]+)")
        if found == command then count = count + 1 end
    end
    return count
end

-- Opening a real profession runs Blizzard's SetSelection/Update lifecycle.
-- Keep the old failure stimulus enabled: if the visible-row path ever queries
-- a non-selected reagent link again, it synchronously emits TRADE_SKILL_UPDATE.
-- The row callback also rejects update/selection calls, events, and messages.
local syncRequests = RequestCount("SYNC")
local updates = stockUpdateCalls
emitTradeSkillUpdate = true
Event("TRADE_SKILL_UPDATE")
TradeSkillFrame_Update()
emitTradeSkillUpdate = false
assert(TradeSkillSkill6Text.text == "Runed Copper Pants [2]",
    "Blizzard's normal row rendering overwrote the corrected recipe-name count")
assert(RequestCount("SYNC") == syncRequests, "TRADE_SKILL_UPDATE started a reagent-bank synchronization loop")
assert(stockUpdateCalls - updates < 20, "nested Blizzard trade-skill updates were unbounded")
assert(recipeRowHookDepth == 0, "recipe-row hook did not unwind")

Event("BAG_UPDATE")
assert(RequestCount("SYNC") == syncRequests + 1, "BAG_UPDATE no longer synchronizes changed bank quantities")

print("PASS visible-row craftable counts, pure bounded calculation, and selected-recipe behavior")
