// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../src/TestToken.sol";
import {SafeSwapFactory} from "../src/SafeSwapFactory.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

contract CreatePool is Script {
    // Arbitrum One addresses
    address constant FACTORY = 0x3bB7a9ebc6351387E1E937772CFC3652f979cB4f;
    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy test token
        TestToken token = new TestToken();
        console.log("TestToken deployed:", address(token));
        console.log("Balance:", token.balanceOf(msg.sender));

        // Step 2: Create protected pool via Factory
        // sqrtPriceX96 for ~1:1 price ratio
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0); // 1:1

        SafeSwapFactory factory = SafeSwapFactory(FACTORY);
        factory.createPool(
            address(token),     // memeToken
            WETH,               // pairedToken
            60,                 // tickSpacing
            sqrtPriceX96,       // initial price (1:1)
            200,                // maxSellBps = 2% per window
            86400,              // windowDuration = 24h
            60,                 // cooldownSeconds = 60s
            3600,               // launchDurationSeconds = 1 hour
            500,                // launchMaxBuyBps = 5%
            100,                // launchMaxSellBps = 1%
            120                 // launchCooldownSeconds = 2 min
        );

        console.log("Pool created successfully!");

        vm.stopBroadcast();
    }
}
