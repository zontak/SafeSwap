// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";
import {SafeSwapHook} from "../src/SafeSwapHook.sol";

contract SafeSwapHookTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    SafeSwapHook hook;
    PoolKey poolKey;
    PoolId poolId;

    // Tokens with controlled supply (1M tokens, 18 decimals)
    uint256 constant TOKEN_SUPPLY = 1_000_000e18;

    // Default pool config
    uint64 constant MAX_SELL_BPS = 200;        // 2% per window
    uint64 constant WINDOW_DURATION = 86400;    // 24h
    uint64 constant COOLDOWN = 60;              // 60s

    // Sellers
    address seller1 = makeAddr("seller1");
    address seller2 = makeAddr("seller2");

    // Track which token is the meme token
    bool memeIsToken0;

    function setUp() public {
        // Deploy manager and all test routers
        deployFreshManagerAndRouters();

        // Deploy tokens with controlled supply
        MockERC20 tokenA = new MockERC20("MEME", "MEME", 18);
        MockERC20 tokenB = new MockERC20("USDC", "USDC", 18);
        tokenA.mint(address(this), TOKEN_SUPPLY);
        tokenB.mint(address(this), TOKEN_SUPPLY);

        // Sort tokens (required by Uniswap — currency0 < currency1)
        (currency0, currency1) = SortTokens.sort(tokenA, tokenB);

        // Determine which position the meme token ended up in
        memeIsToken0 = (Currency.unwrap(currency0) == address(tokenA));

        // Approve tokens to all routers
        _approveToRouters(tokenA);
        _approveToRouters(tokenB);

        // Give sellers tokens and pre-approve swap router
        tokenA.mint(seller1, TOKEN_SUPPLY);
        tokenB.mint(seller1, TOKEN_SUPPLY);
        tokenA.mint(seller2, TOKEN_SUPPLY);
        tokenB.mint(seller2, TOKEN_SUPPLY);

        _approveSellerToRouter(seller1, tokenA, tokenB);
        _approveSellerToRouter(seller2, tokenA, tokenB);

        // Deploy hook at address with correct permission flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address hookAddr = address(flags);

        deployCodeTo(
            "SafeSwapHook.sol:SafeSwapHook",
            abi.encode(address(manager), address(this)),
            hookAddr
        );
        hook = SafeSwapHook(hookAddr);

        // Build pool key
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(hookAddr)
        });
        poolId = poolKey.toId();

        // Configure pool protection BEFORE initialization
        hook.configurePool(
            poolKey,
            memeIsToken0,
            MAX_SELL_BPS,
            WINDOW_DURATION,
            COOLDOWN,
            0, 0, 0, 0 // no launch mode
        );

        // Initialize pool and add liquidity
        manager.initialize(poolKey, SQRT_PRICE_1_1);

        // Add substantial liquidity for meaningful swaps
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            LIQUIDITY_PARAMS,
            ZERO_BYTES
        );
        // Seed more liquidity for larger swaps
        seedMoreLiquidity(poolKey, 100_000e18, 100_000e18);
    }

    function _approveToRouters(MockERC20 token) internal {
        token.approve(address(swapRouter), type(uint256).max);
        token.approve(address(swapRouterNoChecks), type(uint256).max);
        token.approve(address(modifyLiquidityRouter), type(uint256).max);
        token.approve(address(modifyLiquidityNoChecks), type(uint256).max);
        token.approve(address(donateRouter), type(uint256).max);
        token.approve(address(takeRouter), type(uint256).max);
        token.approve(address(claimsRouter), type(uint256).max);
        token.approve(address(nestedActionRouter.executor()), type(uint256).max);
        token.approve(address(actionsRouter), type(uint256).max);
    }

    function _approveSellerToRouter(address seller, MockERC20 tokenA, MockERC20 tokenB) internal {
        vm.startPrank(seller, seller);
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();
    }

    // ══════════════════════════════════════════════════════════════════════
    // Helper: execute a sell (swap meme → other)
    // ══════════════════════════════════════════════════════════════════════

    function _sell(address seller, int256 amount) internal returns (BalanceDelta) {
        vm.startPrank(seller, seller);
        BalanceDelta delta = swap(poolKey, memeIsToken0, amount, ZERO_BYTES);
        vm.stopPrank();
        return delta;
    }

    function _buy(address buyer, int256 amount) internal returns (BalanceDelta) {
        vm.startPrank(buyer, buyer);
        BalanceDelta delta = swap(poolKey, !memeIsToken0, amount, ZERO_BYTES);
        vm.stopPrank();
        return delta;
    }

    // ══════════════════════════════════════════════════════════════════════
    // configurePool tests
    // ══════════════════════════════════════════════════════════════════════

    function test_configurePool_emitsEvent() public {
        // Create a new pool key for a fresh pool
        MockERC20 tokenC = new MockERC20("NEW", "NEW", 18);
        MockERC20 tokenD = new MockERC20("OTHER", "OTHER", 18);
        tokenC.mint(address(this), TOKEN_SUPPLY);
        tokenD.mint(address(this), TOKEN_SUPPLY);

        (Currency c0, Currency c1) = SortTokens.sort(tokenC, tokenD);

        PoolKey memory newKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });
        PoolId newId = newKey.toId();

        vm.expectEmit(true, false, false, true);
        emit SafeSwapHook.PoolConfigured(newId, 300, 43200, 120);

        hook.configurePool(newKey, true, 300, 43200, 120, 0, 0, 0, 0);
    }

    function test_configurePool_revert_alreadyInitialized() public {
        vm.expectRevert(SafeSwapHook.PoolAlreadyInitialized.selector);
        hook.configurePool(poolKey, memeIsToken0, MAX_SELL_BPS, WINDOW_DURATION, COOLDOWN, 0, 0, 0, 0);
    }

    function test_configurePool_revert_invalidMaxSellBps_zero() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.tickSpacing = 10; // different key → different PoolId

        vm.expectRevert(SafeSwapHook.InvalidMaxSellBps.selector);
        hook.configurePool(fakeKey, true, 0, WINDOW_DURATION, COOLDOWN, 0, 0, 0, 0);
    }

    function test_configurePool_revert_invalidMaxSellBps_tooHigh() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.tickSpacing = 10;

        vm.expectRevert(SafeSwapHook.InvalidMaxSellBps.selector);
        hook.configurePool(fakeKey, true, 10001, WINDOW_DURATION, COOLDOWN, 0, 0, 0, 0);
    }

    function test_configurePool_revert_invalidCooldown() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.tickSpacing = 10;

        vm.expectRevert(SafeSwapHook.InvalidCooldown.selector);
        hook.configurePool(fakeKey, true, MAX_SELL_BPS, WINDOW_DURATION, 0, 0, 0, 0, 0);
    }

    function test_configurePool_defaultWindowDuration() public {
        PoolKey memory fakeKey = poolKey;
        fakeKey.tickSpacing = 10;

        hook.configurePool(fakeKey, true, MAX_SELL_BPS, 0, COOLDOWN, 0, 0, 0, 0);

        (,uint64 windowDuration,,,,,,,) = hook.poolConfigs(fakeKey.toId());
        assertEq(windowDuration, 86400, "default window should be 24h");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Unconfigured pool — passthrough with base fee
    // ══════════════════════════════════════════════════════════════════════

    function test_unconfiguredPool_passthrough() public {
        // Deploy new tokens for a separate unconfigured pool
        MockERC20 tokenC = new MockERC20("AAA", "AAA", 18);
        MockERC20 tokenD = new MockERC20("BBB", "BBB", 18);
        tokenC.mint(address(this), TOKEN_SUPPLY);
        tokenD.mint(address(this), TOKEN_SUPPLY);

        (Currency c0, Currency c1) = SortTokens.sort(tokenC, tokenD);

        _approveToRouters(tokenC);
        _approveToRouters(tokenD);

        PoolKey memory unconfiguredKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        // Initialize without configuring — should pass through
        manager.initialize(unconfiguredKey, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(unconfiguredKey, LIQUIDITY_PARAMS, ZERO_BYTES);

        // Swap should work (base fee, no restrictions)
        swap(unconfiguredKey, true, -100, ZERO_BYTES);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Buy tests
    // ══════════════════════════════════════════════════════════════════════

    function test_buy_normalMode_baseFee() public {
        // Buy should always succeed in normal mode with base fee
        _buy(seller1, -100e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Sell tests — Progressive fees
    // ══════════════════════════════════════════════════════════════════════

    function test_sell_smallAmount_baseFee() public {
        // Sell < 0.1% of supply → base fee (0.30%)
        // 0.05% of supply = 500e18
        _sell(seller1, -500e18);
    }

    function test_sell_withinRateLimit() public {
        // Sell within 2% window limit should succeed
        // 1% of 1M supply = 10_000e18
        _sell(seller1, -1_000e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Sell tests — Rate limiting
    // ══════════════════════════════════════════════════════════════════════

    function test_sell_exceedsRateLimit_reverts() public {
        // Total supply = TOKEN_SUPPLY * 3 (this + seller1 + seller2) = 3M per token
        // But supply cache caps at uint128 and uses the meme token's totalSupply
        // Max sell per window = totalSupply * MAX_SELL_BPS / 10_000
        // We need an amount that exceeds this. Use a very large sell.
        // With 3M supply and 200 bps (2%), max = 60_000e18
        // Try selling 100_000e18 which exceeds the limit
        vm.startPrank(seller1, seller1);
        vm.expectRevert();
        swap(poolKey, memeIsToken0, -100_000e18, ZERO_BYTES);
        vm.stopPrank();
    }

    function test_sell_multipleSells_accumulate() public {
        // First sell should succeed
        _sell(seller1, -100e18);

        // Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN + 1);

        // Second sell should succeed (still within window)
        _sell(seller1, -100e18);
    }

    function test_sell_windowReset() public {
        // First sell
        _sell(seller1, -100e18);

        // Warp past window duration
        vm.warp(block.timestamp + WINDOW_DURATION + 1);

        // Should be able to sell again (window reset)
        _sell(seller1, -100e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Cooldown tests
    // ══════════════════════════════════════════════════════════════════════

    function test_sell_cooldown_active_reverts() public {
        // First sell
        _sell(seller1, -100e18);

        // Try to sell again immediately (within cooldown)
        vm.startPrank(seller1, seller1);
        vm.expectRevert();
        swap(poolKey, memeIsToken0, -100e18, ZERO_BYTES);
        vm.stopPrank();
    }

    function test_sell_cooldown_expired_succeeds() public {
        // First sell
        _sell(seller1, -100e18);

        // Warp past cooldown
        vm.warp(block.timestamp + COOLDOWN + 1);

        // Should succeed
        _sell(seller1, -100e18);
    }

    function test_sell_differentSellers_noCooldownConflict() public {
        // Seller1 sells
        _sell(seller1, -100e18);

        // Seller2 can sell immediately (different wallet, no cooldown)
        _sell(seller2, -100e18);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Launch mode tests
    // ══════════════════════════════════════════════════════════════════════

    function test_launchMode_buyLimit() public {
        (PoolKey memory launchKey,, bool launchMeme0) = _setupLaunchPool();

        // Small buy should succeed. Buy = opposite of sell direction.
        vm.startPrank(seller1, seller1);
        MockERC20(Currency.unwrap(launchKey.currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(launchKey.currency1)).approve(address(swapRouter), type(uint256).max);
        swap(launchKey, !launchMeme0, -10e18, ZERO_BYTES);
        vm.stopPrank();
    }

    function test_launchMode_buyExceedsLimit_reverts() public {
        (PoolKey memory launchKey,, bool launchMeme0) = _setupLaunchPool();

        // Buy exceeding 0.5% of supply should revert
        vm.startPrank(seller1, seller1);
        MockERC20(Currency.unwrap(launchKey.currency0)).approve(address(swapRouter), type(uint256).max);
        MockERC20(Currency.unwrap(launchKey.currency1)).approve(address(swapRouter), type(uint256).max);
        vm.expectRevert();
        swap(launchKey, !launchMeme0, -50_000e18, ZERO_BYTES);
        vm.stopPrank();
    }

    function test_launchMode_expires() public {
        (PoolKey memory launchKey,, ) = _setupLaunchPool();
        PoolId launchId = launchKey.toId();

        // Should be in launch mode
        assertTrue(hook.isInLaunchMode(launchId));

        // Warp past launch duration (1 hour)
        vm.warp(block.timestamp + 3601);

        // Should no longer be in launch mode
        assertFalse(hook.isInLaunchMode(launchId));
    }

    function _setupLaunchPool() internal returns (PoolKey memory launchKey, PoolId launchId, bool launchMemeIsToken0) {
        MockERC20 tokenC = new MockERC20("LAUNCH", "LAUNCH", 18);
        MockERC20 tokenD = new MockERC20("STABLE", "STABLE", 18);
        tokenC.mint(address(this), TOKEN_SUPPLY);
        tokenD.mint(address(this), TOKEN_SUPPLY);
        tokenC.mint(seller1, TOKEN_SUPPLY);
        tokenD.mint(seller1, TOKEN_SUPPLY);

        (Currency c0, Currency c1) = SortTokens.sort(tokenC, tokenD);

        _approveToRouters(tokenC);
        _approveToRouters(tokenD);

        launchMemeIsToken0 = (Currency.unwrap(c0) == address(tokenC));

        launchKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });
        launchId = launchKey.toId();

        // Configure with launch mode: 1 hour, 50bps max buy, 50bps max sell, 300s cooldown
        hook.configurePool(
            launchKey,
            launchMemeIsToken0,
            MAX_SELL_BPS,       // normal max sell: 2%
            WINDOW_DURATION,    // 24h window
            COOLDOWN,           // 60s normal cooldown
            3600,               // launch duration: 1 hour
            50,                 // launch max buy: 0.5%
            50,                 // launch max sell: 0.5%
            300                 // launch cooldown: 5 minutes
        );

        manager.initialize(launchKey, SQRT_PRICE_1_1);
        modifyLiquidityRouter.modifyLiquidity(launchKey, LIQUIDITY_PARAMS, ZERO_BYTES);
        seedMoreLiquidity(launchKey, 100_000e18, 100_000e18);

        return (launchKey, launchId, launchMemeIsToken0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // View function tests
    // ══════════════════════════════════════════════════════════════════════

    function test_getWalletState_initial() public view {
        SafeSwapHook.WalletState memory ws = hook.getWalletState(poolId, seller1);
        assertEq(ws.soldInWindow, 0);
        assertEq(ws.windowStart, 0);
        assertEq(ws.lastSellTimestamp, 0);
    }

    function test_getWalletState_afterSell() public {
        _sell(seller1, -100e18);

        SafeSwapHook.WalletState memory ws = hook.getWalletState(poolId, seller1);
        assertGt(ws.soldInWindow, 0);
        assertEq(ws.lastSellTimestamp, uint64(block.timestamp));
    }

    function test_isInLaunchMode_false() public view {
        assertFalse(hook.isInLaunchMode(poolId));
    }

    function test_previewFee_baseFee() public view {
        assertEq(hook.previewFee(5), 3000);    // < 10 bps → base fee
    }

    function test_previewFee_tier2() public view {
        assertEq(hook.previewFee(10), 10_000);  // >= 10 bps → 1%
        assertEq(hook.previewFee(49), 10_000);  // still tier 2
    }

    function test_previewFee_tier3() public view {
        assertEq(hook.previewFee(50), 30_000);  // >= 50 bps → 3%
        assertEq(hook.previewFee(99), 30_000);
    }

    function test_previewFee_tier4() public view {
        assertEq(hook.previewFee(100), 50_000); // >= 100 bps → 5%
        assertEq(hook.previewFee(500), 50_000);
    }

    function test_getSupplyCache_populated() public {
        // Trigger a sell to populate the supply cache
        _sell(seller1, -100e18);

        (uint128 supply, uint128 lastBlock) = hook.getSupplyCache(poolId);
        assertGt(supply, 0);
        assertEq(lastBlock, uint128(block.number));
    }

    // ══════════════════════════════════════════════════════════════════════
    // Owner functions
    // ══════════════════════════════════════════════════════════════════════

    function test_rescueTokens_notOwner_reverts() public {
        vm.prank(seller1);
        vm.expectRevert(SafeSwapHook.NotOwner.selector);
        hook.rescueTokens(Currency.unwrap(currency0), seller1);
    }

    function test_rescueTokens_owner_noBalance() public {
        address hookOwner = hook.owner();
        vm.prank(hookOwner);
        hook.rescueTokens(Currency.unwrap(currency0), hookOwner);
    }

    function test_rescueTokens_owner_withBalance() public {
        address hookOwner = hook.owner();
        address tokenAddr = Currency.unwrap(currency0);

        // Send some tokens directly to the hook contract
        MockERC20(tokenAddr).mint(address(hook), 1000e18);
        uint256 hookBalance = MockERC20(tokenAddr).balanceOf(address(hook));
        assertEq(hookBalance, 1000e18);

        // Owner rescues
        vm.prank(hookOwner);
        hook.rescueTokens(tokenAddr, hookOwner);

        // Hook should have 0, owner should have received the tokens
        assertEq(MockERC20(tokenAddr).balanceOf(address(hook)), 0);
        assertGt(MockERC20(tokenAddr).balanceOf(hookOwner), 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Events
    // ══════════════════════════════════════════════════════════════════════

    function test_whaleSellDetected_event() public {
        // We need a sell >= 0.1% of supply to trigger WhaleSellDetected
        // Total supply = 3M tokens, 0.1% = 3000 tokens. Sell 5000 tokens.
        // Use recordLogs to check for the event after the swap
        vm.recordLogs();
        _sell(seller1, -5_000e18);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        // Search for WhaleSellDetected event
        bytes32 whaleSellSig = keccak256("WhaleSellDetected(bytes32,address,uint256,uint24)");
        bool found = false;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == whaleSellSig) {
                found = true;
                break;
            }
        }
        assertTrue(found, "WhaleSellDetected event not emitted");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Hook permissions
    // ══════════════════════════════════════════════════════════════════════

    function test_hookPermissions() public view {
        Hooks.Permissions memory perms = hook.getHookPermissions();
        assertTrue(perms.beforeInitialize);
        assertTrue(perms.beforeSwap);
        assertTrue(perms.afterSwap);
        assertFalse(perms.afterInitialize);
        assertFalse(perms.beforeAddLiquidity);
        assertFalse(perms.afterAddLiquidity);
        assertFalse(perms.beforeRemoveLiquidity);
        assertFalse(perms.afterRemoveLiquidity);
        assertFalse(perms.beforeDonate);
        assertFalse(perms.afterDonate);
        assertFalse(perms.beforeSwapReturnDelta);
        assertTrue(perms.afterSwapReturnDelta);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Fuzz tests
    // ══════════════════════════════════════════════════════════════════════

    function testFuzz_previewFee_monotonic(uint256 bps1, uint256 bps2) public view {
        bps1 = bound(bps1, 0, 10_000);
        bps2 = bound(bps2, bps1, 10_000);
        // Larger sell bps should have >= fee
        assertGe(hook.previewFee(bps2), hook.previewFee(bps1));
    }

    function testFuzz_previewFee_correctTier(uint256 bps) public view {
        bps = bound(bps, 0, 10_000);
        uint24 fee = hook.previewFee(bps);

        if (bps >= 100) {
            assertEq(fee, 50_000);
        } else if (bps >= 50) {
            assertEq(fee, 30_000);
        } else if (bps >= 10) {
            assertEq(fee, 10_000);
        } else {
            assertEq(fee, 3_000);
        }
    }

    function testFuzz_configurePool_validParams(uint64 maxSell, uint64 window, uint64 cooldown) public {
        maxSell = uint64(bound(maxSell, 1, 10_000));
        cooldown = uint64(bound(cooldown, 1, type(uint64).max));

        // Create unique pool key
        MockERC20 t0 = new MockERC20("F", "F", 18);
        MockERC20 t1 = new MockERC20("G", "G", 18);
        t0.mint(address(this), 1e18);
        t1.mint(address(this), 1e18);
        (Currency c0, Currency c1) = SortTokens.sort(t0, t1);

        PoolKey memory fuzzKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        hook.configurePool(fuzzKey, true, maxSell, window, cooldown, 0, 0, 0, 0);

        (uint64 stored,,,,,,,, bool init) = hook.poolConfigs(fuzzKey.toId());
        assertEq(stored, maxSell);
        assertTrue(init);
    }
}
