# Automated checks

Run `python3 tests/run_checks.py`. The suite compiles protocol and safety-policy tests,
executes controlled commit-failure/duplicate/concurrency models, simulates synchronization
ordering/timeouts/retries, and checks the Schema-3 manifest, pinned stock TOC, deterministic
EPF contents, backward-compatible SQL, journal schema, quest protection, limits, and Lua API.
It also compiles both client files with the available Lua library and executes a mocked WoW
FrameXML lifecycle covering 42-button initialization, empty/populated pagination, mutually
exclusive pages, stock-control restoration, and close/reopen behavior. `pkg-config lua` and
the corresponding development headers are therefore required to run the full suite.

It is deliberately not a substitute for the live AzerothCore and patched-client matrix in
`docs/LIVE_TEST_PLAN.md`.
