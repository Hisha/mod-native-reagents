#!/usr/bin/env python3
from __future__ import annotations
import hashlib, json, pathlib, subprocess, sys, tempfile, zipfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]

def require(condition: bool, message: str) -> None:
    if not condition: raise AssertionError(message)

def main() -> None:
    manifest = json.loads((ROOT / "content/manifest.json").read_text())
    require(manifest["schema"] == 3, "EPF must use schema 3")
    require(manifest["package"] == "mod-native-reagents", "wrong package id")
    frame = manifest["clientFrameXml"]
    toc = ROOT / "content" / frame["stockTocSource"]
    require(hashlib.sha256(toc.read_bytes()).hexdigest() == frame["stockTocSha256"], "stock TOC digest mismatch")
    targets = {row["target"] for row in manifest["content"]}
    require(frame["loadEntries"][0]["target"] in targets, "load target is not content")
    require(frame["loadEntries"][0]["after"] == "Interface/FrameXML/BankFrame.xml", "bank load order changed")
    for row in manifest["content"]: require((ROOT / "content" / row["source"]).is_file(), "missing " + row["source"])
    ET.parse(ROOT / "content/client/Interface/FrameXML/NativeReagentsFrame.xml")

    sql = (ROOT / "data/sql/db-characters/base/001_mod_native_reagents.sql").read_text()
    journal_sql = (ROOT / "data/sql/db-characters/base/002_mod_native_reagent_operations.sql").read_text()
    require("BIGINT UNSIGNED" in sql and "character_bank_reagents" in sql, "compatible quantity schema missing")
    require("DROP TABLE" not in sql.upper() and "ALTER TABLE" not in sql.upper(), "base SQL must be non-destructive")
    require("character_native_reagent_operations" in journal_sql and "FOREIGN KEY" in journal_sql, "safety journal schema missing")
    manager = (ROOT / "src/NativeReagentsManager.cpp").read_text()
    require(manager.count("SaveInventoryAndGoldToDB(transaction)") == 5,
            "all inventory writes must join their reagent transaction")
    require("AsyncCommitTransaction(transaction)" in manager and "callback.m_future.get()" in manager,
            "inventory transactions must execute on an async connection and wait for the real result")
    require("SaveToDB(transaction, false, false)" not in manager,
            "full character saves append unrelated async-only statements")
    require("GetOperationStatus" in manager and "OperationGuard" in manager, "verified serialized operations missing")
    require("SELECT 1 AS sentinel" in manager and "OperationStatus::Unavailable" in manager,
            "commit verification must distinguish an absent marker from an unavailable database")
    require("FailStopAmbiguousCommit" in manager,
            "ambiguous COMMIT outcomes must not permit a later character save")
    require("HasQuestForItem" in manager, "quest reagent protection missing")
    require("MaxQuantityPerItem" in manager and "MaxTypes" in manager, "storage limits missing")
    lua = (ROOT / "content/client/Interface/FrameXML/NativeReagents.lua").read_text()
    for api in ("IsAvailable", "IsReady", "GetStatus", "IsBankOpen", "GetItems", "GetQuantity", "DepositAll", "Withdraw", "GetAutoDeposit", "SetAutoDeposit", "RegisterCallback", "RegisterPresentation"):
        require(("function NR." + api) in lua, "missing Lua API " + api)
    require("RefreshTradeSkill" not in lua and "refreshingTradeSkill" not in lua,
            "recipe-list-wide refresh implementation remains installed")
    require('hooksecurefunc(count, "SetText"' in lua,
            "visible recipe quantities must be attached to Blizzard's row rendering")
    require(lua.count("VisibleRecipeMaximum(") == 2 and
            lua.count("RenderVisibleRecipeCount(") == 2,
            "recipe-list calculation must be reachable only from the visible-row hook")
    require("math.min(GetTradeSkillNumReagents(index) or 0, MAX_TRADE_SKILL_REAGENTS or 8)" in lua,
            "visible recipe calculation is not explicitly bounded")
    calculator = lua.split("local function VisibleRecipeMaximum(index)", 1)[1].split(
        "local rowCountRendering", 1)[0]
    for forbidden in ("TradeSkillFrame_Update", "TradeSkillFrame_SetSelection", "RequestSync",
                      "GetTradeSkillReagentItemLink", "SendAddonMessage", "Send(", "Fire(",
                      "SetText", "SetWidth"):
        require(forbidden not in calculator,
                "visible recipe calculation contains forbidden call " + forbidden)
    require(lua.count("InvalidateCombinedReagentCounts()") == 3,
            "combined reagent cache must be invalidated only by inventory or changed bank contents")
    bank_lua = (ROOT / "content/client/Interface/FrameXML/NativeReagentsBank.lua").read_text()
    require("local columns, rows, perPage = 7, 5, 35" in bank_lua, "reagent page must use the five-row layout")
    require("Bank-Background" not in bank_lua.replace("post-Wrath Bank-Background", ""),
            "client references the post-Wrath Bank-Background texture")
    require('hooksecurefunc("UpdateBagSlotStatus", EnforceStockHidden)' in bank_lua,
            "purchase-info refresh guard is missing")
    require(bank_lua.count("hooksecurefunc(") == 1, "bank page installed unexpected visibility hooks")
    require("function NR.DumpBankFrame()" in bank_lua and "function NR.SetBankFrameDiagnostics" in bank_lua,
            "opt-in BankFrame diagnostics are missing")

    with tempfile.TemporaryDirectory(prefix="native-reagents-tests-") as directory:
        binary = pathlib.Path(directory) / "protocol_tests"
        subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/protocol_tests.cpp"), str(ROOT / "src/NativeReagentsProtocol.cpp"), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        safety = pathlib.Path(directory) / "safety_model_tests"
        subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror", str(ROOT / "tests/safety_model_tests.cpp"), "-o", str(safety)], check=True)
        subprocess.run([str(safety)], check=True)
        lua_flags = subprocess.run(
            ["pkg-config", "--cflags", "--libs", "lua"], check=True, text=True, capture_output=True
        ).stdout.split()
        lua_runner = pathlib.Path(directory) / "lua_runner"
        subprocess.run(["c++", "-std=c++17", "-Wall", "-Wextra", "-Werror",
                        str(ROOT / "tests/lua_runner.cpp"), *lua_flags, "-o", str(lua_runner)], check=True)
        subprocess.run([str(lua_runner), "--syntax",
                        str(ROOT / "content/client/Interface/FrameXML/NativeReagents.lua"),
                        str(ROOT / "content/client/Interface/FrameXML/NativeReagentsBank.lua")], check=True)
        subprocess.run([str(lua_runner), str(ROOT / "tests/wow_ui_harness.lua")], cwd=ROOT, check=True)
        subprocess.run([str(lua_runner), str(ROOT / "tests/tradeskill_ui_harness.lua")], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT / "tests/test_sync_protocol.py")], check=True)
    subprocess.run([sys.executable, str(ROOT / "content/build_epf.py")], cwd=ROOT, check=True)
    subprocess.run([sys.executable, str(ROOT / "content/build_epf.py"), "--check"], cwd=ROOT, check=True)
    with zipfile.ZipFile(ROOT / "content/mod-native-reagents.epf") as archive:
        require(set(archive.namelist()) == {"manifest.json", "upstream/FrameXML.toc", *(row["source"] for row in manifest["content"])}, "EPF members differ from manifest")
    print("PASS schema compatibility, transaction guards, API contract, deterministic EPF")

if __name__ == "__main__": main()
