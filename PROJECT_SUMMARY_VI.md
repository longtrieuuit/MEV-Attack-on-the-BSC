# Tóm Tắt Dự Án MEV Attack - Tiếng Việt

## 📌 Tổng Quan

Dự án này là một hệ thống MEV (Maximal Extractable Value) Attack hoàn chỉnh trên Binance Smart Chain, cho phép khai thác lợi nhuận từ các giao dịch DEX swap.

### Thời gian hoạt động
**Tháng 1/2024 - Tháng 5/2024** (đã ngừng hoạt động do thiếu vốn)

### Lý do dừng
Cần vốn **$100K - $1M** để có thể sinh lời ổn định từ sandwich attacks.

## 🎯 Mục Đích

1. **Sandwich Attack**: Đặt transaction trước và sau transaction của nạn nhân để kiếm lời từ chênh lệch giá
2. **Arbitrage Attack**: Khai thác chênh lệch giá giữa các DEX khác nhau

## 🏗️ Kiến Trúc Hệ Thống

### 1. Infrastructure (Hạ tầng)
```
BSC Full Node (Geth) → Python MEV Client → Smart Contracts → DEX Pools
```

**Yêu cầu:**
- Node đặt tại New York hoặc Đức (gần validators)
- Cùng instance với MEV client (giảm latency)
- Snapshot thường xuyên (Geth dễ corrupt)
- Chi phí: bloXroute $5K/tháng + hosting

### 2. Cấu Trúc Code

```
├── contract/              # Smart contracts (Solidity)
│   ├── BSC.sol           # Contract chính cho BSC
│   └── dexes/            # Hỗ trợ swap cho các DEX
├── src/                  # Python code
│   ├── sandwich/         # Logic sandwich attack
│   ├── arbitrage/        # Logic arbitrage attack
│   ├── apis/             # API & utilities
│   ├── evm.py           # EVM simulator
│   └── formula.py       # Công thức toán học
├── iac/                 # Infrastructure as Code
├── pyrevm/              # Python wrapper cho REVM
├── main_sandwich.py     # Entry point cho sandwich
└── main.py             # Entry point cho arbitrage
```

## 🔄 Workflow Chính - Sandwich Attack

### Bước 1: Streaming Mempool
```
bloXroute Mempool Stream → Filter transactions → Trace transactions → Queue
```

**Lợi thế**: bloXroute nhanh hơn ~200ms so với local node

### Bước 2: Phân Tích (6 worker processes song song)
```
Queue → Worker → Tìm Sandwich Path → EVM Simulation → Tính Profit
```

**Tối ưu hóa**:
- Uniswap V2: Dùng công thức toán học (nhanh)
- Các DEX khác: Dùng pyREVM simulation (chính xác)

### Bước 3: Chọn Path Submit

#### Path 1: bloXroute (nếu validator hỗ trợ)
```
✅ Đảm bảo thứ tự transaction
✅ Không mất phí nếu fail
❌ Phải trả bundle fee cao
❌ Cạnh tranh cao (auction)

Chi phí:
- Front run gas: victim_gas_price × front_gas
- Back run gas: calculated_gas_price × back_gas
- Bundle fee: 98% lợi nhuận còn lại
```

#### Path 2: 48 Club (nếu validator hỗ trợ)
```
✅ Đảm bảo thứ tự transaction
✅ Không có base cost
❌ Phải trả fee qua transaction riêng
⚠️  Đã deprecated (tháng 5/2024)

Chi phí:
- Fee transaction: gas_price × 21000
- Front + Back gas: tương tự bloXroute
```

#### Path 3: General (validators khác)
```
❌ KHÔNG đảm bảo thứ tự
❌ Có thể bị front-run bởi người khác
❌ Mất gas dù fail
✅ Không có phí MEV-relay

Chiến thuật:
- Tăng gas price lên victim_gas + 1
- Dùng "Difficult" functions (validate block number)
- Monitor kết quả, có recovery nếu cần
```

