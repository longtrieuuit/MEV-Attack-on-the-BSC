# ⚠️ Phân Tích Các Functions Bị Thiếu Trong Smart Contract

## 🔍 Tổng Quan

Sau khi scan toàn bộ dự án, tôi phát hiện ra **NHIỀU FUNCTIONS BỊ THIẾU** trong smart contract mà Python code đang gọi. Điều này sẽ gây lỗi khi chạy thực tế.

---

## ❌ Danh Sách Functions Bị Thiếu

### 1. **Arbitrage Functions (CRITICAL)**

#### `multiHopArbitrageWithBloxroute`

**Được gọi trong:**
- `src/arbitrage/search.py:305`
- `src/apis/transaction.py:49` (ABI definition)
- `contract/test/ArbitrageSwap.ts:114` (test file)

**ABI Definition:**
```javascript
{
    "inputs": [
        {"internalType": "uint8", "name": "startIdx", "type": "uint8"},
        {"internalType": "uint256", "name": "amountIn", "type": "uint256"},
        {"internalType": "uint8[]", "name": "exchanges", "type": "uint8[]"},
        {"internalType": "address[]", "name": "poolAddresses", "type": "address[]"},
        {"internalType": "address[]", "name": "tokenAddresses", "type": "address[]"}
    ],
    "name": "multiHopArbitrageWithBloxroute",
    "outputs": [],
    "stateMutability": "payable",
    "type": "function"
}
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

**Expected Location:** `contract/contracts/ArbitrageSwap.sol`

---

#### `multiHopArbitrageWithoutRelay`

**Được gọi trong:**
- `src/evm.py:392`
- `src/apis/transaction.py:82` (ABI definition)
- `src/arbitrage/simulation.py` (via evm.send_arbitrage)

**ABI Definition:**
```javascript
{
    "inputs": [
        {"internalType": "uint8", "name": "startIdx", "type": "uint8"},
        {"internalType": "uint256", "name": "amountIn", "type": "uint256"},
        {"internalType": "uint8[]", "name": "exchanges", "type": "uint8[]"},
        {"internalType": "address[]", "name": "poolAddresses", "type": "address[]"},
        {"internalType": "address[]", "name": "tokenAddresses", "type": "address[]"}
    ],
    "name": "multiHopArbitrageWithoutRelay",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
}
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

**Expected Location:** `contract/contracts/ArbitrageSwap.sol`

---

### 2. **Optimization Functions (Used by Sandwich)**

#### `optimizedSwapUniswapV2`

**Được gọi trong:**
- `src/sandwich/optimization.py:33`

