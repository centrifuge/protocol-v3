// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CastLib} from "../../misc/libraries/CastLib.sol";
import {BytesLib} from "../../misc/libraries/BytesLib.sol";

import {PoolId} from "../types/PoolId.sol";
import {AssetId} from "../types/AssetId.sol";

// NOTE: Should never exceed 254 messages because id == 255 corresponds to message proofs
enum MessageType {
    /// @dev Placeholder for null message type
    _Invalid,
    // -- Pool independent messages
    ScheduleUpgrade,
    CancelUpgrade,
    RecoverTokens,
    RegisterAsset,
    _Placeholder5,
    _Placeholder6,
    _Placeholder7,
    _Placeholder8,
    _Placeholder9,
    _Placeholder10,
    _Placeholder11,
    _Placeholder12,
    _Placeholder13,
    _Placeholder14,
    _Placeholder15,
    // -- Pool dependent messages
    NotifyPool,
    NotifyShareClass,
    NotifyPricePoolPerShare,
    NotifyPricePoolPerAsset,
    NotifyShareMetadata,
    UpdateShareHook,
    InitiateTransferShares,
    ExecuteTransferShares,
    UpdateRestriction,
    UpdateContract,
    UpdateVault,
    UpdateBalanceSheetManager,
    UpdateHoldingAmount,
    UpdateShares,
    MaxAssetPriceAge,
    MaxSharePriceAge,
    Request,
    RequestCallback,
    SetRequestManager
}

/// @dev Used internally in the UpdateVault message (not represent a submessage)
enum VaultUpdateKind {
    DeployAndLink,
    Link,
    Unlink
}

