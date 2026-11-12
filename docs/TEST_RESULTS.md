# Test results — 2026-11-11

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
