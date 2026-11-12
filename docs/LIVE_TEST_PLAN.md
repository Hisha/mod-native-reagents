# Live validation matrix

These checks require a running server, characters database, Content Manager build,
generation-2 protected-FrameXML client, and WoW 3.3.5a build 12340. They are not automated.

- Open several stock bankers: Personal Bank is default, bank bags and purchases work, and
  Reagents switches without affecting guild bank behavior.
- Exercise empty, single-type, multi-type, large, limited, and overflow-boundary deposits;
  confirm active-quest reagents remain carried.
- Withdraw one stack and shift-selected quantities into empty, partial, and full bags;
  repeat a captured request ID and confirm only one mutation in the server session.
- Toggle Auto Deposit, relog/restart, and confirm preference persistence and manual deposit
  availability while disabled.
- Keep `NativeReagents.RemoteCraft.Enable=0` for the initial banking pass. On a separate
  isolated pass only, enable it and craft with carried-only, stored-only, and mixed materials; test Create, Create All,
  cancellation, failed casts, full bags, logout, stack merging, and server restart recovery.
- Import/build the EPF cumulatively beside existing packages, inspect generated MPQ members,
  deploy through Portalkeeper with `protected-framexml`, and verify tooltips/quality borders.
- Repeat without BankReagentsUI and UnifiedBags335 installed. Test an alternative presenter
  using the documented API, then release ownership and confirm the default view returns.
