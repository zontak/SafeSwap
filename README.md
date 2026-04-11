# SafeSwap Hook

Anti-rug and anti-whale protection hook for Uniswap V4. Enforces sell-side rate limiting and progressive fees to protect LPs and traders from large sudden dumps.

**Deployed on Arbitrum One (2026-04-09):**

| Contract | Address |
|----------|---------|
| SafeSwapHook | [`0x66af5c4d7ba72da6c635b26589c0af86353ae0c0`](https://arbiscan.io/address/0x66af5c4d7ba72da6c635b26589c0af86353ae0c0) |
| SafeSwapFactory | [`0x7704377059cf4eb88050445b78f1d6b1eb1fa78a`](https://arbiscan.io/address/0x7704377059cf4eb88050445b78f1d6b1eb1fa78a) |
| PoolManager (Uniswap V4) | [`0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32`](https://arbiscan.io/address/0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32) |

## How It Works

SafeSwap attaches to any Uniswap V4 pool as a `beforeInitialize` + `beforeSwap` + `afterSwap` hook (with `afterSwapReturnDelta` for protocol fee extraction). It monitors sells of a designated "protected" token (e.g., a meme coin) and enforces:

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
5. **Protocol fees** -- Owner-configurable fee (up to 0.5%) taken from the unspecified token delta via `afterSwapReturnDelta`

## Architecture

Two contracts:

- **SafeSwapHook** -- The Uniswap V4 hook enforcing protection rules
- **SafeSwapFactory** -- Permissionless pool creation (configure + initialize in one transaction)

```
Token Creator                       Trader
     |                                 |
     v                                 v
Factory.createPool()             swap(sell)
     |                                 |
     +-> configurePool()       beforeSwap: check limits + set fee
     +-> poolManager.initialize()      |
                                       v
                               afterSwap: record sell + extract protocol fee
```

- **State scoping**: All state is keyed by `PoolId` -- no cross-pool contamination
- **Immutable config**: Pool parameters are set once before initialization, cannot be changed
- **Seller ID**: Uses `tx.origin` to identify sellers (works with all existing routers)
- **Supply detection**: Cached `ERC20.totalSupply()` with try-catch, refreshes every 100 blocks
- **Protocol fees**: Extracted via `afterSwapReturnDelta`, accumulated per token, withdrawable by owner

## Quick Start

```bash
# Install dependencies
forge install

# Build
forge build

# Test (67 tests, 100% line coverage)
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
  --etherscan-api-key $ARBISCAN_API_KEY \
  -vvvv
```

This deploys both `SafeSwapHook` (via CREATE2 with mined salt) and `SafeSwapFactory`, then authorizes the factory on the hook.

3. Create a protected pool via the factory (recommended):

```solidity
factory.createPool(
    memeToken,   // address of the protected token
    pairedToken, // e.g., WETH or USDC
    60,          // tickSpacing
    sqrtPriceX96,
    200,         // maxSellBps: 2% max sell per window
    86400,       // windowDuration: 24 hours
    60,          // cooldownSeconds: 1 minute between sells
    3600,        // launchDuration: 1 hour of strict limits (0 to disable)
    50,          // launchMaxBuyBps: 0.5% max buy during launch
    50,          // launchMaxSellBps: 0.5% max sell during launch
    300          // launchCooldown: 5 minutes during launch
);
```

Or configure directly via the hook (owner/factory only):

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

4. If using `configurePool` directly, initialize the pool with `fee = LPFeeLibrary.DYNAMIC_FEE_FLAG` (`0x800000`)

## Test Coverage

```
| File                    | Lines  | Statements | Branches | Functions |
|-------------------------|--------|------------|----------|-----------|
| src/SafeSwapHook.sol    | 100.0% | 99.25%     | 90.91%   | 100.0%    |
| src/SafeSwapFactory.sol | 100.0% | 100.0%     | 100.0%   | 100.0%    |
```

67 tests across two test files:
- `SafeSwapHook.t.sol` -- 36 tests (config, rate limiting, cooldowns, fees, launch mode, fuzz)
- `SafeSwapFactory.t.sol` -- 31 tests (pool creation, fee management, token sorting, edge cases)

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

## Landing Page

The `site/` directory contains a static landing page for SafeSwap. Open `site/index.html` locally or deploy to any static host.

## Stack

- Solidity 0.8.26, Cancun EVM
- [Foundry](https://book.getfoundry.sh/)
- [OpenZeppelin Uniswap Hooks](https://github.com/OpenZeppelin/uniswap-hooks) (BaseHook)
- Uniswap V4 Core

## License

[MIT](LICENSE)
