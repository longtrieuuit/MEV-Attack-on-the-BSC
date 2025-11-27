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
 * @title ArbitrageSwap - ULTIMATE VERSION
 * @notice Incorporates best practices from research:
 *  1. Fixed critical bugs
 *  2. On-chain profit check (view function)
 *  3. Configurable slippage
 *  4. Block number validation
 *  5. Flash swap support (via existing callbacks)
 *  6. Batch arbitrage
 *  7. Emergency controls
 * @dev Based on analysis of Flashbots, Haehnchen, and other MEV bots
 */
contract ArbitrageSwap is SwapCallBack {
    using ISafeERC20 for IERC20;

    address bloxrouteAddress = 0x74c5F8C6ffe41AD4789602BDB9a48E6Cad623520;
    address private wrappedNativeAddress;

    address public owner;
    bool public emergencyStop = false;  // Circuit breaker

    modifier onlyOwner {
        require(msg.sender == owner, "Ownable: You are not the owner, Bye.");
        _;
    }

    modifier notStopped {
        require(!emergencyStop, "Emergency stop activated");
        _;
    }

    constructor(uint chainID, address _wrappedNativeAddress) SwapCallBack(chainID) {
        wrappedNativeAddress = _wrappedNativeAddress;
        owner = msg.sender;
    }

    receive() external payable {}

    // ============================================================
    // EMERGENCY CONTROLS
    // ============================================================

    function setEmergencyStop(bool _stop) external onlyOwner {
        emergencyStop = _stop;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    // ============================================================
    // SANDWICH FUNCTIONS (Original)
    // ============================================================

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

    function sandwichBackRunWithBloxroute(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner notStopped {
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
        payable(bloxrouteAddress).transfer(msg.value);
    }

    function sandwichBackRun(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        require(IERC20(tokenAddresses[tokenAddresses.length - 1]).balanceOf(address(this)) >= amountIn, "SandwichBackRun: insufficient balance");
        _sandwichBackRun(amountIn, exchanges, poolAddresses, tokenAddresses);
    }

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
    // ARBITRAGE FUNCTIONS (ULTIMATE with All Improvements)
    // ============================================================

    /**
     * @notice Check arbitrage profitability without executing
     * @dev View function for off-chain validation and MEV relays
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

    /**
     * @notice Multi-hop arbitrage without relay
     * @param startIdx Starting index in exchanges array
     * @param amountIn Initial amount to arbitrage
     * @param exchanges Array of DEX IDs
     * @param poolAddresses Array of pool addresses
     * @param tokenAddresses Circular token path (first == last)
     */
    function multiHopArbitrageWithoutRelay(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        _executeArbitrage(
            startIdx,
            amountIn,
            exchanges,
            poolAddresses,
            tokenAddresses
        );
    }

    /**
     * @notice Multi-hop arbitrage with bloXroute relay fee
     * @param startIdx Starting index
     * @param amountIn Initial amount
     * @param exchanges DEX IDs
     * @param poolAddresses Pool addresses
     * @param tokenAddresses Circular token path
     */
    function multiHopArbitrageWithBloxroute(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external payable onlyOwner notStopped {
        _executeArbitrage(
            startIdx,
            amountIn,
            exchanges,
            poolAddresses,
            tokenAddresses
        );
        payable(bloxrouteAddress).transfer(msg.value);
    }

    /**
     * @notice Multi-hop arbitrage with block number validation
     * @dev Prevents frontrunning by validating execution block
     * @param blockNumber Expected block number for execution
     */
    function multiHopArbitrageWithBlockNumber(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses,
        uint256 blockNumber
    ) external payable onlyOwner notStopped {
        require(block.number == blockNumber, "Wrong block number");

        _executeArbitrage(
            startIdx,
            amountIn,
            exchanges,
            poolAddresses,
            tokenAddresses
        );

        if (msg.value > 0) {
            payable(bloxrouteAddress).transfer(msg.value);
        }
    }

    /**
     * @notice Batch execute multiple arbitrages in one transaction
     * @dev More gas efficient than multiple transactions
     */
    function batchArbitrage(
        uint8[] memory startIdxs,
        uint256[] memory amountsIn,
        uint8[][] memory allExchanges,
        address[][] memory allPoolAddresses,
        address[][] memory allTokenAddresses
    ) external onlyOwner notStopped {
        require(startIdxs.length == amountsIn.length, "Length mismatch");
        require(amountsIn.length == allExchanges.length, "Length mismatch");

        for (uint256 i = 0; i < startIdxs.length; i++) {
            // Try each arbitrage, continue on failure
            try this._executeArbitrageExternal(
                startIdxs[i],
                amountsIn[i],
                allExchanges[i],
                allPoolAddresses[i],
                allTokenAddresses[i]
            ) {
                // Success
            } catch {
                // Failure - continue with next
            }
        }
    }

    /**
     * @notice External wrapper for batch arbitrage try-catch
     */
    function _executeArbitrageExternal(
        uint8 startIdx,
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external {
        require(msg.sender == address(this), "Internal only");
        _executeArbitrage(startIdx, amountIn, exchanges, poolAddresses, tokenAddresses);
    }

    /**
     * @notice Internal arbitrage execution logic
     * @dev Shared by all arbitrage functions
     */
    function _executeArbitrage(
        uint8 startIdx,
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

        for (uint256 i = startIdx; i < exchanges.length; i++) {
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

    // ============================================================
    // MULTI-HOP SWAP (ULTIMATE)
    // ============================================================

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
    // OPTIMIZED SWAPS (ULTIMATE)
    // ============================================================

    function optimizedSwapUniswapV2(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        address fromAddress = address(this);
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
            if (i + 1 < exchanges.length) {
                toAddress = poolAddresses[i + 1];
            } else {
                toAddress = address(this);
            }

            uint256 balanceBefore = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress);
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

    function optimizedSwapUniswapV3(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
            toAddress = address(this);

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

    function optimizedSwapUniswapV2V3(
        uint256 amountIn,
        uint8[] memory exchanges,
        address[] memory poolAddresses,
        address[] memory tokenAddresses
    ) external onlyOwner notStopped {
        address fromAddress = address(this);
        address toAddress;

        for (uint256 i = 0; i < exchanges.length; i++) {
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
