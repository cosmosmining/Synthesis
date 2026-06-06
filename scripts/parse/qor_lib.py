#!/usr/bin/env python3
"""Shared QoR extraction: raw ORFS logs/artifacts -> a dict of metrics.

Single source of truth for `parse_flow.py` (one run) and
`parse_experiment.py` (many variants). Every value is pulled from a tool
log/artifact; missing metrics come back as None, never guessed.
"""
import glob, json, os, re


def last_match(files, pattern, group=1, flags=0):
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


def extract(log_dir, results_dir, reports_dir):
    """Return a dict of QoR metrics for one ORFS run."""
    logs = sorted(glob.glob(os.path.join(log_dir, "*.log")))
    timing_logs = [f for f in logs if re.search(r"/(6_report|5_)", f)] or logs
    sta_rpt = os.path.join(reports_dir, "signoff_sta.rpt")
    sources = [*timing_logs, sta_rpt]          # sta_rpt last => wins in last_match

    m = {}

    # clock period from the propagated-clock SDC
    sdcs = [os.path.join(results_dir, n)
            for n in ("6_final.sdc", "5_route.sdc", "4_cts.sdc", "1_synth.sdc")]
    m["period"] = fnum(last_match([p for p in sdcs if os.path.exists(p)],
                                  r"create_clock.*-period\s+([0-9.]+)"))

    # timing — prefer SPEF-based signoff report, fall back to route-stage logs
    m["setup_ws"] = fnum(last_match([sta_rpt], r"setup worst slack:\s*(-?[0-9.eE+-]+)"))
    if m["setup_ws"] is None:
        m["setup_ws"] = fnum(last_match(timing_logs, r"worst slack\s+(-?[0-9.]+)"))
    m["hold_ws"] = fnum(last_match([sta_rpt], r"hold +worst slack:\s*(-?[0-9.eE+-]+)"))
    m["tns"] = fnum(last_match(sources, r"^tns\s+(-?[0-9.]+)", flags=re.M))
    m["setup_viol"] = last_match(timing_logs, r"setup violation count\s+(\d+)")
    m["hold_viol"] = last_match(timing_logs, r"hold violation count\s+(\d+)")

    # area / utilization
    m["area"] = fnum(last_match(sources, r"Design area\s+([0-9.]+)\s*u\^2"))
    m["util"] = fnum(last_match(sources, r"Design area.*?([0-9.]+)%\s*utilization"))

    # power (W) — total column of the "Total ... 100.0%" line
    m["power"] = fnum(last_match(
        sources, r"^Total\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+"
                 r"([0-9.eE+-]+)\s+([0-9.eE+-]+)\s+[0-9.]+%", group=4, flags=re.M))

    # route wirelength + vias (DRT metrics json)
    m["wirelength"] = m["vias"] = None
    drt = os.path.join(log_dir, "5_2_TritonRoute.json")
    if os.path.exists(drt):
        try:
            d = json.load(open(drt))
            m["wirelength"] = d.get("drt::wire length::total")
            m["vias"] = d.get("drt::vias::total")
        except Exception:
            pass

    # global-route congestion (E3) from FastRoute's final report
    m["overflow"] = m["peak_usage"] = m["gr_wl"] = None
    fr = os.path.join(log_dir, "5_1_fastroute.log")
    if os.path.exists(fr):
        t = open(fr, errors="ignore").read()
        mt = re.search(r"^Total\s+\d+\s+\d+\s+([\d.]+)%\s+\d+\s*/\s*\d+\s*/\s*(\d+)", t, re.M)
        if mt:
            m["peak_usage"] = float(mt.group(1)); m["overflow"] = int(mt.group(2))
        wl = re.search(r"Total wirelength:\s+(\d+)\s*um", t)
        if wl:
            m["gr_wl"] = int(wl.group(1))

    m["drc"] = last_match(timing_logs, r"Number of violations\s*=\s*(\d+)")
    m["cells"] = last_match([os.path.join(reports_dir, "synth_stat.txt")],
                            r"^\s*(\d+)\s+[0-9.eE+]+\s+cells", flags=re.M)

    # CTS: clock buffers in the post-CTS netlist, and skew/insertion if logged
    cts_v = os.path.join(results_dir, "4_cts.v")
    if os.path.exists(cts_v):
        try:
            txt = open(cts_v, errors="ignore").read()
            m["clk_buffers"] = len(re.findall(r"\bclkbuf_\w+\b", txt))
        except Exception:
            m["clk_buffers"] = None

    # Completeness guard: a run that never reached CTS (e.g. placement failed on
    # a too-dense floorplan) has only meaningless pre-placement "worst slack".
    # Null its timing so it shows n/a rather than a misleading number.
    reached_cts = (os.path.exists(os.path.join(results_dir, "4_cts.def")) or
                   os.path.exists(os.path.join(results_dir, "5_route.def")))
    m["incomplete"] = not reached_cts
    if not reached_cts:
        for k in ("setup_ws", "hold_ws", "tns"):
            m[k] = None

    # derived: min period the worst path could meet, and implied Fmax
    m["achievable"] = m["fmax"] = None
    if m["period"] is not None and m["setup_ws"] is not None:
        m["achievable"] = m["period"] - m["setup_ws"]
        if m["achievable"] and m["achievable"] > 0:
            m["fmax"] = 1000.0 / m["achievable"]
    return m


def fmt(v, spec="{}"):
    return spec.format(v) if v is not None else "n/a"
