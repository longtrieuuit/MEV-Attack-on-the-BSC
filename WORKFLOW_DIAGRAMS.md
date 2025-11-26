# MEV Attack Workflow - Mermaid Diagrams

Tài liệu này cung cấp các sơ đồ workflow dưới dạng Mermaid để dễ dàng visualize và nhúng vào các công cụ hỗ trợ.

## 1. Kiến Trúc Tổng Thể

```mermaid
graph TB
    subgraph Infrastructure["Infrastructure Layer"]
        Node[BSC Full Node<br/>Geth]
        Docker[Docker Containers]
        Cloud[AWS/GCP<br/>IaC Pulumi]
    end

    subgraph Streaming["Data Streaming"]
        BloX[bloXroute<br/>Mempool Stream]
        Local[Local Node<br/>RPC/WS]
        BlockStream[Block Stream]
    end

    subgraph Processing["MEV Processing Engine"]
        Stream[Stream Process]
        Queue[(Transaction<br/>Queue)]
        W1[Worker 1]
        W2[Worker 2]
        W3[Worker 3]
        W4[Worker 4]
        W5[Worker 5]
        W6[Worker 6]
    end

    subgraph Analysis["Analysis Layer"]
        Trace[Transaction<br/>Trace]
        Search[Opportunity<br/>Search]
        EVM[EVM<br/>Simulation<br/>pyREVM]
        Optimize[Optimization]
    end

    subgraph Submission["Transaction Submission"]
        PathSelect{Select<br/>Path}
        BloXRoute[bloXroute<br/>Bundle API]
        Club48[48 Club<br/>Puissant API]
        General[General<br/>Mempool]
    end

    subgraph Execution["On-Chain Execution"]
        Contract[Smart Contract<br/>BSC/ETH]
        DEX[DEX Pools<br/>UniswapV2/V3<br/>Curve]
    end

    BloX --> Stream
    Local --> Stream
    BlockStream --> Stream
    Node --> Local
    Cloud --> Node
    Cloud --> Docker

    Stream --> Queue
    Queue --> W1 & W2 & W3 & W4 & W5 & W6

    W1 & W2 & W3 & W4 & W5 & W6 --> Trace
    Trace --> Search
    Search --> EVM
    EVM --> Optimize

    Optimize --> PathSelect
    PathSelect -->|bloXroute Validator| BloXRoute
    PathSelect -->|48 Club Validator| Club48
    PathSelect -->|Other Validator| General

    BloXRoute --> Contract
    Club48 --> Contract
    General --> Contract

    Contract --> DEX

    style BloX fill:#ff6b6b
    style EVM fill:#4ecdc4
    style Contract fill:#95e1d3
    style Queue fill:#f38181
```

## 2. Sandwich Attack - Complete Flow

```mermaid
sequenceDiagram
    participant M as Mempool Stream
    participant Q as Queue
    participant W as Worker Process
    participant T as Trace Engine
    participant S as Search Engine
    participant E as EVM Simulator
    participant P as Path Selector
    participant B as bloXroute
    participant SC as Smart Contract
    participant DEX as DEX Pool

    M->>M: Monitor Mempool
    M->>T: Detect Transaction
    T->>T: debug_traceCall
    T->>T: Extract Swap Events
    T->>Q: Push Transaction

    Q->>W: Poll Transaction
    W->>W: Validate (still pending?)

    W->>S: Search Sandwich Path
    S->>S: Find Linking Pools
    S->>S: Check Liquidity

    alt Uniswap V2 Path
        S->>S: Quick Calculate<br/>(Formula)
    else Other DEX
        S->>E: Request Simulation
        E->>E: pyREVM Simulate
        E->>S: Return Results
    end

    S->>S: Check Profitability

    alt Not Profitable
        S->>W: Reject
    else Profitable
        S->>P: Continue
    end

    P->>P: Get Next Block Validator

    alt bloXroute Validator
        P->>B: Submit Bundle
        B->>B: Validate Bundle
        B->>B: Auction (compete)
        B->>SC: Execute if Won
    else 48 Club Validator
        P->>B: Submit to 48 Club
        B->>SC: Execute
    else Other Validator
        P->>SC: Send FrontRun
        Note over SC: Victim Tx
        P->>SC: Send BackRun
    end

    SC->>DEX: FrontRun Swap
    DEX->>SC: Return Tokens
    Note over DEX: Victim Swap<br/>(Price Impact)
    SC->>DEX: BackRun Swap
    DEX->>SC: Return Profit
    SC->>P: Profit to Owner
```

## 3. Mempool Processing Pipeline

