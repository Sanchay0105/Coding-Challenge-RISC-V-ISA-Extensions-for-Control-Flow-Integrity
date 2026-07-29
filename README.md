# RISC-V Control Flow Integrity Challenge — 3-State FSM

A SystemVerilog implementation and verification environment for a 3-state
control-flow FSM, built as part of a submission for the Linux Foundation
RISC-V mentorship application.

## Problem Statement

Implement a 3-state FSM that accepts a 32-bit packet every cycle:
- Bits `[31:24]` — command: `SET (0x01)`, `JUMP (0x02)`, `LPAD (0x03)`
- Bits `[23:0]` — payload data

**Behavior:**
- **IDLE**: on `SET`, store payload into an internal label register and stay
  in IDLE. On `JUMP`, move to `CHECK`. Any other command, stay in IDLE.
- **CHECK**: on `LPAD` with payload matching the stored label, return to
  IDLE. Otherwise (wrong command or mismatched payload), move to `ERROR`.
- **ERROR**: terminal state — stays in `ERROR` forever until reset.

## Files

| File | Description |
|---|---|
| `fsm_pkg.sv` | Shared `states` enum typedef, imported by DUT and TB |
| `top.sv` | DUT — the FSM module |
| `tb.sv` | Self-checking testbench |
| `files.f` | File list for compilation |

## Design Notes

- `label_reg` is implemented in a dedicated `always_ff` block (not inside
  the combinational next-state logic) to avoid inferring a latch.
- `current_state` and `label_out` are exposed as primary outputs
  specifically to support black-box verification — the testbench never
  reaches into DUT internals.

## Verification Methodology

Verification is layered, matched to the FSM's complexity:

1. **Directed tests** — cover every named transition in the spec, plus:
   - Invalid commands in every state (not just IDLE)
   - Back-to-back SETs (only the last value before JUMP should stick)
   - Reset asserted from every state, including ERROR
2. **Self-checking scoreboard** — a reference model runs in parallel with
   the DUT and its predicted state/label are compared every cycle. Pass/fail
   is automatic; no manual waveform inspection required.
3. **Property checks** for implicit invariants the spec implies but doesn't
   state outright:
   - `ERROR` is sticky — once entered, never left except by reset
   - `CHECK` is only reachable via a valid `JUMP` from `IDLE`
   - Reset always forces `IDLE` on the following cycle

   These were originally written as SystemVerilog Assertions
   (`property` / `assert property`), but Icarus Verilog (the simulator
   used here) has incomplete support for concurrent SVA syntax. They were
   converted to equivalent procedural checks (`always` blocks with
   `$error`) without changing what is being verified. With a commercial
   simulator or newer Verilator, these would be re-expressed as native SVA.

4. **Not implemented, intentionally**: constrained-random stimulus and
   functional coverage. For a 3-state FSM, this would be effort mismatched
   to the problem's complexity — directed tests already achieve full
   transition and edge-case coverage. Noted here as the natural next step
   if the design were to grow (e.g. more commands, wider states).

### A verification bug, not just a DUT bug

During development, the "ERROR is sticky" checker itself produced a false
positive: it flagged a transition out of ERROR that was actually a
**legitimate reset recovery**, because the check only looked at the
current cycle's `rst` and not whether reset had occurred in the
intervening cycle. Fixed by also gating on `prev_rst`. Left as a reminder
that testbenches need their own verification too, not just the DUT.

## Tooling Notes (oss-cad-suite / Icarus Verilog)

- `always_comb` sensitivity-list inference on part-selects
  (`data[31:24]`) is imprecise in Icarus — it conservatively becomes
  sensitive to the full 32-bit bus. This produces a compiler warning but
  does not affect correctness.
- Enum `.name()` method calls fail on port-connected (net-typed) enum
  signals in Icarus; a small helper function (`state_name()`) is used
  instead to print human-readable state names in `$error` messages.

## Running

```bash
source /path/to/oss-cad-suite/environment.sh   # activate toolchain
iverilog -g2012 -o sim.vvp -f files.f
vvp sim.vvp
```

Expected output on success:

To view waveforms:
```bash
gtkwave tb.vcd
```

## Author

Sanchay — Final-year ECE, RCOEM Nagpur
