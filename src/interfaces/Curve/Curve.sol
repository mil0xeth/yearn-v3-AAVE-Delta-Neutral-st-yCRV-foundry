// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

interface ICurve {
    function exchange(
        int128 from,
        int128 to,
        uint256 _from_amount,
        uint256 _min_to_amount
    ) external returns (uint256);

    function balances(uint256) external view returns (uint256);

    function get_dy(
        int128 from,
        int128 to,
        uint256 _from_amount
    ) external view returns (uint256);
    function A() external view returns (uint);
    function fee() external view returns (uint);
}

interface ICurveCalc {
    function get_dx(int128 n_coins, uint[8] calldata balances, uint amp, uint fee, uint[8] calldata rates, uint[8] calldata precisions, bool underlying, int128 i_from, int128 j_to, uint dy) external view returns (uint);
}
