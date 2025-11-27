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
 * @title ArbitrageSwap V2 - FINAL CORRECTED VERSION
 * @notice This contract fixes ALL critical bugs discovered:
 *
 * FIXES:
 *  ✅ BUG #1: Removed startIdx parameter from arbitrage functions
 *  ✅ BUG #2: Corrected optimizedSwap function signatures to match Python expectations
 *  ✅ BUG #3: All functions ready for ABI generation
 *
 * FEATURES:
 *  - Arbitrage execution (multi-hop, circular paths)
 *  - Sandwich attack (front-run + back-run)
 *  - Optimized single swaps (V2, V3, V2+V3 mixed)
 *  - Multi-hop swap with stages
 *  - On-chain profit checks (view functions)
 *  - Block number validation (anti-frontrun)
 *  - Emergency stop mechanism
 *  - bloXroute integration
 *
 * @dev All function signatures verified against Python code
 * @author Claude Code - Bug Fix Version
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
    // ARBITRAGE FUNCTIONS (FIXED: Removed startIdx parameter)
    // ============================================================

    /**
     * @notice Multi-hop arbitrage without relay fee
     * @dev FIXED: Removed startIdx parameter (always starts at index 0)
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
     * @param amountIn Initial amount
     * @param exchanges DEX IDs
     * @param poolAddresses Pool addresses
     * @param tokenAddresses Circular token path
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
     * @param amountIn Initial amount
     * @param exchanges DEX IDs
     * @param poolAddresses Pool addresses
     * @param tokenAddresses Circular token path
     * @param blockNumber Expected block number for execution
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
     * @dev FIXED: Always starts from index 0 (no startIdx parameter)
     */
    function _executeArbitrage(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) internal {
        require(
            tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1],
            "Arbitrage: First and last token must be the same"
        );

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
    // MULTI-HOP SWAP FUNCTION
    // ============================================================

    /**
     * @notice Multi-stage multi-hop swap
     * @dev Used for complex sandwich attack patterns
     * @param amountsIn Array of input amounts for each stage
     * @param stages Array of ending indices for each stage
     * @param exchanges Array of all DEX IDs
     * @param poolAddresses Array of all pool addresses
     * @param tokenAddresses Array of all token addresses
     * @param preserveAmounts Minimum output amounts for each stage (0 = no check)
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
    // OPTIMIZED SWAP FUNCTIONS (FIXED: Correct Signatures)
    // ============================================================

    /**
     * @notice Gas-optimized single UniswapV2 swap
     * @dev FIXED: Signature matches Python expectations (6 parameters)
     * @param amountIn Input amount
     * @param expectedAmountOut Expected output (for slippage validation)
     * @param poolAddress Pool address (single pool, NOT array)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param zeroForOne Swap direction (token0 → token1 or vice versa)
     */
    function optimizedSwapUniswapV2(
        uint256 amountIn,
        uint256 expectedAmountOut,
        address poolAddress,
        address tokenIn,
        address tokenOut,
        bool zeroForOne
    ) external onlyOwner notStopped {
        // Transfer tokens to pool (V2 pull pattern)
        IERC20(tokenIn).safeTransfer(poolAddress, amountIn);

        // Calculate actual output
        uint256 amountOut = getAmountOut(poolAddress, tokenIn, amountIn, zeroForOne);

        // Slippage check
        require(amountOut >= expectedAmountOut, "OptimizedV2: Slippage too high");

        // Execute swap
        if (zeroForOne) {
            IUniswapV2Pair(poolAddress).swap(0, amountOut, address(this), '');
        } else {
            IUniswapV2Pair(poolAddress).swap(amountOut, 0, address(this), '');
        }
    }

    /**
     * @notice Gas-optimized single UniswapV3 swap
     * @dev FIXED: Signature matches Python expectations (4 parameters)
     * @param amountIn Input amount
     * @param poolAddress Pool address (single pool, NOT array)
     * @param tokenIn Input token address
     * @param zeroForOne Swap direction
     */
    function optimizedSwapUniswapV3(
        uint256 amountIn,
        address poolAddress,
        address tokenIn,
        bool zeroForOne
    ) external onlyOwner notStopped {
        // V3 uses callback pattern, no pre-transfer needed
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
     * @param v2AmountIn V2 swap input amount
     * @param v3AmountIn V3 swap input amount
     * @param v2ExpectedAmountOut V2 expected output (slippage check)
     * @param v2Pool V2 pool address
     * @param v3Pool V3 pool address
     * @param v2Token0 V2 first token
     * @param v2Token1 V2 second token
     * @param v3Token0 V3 first token
     * @param v3Token1 V3 second token
     * @param v2ZeroForOne V2 swap direction
     * @param v3ZeroForOne V3 swap direction
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
        // Determine swap order: which swap produces input for the other?
        // If V2 output token matches V3 input token → V2 first
        bool v2First = (v2Token1 == v3Token0 || v2Token1 == v3Token1);

        if (v2First) {
            // Execute V2 swap first
            _executeV2Swap(v2Pool, v2Token0, v2AmountIn, v2ExpectedAmountOut, v2ZeroForOne);

            // Execute V3 swap second (uses output from V2 if chained)
            _executeV3Swap(v3Pool, v3Token0, v3AmountIn, v3ZeroForOne);
        } else {
            // Execute V3 swap first
            _executeV3Swap(v3Pool, v3Token0, v3AmountIn, v3ZeroForOne);

            // Execute V2 swap second
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
    // BATCH ARBITRAGE (BONUS FEATURE)
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
