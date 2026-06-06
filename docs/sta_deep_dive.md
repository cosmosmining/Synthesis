# STA deep-dive — Ibex / sky130hd, post-route signoff (extracted SPEF)

Signed off on the **base** config (17.4 ns clock — the ORFS default, which turns
out to sit *past* this stack's Fmax edge, so there are real violations to
explain). Parasitics are OpenRCX-extracted SPEF. The path table is generated:
[`reports/ibex_sta_paths.md`](../reports/ibex_sta_paths.md); full expanded paths
are in the signoff report (`make sta`). Numbers below are pulled from there.

## Headline
- **Setup** worst slack **−1.45 ns**, **hold** worst slack **−0.72 ns**, TNS −88.6 ns.
- So 17.4 ns (57 MHz) is **not** met at signoff — see E1 for where it closes.

## Top-5 setup paths — all `_29610_ → instr_addr_o[*]`
Every worst setup path launches from the same register `_29610_` (instruction-
fetch address datapath) and ends at the **`instr_addr_o`** output bus, **~31–35
levels of logic deep**.

| | worst path |
|---|---|
| start → end | `_29610_` → `instr_addr_o[31]` |
| slack | −1.45 ns |
| logic (cell) delay | **9.33 ns** |
| wire delay | **0.08 ns (1 %)** |
| logic depth | 35 stages |

**Read it:** this is a **logic-depth–bound** path, not a wire problem — at 130 nm
on a small block, cell delay dominates and interconnect is ~1 %. Three things
stack up against it: (1) ~9.3 ns through 35 gates, (2) a **6.84 ns launch clock
insertion** (from the CTS tree) that is *not* cancelled at the output port (the
port sees an ideal virtual clock, so launch insertion hits setup directly), and
(3) the 3.48 ns `set_output_delay` (0.2·P) off-chip budget.

**What fixes each:**
- **Relax the clock** — the direct lever; E1 shows the wall and where slack goes
  positive.
- **Cut logic depth** — 35 levels to an output is deep; pipelining/retiming the
  fetch-address path is the architectural fix. E2 flips Ibex's `WritebackStage`
  (2→3 stage) to quantify the PPA cost/benefit of adding a register stage.
- **Rebalance the clock tree** — 6.84 ns insertion is excessive for a 2-level
  tree; reducing it (better CTS) directly recovers these output-port setup paths.

## Top-5 hold paths — chip inputs → nearby FFs
Worst hold launches from input ports (`irq_nm_i`, `boot_addr_i[*]`,
`instr_rdata_i[*]`) into close-by capture registers, slacks −0.63 → **−0.72 ns**,
~0 ns wire.

**Read it:** hold is a **clock-skew** problem, not a logic problem. The capture
FFs sit deep in the clock tree (insertion up to 6.84 ns) while the input launch
is referenced to an ideal source — so the capture edge arrives *late* and the
fast input data violates hold (`slack_hold = t_clk2q + t_comb − t_hold − skew`,
and skew here is **4.54 ns**). It cannot be fixed by changing the clock period
(no period term in the hold equation).

**What fixes each:** `repair_timing -hold` inserts delay cells on these short
paths — it already pulled worst hold from **−2.64 ns** (post-CTS) to **−0.72 ns**
(signoff). It doesn't fully close here because the **4.54 ns skew** from the
unbalanced tree is too large; the real fix is a better-balanced clock tree (lower
insertion/skew) — or, where a specific launch/capture pair allows it, deliberate
**useful skew**. See [`reports/ibex_cts_analysis.md`](../reports/ibex_cts_analysis.md).

## Methodology note (so the experiment numbers are honest)
The E1 clock ladder is reported **post-CTS with placement-estimated parasitics**
(fast, lets us sweep). That runs **optimistic** versus SPEF signoff — and I
measured the gap: `clk22` is **+1.89 ns** post-CTS but **−0.087 ns** at full
SPEF signoff (`reports/E1b_signoff_sweep.md`), a **~2 ns** pessimism swing. So
**use the E1 ladder for the *shape* (wall, path migration); use the E1b SPEF
sweep for the *absolute* truth**: the real setup wall is **~22 ns (≈45 MHz)**,
not the ~18 ns the post-CTS sweep suggests. And hold (§ above) stays −0.5…−0.8 ns
at every clock — setup-closable, hold-limited by the clock tree.
