// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISafe} from "src/common/interfaces/IGuardian.sol";

import {PermissionlessAdapter} from "test/vaults/mocks/PermissionlessAdapter.sol";
import {InvestmentManager} from "src/vaults/InvestmentManager.sol";
import {VaultsDeployer} from "script/vaults/Deployer.s.sol";

// Script to deploy Vaults with a permissionless adapter for testing.
contract PermissionlessScript is VaultsDeployer {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        deployVaults(ISafe(msg.sender), msg.sender);

        PermissionlessAdapter adapter = new PermissionlessAdapter(address(gateway));
        wire(adapter);

        vm.stopBroadcast();
    }
}
