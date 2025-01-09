// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ItemId} from "src/types/ItemId.sol";
import {PoolId} from "src/types/PoolId.sol";
import {AssetId} from "src/types/AssetId.sol";
import {ShareClassId} from "src/types/ShareClassId.sol";
import {IItemManager} from "src/interfaces/IItemManager.sol";

interface IHoldings is IItemManager {
    /// @notice Emitted when a call to `file()` was performed.
    event File(bytes32 what, address addr);

    /// @notice Dispatched when the `what` parameter of `file()` is not supported by the implementation.
    error FileUnrecognizedWhat();

    /// @notice AssetId is not valid.
    error WrongAssetId();

    /// @notice ShareClassId is not valid.
    error WrongShareClassId();

    /// @notice Updates a contract parameter.
    /// @param what Name of the parameter to update.
    /// Accepts a `bytes32` representation of 'poolRegistry' string value.
    /// @param data New value given to the `what` parameter
    function file(bytes32 what, address data) external;

    /// @notice Returns the itemId for an specific asset in a share class
    function itemIdFromAsset(PoolId poolId, ShareClassId scId, AssetId assetId) external view returns (ItemId);

    /// @notice Returns the share class and asset of a specific item
    function itemIdToAsset(PoolId poolId, ItemId itemId) external view returns (ShareClassId scId, AssetId assetId);
}
