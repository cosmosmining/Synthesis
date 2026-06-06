# STA & CTS field notes

Interview theory with **my** numbers plugged in. Written to teach a peer the
night before an on-site. Sections fill in as stages 2–4 land; right now the
worked example is the `gcd` smoke (sky130hd, clock 4.3647 ns, signoff via
OpenRCX SPEF).

---

## 1. The setup inequality (and where my numbers go)

A launch→capture FF pair passes setup when the data arrives before the capture
edge needs it:

```
t_clk2q + t_comb + t_setup  ≤  T_period + t_skew(capture−launch) − t_uncertainty
slack_setup = T_period + t_skew − t_uncertainty − (t_clk2q + t_comb + t_setup)
```

- **Tighten `T_period`** (the E1 sweep) and slack falls 1:1 until the worst path
  goes negative — that's Fmax.
- **Positive skew** (capture clock later than launch) *adds* to the setup budget
  — this is why "useful skew" can buy timing (§5).

`gcd` example: `T_period = 4.3647 ns`, signoff worst setup slack `+0.4054 ns`
→ the worst register path actually consumes `4.3647 − 0.4054 = 3.9593 ns`, i.e.
this block could run at ~**252.6 MHz** before the first path fails. _(Ibex
top-5 setup paths with the delay split land here in stage 2.)_

## 2. The hold inequality (why CTS comes first)

```
t_clk2q + t_comb(min)  ≥  t_hold + t_skew(capture−launch)
slack_hold = t_clk2q + t_comb(min) − t_hold − t_skew
```

Hold has **no `T_period` term** — you cannot fix a hold violation by slowing the
clock. It's a race against clock **skew**, so it can only be analyzed honestly
once the clock tree is real (post-CTS) — see §4. `gcd` signoff hold worst slack:
`+0.5328 ns`. _(Where the worst hold path lands on Ibex — and why — in stage 2.)_

## 3. Constraints I can defend

_The Ibex SDC (clock defs, async groups, any false/multicycle paths) is built
and justified line-by-line in stage 2. No cargo-cult constraints._

## 4. Pre-CTS vs post-CTS (skew, insertion delay, hold repair)

_Stage 3: ideal-clock vs propagated-clock numbers, buffer count added, hold
violations CTS *creates* and how `repair_timing` fixes them, plus the extracted
clock-tree topology for one domain._

## 5. Useful skew, OCV/derates, CRPR

_Stage 3–5: the derates/OCV ORFS applied (from the logs), CRPR/CPPR on a real
reconvergent path, and a path where intentional skew would help._

## 6. Experiments → theory

- **E1 clock sweep / Fmax wall** — _stage 4_
- **E2 pipelining PPA delta** — _stage 4_
- **E3 utilization vs congestion/timing** — _stage 4_
- **E4 CDC FIFO depth (if axi-qos-fabric)** — N/A (using Ibex)
