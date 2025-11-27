# 🚨 CRITICAL BUG: startIdx Logic Error in Arbitrage Functions

## Tóm tắt

**BUG NGHIÊM TRỌNG**: Parameter `startIdx` trong contract **KHÔNG TƯƠNG THÍCH** với logic arbitrage và sẽ gây lỗi nếu `startIdx != 0`.

Python code LUÔN LUÔN truyền `startIdx = 0`, nhưng nếu ai đó thay đổi giá trị này → Contract sẽ FAIL.

---

## 1. Python Code Analysis

### Python luôn truyền startIdx = 0

**File: `src/evm.py:391-401`**
```python
def send_arbitrage(self, amount_in, exchanges, pool_addresses, token_addresses):
    function_name = "multiHopArbitrageWithoutRelay"
    result = self.call_function(
        caller=self.account_address,
        to=self.contract_address,
        value=0,
        function_name=function_name,
        input=[0, amount_in, exchanges, pool_addresses, token_addresses],
        #      ↑
        #      startIdx = 0 (HARDCODED)
        abi=contract_abi,
    )
    return result
```

**File: `src/arbitrage/search.py:308-316`**
```python
return ArbitrageAttack(
    function_name=function_name,
    data=[
        0,  # ← startIdx = 0 (HARDCODED)
        path.amount_in,
        path.exchanges,
        path.pool_addresses,
        path.token_addresses,
    ],
    revenue_based_on_eth=revenue,
    gas_used=gas_used,
)
```

**Kết luận**: Python KHÔNG BAO GIỜ sử dụng `startIdx != 0`.

---

## 2. Contract Logic Analysis

### Contract Function: `multiHopArbitrageWithoutRelay`

**File: `contract/contracts/ArbitrageSwap_ULTIMATE.sol:229-243`**
```solidity
function multiHopArbitrageWithoutRelay(
    uint8 startIdx,        // ← Received from Python (always 0)
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner notStopped {
    _executeArbitrage(
        startIdx,          // ← Passed to internal function
        amountIn,
        exchanges,
        poolAddresses,
        tokenAddresses
    );
}
```

### Internal Function: `_executeArbitrage`

**File: `contract/contracts/ArbitrageSwap_ULTIMATE.sol:346-392`**
```solidity
function _executeArbitrage(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) internal {
    // Step 1: Check circular path
    require(
        tokenAddresses[0] == tokenAddresses[tokenAddresses.length - 1],
        //                ↑                                          ↑
        //              FIRST                                      LAST
        "Arbitrage: First and last token must be the same"
    );

    // Step 2: Measure initial balance of FIRST token
    uint256 initialBalance = IERC20(tokenAddresses[0]).balanceOf(address(this));
    //                                              ↑
    //                                          Index 0

    address fromAddress = address(this);
    address toAddress;

    // Step 3: Loop from startIdx to end
    for (uint256 i = startIdx; i < exchanges.length; i++) {
        //              ↑
        //          Starts from startIdx, NOT 0!

        if (
            i + 1 < exchanges.length &&
            isPossibleToAddress(exchanges[i]) &&
            isPossibleFromAddress(exchanges[i + 1])
        ) {
            toAddress = poolAddresses[i + 1];
        } else {
            toAddress = address(this);
        }

        // Step 4: Swap tokenAddresses[i] → tokenAddresses[i + 1]
        amountIn = swap(
            exchanges[i],
            poolAddresses[i],
            fromAddress,
            toAddress,
            tokenAddresses[i],      // ← Token IN at index i
            tokenAddresses[i + 1],  // ← Token OUT at index i+1
            amountIn
        );

        fromAddress = toAddress;
    }

    // Step 5: Measure final balance of FIRST token
    uint256 finalBalance = IERC20(tokenAddresses[0]).balanceOf(address(this));
    //                                             ↑
    //                                         Index 0

    // Step 6: Require profit
    require(
        finalBalance > initialBalance,
        "Arbitrage: No profit - revert transaction"
    );
}
```

---

## 3. The BUG Explained

### Scenario: What if startIdx = 1?

Giả sử có arbitrage path:
```
tokenAddresses = [WBNB, USDT, BUSD, WBNB]
exchanges = [PancakeSwap, Biswap, ApeSwap]
poolAddresses = [pool1, pool2, pool3]
```

Arbitrage path đúng:
```
WBNB → USDT → BUSD → WBNB
 (0)    (1)    (2)    (3)
```

### Nếu startIdx = 0 (CORRECT):

```solidity
// Step 1: Check circular
tokenAddresses[0] == tokenAddresses[3]  // WBNB == WBNB ✓

// Step 2: Initial balance
initialBalance = balanceOf(WBNB)  // ✓

// Step 3: Loop from i=0 to i=2
i=0: Swap WBNB → USDT at PancakeSwap  // ✓
i=1: Swap USDT → BUSD at Biswap       // ✓
i=2: Swap BUSD → WBNB at ApeSwap      // ✓

// Step 4: Final balance
finalBalance = balanceOf(WBNB)  // ✓

// Step 5: Profit check
finalBalance > initialBalance  // ✓
```

