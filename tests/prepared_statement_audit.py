#!/usr/bin/env python3
"""Audit the exact AzerothCore inventory statements used by this module."""

from __future__ import annotations

import argparse
import pathlib
import re


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--acore-source", required=True, type=pathlib.Path)
    args = parser.parse_args()
    header = args.acore_source / "src/server/database/Database/Implementation/CharacterDatabase.h"
    implementation = args.acore_source / "src/server/database/Database/Implementation/CharacterDatabase.cpp"
    player = args.acore_source / "src/server/game/Entities/Player/PlayerStorage.cpp"
    item = args.acore_source / "src/server/game/Entities/Item/Item.cpp"
    module = pathlib.Path(__file__).resolve().parents[1] / "src/NativeReagentsManager.cpp"
    for path in (header, implementation, player, item, module):
        if not path.is_file():
            raise SystemExit(f"missing source file: {path}")

    names = re.findall(r"^\s*(CHAR_[A-Z0-9_]+)\s*,?\s*$", header.read_text(), re.MULTILINE)
    ids = {name: index for index, name in enumerate(names)}
    registrations = {
        match.group(1): (match.group(0), match.group(2))
        for match in re.finditer(
            r"PrepareStatement\((CHAR_[A-Z0-9_]+),[\s\S]*?,\s*(CONNECTION_[A-Z]+)\);",
            implementation.read_text())
    }
    required = {
        "CHAR_REP_INVENTORY_ITEM", "CHAR_REP_ITEM_INSTANCE", "CHAR_UPD_ITEM_INSTANCE",
        "CHAR_DEL_ITEM_INSTANCE", "CHAR_DEL_CHAR_INVENTORY_BY_ITEM",
        "CHAR_DEL_CHAR_INVENTORY_BY_BAG_SLOT", "CHAR_UDP_CHAR_MONEY",
        "CHAR_UPD_GIFT_OWNER", "CHAR_DEL_GIFT",
    }
    missing = sorted(required - registrations.keys())
    if missing:
        raise AssertionError(f"unregistered inventory statements: {missing}")
    wrong_mode = sorted(name for name in required if registrations[name][1] not in {"CONNECTION_ASYNC", "CONNECTION_BOTH"})
    if wrong_mode:
        raise AssertionError(f"inventory statements unavailable to async transactions: {wrong_mode}")

    module_text = module.read_text()
    assert "AsyncCommitTransaction(transaction)" in module_text
    assert "callback.m_future.get()" in module_text
    assert "SaveToDB(transaction, false, false)" not in module_text
    # The one remaining direct transaction contains only raw auto-deposit SQL;
    # no Player persistence/prepared statement is appended to it.
    assert module_text.count("DirectCommitTransaction(transaction)") == 1
    assert "SaveInventoryAndGoldToDB(transaction)" in module_text

    update_id = ids["CHAR_UPD_CHARACTER"]
    update_registration, update_mode = registrations["CHAR_UPD_CHARACTER"]
    assert update_mode == "CONNECTION_ASYNC"
    assert "UPDATE characters SET" in update_registration
    assert "_SaveCharacter(create, trans);" in player.read_text()
    assert "CHAR_REP_ITEM_INSTANCE" in item.read_text()

    print(f"PASS statement audit: CHAR_UPD_CHARACTER={update_id} mode={update_mode}")
    for name in sorted(required, key=ids.get):
        print(f"  {ids[name]:3d} {name} {registrations[name][1]}")


if __name__ == "__main__":
    main()