```mermaid
flowchart LR
    subgraph Input["Input Sources"]
        BX[bloXroute<br/>~200ms faster]
        LN[Local Node<br/>Standard]
    end

    subgraph Filter["Filtering Stage"]
        F1{Has Gas<br/>Info?}
        F2{Has Data<br/>(contract)?}
    end

    subgraph Trace["Trace Stage"]
        T1[debug_traceCall]
        T2[Parse Call Tree]
        T3{Found Swap<br/>Function?}
    end

    subgraph Extract["Extract Stage"]
        E1[Detect Function<br/>Selectors]
        E2[Extract Transfers]
        E3[Build SwapEvents]
        E4{Valid<br/>Swaps?}
    end

    subgraph Output["Output"]
        Q[(Queue)]
        D[Discard]
    end

    BX --> F1
    LN --> F1

    F1 -->|No| D
    F1 -->|Yes| F2
    F2 -->|No| D
    F2 -->|Yes| T1

    T1 --> T2
    T2 --> T3
    T3 -->|No| D
    T3 -->|Yes| E1

    E1 --> E2
    E2 --> E3
    E3 --> E4

    E4 -->|No| D
    E4 -->|Yes| Q

    style BX fill:#ff6b6b
    style Q fill:#4ecdc4
    style D fill:#95e1d3
```

## 4. Sandwich Path Discovery

```mermaid
flowchart TD
    Start[Transaction with<br/>Swap Events] --> Split{Token Type?}

    Split -->|Native Token<br/>WBNB| Native[Direct Path<br/>WBNB → Token]
    Split -->|Non-Native<br/>Token| Link[Find Link Pool]

    Link --> Query[Query Pool List<br/>WBNB ↔ Token]
    Query --> Filter[Filter Pools<br/>Exclude Victim Pool]
    Filter --> Liquidity[Get Pool Liquidity<br/>Balance Query]
    Liquidity --> Select[Select Highest<br/>Liquidity Pool]

    Select --> Build2[Build 2-Hop Path<br/>WBNB → Token A → Token B]
    Native --> Build1[Build 1-Hop Path<br/>WBNB → Token]

    Build1 --> Validate{Is Uniswap<br/>V2?}
    Build2 --> Validate

    Validate -->|Yes| Quick[Quick Calculate<br/>Optimized Formula]
    Validate -->|No| Sim[EVM Simulation<br/>pyREVM]

    Quick --> Check{Profit ><br/>Threshold?}
    Sim --> Check

    Check -->|No| Reject[Reject]
    Check -->|Yes| Return[Return Attack<br/>Parameters]

    style Quick fill:#4ecdc4
    style Sim fill:#ff6b6b
    style Return fill:#95e1d3
    style Reject fill:#f38181
```

## 5. Path Selection Logic

```mermaid
flowchart TD
    Start[Profitable<br/>Opportunity] --> GetVal[Get Next Block<br/>Validator Address]

    GetVal --> Check{Check<br/>Validator}

    Check -->|bloXroute<br/>Validator| BloX[bloXroute Path]
    Check -->|48 Club<br/>Validator| Club[48 Club Path]
    Check -->|Other<br/>Validator| Gen[General Path]

    BloX --> CalcBX[Calculate Bundle Fee<br/>98% of profit]
    CalcBX --> CheckBX{Fee ><br/>1 Gwei?}
    CheckBX -->|No| Reject1[Reject]
    CheckBX -->|Yes| SubmitBX[Submit Bundle<br/>to bloXroute API]

    Club --> CalcClub[Calculate Gas Price<br/>for Fee Tx]
    CalcClub --> CheckMin{Gas ><br/>Minimum?}
    CheckMin -->|No| Reject2[Reject]
    CheckMin -->|Yes| SubmitClub[Submit Bundle<br/>to 48 Club API]

    Gen --> CheckArb{Arbitrage<br/>Exists?}
    CheckArb -->|Yes >0.01| Reject3[Reject<br/>High Competition]
    CheckArb -->|No| CalcProfit{Profit ><br/>0.001 BNB?}
    CalcProfit -->|No| Reject4[Reject]
    CalcProfit -->|Yes| Wait[Wait for<br/>Block Timing]
    Wait --> Send[Send Transactions<br/>Separately]
    Send --> Monitor[Monitor Results]
    Monitor --> Failed{FrontRun OK<br/>BackRun Fail?}
    Failed -->|Yes| Recover[Send Recovery<br/>Transaction]
    Failed -->|No| Done1[Complete]
    Recover --> Done2[Complete]

    SubmitBX --> Done3[Complete]
    SubmitClub --> Done4[Complete]

    style BloX fill:#ff6b6b
    style Club fill:#feca57
    style Gen fill:#48dbfb
    style Recover fill:#ff9ff3
```

## 6. Smart Contract Execution Flow

