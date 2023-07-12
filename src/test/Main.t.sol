// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import "forge-std/console.sol";
import {Setup} from "./utils/Setup.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAToken} from "../interfaces/Aave/V3/IAtoken.sol";

contract MainTest is Setup {
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

    function test_main() public {
        setPerformanceFeeToZero(address(strategy));
        //init
        uint256 profit;
        uint256 loss;
        uint256 _amount = 1000e18; //1000 DAI
        vm.prank(management);
        strategy.setLTV(12e16, 14e16, 23e16, 25e16);
        console.log("asset: ", asset.symbol());
        console.log("amount:", _amount);
        //user funds:
        airdrop(asset, user, _amount);
        assertEq(asset.balanceOf(user), _amount, "!totalAssets");
        //user deposit:
        depositIntoStrategy(strategy, user, _amount);
        assertEq(asset.balanceOf(user), 0, "user balance after deposit =! 0");
        assertEq(strategy.totalAssets(), _amount, "strategy.totalAssets() != _amount after deposit");
        console.log("deposit strategy.totalAssets() after deposit: ", strategy.totalAssets());
        console.log("strategy.totalDebt() after deposit: ", strategy.totalDebt());
        console.log("strategy.totalIdle() after deposit: ", strategy.totalIdle());
        //aToken amount:
        IAToken aToken = IAToken(strategy.aToken());
        console.log("aToken address: ", address(aToken));
        console.log("aToken balance: ", aToken.balanceOf(address(strategy)));
        checkStrategyTotals(strategy, _amount, _amount, 0);
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in CRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in DAI: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));

        //keeper trigger borrowMore:
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("FIRST REPORT->log: profit ", profit);
        console.log("loss: ", loss);
        console.log("strategy LTVborrowLessNow: ", strategy.LTVborrowLessNow());
        console.log("strategy LTVborrowLess: ", strategy.LTVborrowLess());
        console.log("strategy LTVtarget: ", strategy.LTVtarget());
        console.log("strategy LTVborrowMore: ", strategy.LTVborrowMore());
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        skip(strategy.profitMaxUnlockTime());

/*
        //keeper trigger borrowLess:
        vm.prank(management);
        strategy.setLTV(40e16, 50e16, 50e16, 60e16);
        console.log("SETLTV->log: strategy LTVborrowLessNow: ", strategy.LTVborrowLessNow());
        console.log("strategy LTVborrowLess: ", strategy.LTVborrowLess());
        console.log("strategy LTVtarget: ", strategy.LTVtarget());
        console.log("strategy LTVborrowMore: ", strategy.LTVborrowMore());
        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("SECOND REPORT->log: profit: ", profit);
        console.log("loss: ", loss);
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());
*/

        //simulate loss:
        vm.prank(address(strategy));
        STYCRV.transfer(user, 140e18*0.25925925925925924);

        // Withdraw all funds
        console.log("strategy.totalAssets() before redeem: ", strategy.totalAssets());
        console.log("shares user: ", strategy.balanceOf(user));
        vm.prank(user);
        strategy.redeem(_amount*90/100, user, user);
        console.log("REDEEM 90%->log: ", _amount*90/100);
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());
        console.log("balance user: ", asset.balanceOf(user));

        //vm.prank(management);
        //strategy.setUniFees(asset, CRV, 3000);

        vm.prank(management);
        strategy.setMinLossToSellCollateralBPS(0);
        console.log("SETMINLOSSTOSELLCOLLATERALBPS(0)->log");

        vm.prank(keeper);
        (profit, loss) = strategy.report();
        console.log("THIRD REPORT->log: profit: ", profit);
        console.log("loss: ", loss);
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        //console.log("balanceDebt in Asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());

        // Withdraw all funds
        console.log("strategy.totalAssets() before FINAL redeem: ", strategy.totalAssets());
        uint sharesLeft = strategy.balanceOf(user)*9999/10000;
        console.log("shares user: ", sharesLeft);
        vm.prank(user);
        strategy.redeem(sharesLeft, user, user);
        console.log("REDEEM 90%->log: ", sharesLeft);
        console.log("balanceAsset: ", strategy.balanceAsset());
        console.log("balanceCollateral in asset: ", strategy.balanceCollateral());
        console.log("balanceDebt in CRV: ", strategy.balanceDebt());
        console.log("balanceDebt in asset: ", strategy.CRVtoAsset(strategy.balanceDebt()));
        console.log("balanceSTYCRV in STYCRV: ", strategy.balanceSTYCRV());
        console.log("balanceSTYCRV in YCRV: ", strategy.STYCRVtoYCRV(strategy.balanceSTYCRV()));
        console.log("balanceSTYCRV in CRV: ", strategy.YCRVtoCRV(strategy.STYCRVtoYCRV(strategy.balanceSTYCRV())));
        console.log("balanceSTYCRV in asset: ", strategy.STYCRVtoAsset(strategy.balanceSTYCRV()));
        console.log("LTV: ", strategy.LTV());
        console.log("balance user: ", asset.balanceOf(user));



    }
/*
    function test_fuzz_operation(uint256 _amount) public {
        vm.assume(_amount > minFuzzAmount && _amount < maxFuzzAmount);
        // Deposit into strategy
        mintAndDepositIntoStrategy(strategy, user, _amount);
        checkStrategyTotals(strategy, _amount, _amount, 0);
    }
*/
}