**Expected Signature:**
```solidity
function optimizedSwapUniswapV2(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

---

#### `optimizedSwapUniswapV3`

**Được gọi trong:**
- `src/sandwich/optimization.py:51`

**Expected Signature:**
```solidity
function optimizedSwapUniswapV3(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

---

#### `optimizedSwapUniswapV2V3`

**Được gọi trong:**
- `src/sandwich/optimization.py:73`

**Expected Signature:**
```solidity
function optimizedSwapUniswapV2V3(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

---

#### `multiHopSwap`

**Được gọi trong:**
- `src/evm.py:337`
- `src/evm.py:365`
- `src/sandwich/optimization.py:108`

**Expected Signature:**
```solidity
function multiHopSwap(
    uint256[] memory amountsIn,
    uint256[] memory stages,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses,
    uint256[] memory preserveAmounts
) external onlyOwner
```

**Solidity Implementation:** ❌ **KHÔNG TỒN TẠI**

---

## ✅ Functions Tồn Tại (Sandwich Only)

### Trong `contract/contracts/ArbitrageSwap.sol`:

1. ✅ `sandwichFrontRun` (line 36-56)
2. ✅ `sandwichFrontRunDifficult` (line 58-86)
3. ✅ `sandwichBackRunWithBloxroute` (line 88-96)
4. ✅ `sandwichBackRun` (line 98-106)
5. ✅ `sandwichBackRunDifficult` (line 108-123)
6. ✅ `_sandwichBackRun` (line 125-145) - internal

---

## 🔴 Impact Analysis

### Arbitrage Flow - HOÀN TOÀN KHÔNG HOẠT ĐỘNG

**Flow hiện tại:**
```
main.py:65
  ↓ search_arbitrage()
  ↓ src/arbitrage/search.py:305
  ↓ function_name = "multiHopArbitrageWithBloxroute" ← BỊ THIẾU!
  ↓
  ↓ simulate_arbitrage()
  ↓ src/arbitrage/simulation.py:131
  ↓ evm.send_arbitrage()
  ↓ src/evm.py:392
  ↓ function_name = "multiHopArbitrageWithoutRelay" ← BỊ THIẾU!
  ↓
  ↓ call_function() ← SẼ BÁO LỖI!
```

**Error sẽ gặp:**
```python
# src/evm.py:258-260
function_signature = None
for item in abi:
    if item["name"] == function_name:
        function_signature = item

assert function_signature is not None, f"Function {function_name} not found in ABI"
# ↑ LỖI: Function không có trong ABI của compiled contract
```

**Hoặc:**
```
# Nếu chạy real transaction
Error: function selector was not recognized and there's no fallback function
```

---

### Sandwich Flow - MỘT PHẦN HOẠT ĐỘNG

**Functions có:**
- ✅ `sandwichFrontRun` - Hoạt động
- ✅ `sandwichBackRunWithBloxroute` - Hoạt động

**Functions thiếu:**
- ❌ `optimizedSwapUniswapV2` - Fallback về `sandwichFrontRun`
- ❌ `optimizedSwapUniswapV3` - Fallback về `sandwichFrontRun`
- ❌ `multiHopSwap` - Fallback về `sandwichFrontRun`

**Code trong `src/sandwich/optimization.py`:**
```python
# Line 33
front_run_function_name = "optimizedSwapUniswapV2"  # BỊ THIẾU!

# Line 51
front_run_function_name = "optimizedSwapUniswapV3"  # BỊ THIẾU!

# Line 73
front_run_function_name = "optimizedSwapUniswapV2V3"  # BỊ THIẾU!

# Line 108
front_run_function_name = "multiHopSwap"  # BỊ THIẾU!
```

**Impact:** Sandwich có fallback logic, sẽ không crash nhưng mất tính năng optimization.

---

## 📂 File Structure Analysis

### Current Structure:
```
contract/
├── contracts/
│   ├── BSC.sol                    ← Main contract (chỉ inherit)
│   ├── ArbitrageSwap.sol          ← Chỉ có Sandwich functions!
│   ├── SwapCallBack.sol           ← Callback handlers
│   ├── SwapRouter.sol             ← swap() function
│   ├── Balance.sol                ← withdraw/deposit
│   └── dexes/
│       ├── UniswapV2.sol
│       ├── UniswapV3.sol
│       └── ...
└── bytecode/
    └── (KHÔNG TỒN TẠI!)           ← Contract chưa compile!
```

**Problems:**
1. `ArbitrageSwap.sol` tên file gợi ý có arbitrage, nhưng CHỈ có sandwich functions
2. Không có file nào chứa arbitrage logic
3. Bytecode folder không tồn tại → contract chưa được compile

---

## 💡 Recommended Implementation

### Function: `multiHopArbitrageWithoutRelay`

**Location:** `contract/contracts/ArbitrageSwap.sol`

**Suggested Implementation:**
```solidity
function multiHopArbitrageWithoutRelay(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner {
    // Validate: tokenAddresses[0] == tokenAddresses[end] (circular path)
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
        // Optimize token transfers (same as sandwichFrontRun)
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
        "Arbitrage: No profit"
    );
}
```

---

### Function: `multiHopArbitrageWithBloxroute`

**Location:** `contract/contracts/ArbitrageSwap.sol`

**Suggested Implementation:**
```solidity
function multiHopArbitrageWithBloxroute(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external payable onlyOwner {
    // Execute arbitrage
    multiHopArbitrageWithoutRelay(
        startIdx,
        amountIn,
        exchanges,
        poolAddresses,
        tokenAddresses
    );

    // Pay bloXroute fee
    payable(bloxrouteAddress).transfer(msg.value);
}
```

---

### Function: `multiHopSwap`

**Location:** `contract/contracts/ArbitrageSwap.sol`

**Suggested Implementation:**
```solidity
function multiHopSwap(
    uint256[] memory amountsIn,
    uint256[] memory stages,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses,
    uint256[] memory preserveAmounts
) external onlyOwner {
    uint256 stageIdx = 0;
    uint256 amountIdx = 0;

    for (uint256 i = 0; i < stages.length; i++) {
        uint256 stageEnd = stages[i];
        address fromAddress = address(this);
        address toAddress;
        uint256 amountIn = amountsIn[amountIdx];

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

        // Validate minimum output
        if (preserveAmounts[i] > 0) {
            require(
                amountIn >= preserveAmounts[i],
                "MultiHopSwap: Insufficient output"
            );
        }

        stageIdx = stageEnd;
        amountIdx++;
    }
}
```

---

### Functions: `optimizedSwapUniswapV2`, `optimizedSwapUniswapV3`, `optimizedSwapUniswapV2V3`

**Note:** Đây là các optimized versions của `sandwichFrontRun` cho specific DEX types.

**Location:** `contract/contracts/ArbitrageSwap.sol`

**Suggested Implementation:**
```solidity
// Optimized for UniswapV2 only (fewer checks)
function optimizedSwapUniswapV2(
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner {
    // Assumption: All exchanges are UniswapV2
    // Skip isUniswapV2() checks for gas savings

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

        // Direct call to uniswapV2Swap (no routing)
        uniswapV2Swap(
            poolAddresses[i],
            fromAddress,
            tokenAddresses[i],
            tokenAddresses[i + 1],
            amountIn
        );

        // Get actual output
        amountIn = IERC20(tokenAddresses[i + 1]).balanceOf(toAddress);
        fromAddress = toAddress;
    }
}

// Similar for V3 and V2V3
function optimizedSwapUniswapV3(...) external onlyOwner {
    // Optimized for UniswapV3
}

function optimizedSwapUniswapV2V3(...) external onlyOwner {
    // Optimized for mixed V2/V3
}
```

---

## 🛠️ How to Fix

### Step 1: Add Missing Functions to Contract

**File:** `contract/contracts/ArbitrageSwap.sol`

Add sau function `_sandwichBackRun`:

```solidity
// ============ Arbitrage Functions ============

function multiHopArbitrageWithoutRelay(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external onlyOwner {
    // Implementation above
}

function multiHopArbitrageWithBloxroute(
    uint8 startIdx,
    uint256 amountIn,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses
) external payable onlyOwner {
    // Implementation above
}

// ============ Multi-Hop Swap ============

function multiHopSwap(
    uint256[] memory amountsIn,
    uint256[] memory stages,
    uint8[] memory exchanges,
    address[] memory poolAddresses,
    address[] memory tokenAddresses,
    uint256[] memory preserveAmounts
) external onlyOwner {
    // Implementation above
}

// ============ Optimized Swaps ============

function optimizedSwapUniswapV2(...) external onlyOwner {
    // Implementation above
}

function optimizedSwapUniswapV3(...) external onlyOwner {
    // Implementation above
}

function optimizedSwapUniswapV2V3(...) external onlyOwner {
    // Implementation above
}
```

---

### Step 2: Compile Contract

```bash
cd contract
npm install
npx hardhat compile
```

**Expected Output:**
```
Compiled 30 Solidity files successfully
```

**Verify bytecode:**
```bash
ls -la artifacts/contracts/BSC.sol/
# Should contain: BSC.json, BSC.dbg.json
```

---

### Step 3: Update Python ABI (if needed)

File: `src/apis/transaction.py`

ABI đã có sẵn (lines 20-328), chỉ cần contract có implementation.

---

### Step 4: Deploy New Contract

```bash
npx hardhat run scripts/deploy.js --network bsc
```

Update contract address trong config:
```python
# src/config.py
contract_address = "0x..." # New deployed address
```

---

### Step 5: Test

```bash
# Test arbitrage
npx hardhat test test/ArbitrageSwap.ts

# Test in Python
python -m pytest tests/test_arbitrage.py
```

---

## 📊 Summary Table

| Function Name | Expected In | Actually In | Status | Impact |
|---------------|-------------|-------------|--------|--------|
| `multiHopArbitrageWithBloxroute` | ArbitrageSwap.sol | ❌ None | **CRITICAL** | Arbitrage không hoạt động |
| `multiHopArbitrageWithoutRelay` | ArbitrageSwap.sol | ❌ None | **CRITICAL** | Arbitrage simulation fail |
| `multiHopSwap` | ArbitrageSwap.sol | ❌ None | **HIGH** | Sandwich optimization fail |
| `optimizedSwapUniswapV2` | ArbitrageSwap.sol | ❌ None | **MEDIUM** | Fallback to normal swap |
| `optimizedSwapUniswapV3` | ArbitrageSwap.sol | ❌ None | **MEDIUM** | Fallback to normal swap |
| `optimizedSwapUniswapV2V3` | ArbitrageSwap.sol | ❌ None | **MEDIUM** | Fallback to normal swap |
| `sandwichFrontRun` | ArbitrageSwap.sol | ✅ Line 36 | **OK** | Working |
| `sandwichBackRunWithBloxroute` | ArbitrageSwap.sol | ✅ Line 88 | **OK** | Working |
| `sandwichBackRun` | ArbitrageSwap.sol | ✅ Line 98 | **OK** | Working |

---

## ⚠️ Critical Issues

### Issue 1: Arbitrage Hoàn Toàn Không Hoạt Động

**Proof:**
```bash
# Chạy arbitrage bot
python main.py

# Sẽ crash khi tìm thấy opportunity:
# File "src/evm.py", line 258
# AssertionError: Function multiHopArbitrageWithoutRelay not found in ABI
```

**Impact:**
- 100% arbitrage opportunities bị bỏ lỡ
- Bot chỉ chạy được sandwich mode

---

### Issue 2: Bytecode Không Tồn Tại

**Proof:**
```bash
ls contract/bytecode/contracts/BSC.sol/
# ls: cannot access 'contract/bytecode/contracts/BSC.sol/': No such file or directory
```

**Impact:**
- `src/evm.py:146` sẽ crash khi deploy contract for testing
- Không thể test trên local

---

### Issue 3: Test File Reference Missing Functions

**File:** `contract/test/ArbitrageSwap.ts:114`

```typescript
await contract.multiHopArbitrageWithBloxroute(
    0, amountIn, exchanges, POOL_ADDRESSES, TOKEN_ADDRESSES,
    {value:10n ** 1n}
);
```

**Impact:** Test sẽ fail nếu chạy.

---

## 🎯 Recommended Action Plan

### Priority 1 (CRITICAL - Do Now):
1. ✅ Implement `multiHopArbitrageWithoutRelay`
2. ✅ Implement `multiHopArbitrageWithBloxroute`
3. ✅ Compile contract
4. ✅ Deploy to testnet
5. ✅ Test arbitrage flow

### Priority 2 (HIGH - Do This Week):
1. ✅ Implement `multiHopSwap`
2. ✅ Test sandwich optimization

### Priority 3 (MEDIUM - Nice to Have):
1. ✅ Implement `optimizedSwapUniswapV2`
2. ✅ Implement `optimizedSwapUniswapV3`
3. ✅ Implement `optimizedSwapUniswapV2V3`
4. ✅ Gas optimization testing

---

## 📝 Conclusion

**Current State:**
- Dự án có đầy đủ Python code cho arbitrage
- Dự án có đầy đủ ABI definitions
- Dự án có test files
- **NHƯNG:** Smart contract THIẾU toàn bộ arbitrage implementation!

**Root Cause:**
- File `ArbitrageSwap.sol` có tên gợi ý arbitrage
- Nhưng chỉ implement sandwich functions
- Có thể do:
  - Code bị mất khi migrate
  - Hoặc chưa implement xong
  - Hoặc developer quên commit

**Next Steps:**
1. Implement missing functions (code samples provided above)
2. Compile & deploy
3. Test thoroughly
4. Update documentation

---

*Document này được tạo bởi Claude Code sau khi scan toàn bộ codebase*

*Ngày: 2025-11-27*

*Status: CRITICAL - Requires Immediate Action*
