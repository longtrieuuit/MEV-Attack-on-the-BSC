# Phân Tích Workflow Dự Án MEV Attack on BSC

## Tổng Quan Dự Án

Dự án này triển khai một hệ thống MEV (Maximal Extractable Value) Attack hoàn chỉnh trên Binance Smart Chain (BSC), bao gồm 2 loại tấn công chính:
- **Sandwich Attack**: Tấn công bằng cách đặt transaction trước và sau transaction của nạn nhân
- **Arbitrage Attack**: Khai thác chênh lệch giá giữa các DEX

## Kiến Trúc Tổng Thể

```
┌─────────────────────────────────────────────────────────────────┐
│                        MEV ATTACK SYSTEM                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐      ┌──────────────┐      ┌──────────────┐ │
│  │ Infrastructure│      │   Mempool    │      │   Analysis   │ │
│  │    Layer      │─────▶│   Stream     │─────▶│   Engine     │ │
│  │   (IAC/Node)  │      │  (bloXroute) │      │   (Python)   │ │
│  └──────────────┘      └──────────────┘      └──────────────┘ │
│         │                      │                      │         │
│         │                      │                      ▼         │
│         │                      │           ┌──────────────┐    │
│         │                      │           │  EVM Simulate│    │
│         │                      │           │   (pyREVM)   │    │
│         │                      │           └──────────────┘    │
│         │                      │                      │         │
│         │                      ▼                      ▼         │
│         │           ┌──────────────────────────────────────┐   │
│         └──────────▶│      Transaction Submission          │   │
│                     │  ┌────────┬──────────┬───────────┐   │   │
│                     │  │General │bloXroute │ 48 Club   │   │   │
│                     │  │ Path   │  Path    │   Path    │   │   │
│                     │  └────────┴──────────┴───────────┘   │   │
│                     └──────────────────────────────────────┘   │
│                                    │                            │
│                                    ▼                            │
│                          ┌──────────────┐                       │
│                          │ Smart Contract│                      │
│                          │  (Solidity)   │                      │
│                          └──────────────┘                       │
│                                    │                            │
│                                    ▼                            │
│                          ┌──────────────┐                       │
│                          │  DEX Pools   │                       │
│                          │ (UniswapV2/V3│                       │
│                          │  Curve, etc) │                       │
│                          └──────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## 1. Cấu Trúc Thư Mục

```
MEV-Attack-on-the-BSC/
├── contract/                    # Smart contracts (Solidity)
│   ├── contracts/
│   │   ├── BSC.sol             # Main contract cho BSC
│   │   ├── ETH.sol             # Main contract cho Ethereum
│   │   ├── ArbitrageSwap.sol   # Arbitrage logic
│   │   ├── SwapCallBack.sol    # Callback handlers
│   │   └── dexes/              # DEX implementations
│   │       ├── SwapRouter.sol  # Universal swap router
│   │       ├── uniswapV2/      # Uniswap V2 family
│   │       ├── uniswapV3/      # Uniswap V3 family
│   │       └── Curve.sol       # Curve pools
│   └── test/                   # Test files
│
├── src/                        # Python source code
│   ├── sandwich/               # Sandwich attack logic
│   │   ├── search.py          # Tìm kiếm cơ hội sandwich
│   │   ├── optimization.py    # Tối ưu hóa parameters
│   │   └── simulation.py      # Simulate sandwich attack
│   ├── arbitrage/             # Arbitrage attack logic
│   │   └── search.py          # Tìm kiếm cơ hội arbitrage
│   ├── apis/                  # API và utilities
│   │   ├── subscribe.py       # Stream mempool
│   │   ├── trace_tx.py        # Trace transactions
│   │   ├── transaction.py     # Submit transactions
│   │   └── contract.py        # Contract interactions
│   ├── dex/                   # DEX AMM implementations
│   ├── evm.py                 # EVM simulator wrapper
│   ├── formula.py             # Mathematical formulas
│   ├── types.py               # Data types
│   └── config.py              # Configuration
│
├── iac/                       # Infrastructure as Code
│   ├── aws/                   # AWS deployment
│   └── gcp/                   # GCP deployment (deprecated)
│
├── pyrevm/                    # Python EVM wrapper
├── docker/                    # Docker configurations
├── main.py                    # Arbitrage main entry
└── main_sandwich.py           # Sandwich main entry
```

## 2. Workflow Chi Tiết - Sandwich Attack

### 2.1. Khởi Động Hệ Thống

```
┌─────────────────────────────────────────────────────────────┐
│                    SYSTEM INITIALIZATION                     │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Load Configuration                  │
         │  - BSC node endpoint                 │
         │  - Contract addresses                │
         │  - Account credentials               │
         │  - MEV-Relay settings               │
         └──────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Fetch Pool List from CoinMarketCap │
         │  - Top liquidity pools              │
         │  - Token pair information            │
         └──────────────────────────────────────┘
                            │
                            ▼
         ┌──────────────────────────────────────┐
         │  Setup Multiprocessing               │
         │  - 6 worker processes                │
         │  - Queue (maxsize=40)                │
         │  - Shared memory for block number    │
         └──────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
    ┌─────────────────┐         ┌─────────────────┐
    │ Stream Process  │         │ Worker Processes│
    │ (Mempool/Block) │         │   (6 instances) │
    └─────────────────┘         └─────────────────┘
