// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";
import {SafeSwapHook} from "../src/SafeSwapHook.sol";
import {SafeSwapFactory} from "../src/SafeSwapFactory.sol";

contract SafeSwapFactoryTest is Test, Deployers {
    using PoolIdLibrary for PoolKey;

    SafeSwapHook hook;
    SafeSwapFactory factory;

    MockERC20 memeToken;
    MockERC20 pairedToken;

    uint256 constant TOKEN_SUPPLY = 1_000_000e18;
    uint256 constant CREATION_FEE = 0.01 ether;

    address owner = address(this);
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address attacker = makeAddr("attacker");

    function setUp() public {
        deployFreshManagerAndRouters();

        // Deploy hook at address with correct permission flags
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );
        address hookAddr = address(flags);

        deployCodeTo(
            "SafeSwapHook.sol:SafeSwapHook",
            abi.encode(address(manager), owner),
            hookAddr
        );
        hook = SafeSwapHook(hookAddr);

        // Deploy factory
        factory = new SafeSwapFactory(manager, hook, CREATION_FEE);

        // Authorize factory on the hook
        hook.setFactory(address(factory));

        // Deploy test tokens
        memeToken = new MockERC20("MEME", "MEME", 18);
        pairedToken = new MockERC20("USDC", "USDC", 18);
        memeToken.mint(address(this), TOKEN_SUPPLY);
        pairedToken.mint(address(this), TOKEN_SUPPLY);

        // Fund users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Constructor
    // ══════════════════════════════════════════════════════════════════════

    function test_constructor() public view {
        assertEq(factory.owner(), owner);
        assertEq(address(factory.poolManager()), address(manager));
        assertEq(address(factory.hook()), address(hook));
        assertEq(factory.creationFee(), CREATION_FEE);
    }

    // ══════════════════════════════════════════════════════════════════════
    // createPool — success cases
    // ══════════════════════════════════════════════════════════════════════

    function test_createPool_success() public {
        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200,    // 2% max sell
            86400,  // 24h window
            60,     // 60s cooldown
            0, 0, 0, 0  // no launch mode
        );

        // Verify pool was configured
        (Currency c0, Currency c1) = address(memeToken) < address(pairedToken)
            ? (Currency.wrap(address(memeToken)), Currency.wrap(address(pairedToken)))
            : (Currency.wrap(address(pairedToken)), Currency.wrap(address(memeToken)));

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        (,,,,,,,,bool initialized) = hook.poolConfigs(key.toId());
        assertTrue(initialized, "pool should be configured");
    }

    function test_createPool_emitsEvent() public {
        (Currency c0, Currency c1) = address(memeToken) < address(pairedToken)
            ? (Currency.wrap(address(memeToken)), Currency.wrap(address(pairedToken)))
            : (Currency.wrap(address(pairedToken)), Currency.wrap(address(memeToken)));

        vm.expectEmit(true, true, true, true);
        emit SafeSwapFactory.PoolCreated(
            user1,
            Currency.unwrap(c0),
            Currency.unwrap(c1),
            int24(60),
            CREATION_FEE
        );

        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_withLaunchMode() public {
        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200,    // 2% max sell
            86400,  // 24h window
            60,     // 60s cooldown
            3600,   // 1h launch
            50,     // 0.5% max buy during launch
            50,     // 0.5% max sell during launch
            300     // 5min launch cooldown
        );

        // Build expected key
        (Currency c0, Currency c1) = address(memeToken) < address(pairedToken)
            ? (Currency.wrap(address(memeToken)), Currency.wrap(address(pairedToken)))
            : (Currency.wrap(address(pairedToken)), Currency.wrap(address(memeToken)));

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        assertTrue(hook.isInLaunchMode(key.toId()), "should be in launch mode");
    }

    function test_createPool_refundsExcessETH() public {
        uint256 excess = 0.05 ether;
        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        factory.createPool{value: CREATION_FEE + excess}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // User should get excess back
        assertEq(user1.balance, balanceBefore - CREATION_FEE, "should refund excess");
    }

    function test_createPool_zeroFee() public {
        // Set fee to zero
        factory.setCreationFee(0);

        vm.prank(user1);
        factory.createPool{value: 0}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // Should succeed with no payment
    }

    function test_createPool_tokenSorting() public {
        // Regardless of argument order, tokens should be sorted correctly
        // Try with memeToken > pairedToken order
        address higher = address(memeToken) > address(pairedToken) ? address(memeToken) : address(pairedToken);
        address lower = address(memeToken) < address(pairedToken) ? address(memeToken) : address(pairedToken);

        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            higher,  // pass higher address as meme
            lower,   // pass lower address as paired
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // Pool should be created with correct sorting
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(lower),
            currency1: Currency.wrap(higher),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        (,,,,,,,,bool initialized) = hook.poolConfigs(key.toId());
        assertTrue(initialized, "pool should be configured regardless of argument order");
    }

    // ══════════════════════════════════════════════════════════════════════
    // createPool — revert cases
    // ══════════════════════════════════════════════════════════════════════

    function test_createPool_revert_insufficientFee() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(SafeSwapFactory.InsufficientFee.selector, CREATION_FEE - 1, CREATION_FEE)
        );
        factory.createPool{value: CREATION_FEE - 1}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_zeroMemeToken() public {
        vm.prank(user1);
        vm.expectRevert(SafeSwapFactory.InvalidTokens.selector);
        factory.createPool{value: CREATION_FEE}(
            address(0),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_zeroPairedToken() public {
        vm.prank(user1);
        vm.expectRevert(SafeSwapFactory.InvalidTokens.selector);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(0),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_sameToken() public {
        vm.prank(user1);
        vm.expectRevert(SafeSwapFactory.InvalidTokens.selector);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(memeToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_duplicatePool() public {
        // First creation succeeds
        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // Second creation with same tokens + tickSpacing should revert (already initialized)
        vm.prank(user2);
        vm.expectRevert();
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_invalidMaxSellBps() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            0,      // invalid: zero
            86400, 60,
            0, 0, 0, 0
        );
    }

    function test_createPool_revert_invalidCooldown() public {
        vm.prank(user1);
        vm.expectRevert();
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400,
            0,      // invalid: zero cooldown
            0, 0, 0, 0
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // setCreationFee
    // ══════════════════════════════════════════════════════════════════════

    function test_setCreationFee_owner() public {
        uint256 newFee = 0.5 ether;

        vm.expectEmit(false, false, false, true);
        emit SafeSwapFactory.CreationFeeUpdated(CREATION_FEE, newFee);

        factory.setCreationFee(newFee);
        assertEq(factory.creationFee(), newFee);
    }

    function test_setCreationFee_revert_notOwner() public {
        vm.prank(attacker);
        vm.expectRevert(SafeSwapFactory.NotOwner.selector);
        factory.setCreationFee(0);
    }

    function test_setCreationFee_enforcedOnNextCreate() public {
        // Raise fee
        uint256 newFee = 1 ether;
        factory.setCreationFee(newFee);

        // Old fee should be rejected
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(SafeSwapFactory.InsufficientFee.selector, CREATION_FEE, newFee)
        );
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // New fee should work
        vm.prank(user1);
        factory.createPool{value: newFee}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    // ══════════════════════════════════════════════════════════════════════
    // withdrawFees (Factory)
    // ══════════════════════════════════════════════════════════════════════

    function test_withdrawFees_owner() public {
        // Create a pool to accumulate fees
        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        assertEq(address(factory).balance, CREATION_FEE);

        address recipient = makeAddr("treasury");
        uint256 recipientBefore = recipient.balance;

        vm.expectEmit(true, false, false, true);
        emit SafeSwapFactory.FeesWithdrawn(recipient, CREATION_FEE);

        factory.withdrawFees(recipient);

        assertEq(address(factory).balance, 0);
        assertEq(recipient.balance, recipientBefore + CREATION_FEE);
    }

    function test_withdrawFees_revert_notOwner() public {
        vm.prank(attacker);
        vm.expectRevert(SafeSwapFactory.NotOwner.selector);
        factory.withdrawFees(attacker);
    }

    function test_withdrawFees_noBalance() public {
        address recipient = makeAddr("treasury");
        // Should not revert, just do nothing
        factory.withdrawFees(recipient);
        assertEq(recipient.balance, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Hook access control — configurePool authorization
    // ══════════════════════════════════════════════════════════════════════

    function test_hook_configurePool_revert_unauthorized() public {
        MockERC20 t0 = new MockERC20("X", "X", 18);
        MockERC20 t1 = new MockERC20("Y", "Y", 18);
        (Currency c0, Currency c1) = SortTokens.sort(t0, t1);

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        // Random user cannot configure pool
        vm.prank(attacker);
        vm.expectRevert(SafeSwapHook.NotAuthorized.selector);
        hook.configurePool(key, true, 200, 86400, 60, 0, 0, 0, 0);
    }

    function test_hook_configurePool_owner_succeeds() public {
        MockERC20 t0 = new MockERC20("X", "X", 18);
        MockERC20 t1 = new MockERC20("Y", "Y", 18);
        (Currency c0, Currency c1) = SortTokens.sort(t0, t1);

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        // Owner can still configure directly
        hook.configurePool(key, true, 200, 86400, 60, 0, 0, 0, 0);

        (,,,,,,,,bool initialized) = hook.poolConfigs(key.toId());
        assertTrue(initialized);
    }

    function test_hook_configurePool_factory_succeeds() public {
        MockERC20 t0 = new MockERC20("X", "X", 18);
        MockERC20 t1 = new MockERC20("Y", "Y", 18);
        (Currency c0, Currency c1) = SortTokens.sort(t0, t1);

        PoolKey memory key = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        // Factory can configure
        vm.prank(address(factory));
        hook.configurePool(key, true, 200, 86400, 60, 0, 0, 0, 0);

        (,,,,,,,,bool initialized) = hook.poolConfigs(key.toId());
        assertTrue(initialized);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Hook access control — setFactory
    // ══════════════════════════════════════════════════════════════════════

    function test_hook_setFactory_owner() public {
        address newFactory = makeAddr("newFactory");
        hook.setFactory(newFactory);
        assertEq(hook.factory(), newFactory);
    }

    function test_hook_setFactory_revert_notOwner() public {
        vm.prank(attacker);
        vm.expectRevert(SafeSwapHook.NotOwner.selector);
        hook.setFactory(attacker);
    }

    function test_hook_setFactory_revokesOldFactory() public {
        // Current factory can configure
        MockERC20 t0 = new MockERC20("A", "A", 18);
        MockERC20 t1 = new MockERC20("B", "B", 18);
        (Currency c0, Currency c1) = SortTokens.sort(t0, t1);

        PoolKey memory key1 = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        vm.prank(address(factory));
        hook.configurePool(key1, true, 200, 86400, 60, 0, 0, 0, 0);

        // Change factory to a new address
        address newFactory = makeAddr("newFactory");
        hook.setFactory(newFactory);

        // Old factory can no longer configure
        MockERC20 t2 = new MockERC20("C", "C", 18);
        MockERC20 t3 = new MockERC20("D", "D", 18);
        (Currency c2, Currency c3) = SortTokens.sort(t2, t3);

        PoolKey memory key2 = PoolKey({
            currency0: c2,
            currency1: c3,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(address(hook))
        });

        vm.prank(address(factory));
        vm.expectRevert(SafeSwapHook.NotAuthorized.selector);
        hook.configurePool(key2, true, 200, 86400, 60, 0, 0, 0, 0);

        // New factory can configure
        vm.prank(newFactory);
        hook.configurePool(key2, true, 200, 86400, 60, 0, 0, 0, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Fee accumulation integration test
    // ══════════════════════════════════════════════════════════════════════

    function test_integration_multiplePoolsAccumulateFees() public {
        // Create multiple pools, verify fees accumulate
        MockERC20 token1 = new MockERC20("T1", "T1", 18);
        MockERC20 token2 = new MockERC20("T2", "T2", 18);
        MockERC20 token3 = new MockERC20("T3", "T3", 18);

        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(token1), address(pairedToken),
            int24(60), SQRT_PRICE_1_1,
            200, 86400, 60, 0, 0, 0, 0
        );

        vm.prank(user2);
        factory.createPool{value: CREATION_FEE}(
            address(token2), address(pairedToken),
            int24(60), SQRT_PRICE_1_1,
            200, 86400, 60, 0, 0, 0, 0
        );

        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(token3), address(pairedToken),
            int24(60), SQRT_PRICE_1_1,
            200, 86400, 60, 0, 0, 0, 0
        );

        // Factory should hold 3x creation fee
        assertEq(address(factory).balance, CREATION_FEE * 3);

        // Withdraw all
        address treasury = makeAddr("treasury");
        factory.withdrawFees(treasury);
        assertEq(treasury.balance, CREATION_FEE * 3);
        assertEq(address(factory).balance, 0);
    }

    // ══════════════════════════════════════════════════════════════════════
    // Fuzz tests
    // ══════════════════════════════════════════════════════════════════════

    function testFuzz_createPool_anyFeeAmount(uint256 fee) public {
        fee = bound(fee, 0, 10 ether);
        factory.setCreationFee(fee);

        vm.deal(user1, fee + 1 ether);

        MockERC20 t0 = new MockERC20("F", "F", 18);

        vm.prank(user1);
        factory.createPool{value: fee}(
            address(t0), address(pairedToken),
            int24(60), SQRT_PRICE_1_1,
            200, 86400, 60, 0, 0, 0, 0
        );

        assertEq(address(factory).balance, fee);
    }

    function testFuzz_setCreationFee(uint256 fee) public {
        factory.setCreationFee(fee);
        assertEq(factory.creationFee(), fee);
    }

    // ══════════════════════════════════════════════════════════════════════
    // TransferFailed edge cases
    // ══════════════════════════════════════════════════════════════════════

    function test_createPool_revert_refundTransferFailed() public {
        // Deploy a contract that rejects ETH refunds
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        // Rejecter creates pool with excess ETH — refund should fail
        vm.prank(address(rejecter));
        vm.expectRevert(SafeSwapFactory.TransferFailed.selector);
        factory.createPool{value: CREATION_FEE + 1 ether}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );
    }

    function test_withdrawFees_revert_transferFailed() public {
        // Accumulate some fees
        vm.prank(user1);
        factory.createPool{value: CREATION_FEE}(
            address(memeToken),
            address(pairedToken),
            int24(60),
            SQRT_PRICE_1_1,
            200, 86400, 60,
            0, 0, 0, 0
        );

        // Try to withdraw to a contract that rejects ETH
        ETHRejecter rejecter = new ETHRejecter();
        vm.expectRevert(SafeSwapFactory.TransferFailed.selector);
        factory.withdrawFees(address(rejecter));
    }
}

/// @dev Helper contract that rejects all ETH transfers
contract ETHRejecter {
    receive() external payable {
        revert("no ETH");
    }
}