✅ **WORKS CORRECTLY**

---

### Nếu startIdx = 1 (WRONG):

```solidity
// Step 1: Check circular
tokenAddresses[0] == tokenAddresses[3]  // WBNB == WBNB ✓

// Step 2: Initial balance
initialBalance = balanceOf(WBNB)  // Measured WBNB

// Step 3: Loop from i=1 to i=2 (SKIPS i=0!)
i=1: Swap USDT → BUSD at Biswap  // ❌ Contract doesn't have USDT!
     tokenAddresses[1] → tokenAddresses[2]
     But we never got USDT because we skipped the first swap!

// REVERT: Insufficient USDT balance!
```

❌ **FAILS: Contract doesn't have USDT to execute the swap!**

**Tại sao fail?**
1. Contract measures initial balance of `tokenAddresses[0]` (WBNB)
2. But loop starts at `i = startIdx = 1`
3. First swap tries to swap `tokenAddresses[1]` (USDT)
4. Contract doesn't have USDT because we skipped the `WBNB → USDT` swap
5. Transaction reverts with "Insufficient balance"

---

## 4. Why Does startIdx Exist?

### Hypothesis: Copied from Sandwich Attack Logic

Trong **sandwich attack**, `startIdx` có ý nghĩa:

**Sandwich FrontRun** (file `ArbitrageSwap_ULTIMATE.sol:78-114`):
```solidity
function sandwichFrontRun(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner notStopped {
    address fromAddress = address(this);
    address toAddress;

    // Loop from 0 to end (NO startIdx parameter)
    for (uint256 i = 0; i < exchanges.length; i++) {
        // Swap forward: token[0] → token[1] → token[2]
    }
}
```

**Sandwich BackRun** (file `ArbitrageSwap_ULTIMATE.sol:154-175`):
```solidity
function _sandwichBackRun(...) internal {
    address fromAddress = address(this);
    address toAddress;

    // Loop BACKWARDS from end to start
    for (uint256 i = exchanges.length; i > 0; i--) {
        // Swap backward: token[2] → token[1] → token[0]
        amountIn = swap(
            exchanges[i - 1],
            poolAddresses[i - 1],
            fromAddress,
            toAddress,
            tokenAddresses[i],      // ← Reverse direction
            tokenAddresses[i - 1],
            amountIn
        );
    }
}
```

**Sandwich attack logic:**
- **FrontRun**: Swap **forward** (0 → 1 → 2)
- **Victim**: Executes transaction
- **BackRun**: Swap **backward** (2 → 1 → 0)

Sandwich không cần `startIdx` vì:
- FrontRun luôn bắt đầu từ token đầu tiên
- BackRun luôn bắt đầu từ token cuối cùng

---

### Arbitrage KHÔNG CẦN startIdx

**Arbitrage logic:**
- **Circular path**: Token đầu == Token cuối (WBNB → ... → WBNB)
- **Single direction**: Chỉ swap một chiều (không có backward)
- **Must complete full cycle**: Phải hoàn thành toàn bộ vòng để về token ban đầu

❌ **startIdx parameter is USELESS for arbitrage!**

**Lý do:**
1. Arbitrage PHẢI bắt đầu từ token đầu tiên (index 0)
2. Arbitrage PHẢI kết thúc tại token cuối cùng (index length-1)
3. Arbitrage PHẢI thực hiện TẤT CẢ swaps (không thể skip)
4. Nếu skip bất kỳ swap nào → Không có token để swap tiếp theo → FAIL

---

## 5. Impact Assessment

### Current Impact: LOW (vì Python hardcode 0)

✅ **Hiện tại KHÔNG có vấn đề** vì:
- Python luôn truyền `startIdx = 0`
- Contract hoạt động đúng với `startIdx = 0`
- Không ai thay đổi giá trị này

### Potential Impact: HIGH (nếu ai đó thay đổi code)

❌ **Rủi ro tiềm ẩn**:
1. **Developer nhầm lẫn**: Ai đó nghĩ có thể skip swaps bằng cách đổi startIdx
2. **Contract vulnerability**: Function signature cho phép `startIdx != 0` → Có thể bị lợi dụng
3. **Gas waste**: Parameter không cần thiết → Tốn gas
4. **Code complexity**: Tăng độ phức tạp không cần thiết

---

## 6. Proof of Concept

### Test Case: startIdx = 1

