// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "src/misc/ERC20.sol";

import {ISafe} from "src/common/interfaces/IGuardian.sol";
import {VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId, newAssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";

import {FullDeployer, PoolsDeployer, VaultsDeployer} from "script/FullDeployer.s.sol";

// Script to deploy CP and CP with an Localhost Adapter.
contract LocalhostDeployer is FullDeployer {
    function run() public {
        uint16 centrifugeId = uint16(vm.envUint("CENTRIFUGE_ID"));

        vm.startBroadcast();

        deployFull(centrifugeId, ISafe(vm.envAddress("ADMIN")), msg.sender);
        saveDeploymentOutput();

        _configureTestData(centrifugeId);

        vm.stopBroadcast();
    }

    function _configureTestData(uint16 centrifugeId) internal {
        // Create pool
        PoolId poolId = poolRouter.createPool(msg.sender, USD, multiShareClass);
        ShareClassId scId = multiShareClass.previewNextShareClassId(poolId);

        // Deploy and register test USDC
        ERC20 token = new ERC20(6);
        token.file("name", "USD Coin");
        token.file("symbol", "USDC");
        token.mint(msg.sender, 10_000_000e6);
        vaultRouter.registerAsset{value: 0.1 ether}(address(token), 0, centrifugeId);

        // Deploy vault
        AssetId assetId = newAssetId(centrifugeId, 1);
        (bytes[] memory cs, uint256 c) = (new bytes[](6), 0);
        cs[c++] = abi.encodeWithSelector(poolRouter.setPoolMetadata.selector, bytes("Testing pool"));
        cs[c++] = abi.encodeWithSelector(
            poolRouter.addShareClass.selector, "Tokenized MMF", "MMF", bytes32(bytes("1")), bytes("")
        );
        cs[c++] = abi.encodeWithSelector(poolRouter.notifyPool.selector, centrifugeId);
        cs[c++] = abi.encodeWithSelector(
            poolRouter.notifyShareClass.selector, centrifugeId, scId, bytes32(bytes20(restrictedRedemptions))
        );
        cs[c++] = abi.encodeWithSelector(poolRouter.createHolding.selector, scId, assetId, identityValuation, 0x01);
        cs[c++] = abi.encodeWithSelector(
            poolRouter.updateVault.selector,
            scId,
            assetId,
            bytes32(bytes20(address(poolManager))),
            bytes32(bytes20(address(vaultFactory))),
            VaultUpdateKind.DeployAndLink
        );

        poolRouter.execute{value: 0.1 ether}(poolId, cs);
    }
}
