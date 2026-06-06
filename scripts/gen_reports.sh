#!/usr/bin/env bash
# Regenerate every markdown report in reports/ from the current ORFS logs.
# Nothing here is hand-edited — re-run after any flow run.
set -uo pipefail
cd "$(dirname "$0")/.."
ORFS=/home/user/ORFS/flow
P=sky130hd; D=ibex
PE() { python3 scripts/parse/parse_experiment.py --platform $P --design $D --orfs-flow $ORFS "$@"; }

# --- STA deep-dive + CTS (base = 17.4 ns SPEF signoff) ---
python3 scripts/parse/parse_paths.py \
  --rpt $ORFS/reports/$P/$D/base/signoff_sta.rpt --out reports/ibex_sta_paths.md
python3 scripts/cts/cts_report.py \
  --log-dir $ORFS/logs/$P/$D/base --results-dir $ORFS/results/$P/$D/base \
  --reports-dir $ORFS/reports/$P/$D/base --clock-net clk_i \
  --out reports/ibex_cts_analysis.md

# --- E1 clock-period ladder (post-CTS) ---
PE --title "E1 — clock-period ladder (Ibex / sky130hd, post-CTS STA)" --rowlabel "Clock (ns)" \
  --cols setup_ws,hold_ws,fmax,area,clk_buffers \
  --variant clk22:22 --variant clk20:20 --variant clk19:19 \
  --variant clk18:18 --variant clk16:16 --variant clk15:15 \
  --note "_Post-CTS placement-estimated parasitics (optimistic vs SPEF signoff — see docs/sta_deep_dive.md). Hold WS is pre-routing-repair, hence period-independent and negative across the ladder. Fmax = 1/(period − setup WNS)._" \
  --out reports/E1_clock_sweep.md
python3 scripts/parse/crit_migration.py --orfs-flow $ORFS \
  --variant clk22:22 --variant clk20:20 --variant clk19:19 \
  --variant clk18:18 --variant clk16:16 --variant clk15:15 \
  --out reports/E1_path_migration.md

# --- E2 pipelining: WritebackStage 0 vs 1 (19 ns, util20, post-CTS) ---
PE --title "E2 — pipelining: WritebackStage 0 vs 1 (Ibex / 19 ns, post-CTS)" --rowlabel "Config" \
  --cols setup_ws,hold_ws,fmax,area,cells,power \
  --variant clk19:"WB=0 (2-stage)" --variant wb1:"WB=1 (3-stage)" \
  --note "_WritebackStage flipped via VERILOG_TOP_PARAMS (chparam) — propagates to ibex_id_stage/ibex_wb_stage._" \
  --out reports/E2_pipelining.md

# --- E3 utilization sweep (global route: congestion + timing) ---
PE --title "E3 — utilization sweep (Ibex / 19 ns, post-global-route)" --rowlabel "Util target (%)" \
  --cols setup_ws,fmax,area,peak_usage,overflow,gr_wl \
  --variant clk19:20 --variant util40:40 --variant util60:60 \
  --note "_'Area' is placed **cell** area (≈constant — identical netlist); the knob shrinks the **canvas**. Timing is logic-bound, so Fmax barely moves 20→40%, but peak global-route usage on the busiest layer climbs **29%→55%** as the die tightens. At 60% the buffered netlist needs ~76% density yet the die offers only 60% → RePlAce **GPL-0302, placement infeasible** (the density wall). Here density costs **congestion**, not speed — until it costs you routability entirely._" \
  --out reports/E3_util_sweep.md

echo "all reports regenerated"