```

**File**: `main_sandwich.py:208-237`

**Process**:
1. Tạo multiprocessing Queue để truyền transactions
2. Tạo shared Value để lưu block number
3. Spawn 6 worker processes xử lý song song
4. Spawn stream process để nhận mempool
5. Spawn process để track validator addresses

### 2.2. Mempool Streaming & Transaction Filtering

```
┌────────────────────────────────────────────────────────────────┐
│                    MEMPOOL STREAM PROCESS                      │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  bloXroute Mempool Stream    │
              │  - Receive pending txs        │
              │  - ~200ms faster than local   │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Filter Transaction           │
              │  ✓ Has gas information        │
              │  ✓ Has data (contract call)   │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Trace Transaction            │
              │  - debug_traceCall            │
              │  - Analyze function calls     │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Detect Swap Events           │
              │  - 0x022c0d9f (UniswapV2)    │
              │  - 0x128acb08 (UniswapV3)    │
              │  - 0x6d9a640a (BakerySwap)   │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Extract Token Transfers      │
              │  - 0xa9059cbb (transfer)     │
              │  - 0x23b872dd (transferFrom) │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Build Transaction Object     │
              │  - Swap events                │
              │  - Token addresses            │
              │  - Pool addresses             │
              │  - Amounts                    │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Push to Queue                │
              │  (for worker processes)       │
              └───────────────────────────────┘
```

**File**: `src/apis/trace_tx.py:212-278`

**Key Functions**:
- `search_dex_transaction()`: Phát hiện swap function calls
- `set_transfer_event()`: Extract token transfer information
- `filter_swap_events()`: Validate swap events

### 2.3. Sandwich Opportunity Analysis

```
┌────────────────────────────────────────────────────────────────┐
│                    WORKER PROCESS (x6)                         │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Get Transaction from Queue   │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Validate Transaction         │
              │  ✓ Still in mempool?          │
              │  ✓ Block not too old?         │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Search Sandwich Candidate    │
              │  - Find linking pools         │
              │  - Check liquidity            │
              └───────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        ▼                                           ▼
┌──────────────────┐                    ┌──────────────────┐
│ Native Token Swap│                    │Non-Native Token  │
│ (WBNB directly)  │                    │     Swap         │
└──────────────────┘                    └──────────────────┘
        │                                           │
        │                              ┌────────────┘
        │                              │
        │                              ▼
        │                   ┌─────────────────────┐
        │                   │ Find Link Pool      │
        │                   │ WBNB ↔ Token       │
        │                   │ (highest liquidity) │
        │                   └─────────────────────┘
        │                              │
        └──────────────┬───────────────┘
                       ▼
        ┌──────────────────────────────┐
        │  Build Candidate Path        │
        │  - Exchanges (DEX IDs)       │
        │  - Pool addresses            │
        │  - Token addresses           │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Quick Check (Uniswap V2)    │
        │  - Use optimized formula     │
        │  - Calculate expected profit │
        │  - Min: 100K gas * 2tx       │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Detailed Simulation (EVM)   │
        │  - pyREVM simulation         │
        │  - Optimize amount_in        │
        │  - Calculate gas used        │
        └──────────────────────────────┘
                       │
                       ▼
        ┌──────────────────────────────┐
        │  Profitability Check         │
        │  Revenue > Gas Cost?         │
        └──────────────────────────────┘
                       │
            Yes        │        No
        ┌──────────────┴──────────────┐
        ▼                             ▼
