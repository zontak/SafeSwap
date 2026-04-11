// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {LiquidityAmounts} from "@uniswap/v4-periphery/src/libraries/LiquidityAmounts.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {LPFeeLibrary} from "@uniswap/v4-core/src/libraries/LPFeeLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract AddLiquidity is Script {
    // Arbitrum One addresses
    IPositionManager constant POSM = IPositionManager(0xd88F38F930b7952f2DB2432Cb002E7abbF3dD869);
    IAllowanceTransfer constant PERMIT2 = IAllowanceTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address constant HOOK = 0x3E61d0519d598bF2dfAEf5B8Fa0256bF7e1D60c0;
    address constant SSDEMO = 0x5148e15b4a90f7BBA98a5941937586b8A2caA349;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        // Token ordering: SSDEMO (0x5148...) < WETH (0x82aF...), so SSDEMO is token0
        address token0 = SSDEMO;
        address token1 = WETH;

        // Step 1: Wrap 0.001 ETH -> WETH
        uint256 wethAmount = 0.001 ether;
        IWETH(WETH).deposit{value: wethAmount}();
        console.log("Wrapped ETH to WETH:", wethAmount);

        // Step 2: Approve both tokens to Permit2
        IERC20(token0).approve(address(PERMIT2), type(uint256).max);
        IWETH(WETH).approve(address(PERMIT2), type(uint256).max);

        // Step 3: Approve PositionManager on Permit2
        PERMIT2.approve(token0, address(POSM), type(uint160).max, type(uint48).max);
        PERMIT2.approve(token1, address(POSM), type(uint160).max, type(uint48).max);

        // Step 4: Build PoolKey (must match exactly how pool was created)
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: LPFeeLibrary.DYNAMIC_FEE_FLAG,
            tickSpacing: int24(60),
            hooks: IHooks(HOOK)
        });

        // Step 5: Calculate liquidity
        // Pool was initialized at tick 0 (1:1 price)
        // Use wide range: -6000 to 6000 (100 tick spacings each way)
        int24 tickLower = int24(-6000);
        int24 tickUpper = int24(6000);
        uint256 amount0Desired = 100_000 * 1e18; // 100k SSDEMO
        uint256 amount1Desired = wethAmount;       // 0.001 WETH

        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );
        console.log("Liquidity:", liquidity);

        // Step 6: Build action plan
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(
            key,
            tickLower,
            tickUpper,
            uint256(liquidity),
            uint128(type(uint128).max), // amount0Max (slippage)
            uint128(type(uint128).max), // amount1Max (slippage)
            address(1),                 // MSG_SENDER constant
            bytes("")                   // hookData
        );
        params[1] = abi.encode(key.currency0, key.currency1);

        // Step 7: Execute
        POSM.modifyLiquidities(abi.encode(actions, params), block.timestamp + 300);

        console.log("Liquidity added successfully!");

        vm.stopBroadcast();
    }
}
