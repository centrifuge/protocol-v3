// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {PoolId} from "src/common/types/PoolId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {IGuardian, ISafe} from "src/common/interfaces/IGuardian.sol";

import {Hub} from "src/hub/Hub.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";

import {VaultRouter} from "src/vaults/VaultRouter.sol";
import "src/vaults/interfaces/IPoolManager.sol";

import {FullDeployer, HubDeployer, VaultsDeployer} from "script/FullDeployer.s.sol";
import {CommonDeployer, MESSAGE_COST_ENV} from "script/CommonDeployer.s.sol";

import {LocalAdapter} from "test/integration/adapters/LocalAdapter.sol";

/// End to end testing assuming two full deployments in two different chains
contract TestEndToEnd is Test {
    ISafe immutable safeAdminA = ISafe(makeAddr("SafeAdminA"));
    ISafe immutable safeAdminB = ISafe(makeAddr("SafeAdminB"));

    uint16 constant CENTRIFUGE_ID_A = 5;
    uint16 constant CENTRIFUGE_ID_B = 6;
    uint64 constant GAS = 100 wei;

    address immutable DEPLOYER = address(this);
    address immutable FM = makeAddr("FM");

    FullDeployer deployA = new FullDeployer();
    FullDeployer deployB = new FullDeployer();

    function setUp() public {
        vm.setEnv(MESSAGE_COST_ENV, vm.toString(GAS));

        LocalAdapter adapterA = _deployChain(deployA, CENTRIFUGE_ID_A, CENTRIFUGE_ID_B, safeAdminA);
        LocalAdapter adapterB = _deployChain(deployB, CENTRIFUGE_ID_B, CENTRIFUGE_ID_A, safeAdminB);

        // We connect both deploys through the adapters
        adapterA.setEndpoint(adapterB);
        adapterB.setEndpoint(adapterA);

        // Initialize accounts
        vm.deal(FM, 1 ether);

        // We not use the VM chain
        vm.chainId(0xDEAD);
    }

    function _deployChain(FullDeployer deploy, uint16 localCentrifugeId, uint16 remoteCentrifugeId, ISafe safeAdmin)
        public
        returns (LocalAdapter adapter)
    {
        deploy.deployFull(localCentrifugeId, safeAdmin, address(deploy), true);

        adapter = new LocalAdapter(localCentrifugeId, deploy.gateway(), address(deploy));
        deploy.wire(remoteCentrifugeId, adapter, address(deploy));

        vm.startPrank(address(deploy));
        vm.stopPrank();

        deploy.removeFullDeployerAccess(address(deploy));
    }

    function _getDeploys(bool sameChain) public view returns (HubDeployer ch, VaultsDeployer cv) {
        ch = deployA;
        cv = (sameChain) ? deployA : deployB;
    }

    /// forge-config: default.isolate = true
    function testConfigurePool(bool sameChain) public {
        (HubDeployer ch, VaultsDeployer cv) = _getDeploys(sameChain);
        uint16 cvChainId = cv.messageDispatcher().localCentrifugeId();

        IGuardian guardian = ch.guardian();
        AssetId usd = deployA.USD();
        vm.prank(address(guardian.safe()));
        PoolId poolId = guardian.createPool(FM, usd);

        vm.startPrank(FM);
        ch.hub().notifyPool{value: GAS}(poolId, cvChainId);

        assert(cv.poolManager().pools(poolId.raw()) != 0);
    }
}