┌──────────────┐              ┌─────────────┐
│ Continue to  │              │   Discard   │
│ Submission   │              └─────────────┘
└──────────────┘
```

**File**: `src/sandwich/search.py:123-224`

**Key Steps**:
1. **Candidate Path Search**: Tìm pools phù hợp cho attack (`search_sandwich_candidate_path`)
2. **Quick Calculation**: Với Uniswap V2, dùng công thức tối ưu (`calculate_uniswap_v2_sandwich`)
3. **EVM Simulation**: Simulate chính xác với pyREVM (`simulate_sandwich`)
4. **Optimization**: Tối ưu hóa amount_in để maximize profit

### 2.4. Path Selection & Transaction Submission

```
┌────────────────────────────────────────────────────────────────┐
│               DETERMINE SUBMISSION PATH                        │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Get Next Block Validator     │
              └───────────────────────────────┘
                              │
        ┌─────────────────────┼─────────────────────┐
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────┐  ┌─────────────────┐  ┌──────────────────┐
│   bloXroute   │  │    48 Club      │  │     General      │
│   Validator   │  │   Validator     │  │  (Other/None)    │
└───────────────┘  └─────────────────┘  └──────────────────┘
        │                     │                     │
        ▼                     ▼                     ▼
┌───────────────────────────────────────────────────────────┐
│                   bloXroute PATH                          │
├───────────────────────────────────────────────────────────┤
│  1. Calculate Gas Prices                                  │
│     back_run_gas_price = (victim_gas + back_run_gas)     │
│                          / back_run_gas * 1e9            │
│                                                           │
│  2. Calculate Bundle Fee (98% of remaining profit)        │
│     bundle_fee = (revenue - front_gas - back_gas) * 0.98 │
│                                                           │
│  3. Prepare Transactions                                  │
│     - FrontRun: sandwichFrontRun (simplified)            │
│     - Victim: original transaction                        │
│     - BackRun: sandwichBackRunWithBloxroute              │
│                                                           │
│  4. Submit Bundle                                         │
│     POST to bloXroute API                                 │
│     - Bundle: [frontrun, victim, backrun]                │
│     - Fee paid in backrun transaction                     │
│                                                           │
│  ✓ Transaction order guaranteed                           │
│  ✓ Atomic execution (all or nothing)                      │
│  ✓ No gas cost if failed                                  │
│  ✗ High competition & fees                                │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│                    48 CLUB PATH                           │
├───────────────────────────────────────────────────────────┤
│  1. Calculate Fee Transaction Gas Price                   │
│     gas_price = (revenue - front_gas - back_gas)         │
│                 / 21000 * 0.98                            │
│                                                           │
│  2. Check Minimum Gas Price                               │
│     GET 48 Club minimum from API                          │
│                                                           │
│  3. Prepare Transactions                                  │
│     - Fee Tx: self-transfer with high gas price          │
│     - FrontRun: sandwichFrontRun (simplified)            │
│     - Victim: original transaction                        │
│     - BackRun: sandwichBackRun                           │
│                                                           │
│  4. Submit Bundle                                         │
│     POST to 48 Club Puissant API                          │
│                                                           │
│  ✓ Transaction order guaranteed                           │
│  ✓ No base cost                                           │
│  ✗ Fee paid via separate transaction                      │
│  ⚠ Puissant deprecated (as of May 2024)                  │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│                    GENERAL PATH                           │
├───────────────────────────────────────────────────────────┤
│  1. Check for Arbitrage Competition                       │
│     Skip if arbitrage opportunity > 0.01 BNB             │
│                                                           │
│  2. Calculate Profit                                      │
│     expected_profit = revenue - (front_gas + back_gas)   │
│     Minimum: 0.001 BNB                                    │
│                                                           │
│  3. Set Gas Price                                         │
│     front_run_gas_price = victim_gas + 1                 │
│     OR 30% of profit / front_gas (whichever higher)      │
│                                                           │
│  4. Use "Difficult" Functions                            │
│     - sandwichFrontRunDifficult                          │
│     - sandwichBackRunDifficult                           │
│     (with block number validation)                        │
│                                                           │
│  5. Wait for Block Timing                                │
│     delay_time() - wait near block boundary              │
│                                                           │
│  6. Submit Transactions Separately                        │
│     - Send frontrun                                       │
│     - Send backrun                                        │
│                                                           │
│  7. Monitor Results                                       │
│     If frontrun success BUT backrun failed:              │
│     → Send recovery transaction                           │
│                                                           │
│  ✗ No transaction order guarantee                         │
│  ✗ Risk of being front-run by others                      │
│  ✗ Gas cost even if failed                                │
│  ✓ No MEV-relay fees                                      │
└───────────────────────────────────────────────────────────┘
```

**File**: `main_sandwich.py:94-174`

**Path Selection Logic**:
- `accessible_block_number > 0` → bloXroute
- `accessible_block_number == -1` → 48 Club
- `accessible_block_number == 0` → General

### 2.5. Smart Contract Execution

```
┌────────────────────────────────────────────────────────────────┐
│                   SMART CONTRACT FLOW                          │
└────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│                      FRONT RUN                              │
├─────────────────────────────────────────────────────────────┤
│  sandwichFrontRun(                                          │
│    uint256 amountIn,          // WBNB amount                │
│    uint16[] exchanges,        // DEX IDs                    │
│    address[] poolAddresses,   // Pool addresses             │
│    address[] tokenAddresses   // Token path                 │
│  )                                                          │
│                                                             │
│  Flow:                                                      │
│  1. Wrap BNB → WBNB (if needed)                            │
│  2. Approve WBNB to first pool                             │
│  3. Swap WBNB → Token                                       │
│  4. If 2-hop: Swap Token → Target Token                    │
│  5. Store balances for backrun                             │
│                                                             │
│  Result: Contract holds victim's target token              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
         [Victim Transaction Executes]
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                      BACK RUN                               │
├─────────────────────────────────────────────────────────────┤
│  sandwichBackRun(                                           │
│    uint256 amountIn,          // Token amount from frontrun │
│    uint16[] exchanges,        // DEX IDs (reversed)         │
│    address[] poolAddresses,   // Pool addresses (reversed)  │
│    address[] tokenAddresses   // Token path (reversed)      │
│  )                                                          │
│                                                             │
│  Flow:                                                      │
│  1. Approve token to pool                                   │
│  2. If 2-hop: Swap Target Token → Intermediate Token       │
│  3. Swap Token → WBNB                                       │
│  4. Unwrap WBNB → BNB                                       │
│  5. Calculate profit                                        │
│  6. Send profit to owner                                    │
│                                                             │
│  For bloXroute:                                             │
│  sandwichBackRunWithBloxroute() - pays fee to validator    │
└─────────────────────────────────────────────────────────────┘
```

**Files**:
- `contract/contracts/BSC.sol`
- `contract/contracts/dexes/SwapRouter.sol`

**Supported DEXes**:
- Uniswap V2 Family: PancakeSwap, SushiSwap, BiSwap, ApeSwap, etc.
- Uniswap V3 Family: PancakeSwap V3, SushiSwap V3, THENA FUSION
- Curve: Major stable pools

## 3. Workflow Chi Tiết - Arbitrage Attack

```
┌────────────────────────────────────────────────────────────────┐
│                    ARBITRAGE WORKFLOW                          │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Detect Price Change Tx       │
              │  (from mempool stream)        │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Analyze All DEX Pools        │
              │  - Find pools with same pair  │
              │  - Calculate price difference │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Multi-hop Path Finding       │
              │  - 2-hop: Pool A → Pool B     │
              │  - 3-hop: A → B → C           │
              │  - 4-hop: A → B → C → D       │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Calculate Optimal Amount     │
              │  - Use multi-hop formula      │
              │  - Maximize profit            │
              └───────────────────────────────┘
                              │
                              ▼
              ┌───────────────────────────────┐
              │  Submit (General Path Only)   │
              │  - No bundle support          │
              │  - High risk, low competition │
              └───────────────────────────────┘
