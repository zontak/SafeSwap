// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {SafeSwapHook} from "../src/SafeSwapHook.sol";

/// @notice Deploy SafeSwapHook to an address with correct permission flags
/// @dev Usage:
///   forge script script/Deploy.s.sol:DeploySafeSwap \
///     --rpc-url $RPC_URL --broadcast --verify \
///     -vvvv
contract DeploySafeSwap is Script {
    // Uniswap V4 PoolManager addresses (update for target chain)
    // Arbitrum One: 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32
    // Base:         0x498581fF718922c3f8e6A244956aF099B2652b2b
    address constant POOL_MANAGER = 0x360E68faCcca8cA495c1B759Fd9EEe466db9FB32;

    function run() public {
        uint160 flags = uint160(
            Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        bytes memory constructorArgs = abi.encode(POOL_MANAGER);

        // Mine a salt that produces an address with the correct flag bits
        (address hookAddress, bytes32 salt) = HookMiner.find(
            // CREATE2 deployer proxy (used by forge script)
            0x4e59b44847b379578588920cA78FbF26c0B4956C,
            flags,
            type(SafeSwapHook).creationCode,
            constructorArgs
        );

        console.log("Deploying SafeSwapHook to:", hookAddress);
        console.log("Salt:", vm.toString(salt));

        vm.startBroadcast();
        SafeSwapHook hook = new SafeSwapHook{salt: salt}(IPoolManager(POOL_MANAGER));
        vm.stopBroadcast();

        require(address(hook) == hookAddress, "Hook address mismatch");
        console.log("SafeSwapHook deployed at:", address(hook));
        console.log("Owner:", hook.owner());
    }
}
