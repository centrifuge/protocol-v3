// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18} from "src/misc/types/D18.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {Auth} from "src/misc/Auth.sol";
import {Multicall, IMulticall} from "src/misc/Multicall.sol";

import {IGateway} from "src/common/interfaces/IGateway.sol";

import {ShareClassId} from "src/pools/types/ShareClassId.sol";
import {AssetId} from "src/pools/types/AssetId.sol";
import {AccountId, newAccountId} from "src/pools/types/AccountId.sol";
import {PoolId} from "src/pools/types/PoolId.sol";
import {IPoolRegistry} from "src/pools/interfaces/IPoolRegistry.sol";
import {IShareClassManager} from "src/pools/interfaces/IShareClassManager.sol";
import {IPoolManager} from "src/pools/interfaces/IPoolManager.sol";
import {IPoolRouter} from "src/pools/interfaces/IPoolRouter.sol";

contract PoolRouter is Multicall, IPoolRouter {
    IPoolManager public immutable poolManager;
    IGateway public gateway;

    constructor(IPoolManager poolManager_, IGateway gateway_) {
        poolManager = poolManager_;
        gateway = gateway_;
    }

    // --- Administration ---
    /// @inheritdoc IMulticall
    /// @notice performs a multicall but all messages sent in the process will be batched
    function multicall(bytes[] calldata data) public payable override {
        bool wasBatching = gateway.isBatching();
        if (!wasBatching) {
            gateway.startBatch();
        }

        super.multicall(data);

        if (!wasBatching) {
            gateway.setPayableSource(msg.sender);
            gateway.topUp{value: msg.value}();
            gateway.endBatch();
        }
    }

    /// @inheritdoc IPoolRouter
    function execute(PoolId poolId, bytes[] calldata data) external payable {
        poolManager.unlock(poolId, msg.sender);

        multicall(data);

        poolManager.lock();
    }

    /// @inheritdoc IPoolRouter
    function createPool(AssetId currency, IShareClassManager shareClassManager)
        external
        payable
        returns (PoolId poolId)
    {
        return poolManager.createPool(msg.sender, currency, shareClassManager);
    }

    /// @inheritdoc IPoolRouter
    function claimDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor)
        external
        payable
        protected
    {
        _pay();
        gateway.setPayableSource(msg.sender);
        poolManager.claimDeposit(poolId, scId, assetId, investor);
    }

    /// @inheritdoc IPoolRouter
    function claimRedeem(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor)
        external
        payable
        protected
    {
        _pay();
        gateway.setPayableSource(msg.sender);
        poolManager.claimRedeem(poolId, scId, assetId, investor);
    }

    /// @inheritdoc IPoolRouter
    function notifyPool(uint32 chainId) external payable protected {
        poolManager.notifyPool(chainId);
    }

    /// @inheritdoc IPoolRouter
    function notifyShareClass(uint32 chainId, ShareClassId scId, bytes32 hook) external payable protected {
        poolManager.notifyShareClass(chainId, scId, hook);
    }

    /// @inheritdoc IPoolRouter
    function setPoolMetadata(bytes calldata metadata) external payable protected {
        poolManager.setPoolMetadata(metadata);
    }

    /// @inheritdoc IPoolRouter
    function allowPoolAdmin(address account, bool allow) external payable protected {
        poolManager.allowPoolAdmin(account, allow);
    }

    /// @inheritdoc IPoolRouter
    function allowAsset(ShareClassId scId, AssetId assetId, bool allow) external payable protected {
        poolManager.allowAsset(scId, assetId, allow);
    }

    /// @inheritdoc IPoolRouter
    function addShareClass(string calldata name, string calldata symbol, bytes32 salt, bytes calldata data)
        external
        payable
        protected
    {
        poolManager.addShareClass(name, symbol, salt, data);
    }

    /// @inheritdoc IPoolRouter
    function approveDeposits(ShareClassId scId, AssetId paymentAssetId, uint128 maxApproval, IERC7726 valuation)
        external
        payable
        protected
    {
        poolManager.approveDeposits(scId, paymentAssetId, maxApproval, valuation);
    }

    /// @inheritdoc IPoolRouter
    function approveRedeems(ShareClassId scId, AssetId payoutAssetId, uint128 maxApproval) external payable protected {
        poolManager.approveRedeems(scId, payoutAssetId, maxApproval);
    }

    /// @inheritdoc IPoolRouter
    function issueShares(ShareClassId scId, AssetId depositAssetId, D18 navPerShare) external payable protected {
        poolManager.issueShares(scId, depositAssetId, navPerShare);
    }

    /// @inheritdoc IPoolRouter
    function revokeShares(ShareClassId scId, AssetId payoutAssetId, D18 navPerShare, IERC7726 valuation)
        external
        payable
        protected
    {
        poolManager.revokeShares(scId, payoutAssetId, navPerShare, valuation);
    }

    /// @inheritdoc IPoolRouter
    function createHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint24 prefix)
        external
        payable
        protected
    {
        poolManager.createHolding(scId, assetId, valuation, prefix);
    }

    /// @inheritdoc IPoolRouter
    function increaseHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint128 amount)
        external
        payable
        protected
    {
        poolManager.increaseHolding(scId, assetId, valuation, amount);
    }

    /// @inheritdoc IPoolRouter
    function decreaseHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint128 amount)
        external
        payable
        protected
    {
        poolManager.decreaseHolding(scId, assetId, valuation, amount);
    }

    /// @inheritdoc IPoolRouter
    function updateHolding(ShareClassId scId, AssetId assetId) external payable protected {
        poolManager.updateHolding(scId, assetId);
    }

    /// @inheritdoc IPoolRouter
    function updateHoldingValuation(ShareClassId scId, AssetId assetId, IERC7726 valuation)
        external
        payable
        protected
    {
        poolManager.updateHoldingValuation(scId, assetId, valuation);
    }

    /// @inheritdoc IPoolRouter
    function setHoldingAccountId(ShareClassId scId, AssetId assetId, AccountId accountId) external payable protected {
        poolManager.setHoldingAccountId(scId, assetId, accountId);
    }

    /// @inheritdoc IPoolRouter
    function createAccount(AccountId account, bool isDebitNormal) external payable protected {
        poolManager.createAccount(account, isDebitNormal);
    }

    /// @inheritdoc IPoolRouter
    function setAccountMetadata(AccountId account, bytes calldata metadata) external payable protected {
        poolManager.setAccountMetadata(account, metadata);
    }

    /// @inheritdoc IPoolRouter
    function addDebit(AccountId account, uint128 amount) external payable protected {
        poolManager.addDebit(account, amount);
    }

    /// @inheritdoc IPoolRouter
    function addCredit(AccountId account, uint128 amount) external payable protected {
        poolManager.addCredit(account, amount);
    }

    /// @notice Send native tokens to the gateway for transaction payment if it's not in a multicall.
    function _pay() internal {
        if (!gateway.isBatching()) {
            gateway.topUp{value: msg.value}();
        }
    }
}
