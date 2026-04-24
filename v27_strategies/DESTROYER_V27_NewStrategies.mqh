//+------------------------------------------------------------------+
//|  DESTROYER V27 - NEW STRATEGIES MODULE                            |
//|  Elite Strategy Pack for Ryan (@okyyryan)                        |
//|  3 New Strategies: MBD, SRA, SMAD                               |
//|  Magic Numbers: 999101, 999102, 999103                           |
//+------------------------------------------------------------------+
//|  STRATEGY INDEX MAPPING:                                        |
//|  9 = Momentum Burst Detector (MBD)                              |
//|  10 = Session Rotation Alpha (SRA)                              |
//|  11 = Smart Money Accumulation (SMAD)                             |
//+------------------------------------------------------------------+

#property copyright "DESTROYER V27 - MiniMax Agent for Ryan"
#property link      ""
#property version   "27.0"
#property strict

//+------------------------------------------------------------------+
//| INCLUDES                                                        |
//+------------------------------------------------------------------+
#include <stdlib.mqh>

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES - NEW STRATEGIES                                 |
//+------------------------------------------------------------------+
// Strategy IDs
#define STRATEGY_MBD          9
#define STRATEGY_SRA         10
#define STRATEGY_SMAD        11

// Magic Numbers
#define MAGIC_MBD         999101
#define MAGIC_SRA         999102
#define MAGIC_SMAD        999103

//+------------------------------------------------------------------+
//| STRATEGY 1: MOMENTUM BURST DETECTOR (MBD)                        |
//| Magic: 999101                                                   |
//| Entry: BB extreme + RSI extreme + Stoch extreme + Volume spike  |
//+------------------------------------------------------------------+

struct SMBD_Config
{
    int      BollingerPeriod;
    double   BollingerDeviation;
    int      RSIPeriod;
    int      StochPeriod;
    double   ADXMax;
    double   VolumeRatioMin;
    double   StochOversold;
    double   StochOverbought;
    double   RSIOversold;
    double   RSIOverbought;
    double   StopMultiplier;
    double   TpMultiplier;
};

SMBD_Config MBD_Params =
{
    20,    // BollingerPeriod
    2.5,   // BollingerDeviation
    14,    // RSIPeriod
    14,    // StochPeriod
    25.0,  // ADXMax
    1.2,   // VolumeRatioMin
    20.0,  // StochOversold
    80.0,  // StochOverbought
    30.0,  // RSIOversold
    70.0,  // RSIOverbought
    1.5,   // StopMultiplier
    3.0    // TpMultiplier
};