```mermaid
sequenceDiagram
    participant User as MEV Bot
    participant Contract as MEV Contract
    participant Pool1 as Link Pool<br/>(WBNB/Token)
    participant Pool2 as Victim Pool<br/>(Token/Target)

    Note over User,Pool2: FRONT RUN TRANSACTION

    User->>Contract: sandwichFrontRun()<br/>amountIn, exchanges,<br/>poolAddresses, tokenAddresses

    Contract->>Contract: Wrap BNB → WBNB<br/>(if needed)

    alt 2-Hop Sandwich
        Contract->>Pool1: Swap: WBNB → Token A
        Pool1->>Contract: Token A
        Contract->>Pool2: Swap: Token A → Token B
        Pool2->>Contract: Token B
    else 1-Hop Sandwich
        Contract->>Pool2: Swap: WBNB → Token
        Pool2->>Contract: Token
    end

    Contract->>Contract: Store balances

    Note over User,Pool2: VICTIM TRANSACTION EXECUTES
    Note over Pool2: Price increases!

    Note over User,Pool2: BACK RUN TRANSACTION

    User->>Contract: sandwichBackRun()<br/>amountIn, exchanges,<br/>poolAddresses (reversed),<br/>tokenAddresses (reversed)

    alt 2-Hop Sandwich (Reversed)
        Contract->>Pool2: Swap: Token B → Token A
        Pool2->>Contract: Token A
        Contract->>Pool1: Swap: Token A → WBNB
        Pool1->>Contract: WBNB
    else 1-Hop Sandwich
        Contract->>Pool2: Swap: Token → WBNB
        Pool2->>Contract: WBNB
    end

    Contract->>Contract: Unwrap WBNB → BNB
    Contract->>Contract: Calculate Profit

    alt bloXroute Path
        Contract->>Contract: Pay Fee to Validator
    end

    Contract->>User: Send Profit
```

## 7. Worker Process State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle

    Idle --> CheckQueue: Poll Queue
    CheckQueue --> Idle: Empty Queue
    CheckQueue --> ValidateTx: Transaction Available

    ValidateTx --> Idle: Not Pending
    ValidateTx --> ValidateTx: Block Too Old
    ValidateTx --> SearchPath: Valid

    SearchPath --> FindLink: Has Swap Events
    SearchPath --> Idle: No Swap Events

    FindLink --> BuildPath: Link Found
    FindLink --> Idle: No Link

    BuildPath --> QuickCalc: Uniswap V2
    BuildPath --> EVMSim: Other DEX

    QuickCalc --> CheckProfit: Calculated
    EVMSim --> CheckProfit: Simulated

    CheckProfit --> Idle: Not Profitable
    CheckProfit --> SelectPath: Profitable

    SelectPath --> SubmitBloX: bloXroute Validator
    SelectPath --> Submit48: 48 Club Validator
    SelectPath --> SubmitGen: Other Validator

    SubmitBloX --> WaitResult: Submitted
    Submit48 --> WaitResult: Submitted
    SubmitGen --> WaitResult: Submitted

    WaitResult --> CheckResult: Transaction Mined

    CheckResult --> Idle: Success
    CheckResult --> Recovery: Failed (General Only)

    Recovery --> Idle: Recovery Sent
```

## 8. Multi-Hop Arbitrage Path

```mermaid
flowchart LR
    subgraph Detection["Opportunity Detection"]
        D1[Price Change<br/>Transaction]
        D2[Analyze All<br/>DEX Pools]
        D3[Find Same<br/>Token Pairs]
    end

    subgraph PathFinding["Path Construction"]
        P1[2-Hop Path<br/>Pool A → Pool B]
        P2[3-Hop Path<br/>A → B → C]
        P3[4-Hop Path<br/>A → B → C → D]
        P4[n-Hop Path<br/>Generalized]
    end

    subgraph Calculation["Optimal Amount"]
        C1[Multi-Hop<br/>Formula]
        C2[Quadratic<br/>Solution]
        C3[x* = -b + √b²-4ac<br/>/ 2a]
    end

    subgraph Validation["Profitability Check"]
        V1{Revenue ><br/>Gas Cost?}
        V2{Enough<br/>Liquidity?}
    end

    subgraph Submission["Submit"]
        S1[General Path<br/>Only]
        S2[High Risk]
        S3[No Bundle<br/>Support]
    end

    D1 --> D2
    D2 --> D3
    D3 --> P1
    D3 --> P2
    D3 --> P3
    D3 --> P4

    P1 & P2 & P3 & P4 --> C1
    C1 --> C2
    C2 --> C3

    C3 --> V1
    V1 -->|Yes| V2
    V1 -->|No| Reject[Reject]
    V2 -->|Yes| S1
    V2 -->|No| Reject

    S1 --> S2
    S2 --> S3

    style C3 fill:#4ecdc4
    style S1 fill:#ff6b6b
    style Reject fill:#95e1d3
