// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {IERC6909Decimals} from "src/misc/interfaces/IERC6909.sol";

import {PoolId, newPoolId} from "src/common/types/PoolId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {IPoolRegistry} from "src/pools/interfaces/IPoolRegistry.sol";
import {IShareClassManager} from "src/pools/interfaces/IShareClassManager.sol";

contract PoolRegistry is Auth, IPoolRegistry {
    using MathLib for uint256;

    uint48 public latestId;

    mapping(AssetId => uint8) internal _decimals;

    mapping(PoolId => bytes) public metadata;
    mapping(PoolId => AssetId) public currency;
    mapping(PoolId => mapping(address => bool)) public isAdmin;
    mapping(PoolId => mapping(bytes32 => address)) public dependency;

    constructor(address deployer) Auth(deployer) {}

    /// @inheritdoc IPoolRegistry
    function registerAsset(AssetId assetId, uint8 decimals_) external auth {
        require(_decimals[assetId] == 0, AssetAlreadyRegistered());

        _decimals[assetId] = decimals_;

        emit NewAsset(assetId, decimals_);
    }

    /// @inheritdoc IPoolRegistry
    function registerPool(address admin_, uint16 centrifugeChainId, AssetId currency_)
        external
        auth
        returns (PoolId poolId)
    {
        require(admin_ != address(0), EmptyAdmin());
        require(!currency_.isNull(), EmptyCurrency());
        require(currency[poolId].isNull(), PoolAlreadyRegistered());

        poolId = newPoolId(centrifugeChainId, ++latestId);

        isAdmin[poolId][admin_] = true;
        currency[poolId] = currency_;

        emit NewPool(poolId, admin_, currency_);
    }

    /// @inheritdoc IPoolRegistry
    function updateAdmin(PoolId poolId, address admin_, bool canManage) external auth {
        require(exists(poolId), NonExistingPool(poolId));
        require(admin_ != address(0), EmptyAdmin());

        isAdmin[poolId][admin_] = canManage;

        emit UpdateAdmin(poolId, admin_, canManage);
    }

    /// @inheritdoc IPoolRegistry
    function setMetadata(PoolId poolId, bytes calldata metadata_) external auth {
        require(exists(poolId), NonExistingPool(poolId));

        metadata[poolId] = metadata_;

        emit SetMetadata(poolId, metadata_);
    }

    /// @inheritdoc IPoolRegistry
    function updateDependency(PoolId poolId, bytes32 what, address dependency_) external auth {
        require(exists(poolId), NonExistingPool(poolId));

        dependency[poolId][what] = dependency_;

        emit UpdateDependency(poolId, what, dependency_);
    }

    /// @inheritdoc IPoolRegistry
    function updateCurrency(PoolId poolId, AssetId currency_) external auth {
        require(exists(poolId), NonExistingPool(poolId));
        require(!currency_.isNull(), EmptyCurrency());

        currency[poolId] = currency_;

        emit UpdateCurrency(poolId, currency_);
    }

    function decimals(PoolId poolId) public view returns (uint8 decimals_) {
        decimals_ = _decimals[currency[poolId]];
        require(decimals_ > 0, AssetNotFound());
    }

    /// @inheritdoc IERC6909Decimals
    function decimals(uint256 asset_) external view returns (uint8 decimals_) {
        decimals_ = _decimals[AssetId.wrap(asset_.toUint128())];
        require(decimals_ > 0, AssetNotFound());
    }

    /// @inheritdoc IPoolRegistry
    function exists(PoolId poolId) public view returns (bool) {
        return !currency[poolId].isNull();
    }

    /// @inheritdoc IPoolRegistry
    function isRegistered(AssetId assetId) public view returns (bool) {
        return _decimals[assetId] != 0;
    }
}
