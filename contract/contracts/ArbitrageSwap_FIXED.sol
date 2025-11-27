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
 * @title ArbitrageSwap - FIXED VERSION
 * @notice Fixed bugs from COMPLETE version:
 *  - Bug #1: External call to self in multiHopArbitrageWithBloxroute (CRITICAL)
 *  - Optimized gas usage for V2→V2 paths
 * @dev Replace ArbitrageSwap.sol with this file
 */
contract ArbitrageSwap is SwapCallBack {
    using ISafeERC20 for IERC20;
    address bloxrouteAddress = 0x74c5F8C6ffe41AD4789602BDB9a48E6Cad623520;

    address private wrappedNativeAddress;
    constructor(uint chainID, address _wrappedNativeAddress) SwapCallBack(chainID) {
        wrappedNativeAddress = _wrappedNativeAddress;
    }

    address owner = msg.sender;
    modifier onlyOwner {
        require(msg.sender == owner, "Ownable: You are not the owner, Bye.");
        _;
    }

    function withdrawProfitWithBloxroute() internal {
        payable(bloxrouteAddress).transfer(msg.value);
    }

    receive() external payable {}

    // ============================================================
    // SANDWICH FUNCTIONS (From Original)
    // ============================================================

    function sandwichFrontRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        address fromAddress = address(this);
        address toAddress;
        uint256 i = 0;
        for (; i < exchanges.length; i++) {
            if (
                i + 1 < exchanges.length && isPossibleToAddress(exchanges[i]) && isPossibleFromAddress(exchanges[i + 1])
            ) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }
            amountIn = swap(exchanges[i], poolAddresses[i], fromAddress, toAddress, tokenAddresses[i], tokenAddresses[i + 1], amountIn);
            fromAddress = toAddress;
        }
    }

    function sandwichFrontRunDifficult(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 amountOut,
        uint256 poolBalance
    ) external onlyOwner {
        require(IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(poolAddresses[poolAddresses.length - 1]) == poolBalance, "SFRD: insufficient balance");
        address fromAddress = address(this);
        address toAddress;
        uint256 i = 0;
        for (; i < exchanges.length; i++) {
            if (
                i + 1 < exchanges.length && isPossibleToAddress(exchanges[i]) && isPossibleFromAddress(exchanges[i + 1])
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

    function sandwichBackRunWithBloxroute(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner {
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
        payable(bloxrouteAddress).transfer(msg.value);
    }

    function sandwichBackRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        require(IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this)) >= amountIn, "SandwichBackRun: insufficient balance");
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
    }

    function sandwichBackRunDifficult(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 blockNumber
    ) external onlyOwner {
        require(block.number == blockNumber, "SandwichBackRunDifficult: block number is not correct");
        uint256 beforeBalance = IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this));
        require(beforeBalance >= amountIn, "SandwichBackRunDifficult: insufficient balance");
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
        if (tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1] &&
            IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this)) < beforeBalance) {
            revert("SandwichBackRunDifficult: failed");
        }
    }

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
                i > 1 && isPossibleToAddress(exchanges[i - 1]) && isPossibleFromAddress(exchanges[i - 2])
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
    // ARBITRAGE FUNCTIONS (NEW - BUGS FIXED)
    // ============================================================

    /**
     * @notice Multi-hop arbitrage without relay fee
     * @dev External wrapper for _executeArbitrage
     */
    function multiHopArbitrageWithoutRelay(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        _executeArbitrage(
            startIdx,
            amountIn,
            exchanges,
            poolAddresses,
            tokenAddresses
        );
    }

    /**
     * @notice Multi-hop arbitrage with bloXroute relay
     * @dev FIXED: Direct implementation instead of external call to avoid onlyOwner issue
     */
    function multiHopArbitrageWithBloxroute(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner {
        // Execute arbitrage (internal call - no onlyOwner issue)
        _executeArbitrage(
            startIdx,
            amountIn,
            exchanges,
            poolAddresses,
            tokenAddresses
        );

        // Pay bloXroute fee
        payable(bloxrouteAddress).transfer(msg.value);
    }

    /**
     * @notice Internal arbitrage execution logic
     * @dev Shared by both multiHopArbitrageWithoutRelay and multiHopArbitrageWithBloxroute
     */
    function _executeArbitrage(
        uint8 startIdx,
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

        // Execute multi-hop swaps
        address fromAddress = address(this);
        address toAddress;

        for (uint256 i = startIdx; i < exchanges.length; i++) {
            // Determine if can send directly to next pool
            if (
                i + 1 < exchanges.length &&
                isPossibleToAddress(exchanges[i]) &&
                isPossibleFromAddress(exchanges[i + 1])
            ) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }

            // Execute swap
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

    // ============================================================
    // MULTI-HOP SWAP (NEW)
    // ============================================================

    /**
     * @notice Complex multi-stage swap
     * @dev Used for advanced sandwich optimization
     */
    function multiHopSwap(
        uint256[] memory amountsIn,
        uint256[] memory stages,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256[] memory preserveAmounts
    ) external onlyOwner {
        require(amountsIn.length == stages.length, "MultiHopSwap: Length mismatch");
        require(stages.length == preserveAmounts.length, "MultiHopSwap: Length mismatch");

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
    // OPTIMIZED SWAPS (NEW)
    // ============================================================

    /**
     * @notice Gas-optimized swap for UniswapV2 only paths
     * @dev Assumes all exchanges are UniswapV2 compatible
     */
    function optimizedSwapUniswapV2(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        address fromAddress = address(this);
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
            // Optimized: V2 → V2 can send directly
            if (i + 1 < exchanges.length) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }

            // Track output via balance difference
            uint256 balanceBefore = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress);

            // Direct uniswapV2Swap call (no routing overhead)
            uniswapV2Swap(
                poolAddresses[i],
                fromAddress,
                tokenAddresses[i],
                tokenAddresses[i + 1],
                amountIn
            );

            amountIn = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress) - balanceBefore;
            fromAddress = toAddress;
        }
    }

    /**
     * @notice Gas-optimized swap for UniswapV3 only paths
     */
    function optimizedSwapUniswapV3(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
            if (i + 1 < exchanges.length) {
                toAddress = address(this); // V3 uses callback, always to contract
            } else {
                toAddress = address(this);
            }

            uint256 balanceBefore = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress);

            uniswapV3Swap(
                poolAddresses[i],
                toAddress,
                tokenAddresses[i],
                tokenAddresses[i + 1],
                amountIn
            );

            amountIn = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress) - balanceBefore;
        }
    }

    /**
     * @notice Gas-optimized swap for mixed V2/V3 paths
     */
    function optimizedSwapUniswapV2V3(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner {
        address fromAddress = address(this);
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
            // Smart routing: V2 can send to next pool, V3 always to contract
            if (i + 1 < exchanges.length && isUniswapV2(exchanges[i])) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }

            uint256 balanceBefore = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress);

            if (isUniswapV2(exchanges[i])) {
                uniswapV2Swap(
                    poolAddresses[i],
                    fromAddress,
                    tokenAddresses[i],
                    tokenAddresses[i + 1],
                    amountIn
                );
            } else if (isUniswapV3(exchanges[i])) {
                uniswapV3Swap(
                    poolAddresses[i],
                    toAddress,
                    tokenAddresses[i],
                    tokenAddresses[i + 1],
                    amountIn
                );
            } else {
                revert("OptimizedSwap: Unsupported DEX type");
            }

            amountIn = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress) - balanceBefore;
            fromAddress = toAddress;
        }
    }
}
