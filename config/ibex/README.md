# Ibex experiment matrix (sky130hd)

All configs here are **generated** by `scripts/gen_experiments.py` — edit the
matrix there, not these files. Each `<name>.mk` is run with
`make route CONFIG=config/ibex/<name>.mk FLOW_VARIANT=<name>`, so outputs stay
separated by `FLOW_VARIANT` and never clobber.

## Fixed choices (and why)
- **Core utilization = 20 %.** Ibex on sky130hd is *timing-bound*, not
  area-bound — 130 nm standard cells are slow, so the critical path, not the
  cell area, sets the die. A low utilization gives the placer slack to close
  timing; it is also the ORFS default. E3 deliberately sweeps **up** from here
  to expose the congestion/timing wall.
- **Aspect ratio = 1.0, core margin = 2.** Ibex is a single clock-domain core
  with no hard macros or edge-IO constraints, so a square core minimizes the
  longest Manhattan wire; no reason to skew it.
- **I/O delay = 20 % of the clock.** Models off-chip launch/capture budget.

## Clock ladder (E1) — relaxed → aggressive
`22, 20, 19, 18, 16, 15 ns`. The 20 %/17.4 ns calibration already showed
WNS < 0 post-route, so the Fmax wall is bracketed here. **`clk19` is the
"achievable" anchor** reused as the baseline for E2 (WB=0) and E3 (util=20).

## Sweeps
- **E2 pipelining:** `wb1.mk` sets `VERILOG_TOP_PARAMS = WritebackStage 1`,
  turning Ibex's 2-stage pipe into 3-stage (writeback stage). Propagates to
  `ibex_id_stage`/`ibex_wb_stage` via `chparam` at elaboration — a real RTL
  parameter flip, no file edits. Baseline (WB=0) = `clk19`.
- **E3 utilization:** `util40`, `util60` at the achievable clock (19 ns);
  20 % point reuses `clk19`. Run to full route so congestion (DRC, wirelength)
  is real.
