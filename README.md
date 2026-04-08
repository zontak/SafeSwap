# SafeSwap Hook

Anti-rug and anti-whale protection hook for Uniswap V4. Enforces sell-side rate limiting and progressive fees to protect LPs and traders from large sudden dumps.

## How It Works

SafeSwap attaches to any Uniswap V4 pool as a `beforeSwap` + `afterSwap` hook. It monitors sells of a designated "protected" token (e.g., a meme coin) and enforces:

1. **Rate limiting** -- Maximum sell amount per wallet per time window (e.g., 2% of supply per 24h)
2. **Cooldown** -- Minimum time between sells per wallet (e.g., 60 seconds)
3. **Progressive fees** -- Larger sells pay higher LP fees:

| Sell Size (% of supply) | Fee    |
|-------------------------|--------|
| < 0.1%                  | 0.30%  |
| >= 0.1%                 | 1.00%  |
| >= 0.5%                 | 3.00%  |
| >= 1.0%                 | 5.00%  |

4. **Launch protection** -- Optional stricter limits during the first hours after pool creation

## Architecture

```
Pool Creator                    Trader
    |                              |
    v                              v
configurePool()              swap(sell)
    |                              |
    v                              v
[PoolConfig stored]     beforeSwap: check limits + set fee
                               |
                               v
                        afterSwap: record sell amount
```

- **State scoping**: All state is keyed by `PoolId` -- no cross-pool contamination
- **Immutable config**: Pool parameters are set once before initialization, cannot be changed
- **Seller ID**: Uses `tx.origin` to identify sellers (works with all existing routers)
- **Supply detection**: Cached `ERC20.totalSupply()` with try-catch, refreshes every 100 blocks

## Quick Start

```bash
# Install dependencies
forge install

# Build
forge build

# Test (35 tests, 100% line coverage)
forge test

# Coverage report
forge coverage --ir-minimum
```

## Deploy

1. Update `POOL_MANAGER` address in `script/Deploy.s.sol` for your target chain
2. Run the deploy script:

```bash
forge script script/Deploy.s.sol:DeploySafeSwap \
  --rpc-url $RPC_URL \
  --broadcast --verify \
  -vvvv
```

3. Configure a pool:

```solidity
hook.configurePool(
    poolKey,
    true,       // memeIsToken0: true if protected token is currency0
    200,        // maxSellBps: 2% max sell per window
    86400,      // windowDuration: 24 hours
    60,         // cooldownSeconds: 1 minute between sells
    3600,       // launchDuration: 1 hour of strict limits (0 to disable)
    50,         // launchMaxBuyBps: 0.5% max buy during launch
    50,         // launchMaxSellBps: 0.5% max sell during launch
    300         // launchCooldown: 5 minutes during launch
);
```

4. Initialize the pool with `fee = LPFeeLibrary.DYNAMIC_FEE_FLAG` (`0x800000`)

## Test Coverage

```
| File                 | Lines  | Statements | Branches | Functions |
|----------------------|--------|------------|----------|-----------|
| src/SafeSwapHook.sol | 100.0% | 99.25%     | 90.91%   | 100.0%    |
```

35 tests including:
- Unit tests for all configuration paths
- Sell rate limiting and cooldown enforcement
- Progressive fee tier verification
- Launch mode activation and expiry
- Fuzz tests (10,000 runs each)

## Security

See [SECURITY.md](SECURITY.md) for known limitations and vulnerability reporting.

**Key design decisions:**
- `tx.origin` for seller identification (see SECURITY.md for trade-offs)
- `onlyPoolManager` on all external hook functions (via BaseHook)
- All state scoped by PoolId (prevents cross-pool attacks)
- Immutable pool config (prevents post-launch parameter tampering)
- SafeERC20 for token transfers
- Checks-effects-interactions pattern in all callbacks

**This contract has not been formally audited. Use at your own risk.**

## Stack

- Solidity 0.8.26, Cancun EVM
- [Foundry](https://book.getfoundry.sh/)
- [OpenZeppelin Uniswap Hooks](https://github.com/OpenZeppelin/uniswap-hooks) (BaseHook)
- Uniswap V4 Core

## License

[MIT](LICENSE)
