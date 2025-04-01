// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18} from "src/misc/types/D18.sol";

import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {JournalEntry, Meta} from "src/common/libraries/JournalEntryLib.sol";

interface ILocalCentrifugeId {
    function localCentrifugeId() external view returns (uint16);
}

/// @notice Interface for dispatch-only gateway
interface IPoolMessageSender is ILocalCentrifugeId {
    /// @notice Creates and send the message
    function sendNotifyPool(uint16 chainId, PoolId poolId) external;

    /// @notice Creates and send the message
    function sendNotifyShareClass(
        uint16 chainId,
        PoolId poolId,
        ShareClassId scId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        bytes32 salt,
        bytes32 hook
    ) external;

    function sendNotifySharePrice(PoolId poolId, ShareClassId scId, AssetId assetId, D18 pricePerShare) external;

    /// @notice Creates and send the message
    function sendFulfilledDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 assetAmount,
        uint128 shareAmount
    ) external;

    /// @notice Creates and send the message
    function sendFulfilledRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 assetAmount,
        uint128 shareAmount
    ) external;

    /// @notice Creates and send the message
    function sendFulfilledCancelDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 cancelledAmount
    ) external;

    /// @notice Creates and send the message
    function sendFulfilledCancelRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 cancelledShares
    ) external;

    /// @notice Creates and send the message
    function sendUpdateContract(
        uint16 chainId,
        PoolId poolId,
        ShareClassId scId,
        bytes32 target,
        bytes calldata payload
    ) external;
}

/// @notice Interface for dispatch-only gateway
interface IVaultMessageSender is ILocalCentrifugeId {
    /// @notice Creates and send the message
    function sendTransferShares(uint16 chainId, uint64 poolId, bytes16 scId, bytes32 recipient, uint128 amount)
        external;

    /// @notice Creates and send the message
    function sendDepositRequest(uint64 poolId, bytes16 scId, bytes32 investor, uint128 assetId, uint128 amount)
        external;

    /// @notice Creates and send the message
    function sendRedeemRequest(uint64 poolId, bytes16 scId, bytes32 investor, uint128 assetId, uint128 amount)
        external;

    /// @notice Creates and send the message
    function sendCancelDepositRequest(uint64 poolId, bytes16 scId, bytes32 investor, uint128 assetId) external;

    /// @notice Creates and send the message
    function sendCancelRedeemRequest(uint64 poolId, bytes16 scId, bytes32 investor, uint128 assetId) external;

    /// @notice Creates and send the message
    function sendRegisterAsset(
        uint16 chainId,
        uint128 assetId,
        string memory name,
        string memory symbol,
        uint8 decimals
    ) external;

    /// @notice Creates and send the message
    function sendUpdateHoldingAmount(
        PoolId poolId,
        ShareClassId shareClassId,
        AssetId assetId,
        address provider,
        uint128 amount,
        D18 pricePerUnit,
        bool isIncrease,
        Meta calldata meta
    ) external;

    function sendUpdateHoldingValue(PoolId poolId, ShareClassId scId, AssetId assetId, D18 pricePerUnit) external;

    /// @notice Creates and send the message
    function sendUpdateShares(
        PoolId poolId,
        ShareClassId shareClassId,
        address receiver,
        D18 pricePerShare,
        uint128 shares,
        bool isIssuance
    ) external;

    function sendJournalEntry(PoolId poolId, JournalEntry[] calldata debits, JournalEntry[] calldata credits)
        external;
}
