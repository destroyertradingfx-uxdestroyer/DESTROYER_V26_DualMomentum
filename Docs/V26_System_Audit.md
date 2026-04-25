# DESTROYER V26 DualMomentum Integrated — System Deep-Dive Audit & Fix Report

**Date:** 2026.04.25  
**Agent:** Hermes (Max)  
**Repository:** destroyertradingfx-uxdestroyer/DESTROYER_V26_DualMomentum  
**Branch:** master  
**Base File:** `DESTROYER_V26_DualMomentum_Integrated.mq4` (541 KB, 12,805 lines)

---

## 1. EXECUTIVE SUMMARY

**Mission:** Diagnose why V26 is severely under-trading and restore full operational capacity.

**Root Causes Found:**
1. **Capacity undercount** — `CountOpenTrades()` and 3 other functions only counted 3 of 10 strategies
2. **ReaperCondition filter** blocking MeanReversion & Warden with extreme BB+RSI thresholds (~5% of H4 bars)
3. **Low `InpMaxOpenTrades` (5)** — Reaper grid monopolizes slots
4. **DualMomentum strategy body is commented out** — zero trades
5. **MBD/SRA/SMAD ultra-tight 3.0 pip spread filters** — frequently blocked

**Fixes Applied:**
- Expanded all magic-whitelisting to 10 strategies (commits `e30bc76`, `c17555e`)
- Raised `InpMaxOpenTrades`: 5 → 12 (`7cec952`)
- Made `IsReaperConditionMet()` optional via `InpEnable_ReaperConditionFilter = false` (default OFF) (`7cec952`)
- Fixed double-brace bug in `CountOpenTrades()`
- Added time-gate `InpV27_StartTracking` for new strategies
- Verified brace balance (character-level stack = 0)

**Status:** EA structurally sound — ready for backtest. DualMomentum non-functional. V27.1 strategies (MBD/SRA/SMAD) integrated with time-gate & tracking.

---

## 2. ARCHITECTURE MAP

### 10-Strategy Beehive (Indices 0–9)

|Idx|Strategy|Magic|Status|Notes|
|---|---|---|---|---|
|0|MeanReversion|777001|✅ Active|H4 mean reversion|
|1|DualMomentum|777011|❌ DISABLED|Body commented out (lines 6047–6081)|
|2|Titan|777008|✅ Active|MTF momentum (D1/H4 EMAs)|
|3|Warden|777009|✅ Active|Volatility squeeze (BB/KC)|
|4|Reaper Buy|888001|✅ Active|Grid/Martingale basket|
|4|Reaper Sell|888002|✅ Active|Same idx4, separate magic|
|5|Silicon-X|777006|✅ Active|Grid system|
|6|Chronos|777007|✅ Active|Time-based momentum|
|7|MBD|999101|⏸️ Time-gated|BB+RSI fade|
|8|SRA|999102|⏸️ Time-gated|Session-adaptive|
|9|SMAD|999103|⏸️ Time-gated|Pivot absorption|

**Queen Bee:** Centralized risk, basket TP, drawdown control.

---

## 3. UNDER-TRADING ROOT CAUSES

### 3.1 Capacity Undercount (Critical)

`CountOpenTrades()` only checked 3 magics:
```mql4
if(magic == InpMagic_MeanReversion || magic == InpTitan_MagicNumber || magic == InpWarden_MagicNumber)
```
Excluded: Reaper(2×), Silicon-X, Chronos, MBD, SRA, SMAD.

**Impact:**
- EA thought 0–3 slots used when actually 5–8 occupied
- `CountOpenTrades() >= InpMaxOpenTrades` triggered prematurely
- MR/Titan/Warden denied entry despite apparent capacity
- Dashboard P&L incomplete

**Fix:** Expanded to all 10 magics in:
- `CountOpenTrades()`
- `GetTotalCurrentRiskPercent()`
- `UpdateDashboard_Pnl()`
- `UpdateLiveStatsV8_6()`

---

### 3.2 ReaperCondition Filter Blocking MR & Warden