### Bước 4: Smart Contract Execution

```
[FrontRun Transaction]
WBNB → Swap Pool A → Token → Swap Pool B → Target Token
(Tăng giá target token)

[Victim Transaction]
User swap ở giá cao hơn dự kiến

[BackRun Transaction]
Target Token → Swap Pool B → Token → Swap Pool A → WBNB
(Bán với giá cao, kiếm lời)

Profit = WBNB_out - WBNB_in - Gas_costs - MEV_fees
```

## 📊 Ví Dụ Thực Tế

### Sandwich với bloXroute (thành công)
```
Transaction: 0x906bf0f8...
- FrontRun:  -0.21913 WBNB (mua IRT token)
- Victim:     Swap 0.362844 WBNB → IRT
- BackRun:   +0.22019 WBNB (bán IRT)

Lợi nhuận: +0.00012 BNB (~$0.07)
Chi phí:   -0.0009 BNB (gas + fee)
Net:       Lỗ nhẹ (do competition cao)
```

### Sandwich với General (thành công)
```
Transaction: 0x19228eff...
- FrontRun:  -0.69236 WBNB
- Victims:   3 transactions liên tiếp
- BackRun:   +0.71646 WBNB

Lợi nhuận: +0.02410 BNB
Chi phí:   -0.00721 BNB (gas)
Net:       +0.01689 BNB (~$10.13) ✅
```

## 🧮 Công Thức Toán Học Tối Ưu

### Uniswap V2 Amount Out (Tối ưu hóa)

**Formula chuẩn** (có sai số):
```
y = (997 × R_out × x) / (1000 × R_in + 997 × x)
```

**Formula tối ưu** (không sai số, lấy max):
```
y = R_out - ⌊(n × R_in × R_out) / (n × (R_in + x) - s × x)⌋

n = 1000, s = 3 (Uniswap V2)
```

**Lợi ích**: Nhận được nhiều token hơn ~0.05% so với formula chuẩn

### Multi-hop Arbitrage (Tìm x tối ưu)

**2-hop** (A → B → A):
```
Giải phương trình bậc 2:
ax² + bx + c = 0

x* = (-b + √(b² - 4ac)) / (2a)

Trong đó:
k = (n-s)nR₂ᵢₙ + (n-s)²R₁ₒᵤₜ
a = k²
b = 2n²R₁ᵢₙR₂ᵢₙk
c = (n²R₁ᵢₙR₂ᵢₙ)² - (n-s)²n²R₁ᵢₙR₂ᵢₙR₁ₒᵤₜR₂ₒᵤₜ
```

**n-hop**: Generalized formula cho 3, 4, ... hops

## 🎨 Các DEX Được Hỗ Trợ

### Uniswap V2 Family
- PancakeSwap V2
- SushiSwap V2
- BiSwap V2
- ApeSwap
- THENA
- BabySwap
- Nomiswap
- WaultSwap
- GibXSwap
- MDEX

### Uniswap V3 Family
- PancakeSwap V3
- SushiSwap V3
- THENA FUSION

### Curve (Ethereum)
- Hỗ trợ hầu hết major pools
- Sai số ±1 cho mỗi pool

## ⚡ Performance

### Latency Budget (3s block time BSC)
```
1. Mempool reception:     ~200ms (bloXroute advantage)
2. Transaction trace:     ~50-100ms (debug_traceCall)
3. EVM simulation:        ~10-50ms (skip for UniV2)
4. Bundle submission:     ~100-200ms (network)
────────────────────────────────────────────────
   Total:                 ~360-550ms ✅
```

### Tối Ưu Hóa
1. **Multiprocessing**: 6 workers song song
2. **Quick path**: Formula cho Uniswap V2 (không cần EVM)
3. **Co-location**: MEV client + node cùng instance
4. **Filtered pools**: Chỉ theo dõi top liquidity

