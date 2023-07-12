// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract OperationTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testSetupStrategyOK() public {
        console.log("address of strategy", address(strategy));
        assertTrue(address(0) != address(strategy));
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);
        // TODO: add additional check on strat params
    }

    function test_operation_NoFees(uint256 _amount) public {
        setPerformanceFeeToZero(address(strategy));
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(10 days);

        // Report loss
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");

        skip(strategy.profitMaxUnlockTime());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");
    }

    function test_profitableReport_NoFees_Airdrop(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        setPerformanceFeeToZero(address(strategy));
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after first report", loss);

        // Earn Interest
        skip(1 days);

        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("collateral in asset ", strategy.balanceCollateral());
        console.log("debt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("investment in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("_LTV(): ", strategy.LTV());
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after unlocktime report", strategy.totalAssets());
        console.log("collateral in asset ", strategy.balanceCollateral());
        console.log("debt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("investment in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("_LTV(): ", strategy.LTV());

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        checkStrategyTotals(strategy, 0, 0, 0);

        // TODO: Adjust if there are fees
        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount + toAirdrop, "!final balance");
    }

    function test_profitableReport_withFees_Airdrop(
        uint256 _amount,
        uint16 _profitFactor
    ) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        _profitFactor = uint16(bound(uint256(_profitFactor), 10, MAX_BPS));
        uint256 profit;
        uint256 loss;
        // Set protofol fee to 0 and perf fee to 10%
        setFees(0, 1_000);
        console.log("performance fees: ", strategy.performanceFee());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // TODO: Implement logic so totalDebt is _amount and totalIdle = 0.
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Report loss
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        // Check return Values
        assertGe(profit, 0, "!profit");
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        uint256 initialLoss = loss;
        console.log("initialLoss after first report", loss);

        // Earn Interest
        skip(1 days);

        // TODO: implement logic to simulate earning interest.
        uint256 toAirdrop = (_amount * _profitFactor) / MAX_BPS;
        airdrop(asset, address(strategy), toAirdrop);

        // Report profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("IMMEDIATELY actualShares of performanceFeeRecipient", strategy.balanceOf(performanceFeeRecipient));

        // Check return Values
        assertGe(profit * (MAX_BPS + expectedProfitReductionBPS)/MAX_BPS, toAirdrop, "!profit");
        console.log("profit after second report", profit);
        assertGe(strategy.totalAssets() * expectedActivityLossBPS / MAX_BPS, loss, "!loss");
        console.log("loss after second report", loss);

        console.log("TOTAL ASSETS after airdorp report", strategy.totalAssets());
        console.log("collateral in asset ", strategy.balanceCollateral());
        console.log("debt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("investment in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("_LTV(): ", strategy.LTV());
        skip(strategy.profitMaxUnlockTime());
        console.log("TOTAL ASSETS after maxunlocktime", strategy.totalAssets());
        console.log("collateral in asset ", strategy.balanceCollateral());
        console.log("debt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("investment in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("_LTV(): ", strategy.LTV());

        // Get the expected fee
        uint256 actualShares = strategy.balanceOf(performanceFeeRecipient);
        console.log("actualShares of performanceFeeRecipient", actualShares);
        console.log("shares of user", strategy.balanceOf(user));
        console.log("total Shares", strategy.totalSupply());
        assertEq(strategy.balanceOf(performanceFeeRecipient), actualShares);

        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        // TODO: Adjust if there are fees
        assertGe(asset.balanceOf(user) * (MAX_BPS + expectedActivityLossBPS)/MAX_BPS, balanceBefore + _amount, "!final balance");

        
        if (actualShares > 0){
            vm.prank(performanceFeeRecipient);
            strategy.redeem(actualShares, performanceFeeRecipient, performanceFeeRecipient);
        }
        
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(asset.balanceOf(performanceFeeRecipient) * (MAX_BPS + 500)/MAX_BPS, actualShares, "!perf fee out");
    }
    
/*
    function test_tendTrigger(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        assertTrue(!strategy.tendTrigger());

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertTrue(!strategy.tendTrigger());

        // Skip some time
        skip(1 days);

        assertTrue(!strategy.tendTrigger());

        vm.prank(keeper);
        strategy.report();

        assertTrue(!strategy.tendTrigger());

        // Unlock Profits
        skip(strategy.profitMaxUnlockTime());

        assertTrue(!strategy.tendTrigger());

        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertTrue(!strategy.tendTrigger());
    }
    */
}
