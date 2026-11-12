# Test results — 2026-11-12

## Executed successfully

- `python3 tests/run_checks.py`
  - C++ protocol tests compiled with `-std=c++17 -Wall -Wextra -Werror`.
  - Protocol parsing, overflow bounds, version rejection, and response-size framing passed.
  - Executable safety-policy tests covered successful and failed commits, conservation on
    rollback, insufficient storage, full inventory, invalid/zero quantities, overflow and
    configured limits, duplicate IDs, overlapping-operation rejection, exact/ambiguous
    crafting recovery, and banker-session policy.
  - Synchronization simulation covered single/multiple pages, missing pages, duplicate and
    out-of-order pages, stale/overlapping generations, atomic publication, two retries,
    timeout failure, and retention of the last good snapshot.
  - Schema-3 manifest, XML well-formedness, pinned stock TOC digest, load ordering,
    backward-compatible/non-destructive SQL, additive journal schema, transaction guards,
    ambiguous-COMMIT fail-stop guards, quest protection, limits, client API surface,
    deterministic EPF rebuild, and exact archive membership passed.
  - Both Lua files compiled through the available Lua library. The executable mocked-FrameXML
    harness created all 42 item buttons before refresh and passed empty/populated two-page
    rendering, navigation, mutually exclusive page visibility, stock slot/bag restoration,
    and Bank-default close/reopen behavior.
  - The same syntax and lifecycle harness passed when linked directly to Lua 5.1.5 from a
    temporary extracted development package, confirming the client files do not rely on newer
    Lua syntax. The reference audit also confirmed the used templates and panel/item APIs occur
    before `BankFrame.xml` in the pinned build-12340 FrameXML load order.
- The actual `mod-content-manager` `ContentPackage` parser/validator was compiled from the
  adjacent current source and accepted `content/mod-native-reagents.epf`, including its
  Schema-3 additive FrameXML declaration and pinned TOC.
- Both injected Lua files passed a Lua 5.1 grammar parse using `luaparse 0.3.1` from a
  temporary test-only installation; no dependency was added to the repository.
- All four C++ module translation units compiled in `-fsyntax-only` mode with
  `-std=gnu++20 -Wall -Wextra` against the available AzerothCore `e7e2e288e` headers.
- AzerothCore CMake discovered and configured `mod-native-reagents` as a static worldserver
  module and registered its configuration file.
- A real no-PCH AzerothCore build against checkout `e7e2e288e` completed at 100%, including
  `libmodules.a`, `libgame.a`, and the final `worldserver` executable. MySQL 8.4.11 headers
  and `libmysqlclient` from the host's existing dependency cache were used; this also verified
  the module against the actual MySQL-facing database API. The successful final command was
  `cmake --build . --target worldserver -j2`.
- The corrective C++ changes were also rebuilt on 2026-11-12 against an archive of
  `e7e2e288e7d9ec30e2dfe6f417178a95986fcbb2`. AzerothCore CMake discovered the module, and
  `cmake --build build --target modules -j2` compiled `NativeReagentsManager.cpp`,
  `NativeReagentsProtocol.cpp`, `NativeReagentsScripts.cpp`, and the loader, then linked
  `libmodules.a` successfully. A temporary extracted Ubuntu MySQL 8.4.13 development package
  supplied headers/library metadata because the host package was not installed.

## Environment limitation

The initial PCH attempt exhausted temporary storage, and the first no-PCH archive attempt was
blocked by two stale task-created `.gch` files. Removing those regenerable PCH artifacts allowed
`libgame.a` and `worldserver` to link successfully. The recorded build therefore used
`-DNOPCH=1`; builders with tight storage should do the same.

The system package database has no MySQL/MariaDB development package installed. The
build used a pre-existing MySQL 8.4.11 SDK cache because AzerothCore's current database layer
uses MySQL 8 APIs that the available MariaDB development package does not provide. For a clean
Debian/Ubuntu builder, install the MySQL-compatible development package expected by that
AzerothCore revision rather than assuming `libmariadb-dev` is API-compatible.

No running characters database, worldserver, Content Manager realm, Portalkeeper deployment,
or WoW 3.3.5a client was available. Database commit-failure injection and all scenarios in
`LIVE_TEST_PLAN.md` remain unexecuted. Remote crafting is disabled by default and is not
approved for general PTR use.
