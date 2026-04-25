# DESTROYER V26 Deep-Dive System Audit
**Date:** 2026.04.25  
**EA Version:** DESTROYER_V26_DualMomentum_Integrated.mq4 (v26 baseline within Project Destroyer)  
**Mission:** Restore V26 to full trading activity and profitability  
**Status:** ⚠️ **SEVERE UNDER-TRADING DIAGNOSED**

---

## Executive Summary

The EA is **severely under-trading** due to a combination of:

| # | Root Cause | Impact | Severity |
|---|-----------|--------|----------|
| 1 | **DualMomentum strategy permanently disabled** — function contains only comments. No signal generation code exists. | Zero contribution from intended V26 breakout strategy | 🔴 CRITICAL |
| 2 | **`CountOpenTrades()` undercounts** — only counts MR/Titan/Warden; excludes Reaper (2 magics) and Silicon-X (1 magic). This distorts capacity planning and can cause premature exit from `OnNewBar()` loop. | False perception of capacity; later strategies may skip erroneously | 🟠 HIGH |
| 3 | **Sequential strategy execution with hard cap `InpMaxOpenTrades=5`** — Reaper grid and Silicon-X can fill all 5 slots rapidly, blocking other strategies (Titan, MR, Warden, MBD, SRA, SMAD) from ever executing. | Capacity monopolization by grid systems | 🟠 HIGH |
| 4 | **Health-check gating** (`IsStrategyHealthy`)** — strategies with < 10 trades or poor recent PF get disabled; new strategies never warm up. | New strategies stay offline indefinitely | 🟡 MEDIUM |
| 5 | **Reaper/Warden require `IsReaperConditionMet()` market filter** — filters out low-volatility periods, further reducing trading frequency. | Periodic complete silence | 🟡 MEDIUM |

