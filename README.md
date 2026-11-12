# mod-native-reagents

Native reagent banking for AzerothCore 3.3.5a. It adds a **Bank | Reagents**
experience to Blizzard's stock bank, automatic and manual deposits, stack-aware withdrawals,
and crafting from stored materials. The interface is injected through
`mod-content-manager`; no separately installed WoW addon is required.

This is an independent alternative to `mod-bank-reagents` plus `BankReagentsUI`. The
original projects remain usable on their own and are not dependencies of this module.

## Features

- Character-specific reagent storage using the established
  `character_bank_reagents` and `character_bank_reagent_settings` tables.
- Bank remains the default and is Blizzard's unmodified BankFrame content. A full-page,
  stock-styled Reagents view supplies a 7-by-6 icon grid,
  quantities, item tooltips, quality borders, paging, right-click stack withdrawal,
  and shift-click quantity entry.
- Manual **Deposit Reagents** and persistent **Auto Deposit** controls.
- Eligibility derived from consumed trade-skill spell reagents, including custom recipes;
  inappropriate item classes and items needed for active quests are excluded.
- Unlimited types and quantities by default, with optional administrator limits and
  `uint64` overflow checks.
- Stored-only and mixed carried/stored profession crafting through ordinary AzerothCore
  non-triggered spell casts.
- Versioned, generation-aware paged `NRB` protocol with timeouts, retries, atomic snapshot
  publication, and bounded payloads.
- Presentation-independent Lua API for future UnifiedNativeBags integration.
- No core patch and no guild-bank changes.

## Requirements

- AzerothCore WotLK compatible with the script hooks used by commit `e7e2e288e` or newer.
- WoW 3.3.5a build 12340.
- `mod-content-manager` with Schema-3 additive `clientFrameXml` support.
- A client executable/deployment supporting `protected-framexml`; Portalkeeper realms must
  publish `Requirements=protected-framexml` as required by Content Manager.

`mod-bank-reagents` and `mod-native-reagents` **must not run simultaneously**. Both own the
same tables and banker/crafting hooks. BankReagentsUI and UnifiedBags335 are not required.

## Bank interface

The approved visual targets are [`design/Bank Tab mockup.png`](design/Bank%20Tab%20mockup.png)
and [`design/Reagent Tab mockup.png`](design/Reagent%20Tab%20mockup.png). They are design
references only and are not shipped as interface textures.

Opening a banker always selects **Bank**. That page is the original Blizzard BankFrame: its
28 bank slots, seven bank-bag slots, purchased bags, purchase controls, money display,
portrait, title, close button, artwork, size, and behavior remain owned by stock FrameXML.
Blizzard-style **Bank** and **Reagents** tabs are anchored to BankFrame below its visible bottom
border, so they follow the frame at every UI scale.

**Reagents** is a separate BankFrame child page, not an overlay of usable bank slots. While it
is selected, the module records and hides only the stock inventory, bank-bag, purchase, and
money controls, covers the content area with stock artwork, and displays 42 reagent slots,
quality borders, quantities, tooltips, an empty state, mouse-wheel/button pagination,
**Auto Deposit**, and **Deposit Reagents**. Returning to Bank restores each stock control to
its prior visibility state. Closing and reopening the bank always resets the page to Bank.

## Installation

1. Place this repository at `modules/mod-native-reagents` in the AzerothCore source tree.
2. Apply both character base scripts through the normal module SQL workflow. `001` preserves
   the original reagent tables and `002` adds the safety journal. Existing installations may
   apply `data/sql/db-characters/updates/2026_11_11_00_native_reagent_operations.sql`.
3. Copy/merge `conf/mod_native_reagents.conf.dist`, configure AzerothCore, and build.
4. Build and verify the EPF:

   ```bash
   python3 content/build_epf.py
   python3 content/build_epf.py --check
   ```

5. Import `content/mod-native-reagents.epf` into Content Manager, build cumulative content,
   activate it, and inspect the MPQ for the NativeReagents files and composed
   `Interface/FrameXML/FrameXML.toc`.
6. Distribute the patch through Portalkeeper and restart worldserver and client.

The package pins the verified 2,820-byte build-12340 stock TOC and inserts
`NativeReagentsFrame.xml` immediately after `BankFrame.xml`. Copying these files into an
AddOns folder is neither supported nor required.

## Configuration

| Setting | Default | Meaning |
| --- | ---: | --- |
| `NativeReagents.Enable` | `1` | Master switch. |
| `NativeReagents.Debug` | `0` | Log reagent operation authorization outcome and rejection reason. |
| `NativeReagents.AutoDeposit.Enable` | `1` | Permit per-character Auto Deposit. |
| `NativeReagents.Storage.MaxTypes` | `0` | Maximum distinct entries; `0` is unlimited. |
| `NativeReagents.Storage.MaxQuantityPerItem` | `0` | Per-entry cap; `0` is unlimited. |
| `NativeReagents.RemoteCraft.Enable` | `0` | Experimental crafting from storage; disabled for initial PTR banking validation. |
| `NativeReagents.RemoteCraft.TransactionTimeoutSeconds` | `30` | Temporary-loan rollback timeout. |
| `NativeReagents.BankerSession.TimeoutSeconds` | `300` | Maximum idle age of a validated banker session. |
| `NativeReagents.UI.Enable` | `1` | Enable the native bank path. |

