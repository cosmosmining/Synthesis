#!/usr/bin/env bash
# Sequentially drive a list of experiment variants to routed + signoff-STA.
#
#   scripts/run_experiments.sh clk22 clk19 clk17.4 util20 util70 wb1 ...
#
# variant name == config/ibex/<name>.mk == FLOW_VARIANT (outputs are kept
# separate by FLOW_VARIANT, so points never clobber each other).
#
# A point that fails *timing* still routes — that is the Fmax wall, not a flow
# failure, so we record it and continue. A point that fails to *route/crash* is
# logged loudly for follow-up (we do not loosen anything to hide it).
set -uo pipefail
cd "$(dirname "$0")/.."
LOGD="${LOGD:-/tmp/exp_logs}"; mkdir -p "$LOGD"

for fv in "$@"; do
  cfg="config/ibex/${fv}.mk"
  if [ ! -f "$cfg" ]; then echo "SKIP $fv (no $cfg)"; continue; fi
  echo "=== [$(date +%H:%M:%S)] START $fv ==="
  if make route CONFIG="$cfg" FLOW_VARIANT="$fv" >"$LOGD/${fv}.route.log" 2>&1; then
    if make sta CONFIG="$cfg" FLOW_VARIANT="$fv" >"$LOGD/${fv}.sta.log" 2>&1; then
      ws=$(grep -m1 "setup worst slack:" "$LOGD/${fv}.sta.log" | awk '{print $4}')
      echo "=== [$(date +%H:%M:%S)] DONE  $fv  setup_ws=${ws:-?} ==="
    else
      echo "=== [$(date +%H:%M:%S)] STA-FAIL $fv (see $LOGD/${fv}.sta.log) ==="
    fi
  else
    echo "=== [$(date +%H:%M:%S)] ROUTE-FAIL $fv (see $LOGD/${fv}.route.log) ==="
  fi
done
echo "ALL_EXPERIMENTS_DONE"
