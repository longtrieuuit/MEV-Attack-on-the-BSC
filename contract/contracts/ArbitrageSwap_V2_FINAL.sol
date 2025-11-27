// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from './safeERC20/IERC20.sol';
import {ISafeERC20} from './safeERC20/ISafeERC20.sol';
import {IUniswapV2Pair} from './dexes/uniswapV2/interfaces/IUniswapV2Pair.sol';
import {IUniswapV3Pool} from './dexes/uniswapV3/interfaces/IUniswapV3Pool.sol';
import {SwapCallBack} from './SwapCallBack.sol';
import {UniswapV3Constant} from './dexes/uniswapV3/libraries/UniswapV3Constant.sol';
import {INativeToken} from './interfaces/INativeToken.sol';

/**
 * @title ArbitrageSwap V2 FINAL - Complete MEV Bot with Flash Loan Support
 * @notice Ultimate MEV bot contract merging:
 *  - Flash swap arbitrage (ZERO capital needed)
 *  - Regular arbitrage (multi-hop, 2-4 hops)
 *  - Optimized sandwich swaps (gas efficient)
 *  - Safety features (emergency stop, profit validation)
 *  - Best practices from GitHub research
 *
 * FEATURES:
 *  ✅ Flash Swap Arbitrage (4 strategies):
 *     - V2 → V2: Borrow from V2, arbitrage on V2
 *     - V2 → V3: Borrow from V2, arbitrage on V3
 *     - V3 → V2: Flash swap on V3, arbitrage on V2
 *     - V3 → V3: Flash swap on V3, arbitrage on V3
 *  ✅ Regular Arbitrage (requires capital):
 *     - Multi-hop (2-4 hops)
 *     - Circular path validation
 *     - Profit validation
 *  ✅ Sandwich Attack Optimization:
 *     - Optimized V2 swap (single pool)
 *     - Optimized V3 swap (single pool)
 *     - Optimized V2+V3 mixed (2 swaps)
 *     - Multi-stage swap
 *  ✅ Safety & Admin:
 *     - Emergency stop mechanism
 *     - On-chain profit check (view)
 *     - Block number validation
 *     - Batch execution
 *     - Ownership transfer
 *
 * BUGS FIXED:
 *  ✅ Removed startIdx parameter (always start from 0)
 *  ✅ Added circular path validation
 *  ✅ Added profit validation
 *  ✅ Correct optimized swap signatures
 *
 * RESEARCH SOURCES:
 *  - Uniswap V2/V3 official examples
 *  - Haehnchen/uniswap-arbitrage-flash-swap
 *  - solidquant/mev-templates
 *  - Cyfrin/advanced-defi-2024
 *  - akornato/flash-loan
 *
 * @dev All function signatures verified against Python code
 * @author Claude Code - Ultimate Merged Version
 * @date 2025-11-27
 */
