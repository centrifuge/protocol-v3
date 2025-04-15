// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ERC20} from "src/misc/ERC20.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {ISafe} from "src/common/interfaces/IGuardian.sol";
import {VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId, newAssetId} from "src/common/types/AssetId.sol";
import {AccountId} from "src/common/types/AccountId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {MessageLib, UpdateContractType, VaultUpdateKind} from "src/common/libraries/MessageLib.sol";

import {IShareToken} from "src/vaults/interfaces/token/IShareToken.sol";
import {IAsyncVault} from "src/vaults/interfaces/IERC7540.sol";

import {FullDeployer, HubDeployer, VaultsDeployer} from "script/FullDeployer.s.sol";

// Script to deploy Hub and Vaults with a Localhost Adapter.
contract LocalhostDeployer is FullDeployer {
    using CastLib for address;
    using MessageLib for *;

    function run() public {
        uint16 centrifugeId = uint16(vm.envUint("CENTRIFUGE_ID"));

        vm.startBroadcast();

        deployFull(centrifugeId, ISafe(vm.envAddress("ADMIN")), msg.sender, false);

        // Since `wire()` is not called, separately adding the safe here
        guardian.file("safe", address(adminSafe));

        saveDeploymentOutput();

        _configureTestData(centrifugeId);

        vm.stopBroadcast();
    }

    function _configureTestData(uint16 centrifugeId) internal {
        // Deploy and register test USDC
        ERC20 token = new ERC20(6);
        token.file("name", "USD Coin");
        token.file("symbol", "USDC");
        token.mint(msg.sender, 10_000_000e6);
        poolManager.registerAsset(centrifugeId, address(token), 0);

        AssetId assetId = newAssetId(centrifugeId, 1);

        _deployAsyncVault(centrifugeId, token, assetId);
        _deploySyncDepositVault(centrifugeId, token, assetId);
    }

    function _deployAsyncVault(uint16 centrifugeId, ERC20 token, AssetId assetId) internal {
        PoolId poolId = hub.createPool(msg.sender, USD);
        hub.allowPoolAdmin(poolId, vm.envAddress("ADMIN"), true);
        ShareClassId scId = shareClassManager.previewNextShareClassId(poolId);

        hub.setPoolMetadata(poolId, bytes("Testing pool"));
        hub.addShareClass(poolId, "Tokenized MMF", "MMF", bytes32(bytes("1")), bytes(""));
        hub.notifyPool(poolId, centrifugeId);
        hub.notifyShareClass(poolId, centrifugeId, scId, bytes32(bytes20(freelyTransferable)));

        hub.createAccount(poolId, AccountId.wrap(0x01), true);
        hub.createAccount(poolId, AccountId.wrap(0x02), false);
        hub.createAccount(poolId, AccountId.wrap(0x03), false);
        hub.createAccount(poolId, AccountId.wrap(0x04), false);
        hub.createHolding(
            poolId,
            scId,
            assetId,
            identityValuation,
            AccountId.wrap(0x01),
            AccountId.wrap(0x02),
            AccountId.wrap(0x03),
            AccountId.wrap(0x04)
        );

        hub.updateContract(
            poolId,
            centrifugeId,
            scId,
            bytes32(bytes20(address(poolManager))),
            MessageLib.UpdateContractVaultUpdate({
                vaultOrFactory: bytes32(bytes20(address(asyncVaultFactory))),
                assetId: assetId.raw(),
                kind: uint8(VaultUpdateKind.DeployAndLink)
            }).serialize()
        );

        hub.updatePricePerShare(poolId, scId, d18(1, 1));
        hub.notifySharePrice(poolId, centrifugeId, scId);
        hub.notifyAssetPrice(poolId, scId, assetId);

        // Submit deposit request
        IShareToken shareToken = IShareToken(poolManager.shareToken(poolId.raw(), scId.raw()));
        IAsyncVault vault = IAsyncVault(shareToken.vault(address(token)));

        uint128 investAmount = 1_000_000e6;
        token.approve(address(vault), investAmount);
        vault.requestDeposit(investAmount, msg.sender, msg.sender);

        // Fulfill deposit request
        hub.approveDeposits(poolId, scId, assetId, shareClassManager.nowDepositEpoch(scId, assetId), investAmount);
        hub.issueShares(poolId, scId, assetId, shareClassManager.nowIssueEpoch(scId, assetId), d18(1, 1));

        uint32 maxClaims = shareClassManager.maxDepositClaims(scId, msg.sender.toBytes32(), assetId);
        hub.claimDeposit(poolId, scId, assetId, msg.sender.toBytes32(), maxClaims);

        // Claim deposit request
        vault.mint(investAmount, msg.sender);

        // Withdraw principal
        balanceSheet.withdraw(poolId, scId, address(token), 0, msg.sender, investAmount, d18(1, 1));

        // Update price, deposit principal + yield
        hub.updatePricePerShare(poolId, scId, d18(11, 10));
        hub.notifySharePrice(poolId, centrifugeId, scId);
        hub.notifyAssetPrice(poolId, scId, assetId);

        uint256 redeemAmount = investAmount + 100_000e6;
        token.approve(address(balanceSheet), redeemAmount);
        balanceSheet.deposit(poolId, scId, address(token), 0, msg.sender, uint128(redeemAmount), d18(11, 10));

        // Make sender a member to submit redeem request
        hub.updateRestriction(
            poolId,
            centrifugeId,
            scId,
            MessageLib.UpdateRestrictionMember({user: bytes32(bytes20(msg.sender)), validUntil: type(uint64).max})
                .serialize()
        );

        // Submit redeem request
        vault.requestRedeem(investAmount, msg.sender, msg.sender);

        // Fulfill redeem request
        hub.approveRedeems(
            poolId, scId, assetId, shareClassManager.nowRedeemEpoch(scId, assetId), uint128(investAmount)
        );
        hub.revokeShares(poolId, scId, assetId, shareClassManager.nowRevokeEpoch(scId, assetId), d18(11, 10));

        hub.claimRedeem(poolId, scId, assetId, bytes32(bytes20(msg.sender)), 1);

        // Claim redeem request
        vault.withdraw(redeemAmount, msg.sender, msg.sender);
    }

    function _deploySyncDepositVault(uint16 centrifugeId, ERC20 token, AssetId assetId) internal {
        PoolId poolId = hub.createPool(msg.sender, USD);
        hub.allowPoolAdmin(poolId, vm.envAddress("ADMIN"), true);
        ShareClassId scId = shareClassManager.previewNextShareClassId(poolId);

        D18 navPerShare = d18(1, 1);

        hub.setPoolMetadata(poolId, bytes("Testing pool"));
        hub.addShareClass(poolId, "RWA Portfolio", "RWA", bytes32(bytes("2")), bytes(""));
        hub.notifyPool(poolId, centrifugeId);
        hub.notifyShareClass(poolId, centrifugeId, scId, bytes32(bytes20(freelyTransferable)));

        hub.createAccount(poolId, AccountId.wrap(0x01), true);
        hub.createAccount(poolId, AccountId.wrap(0x02), false);
        hub.createAccount(poolId, AccountId.wrap(0x03), false);
        hub.createAccount(poolId, AccountId.wrap(0x04), false);
        hub.createHolding(
            poolId,
            scId,
            assetId,
            identityValuation,
            AccountId.wrap(0x01),
            AccountId.wrap(0x02),
            AccountId.wrap(0x03),
            AccountId.wrap(0x04)
        );

        hub.updateContract(
            poolId,
            centrifugeId,
            scId,
            bytes32(bytes20(address(poolManager))),
            MessageLib.UpdateContractVaultUpdate({
                vaultOrFactory: bytes32(bytes20(address(syncDepositVaultFactory))),
                assetId: assetId.raw(),
                kind: uint8(VaultUpdateKind.DeployAndLink)
            }).serialize()
        );

        hub.updatePricePerShare(poolId, scId, navPerShare);
        hub.notifySharePrice(poolId, centrifugeId, scId);
        hub.notifyAssetPrice(poolId, scId, assetId);

        // Deposit
        IShareToken shareToken = IShareToken(poolManager.shareToken(poolId.raw(), scId.raw()));
        IAsyncVault vault = IAsyncVault(shareToken.vault(address(token)));

        uint128 investAmount = 1_000_000e6;
        token.approve(address(vault), investAmount);
        vault.deposit(investAmount, msg.sender);
    }
}
