// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IUniswapV3Swapper} from "@periphery/swappers/interfaces/IUniswapV3Swapper.sol";

interface IStrategyInterface is IStrategy, IUniswapV3Swapper {
    function initializeAaveV3Lender(address _asset) external;

    function setUniFees(address _token0, address _token1, uint24 _fee) external;

    function setMinAmountToSell(uint256 _minAmountToSell) external;

    function manualRedeemAave() external;

    function emergencyWithdraw(uint256 _amount) external;

    function cloneAaveV3Lender(
        address _asset,
        string memory _name,
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external returns (address newLender);

    function aToken() external view returns (address);
    function balanceAsset() external view returns (uint256);
    function balanceCollateral() external view returns (uint256);
    function balanceDebt() external view returns (uint256);
    function balanceSTYCRV() external view returns (uint256);
    function CRVtoAsset(uint256 _CRVAmount) external view returns (uint256);
    function STYCRVtoYCRV(uint256 _STYCRVAmount) external view returns (uint256);
    function YCRVtoCRV(uint256 _YCRVAmount) external view returns (uint256);
    function STYCRVtoAsset(uint256 _STYCRVAmount) external view returns (uint256);

    function LTVborrowLessNow() external view returns (uint256);
    function LTVborrowLess() external view returns (uint256);
    function LTVtarget() external view returns (uint256);
    function LTVborrowMore() external view returns (uint256);

    function LTV() external view returns (uint256);
    function setLTV(uint256 _LTVborrowLessNowFromLT, uint256 _LTVborrowLessFromLT, uint256 _LTVtargetFromLT, uint256 _LTVborrowMoreFromLT) external;

    function setMinLossToSellCollateralBPS(uint256 _minLossToSellCollateralBPS) external;

    function maxSingleTrade() external view returns (uint256);
}
