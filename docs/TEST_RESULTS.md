# Test results — 2026-11-12

## Passed

- `python3 tests/run_checks.py`
  - Protocol, safety/conservation model, synchronization, Lua syntax, mocked build-12340
    FrameXML lifecycle, repeated Bank/Reagents switching, stock refresh suppression, 42-slot
    paging, stock-bank restoration, schema compatibility, and deterministic EPF checks passed.
  - EPF SHA-256: `1643b21f1d14a8f72eeb069f97dff30750cd4b94fa7d59672ecd61f282f686b1`.
- Official Lua 5.1.5 `luac -p` and mocked FrameXML lifecycle execution
  - Both client Lua files parsed successfully, and the complete UI harness passed under the
    Lua 5.1.5 runtime.
- `python3 tests/prepared_statement_audit.py --acore-source
  /home/smithkt/aicode_folder/azerothcore-wotlk`
  - Mapped `CHAR_UPD_CHARACTER` to ID 225 in `e7e2e288e` and confirmed it is
    `CONNECTION_ASYNC`.
  - Confirmed all nine core inventory statements reachable from
    `SaveInventoryAndGoldToDB` are available on async connections.
- `python3 tests/mysql_integration.py --mysql <mysql-8.4-client> --socket <test-socket>
  --database acore_characters_test`
  - Ran against a disposable MySQL 8.4.11 instance containing the complete AzerothCore
    characters schema plus both module migrations (112 tables).
  - Passed successful/partial deposits and withdrawals, empty storage, durable duplicate
    rejection, invalid/absent operations, injected rollback, conservation, and persistence
    across independent client connections.
- Full AzerothCore worldserver build:
  - Source revision: `e7e2e288e7d9ec30e2dfe6f417178a95986fcbb2`.
  - Configuration: `RelWithDebInfo`, static scripts, static `mod-native-reagents`, PCH enabled.
  - `NativeReagentsManager.cpp` compiled, `modules/libmodules.a` linked, and the final
    `src/server/apps/worldserver` linked successfully.
  - Final binary is a 64-bit PIE with debug information and resolves MySQL 8.4, OpenSSL, and
    crypto libraries.

## Environment boundaries

- The disposable database test exercises real MySQL transactions and the authoritative module
  tables, but it does not instantiate a live `Player` through the worldserver. The executable
  safety tests cover the in-memory mutation/reversal policy.
- No patched 3.3.5a client was connected during this pass. Lua syntax/lifecycle and exact stock
  template geometry were verified, but visual rendering, mouse interaction, and absence of
  runtime FrameXML errors still require the PTR client matrix.
- Remote crafting remains disabled by default and is not approved for general PTR use.
