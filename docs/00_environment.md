# Environment detection & toolchain bring-up

A record of what this sandbox actually offered and why the toolchain is built
the way it is. (Stage 0.)

## What the box has

| Probe | Result |
|---|---|
| OS / CPU / RAM / disk | Ubuntu 24.04, 4 vCPU, 15 GiB RAM, ~31 GiB free |
| Native EDA tools | none (`openroad`/`yosys`/`klayout`/`magic` all absent) |
| Docker | client + daemon **startable** as root |
| Network | egress allowed to github, hub.docker.com API, ghcr, **pypi**, anaconda.org |

## Decision 1 — not the ORFS Docker image

The canonical ORFS route is `docker pull openroad/orfs` (image exists,
~1.58 GB). The daemon comes up, but **every layer blob download fails**:

```
GET https://production.cloudfront.docker.com/.../blobs/sha256/...  ->  403 Forbidden
```

The Docker Hub *API* (manifests, tags) is reachable, but the CloudFront blob
**CDN is firewalled**, so no image — ORFS or even `hello-world` — can be
pulled. Confirmed on retry and on a direct host probe. Docker is out.

## Decision 2 — native binaries via conda

The `litex-hub` conda channel (the `hdl/conda-eda` project) ships prebuilt
`openroad`, `yosys`, `klayout`, `magic`. anaconda.org is reachable, so this is
the path.

**TLS gotcha:** the egress proxy does MITM interception with a private CA that
lives only in the **system** bundle. `curl` trusts it; conda/pip ship their own
bundle and fail with `self-signed certificate in certificate chain`. Fix:

```bash
conda config --set ssl_verify /etc/ssl/certs/ca-certificates.crt
export SSL_CERT_FILE=REQUESTS_CA_BUNDLE=CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
```

**Solver gotcha:** installing `openroad + yosys + klayout` in one env
over-constrains (conflicting boost/qt/python pins across the litex-hub builds).
Install each tool in its **own env**:

- `openroad` resolves to build `2.0_3175_gf12e2f474` (OpenROAD SHA `f12e2f474`,
  ~2022-03-17). Newer litex-hub builds need `libboost 1.73`, which current
  conda-forge no longer carries, so the solver backtracks to this one — fine:
  it already has floorplan, RePlAce/OpenDP, TritonCTS, FastRoute, TritonRoute,
  `repair_timing`, `report_clock_skew`, OpenRCX, and embedded OpenSTA.
- `yosys` comes from conda-forge at `0.65`.
- `klayout` wouldn't solve on conda (Qt/libgit2/openssl conflicts) — installed
  from Ubuntu universe (`apt install klayout`, 0.28.16). Only needed for
  GDS-merge + screenshots.

`/usr/bin/time` (GNU time) is required by ORFS recipes → `apt install time`.

## Decision 3 — pin ORFS to the OpenROAD era

litex-hub builds OpenROAD on its own cadence, so no ORFS commit pins our exact
SHA. We check out ORFS **`de0a109f4` (2022-03-03)**, whose `tools/OpenROAD`
submodule predates our binary — so our binary is a *superset* of the commands
its Tcl scripts use, minimizing "unknown command" risk. ORFS vendors the
sky130hd LEF/LIB in-tree, so no separate PDK download is needed.

Two non-obvious ORFS invocation fixes (baked into the wrapper `Makefile`):
- recipes use `set -o pipefail` → must run under **bash**, not dash:
  `make SHELL=/bin/bash`.
- `versions.txt` shells out to `klayout`; if klayout is absent, pass
  `KLAYOUT_CMD=echo` so the synth→route→STA core still runs.

## Version skew note

Yosys (0.65, 2026) is much newer than OpenROAD (2022). The synth→P&R handoff is
a stable sky130-mapped gate netlist + Liberty, so this works — proven by the
`gcd` RTL→GDS smoke (0 DRC). Watched for on the larger Ibex build.

## Proof

`gcd`/sky130hd ran synth → floorplan → place → CTS → route → fill → SPEF →
signoff STA → GDS with **0 DRC** and positive setup/hold slack. See
`reports/gcd_base_qor.md` and the signoff path report from `make sta`.