contract ArbitrageSwap is SwapCallBack {
    using ISafeERC20 for IERC20;

    // ============================================================
    // STATE VARIABLES
    // ============================================================

    address public bloxrouteAddress = 0x74c5F8C6ffe41AD4789602BDB9a48E6Cad623520;
    address private wrappedNativeAddress;
    address public owner;
    bool public emergencyStop = false;

    // ============================================================
    // MODIFIERS
    // ============================================================

    modifier onlyOwner {
        require(msg.sender == owner, "Ownable: You are not the owner, Bye.");
        _;
    }

    modifier notStopped {
        require(!emergencyStop, "Emergency stop activated");
        _;
    }

    // ============================================================
    // CONSTRUCTOR
    // ============================================================

    constructor(uint chainID, address _wrappedNativeAddress) SwapCallBack(chainID) {
        wrappedNativeAddress = _wrappedNativeAddress;
        owner = msg.sender;
    }

    receive() external payable {}

    // ============================================================
    // ADMIN FUNCTIONS
    // ============================================================

    function setEmergencyStop(bool _stop) external onlyOwner {
        emergencyStop = _stop;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    function setBloxrouteAddress(address _bloxrouteAddress) external onlyOwner {
        require(_bloxrouteAddress != address(0), "Invalid address");
        bloxrouteAddress = _bloxrouteAddress;
    }

    // ============================================================
    // SANDWICH ATTACK FUNCTIONS
    // ============================================================

    /**
     * @notice Front-run swap for sandwich attack
     */
    function sandwichFrontRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        address fromAddress = address(this);
        address toAddress;
        for (uint256 i = 0; i < exchanges.length; i++) {
            if (
                i + 1 < exchanges.length &&
                isPossibleToAddress(exchanges[i]) &&
                isPossibleFromAddress(exchanges[i + 1])
            ) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }
            amountIn = swap(exchanges[i], poolAddresses[i], fromAddress, toAddress, tokenAddresses[i], tokenAddresses[i + 1], amountIn);
            fromAddress = toAddress;
        }
    }

    /**
     * @notice Front-run swap with validation (difficult mode)
     */
    function sandwichFrontRunDifficult(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 amountOut,
        uint256 poolBalance
    ) external onlyOwner notStopped {
        require(IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(poolAddresses[poolAddresses.length - 1]) == poolBalance, "SFRD: insufficient balance");
        address fromAddress = address(this);
        address toAddress;
        for (uint256 i = 0; i < exchanges.length; i++) {
            if (
                i + 1 < exchanges.length &&
                isPossibleToAddress(exchanges[i]) &&
                isPossibleFromAddress(exchanges[i + 1])
            ) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }
            amountIn = swap(exchanges[i], poolAddresses[i], fromAddress, toAddress, tokenAddresses[i], tokenAddresses[i + 1], amountIn);
            fromAddress = toAddress;
        }
        require(amountIn >= amountOut, "SFRD: amountIn <= amountOut");
    }

    /**
     * @notice Back-run swap with bloXroute fee
     */
    function sandwichBackRunWithBloxroute(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner notStopped {
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
        payable(bloxrouteAddress).transfer(msg.value);
    }

    /**
     * @notice Back-run swap without relay fee
     */
    function sandwichBackRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        require(IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this)) >= amountIn, "SandwichBackRun: insufficient balance");
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
    }

    /**
     * @notice Back-run swap with block validation (difficult mode)
     */
    function sandwichBackRunDifficult(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 blockNumber
    ) external onlyOwner notStopped {
        require(block.number == blockNumber, "SandwichBackRunDifficult: block number is not correct");
        uint256 beforeBalance = IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this));
        require(beforeBalance >= amountIn, "SandwichBackRunDifficult: insufficient balance");
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
        if (tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1] &&
            IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this)) < beforeBalance) {
            revert("SandwichBackRunDifficult: failed");
        }
    }

    /**
     * @notice Internal back-run implementation (reverse swap order)
     */
    function _sandwichBackRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) internal {
        address fromAddress = address(this);
        address toAddress;
        for (uint256 i = exchanges.length; i > 0; i--) {
            if (
                i > 1 &&
                isPossibleToAddress(exchanges[i - 1]) &&
                isPossibleFromAddress(exchanges[i - 2])
            ) {
                toAddress = poolAddresses[i - 2];
            } else {
                toAddress = address(this);
            }
            amountIn = swap(exchanges[i - 1], poolAddresses[i - 1], fromAddress, toAddress, tokenAddresses[i], tokenAddresses[i - 1], amountIn);
            fromAddress = toAddress;
        }
    }

    // ============================================================
    // REGULAR ARBITRAGE FUNCTIONS (FIXED - NO startIdx bug)
    // ============================================================

    /**
     * @notice Multi-hop arbitrage without relay fee
     * @dev FIXED: Removed startIdx parameter, always starts from index 0
     * @param amountIn Initial amount to arbitrage
     * @param exchanges Array of DEX IDs
     * @param poolAddresses Array of pool addresses
     * @param tokenAddresses Circular token path (first == last)
     */
    function multiHopArbitrageWithoutRelay(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        _executeArbitrage(amountIn, exchanges, poolAddresses, tokenAddresses);
    }

    /**
     * @notice Multi-hop arbitrage with bloXroute relay fee
     * @dev FIXED: Removed startIdx parameter
     */
    function multiHopArbitrageWithBloxroute(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner notStopped {
        _executeArbitrage(amountIn, exchanges, poolAddresses, tokenAddresses);
        payable(bloxrouteAddress).transfer(msg.value);
    }

    /**
     * @notice Multi-hop arbitrage with block number validation
     * @dev Prevents frontrunning by validating execution block
     */
    function multiHopArbitrageWithBlockNumber(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 blockNumber
    ) external payable onlyOwner notStopped {
        require(block.number == blockNumber, "Block mismatch");
        _executeArbitrage(amountIn, exchanges, poolAddresses, tokenAddresses);
        if (msg.value > 0) {
            payable(bloxrouteAddress).transfer(msg.value);
        }
    }

    /**
     * @notice Internal arbitrage execution logic
     * @dev FIXED: Always starts from index 0, validates circular path and profit
     */
    function _executeArbitrage(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) internal {
        // Validate circular path
        require(
            tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1],
            "Arbitrage: First and last token must be the same"
        );

        // Record initial balance
        uint256 initialBalance = IERC20(tokenAddresses[0]).balanceOf(address(this));

        address fromAddress = address(this);
        address toAddress;

        // FIXED: Always start from 0, no startIdx parameter
        for (uint256 i = 0; i < exchanges.length; i++) {
            if (
                i + 1 < exchanges.length &&
                isPossibleToAddress(exchanges[i]) &&
                isPossibleFromAddress(exchanges[i + 1])
            ) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }

            amountIn = swap(
                exchanges[i],
                poolAddresses[i],
                fromAddress,
                toAddress,
                tokenAddresses[i],
                tokenAddresses[i + 1],
                amountIn
            );

            fromAddress = toAddress;
        }

        // Validate profit
        uint256 finalBalance = IERC20(tokenAddresses[0]).balanceOf(address(this));
        require(
            finalBalance > initialBalance,
            "Arbitrage: No profit - revert transaction"
        );
    }

    /**
     * @notice Check arbitrage profitability without executing (view function)
     * @dev For off-chain validation and MEV relays
     * @return expectedProfit Estimated profit in base token (0 if unprofitable)
     */
    function checkArbitrageProfit(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) public view returns (uint256 expectedProfit) {
        require(
            tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1],
            "Invalid circular path"
        );

        uint256 currentAmount = amountIn;

        for (uint256 i = 0; i < exchanges.length; i++) {
            if (isUniswapV2(exchanges[i])) {
                bool zeroForOne = tokenAddresses[i] < tokenAddresses[i + 1];
                currentAmount = getAmountOut(
                    poolAddresses[i],
                    tokenAddresses[i],
                    currentAmount,
                    zeroForOne
                );
            } else {
                // For V3 and other DEXs, return 0 (cannot simulate easily)
                return 0;
            }
        }

        if (currentAmount > amountIn) {
            expectedProfit = currentAmount - amountIn;
        } else {
            expectedProfit = 0;
        }
    }

    // ============================================================
    // FLASH SWAP ARBITRAGE (ZERO CAPITAL NEEDED!)
    // ============================================================

    /**
     * @notice Flash swap arbitrage: V2 → V2
     * @dev Borrow from V2 pool, arbitrage on another V2 pool, repay with profit
     * @param borrowAmount Amount to borrow via flash swap (no capital needed!)
     * @param pool0 V2 Pool to flash borrow from
     * @param pool1 V2 Pool to arbitrage on
     * @param token0 First token (sorted by address)
     * @param token1 Second token (sorted by address)
     *
     * Flow: Flash borrow token1 from pool0 → Swap token1→token0 on pool1 → Repay pool0 with token0
     * Example: Borrow 100 USDT from PancakeSwap → Swap to 0.5 BNB on Biswap → Repay 0.48 BNB → Keep 0.02 BNB profit
     */
    function flashSwapArbitrageV2V2(
        uint256 borrowAmount,
        address pool0,
        address pool1,
        address token0,
        address token1
    ) external onlyOwner notStopped {
        bool zeroForOne = token0 < token1;
        uint256 repayAmount = _calcRepayAmountV2(pool0, borrowAmount, zeroForOne);

        bytes memory data = _encodeV2FlashData(
            uint8(1),  // Type: V2→V2
            pool1,
            repayAmount,
            zeroForOne ? token1 : token0,  // borrowedToken
            zeroForOne ? token0 : token1   // repayToken
        );

        _executeV2FlashSwap(pool0, borrowAmount, zeroForOne, data);
    }

    /**
     * @notice Flash swap arbitrage: V2 → V3
     * @dev Borrow from V2 pool, arbitrage on V3 pool, repay with profit
     */
    function flashSwapArbitrageV2V3(
        uint256 borrowAmount,
        address pool0,
        address pool1,
        address token0,
        address token1
    ) external onlyOwner notStopped {
        bool zeroForOne = token0 < token1;
        uint256 repayAmount = _calcRepayAmountV2(pool0, borrowAmount, zeroForOne);

        bytes memory data = _encodeV2FlashData(
            uint8(2),  // Type: V2→V3
            pool1,
            repayAmount,
            zeroForOne ? token1 : token0,  // borrowedToken
            zeroForOne ? token0 : token1   // repayToken
        );

        _executeV2FlashSwap(pool0, borrowAmount, zeroForOne, data);
    }

    /**
     * @notice Flash swap arbitrage: V3 → V2
     * @dev Flash swap on V3 pool, arbitrage on V2 pool, repay with profit
     * @param amountIn Amount to swap on V3 (flash swap - no capital needed!)
     * @param pool0 V3 Pool to flash swap from
     * @param pool1 V2 Pool to arbitrage on
     * @param token0 First token (sorted)
     * @param token1 Second token (sorted)
     *
     * Flow: Flash swap token0→token1 on V3 pool0 → Swap token1→token0 on V2 pool1 → Repay V3
     * V3 output goes directly to V2 pool to save gas!
     */
    function flashSwapArbitrageV3V2(
        uint256 amountIn,
        address pool0,
        address pool1,
        address token0,
        address token1
    ) external onlyOwner notStopped {
        bool zeroForOne = token0 < token1;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? UniswapV3Constant.MIN_SQRT_RATIO + 1
            : UniswapV3Constant.MAX_SQRT_RATIO - 1;

        address receivedToken = zeroForOne ? token1 : token0;
        address repayToken = zeroForOne ? token0 : token1;

        // Record balance of received token at V2 pool BEFORE V3 swap
        uint256 beforeBalance = IERC20(receivedToken).balanceOf(pool1);

        // Encode callback data: type=2 means V3→V2
        bytes memory data = abi.encode(
            uint8(2),
            abi.encode(beforeBalance, pool1, amountIn, receivedToken, repayToken)
        );

        // V3 swap - output goes directly to pool1 (V2 pool)
        IUniswapV3Pool(pool0).swap(
            pool1,  // recipient = V2 pool (gas optimization!)
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            data
        );
    }

    /**
     * @notice Flash swap arbitrage: V3 → V3
     * @dev Flash swap on V3 pool, arbitrage on another V3 pool, repay with profit
     */
    function flashSwapArbitrageV3V3(
        uint256 amountIn,
        address pool0,
        address pool1,
        address token0,
        address token1
    ) external onlyOwner notStopped {
        bool zeroForOne = token0 < token1;
        uint160 sqrtPriceLimitX96 = zeroForOne
            ? UniswapV3Constant.MIN_SQRT_RATIO + 1
            : UniswapV3Constant.MAX_SQRT_RATIO - 1;

        address receivedToken = zeroForOne ? token1 : token0;
        address repayToken = zeroForOne ? token0 : token1;

        uint256 beforeBalance = IERC20(receivedToken).balanceOf(address(this));

        // Encode callback data: type=3 means V3→V3
        bytes memory data = abi.encode(
            uint8(3),
            abi.encode(beforeBalance, pool1, amountIn, receivedToken, repayToken)
        );

        // V3 swap - output to this contract
        IUniswapV3Pool(pool0).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96,
            data
        );
    }

    // ============================================================
    // FLASH SWAP HELPER FUNCTIONS
    // ============================================================

    /**
     * @notice Calculate repay amount for V2 flash swap (includes 0.3% fee)
     * @dev Formula: amountIn = (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
     */
    function _calcRepayAmountV2(
        address pool,
        uint256 borrowAmount,
        bool zeroForOne
    ) internal view returns (uint256) {
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pool).getReserves();
        (uint reserveIn, uint reserveOut) = zeroForOne
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
        return _getAmountIn(borrowAmount, reserveIn, reserveOut);
    }

    /**
     * @notice Encode callback data for V2 flash swap
     */
    function _encodeV2FlashData(
        uint8 callbackType,
        address pool1,
        uint256 repayAmount,
        address borrowedToken,
        address repayToken
    ) internal view returns (bytes memory) {
        uint256 beforeBalance = IERC20(borrowedToken).balanceOf(address(this));
        return abi.encode(
            callbackType,
            abi.encode(beforeBalance, repayAmount, pool1, borrowedToken, repayToken)
        );
    }

    /**
     * @notice Execute V2 flash swap
     * @dev Triggers callback automatically if data is not empty
     */
    function _executeV2FlashSwap(
        address pool,
        uint256 borrowAmount,
        bool zeroForOne,
        bytes memory data
    ) internal {
        if (zeroForOne) {
            IUniswapV2Pair(pool).swap(0, borrowAmount, address(this), data);
        } else {
            IUniswapV2Pair(pool).swap(borrowAmount, 0, address(this), data);
        }
    }

    /**
     * @notice Calculate V2 amount in for given amount out (for repayment calculation)
     * @dev Includes 0.3% fee
     * @param amountOut Amount of tokens borrowed (output amount)
     * @param reserveIn Reserve of repay token in the pool
     * @param reserveOut Reserve of borrowed token in the pool
     * @return amountIn Amount of tokens needed to repay (includes fee)
     */
    function _getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut < reserveOut, "INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /**
     * @notice Calculate V2 amount out for given amount in
     * @dev Used for profit estimation
     */
    function _getAmountOutV2(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // ============================================================
    // MULTI-HOP SWAP FUNCTION
    // ============================================================

    /**
     * @notice Multi-stage multi-hop swap
     * @dev Used for complex sandwich attack patterns
     */
    function multiHopSwap(
        uint256[] memory amountsIn,
        uint256[] memory stages,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256[] memory preserveAmounts
    ) external onlyOwner notStopped {
        require(amountsIn.length == stages.length, "Length mismatch");
        require(stages.length == preserveAmounts.length, "Length mismatch");

        uint256 stageIdx = 0;

        for (uint256 i = 0; i < stages.length; i++) {
            uint256 stageEnd = stages[i];
            address fromAddress = address(this);
            address toAddress;
            uint256 amountIn = amountsIn[i];

            for (uint256 j = stageIdx; j < stageEnd; j++) {
                if (
                    j + 1 < exchanges.length &&
                    isPossibleToAddress(exchanges[j]) &&
                    isPossibleFromAddress(exchanges[j + 1])
                ) {
                    toAddress = poolAddresses[j + 1];
                } else {
                    toAddress = address(this);
                }

                amountIn = swap(
                    exchanges[j],
                    poolAddresses[j],
                    fromAddress,
                    toAddress,
                    tokenAddresses[j],
                    tokenAddresses[j + 1],
                    amountIn
                );

                fromAddress = toAddress;
            }

            if (preserveAmounts[i] > 0) {
                require(
                    amountIn >= preserveAmounts[i],
                    "MultiHopSwap: Insufficient output for stage"
                );
            }

            stageIdx = stageEnd;
        }
    }

    // ============================================================
    // OPTIMIZED SWAP FUNCTIONS (Gas Efficient for Sandwich)
    // ============================================================

    /**
     * @notice Gas-optimized single UniswapV2 swap
     * @dev FIXED: Signature matches Python expectations (6 parameters)
     */
    function optimizedSwapUniswapV2(
        uint256 amountIn,
        uint256 expectedAmountOut,
        address poolAddress,
        address tokenIn,
        address tokenOut,
        bool zeroForOne
    ) external onlyOwner notStopped {
        IERC20(tokenIn).safeTransfer(poolAddress, amountIn);
        uint256 amountOut = getAmountOut(poolAddress, tokenIn, amountIn, zeroForOne);
        require(amountOut >= expectedAmountOut, "OptimizedV2: Slippage too high");

        if (zeroForOne) {
            IUniswapV2Pair(poolAddress).swap(0, amountOut, address(this), '');
        } else {
            IUniswapV2Pair(poolAddress).swap(amountOut, 0, address(this), '');
        }
    }

    /**
     * @notice Gas-optimized single UniswapV3 swap
     * @dev FIXED: Signature matches Python expectations (4 parameters)
     */
    function optimizedSwapUniswapV3(
        uint256 amountIn,
        address poolAddress,
        address tokenIn,
        bool zeroForOne
    ) external onlyOwner notStopped {
        IUniswapV3Pool(poolAddress).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne
                ? UniswapV3Constant.MIN_SQRT_RATIO + 1
                : UniswapV3Constant.MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );
    }

    /**
     * @notice Gas-optimized mixed V2+V3 swap (exactly 2 swaps)
     * @dev FIXED: Signature matches Python expectations (11 parameters)
     */
    function optimizedSwapUniswapV2V3(
        uint256 v2AmountIn,
        uint256 v3AmountIn,
        uint256 v2ExpectedAmountOut,
        address v2Pool,
        address v3Pool,
        address v2Token0,
        address v2Token1,
        address v3Token0,
        address v3Token1,
        bool v2ZeroForOne,
        bool v3ZeroForOne
    ) external onlyOwner notStopped {
        // Determine swap order
        bool v2First = (v2Token1 == v3Token0 || v2Token1 == v3Token1);

        if (v2First) {
            _executeV2Swap(v2Pool, v2Token0, v2AmountIn, v2ExpectedAmountOut, v2ZeroForOne);
            _executeV3Swap(v3Pool, v3Token0, v3AmountIn, v3ZeroForOne);
        } else {
            _executeV3Swap(v3Pool, v3Token0, v3AmountIn, v3ZeroForOne);
            _executeV2Swap(v2Pool, v2Token0, v2AmountIn, v2ExpectedAmountOut, v2ZeroForOne);
        }
    }

    /**
     * @notice Internal V2 swap helper
     */
    function _executeV2Swap(
        address poolAddress,
        address tokenIn,
        uint256 amountIn,
        uint256 expectedAmountOut,
        bool zeroForOne
    ) internal {
        IERC20(tokenIn).safeTransfer(poolAddress, amountIn);
        uint256 amountOut = getAmountOut(poolAddress, tokenIn, amountIn, zeroForOne);
        require(amountOut >= expectedAmountOut, "V2: Slippage too high");

        if (zeroForOne) {
            IUniswapV2Pair(poolAddress).swap(0, amountOut, address(this), '');
        } else {
            IUniswapV2Pair(poolAddress).swap(amountOut, 0, address(this), '');
        }
    }

    /**
     * @notice Internal V3 swap helper
     */
    function _executeV3Swap(
        address poolAddress,
        address tokenIn,
        uint256 amountIn,
        bool zeroForOne
    ) internal {
        IUniswapV3Pool(poolAddress).swap(
            address(this),
            zeroForOne,
            int256(amountIn),
            zeroForOne
                ? UniswapV3Constant.MIN_SQRT_RATIO + 1
                : UniswapV3Constant.MAX_SQRT_RATIO - 1,
            abi.encode(tokenIn)
        );
    }

    // ============================================================
    // BATCH ARBITRAGE
    // ============================================================

    /**
     * @notice Execute multiple arbitrage opportunities in one transaction
     * @dev Continues on failure (try-catch pattern)
     */
    function batchArbitrage(
        uint256[] memory amountsIn,
        uint8[][] memory allExchanges,
        address[][] memory allPoolAddresses,
        address[][] memory allTokenAddresses
    ) external onlyOwner notStopped {
        require(amountsIn.length == allExchanges.length, "Length mismatch");

        for (uint256 i = 0; i < amountsIn.length; i++) {
            try this._executeArbitrageExternal(
                amountsIn[i],
                allExchanges[i],
                allPoolAddresses[i],
                allTokenAddresses[i]
            ) {
                // Success - continue
            } catch {
                // Failure - skip and continue with next
            }
        }
    }

    /**
     * @notice External wrapper for batch arbitrage try-catch
     */
    function _executeArbitrageExternal(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external {
        require(msg.sender == address(this), "Internal only");
        _executeArbitrage(amountIn, exchanges, poolAddresses, tokenAddresses);
    }
}
