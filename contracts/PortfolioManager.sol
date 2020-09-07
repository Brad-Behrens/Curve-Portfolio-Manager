pragma solidity ^0.5.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/Curve.sol";

contract PortfolioManager {

    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Contract owner for Admin functionality.
    address public owner;

    // susd pool, Y pool and DAI addresses.
    address constant public DAI = address(0x6b175474e89094c44da98b954eedeac495271d0f);
    address constant public susdPool = address(0xFCBa3E75865d2d561BE8D220616520c171F12851); // susd pool Deposit Contract
    address constant public yPool = address(0xbBC81d23Ea2c3ec7e56D39296F0cbB648873a5d3); // Y pool Deposit Contract
    
    // Pool arrays for verified and whitelisted Curve pools
    address[] public verifiedPools;
    address[] public whitelistedPools;

    // Pool weights
    uint8 public susdWeight;
    uint8 public yWeight;

    // Pool DAI Liquidity
    uint256 public susdLiquidity;
    uint256 public yLiquidity;

    // EVENTS
    event PoolWhitelisted(address indexed pool);
    event PoolWeights(uint8 susdWeight, uint8 yWeight);
    event Deposit(address indexed sender, address indexed pool, uint256 amount);
    event Rebalance(uint256 amount, address indexed pool);

    // CONSTRUCTOR
    constructor(uint8 _susdWeight, uint8 _yWeight) public {
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
    function addLiquidity(address pool) public returns (bool success) {
        // Verify pool address
        require(pool == susdPool || pool == yPool, "Error: Invalid pool address.")
        // DAI balance in user address.
        uint _dai = IERC20(DAI).balanceOf(msg.sender);
        // Deposit DAI in pools.
        if (_dai > 0) {
            // Deposit DAI in susd pool.
            if (pool == susdPool) {
                // susd pool deposit
                IERC20(DAI).safeTransferFrom(msg.sender, address(this), _dai);
                ICurveDeposit(susdPool).add_liquidity([_dai,0,0,0], 0);
                // Update susd pool Liquidity
                susdLiquidity = susdLiquidity.add(_dai);
            }
            else if (pool == yPool){
                // y pool deposit
                IERC20(DAI).safeTransferFrom(msg.sender, address(this), _dai);
                ICurveDeposit(yPool).add_liquidity([_dai,0,0,0], 0); // DAI => yDAI done by deposit contract
                // Update Y pool liquidity
                yLiquidity = yLiquidity.add(_dai);
            }
        }
        // Emit event
        emit Deposit(msg.sender, pool, _dai);
        return success;
    }

    // 4 - Rebalance
    // Description: Remove liquidity from 1 curve pool and provides liquidity to another
    // to rebalance portfolio according to weights in actions 2

    /**
    * @notice Rebalances portfolio of LP tokens set by Admin
    * @dev Public function called periodically
    * @return boolean value of true once protfolio rebalance is complete
    */
    function rebalance() public returns (bool) {
        // Calculates % allocation between susd and Y pool.
        uint totalBalance = susdLiquidity.add(yLiquidity);
        uint susdDAIPartition = (susdLiquidity.div(totalBalance)).mul(100);
        uint yDAIPartition = (yLiquidity.div(totalBalance)).mul(100);
        // Compare % allocation with desired pool weights.
        if (susdDAIPartition > susdWeight) {
            // Calculate excess DAI
            uint susdExcess = susdLiquidity.mul(uint(susdDAIPartition.sub(susdWeight))); 
            // Withdraw DAI from susd pool
            ICurveDeposit(susdPool).remove_liquidity(susdExcess, [0,0,0,0]);
            // Reallocate DAI in Y pool via deposit
            ICurveDeposit(yPool).add_liquidity([susdExcess,0,0,0], 0);
            // Update liquidity pools
            susdLiquidity = susdLiquidity.sub(susdExcess);
            yLiquidity = yLiquidity.add(susdExcess);
            // Emit event
            emit Rebalance(susdExcess, susdPool);
        }
        if (yDAIPartition > yWeight) {
            // Calculate excess DAI
            uint yExcess = yLiquidity.mul(int(yDAIPartition.sub(yWeight))); 
            // WithdrawDAI from Y pool
            ICurveDeposit(yPool).remove_liquidity(yExcess, [0,0,0,0]);
            // Reallocate DAI in susd pool via deposit
            ICurveDeposit(susdPool).add_liquidity([yExcess,0,0,0],0);
            // Update Liquidity pools
            yLiquidity = yLiquidity.sub(yExcess);
            susdLiquidity = susdLiquidity.add(yExcess);
            // Emit Event
            emit Rebalance(yExcess, yPool);
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