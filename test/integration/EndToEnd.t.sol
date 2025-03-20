// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "forge-std/Script.sol";

import {ISafe} from "src/common/interfaces/IGuardian.sol";

import {PoolId} from "src/pools/types/PoolId.sol";

import {PoolRouter} from "src/pools/PoolRouter.sol";

import {VaultRouter} from "src/vaults/VaultRouter.sol";

import {FullDeployer, PoolsDeployer, VaultsDeployer} from "script/FullDeployer.s.sol";

import {LocalAdapter} from "test/integration/adapters/LocalAdapter.sol";

/// End to end testing assuming two full deployments in two different chains
contract TestEndToEnd is Test {
    ISafe immutable safeAdminA = ISafe(makeAddr("SafeAdminA"));
    ISafe immutable safeAdminB = ISafe(makeAddr("SafeAdminB"));

    uint32 constant CHAIN_A = 5;
    uint32 constant CHAIN_B = 6;
    uint64 constant GAS = 100 wei;

    address immutable FM = makeAddr("FM");

    FullDeployer deployA = new FullDeployer();
    FullDeployer deployB = new FullDeployer();

    function _deployChain(ISafe safeAdmin, FullDeployer deploy) public returns (LocalAdapter adapter) {
        deploy.deployFull(safeAdmin);

        adapter = new LocalAdapter(deploy.gateway(), address(deploy));
        deploy.wire(adapter);

        // Configure here as deployer
        vm.startPrank(address(deploy));
        deploy.gasService().file("messageGasLimit", GAS);
        vm.stopPrank();

        deploy.removeFullDeployerAccess();
    }

    function setUp() public {
        LocalAdapter adapterA = _deployChain(safeAdminA, deployA);
        LocalAdapter adapterB = _deployChain(safeAdminB, deployB);

        // We connect both deploys through the adapters
        adapterA.setEndpoint(adapterB);
        adapterB.setEndpoint(adapterA);

        // Initialize accounts
        vm.deal(FM, 1 ether);

        // We not use the VM chain
        vm.chainId(0xDEAD);

        // Label contracts (for debugging)
        vm.label(address(deployA.poolRouter()), "CP.PoolRouter");
        // ...
    }

    function _getDeploys(bool sameChain) public returns (PoolsDeployer cp, VaultsDeployer cv) {
        cp = deployA;
        cv = (sameChain) ? deployA : deployB;

        // Label contracts (for debugging)
        vm.label(address(cv.vaultRouter()), "CV.VaultRouter");
        // ...
    }

    /// forge-config: default.isolate = true
    function testConfigurePool(bool sameChain) public {
        (PoolsDeployer cp, VaultsDeployer cv) = _getDeploys(sameChain);

        vm.startPrank(FM);

        PoolId poolId = cp.poolRouter().createPool(FM, deployA.USD(), deployA.multiShareClass());

        (bytes[] memory c, uint256 i) = (new bytes[](1), 0);
        c[i++] = abi.encodeWithSelector(PoolRouter.notifyPool.selector, CHAIN_B);
        assertEq(i, c.length);

        cp.poolRouter().execute{value: GAS}(poolId, c);

        //assetEq(cv.poolManager().pools(poolId.raw()).createdAt, block.number);
    }
}
