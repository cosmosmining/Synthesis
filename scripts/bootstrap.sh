#!/usr/bin/env bash
# rtl2gds-sta-lab — one-shot, reproducible toolchain bring-up.
#
# WHY NOT DOCKER: the canonical ORFS path is `docker pull openroad/orfs`, but in
# this sandbox the Docker daemon starts yet the layer CDN
# (production.cloudfront.docker.com) returns HTTP 403 for every blob, so no
# image can be pulled. We therefore install native binaries from conda and use
# the ORFS git tree only for its flow scripts/platform files.
#
# WHAT THIS INSTALLS
#   - Miniforge -> /opt/conda
#   - conda env 'or'    : openroad  (OpenSTA is compiled into the openroad binary)
#   - conda env 'yosys' : yosys + abc
#   - GNU time (apt)     : ORFS recipes call /usr/bin/time
#   - klayout (apt)      : optional, GDS-merge + layout screenshots
#   - ORFS git tree pinned to a commit whose tools match the conda openroad SHA
#
# Idempotent: re-running skips anything already present.
set -euo pipefail

CONDA_ROOT="${CONDA_ROOT:-/opt/conda}"
ORFS_ROOT="${ORFS_ROOT:-/home/user/ORFS}"
CA=/etc/ssl/certs/ca-certificates.crt

# The conda openroad we target is build 2.0_3175_gf12e2f474 (OpenROAD SHA
# f12e2f474, ~2022-03-17). We pin ORFS to a same-era commit so its Tcl scripts
# only use commands present in that binary.
ORFS_COMMIT="${ORFS_COMMIT:-de0a109f41}"   # 2022-03-03 "Bump OpenROAD"

echo "### [1/6] TLS: point conda at the system CA bundle (MITM proxy) ###"
export SSL_CERT_FILE="$CA" REQUESTS_CA_BUNDLE="$CA" CURL_CA_BUNDLE="$CA"

echo "### [2/6] Miniforge ###"
if [ ! -x "$CONDA_ROOT/bin/conda" ]; then
  curl -fsSL -o /tmp/miniforge.sh \
    "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
  bash /tmp/miniforge.sh -b -p "$CONDA_ROOT"
fi
"$CONDA_ROOT/bin/conda" config --set ssl_verify "$CA"
MAMBA="$CONDA_ROOT/bin/mamba"

echo "### [3/6] conda env: openroad ###"
# Installed standalone (not alongside yosys/klayout) because the litex-hub
# builds carry conflicting boost/qt/python pins that over-constrain a joint solve.
[ -x "$CONDA_ROOT/envs/or/bin/openroad" ] || \
  "$MAMBA" create -y -n or -c litex-hub -c conda-forge openroad

echo "### [4/6] conda env: yosys ###"
[ -x "$CONDA_ROOT/envs/yosys/bin/yosys" ] || \
  "$MAMBA" create -y -n yosys -c litex-hub -c conda-forge yosys

echo "### [5/6] apt: GNU time (+ klayout if reachable) ###"
command -v time >/dev/null 2>&1 || apt-get install -y -q time || true
if ! command -v klayout >/dev/null 2>&1; then
  apt-get update -q || true
  apt-get install -y -q klayout || echo "  (klayout optional; skipping)"
fi

echo "### [6/6] ORFS flow scripts (pinned to $ORFS_COMMIT) ###"
if [ ! -d "$ORFS_ROOT/.git" ]; then
  git clone https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git "$ORFS_ROOT"
fi
git -C "$ORFS_ROOT" checkout --quiet "$ORFS_COMMIT"

echo
echo "Bootstrap complete. Verify with:  source scripts/env.sh && make smoke"
