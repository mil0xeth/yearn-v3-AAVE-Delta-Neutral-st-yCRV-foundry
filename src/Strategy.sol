// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;
import "forge-std/console.sol";
import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IVault} from "./interfaces/Yearn/IVault.sol";

import {IAToken} from "./interfaces/Aave/V3/IAToken.sol";
import {IVariableDebtToken} from "./interfaces/Aave/V3/IVariableDebtToken.sol";
import {IStakedAave} from "./interfaces/Aave/V3/IStakedAave.sol";
import {IPool} from "./interfaces/Aave/V3/IPool.sol";
import {IProtocolDataProvider} from "./interfaces/Aave/V3/IProtocolDataProvider.sol";
import {IRewardsController} from "./interfaces/Aave/V3/IRewardsController.sol";
import {IPriceOracle} from "./interfaces/Aave/V3/IPriceOracle.sol";

import {ICurve, ICurveCalc} from "./interfaces/Curve/Curve.sol";

// Uniswap V3 Swapper
import {UniswapV3Swapper} from "@periphery/swappers/UniswapV3Swapper.sol";

contract Strategy is BaseTokenizedStrategy, UniswapV3Swapper {
    using SafeERC20 for ERC20;

    uint256 public LTVborrowLessNow = 73e16;  //= 60e16;
    uint256 public LTVborrowLess = 71e16; //= 58e16;
    uint256 public LTVtarget = 62e16; //= 54e16;
    uint256 public LTVborrowMore = 60e16; //= 52e16;
    
    uint256 public DiffFromLTborrowLessNow = 4e16; //-4%
    uint256 public DiffFromLTborrowLess = 6e16;
    uint256 public DiffFromLTtarget = 15e16; //-15% from LT --> 77%-15%=62% target LTV
    uint256 public DiffFromLTborrowMore = 17e16;

    //yearn
    address public YCRV = 0xFCc5c47bE19d06BF83eB04298b026F81069ff65b;
    address public STYCRV = 0x27B5739e22ad9033bcBf192059122d163b60349D;
    
    //aave
    IProtocolDataProvider public constant protocolDataProvider = IProtocolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);
    IPool public lendingPool;
    IRewardsController public rewardsController;
    IAToken public aToken;
    IVariableDebtToken public dToken;
    IAToken public aTokenBorrow;
    IPriceOracle internal oracle;

    //curve
    ICurve internal constant curve_CRV_YCRV = ICurve(0x453D92C7d4263201C69aACfaf589Ed14202d83a4);
    ICurve internal constant curve_ETH_CRV = ICurve(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511);
    ICurve internal constant curve_USDT_WBTC_ETH = ICurve(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46);
    ICurve internal constant curve_DAI_USDC_USDT = ICurve(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ICurveCalc internal constant curveCalc = ICurveCalc(0xc1DB00a8E5Ef7bfa476395cdbcc98235477cDE4E);

    address internal constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    uint256 internal constant CRV_UNIT = 1e18;
    uint256 internal constant CRV_DUST = 1000;
    
    uint256 public maxSingleTrade;

    uint256 public swapPriceDepegCRVYCRVBPS; 
    uint256 public swapSlippageAssetCRVBPS;
    uint256 public minLossToSellCollateralBPS;
    uint256 public maxLossBPS; 
    uint256 public maxUtilizationRateBPS;

    uint256 public ASSET_UNIT;
    uint256 internal constant WAD = 1e18;
    uint256 internal constant MAX_BPS = 100_00;

    // stkAave addresses only applicable for Mainnet.
    IStakedAave internal constant stkAave = IStakedAave(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    constructor(address _asset, string memory _name) BaseTokenizedStrategy(_asset, _name) {
        initializeStrategy(_asset);
    }

    function initializeStrategy(address _asset) public {
        maxSingleTrade = 1e6 * 1e18;
        //maxSingleTrade = 100e6 * 1e18;
        // Set slippages:
        swapPriceDepegCRVYCRVBPS = 6_00;
        swapSlippageAssetCRVBPS = 5_00;
        //swapSlippageAssetCRVBPS = 100_00;
        minLossToSellCollateralBPS = 15_00;
        maxLossBPS = 3_00;
        maxUtilizationRateBPS = 71_50;

        // Set uni swapper values
        minAmountToSell = 1e4;
        base = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        _setUniFees(_asset, base, 500);
        _setUniFees(CRV, base, 3000);

        require(address(aToken) == address(0), "already initialized");
        lendingPool = IPool(protocolDataProvider.ADDRESSES_PROVIDER().getPool());
        oracle = IPriceOracle(protocolDataProvider.ADDRESSES_PROVIDER().getPriceOracle());
        aToken = IAToken(lendingPool.getReserveData(_asset).aTokenAddress);
        dToken = IVariableDebtToken(lendingPool.getReserveData(CRV).variableDebtTokenAddress);
        aTokenBorrow = IAToken(lendingPool.getReserveData(CRV).aTokenAddress);
        require(address(aToken) != address(0), "!aToken");
        require(address(dToken) != address(0), "!dToken");
        rewardsController = aToken.getIncentivesController();

        uint256 assetDecimals = uint256(ERC20(_asset).decimals());
        ASSET_UNIT = 10**assetDecimals;

        //approvals:
        ERC20(_asset).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(CRV).safeApprove(address(lendingPool), type(uint256).max);
        ERC20(CRV).safeApprove(address(curve_CRV_YCRV), type(uint256).max);
        ERC20(YCRV).safeApprove(STYCRV, type(uint256).max);
        ERC20(YCRV).safeApprove(address(curve_CRV_YCRV), type(uint256).max);

        //ltv values:
        (, uint256 maxLTV, uint256 LT, , , , , , , ) = protocolDataProvider.getReserveConfigurationData(_asset);
        maxLTV = maxLTV * 1e14;
        LT = LT * 1e14;
        LTVborrowLessNow = LT - DiffFromLTborrowLessNow;
        LTVborrowLess = LT - DiffFromLTborrowLess;
        LTVtarget = LT - DiffFromLTtarget;
        require(LTVtarget <= maxLTV, "LTVtarget > maxLTV!");
        LTVborrowMore = LT - DiffFromLTborrowMore;
        require(LTVborrowLessNow >= LTVborrowLess && LTVborrowLess >= LTVtarget && LTVtarget >= LTVborrowMore, "LTV order wrong!");
    }

    function setLTV(uint256 _DiffFromLTborrowLessNow, uint256 _DiffFromLTborrowLess, uint256 _DiffFromLTtarget, uint256 _DiffFromLTborrowMore) external onlyManagement {
        (, uint256 maxLTV, uint256 LT, , , , , , , ) = protocolDataProvider.getReserveConfigurationData(asset);
        maxLTV = maxLTV * 1e14;
        LT = LT * 1e14;
        LTVborrowLessNow = LT - _DiffFromLTborrowLessNow;
        LTVborrowLess = LT - _DiffFromLTborrowLess;
        LTVtarget = LT - _DiffFromLTtarget;
        require(LTVtarget <= maxLTV, "LTVtarget > maxLTV");
        LTVborrowMore = LT - _DiffFromLTborrowMore;
        require(LTVborrowLessNow >= LTVborrowLess && LTVborrowLess >= LTVtarget && LTVtarget >= LTVborrowMore, "LTV order wrong!");
        DiffFromLTborrowLessNow = _DiffFromLTborrowLessNow;
        DiffFromLTborrowLess = _DiffFromLTborrowLess;
        DiffFromLTtarget = _DiffFromLTtarget;
        DiffFromLTborrowMore = _DiffFromLTborrowMore;
    }

    function setUniFees(
        address _token0,
        address _token1,
        uint24 _fee
    ) external onlyManagement {
        _setUniFees(_token0, _token1, _fee);
    }

    function setMinAmountToSell(
        uint256 _minAmountToSell
    ) external onlyManagement {
        minAmountToSell = _minAmountToSell;
    }

    /*//////////////////////////////////////////////////////////////
                NEEDED TO BE OVERRIDEN BY STRATEGIST
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Should invest up to '_amount' of 'asset'.
     * @param _amount The amount of 'asset' that the strategy should attemppt
     * to deposit in the yield source.
     *
     *call: user deposits --> _invest SANDWICHABLE
     */
    function _invest(uint256 _amount) internal override {
        lendingPool.supply(asset, _amount, address(this), 0);
    }

    /**
     * @dev Will attempt to free the '_amount' of 'asset'.
     * The amount of 'asset' that is already loose has already
     * been accounted for.
     *
     * Should do any needed parameter checks, '_amount' may be more
     * than is actually available.
     *
     * Should not rely on asset.balanceOf(address(this)) calls other than
     * for diff accounting puroposes.
     *
     * @param _amount, The amount of 'asset' to be freed.
     *
     * call: user withdraws --> _freeFunds SANDWICHABLE
     */
    function _freeFunds(uint256 _amount) internal override {
        console.log("_AMOUNT!!!!!!!!!!!!!!!!!!!!!!!: ", _amount);
        console.log("collateral in asset ", _balanceCollateral());
        console.log("debt in asset: ", _CRVtoAsset(_balanceDebt()));
        console.log("investment in asset: ", _STYCRVtoAsset(_balanceSTYCRV()));
        console.log("_LTV(): ", _STYCRVtoAsset(_balanceSTYCRV()));
        uint256 currentLTV = _LTV();
        uint256 collateralBalance = _balanceCollateral();
        uint256 totalAssets = TokenizedStrategy.totalAssets();
        require(_amount <= totalAssets, "_amount > totalAssets");   
        uint256 STYCRVbalance = _balanceSTYCRV();
        //NON-Sandwichable approach to sell investment to repay debt:
        uint256 STYCRVtoUninvest = STYCRVbalance * _amount / totalAssets; //calculate STYCRV investment amount to swap to CRV as a share of the asked total assets
        STYCRVtoUninvest = Math.min(STYCRVbalance, STYCRVtoUninvest);
        console.log("_balanceCollateral(): ", _balanceCollateral());
        uint256 CRVbalance = _uninvestSTYCRVtoCRV(STYCRVtoUninvest);
        console.log("_balanceCollateral(): ", _balanceCollateral());
        CRVbalance = Math.min(_balanceDebt(), CRVbalance);
        if (CRVbalance > 0) {
            lendingPool.repay(CRV, CRVbalance , 2, address(this)); //repay CRV debt with STYCRV to retain LTV after withdraw
            console.log("_balanceCollateral(): ", _balanceCollateral());
        }
        // Calculate final collateralized debt position (CDP) values that we want to achieve to maintain LTV
        uint256 debtBalanceInAsset = _balanceDebtInAsset();
        console.log("debtBalanceInAsset: ", debtBalanceInAsset);
        require(_amount <= collateralBalance, "wait for keeper to realize profits OR redeem less shares"); //extremely unlikely edge case scenario of massive profits, no reports and huge withdrawal: profits need to be realized by keeper to be non-sandwichable
        require(_amount + debtBalanceInAsset <= collateralBalance, "wait for keeper to report losses OR redeem less shares"); //edge case scenario of massive unreported losses
        uint256 finalCDPvalue = collateralBalance - _amount - debtBalanceInAsset;
        if (_amount == totalAssets) { //special case of full withdrawal of all assets out of strategy
            finalCDPvalue = 0;
        }
        console.log("finalCDPvalue: ", finalCDPvalue);
        uint256 finalCollateral = finalCDPvalue * ASSET_UNIT / (WAD - currentLTV);
        console.log("finalCollateral: ", finalCollateral);
        uint256 finalDebtInAsset = finalCollateral - finalCDPvalue;
        console.log("finalDebtInAsset: ", finalDebtInAsset);
        uint256 collateralToUnlock;
        console.log("debtBalanceInAsset: ", debtBalanceInAsset);
        console.log("finalDebtInAsset: ", finalDebtInAsset);
        // Check if we need to sell collateral to pay off debt to maintain LTV
        if (debtBalanceInAsset > finalDebtInAsset){
            if (finalDebtInAsset == 0) { //total debt repayment scenario
                collateralToUnlock = _maxUnlockableCollateral(collateralBalance, debtBalanceInAsset); //unlock collateral only ever up to maximum LTV allowed
                console.log("collateralToUnlock: ", collateralToUnlock);
                lendingPool.withdraw(asset, collateralToUnlock, address(this));
                _swapAssetToExactCRV(_balanceDebt());
            } else { //partial debt repayment scenario
                collateralToUnlock = debtBalanceInAsset - finalDebtInAsset;
                console.log("collateralToUnlock: ", collateralToUnlock);
                collateralToUnlock = Math.min(collateralBalance, collateralToUnlock);
                console.log("collateralToUnlock: ", collateralToUnlock);
                console.log("_balanceCollateral(): ", _balanceCollateral());
                console.log("_CRVbalance: ", _balanceCRV());
                lendingPool.withdraw(asset, collateralToUnlock, address(this));
                console.log("_balanceCollateral(): ", _balanceCollateral());
                _swapAssetToCRV(collateralToUnlock);
            }
            //pay off debt:
            CRVbalance = _balanceCRV();
            if (CRVbalance > 0) {
                console.log("repay: ", Math.min(_balanceDebt(), CRVbalance));
                lendingPool.repay(CRV, Math.min(_balanceDebt(), CRVbalance), 2, address(this)); //repay CRV debt with STYCRV to retain LTV after withdraw
                console.log("debtBalanceInAsset after repay: ", _balanceDebtInAsset());
            }                        
        }
        // Unlock collateral to pay out redeemed shares
        collateralBalance = _balanceCollateral();
        console.log("collateralBalance: ", collateralBalance);
        collateralToUnlock = Math.min(collateralBalance, _amount);
        console.log("collateralToUnlock: ", collateralToUnlock);
        if (collateralToUnlock > 0) {
            console.log("_balanceCollateral(): ", _balanceCollateral());
            console.log("_balanceDebtInAsset: ", _balanceDebtInAsset());
            debtBalanceInAsset = _balanceDebtInAsset();
            console.log("_maxUnlockableCollateral: ", _maxUnlockableCollateral(collateralBalance, debtBalanceInAsset));
            if (debtBalanceInAsset > 0) {
                require(collateralToUnlock <= _maxUnlockableCollateral(collateralBalance, debtBalanceInAsset), "wait for keeper to adjust LTV OR redeem less shares");
            }
            lendingPool.withdraw(asset, collateralToUnlock, address(this));
            console.log("_balanceCollateral(): ", _balanceCollateral());
        }
        //LTV check:
        require(_LTV() < LTVborrowLessNow, "LTV too high after redeem: redeem less shares & wait for keeper to report");
        console.log("_balanceCollateral(): ", _balanceCollateral());
        console.log("_CRVtoAsset(_balanceDebt()): ", _balanceDebtInAsset());
    }

    function _maxUnlockableCollateral(uint256 _collateralBalance, uint256 _debtBalanceInAsset) internal returns (uint256) {
        if (_debtBalanceInAsset == 0) {
            return _collateralBalance;
        }
        (, uint256 maxLTV, uint256 LT, , , , , , , ) = protocolDataProvider.getReserveConfigurationData(asset);
        maxLTV = maxLTV * 1e14;
        LT = LT * 1e14; //liquidation threshold
        return _collateralBalance - _debtBalanceInAsset * WAD / (LT - 5e14); //unlock collateral only ever up to LT-2e14 (exactly LT would revert, so we need LT in BPS -2BPS)
    }

/*
    function _freeFundsOLD(uint256 _amount) internal override {
        uint256 collateralBalance = _balanceCollateral();
        //NON-Sandwichable approach:        
        //uint256 STYCRVtoUninvest = _balanceSTYCRV() * _amount / collateralBalance; //calculate STYCRV investment amount to swap to CRV as a share of the asked collateral
        uint256 STYCRVtoUninvest = _balanceSTYCRV() * _amount / TokenizedStrategy.totalAssets(); //calculate STYCRV investment amount to swap to CRV as a share of the asked collateral
        uint256 CRVbalance = _uninvestSTYCRVtoCRV(STYCRVtoUninvest);
        CRVbalance = Math.min(_balanceDebt(), CRVbalance);
        if (CRVbalance > 0) {
            lendingPool.repay(CRV, CRVbalance , 2, address(this)); //repay CRV debt with STYCRV to retain LTV after withdraw
        }
        lendingPool.withdraw(asset, Math.min(_balanceCollateral(), _amount), address(this));
        //LTV check:
        require(_LTV() < LTVborrowLessNow, "LTV too high!");
    }
*/

    /**
     * @dev Internal non-view function to harvest all rewards, reinvest
     * and return the accurate amount of funds currently held by the Strategy.
     *
     * This should do any needed harvesting, rewards selling, accrual,
     * reinvesting etc. to get the most accurate view of current assets.
     *
     * All applicable assets including loose assets should be accounted
     * for in this function.
     *
     * @return _invested A trusted and accurate account for the total
     * amount of 'asset' the strategy currently holds.
     *
     *
     * call: keeper harvests & asks for accurate current assets after harvest
     */
    function _totalInvested() internal override returns (uint256 _invested) {
        // Claim and sell any STKAAVE rewards to `asset`.
        //_claimAndSellRewards();

        _realizeProfitsOrCheckAnyLoss();

        // deposit any loose funds
        uint256 looseAsset = _balanceAsset();
        uint256 assetAmountUntilCeiling = _amountUntilCeilingATokenSupply();
        looseAsset = Math.min(assetAmountUntilCeiling, looseAsset);
        if (looseAsset > 0 && !TokenizedStrategy.isShutdown()) {
            lendingPool.supply(asset, looseAsset, address(this), 0);
        }

        // LTV checks:
        uint256 currentLTV = _LTV();

        //check if target LTV is still acceptable or needs to be updated
        (, uint256 maxLTV, uint256 LT, , , , bool borrowingEnabled, , bool isActive, bool isFrozen) = protocolDataProvider.getReserveConfigurationData(asset);
        maxLTV = maxLTV * 1e14;
        LT = LT * 1e14;
        if (LTVtarget != LT - DiffFromLTtarget || LTVtarget > maxLTV) { //LTVtarget should be a distance from liquidation threshold AND below maxLTV
            require(False, "LTVTARGET ERROR!");
            LTVborrowLessNow = LT - DiffFromLTborrowLessNow;
            LTVborrowLess = LT - DiffFromLTborrowLess;
            LTVtarget = LT - DiffFromLTtarget;
            LTVborrowMore = LT - DiffFromLTborrowMore;
        }
        
        //check if borrowLess or borrowMore
        if (currentLTV > LTVtarget) {
            _borrowLess();
        } else if (currentLTV < LTVborrowMore && currentLTV < maxLTV && borrowingEnabled && isActive && !isFrozen) {
            _borrowMore();
        }
        require(_LTV() < LTVborrowLessNow, "LTV too high!");
        _invested = _balanceAsset()  + _balanceCollateral() + _STYCRVtoAsset(_balanceSTYCRV()) - _balanceDebtInAsset();
    }

    //call: keeper tracks to tend if true
    function tendTrigger() external view override returns (bool) {
        //sell collateral?
        uint256 debtBalanceInCRV = _balanceDebt();
        uint256 investmentValueInCRV = _STYCRVtoCRV(investmentValueInSTYCRV);
        if (investmentValueInCRV < debtBalanceInCRV * (MAX_BPS - minLossToSellCollateralBPS) / MAX_BPS ){
            return true;
        }

        //LTV checks:
        uint256 currentLTV = _LTV();
        (, uint256 maxLTV, , , , , bool borrowingEnabled, , bool isActive, bool isFrozen) = protocolDataProvider.getReserveConfigurationData(asset);
        maxLTV = maxLTV * 1e14;

        //borrowLess ignoring gas?
        if (currentLTV > LTVborrowLessNow) {
            return true;
        }
        
        //is gas acceptable?
        if (/*gas check*/false) {
            return false;
        }
        
        //borrowLess considering gas?
        if (currentLTV > LTVborrowLess) {
            return true;
        }

        //borrowMore considering gas? borrowing enabled? borrow rate good? active & not frozen?
        if (currentLTV < LTVborrowMore && currentLTV < maxLTV && borrowingEnabled && isActive && !isFrozen) {
            return true;
        }
        /*
        //tend LTV lever up, after gas check
        if (_get_weth_borrow_rate() <= max_weth_borrow_rate && wsteth_collateral_ > MEANINGFUL_COLLATERAL) {
            return true;
        }*/
        
        //time since last report?
        //check here

        return false;
    }

    function _realizeProfitsOrCheckAnyLoss() internal {
        uint256 investmentValueInSTYCRV = _balanceSTYCRV();
        console.log("investmentValueInSTYCRV: ", investmentValueInSTYCRV);
        uint256 debtBalanceInCRV = _balanceDebt();
        uint256 debtBalanceInSTYCRV = _CRVtoSTYCRV(debtBalanceInCRV);
        console.log("debtBalanceInSTYCRV: ", debtBalanceInSTYCRV);
        // Investment profit check --> realize profits
        if (investmentValueInSTYCRV > debtBalanceInSTYCRV) {
            _uninvestSTYCRVtoCRV(investmentValueInSTYCRV - debtBalanceInSTYCRV); //uninvest STYCRV profit into CRV amount
            _swapCRVtoAsset(_balanceCRV());
            return;
        } 
        // Investment loss check --> sell collateral, repay partly debt, increase investment to make up for loss and stay delta neutral
        uint256 investmentValueInCRV = _STYCRVtoCRV(investmentValueInSTYCRV);
        if (investmentValueInCRV < debtBalanceInCRV * (MAX_BPS - minLossToSellCollateralBPS) / MAX_BPS ) {
            uint256 collateralBalance = _balanceCollateral();
            console.log("collateralBalance: ", collateralBalance);
            uint256 debtBalanceInAsset = _CRVtoAsset(debtBalanceInCRV);
            console.log("debtBalanceInAsset: ", debtBalanceInAsset);
            uint256 investmentValueInAsset = _CRVtoAsset(investmentValueInCRV);
            console.log("investmentValueInAsset: ", investmentValueInAsset);
            uint256 collateralToUnlock = debtBalanceInAsset - investmentValueInAsset;
            console.log("collateralToUnlock: ", collateralToUnlock);
            collateralToUnlock = Math.min(_maxUnlockableCollateral(collateralBalance, debtBalanceInAsset), collateralToUnlock); //unlock collateral only ever up to maximum LTV allowed
            console.log("collateralToUnlock: ", collateralToUnlock);
            lendingPool.withdraw(asset, collateralToUnlock, address(this)); //withdraw collateral to free asset
            console.log("_balanceAsset(): ", _balanceAsset());
            _swapAssetToCRV(collateralToUnlock); //swap asset to CRV to first repay debt and then invest rest
            uint256 idealDebtInAsset = (collateralBalance - collateralToUnlock) * LTVtarget / WAD;
            console.log("idealDebtInAsset: ", idealDebtInAsset);
            uint256 idealDebtInCRV = _assetToCRV(idealDebtInAsset);
            console.log("idealDebtInCRV: ", idealDebtInCRV);
            uint256 debtBalance = _balanceDebt();
            console.log("debtBalance: ", debtBalance);
            if (debtBalance < idealDebtInCRV) {
                console.log("borrow: ", idealDebtInCRV - debtBalance);
                lendingPool.borrow(CRV, idealDebtInCRV - debtBalance, 2, 0, address(this)); //borrow CRV
            } else if (debtBalance > idealDebtInCRV) {
                console.log("repay: ", debtBalance - idealDebtInCRV);
                uint256 CRVrepayAmount = Math.min(_balanceCRV(), debtBalance - idealDebtInCRV);
                if (CRVrepayAmount > 0){
                    lendingPool.repay(CRV, Math.min(_balanceDebt(), CRVrepayAmount), 2, address(this)); //repay debt with part of the CRV
                }
            }
            uint256 CRVbalance = _balanceCRV(); //check what's left to invest
            console.log("CRVbalance: ", CRVbalance);
            if (CRVbalance > CRV_DUST) {
                console.log("CRVbalance: ", CRVbalance);
                _swapCRVtoYCRV(CRVbalance); //swap CRV to YCRV
                IVault(STYCRV).deposit(); //deposit all YCRV into STYCRV
            }
            console.log("FINALcollateralBalance: ", _balanceCollateral());
            console.log("FINALdebtBalanceInAsset: ", _balanceDebtInAsset());
            console.log("FINALinvetment: ", _STYCRVtoAsset(_balanceSTYCRV()));
            console.log("FINALLTV: ", _LTV());
        }
    }

    function _amountUntilCeilingATokenSupply() internal view returns (uint256) {
        uint256 aTokenCap = protocolDataProvider.getReserveCaps(asset)[1] * ASSET_UNIT;
        uint256 aTokenCurrentSupply = aToken.totalSupply();
        if (aTokenCurrentSupply + ASSET_UNIT >= aTokenCap) {
            return 0;
        } else {
            return aTokenCap - aTokenCurrentSupply - ASSET_UNIT;
        }
    }

    function _amountUntilHighUtilizationOfATokenBorrowSupply() internal view returns (uint256) {
        uint256 aTokenBorrowCurrentSupply = aTokenBorrow.totalSupply();
        uint256 dTokenCurrentSupply = dToken.totalSupply();
        if (aTokenBorrowCurrentSupply * maxUtilizationRateBPS/MAX_BPS < dTokenCurrentSupply){
            return 0;
        }
        return aTokenBorrowCurrentSupply * maxUtilizationRateBPS/MAX_BPS - dTokenCurrentSupply;
    }

    function _amountUntilCeilingDTokenBorrowing() internal view returns (uint) {
        uint dTokenCap = protocolDataProvider.getReserveCaps(CRV)[0] * CRV_UNIT;
        uint dTokenCurrentSupply = dToken.totalSupply();
        if (dTokenCurrentSupply + CRV_UNIT >= dTokenCap) {
            return 0;
        } else {
            return dTokenCap - dTokenCurrentSupply - CRV_UNIT;
        }
    }

    function _borrowMore() internal {
        uint256 collateralBalance = _balanceCollateral();
        uint256 debtBalanceInAsset = _balanceDebtInAsset();
        uint256 assetAmountToBorrow = collateralBalance * LTVtarget / WAD - debtBalanceInAsset; //asset amount to borrow to achieve LTV target
        uint256 CRVtoBorrow = _assetToCRV(assetAmountToBorrow); //CRV amount to borrow to achieve LTV target
        //check for maxSingleTrade:
        CRVtoBorrow = Math.min(maxSingleTrade, CRVtoBorrow);
        //check for high utilization rate:
        CRVtoBorrow = Math.min(_amountUntilHighUtilizationOfATokenBorrowSupply(), CRVtoBorrow);
        //check for borrow ceiling: 
        CRVtoBorrow = Math.min(_amountUntilCeilingDTokenBorrowing(), CRVtoBorrow);
        if (CRVtoBorrow > CRV_DUST) {
            lendingPool.borrow(CRV, CRVtoBorrow, 2, 0, address(this)); //borrow CRV
            _swapCRVtoYCRV(CRVtoBorrow); //swap CRV to YCRV
            IVault(STYCRV).deposit(); //deposit all YCRV into STYCRV
        }
    }

    function _borrowLess() internal {
        uint256 collateralBalance = _balanceCollateral();
        uint256 debtBalanceInAsset = _balanceDebtInAsset();
        uint256 assetAmountToRepay = debtBalanceInAsset - collateralBalance * LTVtarget / WAD; //asset amount to repay to achieve LTV target
        uint256 CRVtoRepay = _assetToCRV(assetAmountToRepay); //CRV amount to repay to achieve LTV target
        _repayDebtWithSTYCRV(CRVtoRepay);
    }

    function _repayDebtWithSTYCRV(uint256 _CRVtoRepay) internal {
        uint256 YCRVtoSwap = _YCRVforExactCRV(_CRVtoRepay); //calculate YCRV amount to swap to get CRV
        uint256 STYCRVtoUninvest = _YCRVtoSTYCRV(YCRVtoSwap); //calculate STYCRV amount to uninvest to get enough YCRV to swap to get CRV
        uint256 CRVbalance = _uninvestSTYCRVtoCRV(STYCRVtoUninvest);
        lendingPool.repay(CRV, Math.min(_balanceDebt(), CRVbalance), 2, address(this)); //repay CRV debt to retain LTV after withdraw with max repay full debt check
        _swapCRVtoAsset(_balanceCRV()); //in case there is a CRV surplus: swap to asset
    }
    
    function _uninvestSTYCRVtoCRV(uint256 _STYCRVtoUninvest) internal returns (uint256) {
        _STYCRVtoUninvest = Math.min(_balanceSTYCRV(), _STYCRVtoUninvest); //max uninvest total STYCRV holdings
        if (_STYCRVtoUninvest > 0) {
            IVault(STYCRV).withdraw(_STYCRVtoUninvest, address(this), maxLossBPS); //uninvest STYCRV to get YCRV
            return _swapYCRVtoCRV(_balanceYCRV()); //swap YCRV to CRV
        } else {
            return 0;
        }
        
    }

    function _swapAssetToCRV(uint256 _assetAmount) internal returns (uint256 /*_amountOut*/) {
        if (_assetAmount == 0) {return 0;}
        return _swapFrom(asset, CRV, _assetAmount, _assetToCRV(_assetAmount) * (MAX_BPS - swapSlippageAssetCRVBPS) / MAX_BPS);
    }

    function _swapAssetToExactCRV(uint256 _CRVamount) internal returns (uint256 /*_amountIn*/) {
        if (_CRVamount < CRV_DUST) {return 0;}
        return _swapTo(asset, CRV, _CRVamount, _CRVtoAsset(_CRVamount) * (MAX_BPS + swapSlippageAssetCRVBPS) / MAX_BPS);
    }

    function _swapCRVtoAsset(uint256 _CRVamount) internal returns (uint256 /*_amountOut*/) {
        if (_CRVamount < CRV_DUST) {return 0;}
        return _swapFrom(CRV, asset, _CRVamount, _CRVtoAsset(_CRVamount) * (MAX_BPS - swapSlippageAssetCRVBPS) / MAX_BPS);
    }

    //call: keeper tends
    function _tend(uint256 _totalIdle) internal override {


    }



    function availableDepositLimit(address /*_owner*/) public view override returns (uint256) {
        return Math.min(maxSingleTrade, _amountUntilCeilingATokenSupply());
    }

    function availableWithdrawLimit(address /*_owner*/) public view override returns (uint256) {
        return maxSingleTrade;
    }

    /*//////////////////////////////////////////////////////////////
                INTERNAL:
    //////////////////////////////////////////////////////////////*/

    function _balanceAsset() internal view returns (uint256) {
        return ERC20(asset).balanceOf(address(this));
    }

    function _balanceCollateral() internal view returns (uint256) {
        return aToken.balanceOf(address(this));
    }

    function _balanceDebt() internal view returns (uint256) {
        return dToken.balanceOf(address(this));
    }

    function _balanceDebtInAsset() internal view returns (uint256) {
        return _CRVtoAsset(_balanceDebt());
    }

    function _balanceCRV() internal view returns (uint256) {
        return ERC20(CRV).balanceOf(address(this));
    }

    function _balanceYCRV() internal view returns (uint256) {
        return ERC20(YCRV).balanceOf(address(this));
    }

    function _balanceSTYCRV() internal view returns (uint256) {
        return IVault(STYCRV).balanceOf(address(this));
    }

    function _LTV() internal view returns (uint) {
        uint256 collateralBalance = _balanceCollateral();
        return collateralBalance == 0 ? 0 : _balanceDebtInAsset() * ASSET_UNIT / collateralBalance;
    }

    function _oracle(uint256 amount, address asset0, address asset1) internal view returns (uint256) {
        if (amount == 0){return 0;}
        address[] memory assets = new address[](2); 
        assets[0] = asset0;
        assets[1] = asset1;
        uint[] memory prices = new uint[](2);
        prices = oracle.getAssetsPrices(assets);
        return amount * prices[0] / prices[1];
    }

    function _assetToCRV(uint256 _assetAmount) internal view returns (uint256) {
        return _oracle(_assetAmount, asset, CRV);
    }

    function _CRVtoAsset(uint256 _CRVamount) internal view returns (uint256) {
        return _oracle(_CRVamount, CRV, asset);
    }

    function _YCRVtoCRV(uint256 _YCRVamount) internal view returns (uint256) {
        if (_YCRVamount == 0){return 0;}
        return curve_CRV_YCRV.get_dy(1, 0, _YCRVamount);
    }

    function _CRVtoYCRV(uint256 _CRVamount) internal view returns (uint256) {
        if (_CRVamount == 0){return 0;}
        return curve_CRV_YCRV.get_dy(0, 1, _CRVamount);
    }

    function _STYCRVtoCRV(uint256 _STYCRVamount) internal view returns (uint256) {
        return _YCRVtoCRV(_STYCRVtoYCRV(_STYCRVamount));
    }

    function _CRVtoSTYCRV(uint256 _CRVamount) internal view returns (uint256) {
        return _YCRVtoSTYCRV(_CRVtoYCRV(_CRVamount));
    }

    function _STYCRVtoAsset(uint256 _STYCRVamount) internal view returns (uint256) {
        return _CRVtoAsset(_STYCRVtoCRV(_STYCRVamount)); 
    }

    function _YCRVtoSTYCRV(uint256 _YCRVamount) internal view returns (uint256) {
        return _YCRVamount * WAD / IVault(STYCRV).pricePerShare();
    }

    function _STYCRVtoYCRV(uint256 _STYCRVamount) internal view returns (uint256) {
        return _STYCRVamount * IVault(STYCRV).pricePerShare() / WAD;
    }

    function _swapCRVtoYCRV(uint256 _CRVamount) internal returns (uint256) {
        return curve_CRV_YCRV.exchange(0, 1, _CRVamount, _CRVamount * (MAX_BPS - swapPriceDepegCRVYCRVBPS) / MAX_BPS);
    }

    function _swapYCRVtoCRV(uint256 _YCRVamount) internal returns (uint256) {
        return curve_CRV_YCRV.exchange(1, 0, _YCRVamount, _YCRVamount * (MAX_BPS - swapPriceDepegCRVYCRVBPS) / MAX_BPS);
    }

    struct CurveCalcParams {
        uint[8] balances;
        uint amp;
        uint fee;
        uint[8] rates;
        uint[8] precisions;
    }
    
    function _YCRVforExactCRV(uint256 _CRVamount) internal view returns (uint256) {
        //curve_CRV_YCRV: i = YCRV = 1, j = CRV = 0;
        CurveCalcParams memory params;
        params.balances[0] = curve_CRV_YCRV.balances(0); //independent of i, j
        params.balances[1] = curve_CRV_YCRV.balances(1); //independent of i, j
        if (params.balances[uint(int256(0))] < _CRVamount){ return type(uint256).max; } //check j for liquidity
        params.rates[0] = WAD;
        params.rates[1] = WAD;
        params.precisions[0] = 1;
        params.precisions[1] = 1;
        params.amp = curve_CRV_YCRV.A();
        params.fee = curve_CRV_YCRV.fee();
        return curveCalc.get_dx(2, params.balances, params.amp, params.fee, params.rates, params.precisions, false, 1, 0, _CRVamount + 2); //i, j
    }

    /*//////////////////////////////////////////////////////////////
                EXTERNAL:
    //////////////////////////////////////////////////////////////*/

    function balanceAsset() external view returns (uint256) {
        return _balanceAsset();
    }

    function balanceCollateral() external view returns (uint256) {
        return _balanceCollateral();
    }

    function balanceDebt() external view returns (uint256) {
        return _balanceDebt();
    }

    function LTV() external view returns (uint256) {
        return _LTV();
    }

    function balanceCRV() external view returns (uint256) {
        return _balanceCRV();
    }

    function balanceYCRV() external view returns (uint256) {
        return _balanceYCRV();
    }

    function balanceSTYCRV() external view returns (uint256) {
        return _balanceSTYCRV();
    }

    function CRVtoAsset(uint256 _CRVAmount) external view returns (uint256) {
        return _CRVtoAsset(_CRVAmount);
    }

    function assetToCRV(uint256 _assetAmount) external view returns (uint256) {
        return _assetToCRV(_assetAmount);
    }

    function YCRVtoCRV(uint256 _YCRVamount) external view returns (uint256) {
        return _YCRVtoCRV(_YCRVamount);
    }

    function STYCRVtoYCRV(uint256 _STYCRVAmount) external view returns (uint256) {
        return _STYCRVtoYCRV(_STYCRVAmount);
    }

    function STYCRVtoAsset(uint256 _STYCRVAmount) external view returns (uint256) {
        return _STYCRVtoAsset(_STYCRVAmount);
    }

    function migrateToNewSTYCRV(address _newSTYCRV) external onlyManagement {
        uint256 STYCRVBalance = _balanceSTYCRV();
        if (STYCRVBalance > 0) {
            IVault(STYCRV).withdraw(STYCRVBalance, address(this), maxLossBPS);
        }
        ERC20(YCRV).safeApprove(STYCRV, 0);
        STYCRV = _newSTYCRV;
        ERC20(YCRV).safeApprove(_newSTYCRV, type(uint256).max);
        IVault(_newSTYCRV).deposit();
    }

    // Max deposit and withdraw size in asset:
    function setMaxSingleTrade(uint256 _maxSingleTrade) external onlyManagement {
        maxSingleTrade = _maxSingleTrade;
    }

    // Max slippage in basis points to accept when swapping CRV <-> YCRV:
    function setSwapPriceDepegCRVYCRVBPS(uint256 _swapPriceDepegCRVYCRVBPS) external onlyManagement {
        require(_swapPriceDepegCRVYCRVBPS <= MAX_BPS);
        swapPriceDepegCRVYCRVBPS = _swapPriceDepegCRVYCRVBPS;
    }

    // Max slippage in basis points to accept when swapping asset <-> CRV:
    function setSwapSlippageAssetCRVBPS(uint256 _swapSlippageAssetCRVBPS) external onlyManagement {
        require(_swapSlippageAssetCRVBPS <= MAX_BPS);
        swapSlippageAssetCRVBPS = _swapSlippageAssetCRVBPS;
    }

    // Min loss of investment vs. debt in basis points to collateral selling:
    function setMinLossToSellCollateralBPS(uint256 _minLossToSellCollateralBPS) external onlyManagement {
        require(_minLossToSellCollateralBPS <= MAX_BPS);
        minLossToSellCollateralBPS = _minLossToSellCollateralBPS;
    }

    // Max loss in basis points to accept when withdrawing from STYCRV:
    function setMaxLossBPS(uint256 _maxLossBPS) external onlyManagement {
        require(_maxLossBPS <= MAX_BPS);
        maxLossBPS = _maxLossBPS;
    }

    // Max utilization rate for borrowing:
    function setMaxUtilizationRateBPS(uint256 _maxUtilizationRateBPS) external onlyManagement {
        require(_maxUtilizationRateBPS <= MAX_BPS);
        maxUtilizationRateBPS = _maxUtilizationRateBPS;
    }

    function emergencyWithdraw(uint256 _amount) external onlyManagement {
        lendingPool.withdraw(asset, _amount, address(this));
    }

    function cloneStrategy(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newStrategy) {
        // Use the cloning logic held withen the Base library.
        newStrategy = TokenizedStrategy.clone(
            _asset,
            _name,
            _management,
            _performanceFeeRecipient,
            _keeper
        );
        // Neeed to cast address to payable since there is a fallback function.
        Strategy(payable(newStrategy)).initializeStrategy(_asset);
    }











    /*//////////////////////////////////////////////////////////////
               AAVE TOKEN & STKAAVE TOKEN FUNCTIONS:
    //////////////////////////////////////////////////////////////*/

    
    function _claimAndSellRewards() internal {
        // Need to redeem any aave from StkAave if applicable before
        // claiming rewards and staring cool down over
        _redeemAave();

        //claim all rewards
        address[] memory assets = new address[](1);
        assets[0] = address(aToken);
        (address[] memory rewardsList, ) = rewardsController
            .claimAllRewardsToSelf(assets);

        //swap as much as possible back to want
        address token;
        for (uint256 i = 0; i < rewardsList.length; ++i) {
            token = rewardsList[i];

            if (token == address(stkAave)) {
                _harvestStkAave();
            } else if (token == asset) {
                continue;
            } else {
                _swapFrom(
                    token,
                    asset,
                    ERC20(token).balanceOf(address(this)),
                    0
                );
            }
        }
    }

    function _redeemAave() internal {
        if (!_checkCooldown()) {
            return;
        }

        uint256 stkAaveBalance = ERC20(address(stkAave)).balanceOf(
            address(this)
        );

        if (stkAaveBalance > 0) {
            stkAave.redeem(address(this), stkAaveBalance);
        }

        // sell AAVE for want
        _swapFrom(AAVE, asset, ERC20(AAVE).balanceOf(address(this)), 0);
    }

    function _checkCooldown() internal view returns (bool) {
        if (block.chainid != 1) {
            return false;
        }

        uint256 cooldownStartTimestamp = IStakedAave(stkAave).stakersCooldowns(
            address(this)
        );

        if (cooldownStartTimestamp == 0) return false;

        uint256 COOLDOWN_SECONDS = IStakedAave(stkAave).COOLDOWN_SECONDS();
        uint256 UNSTAKE_WINDOW = IStakedAave(stkAave).UNSTAKE_WINDOW();
        if (block.timestamp >= cooldownStartTimestamp + COOLDOWN_SECONDS) {
            return
                block.timestamp - (cooldownStartTimestamp + COOLDOWN_SECONDS) <=
                UNSTAKE_WINDOW;
        } else {
            return false;
        }
    }

    function _harvestStkAave() internal {
        // request start of cooldown period
        if (ERC20(address(stkAave)).balanceOf(address(this)) > 0) {
            stkAave.cooldown();
        }
    }

    function manualRedeemAave() external onlyKeepers {
        _redeemAave();
    }
    
}
