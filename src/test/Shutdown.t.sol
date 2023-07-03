pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract ShutdownTest is Setup {
    function setUp() public override {
        super.setUp();
    }

    function testFail_depositAboveMaxSingleTrade() public {
        uint256 _amount = strategy.maxSingleTrade() + 1; //just above maxSingleTrade
        mintAndDepositIntoStrategy(strategy, user, _amount);
    }

    function test_reportWaitAndShutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 expectedMaxLossBPS = 100;
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        console.log("after Deposit: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Earn Interest
        skip(1 days);

        console.log("after Interest: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertGe(_amount*expectedMaxLossBPS/100_00, loss);
        checkStrategyTotals(strategy, _amount - loss, _amount - loss, 0);
        console.log("after Report: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        skip(strategy.profitMaxUnlockTime());
        console.log("after skip: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();

        console.log("after Shutdown: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyTotals(strategy, 0, 0, 0);

        console.log("after Redeem: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());


        assertGe(asset.balanceOf(user), balanceBefore + _amount*expectedMaxLossBPS/100_00, "!final balance");
    }

    function test_reportDontWaitAndShutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        uint256 expectedMaxLossBPS = 200;
        uint256 profit;
        uint256 loss;

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        console.log("after Deposit: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Earn Interest
        skip(1 days);

        console.log("after Interest: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        assertGe(_amount*expectedMaxLossBPS/100_00, loss);
        checkStrategyTotals(strategy, _amount - loss, _amount - loss, 0);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();
        checkStrategyTotals(strategy, _amount - loss, _amount - loss, 0);

        console.log("after Shutdown: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        //tend strategy if tend is necessary:
        if (strategy.harvestTrigger() == True) {
            vm.prank(keeper);
            (profit, loss) = strategy.report();
            assertGe(_amount*expectedMaxLossBPS/100_00, loss);
            checkStrategyTotals(strategy, _amount - loss, _amount - loss, 0);
        }

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyTotals(strategy, 0, 0, 0);

        console.log("after Redeem: ", strategy.balanceOf(user));
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        assertGe(asset.balanceOf(user), balanceBefore + _amount*expectedMaxLossBPS/100_00, "!final balance");
    }

    function test_shutdownCanWithdraw(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);

        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Earn Interest
        skip(1 days);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();
        checkStrategyTotals(strategy, _amount, _amount, 0);

        // Make sure we can still withdraw the full amount
        uint256 balanceBefore = asset.balanceOf(user);

        // Withdraw all funds
        vm.prank(user);
        strategy.redeem(_amount, user, user);
        checkStrategyTotals(strategy, 0, 0, 0);

        assertGe(
            asset.balanceOf(user),
            balanceBefore + _amount,
            "!final balance"
        );
    }

    // TODO: Add tests for any emergency function added.
}
