// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ISafe} from "src/common/Guardian.sol";

import "forge-std/Script.sol";
import {PoolsDeployer} from "script/PoolsDeployer.s.sol";
import {VaultsDeployer} from "script/VaultsDeployer.s.sol";

contract FullDeployer is PoolsDeployer, VaultsDeployer {
    function deployFull(uint16 chainId, ISafe adminSafe_, address deployer) public {
        deployPools(chainId, adminSafe_, deployer);
        deployVaults(chainId, adminSafe_, deployer);
    }

    function removeFullDeployerAccess(address deployer) public {
        removePoolsDeployerAccess(deployer);
        removeVaultsDeployerAccess(deployer);
    }
}