## 💰 Phân Tích Chi Phí

### Chi Phí Cố Định
```
- bloXroute subscription:  $5,000/tháng
- Node hosting (AWS):      ~$500-1000/tháng
- Development:             Thời gian + công sức
─────────────────────────────────────────────
  Total:                   ~$5,500+/tháng
```

### Chi Phí Biến Động (mỗi sandwich)
```
bloXroute Path:
- Gas (front+back): ~0.001-0.01 BNB
- Bundle fee:       95-98% lợi nhuận thô

48 Club Path:
- Gas (front+back): ~0.001-0.01 BNB
- Fee transaction:  ~0.002-0.005 BNB

General Path:
- Gas (front+back): ~0.001-0.01 BNB
- Risk:             Có thể mất toàn bộ nếu fail
```

### Break-even Analysis
```
Để hòa vốn $5,500/tháng với profit ~$5/sandwich:
→ Cần ~1,100 successful sandwiches/tháng
→ ~37 sandwiches/ngày
→ ~1.5 sandwiches/giờ (24/7)

Thực tế: Rất khó do competition cao!
```

## ⚠️ Rủi Ro & Thách Thức

### Rủi Ro Kỹ Thuật
- ❌ Geth node crash/corrupt
- ❌ Network connectivity issues
- ❌ Smart contract bugs
- ❌ Calculation errors
- ❌ Competition (bị outbid)

### Rủi Ro Tài Chính
- ❌ Cần capital lớn ($100K-$1M)
- ❌ Competition cao → lợi nhuận thấp
- ❌ Infrastructure costs cao
- ❌ Market dynamics thay đổi nhanh

### Rủi Ro Pháp Lý & Đạo Đức
- ⚠️ MEV gây tổn hại cho users
- ⚠️ Có thể vi phạm ToS của một số platforms
- ⚠️ Regulatory uncertainty

## 📈 Kết Quả Thực Tế

### Thành Công
✅ Hoàn thiện hệ thống MEV hoàn chỉnh
✅ Tối ưu công thức toán học
✅ Production-ready code
✅ Comprehensive testing
✅ Multi-DEX support

### Challenges
❌ Dừng hoạt động do thiếu vốn
❌ Competition quá cao
❌ Infrastructure costs lớn
❌ bloXroute gây tranh cãi (destroy BSC ecosystem)

### Lessons Learned
📚 MEV mechanics
📚 DEX AMM mathematics
📚 Blockchain internals
📚 Infrastructure optimization
📚 Capital requirements

## 🔍 So Sánh EigenPhi

Dự án chỉ ra rằng **EigenPhi thường báo cáo sai profit**:

### Case 1: Sandwich nhận dạng thành Arbitrage
```
EigenPhi báo cáo:   $821,381 profit
Thực tế:            $419 profit

Lý do: Không tính đúng front-run cost
```

### Case 2: Không tính Fee Transaction (48 Club)
```
EigenPhi báo cáo:   $22.45 profit
Thực tế:            $2.15 profit

Lý do: Bỏ qua fee transaction ở position 0
```

## 🎓 Giá Trị Giáo Dục

Dự án này có giá trị lớn cho:

### Developers
- Hiểu sâu về MEV mechanisms
- Tối ưu hóa công thức AMM
- Solidity optimization techniques
- Python async/multiprocessing
- EVM internals

### Researchers
- MEV attack patterns
- Transaction ordering
- Block building process
- Economic incentives

### Users
- Nhận thức về MEV risks
- Cách protect khỏi sandwich attacks
- Slippage protection
- Private mempool usage

## 🛡️ Cách Bảo Vệ Khỏi MEV Attacks

### Cho Users
1. **Set Slippage Thấp**: Giảm cơ hội bị sandwich
2. **Dùng Private Mempools**: Flashbots, Eden Network
3. **Trade Lớn Qua OTC**: Tránh public DEX
4. **Dùng MEV-Protect RPCs**: Flashbots Protect
5. **Limit Orders**: Thay vì market orders

