// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {BytesLib} from "src/misc/libraries/BytesLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {D18, d18} from "src/misc/types/D18.sol";

import {JournalEntry, JournalEntryLib} from "src/common/types/JournalEntry.sol";

enum MessageType {
    /// @dev Placeholder for null message type
    Invalid,
    // -- Gateway messages 1 - 3
    MessageProof,
    InitiateMessageRecovery,
    DisputeMessageRecovery,
    // -- Root messages 4 - 6
    ScheduleUpgrade,
    CancelUpgrade,
    RecoverTokens,
    // -- Gas messages 7
    UpdateGasPrice,
    // -- Pool manager messages 8 - 18
    RegisterAsset,
    NotifyPool,
    NotifyShareClass,
    AllowAsset,
    DisallowAsset,
    UpdateShareClassPrice,
    UpdateShareClassMetadata,
    UpdateShareClassHook,
    TransferShares,
    UpdateRestriction,
    UpdateContract,
    // -- Investment manager messages 19 - 27
    DepositRequest,
    RedeemRequest,
    FulfilledDepositRequest,
    FulfilledRedeemRequest,
    CancelDepositRequest,
    CancelRedeemRequest,
    FulfilledCancelDepositRequest,
    FulfilledCancelRedeemRequest,
    TriggerRedeemRequest,
    // -- BalanceSheetManager messages 28 - 30
    UpdateHolding,
    UpdateShares,
    UpdateJournal
}

enum UpdateRestrictionType {
    /// @dev Placeholder for null update restriction type
    Invalid,
    Member,
    Freeze,
    Unfreeze
}

enum UpdateContractType {
    /// @dev Placeholder for null update restriction type
    Invalid,
    VaultUpdate,
    Permission
}

enum MessageCategory {
    Invalid,
    Gateway,
    Root,
    Gas,
    Pool,
    Investment,
    BalanceSheet,
    Other
}