//+------------------------------------------------------------------+
//| MBD - Calculate Indicators                                       |
//+------------------------------------------------------------------+
bool MBD_CalculateIndicators(double &bb_middle, double &bb_upper, double &bb_lower,
                            double &rsi_value, double &stoch_k, double &stoch_d,
                            double &adx_value, double &atr_value, double &volume_ratio)
{
    // Bollinger Bands
    bb_middle = iMA(NULL, PERIOD_H4, MBD_Params.BollingerPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
    double stddev = iStdDev(NULL, PERIOD_H4, MBD_Params.BollingerPeriod, 0, MODE_SMA, PRICE_CLOSE, 1);
    bb_upper = bb_middle + (MBD_Params.BollingerDeviation * stddev);
    bb_lower = bb_middle - (MBD_Params.BollingerDeviation * stddev);

    // RSI
    rsi_value = iRSI(NULL, PERIOD_H4, MBD_Params.RSIPeriod, PRICE_CLOSE, 1);

    // Stochastic
    stoch_k = iStochastic(NULL, PERIOD_H4, MBD_Params.StochPeriod, 3, 3, MODE_SMA, STO_LOWHIGH, MODE_MAIN, 1);
    stoch_d = iStochastic(NULL, PERIOD_H4, MBD_Params.StochPeriod, 3, 3, MODE_SMA, STO_LOWHIGH, MODE_SIGNAL, 1);

    // ADX
    adx_value = iADX(NULL, PERIOD_H4, 14, PRICE_CLOSE, 1);

    // ATR
    atr_value = iATR(NULL, PERIOD_H4, 14, 1);

    // Volume Ratio (simplified - compare current volume to moving average)
    double volume_ma = iMA(NULL, PERIOD_H4, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
    double current_volume = (double)iVolume(NULL, PERIOD_H4, 1);
    double avg_volume = iMA(NULL, PERIOD_H4, 20, 0, MODE_SMA, MODE_VOLUME, 1);
    volume_ratio = (avg_volume > 0) ? (current_volume / avg_volume) : 1.0;

    return (bb_middle > 0 && rsi_value > 0 && atr_value > 0);
}

//+------------------------------------------------------------------+
//| MBD - Check Entry Conditions                                     |
//+------------------------------------------------------------------+
int MBD_CheckEntry()
{
    double bb_mid, bb_up, bb_low, rsi, stoch_k, stoch_d, adx, atr, vol_ratio;

    if (!MBD_CalculateIndicators(bb_mid, bb_up, bb_low, rsi, stoch_k, stoch_d, adx, atr, vol_ratio))
        return -1;

    double close = Close[1];
    double volume = (double)iVolume(NULL, PERIOD_H4, 1);
    double volume_ma = iMA(NULL, PERIOD_H4, 20, 0, MODE_SMA, MODE_VOLUME, 1);
    vol_ratio = (volume_ma > 0) ? (volume / volume_ma) : 1.0;

    // BUY: Price below lower band + RSI oversold + Stoch oversold + Volume spike + Low ADX
    if (close < bb_low &&
        rsi < MBD_Params.RSIOversold &&
        stoch_k < MBD_Params.StochOversold &&
        vol_ratio > MBD_Params.VolumeRatioMin &&
        adx < MBD_Params.ADXMax)
    {
        return OP_BUY;
    }

    // SELL: Price above upper band + RSI overbought + Stoch overbought + Volume spike + Low ADX
    if (close > bb_up &&
        rsi > MBD_Params.RSIOverbought &&
        stoch_k > MBD_Params.StochOverbought &&
        vol_ratio > MBD_Params.VolumeRatioMin &&
        adx < MBD_Params.ADXMax)
    {
        return OP_SELL;
    }

    return -1;
}

//+------------------------------------------------------------------+
//| MBD - Calculate Stop Loss and Take Profit                        |
//+------------------------------------------------------------------+
void MBD_CalculateSLTP(double entry_price, int direction, double &sl, double &tp)
{
    double atr = iATR(NULL, PERIOD_H4, 14, 1);

    if (direction == OP_BUY)
    {
        sl = entry_price - (atr * MBD_Params.StopMultiplier);
        tp = entry_price + (atr * MBD_Params.TpMultiplier);
    }
    else
    {
        sl = entry_price + (atr * MBD_Params.StopMultiplier);
        tp = entry_price - (atr * MBD_Params.TpMultiplier);
    }
}

//+------------------------------------------------------------------+
//| STRATEGY 2: SESSION ROTATION ALPHA (SRA)                         |
//| Magic: 999102                                                   |
//| Entry: Session-specific parameters for Asia/London/NY            |
//+------------------------------------------------------------------+

enum ENUM_FOREX_SESSION
{
    SESSION_ASIA,
    SESSION_LONDON,
    SESSION_NY,
    SESSION_OVERLAP,
    SESSION_OTHER
};

struct SSRA_Config
{
    // Asia Session Parameters (Range-bound)
    double   Asia_BBDeviation;
    double   Asia_RSI_Oversold;
    double   Asia_RSI_Overbought;

    // London/NY Session Parameters (Trend)
    double   Global_BBDeviation;
    double   Global_RSI_Oversold;
    double   Global_RSI_Overbought;
    double   Global_ADXMax;

    // Common
    double   StopMultiplier;
    double   TpMultiplier;
};

SSRA_Config SRA_Params =
{
    1.5,    // Asia_BBDeviation
    40.0,   // Asia_RSI_Oversold
    60.0,   // Asia_RSI_Overbought

    2.0,    // Global_BBDeviation
    35.0,   // Global_RSI_Oversold
    65.0,   // Global_RSI_Overbought
    30.0,   // Global_ADXMax

    1.5,    // StopMultiplier
    3.0     // TpMultiplier
};

//+------------------------------------------------------------------+
//| SRA - Detect Current Session                                     |
//+------------------------------------------------------------------+
ENUM_FOREX_SESSION SRA_GetCurrentSession()
{
    int hour = Hour();

    if (hour >= 0 && hour < 8)
        return SESSION_ASIA;
    else if (hour >= 8 && hour < 12)
        return SESSION_LONDON;
    else if (hour >= 12 && hour < 16)
        return SESSION_NY;
    else if (hour >= 14 && hour < 18)
        return SESSION_OVERLAP;
    else
        return SESSION_OTHER;
}

//+------------------------------------------------------------------+
//| SRA - Check Entry Conditions                                    |
//+------------------------------------------------------------------+
int SRA_CheckEntry()
{
    ENUM_FOREX_SESSION session = SRA_GetCurrentSession();

    double rsi = iRSI(NULL, PERIOD_H4, 14, PRICE_CLOSE, 1);
    double adx = iADX(NULL, PERIOD_H4, 14, PRICE_CLOSE, 1);

    double bb_dev, rsi_oversold, rsi_overbought;
    double max_adx = 30.0;
    int bb_period = 20;

    // Set session-specific parameters
    if (session == SESSION_ASIA)
    {
        // Asia: Range-bound - tighter bands
        bb_dev = SRA_Params.Asia_BBDeviation;
        rsi_oversold = SRA_Params.Asia_RSI_Oversold;
        rsi_overbought = SRA_Params.Asia_RSI_Overbought;
        max_adx = 35.0;
    }
    else
    {
        // London/NY/Overlap: Trend continuation
        bb_dev = SRA_Params.Global_BBDeviation;
        rsi_oversold = SRA_Params.Global_RSI_Oversold;
        rsi_overbought = SRA_Params.Global_RSI_Overbought;
        max_adx = SRA_Params.Global_ADXMax;
    }

    // Calculate Bollinger Bands with custom deviation
    double bb_mid = iMA(NULL, PERIOD_H4, bb_period, 0, MODE_SMA, PRICE_CLOSE, 1);
    double stddev = iStdDev(NULL, PERIOD_H4, bb_period, 0, MODE_SMA, PRICE_CLOSE, 1);
    double bb_upper = bb_mid + (bb_dev * stddev);
    double bb_lower = bb_mid - (bb_dev * stddev);

    double close = Close[1];

    // BUY: Below lower band + RSI oversold + ADX filter
    if (close < bb_lower && rsi < rsi_oversold && adx < max_adx)
        return OP_BUY;

    // SELL: Above upper band + RSI overbought + ADX filter
    if (close > bb_upper && rsi > rsi_overbought && adx < max_adx)
        return OP_SELL;

    return -1;
}

//+------------------------------------------------------------------+
//| SRA - Calculate Stop Loss and Take Profit                        |
//+------------------------------------------------------------------+
void SRA_CalculateSLTP(double entry_price, int direction, double &sl, double &tp)
{
    double atr = iATR(NULL, PERIOD_H4, 14, 1);

    if (direction == OP_BUY)
    {
        sl = entry_price - (atr * SRA_Params.StopMultiplier);
        tp = entry_price + (atr * SRA_Params.TpMultiplier);
    }
    else
    {
        sl = entry_price + (atr * SRA_Params.StopMultiplier);
        tp = entry_price - (atr * SRA_Params.TpMultiplier);
    }
}

//+------------------------------------------------------------------+
//| STRATEGY 3: SMART MONEY ACCUMULATION (SMAD)                     |
//| Magic: 999103                                                   |
//| Entry: Pivot levels + Absorption pattern + Candle confirmation  |
//+------------------------------------------------------------------+

struct SSMAD_Config
{
    int      ATRPeriod;
    double   AbsorptionMin;
    double   RSIOversold;
    double   RSIOverbought;
    double   StopMultiplier;
    double   TpMultiplier;
};

SSMAD_Config SMAD_Params =
{
    14,     // ATRPeriod
    1.3,    // AbsorptionMin
    40.0,   // RSIOversold
    60.0,   // RSIOverbought
    1.5,    // StopMultiplier
    3.0     // TpMultiplier
};

//+------------------------------------------------------------------+
//| SMAD - Calculate Daily Pivot Levels                              |
//+------------------------------------------------------------------+
void SMAD_CalculatePivots(double &pivot, double &r1, double &s1)
{
    double prev_high = iHigh(NULL, PERIOD_D1, 1);
    double prev_low = iLow(NULL, PERIOD_D1, 1);
    double prev_close = iClose(NULL, PERIOD_D1, 1);

    pivot = (prev_high + prev_low + prev_close) / 3.0;
    r1 = (2 * pivot) - prev_low;
    s1 = (2 * pivot) - prev_high;
}

//+------------------------------------------------------------------+
//| SMAD - Calculate Absorption Score                               |
//+------------------------------------------------------------------+
double SMAD_CalculateAbsorption()
{
    // Volume ratio
    double volume = (double)iVolume(NULL, PERIOD_H4, 1);
    double volume_ma = iMA(NULL, PERIOD_H4, 20, 0, MODE_SMA, MODE_VOLUME, 1);
    double vol_ratio = (volume_ma > 0) ? (volume / volume_ma) : 1.0;

    // ATR for normalization
    double atr = iATR(NULL, PERIOD_H4, SMAD_Params.ATRPeriod, 1);
    double close = Close[1];
    double bb_mid = iMA(NULL, PERIOD_H4, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
    double stddev = iStdDev(NULL, PERIOD_H4, 20, 0, MODE_SMA, PRICE_CLOSE, 1);
    double bb_width = 4.0 * stddev;

    // Absorption = Volume * (1 - BBWidth/ATR)
    double bb_width_normalized = (atr > 0) ? (bb_width / atr) : 0;
    double absorption = vol_ratio * (1.0 - bb_width_normalized);

    return absorption;
}

//+------------------------------------------------------------------+
//| SMAD - Check Entry Conditions                                   |
//+------------------------------------------------------------------+
int SMAD_CheckEntry()
{
    double pivot, r1, s1;
    SMAD_CalculatePivots(pivot, r1, s1);

    double close = Close[1];
    double open = Open[1];
    double rsi = iRSI(NULL, PERIOD_H4, 14, PRICE_CLOSE, 1);
    double atr = iATR(NULL, PERIOD_H4, SMAD_Params.ATRPeriod, 1);
    double absorption = SMAD_CalculateAbsorption();

    // BUY: Near support + High absorption + RSI oversold + Bullish candle
    if (close < (s1 + atr) &&
        absorption > SMAD_Params.AbsorptionMin &&
        rsi < SMAD_Params.RSIOversold &&
        close > open)
    {
        return OP_BUY;
    }

    // SELL: Near resistance + High absorption + RSI overbought + Bearish candle
    if (close > (r1 - atr) &&
        absorption > SMAD_Params.AbsorptionMin &&
        rsi > SMAD_Params.RSIOverbought &&
        close < open)
    {
        return OP_SELL;
    }

    return -1;
}

//+------------------------------------------------------------------+
//| SMAD - Calculate Stop Loss and Take Profit                      |
//+------------------------------------------------------------------+
void SMAD_CalculateSLTP(double entry_price, int direction, double &sl, double &tp)
{
    double atr = iATR(NULL, PERIOD_H4, SMAD_Params.ATRPeriod, 1);

    if (direction == OP_BUY)
    {
        sl = entry_price - (atr * SMAD_Params.StopMultiplier);
        tp = entry_price + (atr * SMAD_Params.TpMultiplier);
    }
    else
    {
        sl = entry_price + (atr * SMAD_Params.StopMultiplier);
        tp = entry_price - (atr * SMAD_Params.TpMultiplier);
    }
}

//+------------------------------------------------------------------+
//| UNIVERSAL TRADE EXECUTION FUNCTION                              |
//+------------------------------------------------------------------+
bool ExecuteNewStrategy(int strategy_id, int magic_number)
{
    int cmd = -1;
    string strategy_name = "";

    // Check entry conditions based on strategy
    switch(strategy_id)
    {
        case STRATEGY_MBD:
            cmd = MBD_CheckEntry();
            strategy_name = "Momentum Burst Detector";
            break;
        case STRATEGY_SRA:
            cmd = SRA_CheckEntry();
            strategy_name = "Session Rotation Alpha";
            break;
        case STRATEGY_SMAD:
            cmd = SMAD_CheckEntry();
            strategy_name = "Smart Money Accumulation";
            break;
    }

    if (cmd < 0)
        return false;

    // Check if we already have an open position for this strategy
    if (CountOrdersForStrategy(magic_number) > 0)
        return false;

    // Calculate entry, SL, TP
    double entry_price = Close[1];
    double sl, tp;

    switch(strategy_id)
    {
        case STRATEGY_MBD:
            MBD_CalculateSLTP(entry_price, cmd, sl, tp);
            break;
        case STRATEGY_SRA:
            SRA_CalculateSLTP(entry_price, cmd, sl, tp);
            break;
        case STRATEGY_SMAD:
            SMAD_CalculateSLTP(entry_price, cmd, sl, tp);
            break;
    }

    // Check spread
    if (!IsSpreadAcceptable(3.0))
        return false;

    // Calculate lot size
    double lot_size = CalculateLotSize(sl, entry_price, 2.0);
    if (lot_size < 0.01)
        return false;

    // Execute trade
    int ticket = OrderSend(Symbol(), cmd, lot_size, entry_price, 3, sl, tp,
                          strategy_name + " (" + IntegerToString(strategy_id) + ")", magic_number, 0, Green);

    if (ticket > 0)
    {
        Print("[", strategy_name, "] Trade opened: ", cmd == OP_BUY ? "BUY" : "SELL",
              " @ ", entry_price, " SL: ", sl, " TP: ", tp);
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| PERFORMANCE TRACKING STRUCTURES                                  |
//+------------------------------------------------------------------+
struct SStrategyPerformance
{
    int      strategy_id;
    string   strategy_name;
    int      magic_number;
    int      total_trades;
    int      winning_trades;
    int      losing_trades;
    double   gross_profit;
    double   gross_loss;
    double   net_profit;
    double   profit_factor;
    double   win_rate;
};

SStrategyPerformance g_MBD_Performance;
SStrategyPerformance g_SRA_Performance;
SStrategyPerformance g_SMAD_Performance;

//+------------------------------------------------------------------+
//| INITIALIZE PERFORMANCE TRACKING                                  |
//+------------------------------------------------------------------+
void InitializeNewStrategyPerformance()
{
    g_MBD_Performance.strategy_id = STRATEGY_MBD;
    g_MBD_Performance.strategy_name = "Momentum Burst Detector";
    g_MBD_Performance.magic_number = MAGIC_MBD;
    g_MBD_Performance.total_trades = 0;
    g_MBD_Performance.winning_trades = 0;
    g_MBD_Performance.losing_trades = 0;
    g_MBD_Performance.gross_profit = 0;
    g_MBD_Performance.gross_loss = 0;
    g_MBD_Performance.net_profit = 0;

    g_SRA_Performance.strategy_id = STRATEGY_SRA;
    g_SRA_Performance.strategy_name = "Session Rotation Alpha";
    g_SRA_Performance.magic_number = MAGIC_SRA;
    g_SRA_Performance.total_trades = 0;
    g_SRA_Performance.winning_trades = 0;
    g_SRA_Performance.losing_trades = 0;
    g_SRA_Performance.gross_profit = 0;
    g_SRA_Performance.gross_loss = 0;
    g_SRA_Performance.net_profit = 0;

    g_SMAD_Performance.strategy_id = STRATEGY_SMAD;
    g_SMAD_Performance.strategy_name = "Smart Money Accumulation";
    g_SMAD_Performance.magic_number = MAGIC_SMAD;
    g_SMAD_Performance.total_trades = 0;
    g_SMAD_Performance.winning_trades = 0;
    g_SMAD_Performance.losing_trades = 0;
    g_SMAD_Performance.gross_profit = 0;
    g_SMAD_Performance.gross_loss = 0;
    g_SMAD_Performance.net_profit = 0;
}

//+------------------------------------------------------------------+
//| UPDATE PERFORMANCE METRICS                                      |
//+------------------------------------------------------------------+
void UpdateNewStrategyPerformance(int strategy_id, double profit)
{
    SStrategyPerformance *perf;
    int magic;

    switch(strategy_id)
    {
        case STRATEGY_MBD:
            perf = g_MBD_Performance;
            magic = MAGIC_MBD;
            break;
        case STRATEGY_SRA:
            perf = g_SRA_Performance;
            magic = MAGIC_SRA;
            break;
        case STRATEGY_SMAD:
            perf = g_SMAD_Performance;
            magic = MAGIC_SMAD;
            break;
        default:
            return;
    }

    perf.total_trades++;

    if (profit > 0)
    {
        perf.winning_trades++;
        perf.gross_profit += profit;
    }
    else
    {
        perf.losing_trades++;
        perf.gross_loss += MathAbs(profit);
    }

    perf.net_profit = perf.gross_profit - perf.gross_loss;
    perf.win_rate = (perf.total_trades > 0) ? (100.0 * perf.winning_trades / perf.total_trades) : 0;
    perf.profit_factor = (perf.gross_loss > 0) ? (perf.gross_profit / perf.gross_loss) : 0;
}

//+------------------------------------------------------------------+
//| PRINT PERFORMANCE REPORT                                        |
//+------------------------------------------------------------------+
void PrintNewStrategyPerformanceReport()
{
    Print("=== DESTROYER V27 - NEW STRATEGIES PERFORMANCE REPORT ===");
    Print("");

    // MBD
    Print("Strategy: ", g_MBD_Performance.strategy_name, " | Magic: ", MAGIC_MBD);
    Print("  Trades: ", g_MBD_Performance.total_trades,
          " | Win Rate: ", DoubleToString(g_MBD_Performance.win_rate, 1), "%",
          " | PF: ", DoubleToString(g_MBD_Performance.profit_factor, 2));
    Print("  Net Profit: $", DoubleToString(g_MBD_Performance.net_profit, 2));
    Print("");

    // SRA
    Print("Strategy: ", g_SRA_Performance.strategy_name, " | Magic: ", MAGIC_SRA);
    Print("  Trades: ", g_SRA_Performance.total_trades,
          " | Win Rate: ", DoubleToString(g_SRA_Performance.win_rate, 1), "%",
          " | PF: ", DoubleToString(g_SRA_Performance.profit_factor, 2));
    Print("  Net Profit: $", DoubleToString(g_SRA_Performance.net_profit, 2));
    Print("");

    // SMAD
    Print("Strategy: ", g_SMAD_Performance.strategy_name, " | Magic: ", MAGIC_SMAD);
    Print("  Trades: ", g_SMAD_Performance.total_trades,
          " | Win Rate: ", DoubleToString(g_SMAD_Performance.win_rate, 1), "%",
          " | PF: ", DoubleToString(g_SMAD_Performance.profit_factor, 2));
    Print("  Net Profit: $", DoubleToString(g_SMAD_Performance.net_profit, 2));
    Print("");

    // Combined
    double total_net = g_MBD_Performance.net_profit + g_SRA_Performance.net_profit + g_SMAD_Performance.net_profit;
    int total_trades = g_MBD_Performance.total_trades + g_SRA_Performance.total_trades + g_SMAD_Performance.total_trades;
    int total_wins = g_MBD_Performance.winning_trades + g_SRA_Performance.winning_trades + g_SMAD_Performance.winning_trades;
    double combined_win_rate = (total_trades > 0) ? (100.0 * total_wins / total_trades) : 0;

    Print("=== COMBINED V27 STRATEGIES ===");
    Print("  Total Trades: ", total_trades);
    Print("  Combined Win Rate: ", DoubleToString(combined_win_rate, 1), "%");
    Print("  Combined Net Profit: $", DoubleToString(total_net, 2));
    Print("=================================================");
}

//+------------------------------------------------------------------+
//| ON TICK - NEW STRATEGIES EXECUTION                              |
//+------------------------------------------------------------------+
void OnTick_NewStrategies()
{
    // Only execute on H4 bar close (new bar)
    static datetime last_bar_time = 0;
    datetime current_bar_time = iTime(NULL, PERIOD_H4, 0);

    if (current_bar_time == last_bar_time)
        return;

    last_bar_time = current_bar_time;

    // Check each new strategy
    ExecuteNewStrategy(STRATEGY_MBD, MAGIC_MBD);
    ExecuteNewStrategy(STRATEGY_SRA, MAGIC_SRA);
    ExecuteNewStrategy(STRATEGY_SMAD, MAGIC_SMAD);
}

//+------------------------------------------------------------------+
//| ON TRADE - UPDATE PERFORMANCE TRACKING                          |
//+------------------------------------------------------------------+
void OnTrade_NewStrategies()
{
    // This function should be called from the main EA's OnTrade function
    // to update performance tracking for closed orders

    for (int i = OrdersTotal() - 1; i >= 0; i--)
    {
        if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
            continue;

        if (OrderType() > OP_SELL)
            continue;

        int magic = OrderMagicNumber();
        int strategy_id = -1;

        if (magic == MAGIC_MBD)
            strategy_id = STRATEGY_MBD;
        else if (magic == MAGIC_SRA)
            strategy_id = STRATEGY_SRA;
        else if (magic == MAGIC_SMAD)
            strategy_id = STRATEGY_SMAD;

        if (strategy_id >= 0)
        {
            UpdateNewStrategyPerformance(strategy_id, OrderProfit() + OrderSwap() + OrderCommission());
        }
    }
}

//+------------------------------------------------------------------+
//| INTEGRATION GUIDE                                                |
//+------------------------------------------------------------------+
/*
INTEGRATION INSTRUCTIONS FOR DESTROYER V26:

1. COPY THIS FILE TO YOUR MT4 EXPERT FOLDER

2. ADD TO YOUR MAIN EA (DESTROYER_QUANTUM_V26_FULLY_INTEGRATED.mq4):

   a) Add at the top:
      #include "DESTROYER_V27_NewStrategies.mqh"

   b) Add in OnInit():
      InitializeNewStrategyPerformance();

   c) Add in OnTick():
      OnTick_NewStrategies();

   d) Add in OnTrade():
      OnTrade_NewStrategies();

   e) Add in OnDeinit():
      PrintNewStrategyPerformanceReport();

3. MAGIC NUMBERS:
   - MBD: 999101
   - SRA: 999102
   - SMAD: 999103

4. VERIFY IN JOURNAL:
   Look for "[Momentum Burst Detector] Trade opened" messages
   Look for "[Session Rotation Alpha] Trade opened" messages
   Look for "[Smart Money Accumulation] Trade opened" messages

5. TRACK PERFORMANCE:
   The strategies will appear in your tracker just like Silicon-X, Reaper, etc.
   Each strategy has unique magic number for tracking.
*/
//+------------------------------------------------------------------+
