// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAdapter} from "src/common/interfaces/IAdapter.sol";
import {MultiAdapter} from "src/common/adapters/MultiAdapter.sol";
import {AxelarAdapter} from "src/common/adapters/AxelarAdapter.sol";
import {WormholeAdapter} from "src/common/adapters/WormholeAdapter.sol";

import "forge-std/Script.sol";

/// @dev Configures the local network's adapters to communicate with remote networks.
///      This script only sets up one-directional communication (local → remote).
///      For bidirectional communication, the script must be run on each network separately.
///      Intended for testnet use only.
contract WireAdapters is Script {
    IAdapter[] adapters; // Storage array like in CommonDeployer

    function fetchConfig(string memory network) internal view returns (string memory) {
        string memory configFile = string.concat("env/", network, ".json");
        string memory config = vm.readFile(configFile);

        string memory environment = vm.parseJsonString(config, "$.network.environment");
        if (keccak256(bytes(environment)) != keccak256(bytes("testnet"))) {
            revert("This script is intended for testnet use only");
        }

        return config;
    }

    function run() public {
        string memory localNetwork = vm.envString("NETWORK");
        string memory localConfig = fetchConfig(localNetwork);

        // Declare and initialize local adapter addresses
        address localWormholeAddr = address(0);
        address localAxelarAddr = address(0);

        // Try to get local Wormhole adapter
        try vm.parseJsonAddress(localConfig, "$.contracts.wormholeAdapter") returns (address addr) {
            if (addr != address(0)) {
                localWormholeAddr = addr;
                adapters.push(IAdapter(addr));
            }
        } catch {
            console.log("No WormholeAdapter found in config for network", localNetwork);
        }

        // Try to get local Axelar adapter
        try vm.parseJsonAddress(localConfig, "$.contracts.axelarAdapter") returns (address addr) {
            if (addr != address(0)) {
                localAxelarAddr = addr;
                adapters.push(IAdapter(addr));
            }
        } catch {
            console.log("No AxelarAdapter found in config for network", localNetwork);
        }

        string[] memory connectsTo = vm.parseJsonStringArray(localConfig, "$.network.connectsTo");

        vm.startBroadcast();
        for (uint256 i = 0; i < connectsTo.length; i++) {
            string memory remoteNetwork = connectsTo[i];
            string memory remoteConfig = fetchConfig(remoteNetwork);
            uint16 remoteCentrifugeId = uint16(vm.parseJsonUint(remoteConfig, "$.network.centrifugeId"));

            // Register ALL adapters for this destination chain
            MultiAdapter multiAdapter = MultiAdapter(vm.parseJsonAddress(localConfig, "$.contracts.multiAdapter"));
            multiAdapter.file("adapters", remoteCentrifugeId, adapters);
            console.log("Registered MultiAdapter(", localNetwork, ") for", remoteNetwork);

            // Wire WormholeAdapter
            if (localWormholeAddr != address(0)) {
                try vm.parseJsonAddress(remoteConfig, "$.contracts.wormholeAdapter") {
                    address remoteWormholeAddr = vm.parseJsonAddress(remoteConfig, "$.contracts.wormholeAdapter");
                    uint16 remoteWormholeId = uint16(vm.parseJsonUint(remoteConfig, "$.adapters.wormhole.wormholeId"));

                    WormholeAdapter localWormholeAdapter = WormholeAdapter(localWormholeAddr);
                    localWormholeAdapter.file("sources", remoteCentrifugeId, remoteWormholeId, remoteWormholeAddr);
                    localWormholeAdapter.file("destinations", remoteCentrifugeId, remoteWormholeId, remoteWormholeAddr);

                    console.log("Wired WormholeAdapter from", localNetwork, "to", remoteNetwork);
                } catch {
                    console.log(
                        "Failed to wire Wormhole.",
                        "No WormholeAdapter contract found in config (not deployed yet?) for network ",
                        remoteNetwork
                    );
                }
            }

            // Wire AxelarAdapter
            if (localAxelarAddr != address(0)) {
                try vm.parseJsonAddress(remoteConfig, "$.contracts.axelarAdapter") {
                    address remoteAxelarAddr = vm.parseJsonAddress(remoteConfig, "$.contracts.axelarAdapter");
                    string memory remoteAxelarId = vm.parseJsonString(remoteConfig, "$.adapters.axelar.axelarId");

                    AxelarAdapter localAxelarAdapter = AxelarAdapter(localAxelarAddr);
                    localAxelarAdapter.file(
                        "sources", remoteAxelarId, remoteCentrifugeId, vm.toString(remoteAxelarAddr)
                    );
                    localAxelarAdapter.file(
                        "destinations", remoteCentrifugeId, remoteAxelarId, vm.toString(remoteAxelarAddr)
                    );

                    console.log("Wired AxelarAdapter from", localNetwork, "to", remoteNetwork);
                } catch {
                    console.log(
                        "Failed to wire Axelar.",
                        "No AxelarAdapter contract found (not deployed yet?) in config for network ",
                        remoteNetwork
                    );
                }
            }
        }
        vm.stopBroadcast();
    }
}
