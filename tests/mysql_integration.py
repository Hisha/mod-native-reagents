#!/usr/bin/env python3
"""Real-MySQL transaction tests for reagent balances and durable journals."""

from __future__ import annotations

import argparse
import os
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mysql", default="mysql")
    parser.add_argument("--socket", required=True)
    parser.add_argument("--database", required=True)
    args = parser.parse_args()
    if not args.database.endswith("_test"):
        raise SystemExit("refusing to mutate a database whose name does not end in _test")
    base = [args.mysql, "--no-defaults", f"--socket={args.socket}", "-uroot", "-N", "-B", args.database]

    def sql(statement: str, *, succeeds: bool = True) -> str:
        result = subprocess.run(base + ["-e", statement], text=True, capture_output=True, env=os.environ.copy())
        if succeeds and result.returncode:
            raise AssertionError(result.stderr.strip())
        if not succeeds and result.returncode == 0:
            raise AssertionError("statement unexpectedly succeeded")
        return result.stdout.strip()

    guid, entry = 4294967294, 70000
    sql("DROP TABLE IF EXISTS native_reagents_test_inventory; "
        "CREATE TABLE native_reagents_test_inventory(guid INT UNSIGNED, item_entry INT UNSIGNED, "
        "quantity BIGINT UNSIGNED NOT NULL, PRIMARY KEY(guid,item_entry)) ENGINE=InnoDB; "
        f"DELETE FROM character_native_reagent_operations WHERE guid={guid}; "
        f"DELETE FROM character_bank_reagents WHERE guid={guid}; "
        f"INSERT INTO native_reagents_test_inventory VALUES({guid},{entry},20)")

    def totals(expected_inventory: int, expected_storage: int) -> None:
        output = sql("SELECT COALESCE((SELECT quantity FROM native_reagents_test_inventory "
                     f"WHERE guid={guid} AND item_entry={entry}),0),"
                     "COALESCE((SELECT quantity FROM character_bank_reagents "
                     f"WHERE guid={guid} AND item_entry={entry}),0)")
        inventory, storage = map(int, output.split("\t"))
        assert (inventory, storage) == (expected_inventory, expected_storage)
        assert inventory + storage == 20

    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=quantity-5 WHERE guid={guid} AND item_entry={entry}; "
        f"INSERT INTO character_bank_reagents VALUES({guid},{entry},5) ON DUPLICATE KEY UPDATE quantity=VALUES(quantity); "
        f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state,result_amount) VALUES({guid},1,'DEPOSIT','COMPLETED',5); COMMIT")
    totals(15, 5)
    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=quantity-3 WHERE guid={guid} AND item_entry={entry}; "
        f"UPDATE character_bank_reagents SET quantity=8 WHERE guid={guid} AND item_entry={entry}; "
        f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state,result_amount) VALUES({guid},2,'DEPOSIT','COMPLETED',3); COMMIT")
    totals(12, 8)
    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=quantity+4 WHERE guid={guid} AND item_entry={entry}; "
        f"UPDATE character_bank_reagents SET quantity=4 WHERE guid={guid} AND item_entry={entry}; "
        f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state,item_entry,amount,result_amount) VALUES({guid},3,'WITHDRAW','COMPLETED',{entry},4,4); COMMIT")
    totals(16, 4)
    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=quantity+2 WHERE guid={guid} AND item_entry={entry}; "
        f"UPDATE character_bank_reagents SET quantity=2 WHERE guid={guid} AND item_entry={entry}; "
        f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state,item_entry,amount,result_amount) VALUES({guid},4,'WITHDRAW','COMPLETED',{entry},2,2); COMMIT")
    totals(18, 2)

    sql(f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state) VALUES({guid},4,'WITHDRAW','COMPLETED')", succeeds=False)
    totals(18, 2)
    assert sql(f"SELECT COUNT(*) FROM character_bank_reagents WHERE guid={guid} AND item_entry={entry + 1}") == "0"
    assert sql(f"SELECT COUNT(*) FROM character_native_reagent_operations WHERE guid={guid} AND operation_id IN (5,6)") == "0"

    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=0 WHERE guid={guid} AND item_entry={entry}; "
        f"UPDATE character_bank_reagents SET quantity=20 WHERE guid={guid} AND item_entry={entry}; "
        f"INSERT INTO character_native_reagent_operations(guid,operation_id,kind,state) VALUES({guid},7,'DEPOSIT','COMPLETED'); ROLLBACK")
    totals(18, 2)
    assert sql(f"SELECT COUNT(*) FROM character_native_reagent_operations WHERE guid={guid} AND operation_id=7") == "0"
    assert sql(f"SELECT CONCAT(quantity,':',(SELECT COUNT(*) FROM character_native_reagent_operations WHERE guid={guid} AND state='COMPLETED')) FROM character_bank_reagents WHERE guid={guid} AND item_entry={entry}") == "2:4"

    sql("START TRANSACTION; "
        f"UPDATE native_reagents_test_inventory SET quantity=20 WHERE guid={guid} AND item_entry={entry}; "
        f"DELETE FROM character_bank_reagents WHERE guid={guid} AND item_entry={entry}; COMMIT")
    totals(20, 0)
    sql(f"DELETE FROM character_native_reagent_operations WHERE guid={guid}; "
        f"DELETE FROM character_bank_reagents WHERE guid={guid}; DROP TABLE native_reagents_test_inventory")
    print("PASS real MySQL deposit/withdraw/empty/partial/duplicate/invalid/rollback/persistence")


if __name__ == "__main__":
    main()
