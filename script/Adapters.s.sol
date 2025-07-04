// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAuth} from "src/misc/interfaces/IAuth.sol";

import {Root} from "src/common/Root.sol";
import {Guardian} from "src/common/Guardian.sol";
import {IAdapter} from "src/common/interfaces/IAdapter.sol";
import {MultiAdapter} from "src/common/adapters/MultiAdapter.sol";
import {AxelarAdapter} from "src/common/adapters/AxelarAdapter.sol";
import {WormholeAdapter} from "src/common/adapters/WormholeAdapter.sol";

import {JsonRegistry} from "script/utils/JsonRegistry.s.sol";

import "forge-std/Script.sol";

contract Adapters is Script, JsonRegistry {
    Root public root;
    Guardian public guardian;
    MultiAdapter public multiAdapter;
    IAdapter[] public adapters;

    function run() public {
        // Read and parse JSON configuration
        string memory network = vm.envString("NETWORK");
        string memory configFile = string.concat("env/", network, ".json");
        string memory config = vm.readFile(configFile);
        string memory environment = vm.parseJsonString(config, "$.network.environment");
        bool isTestnet = keccak256(bytes(environment)) == keccak256(bytes("testnet"));

        console.log("Environment:", environment);
        console.log("Is testnet:", isTestnet);

        root = Root(vm.parseJsonAddress(config, "$.contracts.root"));
        multiAdapter = MultiAdapter(vm.parseJsonAddress(config, "$.contracts.multiAdapter"));
        guardian = Guardian(vm.parseJsonAddress(config, "$.contracts.guardian"));

        vm.startBroadcast();
        startDeploymentOutput();

        // Deploy and save adapters in config file
        if (vm.parseJsonBool(config, "$.adapters.wormhole.deploy")) {
            address relayer = vm.parseJsonAddress(config, "$.adapters.wormhole.relayer");
            WormholeAdapter wormholeAdapter = new WormholeAdapter(multiAdapter, relayer, msg.sender);

            IAuth(address(wormholeAdapter)).rely(address(root));
            IAuth(address(wormholeAdapter)).rely(address(guardian));

            if (!isTestnet) {
                IAuth(address(wormholeAdapter)).deny(msg.sender);
            }

            register("wormholeAdapter", address(wormholeAdapter));
            console.log("WormholeAdapter deployed at:", address(wormholeAdapter));
        }

        if (vm.parseJsonBool(config, "$.adapters.axelar.deploy")) {
            address gateway = vm.parseJsonAddress(config, "$.adapters.axelar.gateway");
            address gasService = vm.parseJsonAddress(config, "$.adapters.axelar.gasService");
            AxelarAdapter axelarAdapter = new AxelarAdapter(multiAdapter, gateway, gasService, msg.sender);
            adapters.push(axelarAdapter);

            IAuth(address(axelarAdapter)).rely(address(root));
            IAuth(address(axelarAdapter)).rely(address(guardian));

            if (!isTestnet) {
                IAuth(address(axelarAdapter)).deny(msg.sender);
            }

            register("axelarAdapter", address(axelarAdapter));
            console.log("AxelarAdapter deployed at:", address(axelarAdapter));
        }

        saveDeploymentOutput();
        vm.stopBroadcast();
    }
}
