#!/usr/bin/env bash
# Full Ibex experiment batch. Launch in the background AFTER the calibration
# route finishes (they would otherwise contend for CPU). Progress lands as
# "DONE <fv>" / "FAIL <fv>" lines that a Monitor can stream.
#
#   group 1  achievable baseline  -> full route + OpenRCX SPEF (deep-dive + CTS)
#   group 2  E1 clock ladder      -> post-CTS STA (fast; Fmax wall + path migration)
#   group 3  E3 util + E2 pipeline -> full route (congestion + PPA need routing)
set -uo pipefail
cd "$(dirname "$0")/.."

echo "##### BATCH START $(date +%H:%M:%S) #####"
echo "### group 1/3: achievable baseline clk19 (finish + SPEF) ###"
STAGE=finish scripts/run_experiments.sh clk19

echo "### group 2/3: E1 clock ladder (post-CTS) ###"
STAGE=cts scripts/run_experiments.sh clk22 clk20 clk18 clk16 clk15

echo "### group 3/3: E3 utilization + E2 pipelining (full route) ###"
STAGE=route scripts/run_experiments.sh util40 util60 wb1

echo "##### BATCH DONE $(date +%H:%M:%S) #####"
