// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ShareClassId} from "src/types/ShareClassId.sol";
import {AssetId} from "src/types/AssetId.sol";
import {PoolId} from "src/types/PoolId.sol";

// TODO: WIP
interface IGateway {
    // NOTE: Should the implementation store a mapping by chainId to track...?
    // - allowed pools
    // - allowed share classes
    // - allowed assets
    // That mapping would act as a whitelist for the Gateway to discard messages that contains not allowed
    // pools/shareClasses
    function sendNotifyPool(uint32 chainId, PoolId poolId) external;
    function sendNotifyShareClass(
        uint32 chainId,
        PoolId poolId,
        ShareClassId scId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        bytes32 hook
    ) external;
    function sendNotifyAllowedAsset(PoolId poolId, ShareClassId scId, AssetId assetId, bool isAllowed) external;
    function sendFulfilledDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 shares,
        uint128 investedAmount
    ) external;
    function sendFulfilledRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 shares,
        uint128 investedAmount
    ) external;
    function sendFulfilledCancelDepositRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 canceledAmount,
        uint128 fulfilledInvestedAmount
    ) external;
    function sendFulfilledCancelRedeemRequest(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 investor,
        uint128 canceledShares,
        uint128 fulfilledInvestedAmount
    ) external;
    function sendUnlockAssets(AssetId assetId, bytes32 receiver, uint128 assetAmount) external;
    function handleMessage(bytes calldata message) external;
}