library MessageLib {
    using MessageLib for bytes;
    using BytesLib for bytes;
    using JournalEntryLib for bytes;
    using CastLib for *;
    using JournalEntryLib for JournalEntry[];

    error UnknownMessageType();

    /// @dev Encode all message lengths in this constant to avoid a large list of if/elseif checks
    /// and reduce generated bytecode
    // forgefmt: disable-next-item
    uint256 constant MESSAGE_LENGTHS =
        (33 << uint8(MessageType.MessageProof) * 8) +
        (65 << uint8(MessageType.InitiateMessageRecovery) * 8) +
        (65 << uint8(MessageType.DisputeMessageRecovery) * 8) +
        (33 << uint8(MessageType.ScheduleUpgrade) * 8) +
        (33 << uint8(MessageType.CancelUpgrade) * 8) +
        (129 << uint8(MessageType.RecoverTokens) * 8) +
        (25 << uint8(MessageType.UpdateGasPrice) * 8) +
        (37 << uint8(MessageType.RegisterAsset) * 8) + //TODO: modify to 178 when registerAsset feature is merged
        (9 << uint8(MessageType.NotifyPool) * 8) +
        (250 << uint8(MessageType.NotifyShareClass) * 8) +
        (41 << uint8(MessageType.AllowAsset) * 8) +
        (41 << uint8(MessageType.DisallowAsset) * 8) +
        (65 << uint8(MessageType.UpdateShareClassPrice) * 8) +
        (185 << uint8(MessageType.UpdateShareClassMetadata) * 8) +
        (57 << uint8(MessageType.UpdateShareClassHook) * 8) +
        (73 << uint8(MessageType.TransferShares) * 8) +
        (27 << uint8(MessageType.UpdateRestriction) * 8) +
        (59 << uint8(MessageType.UpdateContract) * 8) +
        (89 << uint8(MessageType.DepositRequest) * 8) +
        (89 << uint8(MessageType.RedeemRequest) * 8) +
        (105 << uint8(MessageType.FulfilledDepositRequest) * 8) +
        (105 << uint8(MessageType.FulfilledRedeemRequest) * 8) +
        (73 << uint8(MessageType.CancelDepositRequest) * 8) +
        (73 << uint8(MessageType.CancelRedeemRequest) * 8) +
        (89 << uint8(MessageType.FulfilledCancelDepositRequest) * 8) +
        (89 << uint8(MessageType.FulfilledCancelRedeemRequest) * 8) +
        (89 << uint8(MessageType.TriggerRedeemRequest) * 8) +
        (143 << uint8(MessageType.UpdateHolding) * 8) +
        (81 << uint8(MessageType.UpdateShares) * 8) +
        (29 << uint8(MessageType.UpdateJournal) * 8);

    function messageType(bytes memory message) internal pure returns (MessageType) {
        return MessageType(message.toUint8(0));
    }

    function messageCode(bytes memory message) internal pure returns (uint8) {
        return message.toUint8(0);
    }

    function messageLength(bytes memory message) internal pure returns (uint16 length) {
        uint8 kind = message.toUint8(0);
        require(kind <= uint8(type(MessageType).max), UnknownMessageType());

        length = uint16(uint8(bytes32(MESSAGE_LENGTHS)[31 - kind]));

        if (kind == uint8(MessageType.UpdateRestriction)) {
            length += message.toUint16(length - 2); //payloadLength
        } else if (kind == uint8(MessageType.UpdateContract)) {
            length += message.toUint16(length - 2); //payloadLength
        } else if (kind == uint8(MessageType.UpdateHolding)) {
            length += message.toUint16(length - 2); // credits length
            length += message.toUint16(length - 4); //debits length
        }
    }

    function category(uint8 code) internal pure returns (MessageCategory) {
        if (code == 0) {
            return MessageCategory.Invalid;
        } else if (code >= 1 && code <= 3) {
            return MessageCategory.Gateway;
        } else if (code >= 4 && code <= 6) {
            return MessageCategory.Root;
        } else if (code == 7) {
            return MessageCategory.Gas;
        } else if (code >= 8 && code <= 18) {
            return MessageCategory.Pool;
        } else if (code >= 19 && code <= 27) {
            return MessageCategory.Investment;
        } else if (code >= 28 && code <= 33) {
            return MessageCategory.BalanceSheet;
        } else {
            return MessageCategory.Other;
        }
    }

    function updateRestrictionType(bytes memory message) internal pure returns (UpdateRestrictionType) {
        return UpdateRestrictionType(message.toUint8(0));
    }

    function updateContractType(bytes memory message) internal pure returns (UpdateContractType) {
        return UpdateContractType(message.toUint8(0));
    }

    //---------------------------------------
    //    MessageProof
    //---------------------------------------

    struct MessageProof {
        bytes32 hash;
    }

    function deserializeMessageProof(bytes memory data) internal pure returns (MessageProof memory) {
        require(messageType(data) == MessageType.MessageProof, UnknownMessageType());
        return MessageProof({hash: data.toBytes32(1)});
    }

    function serialize(MessageProof memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.MessageProof, t.hash);
    }

    //---------------------------------------
    //    InitiateMessageRecovery
    //---------------------------------------

    struct InitiateMessageRecovery {
        bytes32 hash;
        bytes32 adapter;
    }

    function deserializeInitiateMessageRecovery(bytes memory data)
        internal
        pure
        returns (InitiateMessageRecovery memory)
    {
        require(messageType(data) == MessageType.InitiateMessageRecovery, UnknownMessageType());
        return InitiateMessageRecovery({hash: data.toBytes32(1), adapter: data.toBytes32(33)});
    }

    function serialize(InitiateMessageRecovery memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.InitiateMessageRecovery, t.hash, t.adapter);
    }

    //---------------------------------------
    //    DisputeMessageRecovery
    //---------------------------------------

    struct DisputeMessageRecovery {
        bytes32 hash;
        bytes32 adapter;
    }

    function deserializeDisputeMessageRecovery(bytes memory data)
        internal
        pure
        returns (DisputeMessageRecovery memory)
    {
        require(messageType(data) == MessageType.DisputeMessageRecovery, UnknownMessageType());
        return DisputeMessageRecovery({hash: data.toBytes32(1), adapter: data.toBytes32(33)});
    }

    function serialize(DisputeMessageRecovery memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.DisputeMessageRecovery, t.hash, t.adapter);
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
        bytes32 to;
        uint256 amount;
    }

    function deserializeRecoverTokens(bytes memory data) internal pure returns (RecoverTokens memory) {
        require(messageType(data) == MessageType.RecoverTokens, UnknownMessageType());
        return RecoverTokens({
            target: data.toBytes32(1),
            token: data.toBytes32(33),
            to: data.toBytes32(65),
            amount: data.toUint256(97)
        });
    }

    function serialize(RecoverTokens memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.RecoverTokens, t.target, t.token, t.to, t.amount);
    }

    //---------------------------------------
    //    UpdateGasPrice
    //---------------------------------------

    struct UpdateGasPrice {
        uint128 price;
        uint64 timestamp;
    }

    function deserializeUpdateGasPrice(bytes memory data) internal pure returns (UpdateGasPrice memory) {
        require(messageType(data) == MessageType.UpdateGasPrice, UnknownMessageType());
        return UpdateGasPrice({price: data.toUint128(1), timestamp: data.toUint64(17)});
    }

    function serialize(UpdateGasPrice memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateGasPrice, t.price, t.timestamp);
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
        require(messageType(data) == MessageType.RegisterAsset, UnknownMessageType());
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
    //    AllowAsset
    //---------------------------------------

    struct AllowAsset {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
    }

    function deserializeAllowAsset(bytes memory data) internal pure returns (AllowAsset memory) {
        require(messageType(data) == MessageType.AllowAsset, UnknownMessageType());
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
        require(messageType(data) == MessageType.DisallowAsset, UnknownMessageType());
        return DisallowAsset({poolId: data.toUint64(1), scId: data.toBytes16(9), assetId: data.toUint128(25)});
    }

    function serialize(DisallowAsset memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.DisallowAsset, t.poolId, t.scId, t.assetId);
    }

    //---------------------------------------
    //    UpdateShareClassPrice
    //---------------------------------------

    struct UpdateShareClassPrice {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        uint128 price;
        uint64 timestamp;
    }

    function deserializeUpdateShareClassPrice(bytes memory data) internal pure returns (UpdateShareClassPrice memory) {
        require(messageType(data) == MessageType.UpdateShareClassPrice, UnknownMessageType());
        return UpdateShareClassPrice({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            assetId: data.toUint128(25),
            price: data.toUint128(41),
            timestamp: data.toUint64(57)
        });
    }

    function serialize(UpdateShareClassPrice memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateShareClassPrice, t.poolId, t.scId, t.assetId, t.price, t.timestamp);
    }

    //---------------------------------------
    //    UpdateShareClassMetadata
    //---------------------------------------

    struct UpdateShareClassMetadata {
        uint64 poolId;
        bytes16 scId;
        string name; // Fixed to 128 bytes
        bytes32 symbol; // utf8
    }

    function deserializeUpdateShareClassMetadata(bytes memory data)
        internal
        pure
        returns (UpdateShareClassMetadata memory)
    {
        require(messageType(data) == MessageType.UpdateShareClassMetadata, UnknownMessageType());
        return UpdateShareClassMetadata({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            name: data.slice(25, 128).bytes128ToString(),
            symbol: data.toBytes32(153)
        });
    }

    function serialize(UpdateShareClassMetadata memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.UpdateShareClassMetadata, t.poolId, t.scId, bytes(t.name).sliceZeroPadded(0, 128), t.symbol
        );
    }

    //---------------------------------------
    //    UpdateShareClassHook
    //---------------------------------------

    struct UpdateShareClassHook {
        uint64 poolId;
        bytes16 scId;
        bytes32 hook;
    }

    function deserializeUpdateShareClassHook(bytes memory data) internal pure returns (UpdateShareClassHook memory) {
        require(messageType(data) == MessageType.UpdateShareClassHook, UnknownMessageType());
        return UpdateShareClassHook({poolId: data.toUint64(1), scId: data.toBytes16(9), hook: data.toBytes32(25)});
    }

    function serialize(UpdateShareClassHook memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateShareClassHook, t.poolId, t.scId, t.hook);
    }

    //---------------------------------------
    //    TransferShares
    //---------------------------------------

    struct TransferShares {
        uint64 poolId;
        bytes16 scId;
        bytes32 recipient;
        uint128 amount;
    }

    function deserializeTransferShares(bytes memory data) internal pure returns (TransferShares memory) {
        require(messageType(data) == MessageType.TransferShares, UnknownMessageType());
        return TransferShares({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            recipient: data.toBytes32(25),
            amount: data.toUint128(57)
        });
    }

    function serialize(TransferShares memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.TransferShares, t.poolId, t.scId, t.recipient, t.amount);
    }

    //---------------------------------------
    //    UpdateRestriction
    //---------------------------------------

    struct UpdateRestriction {
        uint64 poolId;
        bytes16 scId;
        bytes payload;
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
    //    UpdateRestrictionMember (submsg)
    //---------------------------------------

    struct UpdateRestrictionMember {
        bytes32 user;
        uint64 validUntil;
    }

    function deserializeUpdateRestrictionMember(bytes memory data)
        internal
        pure
        returns (UpdateRestrictionMember memory)
    {
        require(updateRestrictionType(data) == UpdateRestrictionType.Member, UnknownMessageType());

        return UpdateRestrictionMember({user: data.toBytes32(1), validUntil: data.toUint64(33)});
    }

    function serialize(UpdateRestrictionMember memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(UpdateRestrictionType.Member, t.user, t.validUntil);
    }

    //---------------------------------------
    //    UpdateRestrictionFreeze (submsg)
    //---------------------------------------

    struct UpdateRestrictionFreeze {
        bytes32 user;
    }

    function deserializeUpdateRestrictionFreeze(bytes memory data)
        internal
        pure
        returns (UpdateRestrictionFreeze memory)
    {
        require(updateRestrictionType(data) == UpdateRestrictionType.Freeze, UnknownMessageType());

        return UpdateRestrictionFreeze({user: data.toBytes32(1)});
    }

    function serialize(UpdateRestrictionFreeze memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(UpdateRestrictionType.Freeze, t.user);
    }

    //---------------------------------------
    //    UpdateRestrictionUnfreeze (submsg)
    //---------------------------------------

    struct UpdateRestrictionUnfreeze {
        bytes32 user;
    }

    function deserializeUpdateRestrictionUnfreeze(bytes memory data)
        internal
        pure
        returns (UpdateRestrictionUnfreeze memory)
    {
        require(updateRestrictionType(data) == UpdateRestrictionType.Unfreeze, UnknownMessageType());

        return UpdateRestrictionUnfreeze({user: data.toBytes32(1)});
    }

    function serialize(UpdateRestrictionUnfreeze memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(UpdateRestrictionType.Unfreeze, t.user);
    }

    //---------------------------------------
    //    UpdateContract
    //---------------------------------------

    struct UpdateContract {
        uint64 poolId;
        bytes16 scId;
        bytes32 target;
        bytes payload;
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
    //   UpdateContract.VaultUpdate (submsg)
    //---------------------------------------

    struct UpdateContractVaultUpdate {
        address factory;
        uint128 assetId;
        bool isLinked;
        address vault;
    }

    function deserializeUpdateContractVaultUpdate(bytes memory data)
        internal
        pure
        returns (UpdateContractVaultUpdate memory)
    {
        require(updateContractType(data) == UpdateContractType.VaultUpdate, UnknownMessageType());

        return UpdateContractVaultUpdate({
            factory: data.toAddress(1),
            assetId: data.toUint128(21),
            isLinked: data.toBool(37),
            vault: data.toAddress(38)
        });
    }

    function serialize(UpdateContractVaultUpdate memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(UpdateContractType.VaultUpdate, t.factory, t.assetId, t.isLinked, t.vault);
    }

    //---------------------------------------
    //   UpdateContract.Permission (submsg)
    //---------------------------------------

    struct UpdateContractPermission {
        address who;
        bool allowed;
    }

    function deserializeUpdateContractPermission(bytes memory data)
        internal
        pure
        returns (UpdateContractPermission memory)
    {
        require(updateContractType(data) == UpdateContractType.Permission, UnknownMessageType());

        return UpdateContractPermission({who: data.toAddress(1), allowed: data.toBool(21)});
    }

    function serialize(UpdateContractPermission memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(UpdateContractType.Permission, t.who, t.allowed);
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
        require(messageType(data) == MessageType.DepositRequest, UnknownMessageType());
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
        require(messageType(data) == MessageType.RedeemRequest, UnknownMessageType());
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
        require(messageType(data) == MessageType.CancelDepositRequest, UnknownMessageType());
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
        require(messageType(data) == MessageType.CancelRedeemRequest, UnknownMessageType());
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
        uint128 assetAmount;
        uint128 shareAmount;
    }

    function deserializeFulfilledDepositRequest(bytes memory data)
        internal
        pure
        returns (FulfilledDepositRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledDepositRequest, UnknownMessageType());
        return FulfilledDepositRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            assetAmount: data.toUint128(73),
            shareAmount: data.toUint128(89)
        });
    }

    function serialize(FulfilledDepositRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledDepositRequest, t.poolId, t.scId, t.investor, t.assetId, t.assetAmount, t.shareAmount
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
        uint128 assetAmount;
        uint128 shareAmount;
    }

    function deserializeFulfilledRedeemRequest(bytes memory data)
        internal
        pure
        returns (FulfilledRedeemRequest memory)
    {
        require(messageType(data) == MessageType.FulfilledRedeemRequest, UnknownMessageType());
        return FulfilledRedeemRequest({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            investor: data.toBytes32(25),
            assetId: data.toUint128(57),
            assetAmount: data.toUint128(73),
            shareAmount: data.toUint128(89)
        });
    }

    function serialize(FulfilledRedeemRequest memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(
            MessageType.FulfilledRedeemRequest, t.poolId, t.scId, t.investor, t.assetId, t.assetAmount, t.shareAmount
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
        require(messageType(data) == MessageType.FulfilledCancelDepositRequest, UnknownMessageType());
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
        require(messageType(data) == MessageType.FulfilledCancelRedeemRequest, UnknownMessageType());
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
        require(messageType(data) == MessageType.TriggerRedeemRequest, UnknownMessageType());
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

    //---------------------------------------
    //    UpdateHolding
    //---------------------------------------

    struct UpdateHolding {
        uint64 poolId;
        bytes16 scId;
        uint128 assetId;
        bytes32 who;
        uint128 amount;
        D18 pricePerUnit;
        uint256 timestamp;
        bool isIncrease; // Signals whether this is an increase or a decrease
        bool asAllowance; // Signals whether the amount is transferred or allowed to who on the BSM
        JournalEntry[] debits;
        JournalEntry[] credits;
    }

    function deserializeUpdateHolding(bytes memory data) internal pure returns (UpdateHolding memory h) {
        require(messageType(data) == MessageType.UpdateHolding, "UnknownMessageType");

        uint16 debitsByteLen = data.toUint16(139);
        uint16 creditsByteLen = data.toUint16(141);

        uint256 offset = 143;
        h.debits = data.toJournalEntries(offset, debitsByteLen);
        offset += debitsByteLen;
        h.credits = data.toJournalEntries(offset, creditsByteLen);

        // Now assign each field one at a time
        h.poolId = data.toUint64(1);
        h.scId = data.toBytes16(9);
        h.assetId = data.toUint128(25);
        h.who = data.toBytes32(41);
        h.amount = data.toUint128(73);
        h.pricePerUnit = D18.wrap(data.toUint128(89));
        h.timestamp = data.toUint256(105);
        h.isIncrease = data.toBool(137);
        h.asAllowance = data.toBool(138);

        return h;
    }

    function serialize(UpdateHolding memory t) internal pure returns (bytes memory) {
        bytes memory debits = t.debits.encodePacked();
        bytes memory credits = t.credits.encodePacked();

        bytes memory partial1 = abi.encodePacked(MessageType.UpdateHolding, t.poolId, t.scId, t.assetId, t.who);
        bytes memory partial2 =
            abi.encodePacked(partial1, t.amount, t.pricePerUnit, t.timestamp, t.isIncrease, t.asAllowance);
        bytes memory partial3 = abi.encodePacked(partial2, uint16(debits.length), uint16(credits.length));

        return abi.encodePacked(partial3, debits, credits);
    }

    //---------------------------------------
    //    UpdateShares
    //---------------------------------------

    struct UpdateShares {
        uint64 poolId;
        bytes16 scId;
        bytes32 who;
        uint128 shares;
        uint256 timestamp;
        bool isIssuance;
    }

    function deserializeUpdateShares(bytes memory data) internal pure returns (UpdateShares memory) {
        require(messageType(data) == MessageType.UpdateShares, UnknownMessageType());

        return UpdateShares({
            poolId: data.toUint64(1),
            scId: data.toBytes16(9),
            who: data.toBytes32(25),
            shares: data.toUint128(57),
            timestamp: data.toUint256(73),
            isIssuance: data.toBool(105)
        });
    }

    function serialize(UpdateShares memory t) internal pure returns (bytes memory) {
        return abi.encodePacked(MessageType.UpdateShares, t.poolId, t.scId, t.who, t.shares, t.timestamp, t.isIssuance);
    }

    //---------------------------------------
    //    UpdateJournal
    //---------------------------------------

    struct UpdateJournal {
        uint64 poolId;
        bytes16 scId;
        JournalEntry[] debits;
        JournalEntry[] credits;
    }

    function deserializeUpdateJournal(bytes memory data) internal pure returns (UpdateJournal memory) {
        require(messageType(data) == MessageType.UpdateJournal, UnknownMessageType());

        uint16 debitsLength = data.toUint16(25);
        uint16 creditsLength = data.toUint16(27);
        uint256 offset = 29;
        JournalEntry[] memory debits = data.toJournalEntries(offset, debitsLength);
        offset += debitsLength;
        JournalEntry[] memory credits = data.toJournalEntries(offset, creditsLength);

        return UpdateJournal({poolId: data.toUint64(1), scId: data.toBytes16(9), debits: debits, credits: credits});
    }

    function serialize(UpdateJournal memory t) internal pure returns (bytes memory) {
        bytes memory debits = t.debits.encodePacked();
        bytes memory credits = t.credits.encodePacked();

        return abi.encodePacked(
            MessageType.UpdateJournal, t.poolId, t.scId, uint16(debits.length), uint16(credits.length), debits, credits
        );
    }
}