```

**File**: `src/arbitrage/search.py`

**Note**: Arbitrage chỉ dùng General path vì:
- Sandwich thường profitable hơn → thua trong bundle bidding
- Không đủ tối ưu node để compete trên General path
- Cần capital lớn để có lợi nhuận

## 4. Các Công Thức Toán Học Quan Trọng

### 4.1. Uniswap V2 Optimized Swap Formula

**Formula gốc**:
```
y = (997 * R_out * x) / (1000 * R_in + 997 * x)
```

**Formula tối ưu** (lấy max token có thể):
```
y ≤ R_out - ⌊(n * R_in * R_out) / (n * (R_in + x) - s * x)⌋

Trong đó:
- n = 1000 (Uniswap V2)
- s = 3 (Uniswap V2)
- x = amount in
- y = optimal amount out
- R_in, R_out = reserves
```

**Implementation**: `src/formula.py`

### 4.2. Multi-hop Arbitrage Formula

**2-hop**: Tìm x để maximize lợi nhuận khi đi qua 2 pools

```
k = (n-s)*n*R₂_in + (n-s)²*R₁_out
a = k²
b = 2*n²*R₁_in*R₂_in*k
c = (n²*R₁_in*R₂_in)² - (n-s)²*n²*R₁_in*R₂_in*R₁_out*R₂_out