### Cho Protocols
1. **Implement MEV-Share**: Chia lợi nhuận với users
2. **Batch Auctions**: Thay vì continuous trading
3. **Private Order Flow**: Không public mempool
4. **Time-weighted Pricing**: Giảm price impact

## 📚 Tài Liệu Liên Quan

### Documents trong Repo
- `README.md` - Tài liệu chính (English)
- `README_ko.md` - Tài liệu tiếng Hàn
- `WORKFLOW_ANALYSIS.md` - Phân tích workflow chi tiết
- `WORKFLOW_DIAGRAMS.md` - Các diagram Mermaid
- `PROJECT_SUMMARY_VI.md` - Tóm tắt này

### External Resources
- [Flashbots](https://www.flashbots.net) - MEV-Boost for Ethereum
- [bloXroute Docs](https://docs.bloxroute.com) - BSC MEV solution
- [EigenPhi](https://eigenphi.io) - MEV analysis
- [Uniswap V2 Core](https://github.com/Uniswap/v2-core) - AMM reference

### Research Papers
- [Flash Boys 2.0](https://arxiv.org/abs/1904.05234)
- [MEV and Me](https://research.paradigm.xyz/MEV)
- [Ethereum is a Dark Forest](https://www.paradigm.xyz/2020/08/ethereum-is-a-dark-forest)

## 🚀 Cách Chạy (Educational Purpose)

### Prerequisites
```bash
# Node requirements
- BSC Full Node (Geth)
- Python 3.9+
- Node.js 16+ (for Hardhat)

# API keys
- bloXroute API key (optional)
- CoinMarketCap API key
```

### Setup
```bash
# Clone repo
git clone https://github.com/DonggeunYu/MEV-Attack-on-the-BSC

# Install Python dependencies
pip install -r requirements/requirements.txt

# Install Solidity dependencies
cd contract
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test
```

### Configuration
```python
# Edit src/config.py
http_endpoint = "http://localhost:8545"
ws_endpoint = "ws://localhost:8546"
account_address = "0xYourAddress"
contract_address = "0xDeployedContractAddress"
```

### Run
```bash
# Sandwich attack
python main_sandwich.py

# Arbitrage attack
python main.py
```

## ⚖️ Disclaimer

**⚠️ CHỈ VÌ MỤC ĐÍCH GIÁO DỤC**

Dự án này được chia sẻ để:
- Giáo dục về MEV mechanisms
- Nghiên cứu blockchain security
- Nâng cao nhận thức về risks

**KHÔNG sử dụng cho:**
- ❌ Tấn công users thực tế
- ❌ Gây thiệt hại cho hệ sinh thái
- ❌ Vi phạm pháp luật

Tác giả không chịu trách nhiệm về việc sử dụng sai mục đích.

## 📧 Contact

**Author**: Donggeun Yu
**Email**: donggeunyu@icloud.com
**GitHub Issues**: [Report issues here](https://github.com/DonggeunYu/MEV-Attack-on-the-BSC/issues)

---

## 🌟 Kết Luận

Dự án MEV Attack on BSC là một **case study tuyệt vời** về:

✅ **Technical Excellence**
- Clean architecture
- Optimized algorithms
- Production-ready code
- Comprehensive testing

✅ **Educational Value**
- Deep MEV insights
- Mathematical rigor
- Real-world data
- Honest assessment

❌ **Economic Reality**
- High capital requirements
- High infrastructure costs
- High competition
- Low actual profits

→ **Lesson**: MEV không phải "free money" - cần capital lớn, technical expertise cao, và sẵn sàng chấp nhận rủi ro!

---

*Tài liệu được tạo tự động bởi Claude Code*
*Ngày: 2025-11-26*
*Phân tích bởi: Claude Sonnet 4.5*
