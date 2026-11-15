# Native Reagents

Native Reagents is an [AzerothCore](https://www.azerothcore.org/) module for the
World of Warcraft: Wrath of the Lich King 3.3.5a client. It provides a native
reagent-bank experience inside the stock personal-bank and profession windows:
reagents are stored and persisted authoritatively by the server, while an injected
FrameXML interface displays the bank and augments the existing trade-skill UI.

The client interface is delivered as a protected FrameXML patch through
[`mod-content-manager`](https://github.com/Hisha/mod-content-manager). It is not a
standalone WoW addon and does not require one.

## Features

### Reagent storage

- Character-specific reagent storage in the characters database.
- Manual **Deposit Reagents** and persistent per-character **Auto Deposit** controls.
- Public `NativeReagents.Deposit(itemId, quantity)` support for exact full-stack, partial-stack,
  and multi-stack deposits by conventional 3.3.5a addons.
- Context-aware stock-bag right-click deposits while the Reagents bank view is active, with
  authoritative non-reagent fallback to ordinary banking.
- A dedicated paged reagent view with 35 entries per page, item icons, quantities,
  quality borders, tooltips, and stack-aware withdrawal.
- Deposit eligibility is derived from trade-skill spell reagents, including custom recipes;
  unsuitable item classes and materials needed by active quests remain in inventory.
- Server-side persistence with atomic inventory/storage transactions, operation journaling,
  duplicate-request protection, optional storage limits, and overflow checks.

### Native client interface

- A stock-styled **Bank | Reagents** interface distributed as an EPF client patch.
- Right-click withdrawal of one normal stack and Shift-click quantity entry.
- Versioned, paged synchronization between the client interface and authoritative server
  state, including timeout and retry handling.
- A server-side fallback banker menu for an unpatched client, providing bank access,
  deposit, and Auto Deposit controls. The complete reagent view and profession integration
  require the client patch.

The stock bank remains the default view and retains its slots, bags, purchase controls,
money display, and standard behavior.

### Profession integration

- Material availability combines carried inventory with synchronized reagent-bank balances.
- Craftable quantities appear beside recipes in the standard profession list.
- The stock **Have Materials** checkbox filters against combined inventory and bank
  quantities while continuing to compose with search, subclass, and inventory-slot filters.
- Selected recipes show combined reagent totals and use the combined limiting-reagent
  quantity for Create All.
- Reagents supplied partly or entirely by the bank retain the stock dimmed treatment,
  visually distinguishing them from sufficient inventory-held reagents.
- Counts and filtering refresh after inventory changes, bank synchronization, deposits,
  withdrawals, and normal crafting updates.

### Crafting

- Crafting from stored-only or mixed inventory/bank materials, enabled by default.
- Carried materials are consumed first; only the missing quantity is temporarily
  materialized from storage for the normal AzerothCore spell cast.
- The server revalidates the learned trade-skill spell and material availability, then
  performs ordinary non-triggered casts so normal profession progression and cast
  requirements remain in force.
- Create and Create All are supported, with queued creation capped at 1,000 casts.

> [!IMPORTANT]
> Storage-backed crafting is enabled by default (`NativeReagents.RemoteCraft.Enable = 1`).
> A module hook cannot make spell effects and a failed completion-database commit one
> atomic operation. Review the recovery behavior and residual risks in
> [`docs/REMOTE_CRAFTING_SAFETY.md`](docs/REMOTE_CRAFTING_SAFETY.md) before deployment;
> set `NativeReagents.RemoteCraft.Enable = 0` if those risks are unacceptable.
> Ordinary inventory-only crafting continues through Blizzard's standard `DoTradeSkill` path.

Native Reagents does not patch AzerothCore itself and does not alter guild banks.

## Requirements

| Requirement | Status | Notes |
| --- | --- | --- |
| AzerothCore WotLK | Required | Verified by a full worldserver build against revision `e7e2e288e7d9ec30e2dfe6f417178a95986fcbb2`. A compatible revision exposing the same module hooks is required. |
| WoW 3.3.5a build 12340 | Required for the native UI | The package pins this client's stock `FrameXML.toc` and BankFrame behavior. |
| `mod-content-manager` | Required for the supported native client patch | Schema 3 `clientFrameXml` support composes the module files into protected FrameXML. |
| Protected-FrameXML-capable client deployment | Required for the native UI | The activated patch must be installed before the client starts. |
| Portalkeeper | Optional | It can distribute and activate the generated patch for deployments already using it; it is not a server-module dependency. |

Do not run `mod-bank-reagents` and Native Reagents at the same time. They use the same
compatibility tables and overlapping banker/crafting hooks. `BankReagentsUI` and
`UnifiedBags335` are not dependencies.

## Installation

### 1. Install the server module

Clone the repository into the AzerothCore source tree using the exact module directory name:

```bash
cd /path/to/azerothcore-wotlk/modules
git clone https://github.com/Hisha/mod-native-reagents.git
cd ..
cmake -S . -B build -DMODULES=static -DSCRIPTS=static
cmake --build build --target modules worldserver -j2
```

Reconfigure and rebuild whenever the module's C++ source changes. Use the realm's established
CMake options if they differ; the commands above are the configuration verified by this
repository's live test plan.

### 2. Set up the characters database

Fresh installations use the normal AzerothCore module SQL workflow for both base scripts:

```text
data/sql/db-characters/base/001_mod_native_reagents.sql
data/sql/db-characters/base/002_mod_native_reagent_operations.sql
```

The first script creates the character reagent balances and Auto Deposit preference. The
second adds the operation journal used for transaction verification, duplicate-request
handling, and crafting recovery.

Existing installations that already have the reagent balance and settings tables can apply
the additive update while the worldserver is stopped:

```text
data/sql/db-characters/updates/2026_11_11_00_native_reagent_operations.sql
```

The base and update definitions are idempotent and do not contain destructive migrations.
Back up the characters database before changing a production schema. Existing
`mod-bank-reagents` balances remain in the compatible tables, but the old module must be
disabled before Native Reagents starts.

### 3. Configure the module

The source template is `conf/mod_native_reagents.conf.dist`; CMake registers it with
AzerothCore's module configuration installation. Merge or copy the generated distribution
template into the realm's active module configuration using the same process as the other
AzerothCore modules, then review the settings below.

Remote crafting is enabled by default. Review the storage-backed crafting safety notes
before deployment and disable it explicitly if your deployment does not accept those risks.

### 4. Generate or verify the client EPF

A prebuilt `content/mod-native-reagents.epf` is included. To regenerate it from the tracked
manifest and client files, or verify that it is current:

```bash
python3 content/build_epf.py
python3 content/build_epf.py --check
```

The deterministic package contains the Schema 3 manifest, pinned build-12340 stock TOC, and
three Native Reagents FrameXML files. It inserts
`Interface/FrameXML/NativeReagentsFrame.xml` immediately after
`Interface/FrameXML/BankFrame.xml`.

### 5. Deploy and activate the client patch

1. Import `content/mod-native-reagents.epf` into
   [`mod-content-manager`](https://github.com/Hisha/mod-content-manager).
2. Build it cumulatively with the realm's other content packages and activate the resulting
   content generation.
3. Confirm that the generated MPQ contains all three Native Reagents FrameXML files and the
   composed `Interface/FrameXML/FrameXML.toc` entry.
4. Distribute the activated patch through the realm's client-patch workflow. Portalkeeper
   deployments must publish it with `Requirements=protected-framexml`.
5. Fully exit and restart the client after the patch is installed. Do not copy these files
   into `Interface/AddOns`; addon loading is not the supported integration path.

### 6. Start the updated realm

After the core rebuild, database setup, configuration, and client content activation are
complete, restart `worldserver` using the realm's normal service procedure. Players must
restart the client so protected FrameXML is loaded from the activated patch.

## Configuration

All supported settings are defined in `conf/mod_native_reagents.conf.dist`.

| Setting | Default | Description |
| --- | ---: | --- |
| `NativeReagents.Enable` | `1` | Enables the module and server service. |
| `NativeReagents.Debug` | `0` | Logs reagent-operation authorization outcomes and rejection reasons. |
| `NativeReagents.AutoDeposit.Enable` | `1` | Allows characters to enable persistent automatic deposit when opening a banker. |
| `NativeReagents.Storage.MaxTypes` | `0` | Maximum distinct stored item entries per character; `0` is unlimited. |
| `NativeReagents.Storage.MaxQuantityPerItem` | `0` | Maximum stored quantity for one item entry; `0` is unlimited. |
| `NativeReagents.RemoteCraft.Enable` | `1` | Enables crafting with banked materials by default; set to `0` to disable it. Review the documented recovery limitations. |
| `NativeReagents.RemoteCraft.TransactionTimeoutSeconds` | `30` | Seconds before a temporary crafting loan is rolled back; the effective minimum is 5 seconds. |
| `NativeReagents.BankerSession.TimeoutSeconds` | `300` | Maximum idle age of a validated banker session; the effective minimum is 5 seconds. |
| `NativeReagents.UI.Enable` | `1` | Enables the injected native-bank presentation path. |

Storage-limit checks apply atomically to the entire deposit. Disabling global Auto Deposit
also prevents characters from changing their per-character preference. Reagent mutations
require a currently open, in-range, server-validated banker session regardless of client
state.

## Using Native Reagents

1. Interact with a normal personal-bank banker. The stock **Bank** page opens by default.
2. Select the **Reagents** tab below the BankFrame.
3. Click **Deposit Reagents**, or enable **Auto Deposit** to deposit eligible items whenever
   an authorized bank session opens.
4. Browse stored materials. Right-click an item to withdraw one normal stack, or Shift-click
   it to enter a quantity.
5. Open a standard profession window. Recipe quantities and selected-recipe requirements now
   use carried plus stored material counts.
6. Enable **Have Materials** to show recipes craftable from the combined balances.
7. Craft normally with Create or Create All. With remote crafting enabled by default,
   missing reagents can be drawn from storage after inventory-held materials are used.

Deposits, withdrawals, and Auto Deposit changes are available only while the validated
personal-bank session remains active. Closing the bank, moving out of range, logging out, or
letting the session expire removes that authority.

## How It Works

The characters database is the source of truth for stored balances and per-character
preferences. Deposits are derived from the player's real inventory, and withdrawals are
validated against stored rows and available bag capacity. Inventory changes, absolute storage
balances, and an operation marker are persisted in the same transaction and verified before
the server reports success.

The protected FrameXML client sends versioned requests over the module's `NRB` addon-message
protocol. The server publishes bounded, paged snapshots; the client assembles a complete
generation before replacing its displayed balance. Client requests never establish banker
authority and are not trusted as proof of items or quantities.

The public FrameXML API also exposes `NativeReagents.Deposit(itemId, quantity)`. It returns
`sent, requestId`; final success arrives through the `DEPOSITED` callback and failures through
`ERROR`. The server selects and removes exactly the requested eligible inventory quantity and
then publishes the normal authoritative snapshot. Callers must not clear a cursor item or alter
their local balance merely because the request was sent. Build 12340 does not expose a reliable
split count through `GetCursorInfo()`, so an addon must retain the count supplied to its own split
callback (or use an explicit quantity dialog). Complete-stack callers can capture the source-slot
count with `GetContainerItemInfo` before the drag. See
[`docs/NATIVE_CLIENT_API.md`](docs/NATIVE_CLIENT_API.md) for the full cursor contract.

Profession integration reads the stock trade-skill reagent item IDs and combines the carried
counts reported by the client API with the latest synchronized storage snapshot. Those totals
drive recipe-list quantities, selected-recipe counts, and the custom Have Materials mapping.
They are presentation calculations only. When storage-backed crafting is enabled, the server
again validates the learned trade-skill spell and every reagent, consumes carried items first,
temporarily materializes only the shortage, and lets AzerothCore perform its normal cast.

## Known Limitations

- The native interface targets WoW 3.3.5a build 12340 and requires a protected FrameXML
  client patch. It is not supported as an ordinary addon.
- Storage-backed crafting is enabled by default, but module hooks cannot provide a
  transaction spanning core reagent consumption, arbitrary spell effects, and the
  completion database commit. Review the recovery limitations before deployment; see
  [`docs/REMOTE_CRAFTING_SAFETY.md`](docs/REMOTE_CRAFTING_SAFETY.md).
- Remote crafting does not bypass ordinary recipe ownership, crafting-station,
  profession-tool, inventory-capacity, or other spell-cast requirements.
- When **Have Materials** is active, recipes inside collapsed categories cannot be inspected by
  the 3.3.5a client API. The category header is retained and remains collapsed until the
  player expands it.
- The selected-recipe count uses `*` for combined totals of 100 or more to fit the stock
  reagent-count field.
- Automated tests exercise Lua syntax and a mocked FrameXML lifecycle, but they do not render
  Blizzard textures. Validate the supported UI scales and cumulative patch in the target
  client environment; the live checklist is in
  [`docs/LIVE_TEST_PLAN.md`](docs/LIVE_TEST_PLAN.md).
- Cursor visuals, split-stack cursor persistence, and bag-event ordering still require live
  build-12340 verification; mocked tests prove only request/callback behavior.

## Development and Testing

Run the repository's automated checks from its root:

```bash
python3 tests/run_checks.py
```

The suite compiles the protocol and safety-policy tests, runs synchronization simulations,
executes mocked bank and profession UI harnesses, and validates SQL compatibility,
transaction guards, quest protection, storage limits, the Lua API, Schema 3 load ordering,
the pinned TOC, and deterministic EPF contents. It requires a C++17 compiler, Python 3,
`pkg-config`, and Lua development files discoverable as `lua` by `pkg-config`.

To rebuild or verify only the EPF:

```bash
python3 content/build_epf.py
python3 content/build_epf.py --check
```

Additional opt-in database and AzerothCore source audits are documented in
[`tests/README.md`](tests/README.md). Live client/server validation scenarios are in
[`docs/LIVE_TEST_PLAN.md`](docs/LIVE_TEST_PLAN.md).

## Credits and License

Native Reagents is copyright © 2026 Kevin Smith and is released under the
[MIT License](LICENSE). Copies or substantial portions must retain the copyright and
permission notice as required by that license.

The project integrates with [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk)
and [`mod-content-manager`](https://github.com/Hisha/mod-content-manager). Its client code is
loaded into Blizzard's stock BankFrame and TradeSkillFrame; the repository does not ship the
complete Blizzard interface or bank textures. The pinned build-12340
`content/upstream/FrameXML.toc` is sourced from the archived
[3.3.5 interface files](https://github.com/wowgaming/3.3.5-interface-files/tree/d0339b17b0221db76e6acd2dc2915d224a5b62ca),
whose hierarchy and source provenance are recorded in
[`docs/BANKFRAME_HIERARCHY.md`](docs/BANKFRAME_HIERARCHY.md).

Native Reagents is an independent alternative to `mod-bank-reagents` plus
`BankReagentsUI`; those projects are not dependencies. World of Warcraft and its interface
assets are property of their respective rights holders. This project is not affiliated with
or officially supported by Blizzard Entertainment or AzerothCore.