x* = (-b + √(b² - 4ac)) / (2a)
```

**Generalized n-hop**:

```
k = (n-s)*n^(h-1) * ∏(i=2 to h)[R_i_in] + Σ(j=2 to h)[(n-s)^j * n^(h-j) * ∏R_out * ∏R_in]
a = k²
b = 2*n^h * ∏R_in * k
c = (n^h * ∏R_in)² - (n-s)^h * n^h * ∏R_in * ∏R_out

x* = (-b + √(b² - 4ac)) / (2a)
```

**Implementation**: `src/formula.py::get_multi_hop_optimal_amount_in`

## 5. Infrastructure & Deployment

### 5.1. Node Requirements

```
┌─────────────────────────────────────────────────────┐
│               NODE INFRASTRUCTURE                   │
├─────────────────────────────────────────────────────┤
│  Location:                                          │
│  ✓ New York / Germany (closest to BSC validators)  │
│  ✗ NOT Asia (too far, high latency)                │
│                                                     │
│  Setup:                                             │
│  - BSC Full Node (Geth)                             │
│  - Python MEV client (same instance)                │
│  - NO load balancer (minimize latency)              │
│                                                     │
│  Resources:                                         │
│  - CPU: High performance                            │
│  - Memory: 32GB+ for Geth                           │
│  - Storage: Fast SSD, snapshots enabled             │
│  - Network: Low latency connection                  │
│                                                     │
│  Monitoring:                                        │
│  - Regular snapshots (Geth can corrupt)             │
│  - Mempool sync performance                         │
│  - Transaction success rate                         │
└─────────────────────────────────────────────────────┘
```

**IAC**: `iac/aws/` (Pulumi-based)

### 5.2. External Dependencies

```
┌─────────────────────────────────────────────────────┐
│              EXTERNAL SERVICES                      │
├─────────────────────────────────────────────────────┤
│  bloXroute:                                         │
│  - Base cost: $5,000/month                          │
│  - Bundle submission API                            │
│  - Mempool streaming (~200ms faster)                │
│  - Validator list API                               │
│                                                     │
│  48 Club:                                           │
│  - Free (via Soul Points → 0 Gwei)                  │
│  - Puissant Builder API                             │
│  - Bundle submission                                │
│  ⚠ Deprecated as of May 2024                        │
│                                                     │
│  CoinMarketCap:                                     │
│  - Pool list fetching                               │
│  - Liquidity ranking                                │
│                                                     │
│  BSC Node:                                          │
│  - RPC endpoint (local or remote)                   │
│  - WebSocket for subscriptions                      │
│  - debug_traceCall support required                 │
└─────────────────────────────────────────────────────┘
```

## 6. Performance Considerations

### 6.1. Bottlenecks

```
┌─────────────────────────────────────────────────────┐
│              PERFORMANCE CRITICAL PATHS             │
├─────────────────────────────────────────────────────┤
│  1. Mempool Reception (200ms advantage)             │
│     bloXroute > Local Node                          │
│                                                     │
│  2. Transaction Trace (~50-100ms)                   │
│     debug_traceCall - can be slow                   │
│     → Multiprocessing helps                         │
│                                                     │
│  3. EVM Simulation (~10-50ms)                       │
│     pyREVM - reasonably fast                        │
│     → Skip for Uniswap V2 (use formula)             │
│                                                     │
│  4. Bundle Submission (~100-200ms)                  │
│     Network latency to MEV-Relay                    │
│     → Node location critical                        │
│                                                     │
│  Total latency budget: ~500ms max                   │
│  (3 second block time on BSC)                       │
└─────────────────────────────────────────────────────┘
```

### 6.2. Optimization Techniques

1. **Quick Path for Uniswap V2**: Dùng công thức tối ưu thay vì EVM simulation
2. **Multiprocessing**: 6 workers xử lý song song
3. **bloXroute Mempool**: Nhanh hơn 200ms so với local node
4. **Co-location**: MEV client và node cùng instance
5. **Filtered Pools**: Chỉ theo dõi top liquidity pools

## 7. Risk & Capital Requirements

### 7.1. Capital Requirements

```
Sandwich Attack:
- Minimum: ~$100K (theo FAQ)
- Optimal: $1M+
- Lý do: Cần liquidity đủ lớn để impact price significantly

