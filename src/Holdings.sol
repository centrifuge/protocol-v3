// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PoolId} from "src/types/PoolId.sol";
import {ItemId, AccountId, AssetId, ShareClassId} from "src/types/Domain.sol";

import {IERC20Metadata} from "src/interfaces/IERC20Metadata.sol";
import {IItemManager} from "src/interfaces/IItemManager.sol";
import {IHoldings} from "src/interfaces/IHoldings.sol";
import {IPoolRegistry} from "src/interfaces/IPoolRegistry.sol";
import {IERC7726} from "src/interfaces/IERC7726.sol";

import {MathLib} from "src/libraries/MathLib.sol";

import {AccountingItemManager} from "src/AccountingItemManager.sol";
import {Auth} from "src/Auth.sol";

struct Item {
    ShareClassId scId;
    AssetId assetId;
    IERC7726 valuation;
    uint128 assetAmount;
    uint128 assetAmountValue;
}

contract Holdings is AccountingItemManager, IHoldings {
    using MathLib for uint256;

    mapping(PoolId => mapping(ItemId => Item)) public item;
    mapping(PoolId => mapping(ShareClassId => mapping(AssetId => ItemId))) public itemId;
    mapping(PoolId => uint32) lastItemId;

    IPoolRegistry immutable poolRegistry;

    constructor(address deployer, IPoolRegistry poolRegistry_) AccountingItemManager(deployer) {
        poolRegistry = poolRegistry_;
        // TODO: should we initialize the accounts from AccountingItemManager here?
    }

    /// @inheritdoc IItemManager
    function create(PoolId poolId, IERC7726 valuation_, bytes calldata data) external auth {
        (ShareClassId scId, AssetId assetId) = abi.decode(data, (ShareClassId, AssetId));

        ItemId itemId_ = ItemId.wrap(++lastItemId[poolId]);
        itemId[poolId][scId][assetId] = itemId_;
        item[poolId][itemId_] = Item(scId, assetId, valuation_, 0, 0);
    }

    /// @inheritdoc IItemManager
    function close(PoolId poolId, ItemId itemId_, bytes calldata /*data*/ ) external auth {
        Item storage item_ = item[poolId][itemId_];
        itemId[poolId][item_.scId][item_.assetId] = ItemId.wrap(0);
        delete item[poolId][itemId_];
    }

    /// @inheritdoc IItemManager
    function increase(PoolId poolId, ItemId itemId_, uint128 amount) external auth returns (uint128 amountValue) {
        Item storage item_ = item[poolId][itemId_];
        address poolCurrency = address(poolRegistry.currency(poolId));

        amountValue = uint128(item_.valuation.getQuote(amount, AssetId.unwrap(item_.assetId), poolCurrency));

        item_.assetAmount += amount;
        item_.assetAmountValue += amountValue;
    }

    /// @inheritdoc IItemManager
    function decrease(PoolId poolId, ItemId itemId_, uint128 amount) external auth returns (uint128 amountValue) {
        Item storage item_ = item[poolId][itemId_];
        address poolCurrency = address(poolRegistry.currency(poolId));

        amountValue = uint128(item_.valuation.getQuote(amount, AssetId.unwrap(item_.assetId), poolCurrency));

        item_.assetAmount -= amount;
        item_.assetAmountValue -= amountValue;
    }

    /// @inheritdoc IItemManager
    function update(PoolId poolId, ItemId itemId_) external auth returns (int128 diff) {
        Item storage item_ = item[poolId][itemId_];

        address poolCurrency = address(poolRegistry.currency(poolId));

        uint128 currentAmountValue =
            uint128(item_.valuation.getQuote(item_.assetAmount, AssetId.unwrap(item_.assetId), poolCurrency));

        diff = currentAmountValue > item_.assetAmountValue
            ? uint256(currentAmountValue - item_.assetAmountValue).toInt128()
            : -uint256(item_.assetAmountValue - currentAmountValue).toInt128();

        item_.assetAmountValue = currentAmountValue;
    }

    /// @inheritdoc IItemManager
    function decreaseInterest(PoolId, /*poolId*/ ItemId, /*itemId_*/ uint128 /*amount*/ ) external pure {
        revert("unsupported");
    }

    function increaseInterest(PoolId, /*poolId*/ ItemId, /*itemId_*/ uint128 /*amount*/ ) external pure {
        revert("unsupported");
    }

    /// @inheritdoc IItemManager
    function itemValue(PoolId poolId, ItemId itemId_) external view returns (uint128 value) {
        return item[poolId][itemId_].assetAmountValue;
    }

    /// @inheritdoc IItemManager
    function valuation(PoolId poolId, ItemId itemId_) external view returns (IERC7726) {
        return item[poolId][itemId_].valuation;
    }

    /// @inheritdoc IItemManager
    function updateValuation(PoolId poolId, ItemId itemId_, IERC7726 valuation_) external auth {
        item[poolId][itemId_].valuation = valuation_;
    }

    /// @inheritdoc IHoldings
    function itemIdFromAsset(PoolId poolId, ShareClassId scId, AssetId assetId) external view returns (ItemId) {
        return itemId[poolId][scId][assetId];
    }

    /// @inheritdoc IHoldings
    function itemIdToAsset(PoolId poolId, ItemId itemId_) external view returns (ShareClassId scId, AssetId assetId) {
        Item storage item_ = item[poolId][itemId_];
        return (item_.scId, item_.assetId);
    }
}
