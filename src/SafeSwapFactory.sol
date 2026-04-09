// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {SafeSwapHook} from "./SafeSwapHook.sol";

/// @title SafeSwap Factory — Permissionless pool creation with anti-rug protection
/// @notice Anyone can create a SafeSwap-protected pool by paying the creation fee
contract SafeSwapFactory {

    // ══════════════════════════════════════════════════════════════════════
    // Errors
    // ══════════════════════════════════════════════════════════════════════

    error NotOwner();
    error InsufficientFee(uint256 sent, uint256 required);
    error InvalidTokens();
    error TransferFailed();

    // ══════════════════════════════════════════════════════════════════════
    // Events
    // ══════════════════════════════════════════════════════════════════════

    event PoolCreated(
        address indexed creator,
        address indexed token0,
        address indexed token1,
        int24 tickSpacing,
        uint256 feePaid
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ══════════════════════════════════════════════════════════════════════
    // State
    // ══════════════════════════════════════════════════════════════════════

    address public immutable owner;
    IPoolManager public immutable poolManager;
    SafeSwapHook public immutable hook;

    uint256 public creationFee;

    // ══════════════════════════════════════════════════════════════════════
    // Constructor
    // ══════════════════════════════════════════════════════════════════════

    constructor(IPoolManager _poolManager, SafeSwapHook _hook, uint256 _initialFee) {
        owner = msg.sender;
        poolManager = _poolManager;
        hook = _hook;
        creationFee = _initialFee;
    }

    // ══════════════════════════════════════════════════════════════════════
    // Pool creation
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Create a SafeSwap-protected pool
    /// @param memeToken The address of the protected (meme) token
    /// @param pairedToken The address of the paired token (e.g., WETH, USDC)
    /// @param tickSpacing Tick spacing for the pool (e.g., 60)
    /// @param sqrtPriceX96 Initial price for the pool
    /// @param maxSellBps Max sell per window in basis points (e.g., 200 = 2%)
    /// @param windowDuration Rate limit window in seconds (0 = default 24h)
    /// @param cooldownSeconds Min seconds between sells per wallet
    /// @param launchDurationSeconds Launch protection duration (0 = disabled)
    /// @param launchMaxBuyBps Max buy during launch in basis points
    /// @param launchMaxSellBps Max sell during launch in basis points
    /// @param launchCooldownSeconds Cooldown during launch
    function createPool(
        address memeToken,
        address pairedToken,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        uint64 maxSellBps,
        uint64 windowDuration,
        uint64 cooldownSeconds,
        uint64 launchDurationSeconds,
        uint64 launchMaxBuyBps,
        uint64 launchMaxSellBps,
        uint64 launchCooldownSeconds
    ) external payable {
        if (msg.value < creationFee) revert InsufficientFee(msg.value, creationFee);
        if (memeToken == pairedToken || memeToken == address(0) || pairedToken == address(0)) {
            revert InvalidTokens();
        }

        // Sort tokens (Uniswap V4 requires currency0 < currency1)
        bool memeIsToken0 = memeToken < pairedToken;
        (Currency currency0, Currency currency1) = memeIsToken0
            ? (Currency.wrap(memeToken), Currency.wrap(pairedToken))
            : (Currency.wrap(pairedToken), Currency.wrap(memeToken));

        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });

        // Configure SafeSwap protection
        hook.configurePool(
            key,
            memeIsToken0,
            maxSellBps,
            windowDuration,
            cooldownSeconds,
            launchDurationSeconds,
            launchMaxBuyBps,
            launchMaxSellBps,
            launchCooldownSeconds
        );

        // Initialize the pool
        poolManager.initialize(key, sqrtPriceX96);

        emit PoolCreated(
            msg.sender,
            Currency.unwrap(currency0),
            Currency.unwrap(currency1),
            tickSpacing,
            creationFee
        );

        // Refund excess ETH (after all state changes — CEI pattern)
        uint256 excess = msg.value - creationFee;
        if (excess > 0) {
            (bool sent,) = msg.sender.call{value: excess}("");
            if (!sent) revert TransferFailed();
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Owner functions
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Update the pool creation fee
    function setCreationFee(uint256 newFee) external {
        if (msg.sender != owner) revert NotOwner();
        emit CreationFeeUpdated(creationFee, newFee);
        creationFee = newFee;
    }

    /// @notice Withdraw collected creation fees
    function withdrawFees(address to) external {
        if (msg.sender != owner) revert NotOwner();
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool sent,) = to.call{value: balance}("");
            if (!sent) revert TransferFailed();
            emit FeesWithdrawn(to, balance);
        }
    }
}