library MessageLib {
    using MessageLib for bytes;
    using BytesLib for bytes;
    using CastLib for *;

    error UnknownMessageType();

    /// @dev Encode all message lengths in this constant to avoid a large list of if/elseif checks
    /// and reduce generated bytecode.
    /// If the message has some dynamic part, will be added later in `messageLength()`.
    // forgefmt: disable-next-item
    uint256 constant MESSAGE_LENGTHS_1 =
        (33  << uint8(MessageType.ScheduleUpgrade) * 8) +
        (33  << uint8(MessageType.CancelUpgrade) * 8) +
        (161 << uint8(MessageType.RecoverTokens) * 8) +
        (18  << uint8(MessageType.RegisterAsset) * 8) +
        (0   << uint8(MessageType._Placeholder5) * 8) +
        (0   << uint8(MessageType._Placeholder6) * 8) +
        (0   << uint8(MessageType._Placeholder7) * 8) +
        (0   << uint8(MessageType._Placeholder8) * 8) +
        (0   << uint8(MessageType._Placeholder9) * 8) +
        (0   << uint8(MessageType._Placeholder10) * 8) +
        (0   << uint8(MessageType._Placeholder11) * 8) +
        (0   << uint8(MessageType._Placeholder12) * 8) +
        (0   << uint8(MessageType._Placeholder13) * 8) +
        (0   << uint8(MessageType._Placeholder14) * 8) +
        (0   << uint8(MessageType._Placeholder15) * 8) +
        (9   << uint8(MessageType.NotifyPool) * 8) +
        (250 << uint8(MessageType.NotifyShareClass) * 8) +
        (49  << uint8(MessageType.NotifyPricePoolPerShare) * 8) +
        (65  << uint8(MessageType.NotifyPricePoolPerAsset) * 8) +
        (185 << uint8(MessageType.NotifyShareMetadata) * 8) +
        (57  << uint8(MessageType.UpdateShareHook) * 8) +
        (91  << uint8(MessageType.InitiateTransferShares) * 8) +
        (73  << uint8(MessageType.ExecuteTransferShares) * 8) +
        (25  << uint8(MessageType.UpdateRestriction) * 8) +
        (57  << uint8(MessageType.UpdateContract) * 8) +
        (74  << uint8(MessageType.UpdateVault) * 8) +
        (42  << uint8(MessageType.UpdateBalanceSheetManager) * 8) +
        (91  << uint8(MessageType.UpdateHoldingAmount) * 8) +
        (59  << uint8(MessageType.UpdateShares) * 8) +
        (49  << uint8(MessageType.MaxAssetPriceAge) * 8) +
        (33  << uint8(MessageType.MaxSharePriceAge) * 8);

    // forgefmt: disable-next-item
    uint256 constant MESSAGE_LENGTHS_2 =
        (41  << (uint8(MessageType.Request) - 32) * 8) +
        (41  << (uint8(MessageType.RequestCallback) - 32) * 8) +
        (73  << (uint8(MessageType.SetRequestManager) - 32) * 8);

    function messageType(bytes memory message) internal pure returns (MessageType) {
        return MessageType(message.toUint8(0));
    }

    function messageCode(bytes memory message) internal pure returns (uint8) {
        return message.toUint8(0);
    }

    function messageLength(bytes memory message) internal pure returns (uint16 length) {
        uint8 kind = message.toUint8(0);
        require(kind <= uint8(type(MessageType).max), UnknownMessageType());

        length = (kind <= 31)
            ? uint16(uint8(bytes32(MESSAGE_LENGTHS_1)[31 - kind]))
            : uint16(uint8(bytes32(MESSAGE_LENGTHS_2)[63 - kind]));

        // Special treatment for messages with dynamic size:
        if (kind == uint8(MessageType.UpdateRestriction)) {
            length += 2 + message.toUint16(length); //payloadLength
        } else if (kind == uint8(MessageType.UpdateContract)) {
            length += 2 + message.toUint16(length); //payloadLength
        } else if (kind == uint8(MessageType.Request)) {
            length += 2 + message.toUint16(length); //payloadLength
        } else if (kind == uint8(MessageType.RequestCallback)) {
            length += 2 + message.toUint16(length); //payloadLength
        }
    }

    function messagePoolId(bytes memory message) internal pure returns (PoolId poolId) {
        uint8 kind = message.toUint8(0);

        // All messages from NotifyPool to the end contains a PoolId in position 1.
        if (kind >= uint8(MessageType.NotifyPool)) {
            return PoolId.wrap(message.toUint64(1));
        } else {
            return PoolId.wrap(0);
        }
    }

    function messageSourceCentrifugeId(bytes memory message) internal pure returns (uint16) {
        uint8 kind = message.toUint8(0);

        if (kind <= uint8(MessageType.RecoverTokens)) {
            return 0; // Non centrifugeId associated
        } else if (kind == uint8(MessageType.UpdateShares) || kind == uint8(MessageType.InitiateTransferShares)) {
            return 0; // Non centrifugeId associated
        } else if (kind == uint8(MessageType.RegisterAsset)) {
            return AssetId.wrap(message.toUint128(1)).centrifugeId();
        } else if (kind == uint8(MessageType.UpdateHoldingAmount)) {
            return AssetId.wrap(message.toUint128(25)).centrifugeId();
        } else if (kind == uint8(MessageType.Request)) {
            return AssetId.wrap(message.toUint128(25)).centrifugeId();
        } else {
            return message.messagePoolId().centrifugeId();
        }
    }

    //---------------------------------------
    //    ScheduleUpgrade
    //---------------------------------------

    struct ScheduleUpgrade {
        bytes32 target;
    }

    function deserializeScheduleUpgrade(bytes memory data) internal pure returns (ScheduleUpgrade memory) {
        require(messageType(data) == MessageType.ScheduleUpgrade, UnknownMessageType());
        return ScheduleUpgrade({target: data.toBytes32(1)});
    }

    function serialize(ScheduleUpgrade memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.ScheduleUpgrade, t.target);
    }

    //---------------------------------------
    //    CancelUpgrade
    //---------------------------------------

    struct CancelUpgrade {
        bytes32 target;
    }

    function deserializeCancelUpgrade(bytes memory data) internal pure returns (CancelUpgrade memory) {
        require(messageType(data) == MessageType.CancelUpgrade, UnknownMessageType());
        return CancelUpgrade({target: data.toBytes32(1)});
    }

    function serialize(CancelUpgrade memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.CancelUpgrade, t.target);
    }

    //---------------------------------------
    //    RecoverTokens
    //---------------------------------------

    struct RecoverTokens {
        bytes32 target;
        bytes32 token;
        uint256 tokenId;
        bytes32 to;
        uint256 amount;
    }

    function deserializeRecoverTokens(bytes memory data) internal pure returns (RecoverTokens memory) {
        require(messageType(data) == MessageType.RecoverTokens, UnknownMessageType());
        return RecoverTokens({
            target: data.toBytes32(1),
            token: data.toBytes32(33),
            tokenId: data.toUint256(65),
            to: data.toBytes32(97),
            amount: data.toUint256(129)
        });
    }

    function serialize(RecoverTokens memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.RecoverTokens, t.target, t.token, t.tokenId, t.to, t.amount);
    }

    //---------------------------------------
    //    RegisterAsset
    //---------------------------------------

    struct RegisterAsset {
        uint128 assetId;
        uint8 decimals;
    }

    function deserializeRegisterAsset(bytes memory data) internal pure returns (RegisterAsset memory) {
        require(messageType(data) == MessageType.RegisterAsset, UnknownMessageType());
        return RegisterAsset({assetId: data.toUint128(1), decimals: data.toUint8(17)});
    }

    function serialize(RegisterAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.RegisterAsset, t.assetId, t.decimals);
    }

    //---------------------------------------
    //    NotifyPool
    //---------------------------------------

    struct NotifyPool {
        uint64 poolId;
    }

    function deserializeNotifyPool(bytes memory data) internal pure returns (NotifyPool memory) {
        require(messageType(data) == MessageType.NotifyPool, UnknownMessageType());
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
        bytes32 salt;
        bytes32 hook;
    }

    function deserializeNotifyShareClass(bytes memory data) internal pure returns (NotifyShareClass memory) {
        require(messageType(data) == MessageType.NotifyShareClass, UnknownMessageType());
        return NotifyShareClass({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            name: data.slice(25, 128).bytes128ToString(),
            symbol: data.toBytes32(153),
            decimals: data.toUint8(185),
            salt: data.toBytes32(186),
            hook: data.toBytes32(218)
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
            t.salt,
            t.hook
        );
    }

    //---------------------------------------
    //    NotifyPricePoolPerShare
    //---------------------------------------

    struct NotifyPricePoolPerShare {
        uint64 poolId;
        bytes16 scId;
        uint128 price;
        uint64 timestamp;
    }

    function deserializeNotifyPricePoolPerShare(bytes memory data)
        internal
        pure
        returns (NotifyPricePoolPerShare memory)
    {
        require(messageType(data) == MessageType.NotifyPricePoolPerShare, UnknownMessageType());
        return NotifyPricePoolPerShare({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            price: data.toUint128(25),
            timestamp: data.toUint64(41)
        });
    }

    function serialize(NotifyPricePoolPerShare memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.NotifyPricePoolPerShare, t.poolId, t.scId, t.price, t.timestamp);
    }

    //---------------------------------------
    //    NotifyPricePoolPerAsset
    //---------------------------------------

    struct NotifyPricePoolPerAsset {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        uint128 price;
        uint64 timestamp;
    }

    function deserializeNotifyPricePoolPerAsset(bytes memory data)
        internal
        pure
        returns (NotifyPricePoolPerAsset memory)
    {
        require(messageType(data) == MessageType.NotifyPricePoolPerAsset, UnknownMessageType());
        return NotifyPricePoolPerAsset({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            price: data.toUint128(41),
            timestamp: data.toUint64(57)
        });
    }

    function serialize(NotifyPricePoolPerAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.NotifyPricePoolPerAsset, t.poolId, t.scId, t.assetId, t.price, t.timestamp);
    }

    //---------------------------------------
    //    NotifyShareMetadata
    //---------------------------------------

    struct NotifyShareMetadata {
        uint64 poolId;
        bytes16 scId;
        string name; // Fixed to 128 bytes
        bytes32 symbol; // utf8
    }

    function deserializeNotifyShareMetadata(bytes memory data) internal pure returns (NotifyShareMetadata memory) {
        require(messageType(data) == MessageType.NotifyShareMetadata, UnknownMessageType());
        return NotifyShareMetadata({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            name: data.slice(25, 128).bytes128ToString(),
            symbol: data.toBytes32(153)
        });
    }

    function serialize(NotifyShareMetadata memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.NotifyShareMetadata, t.poolId, t.scId, bytes(t.name).sliceZeroPadded(0, 128), t.symbol
        );
    }

    //---------------------------------------
    //    UpdateShareHook
    //---------------------------------------

    struct UpdateShareHook {
        uint64 poolId;
        bytes16 scId;
        bytes32 hook;
    }

    function deserializeUpdateShareHook(bytes memory data) internal pure returns (UpdateShareHook memory) {
        require(messageType(data) == MessageType.UpdateShareHook, UnknownMessageType());
        return UpdateShareHook({poolId: data.toUint64(1), scId: data.toBytes16(9), hook: data.toBytes32(25)});
    }

    function serialize(UpdateShareHook memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateShareHook, t.poolId, t.scId, t.hook);
    }

    //---------------------------------------
    //    InitiateTransferShares
    //---------------------------------------

    struct InitiateTransferShares {
        uint64 poolId;
        bytes16 scId;
        uint16 centrifugeId;
        bytes32 receiver;
        uint128 amount;
        uint128 extraGasLimit;
    }

    function deserializeInitiateTransferShares(bytes memory data)
        internal
        pure
        returns (InitiateTransferShares memory)
    {
        require(messageType(data) == MessageType.InitiateTransferShares, UnknownMessageType());
        return InitiateTransferShares({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            centrifugeId: data.toUint16(25),
            receiver: data.toBytes32(27),
            amount: data.toUint128(59),
            extraGasLimit: data.toUint128(75)
        });
    }

    function serialize(InitiateTransferShares memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.InitiateTransferShares, t.poolId, t.scId, t.centrifugeId, t.receiver, t.amount, t.extraGasLimit
        );
    }

    //---------------------------------------
    //    ExecuteTransferShares
    //---------------------------------------

    struct ExecuteTransferShares {
        uint64 poolId;
        bytes16 scId;
        bytes32 receiver;
        uint128 amount;
    }

    function deserializeExecuteTransferShares(bytes memory data) internal pure returns (ExecuteTransferShares memory) {
        require(messageType(data) == MessageType.ExecuteTransferShares, UnknownMessageType());
        return ExecuteTransferShares({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            receiver: data.toBytes32(25),
            amount: data.toUint128(57)
        });
    }

    function serialize(ExecuteTransferShares memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.ExecuteTransferShares, t.poolId, t.scId, t.receiver, t.amount);
    }

    //---------------------------------------
    //    UpdateRestriction
    //---------------------------------------

    struct UpdateRestriction {
        uint64 poolId;
        bytes16 scId;
        bytes payload; // As sequence of bytes
    }

    function deserializeUpdateRestriction(bytes memory data) internal pure returns (UpdateRestriction memory) {
        require(messageType(data) == MessageType.UpdateRestriction, UnknownMessageType());

        uint16 payloadLength = data.toUint16(25);
        return UpdateRestriction({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            payload: data.slice(27, payloadLength)
        });
    }

    function serialize(UpdateRestriction memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateRestriction, t.poolId, t.scId, uint16(t.payload.length), t.payload);
    }

    //---------------------------------------
    //    UpdateContract
    //---------------------------------------

    struct UpdateContract {
        uint64 poolId;
        bytes16 scId;
        bytes32 target;
        bytes payload; // As sequence of bytes
    }

    function deserializeUpdateContract(bytes memory data) internal pure returns (UpdateContract memory) {
        require(messageType(data) == MessageType.UpdateContract, UnknownMessageType());
        uint16 payloadLength = data.toUint16(57);
        return UpdateContract({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            target: data.toBytes32(25),
            payload: data.slice(59, payloadLength)
        });
    }

    function serialize(UpdateContract memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.UpdateContract, t.poolId, t.scId, t.target, uint16(t.payload.length), t.payload
        );
    }

    //---------------------------------------
    //    Request
    //---------------------------------------

    struct Request {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        bytes payload; // As sequence of bytes
    }

    function deserializeRequest(bytes memory data) internal pure returns (Request memory) {
        require(messageType(data) == MessageType.Request, UnknownMessageType());
        uint16 payloadLength = data.toUint16(41);
        return Request({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            payload: data.slice(43, payloadLength)
        });
    }

    function serialize(Request memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.Request, t.poolId, t.scId, t.assetId, uint16(t.payload.length), t.payload);
    }

    //---------------------------------------
    //    RequestCallback
    //---------------------------------------

    struct RequestCallback {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        bytes payload; // As sequence of bytes
    }

    function deserializeRequestCallback(bytes memory data) internal pure returns (RequestCallback memory) {
        require(messageType(data) == MessageType.RequestCallback, UnknownMessageType());
        uint16 payloadLength = data.toUint16(41);
        return RequestCallback({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            payload: data.slice(43, payloadLength)
        });
    }

    function serialize(RequestCallback memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.RequestCallback, t.poolId, t.scId, t.assetId, uint16(t.payload.length), t.payload
        );
    }

    //---------------------------------------
    //   VaultUpdate
    //---------------------------------------

    struct UpdateVault {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        bytes32 vaultOrFactory;
        uint8 kind;
    }

    function deserializeUpdateVault(bytes memory data) internal pure returns (UpdateVault memory) {
        require(messageType(data) == MessageType.UpdateVault, UnknownMessageType());
        return UpdateVault({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            vaultOrFactory: data.toBytes32(41),
            kind: data.toUint8(73)
        });
    }

    function serialize(UpdateVault memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateVault, t.poolId, t.scId, t.assetId, t.vaultOrFactory, t.kind);
    }

    //---------------------------------------
    //   SetRequestManager
    //---------------------------------------

    struct SetRequestManager {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        bytes32 manager;
    }

    function deserializeSetRequestManager(bytes memory data) internal pure returns (SetRequestManager memory) {
        require(messageType(data) == MessageType.SetRequestManager, UnknownMessageType());
        return SetRequestManager({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            manager: data.toBytes32(41)
        });
    }

    function serialize(SetRequestManager memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.SetRequestManager, t.poolId, t.scId, t.assetId, t.manager);
    }

    //---------------------------------------
    //   UpdateBalanceSheetManager
    //---------------------------------------

    struct UpdateBalanceSheetManager {
        uint64 poolId;
        bytes32 who;
        bool canManage;
    }

    function deserializeUpdateBalanceSheetManager(bytes memory data)
        internal
        pure
        returns (UpdateBalanceSheetManager memory)
    {
        require(messageType(data) == MessageType.UpdateBalanceSheetManager, UnknownMessageType());
        return UpdateBalanceSheetManager({poolId: data.toUint64(1), who: data.toBytes32(9), canManage: data.toBool(41)});
    }

    function serialize(UpdateBalanceSheetManager memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateBalanceSheetManager, t.poolId, t.who, t.canManage);
    }

    //---------------------------------------
    //    UpdateHoldingAmount
    //---------------------------------------

    struct UpdateHoldingAmount {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        uint128 amount;
        uint128 pricePerUnit;
        uint64 timestamp;
        bool isIncrease;
        bool isSnapshot;
        uint64 nonce;
    }

    function deserializeUpdateHoldingAmount(bytes memory data) internal pure returns (UpdateHoldingAmount memory h) {
        require(messageType(data) == MessageType.UpdateHoldingAmount, UnknownMessageType());

        return UpdateHoldingAmount({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            amount: data.toUint128(41),
            pricePerUnit: data.toUint128(57),
            timestamp: data.toUint64(73),
            isIncrease: data.toBool(81),
            isSnapshot: data.toBool(82),
            nonce: data.toUint64(83)
        });
    }

    function serialize(UpdateHoldingAmount memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.UpdateHoldingAmount,
            t.poolId,
            t.scId,
            t.assetId,
            t.amount,
            t.pricePerUnit,
            t.timestamp,
            t.isIncrease,
            t.isSnapshot,
            t.nonce
        );
    }

    //---------------------------------------
    //    UpdateShares
    //---------------------------------------

    struct UpdateShares {
        uint64 poolId;
        bytes16 scId;
        uint128 shares;
        uint64 timestamp;
        bool isIssuance;
        bool isSnapshot;
        uint64 nonce;
    }

    function deserializeUpdateShares(bytes memory data) internal pure returns (UpdateShares memory) {
        require(messageType(data) == MessageType.UpdateShares, UnknownMessageType());

        return UpdateShares({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            shares: data.toUint128(25),
            timestamp: data.toUint64(41),
            isIssuance: data.toBool(49),
            isSnapshot: data.toBool(50),
            nonce: data.toUint64(51)
        });
    }

    function serialize(UpdateShares memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.UpdateShares, t.poolId, t.scId, t.shares, t.timestamp, t.isIssuance, t.isSnapshot, t.nonce
        );
    }

    //---------------------------------------
    //   MaxAssetPriceAge
    //---------------------------------------

    struct MaxAssetPriceAge {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        uint64 maxPriceAge;
    }

    function deserializeMaxAssetPriceAge(bytes memory data) internal pure returns (MaxAssetPriceAge memory) {
        require(messageType(data) == MessageType.MaxAssetPriceAge, UnknownMessageType());
        return MaxAssetPriceAge({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            maxPriceAge: data.toUint64(41)
        });
    }

    function serialize(MaxAssetPriceAge memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.MaxAssetPriceAge, t.poolId, t.scId, t.assetId, t.maxPriceAge);
    }

    //---------------------------------------
    //   MaxSharePriceAge
    //---------------------------------------

    struct MaxSharePriceAge {
        uint64 poolId;
        bytes16 scId;
        uint64 maxPriceAge;
    }

    function deserializeMaxSharePriceAge(bytes memory data) internal pure returns (MaxSharePriceAge memory) {
        require(messageType(data) == MessageType.MaxSharePriceAge, UnknownMessageType());
        return MaxSharePriceAge({poolId: data.toUint64(1), scId: data.toBytes16(9), maxPriceAge: data.toUint64(25)});
    }

    function serialize(MaxSharePriceAge memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.MaxSharePriceAge, t.poolId, t.scId, t.maxPriceAge);
    }
}
