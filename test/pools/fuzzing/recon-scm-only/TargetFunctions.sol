// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";
import {console2} from "forge-std/console2.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Source
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "./Properties.sol";

import {IHubRegistry} from "src/hub/interfaces/IHubRegistry.sol";
import {IAccounting} from "src/hub/interfaces/IAccounting.sol";
import {IHoldings} from "src/hub/interfaces/IHoldings.sol";
import {IMessageSender} from "src/common/interfaces/IMessageSender.sol";
import {IAsyncRequests} from "src/vaults/interfaces/investments/IAsyncRequests.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";
import {TransientValuation, ITransientValuation} from "src/misc/TransientValuation.sol";
import {IdentityValuation} from "src/misc/IdentityValuation.sol";
import {MessageProcessor} from "src/common/MessageProcessor.sol";
import {Root} from "src/common/Root.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {MockAdapter} from "test/common/mocks/MockAdapter.sol";
import {MockGasService} from "test/common/mocks/MockGasService.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";

abstract contract TargetFunctions is
    BaseTargetFunctions,
    Properties
{


    function shareClassManager_addShareClass(PoolId poolId, string memory name, string memory symbol, bytes32 salt, bytes memory ) public asAdmin {
        shareClassManager.addShareClass(poolId, name, symbol, salt, bytes(""));
    }

    function shareClassManager_approveDeposits(uint128 maxApproval, AssetId paymentAssetId) public asAdmin {
        shareClassManager.approveDeposits(poolId, scId, maxApproval, paymentAssetId, valuation);
    }

    function shareClassManager_approveRedeems(uint128 maxApproval, AssetId payoutAssetId) public asAdmin {
        shareClassManager.approveRedeems(poolId, scId, maxApproval, payoutAssetId);
    }

    function shareClassManager_cancelDepositRequest(AssetId depositAssetId) public asAdmin {

        shareClassManager.cancelDepositRequest(poolId, scId, bytes32(uint256(uint160(_getActor()))), depositAssetId);
    }

    function shareClassManager_cancelRedeemRequest(AssetId payoutAssetId) public asAdmin {
        shareClassManager.cancelRedeemRequest(poolId, scId, bytes32(uint256(uint160(_getActor()))), payoutAssetId);
    }

    function shareClassManager_claimDeposit(AssetId depositAssetId) public asAdmin {
        shareClassManager.claimDeposit(poolId, scId, bytes32(uint256(uint160(_getActor()))), depositAssetId);
    }

    function shareClassManager_claimDepositUntilEpoch(AssetId depositAssetId, uint32 endEpochId) public asAdmin {
        shareClassManager.claimDepositUntilEpoch(poolId, scId, bytes32(uint256(uint160(_getActor()))), depositAssetId, endEpochId);
    }

    function shareClassManager_claimRedeem(AssetId payoutAssetId) public asAdmin {
        shareClassManager.claimRedeem(poolId, scId, bytes32(uint256(uint160(_getActor()))), payoutAssetId);
    }

    function shareClassManager_claimRedeemUntilEpoch(AssetId payoutAssetId, uint32 endEpochId) public asAdmin {
        shareClassManager.claimRedeemUntilEpoch(poolId, scId, bytes32(uint256(uint160(_getActor()))), payoutAssetId, endEpochId);
    }

    function shareClassManager_decreaseShareClassIssuance(D18 navPerShare, uint128 amount) public asAdmin {
        shareClassManager.decreaseShareClassIssuance(poolId, scId, navPerShare, amount);
    }

    function shareClassManager_deny(address user) public asAdmin {
        shareClassManager.deny(user);
    }

    function shareClassManager_file(bytes32 what, address data) public asAdmin {
        shareClassManager.file(what, data);
    }

    function shareClassManager_increaseShareClassIssuance(D18 navPerShare, uint128 amount) public asAdmin {
        shareClassManager.increaseShareClassIssuance(poolId, scId, navPerShare, amount);
    }

    function shareClassManager_issueShares(AssetId depositAssetId, D18 navPerShare) public asAdmin {
        shareClassManager.issueShares(poolId, scId, depositAssetId, navPerShare);
    }

    function shareClassManager_issueSharesUntilEpoch(AssetId depositAssetId, D18 navPerShare, uint32 endEpochId) public asAdmin {
        shareClassManager.issueSharesUntilEpoch(poolId, scId, depositAssetId, navPerShare, endEpochId);
    }

    function shareClassManager_rely(address user) public asAdmin {
        shareClassManager.rely(user);
    }

    function shareClassManager_requestDeposit(uint128 amount, AssetId depositAssetId) public asAdmin {
        shareClassManager.requestDeposit(poolId, scId, amount, bytes32(uint256(uint160(_getActor()))), depositAssetId);
    }

    function shareClassManager_requestRedeem(uint128 amount, AssetId payoutAssetId) public asAdmin {
        shareClassManager.requestRedeem(poolId, scId, amount, bytes32(uint256(uint160(_getActor()))), payoutAssetId);
    }

    function shareClassManager_revokeShares(AssetId payoutAssetId, D18 navPerShare) public asAdmin {
        shareClassManager.revokeShares(poolId, scId, payoutAssetId, navPerShare, valuation);
    }

    function shareClassManager_revokeSharesUntilEpoch(AssetId payoutAssetId, D18 navPerShare, uint32 endEpochId) public asAdmin {
        shareClassManager.revokeSharesUntilEpoch(poolId, scId, payoutAssetId, navPerShare, valuation, endEpochId);
    }

    function shareClassManager_updateMetadata(string memory name, string memory symbol, bytes32 salt, bytes memory ) public asAdmin {
        shareClassManager.updateMetadata(poolId, scId, name, symbol, salt, bytes(""));
    }

    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
