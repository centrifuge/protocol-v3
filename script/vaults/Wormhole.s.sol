// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {WormholeAdapter} from "src/common/WormholeAdapter.sol";
import {ISafe} from "src/common/interfaces/IGuardian.sol";

import {VaultsDeployer} from "script/vaults/Deployer.s.sol";

// Script to deploy Vaults with an Wormhole Adapter.
contract WormholeScript is VaultsDeployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        deployVaults(ISafe(vm.envAddress("ADMIN")), msg.sender);

        WormholeAdapter adapter = new WormholeAdapter(
            gateway, address(vm.envAddress("WORMHOLE_RELAYER")), uint16(vm.envUint("WORMHOLE_LOCAL_CHAIN_ID"))
        );
        wire(adapter);

        removeDeployerAccess(address(adapter), msg.sender);

        vm.stopBroadcast();
    }
}
