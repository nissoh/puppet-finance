// we record CVG and traderPnL in ```scores``` mapping 
    // (epoch => Score(totalScore,traderScore(Trader=>scoreAmount),TotalScore(totalCVG,totalPnL),TraderScore(CVG,PnL))) 
    // in ScoreGauge every time a position is settled
// on epoch increment, Traders can claim rewards from ScoreGauge
// ScoreGauge calculates rewards based on the scores mapping --> ```reward = (score / totalScore) * totalReward```