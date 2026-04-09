// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {SafeSwapHook} from "../src/SafeSwapHook.sol";
import {SafeSwapFactory} from "../src/SafeSwapFactory.sol";

/// @notice Deploy SafeSwapHook + SafeSwapFactory to Arbitrum One
/// @dev Usage:
///   forge script script/Deploy.s.sol:DeploySafeSwap \
///     --rpc-url https://arb1.arbitrum.io/rpc --broadcast --verify \
///     --etherscan-api-key $ARBISCAN_API_KEY \
///     -vvvv
contract DeploySafeSwap is Script {
    // Uniswap V4 PoolManager addresses
    // Arbitrum Sepolia: 0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317
    // Arbitrum One:     0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32
    // Base:             0x498581fF718922c3f8e6A244956aF099B2652b2b
    address constant POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32; // Arbitrum One (mainnet)

    // Initial creation fee: 0 ETH (free during launch)
    uint256 constant INITIAL_CREATION_FEE = 0;

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG
        );

        // Constructor args: poolManager + owner (deployer wallet)
        bytes memory constructorArgs = abi.encode(POOL_MANAGER, deployer);

        // Mine a salt that produces an address with the correct flag bits
        console.log("Mining CREATE2 salt (this may take a moment)...");
        (address hookAddress, bytes32 salt) = HookMiner.find(
            0x4e59b44847b379578588920cA78FbF26c0B4956C,
            flags,
            type(SafeSwapHook).creationCode,
            constructorArgs
        );

        console.log("=== Step 1: Deploy SafeSwapHook ===");
        console.log("Hook address:", hookAddress);
        console.log("Salt:", vm.toString(salt));
        console.log("Owner:", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy hook with CREATE2
        SafeSwapHook hook = new SafeSwapHook{salt: salt}(IPoolManager(POOL_MANAGER), deployer);
        require(address(hook) == hookAddress, "Hook address mismatch");

        // Deploy factory
        console.log("\n=== Step 2: Deploy SafeSwapFactory ===");
        SafeSwapFactory factory = new SafeSwapFactory(
            IPoolManager(POOL_MANAGER),
            hook,
            INITIAL_CREATION_FEE
        );

        // Authorize factory on the hook
        console.log("\n=== Step 3: Authorize Factory ===");
        hook.setFactory(address(factory));

        vm.stopBroadcast();

        // Summary
        console.log("\n========================================");
        console.log("  DEPLOYMENT COMPLETE");
        console.log("========================================");
        console.log("SafeSwapHook:", address(hook));
        console.log("SafeSwapFactory:", address(factory));
        console.log("Owner:", deployer);
        console.log("Creation fee:", INITIAL_CREATION_FEE);
        console.log("Factory authorized:", hook.factory() == address(factory));
    }
}
