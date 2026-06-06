#!/usr/bin/env python3
"""Parse raw ORFS stage logs/results into a single-design QoR markdown table.

Hard rule for this repo: every published number is extracted here from a tool
log/artifact. Nothing is hand-typed. If a metric can't be found we print 'n/a'
rather than guessing.

Sources, in priority order:
  - logs/.../6_report.log        (signoff: area, power, timing)   [if finish ran]
  - logs/.../5_*.log             (post-route timing)
  - results/.../*.sdc            (clock period via create_clock -period)
  - logs/.../5_2_TritonRoute.json (wirelength, vias)
  - reports/.../5_route_drc.rpt  (DRC violation count)
  - reports/.../synth_stat.txt   (cell count, pre-P&R area)
"""
import argparse, glob, json, os, re, sys


def last_match(files, pattern, group=1, flags=0):
    """Return the last regex capture across the given files, or None."""
    rx = re.compile(pattern, flags)
    val = None
    for f in files:
        try:
            with open(f, errors="ignore") as fh:
                for line in fh:
                    m = rx.search(line)
                    if m:
                        val = m.group(group)
        except FileNotFoundError:
            continue
    return val


def fnum(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--design", required=True)
    ap.add_argument("--platform", required=True)
    ap.add_argument("--variant", default="base")
    ap.add_argument("--log-dir", required=True)
    ap.add_argument("--results-dir", required=True)
    ap.add_argument("--reports-dir", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    logs = sorted(glob.glob(os.path.join(a.log_dir, "*.log")))
    # Prefer signoff/post-route logs for timing/area/power (last value wins).
    timing_logs = [f for f in logs if re.search(r"/(6_report|5_)", f)] or logs

    # --- clock period (ns) from the propagated-clock SDC ---
    sdcs = [os.path.join(a.results_dir, n)
            for n in ("6_final.sdc", "5_route.sdc", "4_cts.sdc", "1_synth.sdc")]
    period = fnum(last_match([p for p in sdcs if os.path.exists(p)],
                             r"create_clock.*-period\s+([0-9.]+)"))

    # Signoff STA report (`make sta`) is the preferred source for slack/area/power
    # because it uses the OpenRCX-extracted SPEF; stage logs are the fallback.
    sta_rpt = os.path.join(a.reports_dir, "signoff_sta.rpt")
    sources = [*timing_logs, sta_rpt]   # sta_rpt last => wins in last_match()

    # --- timing ---
    setup_ws = fnum(last_match([sta_rpt], r"setup worst slack:\s*(-?[0-9.eE+-]+)"))
    if setup_ws is None:
        setup_ws = fnum(last_match(timing_logs, r"worst slack\s+(-?[0-9.]+)"))
    hold_ws = fnum(last_match([sta_rpt], r"hold +worst slack:\s*(-?[0-9.eE+-]+)"))
    tns = fnum(last_match(sources, r"^tns\s+(-?[0-9.]+)", flags=re.M))
    hold_viol = last_match(timing_logs, r"hold violation count\s+(\d+)")
    setup_viol = last_match(timing_logs, r"setup violation count\s+(\d+)")

    # --- area / utilization (final "Design area X u^2 Y% utilization") ---
    area = fnum(last_match(sources, r"Design area\s+([0-9.]+)\s*u\^2"))
    util = fnum(last_match(sources, r"Design area.*?([0-9.]+)%\s*utilization"))

    # --- power: "Total  internal switching leakage total  100.0%" ---
    total_power = fnum(last_match(
        sources, r"^Total\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+"
                 r"([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+[0-9.]+%", group=4, flags=re.M))

    # --- route: wirelength + vias from DRT json ---
    wl = vias = None
    drt = os.path.join(a.log_dir, "5_2_TritonRoute.json")
    if os.path.exists(drt):
        try:
            d = json.load(open(drt))
            wl = d.get("drt::wire length::total")
            vias = d.get("drt::vias::total")
        except Exception:
            pass

    # --- DRC violations ---
    drc = last_match(timing_logs, r"Number of violations\s*=\s*(\d+)")

    # --- synth cell count / pre-PnR stats ---
    synth_stat = os.path.join(a.reports_dir, "synth_stat.txt")
    cells = last_match([synth_stat], r"^\s*(\d+)\s+[0-9.eE+]+\s+cells", flags=re.M)

    # --- derived: achievable period and Fmax from WNS ---
    fmax = ach = None
    if period is not None and setup_ws is not None:
        ach = period - setup_ws                 # min period the worst path could meet
        if ach and ach > 0:
            fmax = 1000.0 / ach                 # ns -> MHz

    def cell(v, fmt="{}"):
        return fmt.format(v) if v is not None else "n/a"

    rows = [
        ("Clock period (ns)",        cell(period, "{:.4f}")),
        ("Setup worst slack (ns)",   cell(setup_ws, "{:+.4f}")),
        ("Hold worst slack (ns)",    cell(hold_ws, "{:+.4f}")),
        ("Setup TNS (ns)",           cell(tns, "{:+.4f}")),
        ("Setup violations",         cell(setup_viol)),
        ("Hold violations",          cell(hold_viol)),
        ("Achievable period (ns)",   cell(ach, "{:.4f}")),
        ("Implied Fmax (MHz)",       cell(fmax, "{:.1f}")),
        ("Design area (um^2)",       cell(area, "{:.0f}")),
        ("Core utilization (%)",     cell(util, "{:.1f}")),
        ("Total power (W)",          cell(total_power, "{:.3e}")),
        ("Route wirelength (um)",    cell(wl)),
        ("Vias",                     cell(vias)),
        ("Route DRC violations",     cell(drc)),
        ("Synth cell count",         cell(cells)),
    ]

    lines = [
        f"# QoR — {a.platform} / {a.design} / {a.variant}",
        "",
        "_Auto-generated by `scripts/parse/parse_flow.py` from ORFS logs. Do not edit._",
        "",
        "| Metric | Value |",
        "|---|---|",
    ]
    lines += [f"| {k} | {v} |" for k, v in rows]
    lines.append("")

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w") as fh:
        fh.write("\n".join(lines))
    print(f"wrote {a.out}")
    for k, v in rows:
        print(f"  {k:24s} {v}")


if __name__ == "__main__":
    sys.exit(main())
