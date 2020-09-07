pragma solidity 0.5.17;

interface ICurveDeposit {
    function add_liquidity(uint[4] calldata uamounts, uint min_mint_amount) external;
    function remove_liquidity(uint256 _amount. uint256[4] min_uamounts) external;
    function remove_liquidity_one_coin(uint _token_amount, int128 i, uint min_uamount) external; // Optimal function for DAI withdrawl
}