#!/usr/bin/env bash
# One-shot batch to finish all Ibex experiments. Launch in background.
# Progress: "DONE <x>" / "FAIL <x>" lines (Monitor-friendly). Order front-loads
# the highest-value deliverables.
set -uo pipefail
cd "$(dirname "$0")/.."
LOGD=/tmp/exp_logs; mkdir -p "$LOGD"
BASECFG=/home/user/ORFS/flow/designs/sky130hd/ibex/config.mk

echo "##### FINISH-BATCH START $(date +%H:%M:%S) #####"

# (1) achievable-edge baseline (already routed) -> SPEF signoff + top-5 paths + CTS
echo "### group 1/4: base finish + signoff STA ###"
if make finish CONFIG="$BASECFG" FLOW_VARIANT=base >"$LOGD/base.finish.log" 2>&1; then
  make sta CONFIG="$BASECFG" FLOW_VARIANT=base >"$LOGD/base.sta.log" 2>&1 \
    && echo "DONE base (finish+sta)" || echo "FAIL base sta"
else echo "FAIL base finish"; fi

# (2) clk19 + E3 util to global route (timing + FastRoute congestion).
#     clk19 triple-duties as E1@19ns, E2 WB=0 baseline, E3 util=20 point.
echo "### group 2/4: global-route (clk19, util40, util60) ###"
STAGE=globalroute scripts/run_experiments.sh clk19 util40 util60

# (3) rest of the E1 clock ladder to post-CTS (fast)
echo "### group 3/4: E1 clock ladder post-CTS ###"
STAGE=cts scripts/run_experiments.sh clk22 clk20 clk18 clk16 clk15

# (4) E2 pipelining (WritebackStage=1) to post-CTS, vs clk19 (WB=0)
echo "### group 4/4: E2 WritebackStage=1 post-CTS ###"
STAGE=cts scripts/run_experiments.sh wb1

echo "##### FINISH-BATCH DONE $(date +%H:%M:%S) #####"