Arbitrage Attack:
- Có thể nhỏ hơn
- Nhưng profit thấp, competition cao
```

### 7.2. Risks

```
┌─────────────────────────────────────────────────────┐
│                    ATTACK RISKS                     │
├─────────────────────────────────────────────────────┤
│  General Path:                                      │
│  ✗ Transaction order not guaranteed                 │
│  ✗ Can be front-run by others                       │
│  ✗ Gas cost even if failed                          │
│  ✗ Victim tx may fail/cancel                        │
│                                                     │
│  MEV-Relay (bloXroute/48Club):                      │
│  ✓ Order guaranteed                                 │
│  ✓ No cost if bundle fails                          │
│  ✗ High competition (auction)                       │
│  ✗ Must bid high fees to win                        │
│                                                     │
│  Technical Risks:                                   │
│  - Geth node crashes/corrupts                       │
│  - Network connectivity issues                      │
│  - Smart contract bugs                              │
│  - Calculation errors                               │
└─────────────────────────────────────────────────────┘
```

## 8. Data Flow Diagram

```
┌──────────┐
│ bloXroute├───────┐
│ Mempool  │       │
└──────────┘       │
                   ▼
┌──────────┐   ┌───────────────┐   ┌──────────────┐
│ BSC Node ├──▶│ Stream Process├──▶│    Queue     │
└──────────┘   └───────────────┘   └──────┬───────┘
                                          │
                     ┌────────────────────┼────────────────────┐
                     ▼                    ▼                    ▼
              ┌────────────┐       ┌────────────┐      ┌────────────┐
              │ Worker #1  │       │ Worker #2  │ ...  │ Worker #6  │
              └──────┬─────┘       └──────┬─────┘      └──────┬─────┘
                     │                    │                    │
                     └────────────────────┼────────────────────┘
                                         ▼
                                  ┌──────────────┐
                                  │  Profitable? │
                                  └──────┬───────┘
                                         │ Yes
                                         ▼
                              ┌──────────────────────┐
                              │ Determine Path       │
                              │ (bloXroute/48/Gen)   │
                              └──────┬───────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    ▼                ▼                ▼
            ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
            │  bloXroute   │ │   48 Club    │ │   General    │
            │     API      │ │     API      │ │   Mempool    │
            └──────┬───────┘ └──────┬───────┘ └──────┬───────┘
                   │                │                │
                   └────────────────┼────────────────┘
                                    ▼
                            ┌───────────────┐
                            │  BSC Network  │
                            │  (Validators) │
                            └───────┬───────┘
                                    ▼
                            ┌───────────────┐
                            │ Smart Contract│
                            │  Execution    │
                            └───────┬───────┘
                                    ▼
                            ┌───────────────┐
                            │   DEX Pools   │
                            │   (Swap)      │
                            └───────────────┘
