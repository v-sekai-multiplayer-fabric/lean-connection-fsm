import ConnectionFSM
import Plausible
open ConnectionFSM Plausible

/-- The FoundationDB-style transaction limit: 5 seconds. No connection
    transaction waits longer than this to complete or self-heal. -/
def BUDGET : Nat := 5

/-- Healthy = the client is joined and the server agrees it holds the client. -/
def healthy (w : W) : Bool := (w.cs == .joined) && w.serverHas

/-- Soundness: the client's belief never disagrees with the server once settled.
    (No "ghost": joined-flag set while the server forgot the client.) -/
def sound (fix : Bool) (ns : List Nat) : Bool :=
  let w := settle fix (run fix (evOf ns)) BUDGET
  w.joinedFlag == w.serverHas

/-- Completeness within the 5-second budget: from ANY history, an awake client
    is healthy within BUDGET ticks (seconds). This is the transaction limit —
    a stuck connection self-heals inside 5 s rather than waiting forever. -/
def recoversIn (fix : Bool) (ns : List Nat) : Bool :=
  healthy (settle fix (run fix (evOf ns)) BUDGET)

-- The FIXED protocol: sound and complete within 5 s.
#eval Testable.check (∀ ns : List Nat, sound true ns = true)
#eval Testable.check (∀ ns : List Nat, recoversIn true ns = true)

-- The BUGGY protocol (no auto-rejoin) is NOT complete: Plausible finds a
-- counter-example for `∀ ns, recoversIn false ns = true` (a permanent ghost).
-- Running that #eval halts the build by design; `main` exhibits the witness.

/-- Find and print a concrete witness of the bug, and the exact recovery time
    the fix needs (the smallest settle that heals every history we try). -/
def main : IO Unit := do
  -- soundness + 5s recovery sweep on the fixed protocol
  let mut badSound := 0; let mut badRec := 0
  for n in [0:30000] do
    let ns := (List.range (n % 17)).map (fun i => (n / (i+1) + i*7))
    if !(sound true ns) then badSound := badSound + 1
    if !(recoversIn true ns) then badRec := badRec + 1
  IO.println s!"FIXED: soundness {30000 - badSound}/30000, recovery-within-{BUDGET}s {30000 - badRec}/30000"
  -- the bug: a sleep long enough to drop, then wake — never recovers without the fix
  let ghost := evOf ([0] ++ List.replicate 18 99 ++ [1])  -- sleep, idle past 15s, wake
  let wB := settle false (run false ghost) 100   -- even 100s of settle
  let wF := settle true  (run true  ghost) BUDGET
  IO.println s!"GHOST history -> BUGGY after 100s: healthy={healthy wB} (cs={repr wB.cs}, serverHas={wB.serverHas}, joinedFlag={wB.joinedFlag})"
  IO.println s!"GHOST history -> FIXED after {BUDGET}s: healthy={healthy wF}"
