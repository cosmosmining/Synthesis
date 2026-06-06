# STA & CTS field notes — Ibex on sky130hd

Interview theory with **my** numbers plugged in, the night-before-onsite version.
Every number is from a report in this repo (regenerate: `scripts/gen_reports.sh`).
Baseline for the worked examples is **`base` = 17.4 ns, signed off post-route on
the OpenRCX-extracted SPEF**. The clock ladder (E1) is post-CTS.

---

## 1. Setup — and why my chip misses at 17.4 ns

```
slack_setup = T_period + skew(capture−launch) − uncertainty
              − (t_clk2q + t_comb + t_setup)
```

My worst setup path (`reports/ibex_sta_paths.md`): **`_29610_ → instr_addr_o[31]`**,
slack **−1.45 ns**. The data path is **9.33 ns of cell delay through 35 logic
levels, 0.08 ns of wire (1 %)** — this is a *logic-depth* problem, not a routing
problem (130 nm cells are slow; nets are nothing at this size).

What actually eats the 17.4 ns:
- **9.33 ns** combinational logic (35 deep),
- the launch register's **6.84 ns clock insertion** — and because the endpoint is
  an **output port** (ideal virtual clock, 0 insertion), that launch insertion is
  **not** cancelled by a matching capture insertion, so it lands straight on the
  path,
- **3.48 ns** `set_output_delay` (0.2·P) off-chip budget.

E1 makes the dependence on `T_period` literal. **Post-CTS**
(`reports/E1_clock_sweep.md`):

| Clock (ns) | 19 | 18 | 16 | 15 |
|--|--|--|--|--|
| setup WNS (ns) | +0.09 | −0.02 | −0.95 | −1.64 |

≈ **0.5 ns of slack per ns of period** — post-CTS setup crosses 0 at ~18–19 ns.
But post-CTS is **~2 ns optimistic**: at full **SPEF signoff**
(`reports/E1b_signoff_sweep.md`) the wall is **~22 ns**, where setup just closes
(WNS −0.09, a single near-critical path) → **Fmax ≈ 45 MHz**; the 17.4 ns default
fails by −1.45. The critical endpoint never leaves the **`instr_addr_o`
fetch-address family** down the whole ladder (`reports/E1_path_migration.md`) —
it doesn't migrate, it just goes more negative, so *that one datapath* is the
pipelining target.

## 2. Hold — why period can't save it, and why it waits for CTS

```
slack_hold = t_clk2q + t_comb(min) − t_hold − skew(capture−launch)
```

**No `T_period` term.** My E1 hold WNS barely moves across the ladder
(≈ −0.05 ns at 22 ns *and* at 16 ns) — exactly the textbook tell that hold is
period-independent. You cannot fix it by slowing the clock.

It's a **skew** fight, so it's meaningless until the clock is real. Pre-CTS the
clock is ideal (launch == capture, infinite hold margin). My CTS run
(`reports/ibex_cts_analysis.md`) gives the clock **4.54 ns skew** and up to
**6.84 ns insertion**; that skew drops straight into the hold budget and creates
violations — worst **−2.64 ns** post-CTS. `repair_timing -hold` (run during
routing, *after* the tree exists) pads short paths back to **−0.72 ns** at
signoff. My worst hold path is `irq_nm_i → _29915_`: a chip input into a deep-in-
the-tree capture FF whose clock arrives late — classic skew-driven hold.

## 3. Constraints I can defend
Full line-by-line in `docs/constraints.md`. One synchronous clock on `clk_i`;
the gated `clk` net is the same domain (clock-gating, **not** CDC). Deliberately
**no** async clock groups, **no** CDC false paths, **no** blanket reset
false-path (the `**async_default**` recovery/removal checks on `rst_ni` are real
and kept), **no** multicycle paths. Nothing cargo-cult.

## 4. Pre-CTS vs post-CTS (the CTS deliverable)

| | pre-CTS (ideal) | post-CTS (propagated) |
|--|--|--|
| skew | 0 | **4.54 ns** |
| insertion delay | 0 | **6.84 ns** |
| clock buffers | 0 | **126** (clk_i 54 / gated clk 72) |
| worst hold | +∞ (no skew) | −2.64 → **−0.72** after routing hold-repair |

Two clock trees (`clk_i` 996 sinks, gated `clk` 943 sinks), each 2 levels,
5–8 buffers deep. The **6.84 ns insertion / 4.54 ns skew is the headline
problem** — it both starves the output-port setup paths (§1) and creates the
hold violations (§2). A better-balanced tree (lower insertion/skew) is worth more
here than any logic tweak.

## 5. OCV / derates / CRPR — what's *actually* applied (and the catch)
sky130hd ships **no `derate.tcl`** and the flow sets **no clock uncertainty**, so
this signs off at the **single typical corner** `tt_025C_1v80` with **derate =
1.0** and **0 uncertainty**. **CRPR observed = 0.00** in my skew report (no
double-counted pessimism left on the common clock root for the reported pair).

The catch worth saying out loud: **my numbers are optimistic.** A real signoff
adds slow/fast corners, OCV/AOCV derates, and an uncertainty margin — all of
which push slack *down*. So 17.4 ns isn't just marginally failing, it's failing
*before* I've added the margins a tapeout demands.

## 6. Useful skew — where I'd spend it
Skew is currently an accident (4.54 ns) that hurts hold. As a *tool*: the
`instr_addr_o` setup paths (§1) could **borrow time** by intentionally delaying
the *capture* (here the output) or advancing the *launch* FF's clock — trading
the fat hold margin those paths have for setup. ORFS doesn't do per-endpoint
useful skew here, which is part of why these paths stay red.

## 7. Experiments → theory (my results)
- **E1 — Fmax wall** (`reports/E1_clock_sweep.md` post-CTS,
  `reports/E1b_signoff_sweep.md` signoff): wall ~18–19 ns post-CTS, **~22 ns
  (≈45 MHz) at SPEF signoff** (post-CTS ran ~2 ns optimistic). Critical path =
  instruction-fetch address, stable down the ladder → that datapath is the
  pipelining target. Hold is the *actual* blocker: −0.5…−0.8 ns at every clock
  (skew-bound, §2), so the design is setup-closable but not hold-clean without
  CTS rebalancing.
- **E2 — pipelining** (`reports/E2_pipelining.md`): `WritebackStage` 0→1 (2→3
  stage). Fmax is **flat (52.9 → 52.8 MHz)** — the bottleneck is the fetch-address
  path (§1), which the writeback stage doesn't touch, so pipelining the *wrong*
  stage buys no speed. But it cut **area −7 % (200k → 187k µm²)** and **power
  −13 % (20.6 → 18.0 mW)**: the shorter writeback / load-use paths need far less
  timing-closure buffering, which outweighs the added pipeline registers. Cost:
  **+1 cycle load-use latency** (a CPI hit PPA doesn't show). The lesson I'd give
  at the whiteboard: *pipelining only raises Fmax when it shortens the actual
  critical path* — measure first, then cut.
- **E3 — utilization** (`reports/E3_util_sweep.md`): 20 %→40 % keeps Fmax flat
  (logic-bound) while peak global-route usage climbs 29 %→55 %; **60 % is
  placement-infeasible** (RePlAce GPL-0302, needs 76 % density). Density buys
  area at the cost of congestion, until it costs you routability.
