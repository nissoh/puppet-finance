// we record CVG and traderPnL in ```scores``` mapping 
    // (epoch => Score(totalScore,traderScore(Trader=>scoreAmount),TotalScore(totalCVG,totalPnL),TraderScore(CVG,PnL))) 
    // in ScoreGauge every time a position is settled
// on epoch increment, Traders can claim rewards from ScoreGauge
// ScoreGauge calculates rewards based on the scores mapping --> ```reward = (score / totalScore) * totalReward```


// ---- from discord dm with itburnz ----
// yea so we'll have a local gauge for sidechain dexs, which will receive emissions according to gaugeController weights, then send all emissions to the actual ScoreGauge on the respective sidechain, which Traders will then claim the tokens from. architecture allows us to handle this later :)

// so currently we'll have the GaugeController on Arbi, which will be non-upgradeable, together with the Minter (which mints tokens to ScoreGauges according to GaugeController weights). then we'll have a ScoreGauge contract which keeps the score for Traders and distributes tokens based on that score. then later we'll create a sidechainHelperGauge (or something) that will be on Arbi, will get emissions from Minter/GaugeContoller, and bridge those emissions to it's respective ScoreGauge on whatever sidechain, which will distribute them to Traders

// if then Traders want to lock Puppet and not dump them, they will need to bridge them back to Arbi
// ScoreGauge is also upgradable, so we can add features as we want
// the sidechainHelperGauge will also be able to send vePuppet balances info to sidechain, so we should be able to have the vendor locking feature that way


// ---- from discord dm with itburnz ----
// actually lemme describe it to you from a high level:

// the GaugeController decides on minting of Puppet tokens to diff PerformanceGauges based on weights etc (governance). PerformanceGauges decide on distribution of minted Puppet tokens to Traders according to performanceScore (CVG * cvgWeight + PnL * pnlWeight).
// we need Route to update the performanceScore on the respective PerformanceGauge every time a Trader settles a trade.

// each DEX has it's own PerformanceGauge
// PerformanceGauges works in epochs, only once an epoch (1 week) has ended, a Trader can claim his Puppet tokens