```

## 9. Sequence Diagram - Complete Sandwich Attack

```
Mempool Stream    Queue    Worker    EVM     Smart Contract    bloXroute      BSC
     │              │        │        │            │               │           │
     │─┐            │        │        │            │               │           │
     │ │ Detect Tx  │        │        │            │               │           │
     │◀┘            │        │        │            │               │           │
     │              │        │        │            │               │           │
     │─Trace Tx────▶│        │        │            │               │           │
     │              │        │        │            │               │           │
     │◀─Build Tx────│        │        │            │               │           │
     │              │        │        │            │               │           │
     │─Push Queue──▶│        │        │            │               │           │
     │              │        │        │            │               │           │
     │              │◀─Poll──│        │            │               │           │
     │              │        │        │            │               │           │
     │              │─Return▶│        │            │               │           │
     │              │        │        │            │               │           │
     │              │        │─Find──▶│            │               │           │
     │              │        │ Path   │            │               │           │
     │              │        │        │            │               │           │
     │              │        │◀Return─│            │               │           │
     │              │        │ Path   │            │               │           │
     │              │        │        │            │               │           │
     │              │        │─────Simulate───────▶│               │           │
     │              │        │        │            │               │           │
     │              │        │◀────Gas/Revenue────┤               │           │
     │              │        │        │            │               │           │
     │              │        │─Check Validator────────────────────▶│           │
     │              │        │        │            │               │           │
     │              │        │◀──────Validator Info───────────────┤           │
     │              │        │        │            │               │           │
     │              │        │─────Build Bundle────────────────────▶           │
     │              │        │        │            │               │           │
     │              │        │        │            │               │           │
     │              │        │        │            │◀──FrontRun────────────────│
     │              │        │        │            │               │           │
     │              │        │        │            │◀──Victim Tx───────────────│
     │              │        │        │            │               │           │
     │              │        │        │            │◀──BackRun─────────────────│
     │              │        │        │            │               │           │
     │              │        │        │            │─Execute Swaps─────────────▶
     │              │        │        │            │               │           │
     │              │        │        │            │◀─Results──────────────────┤
     │              │        │        │            │               │           │
     │              │        │◀───────────────Bundle Result────────┤           │
     │              │        │        │            │               │           │
```

## 10. Key Takeaways

### 10.1. Thành Công

✅ **Hoàn thiện hệ thống MEV attack**
- Hỗ trợ đa DEX (UniswapV2, V3, Curve)
- Tối ưu công thức toán học
- EVM simulation chính xác
- Multipath submission

✅ **Tối ưu hóa performance**
- bloXroute mempool streaming
- Multiprocessing architecture
- Quick path cho UniswapV2
- Co-located infrastructure

✅ **Production ready**
- Comprehensive testing
- Error handling & recovery
- Logging & monitoring
- IAC for deployment

### 10.2. Challenges & Lessons

⚠️ **Capital Requirements**
- Cần $100K-$1M để profitable
- Dự án dừng vì thiếu vốn

⚠️ **Competition**
- MEV-relay có auction mechanism
- Phải bid cao để win
- General path rủi ro cao

⚠️ **Infrastructure Costs**
- bloXroute: $5K/month
- Node hosting
- Development & maintenance

⚠️ **Market Dynamics**
- 48 Club deprecated
- bloXroute controversial
- Ecosystem changes fast

### 10.3. Educational Value

📚 **Blockchain Insights**
- MEV mechanism
- DEX AMM mathematics
- Transaction ordering
- Block building process

📚 **Technical Skills**
- Solidity optimization
- Python async/multiprocessing
- EVM internals
- Infrastructure as Code

📚 **Security Awareness**
- Slippage protection
- Private mempools
- MEV protection techniques

---

## Phụ Lục: File Mapping

| Component | Files |
|-----------|-------|
| **Main Entry** | `main_sandwich.py`, `main.py` |
| **Sandwich Logic** | `src/sandwich/search.py`, `src/sandwich/optimization.py`, `src/sandwich/simulation.py` |
| **Arbitrage Logic** | `src/arbitrage/search.py` |
| **Transaction Tracing** | `src/apis/trace_tx.py` |
| **EVM Simulation** | `src/evm.py`, `pyrevm/` |
| **Formulas** | `src/formula.py` |
| **Smart Contracts** | `contract/contracts/BSC.sol`, `contract/contracts/dexes/` |
| **Infrastructure** | `iac/aws/`, `docker/` |
| **Configuration** | `src/config.py` |
| **Types** | `src/types.py` |

---

*Tài liệu được tạo tự động bởi Claude Code*
*Ngày: 2025-11-26*