```

## 9. Transaction Trace Analysis

```mermaid
flowchart TD
    Start[Transaction] --> RPC[debug_traceCall<br/>RPC Request]

    RPC --> Parse[Parse Call Tree]

    Parse --> DetectSwap{Detect Swap<br/>Function?}

    DetectSwap -->|0x022c0d9f| UV2[UniswapV2<br/>swap]
    DetectSwap -->|0x128acb08| UV3[UniswapV3<br/>swap]
    DetectSwap -->|0x6d9a640a| Baker[BakerySwap<br/>swap]
    DetectSwap -->|Other| Skip1[Skip]

    UV2 & UV3 & Baker --> SetSwap[Set Swap Event<br/>dex, address]

    Parse --> DetectTransfer{Detect Token<br/>Transfer?}

    DetectTransfer -->|0xa9059cbb| Trans1[transfer<br/>recipient, value]
    DetectTransfer -->|0x23b872dd| Trans2[transferFrom<br/>sender, recipient, value]
    DetectTransfer -->|Other| Skip2[Skip]

    Trans1 & Trans2 --> Extract[Extract Transfer<br/>Data]

    Extract --> Match{Match Transfer<br/>to Swap?}

    Match -->|Yes| SetTransfer[Set Transfer Event<br/>token_in/out, amount]
    Match -->|No| Skip3[Skip]

    SetSwap & SetTransfer --> Combine[Combine Events]

    Combine --> Validate{Validate<br/>Swap Event?}

    Validate -->|Complete| Complete[Valid Swap Event<br/>dex, pool, tokens, amounts]
    Validate -->|Incomplete| Invalid[Invalid/Discard]

    Complete --> Filter{Filter<br/>Min Amount?}

    Filter -->|≥ 0.01 WBNB| Output[Output<br/>Transaction]
    Filter -->|< 0.01 WBNB| Invalid

    style Complete fill:#4ecdc4
    style Output fill:#95e1d3
    style Invalid fill:#f38181
```

## 10. Cost-Benefit Analysis Flow

```mermaid
flowchart TD
    Start[Sandwich<br/>Opportunity] --> CalcRev[Calculate<br/>Revenue]

    CalcRev --> Path{Submission<br/>Path?}

    Path -->|bloXroute| BloXCost[Cost Calculation]
    Path -->|48 Club| ClubCost[Cost Calculation]
    Path -->|General| GenCost[Cost Calculation]

    BloXCost --> BC1[Front Gas:<br/>victim_gas * front_gas_used]
    BC1 --> BC2[Back Gas:<br/>back_gas_price * back_gas_used]
    BC2 --> BC3[Bundle Fee:<br/>revenue - front - back × 0.98]
    BC3 --> BC4{Bundle Fee<br/>> 1 Gwei?}

    ClubCost --> CC1[Front Gas:<br/>victim_gas+1 × front_gas_used]
    CC1 --> CC2[Back Gas:<br/>1 Gwei × back_gas_used]
    CC2 --> CC3[Fee Tx:<br/>gas_price × 21000]
    CC3 --> CC4{Total Cost<br/>< Revenue<br/>× 0.98?}

    GenCost --> GC1[Front Gas:<br/>victim_gas+1 × front_gas_used]
    GC1 --> GC2[Back Gas:<br/>victim_gas × back_gas_used]
    GC2 --> GC3[Risk Cost:<br/>Potential failure]
    GC3 --> GC4{Net Profit<br/>> 0.001 BNB?}

    BC4 -->|No| Reject1[Reject<br/>Not Profitable]
    BC4 -->|Yes| Submit1[Submit]

    CC4 -->|No| Reject2[Reject<br/>Not Profitable]
    CC4 -->|Yes| Submit2[Submit]

    GC4 -->|No| Reject3[Reject<br/>Not Profitable]
    GC4 -->|Yes| Submit3[Submit]

    style Submit1 fill:#4ecdc4
    style Submit2 fill:#4ecdc4
    style Submit3 fill:#4ecdc4
    style Reject1 fill:#f38181
    style Reject2 fill:#f38181
    style Reject3 fill:#f38181
```

## Cách Sử Dụng Diagrams

### Trong GitHub
Các diagram Mermaid sẽ tự động render khi xem file `.md` trên GitHub.

### Trong VSCode
Cài đặt extension "Markdown Preview Mermaid Support" để preview.

### Trong Documentation Sites
Các công cụ như GitBook, MkDocs, Docusaurus đều hỗ trợ Mermaid.

### Export to Image
Sử dụng Mermaid Live Editor (https://mermaid.live) để export sang PNG/SVG.

---

*Tài liệu được tạo tự động bởi Claude Code*
*Ngày: 2025-11-26*
