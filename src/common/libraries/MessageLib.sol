// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BytesLib} from "src/misc/libraries/BytesLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import "forge-std/Test.sol";

// TODO: update with the latest version.
enum MessageType {
    Invalid,
    MessageProof,
    InitiateMessageRecovery,
    DisputeMessageRecovery,
    Batch,
    ScheduleUpgrade,
    CancelUpgrade,
    RecoverTokens,
    UpdateCentrifugeGasPrice,
    RegisterAsset,
    NotifyPool,
    NotifyShareClass,
    AllowAsset,
    DisallowAsset,
    UpdateTranchePrice,
    UpdateTrancheMetadata,
    UpdateTrancheHook,
    TransferTrancheTokens,
    UpdateRestriction,
    DepositRequest,
    RedeemRequest,
    FulfilledDepositRequest,
    FulfilledRedeemRequest,
    CancelDepositRequest,
    CancelRedeemRequest,
    FulfilledCancelDepositRequest,
    FulfilledCancelRedeemRequest,
    TriggerRedeemRequest
}

library MessageLib {
    using MessageLib for bytes;
    using BytesLib for bytes;
    using CastLib for *;

    error DeserializationError();

    function messageType(bytes memory _msg) internal pure returns (MessageType) {
        return MessageType(_msg.toUint8(0));
    }

    //---------------------------------------
    //    RegisterAsset
    //---------------------------------------

    struct RegisterAsset {
        uint128 assetId;
        string name; // Fixed to 128 bytes
        bytes32 symbol; // utf8
        uint8 decimals;
    }

    function deserializeRegisterAsset(bytes memory data) internal pure returns (RegisterAsset memory) {
        require(messageType(data) == MessageType.RegisterAsset, DeserializationError());
        return RegisterAsset({
            assetId: data.toUint128(1),
            name: data.slice(17, 128).bytes128ToString(),
            symbol: data.toBytes32(145),
            decimals: data.toUint8(177)
        });
    }

    function serialize(RegisterAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.RegisterAsset, t.assetId, bytes(t.name).sliceZeroPadded(0, 128), t.symbol, t.decimals
        );
    }

    //---------------------------------------
    //    NotifyPool
    //---------------------------------------

    struct NotifyPool {
        uint64 poolId;
    }

    function deserializeNotifyPool(bytes memory data) internal pure returns (NotifyPool memory) {
        require(messageType(data) == MessageType.NotifyPool, DeserializationError());
        return NotifyPool({poolId: data.toUint64(1)});
    }

    function serialize(NotifyPool memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.NotifyPool, t.poolId);
    }

    //---------------------------------------
    //    NotifyShareClass
    //---------------------------------------

    struct NotifyShareClass {
        uint64 poolId;
        bytes16 scId;
        string name; // Fixed to 128 bytes
        bytes32 symbol; // utf8
        uint8 decimals;
        bytes32 hook;
    }

    function deserializeNotifyShareClass(bytes memory data) internal pure returns (NotifyShareClass memory) {
        require(messageType(data) == MessageType.NotifyShareClass, DeserializationError());
        return NotifyShareClass({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            name: data.slice(25, 128).bytes128ToString(),
            symbol: data.toBytes32(153),
            decimals: data.toUint8(185),
            hook: data.toBytes32(186)
        });
    }

    function serialize(NotifyShareClass memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.NotifyShareClass,
            t.poolId,
            t.scId,
            bytes(t.name).sliceZeroPadded(0, 128),
            t.symbol,
            t.decimals,
            t.hook
        );
    }

    //---------------------------------------
    //    AllowAsset
    //---------------------------------------

    struct AllowAsset {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
    }

    function deserializeAllowAsset(bytes memory data) internal pure returns (AllowAsset memory) {
        require(messageType(data) == MessageType.AllowAsset, DeserializationError());
        return AllowAsset({poolId: data.toUint64(1), scId: data.toBytes16(9), assetId: data.toUint128(25)});
    }

    function serialize(AllowAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.AllowAsset, t.poolId, t.scId, t.assetId);
    }

    //---------------------------------------
    //    DisallowAsset
    //---------------------------------------

    struct DisallowAsset {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
    }

    function deserializeDisallowAsset(bytes memory data) internal pure returns (DisallowAsset memory) {
        require(messageType(data) == MessageType.DisallowAsset, DeserializationError());
        return DisallowAsset({poolId: data.toUint64(1), scId: data.toBytes16(9), assetId: data.toUint128(25)});
    }

    function serialize(DisallowAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.DisallowAsset, t.poolId, t.scId, t.assetId);
    }

    //---------------------------------------
    //    DepositRequest
    //---------------------------------------

    struct DepositRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 amount;
    }

    function deserializeDepositRequest(bytes memory data) internal pure returns (DepositRequest memory) {
        require(messageType(data) == MessageType.DepositRequest, DeserializationError());
        return DepositRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            amount: data.toUint128(73)
        });
    }

    function serialize(DepositRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.DepositRequest, t.poolId, t.scId, t.investor, t.assetId, t.amount);
    }

    //---------------------------------------
    //    RedeemRequest
    //---------------------------------------

    struct RedeemRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 amount;
    }

    function deserializeRedeemRequest(bytes memory data) internal pure returns (RedeemRequest memory) {
        require(messageType(data) == MessageType.RedeemRequest, DeserializationError());
        return RedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            amount: data.toUint128(73)
        });
    }

    function serialize(RedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.RedeemRequest, t.poolId, t.scId, t.investor, t.assetId, t.amount);
    }

    //---------------------------------------
    //    CancelDepositRequest
    //---------------------------------------

    struct CancelDepositRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
    }

    function deserializeCancelDepositRequest(bytes memory data) internal pure returns (CancelDepositRequest memory) {
        require(messageType(data) == MessageType.CancelDepositRequest, DeserializationError());
        return CancelDepositRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57)
        });
    }

    function serialize(CancelDepositRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.CancelDepositRequest, t.poolId, t.scId, t.investor, t.assetId);
    }

    //---------------------------------------
    //    CancelRedeemRequest
    //---------------------------------------

    struct CancelRedeemRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
    }

    function deserializeCancelRedeemRequest(bytes memory data) internal pure returns (CancelRedeemRequest memory) {
        require(messageType(data) == MessageType.CancelRedeemRequest, DeserializationError());
        return CancelRedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57)
        });
    }

    function serialize(CancelRedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.CancelRedeemRequest, t.poolId, t.scId, t.investor, t.assetId);
    }

    //---------------------------------------
    //    FulfilledDepositRequest
    //---------------------------------------

    struct FulfilledDepositRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 shareAmount;
        uint128 assetAmount;
    }

    function deserializeFulfilledDepositRequest(bytes memory data)
        internal
        pure
        returns (FulfilledDepositRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledDepositRequest, DeserializationError());
        return FulfilledDepositRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            shareAmount: data.toUint128(73),
            assetAmount: data.toUint128(89)
        });
    }

    function serialize(FulfilledDepositRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledDepositRequest, t.poolId, t.scId, t.investor, t.assetId, t.shareAmount, t.assetAmount
        );
    }

    //---------------------------------------
    //    FulfilledRedeemRequest
    //---------------------------------------

    struct FulfilledRedeemRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 shareAmount;
        uint128 assetAmount;
    }

    function deserializeFulfilledRedeemRequest(bytes memory data)
        internal
        pure
        returns (FulfilledRedeemRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledRedeemRequest, DeserializationError());
        return FulfilledRedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            shareAmount: data.toUint128(73),
            assetAmount: data.toUint128(89)
        });
    }

    function serialize(FulfilledRedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledRedeemRequest, t.poolId, t.scId, t.investor, t.assetId, t.shareAmount, t.assetAmount
        );
    }

    //---------------------------------------
    //    FulfilledCancelDepositRequest
    //---------------------------------------

    struct FulfilledCancelDepositRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 cancelledAmount;
    }

    function deserializeFulfilledCancelDepositRequest(bytes memory data)
        internal
        pure
        returns (FulfilledCancelDepositRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledCancelDepositRequest, DeserializationError());
        return FulfilledCancelDepositRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            cancelledAmount: data.toUint128(73)
        });
    }

    function serialize(FulfilledCancelDepositRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledCancelDepositRequest, t.poolId, t.scId, t.investor, t.assetId, t.cancelledAmount
        );
    }

    //---------------------------------------
    //    FulfilledCancelRedeemRequest
    //---------------------------------------

    struct FulfilledCancelRedeemRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 cancelledShares;
    }

    function deserializeFulfilledCancelRedeemRequest(bytes memory data)
        internal
        pure
        returns (FulfilledCancelRedeemRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledCancelRedeemRequest, DeserializationError());
        return FulfilledCancelRedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            cancelledShares: data.toUint128(73)
        });
    }

    function serialize(FulfilledCancelRedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledCancelRedeemRequest, t.poolId, t.scId, t.investor, t.assetId, t.cancelledShares
        );
    }

    //---------------------------------------
    //    TriggerRedeemRequest
    //---------------------------------------

    struct TriggerRedeemRequest {
        uint64 poolId;
        bytes16 scId;
        bytes32 investor;
        uint128 assetId;
        uint128 shares;
    }

    function deserializeTriggerRedeemRequest(bytes memory data) internal pure returns (TriggerRedeemRequest memory) {
        require(messageType(data) == MessageType.TriggerRedeemRequest, DeserializationError());
        return TriggerRedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            shares: data.toUint128(73)
        });
    }

    function serialize(TriggerRedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.TriggerRedeemRequest, t.poolId, t.scId, t.investor, t.assetId, t.shares);
    }
}
