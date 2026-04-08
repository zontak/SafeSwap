// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SafeSwap Hook — Anti-Rug & Anti-Whale Protection for Uniswap V4
/// @notice Enforces sell-side rate limiting and progressive fees to protect LPs and traders
/// @dev Pool MUST be created with fee = LPFeeLibrary.DYNAMIC_FEE_FLAG (0x800000)
contract SafeSwapHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using SafeERC20 for IERC20;

    // ══════════════════════════════════════════════════════════════════════
    // Errors
    // ══════════════════════════════════════════════════════════════════════

    error PoolAlreadyInitialized();
    error InvalidMaxSellBps();
    error InvalidCooldown();
    error SellLimitExceeded(uint256 requested, uint256 remaining);
    error CooldownActive(uint256 nextAllowed);
    error BuyLimitExceeded();
    error NotOwner();

    // ══════════════════════════════════════════════════════════════════════
    // Events
    // ══════════════════════════════════════════════════════════════════════

    event PoolConfigured(PoolId indexed poolId, uint256 maxSellBps, uint256 windowDuration, uint256 cooldownSeconds);
    event WhaleSellDetected(PoolId indexed poolId, address indexed seller, uint256 sellBps, uint24 fee);
    event FeesWithdrawn(address indexed token, address indexed to, uint256 amount);

    // ══════════════════════════════════════════════════════════════════════
    // Types
    // ══════════════════════════════════════════════════════════════════════

    struct PoolConfig {
        uint64 maxSellBpsPerWindow;   // max sell as basis points of supply (e.g., 200 = 2%)
        uint64 windowDuration;         // rate limit window in seconds (default: 86400 = 24h)
        uint64 cooldownSeconds;        // min time between sells per wallet
        uint64 launchProtectionEnd;    // timestamp when launch mode ends (0 = no launch mode)
        uint64 launchMaxBuyBps;        // max buy during launch (basis points)
        uint64 launchMaxSellBps;       // max sell during launch (stricter)
        uint64 launchCooldownSeconds;  // stricter cooldown during launch
        bool memeIsToken0;             // true if the meme/protected token is currency0
        bool initialized;
    }

    struct WalletState {
        uint128 soldInWindow;          // tokens sold in current window
        uint64 windowStart;            // timestamp of current window start
        uint64 lastSellTimestamp;      // for cooldown enforcement
    }

    struct SupplyCache {
        uint128 cachedSupply;
        uint128 lastUpdateBlock;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Constants
    // ══════════════════════════════════════════════════════════════════════

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant SUPPLY_CACHE_BLOCKS = 100;

    // Fee tiers (in hundredths of basis points for LPFeeLibrary)
    uint24 public constant BASE_FEE = 3000;           // 0.30%
    uint24 public constant TIER2_FEE = 10_000;        // 1.00%
    uint24 public constant TIER3_FEE = 30_000;        // 3.00%
    uint24 public constant TIER4_FEE = 50_000;        // 5.00%

    // Sell size thresholds (basis points of supply)
    uint256 public constant TIER2_THRESHOLD = 10;      // 0.1%
    uint256 public constant TIER3_THRESHOLD = 50;      // 0.5%
    uint256 public constant TIER4_THRESHOLD = 100;     // 1.0%

    // ══════════════════════════════════════════════════════════════════════
    // State
    // ══════════════════════════════════════════════════════════════════════

    address public immutable owner;

    mapping(PoolId => PoolConfig) public poolConfigs;
    mapping(PoolId => mapping(address => WalletState)) internal _walletStates;
    mapping(PoolId => SupplyCache) internal _supplyCaches;

    // ══════════════════════════════════════════════════════════════════════
    // Constructor
    // ══════════════════════════════════════════════════════════════════════

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {
        owner = msg.sender;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Hook Permissions
    // ══════════════════════════════════════════════════════════════════════

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ══════════════════════════════════════════════════════════════════════
    // beforeInitialize — Set immutable pool config
    // ══════════════════════════════════════════════════════════════════════

    function _beforeInitialize(address, PoolKey calldata, uint160)
        internal
        pure
        override
        returns (bytes4)
    {
        return BaseHook.beforeInitialize.selector;
    }

    /// @notice Configure protection parameters for a pool. Must be called before pool initialization.
    /// @dev Parameters are immutable after pool initialization.
    function configurePool(
        PoolKey calldata key,
        bool memeIsToken0,
        uint64 maxSellBps,
        uint64 windowDuration,
        uint64 cooldownSeconds,
        uint64 launchDurationSeconds,
        uint64 launchMaxBuyBps,
        uint64 launchMaxSellBps,
        uint64 launchCooldownSeconds
    ) external {
        PoolId id = key.toId();
        if (poolConfigs[id].initialized) revert PoolAlreadyInitialized();
        if (maxSellBps == 0 || maxSellBps > uint64(BPS_DENOMINATOR)) revert InvalidMaxSellBps();
        if (cooldownSeconds == 0) revert InvalidCooldown();
        if (windowDuration == 0) windowDuration = 86400; // default 24h

        poolConfigs[id] = PoolConfig({
            maxSellBpsPerWindow: maxSellBps,
            windowDuration: windowDuration,
            cooldownSeconds: cooldownSeconds,
            launchProtectionEnd: launchDurationSeconds > 0
                ? uint64(block.timestamp) + launchDurationSeconds
                : 0,
            launchMaxBuyBps: launchMaxBuyBps,
            launchMaxSellBps: launchMaxSellBps,
            launchCooldownSeconds: launchCooldownSeconds,
            memeIsToken0: memeIsToken0,
            initialized: true
        });

        emit PoolConfigured(id, maxSellBps, windowDuration, cooldownSeconds);
    }

    // ══════════════════════════════════════════════════════════════════════
    // beforeSwap — Rate limiting + progressive fees
    // ══════════════════════════════════════════════════════════════════════

    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId id = key.toId();
        PoolConfig storage config = poolConfigs[id];

        // If pool is not configured with SafeSwap, pass through with base fee
        if (!config.initialized) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        // Buy handling
        if (!_isSell(config, params)) {
            _checkBuyLimit(id, key, config, params);
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, BASE_FEE | LPFeeLibrary.OVERRIDE_FEE_FLAG);
        }

        // Sell handling
        uint24 fee = _enforceSellLimits(id, key, config, params);
        return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, fee | LPFeeLibrary.OVERRIDE_FEE_FLAG);
    }

    /// @dev Check buy limits during launch mode
    function _checkBuyLimit(PoolId id, PoolKey calldata key, PoolConfig storage config, SwapParams calldata params) internal {
        if (_isInLaunchMode(config) && config.launchMaxBuyBps > 0) {
            uint256 supply = _getSupply(id, key, config);
            uint256 buyBps = (_absAmount(params) * BPS_DENOMINATOR) / supply;
            if (buyBps > config.launchMaxBuyBps) {
                revert BuyLimitExceeded();
            }
        }
    }

    /// @dev Enforce sell rate limits, cooldowns, and return progressive fee
    function _enforceSellLimits(PoolId id, PoolKey calldata key, PoolConfig storage config, SwapParams calldata params) internal returns (uint24) {
        address seller = tx.origin;
        uint256 supply = _getSupply(id, key, config);
        uint256 sellAmount = _absAmount(params);
        uint256 sellBps = supply > 0 ? (sellAmount * BPS_DENOMINATOR) / supply : 0;

        bool inLaunchMode = _isInLaunchMode(config);
        uint64 activeCooldown = inLaunchMode ? config.launchCooldownSeconds : config.cooldownSeconds;
        uint64 activeMaxSellBps = inLaunchMode && config.launchMaxSellBps > 0
            ? config.launchMaxSellBps
            : config.maxSellBpsPerWindow;

        // Check cooldown
        WalletState storage ws = _walletStates[id][seller];
        if (ws.lastSellTimestamp > 0 && block.timestamp < uint256(ws.lastSellTimestamp) + activeCooldown) {
            revert CooldownActive(uint256(ws.lastSellTimestamp) + activeCooldown);
        }

        // Check/reset window
        if (ws.windowStart == 0 || block.timestamp >= uint256(ws.windowStart) + config.windowDuration) {
            ws.soldInWindow = 0;
            ws.windowStart = uint64(block.timestamp);
        }

        // Check rate limit
        uint256 maxSellAmount = (supply * activeMaxSellBps) / BPS_DENOMINATOR;
        uint256 newTotal = uint256(ws.soldInWindow) + sellAmount;
        if (newTotal > maxSellAmount) {
            uint256 remaining = maxSellAmount > ws.soldInWindow ? maxSellAmount - ws.soldInWindow : 0;
            revert SellLimitExceeded(sellAmount, remaining);
        }

        uint24 fee = _calculateFee(sellBps);

        if (sellBps >= TIER2_THRESHOLD) {
            emit WhaleSellDetected(id, seller, sellBps, fee);
        }

        return fee;
    }

    // ══════════════════════════════════════════════════════════════════════
    // afterSwap — Record trade data
    // ══════════════════════════════════════════════════════════════════════

    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        PoolId id = key.toId();
        PoolConfig storage config = poolConfigs[id];

        if (config.initialized && _isSell(config, params)) {
            address seller = tx.origin;
            uint256 sellAmount = _absAmount(params);

            WalletState storage ws = _walletStates[id][seller];
            ws.soldInWindow += uint128(sellAmount);
            ws.lastSellTimestamp = uint64(block.timestamp);
        }

        return (this.afterSwap.selector, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Internal helpers
    // ══════════════════════════════════════════════════════════════════════

    /// @dev Check if pool is in launch protection mode
    function _isInLaunchMode(PoolConfig storage config) internal view returns (bool) {
        return config.launchProtectionEnd > 0 && block.timestamp < config.launchProtectionEnd;
    }

    /// @dev Determine if a swap is a sell of the protected (meme) token
    function _isSell(PoolConfig storage config, SwapParams calldata params) internal view returns (bool) {
        // Selling meme token = swapping meme token for the other
        // If memeIsToken0: selling = zeroForOne (swapping token0 out for token1)
        // If !memeIsToken0: selling = !zeroForOne (swapping token1 out for token0)
        return config.memeIsToken0 ? params.zeroForOne : !params.zeroForOne;
    }

    /// @dev Get absolute sell/buy amount from swap params
    function _absAmount(SwapParams calldata params) internal pure returns (uint256) {
        int256 amount = params.amountSpecified;
        return amount < 0 ? uint256(-amount) : uint256(amount);
    }

    /// @dev Calculate progressive fee based on sell size in basis points
    function _calculateFee(uint256 sellBps) internal pure returns (uint24) {
        if (sellBps >= TIER4_THRESHOLD) return TIER4_FEE;   // >= 1.0% supply: 5.00%
        if (sellBps >= TIER3_THRESHOLD) return TIER3_FEE;   // >= 0.5% supply: 3.00%
        if (sellBps >= TIER2_THRESHOLD) return TIER2_FEE;   // >= 0.1% supply: 1.00%
        return BASE_FEE;                                      // < 0.1% supply: 0.30%
    }

    /// @dev Get total supply with caching (refreshes every SUPPLY_CACHE_BLOCKS blocks)
    function _getSupply(PoolId id, PoolKey calldata key, PoolConfig storage config) internal returns (uint256) {
        SupplyCache storage cache = _supplyCaches[id];

        if (cache.cachedSupply == 0 || block.number >= uint256(cache.lastUpdateBlock) + SUPPLY_CACHE_BLOCKS) {
            Currency memeToken = config.memeIsToken0 ? key.currency0 : key.currency1;
            address tokenAddr = Currency.unwrap(memeToken);

            // Bounded external call — malicious token cannot grief
            try IERC20(tokenAddr).totalSupply() returns (uint256 supply) {
                if (supply > 0) {
                    cache.cachedSupply = uint128(supply > type(uint128).max ? type(uint128).max : supply);
                    cache.lastUpdateBlock = uint128(block.number);
                }
            } catch {
                // Keep stale cache on failure
            }
        }

        return uint256(cache.cachedSupply);
    }

    // ══════════════════════════════════════════════════════════════════════
    // View functions
    // ══════════════════════════════════════════════════════════════════════

    function getWalletState(PoolId id, address wallet) external view returns (WalletState memory) {
        return _walletStates[id][wallet];
    }

    function getSupplyCache(PoolId id) external view returns (uint128 supply, uint128 lastBlock) {
        SupplyCache storage cache = _supplyCaches[id];
        return (cache.cachedSupply, cache.lastUpdateBlock);
    }

    function isInLaunchMode(PoolId id) external view returns (bool) {
        return _isInLaunchMode(poolConfigs[id]);
    }

    /// @dev Calculate fee for a given sell size (view, for UI integration)
    function previewFee(uint256 sellBps) external pure returns (uint24) {
        return _calculateFee(sellBps);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Owner functions
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Withdraw accumulated fees from the hook contract
    function withdrawFees(address token, address to) external {
        if (msg.sender != owner) revert NotOwner();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(to, balance);
            emit FeesWithdrawn(token, to, balance);
        }
    }
}