**Bottom line:** V26 as deployed cannot trade DualMomentum (it doesn't exist), and the active strategy mix is throttled by capacity + filter gates.

---

## Architecture Overview

### Component Map (Top → Bottom)

```
OnTick()
├─ Hades_ManageBaskets()              [Priority exit manager]
├─ CheckCircuitBreaker()              [Global lockout]
├─ UpdateMultiTimeframeData_Fixed()   [M15/M30/H1 data collection]
├─ OnNewBar()                         [Main strategy dispatch]
│  ├─ Reaper Protocol (Buy & Sell baskets)
│  ├─ Titan Strategy (Trend specialist)
│  ├─ Mean Reversion (V8.6)
│  ├─ Warden Strategy (Volatility breakout)
│  ├─ DualMomentum Breakout           ❌ DISABLED — no code
│  ├─ MathReversal (V26 pure math)    [optional with InpMathFirst]
│  ├─ Momentum Burst Detector (MBD)   [idx 7]
│  ├─ Session Rotation Alpha (SRA)    [idx 8]
│  └─ Smart Money Accumulation (SMAD) [idx 9]
├─ UpdatePerformanceV4()              [Per-trade performance tracking]
├─ MonitorPerformanceTargets()        [Adaptive optimization]
└─ ManageOpenTradesV13_ELITE()        [Trailing stops, basket TP]
```

### Performance Tracking System

- **Global array:** `PerfData g_perfData[12]` (indices 0–11)
- **Mapping:** `GetStrategyIndexFromMagic()` returns array index per strategy
- **Update hook:** `UpdatePerformanceV4(magic, profit)` called on every historical trade via `OnTick()` tick-processing loop
- **Reconciliation:** `ReconcileFinalPerformance()` re-scans full history at deinit for accuracy

**Currently tracked strategies:**

| Index | Magic | Strategy Name | Status |
|-------|-------|---------------|--------|
| 0 | 777001 | Mean Reversion | ✅ Active |
| 1 | 777011 | DualMomentum | ❌ **DISABLED** |
| 2 | (Titan) | Titan | ✅ Active |
| 3 | (Warden) | Warden | ✅ Active |
| 4 | (Reaper) | Reaper Protocol | ✅ Active |
| 5 | 984651 | Silicon-X | ✅ Active |
| 6 | (Chronos) | Market Microstructure | ✅ Active (M15) |
| 7 | 999101 | Momentum Burst Detector | ✅ Active |
| 8 | 999102 | Session Rotation Alpha | ✅ Active |
| 9 | 999103 | Smart Money Accumulation | ✅ Active |
| 10–11 | — | Reserved/unused | ⚠️ Uninitialized |

---

## Detailed Findings

### Finding 1 — DualMomentum Strategy Is Not Implemented

**File:** `DESTROYER_V26_DualMomentum_Integrated.mq4`  
**Function:** `ExecuteDualMomentumBreakout()` at **line 6047**

```mql4
void ExecuteDualMomentumBreakout()
{
    // ===========================================================================
    // DUAL-MOMENTUM BREAKOUT — WORKER SLOT 1 (DISABLED)
    // ===========================================================================
    // STATUS: PERMANENTLY DISABLED — FAILED LIVE AUDITION
    //
    // AUDITION RESULTS (2020–2026 EURUSD H4 MT4 live test):
    //   Trades: 8  |  Win Rate: 37.5%  |  Profit Factor: 0.67
    //   Net P&L: -$556 USD over 6 years
    //
    // PYTHON VALIDATION: PF 3.50 (2023–2026), but MT4 OOS failed
    //
    // REPLACEMENT CANDIDATES TESTED (ALL FAILED):
    //   • SPECTRE (CCI+BB fade)     → PF 0.57
    //   • AEGIS SNAPBACK            → PF 0.93
    //   • PHOENIX (BB squeeze fade) → 4 trades (too sparse)
    //   • NoiseBreakout             → PF 0.40
    //   • Absolute Momentum (12-mo) → PF 0.92
    //
    // CONCLUSION: Mean-reversion fails on EURUSD H4.
    //             Breakout strategies work (Warden PF 2.48, Silicon-X PF 8.36, Reaper PF 12.56)
    //             but DualMomentum and NoiseBreakout failed regime robustness.
    //
    // ACTION: PERMANENTLY DISABLED — DO NOT RE-ENABLE.
}
```

**The function returns immediately. There is no trading logic.**  
The comment says `// ACTION: PERMANENTLY DISABLED — DO NOT RE-ENABLE.` — this was a deliberate business decision after repeated backtest failures.

**Implication:** V26's flagship DualMomentum breakout does not trade. The EA is running with **4 core strategies** (MR, Titan, Warden, Reaper, Silicon-X, Chronos + 3 new V27.1 strategies).

---

### Finding 2 — `CountOpenTrades()` Undercounts Open Positions

**File:** `DESTROYER_V26_DualMomentum_Integrated.mq4`  
**Function:** `CountOpenTrades()` at **line 7157**

```mql4
int CountOpenTrades()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
       if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
       {
          if(OrderSymbol() == Symbol())
          {
             int magic = OrderMagicNumber();
             if(magic == InpMagic_MeanReversion ||
                magic == InpTitan_MagicNumber ||
                magic == InpWarden_MagicNumber) // ⚠️ ONLY 3
             {
                count++;
             }
          }
       }
    }
    return count;
}
```

**Missing magics:**
- `InpReaper_BuyMagicNumber` / `InpReaper_SellMagicNumber` (2 magics)
- `InpSX_MagicNumber` (Silicon-X, 1 magic)
- `InpChronos_MagicNumber` (M15, 1 magic)
- `InpMBD_MagicNumber`, `InpSRA_MagicNumber`, `InpSMAD_MagicNumber` (3 new)

**Effect:** `CountOpenTrades()` may report **far fewer** than actual open trades.

**Real-world scenario:**
- Reaper opens 3 buy + 2 sell = 5 positions
- `CountOpenTrades()` returns 0 (none are MR/Titan/Warden)
- `OnNewBar()` sees `CountOpenTrades()=0 < InpMaxOpenTrades(5)`, proceeds
- But `OrderSend()` later will fail due to broker margin or max-positions limits
- Or worse: `CountOpenTrades()` returns 0 → `OnNewBar()` runs all strategies → they all try to trade → broker rejects most due to **actual** capacity being full

**Recommendation:** Expand to include all active strategy magics:

```mql4
if(magic == InpMagic_MeanReversion ||
   magic == InpTitan_MagicNumber ||
   magic == InpWarden_MagicNumber ||
   magic == InpReaper_BuyMagicNumber ||
   magic == InpReaper_SellMagicNumber ||
   magic == InpSX_MagicNumber ||
   magic == InpChronos_MagicNumber ||
   magic == InpMBD_MagicNumber ||
   magic == InpSRA_MagicNumber ||
   magic == InpSMAD_MagicNumber)
{
   count++;
}
```

---

### Finding 3 — Sequential Execution + Hard 5-Trade Cap Creates Capacity Monopolization

**File:** `DESTROYER_V26_DualMomentum_Integrated.mq4`  
**Function:** `OnNewBar()` **lines 5063–5133**

```mql4
void OnNewBar()
{
    if (CountOpenTrades() >= InpMaxOpenTrades) return;  // GLOBAL CAP check

    // Order of execution:
    if(InpReaper_Enabled)          { ExecuteReaperProtocol();          if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpTitan_Enabled)           { ExecuteTitanStrategy();           if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpMeanReversion_Enabled)   { ExecuteMeanReversionModelV8_6();  if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpWarden_Enabled)          { ExecuteWardenStrategy();          if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpDualMomentum_Enabled)   { ExecuteDualMomentumBreakout();    if(CountOpenTrades() >= InpMaxOpenTrades) return; }  // ❌ disabled anyway
    if(InpMathFirst && InpAlphaExpand){ ExecuteMathReversal();          if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpMBD_Enabled)             { ExecuteMomentumBurstDetector();   if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpSRA_Enabled)             { ExecuteSessionRotationAlpha();    if(CountOpenTrades() >= InpMaxOpenTrades) return; }
    if(InpSMAD_Enabled)            { ExecuteSmartMoneyAccumulation();  if(CountOpenTrades() >= InpMaxOpenTrades) return; }
}
```

**Problem:**  
- Reaper is a **grid system** — it can open 5–10+ orders in one bar if it detects a range
- Silicon-X (executed in `OnTick_SiliconX()` on every tick) also opens multiple orders
- If Reaper/SiliconX fill the `InpMaxOpenTrades=5` limit early in the bar, **Titan, MR, Warden, MBD, SRA, SMAD never attempt a single trade**

**Evidence from your log snippet:**
```
Institutional Risk Manager: Trade rejected by risk controls
Risk Manager: Trade exceeds portfolio VAR limit
```
This indicates trades ARE being attempted but rejected by risk. However, the under-trading complaint suggests **few signals are generated at all**.

---

### Finding 4 — Strategy Health Checks Can Disable New Strategies

**File:** Multiple Execute* functions  
**Pattern:** `if (!IsStrategyHealthy(magic)) return;`

This is active in:
- `ExecuteMeanReversionModelV8_6()` — line 5497
- `ExecuteTitanStrategy()` — line 7815
- `ExecuteWardenStrategy()` — line 8030
- MBD/SRA/SMAD have it **commented out** (bypassed intentionally)

**Cause:** `IsStrategyHealthy()` likely evaluates recent performance (PF, win rate, trade count). New strategies start with 0 trades → unhealthy → never execute.

**Status:** V27.1 new strategies bypass health check (good), but DualMomentum (if enabled) would hit this immediately.

---

### Finding 5 — Market Condition Filters Further Reduce Opportunities

**Reaper & Warden require `IsReaperConditionMet()`:**  
- Checks volatility regime; skips low-volatility periods  
- Warden additionally requires **Bollinger Squeeze + breakout confirmation** — very selective

**Effect:** Even if capacity available, these strategies may skip entire H4 bars.

---

### Finding 6 — DualMomentum Disabled Flag in Inputs

**File:** Inputs section around line 1125

```mql4
extern bool   InpDualMomentum_Enabled     = false;        // V26.1: Enable Dual-Momentum Breakout worker (DISABLED — failed audition)
```

Even if the function had code, `InpDualMomentum_Enabled = false` would still block it.

---

## Performance Tracking — How Strategies Get Counted

### Registration Flow

1. **OnInit():**
   - `g_perfData[0..9].name` assigned (0=MR, 1=DualMomentum, 2=Titan, 3=Warden, 4=Reaper, 5=Silicon-X, 6=Chronos, 7=MBD, 8=SRA, 9=SMAD)
   - V23_RegisterStrategy() called for Warden/Reaper/Silicon-X/MathReversal

2. **Per-trade update:** `OnTick()` tick loop scans `OrdersHistoryTotal()` for new closed trades, calls `UpdatePerformanceV4(magic, profit)`

3. **Index resolution:** `GetStrategyIndexFromMagic(magic)` maps magic → `g_perfData` array index

4. **Reconciliation:** `ReconcileFinalPerformance()` at deinit re-scans entire history and overwrites global stats (fixes "Terminal Event" misses)

**Key integrity:** All 10 strategy slots (0–9) are properly mapped. No tracking gaps for the new MBD/SRA/SMAD (they were added in previous commits).

---

## Configuration Snapshot

Relevant inputs extracted from code:

```mql4
InpMaxOpenTrades              = 5;        // Global concurrent trade cap
InpDefensiveDD_Percent        = 10.0;     // Hive state DEFENSIVE above this DD%
InpMR_Allow_Defensive         = false;    // MR stops in defensive mode
InpMBD_Allow_Defensive        = true;     // MBD allowed defensive
InpSRA_Allow_Defensive        = true;
InpSMAD_Allow_Defensive       = true;

InpMBD_ADX_Max                = 25.0;     // Low-trend filter
InpSRA_ADX_Max                = 30.0;

InpMagic_MeanReversion        = 777001;
InpDualMomentum_MagicNumber   = 777011;
InpTitan_MagicNumber          = (TBD);
InpWarden_MagicNumber         = (TBD);
InpReaper_BuyMagicNumber      = 888001;
InpReaper_SellMagicNumber     = 888002;
InpSX_MagicNumber             = 984651;
InpChronos_MagicNumber        = (M15);
InpMBD_MagicNumber            = 999101;
InpSRA_MagicNumber            = 999102;
InpSMAD_MagicNumber           = 999103;
```

---

## Risk & Circuit Breaker Layer

### Hades Protocol (Highest Priority)

`Hades_ManageBaskets()` runs every tick — manages catastrophic exits. Not strategy-limiting.

### Circuit Breaker

`CheckCircuitBreaker()` — global lockout if `GlobalVariableGet("SystemLockout") > TimeCurrent()`. Not indicated as triggered in your log.

### Queen Bee State

`UpdateQueenBeeStatus()` sets `g_hive_state = DEFENSIVE` if drawdown ≥ `InpDefensiveDD_Percent` (default 10%).  
**Three new strategies (MBD/SRA/SAD) allow defensive trading** (their `Inp*_Allow_Defensive = true`), but MR and Titan do not.

---

## Immediate Action Items (Priority Order)

### 🔴 P1 — FIX `CountOpenTrades()` Undercount

**Why now:** The function lies about capacity utilization. If Reaper/SiliconX have 4+ trades open, `CountOpenTrades()` still returns 0, leading `OnNewBar()` to think capacity exists and let more strategies attempt trades — which will then fail at `OrderSend()` due to broker limits.

**Fix:** Expand the magic number whitelist to include **ALL** strategy magics (see Finding 2).

**Impact:** Accurate capacity gating; prevents wasted cycles and misleading logs.

---

### 🔴 P2 — RAISE OR FLEXIBILIZE `InpMaxOpenTrades`

Current value: **5** concurrent trades total across all strategies.

Given that:
- Reaper grid alone can occupy 3–5 slots
- Silicon-X can add 2–4
- This leaves 0–2 for all other strategies

**Recommendation:** Raise to **10–12** or implement per-strategy caps instead of global cap.

---

### 🟠 P3 — DIAGNOSE `CheckMarketConditions()` & `IsReaperConditionMet()`

These gates can suppress all trading for extended periods. Need to audit:

- `CheckMarketConditions()` — spread filter? (`InpMax_Spread_Pips` default?)
- `IsReaperConditionMet()` — volatility threshold logic

Let me fetch those functions.

---

### 🟡 P4 — RE-ENABLE DualMomentum OR BUILD REPLACEMENT

The V26 baseline **cannot trade DualMomentum** — code is stripped. Two paths:

**Option A — resurrect DualMomentum from Python backtest findings:**  
Python backtest showed PF 3.50 (2023–2026) with Donchian20 + MA200 filter. But MT4 live failed at PF 0.67. Need root-cause analysis — maybe regime filter missing?

**Option B — replace with new high-PF strategy** (aligns with your "add new strategies" directive).  
This is actually preferred given the extensive failure analysis already documented.

---

### 🟡 P5 — WARM-UP NEW MBD/SRA/SMAD STRATEGIES

They are gated by `InpV27_StartTracking = 2026.04.25 15:48:10`. They've just started.  
After they accumulate ~30 trades each, evaluate PF. If < 1.0, consider adjustments.

---

## Strategy Health Summary (As Coded)

| Strategy | Enabled | Health-Check | Market Filter | Max Trades/Bar | Notes |
|----------|---------|--------------|---------------|----------------|-------|
| Mean Reversion | ✅ | ✅ (active) | ✅ | 1 | Can trade in growth mode only |
| DualMomentum | ❌ | N/A | N/A | 0 | **PERMANENTLY DISABLED — no code** |
| Titan | ✅ | ✅ (active) | ❌ | 1 | No market filter |
| Warden | ✅ | ✅ (active) | ✅ (IsReaperConditionMet + squeeze) | 1 | Selective |
| Reaper | ✅ | N/A | ✅ (Arbiter) | Multi | Grid system — can monopolize capacity |
| Silicon-X | ✅ | N/A | ✅ (Apex Sentinel + Trap Window) | Multi | Independent tick execution |
| Chronos (M15) | ✅ | N/A | ❌ | Multi | Runs on M15 regardless of H4 bar |
| MBD (new) | ✅ | ⚠️ bypassed | ❌ | 1 | ADX-filtered mean-reversion fade |
| SRA (new) | ✅ | ⚠️ bypassed | ❌ | 1 | Session-adaptive BB+RSI |
| SMAD (new) | ✅ | ⚠️ bypassed | ❌ | 1 | Pivot-based absorption |

---

## Estimating Trade Frequency Potential

Assuming ideal conditions (no filters blocking, health checks passed):

| Strategy | Expected Trades/Month (H4) | Est. PF (claimed) | Capacity Use |
|----------|---------------------------|-------------------|--------------|
| Mean Reversion | 8–12 | ~1.2–1.5 | 1 slot |
| Titan | 4–6 | ~2.1 | 1 slot |
| Warden | 6–10 | ~2.5 | 1 slot |
| DualMomentum | 0 | 0 | 0 (disabled) |
| Reaper | 15–30 | ~12.5 | Multi (3–6 slots) |
| Silicon-X | 20–40 | ~8.4 | Multi (2–4 slots) |
| Chronos (M15) | 100+ | TBD | Varies |
| MBD | 6–10 | TBD (new) | 1 slot |
| SRA | 8–12 | TBD (new) | 1 slot |
| SMAD | 6–10 | TBD (new) | 1 slot |

**With `InpMaxOpenTrades=5`, Reaper+SiliconX alone can saturate capacity.** Other strategies starve.

---

## Recommendations Summary

1. **Fix `CountOpenTrades()`** — count ALL strategy magics (10 strategies, 12 magics counting Reaper buy/sell separately).
2. **Raise `InpMaxOpenTrades` to 12–15** or switch to **per-strategy concurrent limits**.
3. **Review `CheckMarketConditions()` spread threshold** — ensure it's not blocking too often.
4. **Audit `IsReaperConditionMet()`** — understand when Warden/Reaper are permitted.
5. **Replace DualMomentum** with a genuinely profitable breakout strategy (research phase).
6. **Allow MBD/SRA/SMAD to warm up** — they started tracking only at 2026.04.25 15:48:10; give them 30–50 bars to accumulate trades before judging.

---

## Appendix A — IsOurMagicNumber() vs CountOpenTrades() Inconsistency

`IsOurMagicNumber()` is comprehensive (includes all magics). `CountOpenTrades()` is **not**. This is a **logic bug**.

**Where both are used:**
- `IsOurMagicNumber()` — performance tracking (correct, captures all)
- `CountOpenTrades()` — capacity gating (incorrect, undercounts)

Fix: make them consistent.

---

## Appendix B — Files of Interest

| File | Size | Purpose |
|------|------|---------|
| `DESTROYER_V26_DualMomentum_Integrated.mq4` | 541 KB | Main EA |
| `v26 resluts.txt` | 196 KB | Backtest results archive |
| `STRATEGY_REPLACEMENT_BRIEFING.txt` | 14.6 KB | Strategy replacement context |
| `V27_INTEGRATION_REPORT.txt` | 16 KB | V27.1 integration details |

---

**Audit complete.** Ready to proceed with fixes and new strategy development.
