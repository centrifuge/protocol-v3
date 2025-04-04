// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "src/misc/ERC20.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";

import {ISafe} from "src/common/interfaces/IGuardian.sol";
import {VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId, newAssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";

import {IShareToken} from "src/vaults/interfaces/token/IShareToken.sol";
import {IAsyncVault} from "src/vaults/interfaces/IERC7540.sol";

import {FullDeployer, PoolsDeployer, VaultsDeployer} from "script/FullDeployer.s.sol";

// Script to deploy CP and CP with an Localhost Adapter.
contract LocalhostDeployer is FullDeployer {
    function run() public {
        uint16 centrifugeId = uint16(vm.envUint("CENTRIFUGE_ID"));

        vm.startBroadcast();

        deployFull(centrifugeId, ISafe(vm.envAddress("ADMIN")), msg.sender);

        // Since `wire()` is not called, separately adding the safe here
        guardian.file("safe", address(adminSafe));

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
        vaultRouter.registerAsset{value: 0.001 ether}(address(token), 0, centrifugeId);

        // Deploy vault
        D18 navPerShare = d18(1, 1);

        AssetId assetId = newAssetId(centrifugeId, 1);
        (bytes[] memory cs, uint256 c) = (new bytes[](8), 0);
        cs[c++] = abi.encodeWithSelector(poolRouter.setPoolMetadata.selector, bytes("Testing pool"));
        cs[c++] = abi.encodeWithSelector(
            poolRouter.addShareClass.selector, "Tokenized MMF", "MMF", bytes32(bytes("1")), bytes("")
        );
        cs[c++] = abi.encodeWithSelector(poolRouter.notifyPool.selector, centrifugeId);
        cs[c++] = abi.encodeWithSelector(
            poolRouter.notifyShareClass.selector, centrifugeId, scId, bytes32(bytes20(freelyTransferable))
        );
        cs[c++] =
            abi.encodeWithSelector(poolRouter.createHolding.selector, scId, assetId, identityValuation, false, 0x01);
        cs[c++] = abi.encodeWithSelector(
            poolRouter.updateVault.selector,
            scId,
            assetId,
            bytes32(bytes20(address(poolManager))),
            bytes32(bytes20(address(asyncVaultFactory))),
            VaultUpdateKind.DeployAndLink
        );
        // TODO(follow-up): Enable after merging #184
        // cs[c++] = abi.encodeWithSelector(poolRouter.updateSharePrice.selector, scId, navPerShare);
        // cs[c++] = abi.encodeWithSelector(poolRouter.notifySharePrice.selector, scId, assetId);

        //poolRouter.execute{value: 0.001 ether}(poolId, cs);

        // Submit deposit request
        IShareToken shareToken = IShareToken(poolManager.shareToken(poolId.raw(), scId.raw()));
        IAsyncVault vault = IAsyncVault(shareToken.vault(address(token)));

        uint256 investAmount = 1_000_000e6;
        token.approve(address(vault), investAmount);
        vault.requestDeposit(investAmount, msg.sender, msg.sender);

        // Fulfill deposit request
        IERC7726 valuation = holdings.valuation(poolId, scId, assetId);

        (bytes[] memory cs2, uint256 c2) = (new bytes[](2), 0);
        cs2[c2++] = abi.encodeWithSelector(poolRouter.approveDeposits.selector, scId, assetId, investAmount, valuation);
        cs2[c2++] = abi.encodeWithSelector(poolRouter.issueShares.selector, scId, assetId, navPerShare);

        poolRouter.execute{value: 0.001 ether}(poolId, cs2);

        poolRouter.claimDeposit{value: 0.001 ether}(poolId, scId, assetId, bytes32(bytes20(msg.sender)));

        // Claim deposit request
        vault.mint(investAmount, msg.sender);
    }
}
