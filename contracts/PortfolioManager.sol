pragma solidity 0.5.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Curve.sol";

contract PortfolioManager is Ownable {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Contract owner for Admin functionality.
    address public owner;

    // susd pool, Y pool and DAI addresses.
    address constant public DAI = address(0x6b175474e89094c44da98b954eedeac495271d0f);
    address constant public susdPool = address(0xFCBa3E75865d2d561BE8D220616520c171F12851); // susd pool Deposit Contract
    address constant public yPool = address(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3); // Y pool Deposit Contract
    address constant public sCRV = address(0xC25a3A3b969415c80451098fa907EC722572917F); // susd LP token
    address constant public yCRV = address(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8); // Y LP token

    // Pool arrays for verified and whitelisted Curve pools
    address[] public verifiedPools;
    address[] public whitelistedPools;

    // Pool weights
    uint public susdWeight;
    uint public yWeight;

    // Pool DAI Liquidity
    uint256 public susdLiquidity;
    uint256 public yLiquidity;

    // EVENTS
    event PoolWhitelisted(address indexed pool);
    event PoolWeights(uint susdWeight, uint yWeight);
    event Deposit(address indexed sender, address indexed pool, uint256 amount);
    event Rebalance(uint256 amount, address indexed pool);

    // CONSTRUCTOR
    constructor(uint _susdWeight, uint _yWeight) public {
        // Init contract owner
        owner = msg.sender;
        // Init susd and Y pool weights
        susdWeight = _susdWeight;
        yWeight = _yWeight;
        // Init pool liquidity
        susdLiquidity = 0;
        yLiquidity = 0;
        // Init verified pools (susd and Y pool only)
        verifiedPools.push(susdPool);
        verifiedPools.push(yPool);
    }

    // ADMIN ACTIONS

    // 1 - Whitelist a new curve pool

    /**
    * @notice Whitelist a new pool that Curve adds
    * @dev Only contract owner can call this function
    * @param pools Address array of curve pool addresses
    */
    function whitelistPool(address[] memory pools) public onlyOwner {
        for (uint i = 0; i < pools.length; i++) {
            _whitelistPool(pools[i]);
        }
    }

    // 2 - Set desired weight for liquidity allocation across pools (completed)

    /**
    * @notice Set the weights for portfoio allocation between susd and Y pools
    * @dev Only contract owner can call this function
    * @param _susdWeight Weight allocation of susd pool
    * @param _yWeight Weight allocation of Y pool
    * @return boolean value of true if execution was successful
    */
    function poolWeights(uint8 _susdWeight, uint8 _yWeight) public onlyOwner returns (bool) {
        // Verify weights are set differantly
        require(susdWeight != _susdWeight && yWeight != _yWeight, "Error: Weights already set to current value.");
        // Verify weights add up (100%)
        require(_susdWeight + _yWeight == 100, "Error: Invalid pool weights.");
        // Set pool weights
        susdWeight = _susdWeight;
        yWeight = _yWeight;
        // Emit event
        emit PoolWeights(susdWeight, yWeight);
        return true;
    }

    // USER ACTIONS

    // 3 - Add liquidity to any pool (Y-pool & SUSD)

    /**
    * @notice Add liquidity to either susd or Y pool
    * @dev Anyone has the ability to add liquidity to susd or Y pool
    * @param pool Address of the susd or Y pool deposit contracts
    * @return boolean value of true if execution was successful
    */
    function addLiquidity(address pool, uint inAmount) public returns (bool) {
        // Verify pool address
        require(pool == susdPool || pool == yPool, "Error: Invalid pool address.")
        // DAI balance in user address.
        uint _dai = IERC20(DAI).balanceOf(msg.sender);
        // Deposit DAI in pools.
        if (_dai > inAmount) {
            // Deposit DAI in susd pool.
            if (pool == susdPool) {
                // susd pool deposit
                IERC20(DAI).safeTransferFrom(msg.sender, address(this), inAmount);
                ICurveDeposit(susdPool).add_liquidity([inAmount,0,0,0], 0);
                // Update susd pool Liquidity
                susdLiquidity = susdLiquidity.add(inAmount);
            }
            else if (pool == yPool){
                // y pool deposit
                IERC20(DAI).safeTransferFrom(msg.sender, address(this), inAmount);
                ICurveDeposit(yPool).add_liquidity([inAmount,0,0,0], 0); // DAI => yDAI done by deposit contract
                // Update Y pool liquidity
                yLiquidity = yLiquidity.add(inAmount);
            }
        }
        // Emit event
        emit Deposit(msg.sender, pool, inAmount);
        return true;
    }

    // 4 - Rebalance
    // Description: Remove liquidity from 1 curve pool and provides liquidity to another
    // to rebalance portfolio according to weights in actions 2

    // TODO

    // 2) Calculate % distribution of LP tokens
    // 3) Readjust balance accordingly (remove_liquidity() & deposit(liquidity))

    /**
    * @notice Rebalances portfolio of LP tokens set by Admin
    * @dev Public function called periodically
    * @return boolean value of true once protfolio rebalance is complete
    */
    function rebalance() public returns (bool) {
        // Calculates % allocation between susd and Y pool.
        uint sCRV_Balance = IERC20(sCRV).balanceOf(address(this));
        uint yCRV_Balance = IERC20(yCRV).balanceOf(address(this));
        uint totalLP_Balance = sCRV_Balance.add(yCRV_Balance);
        // ASSUME 1 sCRV = 1 yCRV (% = total * percentage / 100)
        uint sCRV_Allocation = (totalLPBalance.mul(sCRV_Balance)).div(100);
        uint yCRV_Allocation = (totalLPBalance.mul(yCRV_Balance)).div(100);
        // Compare % allocation with desired pool weights.
        if (sCRV_Allocation > susdWeight) {
            // Calculate excess sCRV tokens
            uint sCRV_Excess = totalLPBalance.div(sCRV_Allocation.sub(susdWeight));
            // Withdraw sCRV from susd pool
            ICurveDeposit(susdPool).remove_liquidity(sCRV_Excess, [0,0,0,0]);
            // Reallocate DAI into Y pool
            uint _dai = IERC20(DAI).balanceOf(address(this));
            if (_dai >= sCRV_Excess){
                // Deposit sCRV excess into Y Pool
                ICurveDeposit(yCRV).add_liquidity([sCRV_Excess,0,0,0],0);
                // Update liquidity pools
                susdLiquidity = susdLiquidity.sub(sCRV_Excess);
                yLiquidity = yLiquidity.add(sCRV_Excess);
            }
            // Emit event
            emit Rebalance(sCRV_Excess, susdPool);
        }
        if (yCRV_Allocation > yWeight) {
            // Calculate excess yCRV
            uint yCRV_Excess = totalLPBalance.div(yCrv_Allocation.sub(yWeight));
            // Withdraw yCRV from Y pool
            ICurveDeposit(ypool).remove_liquidity(yCRV_Excess, [0,0,0,0]);
            // Reallocate DAI in susd pool via deposit
            uint _dai = IERC20(DAI).balanceOf(address(this));
            if (_dai >= yCRV_Excess) {
                ICurveDeposit(yCRV).add_liquidity([sCRV_Excess,0,0,0],0);
                // Update liquidity pools
                susdLiquidity = susdLiquidity.sub(sCRV_Excess);
                yLiquidity = yLiquidity.add(sCRV_Excess);
            }
            // Emit event
            emit Rebalance(yCRV_Excess, yPool);
        }
        return true;
    }

    // Returns current pool weighting set by Admin.
    function getPoolWeights() public view returns (uint256, uint256) {
        return (susdWeight, yWeight);
    }

    // DAI balance of the susd pool.
    function susdDAIBalance() public view returns (uint256) {
        return susdLiquidity;
    }

    // DAI balance of the Y pool.
    function yDAIBalance() public view returns (uint256) {
        return yLiquidity;
    }

    // Function called internally to verify pool has not already been verified.
    function _whitelistPool(address pool) internal {
        for (uint i = 0; i < whitelistedPools.length; i++) {
            require(whitelistedPools[i] != pool);
        }
        whitelistedPools.push(pool);
        emit PoolWhitelisted(pool);
    }

}