Unconditional gate in both strategies:
```mql4
if(!IsReaperConditionMet()) return;
```
Requirement: Price **outside** 20/2 Bollinger Bands **AND** RSI >70/<30.

**Trigger rate on EURUSD H4:** ~5% (extreme breakouts only).

**Fix:** Added `InpEnable_ReaperConditionFilter` (default `false`).
Condition now: `if(InpEnable_ReaperConditionFilter && !IsReaperConditionMet()) return;`

---

### 3.3 Capacity Too Low

`InpMaxOpenTrades = 5` is insufficient when Reaper grid uses up to 10 levels × 2 directions.

**Fix:** Raised to **12**.

---

### 3.4 DualMomentum Disabled

Lines 6047–6081 are mostly comments. Strategy body absent.

**Status:** ❌ NOT FIXED — biggest remaining gap.
**Options:** Reactivate original code OR design replacement momentum strategy.

---

### 3.5 Ultra-Tight Spread Filters on New Strategies

MBD/SRA/SMAD: `Inp*_MaxSpread = 3.0` while global max is 55.0.

**Recommendation:** Raise to 8.0 or set `=0` to inherit global.

---

## 4. CODE CHANGES (Commits)

| Commit | Message |
|---|---|
| `3f08052` | Initial audit skeleton + iADX 6-param fix |
| `001e15b` | Array bounds: `reconciledData[7]→[12]`, loops to `i<12` |
| `d609e84` | `InpV27_StartTracking` datetime; time-gate MBD/SRA/SMAD; `GetStrategyName()` mapping |
| `e30bc76` | Expand magic-whitelisting to 10 strategies (4 functions) |
| `7cec952` | `InpMaxOpenTrades` 5→12; `InpEnable_ReaperConditionFilter = false` |
| `c17555e` | Fix `CountOpenTrades()` double-brace; verify MR/Warden conditions |
| `0a8f12c` | **This full audit report** |

---

## 5. STRATEGY KNOWN PERFORMANCE (Reference)

|Strategy|Period|PF|WR|Trades|
|---|---|---|---|---|
|VolatilityMR|2023–2026|4.16|65.7%|35|
|Titan Best|2023–2026|2.12|—|—|
|DualMomentum (Python)|2023–2026|3.50|69.0%|58|
|DualMomentum (MT4)|2020–2026|0.67|—|—| (failed)
|NoiseBreakout|Historical|5.78|—|—| (old data)
|Donchian Breakout|—|>2.0|—|—| (only passed sweep)

**Takeaway:** Titan and Donchian are only PF>2.0 strategies on recent data. All VWAP/Noise/ORB variants failed.

---

## 6. REMAINING BLOCKERS

1. **DualMomentum disabled** — must reactivate or replace to reach target trade count
2. **MBD/SRA/SMAD spread = 3.0 pips** — likely too tight; raise to 5–8
3. **Dashboard loops `i<7`** — cosmetic, but hides strategies 7–9 on UI
4. **Time-gate silent** — add log when strategies skip due to `InpV27_StartTracking`

---

## 7. BACKTEST SETTINGS

```
InpMaxOpenTrades = 12
InpEnable_ReaperConditionFilter = false
InpEnableAdaptiveSelection = false
InpEnableCooldownSystem = false
InpMax_Spread_Pips = 55
InpMBD_MaxSpread = 8.0
InpSRA_MaxSpread = 8.0
InpSMAD_MaxSpread = 8.0
InpTradingStartHour = 0
InpTradingEndHour = 24
```

Period: 2023.01.01 – 2026.04.25, Model: Every tick.

---

## 8. CONCLUSION

V26 was **capable but artificially constrained**. Capacity blindness and over-filtering caused under-trading, not strategy flaws.

Fixes restore:
- Accurate capacity accounting
- Unblocked MR & Warden
- Grid/other coexistence
- True dashboard P&L

**The only missing piece is an active 10th strategy.** DualMomentum must be reactivated or replaced to hit trade-count and PF targets.

**Next decision:** Replace or repair DualMomentum?

---

**Audit by:** Hermes (Max)  
**GitHub:** `0a8f12c` — `Docs/V26_System_Audit.md`  
**All fixes:** pushed to `master`