## Banking and transaction safety

The server derives deposits from real inventory and withdrawals from stored rows. Client
item IDs and quantities are requests, never evidence. Bank-only mutations use AzerothCore's
normal `GetNPCIfCanInteractWith` banker validation. The session is created only after the
server observes and validates `CMSG_BANKER_ACTIVATE`; the client `BANKOPEN` message can only
confirm that existing server session. It cannot create authority. The session is cleared by
bank close, range/NPC failure, timeout, or logout. `NativeReagents.Debug=1` logs the operation,
authorization outcome, and precise reason without adding normal-gameplay log noise.

Inventory changes use `Player::SaveToDB(CharacterDatabaseTransaction, ...)` in the same
characters-database transaction as absolute storage balances and an operation-journal marker.
Critical transactions use the supported direct commit path and read the marker back before
success is reported. This short world-thread block is intentional: the asynchronous API
reports transaction success later and cannot safely prevent logout from independently saving
an unconfirmed inventory mutation. Per-character guards reject overlapping operations.

The journal makes successful deposit/withdraw request IDs durable and prevents replay while
their retained records exist. Completed records older than 30 days are pruned at login. Do not
run another process or module that directly mutates these rows while a character is online;
absolute serialized balances deliberately assume this documented single-writer rule.

Remote crafting is now disabled by default. When explicitly enabled for isolated testing it
aggregates duplicate reagent entries, validates all borrowing before changing storage,
journals `BORROWED`/`COMPLETED`/`ROLLEDBACK` states, and recovers exact outstanding loans on
login. Ambiguous recovery is quarantined as `REVIEW` and never blindly credited. Core source
confirms `OnSpellCast` occurs after `TakeReagents()` and immediate effects. However, no module
hook can make those core spell effects and a failed database completion commit one atomic
operation, so this feature is not approved for initial PTR use.

## Database compatibility and migration

The original tables are unchanged. Additive `character_native_reagent_operations` and
`character_native_reagent_operation_items` tables provide verified commits, durable replay,
and crafting recovery. They do not interfere with the original module; it simply ignores
them. No conversion, copy, `ALTER`, or destructive migration occurs.

To migrate:

1. Stop worldserver and back up the characters database.
2. Disable/remove `mod-bank-reagents`; never load both modules.
3. Install this module and apply its idempotent base SQL.
4. Deploy and activate the EPF, then start the server.
5. Verify representative balances and preferences before production use.

Returning to the original module remains practical because neither shared table is changed.

## Crafting behavior

When explicitly enabled, the profession hook combines carried and synchronized stored counts. Bag-only recipes still
use `DoTradeSkill`; recipes short on carried materials send the learned spell ID and count to
the server. The server revalidates recipe ownership, quantities, eligibility, inventory
capacity, and each cast. Create All is capped at 1,000 queued casts.

## Native client API

The stable API and callback contract are documented in
[`docs/NATIVE_CLIENT_API.md`](docs/NATIVE_CLIENT_API.md). `RegisterPresentation` lets future
UnifiedNativeBags claim visual ownership without replacing synchronization or operations;
passing `nil` releases it. UnifiedNativeBags itself is intentionally not implemented here.

## Testing

```bash
python3 tests/run_checks.py
```

This compiles executable protocol and safety-policy tests, runs synchronization simulations,
and validates SQL compatibility, transaction guards, quest protection, limits, Lua API,
Schema-3 load ordering, pinned TOC, and deterministic EPF contents. Live scenarios are in
[`docs/LIVE_TEST_PLAN.md`](docs/LIVE_TEST_PLAN.md).

## Troubleshooting

- **No Reagents tab:** confirm the active MPQ contains the NativeReagents files and composed
  TOC, and that the realm/client satisfies `protected-framexml`.
- **banker-required:** keep the stock bank open after normal banker interaction.
- **Profession UI reports missing materials:** remote crafting is intentionally disabled by
  default. Enable it only on an isolated test realm after reviewing the known limitation.
- **Nothing auto-deposits:** check the per-character toggle, global setting, recipe-derived
  eligibility, and active quest requirements.
- **Migration balances are absent:** verify the same characters database and only one module.

## Verification boundary

Automated checks and direct compilation of every module translation unit against the
available AzerothCore headers are supported. The module also compiled into AzerothCore's real
`libmodules.a`, and a no-PCH build linked the final `worldserver` executable against AzerothCore
`e7e2e288e`. UI behavior, live SQL commits, crafting interruption, cumulative MPQ generation,
and Portalkeeper delivery require the live plan and must not be inferred from build/static
checks alone.

Known limitations: the precise tab offsets, content crop, tooltip behavior, bank-bag purchase
popups, and controls at non-default UI scales still require the patched 3.3.5a client matrix.
Automated tests model the FrameXML lifecycle but do not render Blizzard textures. Remote
crafting remains outside this corrective pass and disabled by default.
