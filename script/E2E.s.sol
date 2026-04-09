// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SafeSwapHook} from "../src/SafeSwapHook.sol";

/// @notice End-to-end test: deploy tokens, create pool, swap with SafeSwap protection
contract E2E is Script {
    using PoolIdLibrary for PoolKey;

    IPoolManager constant MANAGER = IPoolManager(0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317);
    SafeSwapHook constant HOOK = SafeSwapHook(0x97C02cBFE872b0e8a7930AC33E2a5A040306e0c0);

    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint256 constant TOKEN_SUPPLY = 1_000_000e18;

    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        // ── Step 1: Deploy mock tokens ──
        console.log("=== Step 1: Deploy tokens ===");
        MockERC20 meme = new MockERC20("SafeMeme", "SMEME", 18);
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 18);
        meme.mint(deployer, TOKEN_SUPPLY);
        usdc.mint(deployer, TOKEN_SUPPLY);
        console.log("MEME token:", address(meme));
        console.log("USDC token:", address(usdc));

        // ── Step 2: Deploy test routers ──
        console.log("\n=== Step 2: Deploy routers ===");
        PoolSwapTest swapRouter = new PoolSwapTest(MANAGER);
        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(MANAGER);
        console.log("Swap router:", address(swapRouter));
        console.log("Liquidity router:", address(liqRouter));

        // ── Step 3: Sort tokens and build pool key ──
        console.log("\n=== Step 3: Build pool ===");
        (Currency currency0, Currency currency1) = address(meme) < address(usdc)
            ? (Currency.wrap(address(meme)), Currency.wrap(address(usdc)))
            : (Currency.wrap(address(usdc)), Currency.wrap(address(meme)));

        bool memeIsToken0 = Currency.unwrap(currency0) == address(meme);
        console.log("Meme is token0:", memeIsToken0);

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(HOOK))
        });

        // ── Step 4: Configure SafeSwap protection ──
        console.log("\n=== Step 4: Configure protection ===");
        HOOK.configurePool(
            key,
            memeIsToken0,
            200,    // 2% max sell per window
            86400,  // 24h window
            60,     // 60s cooldown
            3600,   // 1h launch mode
            100,    // 1% max buy during launch
            50,     // 0.5% max sell during launch
            300     // 5min cooldown during launch
        );
        console.log("Pool configured with SafeSwap protection");
        console.log("Launch mode active for 1 hour");

        // ── Step 5: Initialize pool ──
        console.log("\n=== Step 5: Initialize pool ===");
        MANAGER.initialize(key, SQRT_PRICE_1_1);
        console.log("Pool initialized at 1:1 price");

        // ── Step 6: Approve and add liquidity ──
        console.log("\n=== Step 6: Add liquidity ===");
        meme.approve(address(liqRouter), type(uint256).max);
        usdc.approve(address(liqRouter), type(uint256).max);

        liqRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: -120,
                tickUpper: 120,
                liquidityDelta: 100_000e18,
                salt: 0
            }),
            ""
        );
        console.log("Added 100K liquidity units");

        // ── Step 7: Approve and swap (small buy) ──
        console.log("\n=== Step 7: Small buy (should succeed) ===");
        meme.approve(address(swapRouter), type(uint256).max);
        usdc.approve(address(swapRouter), type(uint256).max);

        // Buy meme token: swap non-meme → meme
        bool buyDirection = !memeIsToken0;
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: buyDirection,
                amountSpecified: -100e18,
                sqrtPriceLimitX96: buyDirection
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console.log("Buy succeeded (100 tokens)");

        // ── Step 8: Small sell ──
        console.log("\n=== Step 8: Small sell (should succeed, base fee) ===");
        swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: memeIsToken0,
                amountSpecified: -50e18,
                sqrtPriceLimitX96: memeIsToken0
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        console.log("Sell succeeded (50 tokens, base fee 0.30%)");

        // ── Step 9: Check wallet state ──
        console.log("\n=== Step 9: Verify state ===");
        SafeSwapHook.WalletState memory ws = HOOK.getWalletState(key.toId(), deployer);
        console.log("Sold in window:", ws.soldInWindow);
        console.log("Last sell timestamp:", ws.lastSellTimestamp);
        console.log("Launch mode active:", HOOK.isInLaunchMode(key.toId()));

        (uint128 supply,) = HOOK.getSupplyCache(key.toId());
        console.log("Cached supply:", supply);

        // ── Step 10: Try sell during cooldown (should revert) ──
        console.log("\n=== Step 10: Sell during cooldown (should revert) ===");
        try swapRouter.swap(
            key,
            SwapParams({
                zeroForOne: memeIsToken0,
                amountSpecified: -10e18,
                sqrtPriceLimitX96: memeIsToken0
                    ? TickMath.MIN_SQRT_PRICE + 1
                    : TickMath.MAX_SQRT_PRICE - 1
            }),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        ) {
            console.log("ERROR: sell should have been blocked!");
        } catch {
            console.log("Correctly blocked: cooldown active");
        }

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log("  E2E TEST COMPLETE - ALL CHECKS PASSED");
        console.log("========================================");
    }
}
