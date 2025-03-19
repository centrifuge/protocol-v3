// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {CastLib} from "src/misc/libraries/CastLib.sol";
import {BytesLib} from "src/misc/libraries/BytesLib.sol";
import {Auth} from "src/misc/Auth.sol";

import {MessageType, MessageLib} from "src/common/libraries/MessageLib.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";
import {IMessageSender} from "src/common/interfaces/IMessageSender.sol";
import {IPoolRouterGatewayHandler} from "src/common/interfaces/IGatewayHandlers.sol";
import {IPoolMessageSender} from "src/common/interfaces/IGatewaySenders.sol";

import {ShareClassId} from "src/pools/types/ShareClassId.sol";
import {AssetId} from "src/pools/types/AssetId.sol";
import {PoolId} from "src/pools/types/PoolId.sol";

contract MessageProcessor is Auth, IPoolMessageSender, IMessageHandler {
    using MessageLib for *;
    using BytesLib for bytes;
    using CastLib for *;

    IPoolRouterGatewayHandler public immutable poolRouter;
    IMessageSender public immutable gateway;

    constructor(IMessageSender sender_, IPoolRouterGatewayHandler manager_, address deployer) Auth(deployer) {
        gateway = sender_;
        poolRouter = manager_;
    }

    /// @inheritdoc IPoolMessageSender
    function sendNotifyPool(uint32 chainId, PoolId poolId) external auth {
        // In case we want to optimize for the same network:
        //if chainId == uint32(block.chainId) {
        //    cv.poolManager.notifyPool(poolId);
        //}
        //else {
        gateway.send(chainId, MessageLib.NotifyPool({poolId: poolId.raw()}).serialize());
        //}
    }

    /// @inheritdoc IPoolMessageSender
    function sendNotifyShareClass(
        uint32 chainId,
        PoolId poolId,
        ShareClassId scId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        bytes32 salt,
        bytes32 hook
    ) external auth {
        gateway.send(
            chainId,
            MessageLib.NotifyShareClass({
                poolId: poolId.raw(),
                scId: scId.raw(),
                name: name,
                symbol: symbol.toBytes32(),
                decimals: decimals,
                salt: salt,
                hook: hook
            }).serialize()
        );
    }

    /// @inheritdoc IPoolMessageSender
    function sendFulfilledDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 assetAmount,
        uint128 shareAmount
    ) external auth {
        gateway.send(
            assetId.chainId(),
            MessageLib.FulfilledDepositRequest({
                poolId: poolId.raw(),
                scId: scId.raw(),
                investor: investor,
                assetId: assetId.raw(),
                assetAmount: assetAmount,
                shareAmount: shareAmount
            }).serialize()
        );
    }

    /// @inheritdoc IPoolMessageSender
    function sendFulfilledRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 assetAmount,
        uint128 shareAmount
    ) external auth {
        gateway.send(
            assetId.chainId(),
            MessageLib.FulfilledRedeemRequest({
                poolId: poolId.raw(),
                scId: scId.raw(),
                investor: investor,
                assetId: assetId.raw(),
                assetAmount: assetAmount,
                shareAmount: shareAmount
            }).serialize()
        );
    }

    /// @inheritdoc IPoolMessageSender
    function sendFulfilledCancelDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 cancelledAmount
    ) external auth {
        gateway.send(
            assetId.chainId(),
            MessageLib.FulfilledCancelDepositRequest({
                poolId: poolId.raw(),
                scId: scId.raw(),
                investor: investor,
                assetId: assetId.raw(),
                cancelledAmount: cancelledAmount
            }).serialize()
        );
    }

    /// @inheritdoc IPoolMessageSender
    function sendFulfilledCancelRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 cancelledShares
    ) external auth {
        gateway.send(
            assetId.chainId(),
            MessageLib.FulfilledCancelRedeemRequest({
                poolId: poolId.raw(),
                scId: scId.raw(),
                investor: investor,
                assetId: assetId.raw(),
                cancelledShares: cancelledShares
            }).serialize()
        );
    }

    /// @inheritdoc IMessageHandler
    function handle(uint32, /* chainId */ bytes memory message) external auth {
        MessageType kind = message.messageType();

        if (kind == MessageType.RegisterAsset) {
            MessageLib.RegisterAsset memory m = message.deserializeRegisterAsset();
            poolRouter.registerAsset(AssetId.wrap(m.assetId), m.name, m.symbol.toString(), m.decimals);
        } else if (kind == MessageType.DepositRequest) {
            MessageLib.DepositRequest memory m = message.deserializeDepositRequest();
            poolRouter.depositRequest(
                PoolId.wrap(m.poolId), ShareClassId.wrap(m.scId), m.investor, AssetId.wrap(m.assetId), m.amount
            );
        } else if (kind == MessageType.RedeemRequest) {
            MessageLib.RedeemRequest memory m = message.deserializeRedeemRequest();
            poolRouter.redeemRequest(
                PoolId.wrap(m.poolId), ShareClassId.wrap(m.scId), m.investor, AssetId.wrap(m.assetId), m.amount
            );
        } else if (kind == MessageType.CancelDepositRequest) {
            MessageLib.CancelDepositRequest memory m = message.deserializeCancelDepositRequest();
            poolRouter.cancelDepositRequest(
                PoolId.wrap(m.poolId), ShareClassId.wrap(m.scId), m.investor, AssetId.wrap(m.assetId)
            );
        } else if (kind == MessageType.CancelRedeemRequest) {
            MessageLib.CancelRedeemRequest memory m = message.deserializeCancelRedeemRequest();
            poolRouter.cancelRedeemRequest(
                PoolId.wrap(m.poolId), ShareClassId.wrap(m.scId), m.investor, AssetId.wrap(m.assetId)
            );
        } else {
            revert InvalidMessage(uint8(kind));
        }
    }
}