```solidity
// Arbitrage path: WBNB → USDT → BUSD → WBNB
tokenAddresses = [WBNB, USDT, BUSD, WBNB]
exchanges = [4, 6, 8]  // PancakeSwap, Biswap, ApeSwap
poolAddresses = [pool1, pool2, pool3]
amountIn = 1 WBNB
startIdx = 1  // ❌ WRONG!

// Execution flow:
1. require(WBNB == WBNB) ✓
2. initialBalance = balanceOf(WBNB) = 1 WBNB ✓
3. Loop from i=1:
   i=1: Swap USDT → BUSD
        But contract has 0 USDT!
        Revert: "ERC20: transfer amount exceeds balance"
```

**Expected error:**
```
Revert: ERC20: transfer amount exceeds balance
```

---

## 7. Recommended Fix

### Option 1: Remove startIdx parameter (RECOMMENDED)

**Lý do:**
- ✅ Arbitrage LUÔN LUÔN cần startIdx = 0
- ✅ Giảm complexity
- ✅ Giảm gas cost (uint8 parameter ~ 200 gas)
- ✅ Tránh nhầm lẫn

**Implementation:**

```solidity
// BEFORE (ArbitrageSwap_ULTIMATE.sol:229)
function multiHopArbitrageWithoutRelay(
    uint8 startIdx,      // ❌ Remove this
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner notStopped {
    _executeArbitrage(
        startIdx,        // ❌ Remove this
        amountIn,
        exchanges,
        poolAddresses,
        tokenAddresses
    );
}

// AFTER
function multiHopArbitrageWithoutRelay(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner notStopped {
    _executeArbitrage(
        amountIn,
        exchanges,
        poolAddresses,
        tokenAddresses
    );
}

// Internal function
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

    // Always start from 0
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
```

**Python code changes:**

```python
# BEFORE (src/evm.py:398)
input=[0, amount_in, exchanges, pool_addresses, token_addresses]

# AFTER
input=[amount_in, exchanges, pool_addresses, token_addresses]
```

```python
# BEFORE (src/arbitrage/search.py:310-315)
data=[
    0,  # ❌ Remove
    path.amount_in,
    path.exchanges,
    path.pool_addresses,
    path.token_addresses,
]

# AFTER
data=[
    path.amount_in,
    path.exchanges,
    path.pool_addresses,
    path.token_addresses,
]
```

---

### Option 2: Add validation (NOT RECOMMENDED)

Nếu muốn giữ parameter `startIdx` (không khuyến khích):

```solidity
function _executeArbitrage(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) internal {
    // Validate startIdx MUST be 0 for arbitrage
    require(startIdx == 0, "Arbitrage: startIdx must be 0");

    // ... rest of code
}
```

**Vấn đề:**
- ❌ Vẫn tốn gas cho parameter không cần thiết
- ❌ Validation tốn thêm gas (~200 gas)
- ❌ Code phức tạp hơn

---

## 8. Related Files to Fix

### Contract Files:
1. ✅ `contract/contracts/ArbitrageSwap_COMPLETE.sol`
2. ✅ `contract/contracts/ArbitrageSwap_FIXED.sol`
3. ✅ `contract/contracts/ArbitrageSwap_ULTIMATE.sol`

### Python Files:
1. ✅ `src/evm.py:398` - Remove `0` from input array
2. ✅ `src/arbitrage/search.py:310` - Remove `0` from data array

---

## 9. Conclusion

**BUG SEVERITY:** 🟡 **MEDIUM** (hiện tại) → 🔴 **HIGH** (tiềm ẩn)

**Root Cause:**
- Parameter `startIdx` được copy từ sandwich attack logic
- Không phù hợp với arbitrage logic (phải bắt đầu từ index 0)
- Contract cho phép `startIdx != 0` nhưng sẽ fail nếu sử dụng

**Current Status:**
- ✅ Python hardcode `startIdx = 0` → Hoạt động bình thường
- ❌ Parameter không cần thiết → Lãng phí gas và code complexity

**Recommended Action:**
- 🔨 **Remove `startIdx` parameter completely** (Option 1)
- 🔨 Update contract functions: `multiHopArbitrageWithoutRelay`, `multiHopArbitrageWithBloxroute`, `_executeArbitrage`
- 🔨 Update Python files: `src/evm.py`, `src/arbitrage/search.py`
- 🔨 Redeploy contract với function signature mới

---

## 10. Gas Savings

Removing `startIdx`:
- Parameter cost: ~200 gas per call
- Validation cost (if added): ~200 gas per call
- **Total savings: ~200-400 gas per arbitrage transaction**

Với 1000 arbitrage transactions/day:
- **Daily savings: 200,000 - 400,000 gas**
- **Monthly savings: 6M - 12M gas**

At 5 Gwei gas price và BNB = $600:
- **Monthly savings: ~$18 - $36 USD**

---

**Prepared by:** Claude Code
**Date:** 2025-11-27
**Status:** Critical Bug - Needs Fix
