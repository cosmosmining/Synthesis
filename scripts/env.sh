#!/usr/bin/env bash
# rtl2gds-sta-lab — environment configuration.
# Source this before driving the flow:   source scripts/env.sh
#
# The toolchain is NOT the ORFS Docker image: in this environment the Docker
# layer CDN (production.cloudfront.docker.com) is firewalled (HTTP 403), so
# image pulls fail. Instead we use native binaries from conda (litex-hub +
# conda-forge) and ORFS purely for its flow *scripts*. See docs/00_environment.md.

# --- conda tool envs (created by scripts/bootstrap.sh) ---
export CONDA_ROOT="${CONDA_ROOT:-/opt/conda}"
export OR_BIN="$CONDA_ROOT/envs/or/bin"          # openroad (OpenSTA compiled in)
export YOSYS_BIN="$CONDA_ROOT/envs/yosys/bin"    # yosys + abc

# --- ORFS flow scripts (cloned + pinned by bootstrap.sh) ---
export ORFS_ROOT="${ORFS_ROOT:-/home/user/ORFS}"
export ORFS_FLOW="$ORFS_ROOT/flow"

# --- TLS: this sandbox MITM-intercepts HTTPS with a private CA that is present
#     only in the system bundle. Tools that ship their own bundle (conda, pip,
#     python-requests) must be pointed at the system one or they fail verify. ---
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

# --- PATH: tool bins first ---
export PATH="$OR_BIN:$YOSYS_BIN:$PATH"

# klayout is optional (only GDS-merge + screenshots). Prefer an apt/system
# install; fall back to a conda env; else leave a no-op so the core flow runs.
if command -v klayout >/dev/null 2>&1; then
  export KLAYOUT_CMD="$(command -v klayout)"
elif [ -x "$CONDA_ROOT/envs/klayout/bin/klayout" ]; then
  export KLAYOUT_CMD="$CONDA_ROOT/envs/klayout/bin/klayout"
  export PATH="$CONDA_ROOT/envs/klayout/bin:$PATH"
else
  export KLAYOUT_CMD="echo"   # no-op: versions.txt etc. still succeed
fi

# --- explicit handles the ORFS Makefile honours ---
export OPENROAD_EXE="$OR_BIN/openroad"
export YOSYS_CMD="$YOSYS_BIN/yosys"

echo "[env] openroad : $(command -v openroad || echo MISSING)"
echo "[env] yosys    : $(command -v yosys || echo MISSING)"
echo "[env] klayout  : $KLAYOUT_CMD"
echo "[env] ORFS_FLOW: $ORFS_FLOW"
