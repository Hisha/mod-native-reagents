# Live validation matrix

These checks require a running server, characters database, Content Manager build,
generation-2 protected-FrameXML client, and WoW 3.3.5a build 12340. They are not automated.
The approved targets are [`../design/Bank Tab mockup.png`](../design/Bank%20Tab%20mockup.png)
and [`../design/Reagent Tab mockup.png`](../design/Reagent%20Tab%20mockup.png).

## Rebuild and deploy to PTR

1. In the AzerothCore checkout, update `modules/mod-native-reagents` to this working tree and
   keep `NativeReagents.RemoteCraft.Enable = 0`. Set `NativeReagents.Debug = 1` for the first
   authorization pass only.
2. Reconfigure and rebuild using the realm's normal preset. At minimum, build the module and
   worldserver targets; for a conventional build directory:

   ```bash
   cmake -S . -B build -DMODULES=static -DSCRIPTS=static
   cmake --build build --target modules worldserver -j2
   ```

3. Restart worldserver only after its normal backup/change procedure. No new destructive SQL
   is required. If the journal update was never installed, apply
   `data/sql/db-characters/updates/2026_11_11_00_native_reagent_operations.sql` while the realm
   is stopped.
4. In this module repository, rebuild and verify the client package:

   ```bash
   python3 tests/run_checks.py
   python3 content/build_epf.py --check
   ```

5. Import `content/mod-native-reagents.epf` into mod-content-manager. Build it cumulatively with
   the PTR's existing packages, confirm the generated MPQ contains all three NativeReagents
   FrameXML files and the composed `FrameXML.toc` entry immediately after `BankFrame.xml`, then
   activate that content generation.
6. Publish the activated patch through the existing Portalkeeper workflow with
   `Requirements=protected-framexml`. Fully exit the WoW client, let Portalkeeper update it,
   and confirm the client is build 12340 and using the new cumulative patch. Do not copy these
   files into `Interface/AddOns`.

## PTR validation matrix

- Open Teller Gee and at least two other stock bankers. Confirm **Bank** is selected by default;
  the two tabs are below the bottom border; the stock slots, bank bags, purchased bags, purchase
  button/popups, money, title, portrait, close button, deposits, and withdrawals behave normally.
- Select **Reagents**. Confirm no stock slot, stock label, bank bag, purchase control, or money
  control remains visible behind the full-page reagent content. Confirm the title, portrait,
  border, close button, and both tabs remain visible and Reagents is highlighted.
- Switch Bank/Reagents at least 20 times, close while each page is selected, and reopen. Bank
  must always be the default; no duplicate controls, Lua errors, hidden stock controls, or stale
  reagent controls may remain.
- Repeat at 0.64, 0.8, and 1.0 UI scale (or the PTR-supported range). Tabs must stay attached to
  BankFrame and must not overlap content or other panels.
- Exercise empty, single-type, multi-type, large, limited, and overflow-boundary deposits;
  confirm active-quest reagents remain carried.
- Withdraw one stack and shift-selected quantities into empty, partial, and full bags;
  repeat a captured request ID and confirm only one mutation in the server session.
- Toggle Auto Deposit, relog/restart, and confirm preference persistence and manual deposit
  availability while disabled.
- With empty storage, confirm `No reagents stored` and 42 initialized empty slots. With 1, 42,
  43, and 85 distinct entries, verify `Page X of Y`, disabled bounds, Previous/Next, mouse-wheel
  navigation, icons, quality borders, quantities above normal stack size, and tooltips.
- Right-click an entry to withdraw one normal stack; shift-click it to withdraw a chosen amount.
  Confirm successful deposit/withdraw refreshes and full-bag/invalid-quantity failures do not
  corrupt the displayed or persisted balance.
- For authorization, capture the worldserver log with `NativeReagents.Debug=1`. A legitimate
  Teller Gee open must show `BANKOPEN ... outcome=allowed reason=authorized`; deposit, auto,
  and withdrawal must also be allowed. Move out of range, close the bank, wait beyond the
  configured timeout, and replay stale/forged requests: each must be rejected with a targeted
  reason. Merely targeting a banker or sending `BANKOPEN` without a validated activation must
  remain rejected. Return `NativeReagents.Debug=0` after this pass.
- Keep `NativeReagents.RemoteCraft.Enable=0` for the initial banking pass. On a separate
  isolated pass only, enable it and craft with carried-only, stored-only, and mixed materials; test Create, Create All,
  cancellation, failed casts, full bags, logout, stack merging, and server restart recovery.
- Import/build the EPF cumulatively beside existing packages, inspect generated MPQ members,
  deploy through Portalkeeper with `protected-framexml`, and verify tooltips/quality borders.
- Repeat without BankReagentsUI and UnifiedBags335 installed. Test an alternative presenter
  using the documented API, then release ownership and confirm the default view returns.
- Open normal bags, a guild bank, mail, vendors, auction house, and profession windows before
  and after bank use; verify this presentation changes only the personal BankFrame.

Record screenshots for both pages, the exact cumulative content generation, Portalkeeper
package version, worldserver revision, UI scale, `/console scriptErrors 1` output, debug
authorization lines, database balances before/after, and every failed scenario. A clean live
pass is still required before calling the visual design or banker sequence PTR-verified.
