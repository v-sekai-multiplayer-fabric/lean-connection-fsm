# connection_fsm

A Lean 4 + Plausible model of the client↔server connection lifecycle, written to
pin a real bug: a client dropped by the server's liveliness window keeps a stale
identity and never re-announces, so it believes it is connected while the server
has forgotten it (a "ghost"). The fix is one rule — a client that stops hearing
the server re-joins.

## What Plausible proves

- **Soundness** — the client's belief never disagrees with the server once
  settled (`joinedFlag == serverHas`). No ghost.
- **Completeness within a 5-second budget** — from any history, an awake client
  is healthy (joined and server-acknowledged) within 5 ticks. One tick is one
  second, so this is a FoundationDB-style **5-second transaction limit**: a
  stuck connection self-heals inside 5 s rather than waiting forever.

The buggy protocol (no auto-rejoin) is shown not complete: Plausible finds a
counter-example, and the runnable witness stays `healthy=false` after 100 s.

```sh
lake exe fsm_demo
# FIXED: soundness 30000/30000, recovery-within-5s 30000/30000
# GHOST history -> BUGGY after 100s: healthy=false (cs=joined, serverHas=false, joinedFlag=true)
# GHOST history -> FIXED after 5s:   healthy=true
```

`LIVENESS = 15` (server drop window), `REJOIN = 4` (client re-join delay),
`BUDGET = 5` (the transaction limit). The fix lives in the loop client's
connection state machine.
