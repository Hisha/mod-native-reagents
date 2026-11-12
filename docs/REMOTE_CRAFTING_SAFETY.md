# Remote crafting safety status

Remote crafting is disabled by default for initial PTR banking validation.

## Verified core ordering

In the available AzerothCore source, `Spell::cast` calls `TakeReagents()` before effects and
calls `sScriptMgr->OnSpellCast(...)` afterward. `OnSpellCheckCast` runs before the ordinary
reagent check. Therefore:

- borrowing must be complete before the remainder of `CheckCast`;
- cancellation before cast execution may return the full unused loan; and
- `OnSpellCast` is post-consumption and must never refund the loan.

## Implemented hardening

- Requirements are aggregated by item entry.
- Every required loan is validated before persistent storage changes.
- Partial materialization failure removes all earlier temporary quantities.
- Borrowed storage debits, physical inventory, journal header, and per-item baseline rows
  commit together and are verified.
- `BORROWED` records roll back on cancellation, timeout, or logout.
- Login recovery rolls back only when every entry still has the exact minimum
  `baseline + borrowed` balance. Any ambiguity becomes `REVIEW`; it is never credited.
- Successful casts persist consumed inventory, created results, and `COMPLETED` state in one
  module transaction. Borrow records are cleared only after the post-consumption hook.
- Sale, mail, and trade hooks continue to reject entries participating in a live loan.

## Remaining core-bound limitation

Spell reagent consumption and effects occur inside core before the module completion hook.
No supported module hook encloses those changes in a caller-supplied database transaction.
If the completion database commit fails after core effects have executed, the module cannot
atomically undo an arbitrary crafted effect/output. It quarantines the journal and disconnects
the session rather than refunding consumed reagents, but that path still needs operator review.

Eliminating this final ambiguity requires a core integration that lets a module either:

1. provide virtual reagent availability/consumption directly to `CheckCast`/`TakeReagents`,
   or
2. participate in a transaction spanning reagent consumption, spell effects, and inventory
   persistence.

No core modification is included or authorized here. Until such an integration is reviewed,
keep `NativeReagents.RemoteCraft.Enable = 0` outside isolated testing.
