namespace ConnectionFSM

/-- A model of the client↔server connection lifecycle that produced the "ghost"
    bug: the server drops a silent client after a liveliness window, but the
    client keeps a stale identity and never re-announces, so it believes it is
    connected while the server has forgotten it. The fix is one rule — a client
    that stops hearing the server re-joins. Plausible checks soundness (the
    client's belief never disagrees with the server once settled) and
    completeness (from any history, an awake client recovers). -/

inductive CState | disc | conn | joined
  deriving DecidableEq, Repr

/-- Combined world: the client's view, the server's view, and the link. -/
structure W where
  cs          : CState := .disc
  joinedFlag  : Bool := false   -- client believes it is in the game
  clientSilent: Nat := 0        -- ticks since the client last heard the server
  serverHas   : Bool := false   -- the server holds this client in `players`
  serverSilent: Nat := 0        -- ticks since the server last heard the client
  up          : Bool := false   -- transport (QUIC session) is up
  awake       : Bool := true    -- headset awake (and therefore sending)
  deriving Repr

def LIVENESS : Nat := 15  -- server drops a client silent this many seconds
def REJOIN   : Nat := 4   -- client re-joins after this many silent seconds

inductive Ev | tick | sleep | wake
  deriving Repr

/-- One step. `fix` toggles the auto-rejoin rule (the patch under test). -/
def step (fix : Bool) (w : W) : Ev → W
  | .sleep => { w with awake := false }
  | .wake  => { w with awake := true }
  | .tick =>
    -- 1. the server hears the client only if it is awake, linked, and known
    let serverSilent := if w.awake && w.up && w.serverHas then 0 else w.serverSilent + 1
    -- 2. liveliness: drop a client silent past the window
    let serverHas := if serverSilent > LIVENESS then false else w.serverHas
    -- 3. the server pings known clients; the client hears it
    let clientSilent := if serverHas && w.up then 0 else w.clientSilent + 1
    -- 4. the client connection state machine
    if !w.up then
      -- transport down → rebuild and reconnect
      { w with up := true, cs := .conn, joinedFlag := false,
               clientSilent := 0, serverHas := serverHas, serverSilent := serverSilent }
    else match w.cs with
      | .disc => { w with cs := .conn, serverHas := serverHas, serverSilent := serverSilent, clientSilent := clientSilent }
      | .conn =>
        -- send join → the server admits this client
        { w with cs := .joined, joinedFlag := true, serverHas := true,
                 serverSilent := 0, clientSilent := 0 }
      | .joined =>
        if fix && clientSilent > REJOIN then
          -- THE FIX: server has gone silent → assume dropped, re-join
          { w with cs := .conn, joinedFlag := false, serverHas := serverHas, serverSilent := serverSilent, clientSilent := clientSilent }
        else
          { w with serverHas := serverHas, serverSilent := serverSilent, clientSilent := clientSilent }

def run (fix : Bool) (es : List Ev) : W :=
  es.foldl (step fix) ({})

/-- After a history, put the headset on and give it `k` ticks to settle. -/
def settle (fix : Bool) (w : W) (k : Nat) : W :=
  (List.replicate k Ev.tick).foldl (step fix) { w with awake := true }

def evOf (ns : List Nat) : List Ev :=
  ns.map (fun n => match n % 6 with | 0 => .sleep | 1 => .wake | _ => .tick)

end ConnectionFSM
