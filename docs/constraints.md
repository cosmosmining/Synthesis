# Constraints I can defend (Ibex / sky130hd)

The SDC the flow actually uses is generated (`config/ibex/sdc/*.sdc`); this is
the line-by-line justification. The guiding rule: **every constraint earns its
place — no cargo-cult exceptions.**

```tcl
create_clock -name core_clock -period <P> [get_ports clk_i]      # the only clock
set clk_io_pct 0.2
set_input_delay  [expr <P>*0.2] -clock core_clock [all non-clock inputs]
set_output_delay [expr <P>*0.2] -clock core_clock [all outputs]
```

### 1. `create_clock` on `clk_i` — and why it's the *only* clock
Ibex (this config: `RV32MFast`, `RegFileFF`, no `BranchTargetALU`) is a **single
synchronous clock domain**. There is exactly one clock port, `clk_i`. The flow's
clock-tree run shows two clock *nets* — `clk_i` (996 sinks) and `clk` (943
sinks) — but `clk` is the **gated** version produced by Ibex's
`prim_clock_gating` cells, not a second domain. Same source, same edges → no
clock relationship to declare, and **no CDC**: a clock-gate latch is timed
within the domain, it does not cross domains.

### 2. `set_input_delay` / `set_output_delay` = 20 % of the period
Models the off-chip budget: an upstream chip launches our inputs partway into
the cycle and a downstream chip needs our outputs before its own setup. 0.2·P
is a deliberate, *stated* budget, not a default I forgot to set — it makes the
I/O paths carry real (not zero) external delay so the tool optimizes them.
A real tape-out would replace this with characterized board/IO numbers.

### 3. What I deliberately did **not** add (the anti-cargo-cult part)

- **No async clock groups / `set_clock_groups`.** There is one clock. Declaring
  groups would be theater.
- **No CDC false paths / synchronizer exceptions.** No clock crossing exists.
- **No blanket `set_false_path -from rst_ni`.** Tempting — reset is async — but
  Ibex expects an **externally synchronized** reset (async assert, sync
  de-assert). The de-assertion *is* a real timing event, so OpenSTA's
  **recovery/removal** checks on `rst_ni` (the `**async_default**` path group
  that shows up in the reports) are legitimate and worth keeping. Blanket
  false-pathing reset would hide a real removal failure. I only false-path a
  reset when I can point to the synchronizer that justifies it.
- **No multicycle paths.** Nothing in this Ibex config is documented as taking
  >1 cycle (the multi-cycle divider has its own internal valid handshake, not a
  multicycle *timing* exception). Adding an MCP without an RTL contract behind
  it is how you ship silicon that fails.

### 4. Corner & analysis settings (from the platform, not me)
sky130hd signs off at the **`tt_025C_1v80`** typical corner with a single
Liberty. ORFS applies its default timing derates/OCV and CRPR (clock
reconvergence pessimism removal) — see `docs/sta_cts_field_notes.md §5` for the
actual derate/CRPR values pulled from my reports.
