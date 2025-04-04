// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {BytesLib} from "src/misc/libraries/BytesLib.sol";

import {PoolId} from "src/common/types/PoolId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {ShareClassId, newShareClassId} from "src/common/types/ShareClassId.sol";

import {IPoolRegistry} from "src/pools/interfaces/IPoolRegistry.sol";
import {IShareClassManager} from "src/pools/interfaces/IShareClassManager.sol";
import {IMultiShareClass} from "src/pools/interfaces/IMultiShareClass.sol";

struct EpochAmounts {
    /// @dev Total pending asset amount of deposit asset
    uint128 depositPending;
    /// @dev Total approved asset amount of deposit asset
    uint128 depositApproved;
    /// @dev Total approved pool amount of deposit asset
    uint128 depositPool;
    /// @dev Total number of share class tokens issued
    uint128 depositShares;
    /// @dev Amount of shares pending to be redeemed
    uint128 redeemPending;
    /// @dev Total approved amount of redeemed share class tokens
    uint128 redeemApproved;
    /// @dev Total asset amount of revoked share class tokens
    uint128 redeemAssets;
}

struct UserOrder {
    /// @dev Pending amount in deposit asset denomination
    uint128 pending;
    /// @dev Index of epoch in which last order was made
    uint32 lastUpdate;
}

struct EpochPointers {
    /// @dev The last epoch in which a deposit approval was made
    uint32 latestDepositApproval;
    /// @dev The last epoch in which a redeem approval was made
    uint32 latestRedeemApproval;
    /// @dev The last epoch in which shares were issued
    uint32 latestIssuance;
    /// @dev The last epoch in which a shares were revoked
    uint32 latestRevocation;
}

struct ShareClassMetadata {
    /// @dev The name of the share class token
    string name;
    /// @dev The symbol of the share class token
    string symbol;
    /// @dev The salt of the share class token
    bytes32 salt;
}

struct ShareClassMetrics {
    /// @dev Total number of shares
    uint128 totalIssuance;
    /// @dev The latest net asset value per share class token
    D18 navPerShare;
}

contract MultiShareClass is Auth, IMultiShareClass {
    using MathLib for D18;
    using MathLib for uint128;
    using MathLib for uint256;
    using CastLib for bytes;
    using CastLib for bytes32;
    using BytesLib for bytes;

    uint32 constant META_NAME_LENGTH = 128;
    uint32 constant META_SYMBOL_LENGTH = 32;

    /// Storage
    uint32 internal transient _epochIncrement;
    IPoolRegistry public poolRegistry;
    mapping(bytes32 salt => bool) public salts;
    mapping(PoolId poolId => uint32) public epochId;
    mapping(PoolId poolId => uint32) public shareClassCount;
    mapping(ShareClassId scId => ShareClassMetrics) public metrics;
    mapping(ShareClassId scId => ShareClassMetadata) public metadata;
    mapping(PoolId poolId => mapping(ShareClassId => bool)) public shareClassIds;
    mapping(ShareClassId scId => mapping(AssetId assetId => EpochPointers)) public epochPointers;
    mapping(ShareClassId scId => mapping(AssetId payoutAssetId => uint128 pending)) public pendingRedeem;
    mapping(ShareClassId scId => mapping(AssetId paymentAssetId => uint128 pending)) public pendingDeposit;
    mapping(ShareClassId scId => mapping(AssetId assetId => mapping(uint32 epochId_ => EpochAmounts epoch))) public
        epochAmounts;
    mapping(ShareClassId scId => mapping(AssetId payoutAssetId => mapping(bytes32 investor => UserOrder pending)))
        public redeemRequest;
    mapping(ShareClassId scId => mapping(AssetId paymentAssetId => mapping(bytes32 investor => UserOrder pending)))
        public depositRequest;

    constructor(IPoolRegistry poolRegistry_, address deployer) Auth(deployer) {
        poolRegistry = poolRegistry_;
    }

    function file(bytes32 what, address data) external auth {
        require(what == "poolRegistry", UnrecognizedFileParam());
        poolRegistry = IPoolRegistry(data);
        emit File(what, data);
    }

    /// @inheritdoc IShareClassManager
    function addShareClass(PoolId poolId, string calldata name, string calldata symbol, bytes32 salt, bytes calldata) external auth returns (ShareClassId scId_) {
        scId_ = previewNextShareClassId(poolId);

        uint32 index = ++shareClassCount[poolId];
        shareClassIds[poolId][scId_] = true;

        // Initialize epoch with 1 iff first class was added
        if (index == 1) {
            epochId[poolId] = 1;
        }

        _updateMetadata(scId_, name, symbol, salt);

        emit AddShareClass(poolId, scId_, index, name, symbol, salt);
    }

    /// @inheritdoc IShareClassManager
    function requestDeposit(
        PoolId poolId,
        ShareClassId scId_,
        uint128 amount,
        bytes32 investor,
        AssetId depositAssetId
    ) external auth {
        require(exists(poolId, scId_), ShareClassNotFound());

        // NOTE: CV ensures amount > 0
        _updateDepositRequest(poolId, scId_, amount, true, investor, depositAssetId);
    }

    function cancelDepositRequest(PoolId poolId, ShareClassId scId_, bytes32 investor, AssetId depositAssetId)
        external
        auth
        returns (uint128 cancelledAssetAmount)
    {
        require(exists(poolId, scId_), ShareClassNotFound());

        cancelledAssetAmount = depositRequest[scId_][depositAssetId][investor].pending;

        _updateDepositRequest(poolId, scId_, cancelledAssetAmount, false, investor, depositAssetId);
    }

    /// @inheritdoc IShareClassManager
    function requestRedeem(
        PoolId poolId,
        ShareClassId scId_,
        uint128 amount,
        bytes32 investor,
        AssetId payoutAssetId
    ) external auth {
        require(exists(poolId, scId_), ShareClassNotFound());

        // NOTE: CV ensures amount > 0
        _updateRedeemRequest(poolId, scId_, amount, true, investor, payoutAssetId);
    }

    /// @inheritdoc IShareClassManager
    function cancelRedeemRequest(PoolId poolId, ShareClassId scId_, bytes32 investor, AssetId payoutAssetId)
        external
        auth
        returns (uint128 cancelledShareAmount)
    {
        require(exists(poolId, scId_), ShareClassNotFound());

        cancelledShareAmount = redeemRequest[scId_][payoutAssetId][investor].pending;

        _updateRedeemRequest(poolId, scId_, cancelledShareAmount, false, investor, payoutAssetId);
    }

    /// @inheritdoc IShareClassManager
    function approveDeposits(
        PoolId poolId,
        ShareClassId scId_,
        uint128 maxApproval,
        AssetId paymentAssetId,
        IERC7726 valuation
    ) external auth returns (uint128 approvedAssetAmount, uint128 approvedPoolAmount) {
        require(exists(poolId, scId_), ShareClassNotFound());

        // Advance epochId if it has not been advanced within this transaction (e.g. in case of multiCall context)
        uint32 approvalEpochId = _advanceEpoch(poolId);

        // Block approvals for the same asset in the same epoch
        require(
            epochPointers[scId_][paymentAssetId].latestDepositApproval != approvalEpochId, AlreadyApproved()
        );

        // Limit in case approved > pending due to race condition of FM approval and async incoming requests
        uint128 _pendingDeposit = pendingDeposit[scId_][paymentAssetId];
        approvedAssetAmount = maxApproval.min(_pendingDeposit).toUint128();
        require(approvedAssetAmount > 0, ZeroApprovalAmount());

        // Increase approved
        address poolCurrency = poolRegistry.currency(poolId).addr();
        approvedPoolAmount =
            (IERC7726(valuation).getQuote(approvedAssetAmount, paymentAssetId.addr(), poolCurrency)).toUint128();

        // Update epoch data
        EpochAmounts storage epochAmounts_ = epochAmounts[scId_][paymentAssetId][approvalEpochId];
        epochAmounts_.depositApproved = approvedAssetAmount;
        epochAmounts_.depositPool = approvedPoolAmount;
        epochAmounts_.depositPending = _pendingDeposit;
        epochPointers[scId_][paymentAssetId].latestDepositApproval = approvalEpochId;

        // Reduce pending
        pendingDeposit[scId_][paymentAssetId] -= approvedAssetAmount;
        _pendingDeposit -= approvedAssetAmount;

        emit ApproveDeposits(
            poolId,
            scId_,
            approvalEpochId,
            paymentAssetId,
            approvedPoolAmount,
            approvedAssetAmount,
            _pendingDeposit
        );
    }

    /// @inheritdoc IShareClassManager
    function approveRedeems(PoolId poolId, ShareClassId scId_, uint128 maxApproval, AssetId payoutAssetId)
        external
        auth
        returns (uint128 approvedShareAmount, uint128 pendingShareAmount)
    {
        require(exists(poolId, scId_), ShareClassNotFound());

        // Advance epochId if it has not been advanced within this transaction (e.g. in case of multiCall context)
        uint32 approvalEpochId = _advanceEpoch(poolId);

        // Block approvals for the same asset in the same epoch
        require(epochPointers[scId_][payoutAssetId].latestRedeemApproval != approvalEpochId, AlreadyApproved());

        // Limit in case approved > pending due to race condition of FM approval and async incoming requests
        pendingShareAmount = pendingRedeem[scId_][payoutAssetId];
        approvedShareAmount = maxApproval.min(pendingShareAmount).toUint128();
        require(approvedShareAmount > 0, ZeroApprovalAmount());

        // Update epoch data
        EpochAmounts storage epochAmounts_ = epochAmounts[scId_][payoutAssetId][approvalEpochId];
        epochAmounts_.redeemApproved = approvedShareAmount;
        epochAmounts_.redeemPending = pendingShareAmount;

        // Reduce pending
        pendingRedeem[scId_][payoutAssetId] -= approvedShareAmount;
        pendingShareAmount -= approvedShareAmount;

        epochPointers[scId_][payoutAssetId].latestRedeemApproval = approvalEpochId;

        emit ApproveRedeems(
            poolId,
            scId_,
            approvalEpochId,
            payoutAssetId,
            approvedShareAmount,
            pendingShareAmount
        );
    }

    /// @inheritdoc IShareClassManager
    function issueShares(PoolId poolId, ShareClassId scId_, AssetId depositAssetId, D18 navPerShare)
        external
        auth
    {
        EpochPointers storage epochPointers_ = epochPointers[scId_][depositAssetId];
        require(epochPointers_.latestDepositApproval > epochPointers_.latestIssuance, ApprovalRequired());

        issueSharesUntilEpoch(poolId, scId_, depositAssetId, navPerShare, epochPointers_.latestDepositApproval);
    }

    /// @inheritdoc IMultiShareClass
    function issueSharesUntilEpoch(
        PoolId poolId,
        ShareClassId scId_,
        AssetId depositAssetId,
        D18 navPerShare,
        uint32 endEpochId
    ) public auth {
        require(exists(poolId, scId_), ShareClassNotFound());
        require(endEpochId < epochId[poolId], EpochNotFound());

        uint128 totalIssuance = metrics[scId_].totalIssuance;

        // First issuance starts at epoch 0, subsequent ones at latest pointer plus one
        uint32 startEpochId = epochPointers[scId_][depositAssetId].latestIssuance + 1;

        for (uint32 epochId_ = startEpochId; epochId_ <= endEpochId; epochId_++) {
            // Skip redeem epochs
            if (epochAmounts[scId_][depositAssetId][epochId_].depositApproved == 0) {
                continue;
            }

            uint128 issuedShareAmount = navPerShare.reciprocalMulUint128(
                epochAmounts[scId_][depositAssetId][epochId_].depositPool
            );
            epochAmounts[scId_][depositAssetId][epochId_].depositShares = issuedShareAmount;
            totalIssuance += issuedShareAmount;
            uint128 nav = navPerShare.mulUint128(totalIssuance);

            emit IssueShares(poolId, scId_, epochId_, navPerShare, nav, issuedShareAmount);
        }

        epochPointers[scId_][depositAssetId].latestIssuance = endEpochId;
        metrics[scId_] = ShareClassMetrics(totalIssuance, navPerShare);
    }

    /// @inheritdoc IShareClassManager
    function revokeShares(
        PoolId poolId,
        ShareClassId scId_,
        AssetId payoutAssetId,
        D18 navPerShare,
        IERC7726 valuation
    ) external auth returns (uint128 payoutAssetAmount, uint128 payoutPoolAmount) {
        EpochPointers storage epochPointers_ = epochPointers[scId_][payoutAssetId];
        require(epochPointers_.latestRedeemApproval > epochPointers_.latestRevocation, ApprovalRequired());

        return revokeSharesUntilEpoch(
            poolId, scId_, payoutAssetId, navPerShare, valuation, epochPointers_.latestRedeemApproval
        );
    }

    /// @inheritdoc IMultiShareClass
    function revokeSharesUntilEpoch(
        PoolId poolId,
        ShareClassId scId_,
        AssetId payoutAssetId,
        D18 navPerShare,
        IERC7726 valuation,
        uint32 endEpochId
    ) public auth returns (uint128 payoutAssetAmount, uint128 payoutPoolAmount) {
        require(exists(poolId, scId_), ShareClassNotFound());
        require(endEpochId < epochId[poolId], EpochNotFound());

        uint128 totalIssuance = metrics[scId_].totalIssuance;
        address poolCurrency = poolRegistry.currency(poolId).addr();

        // First issuance starts at epoch 0, subsequent ones at latest pointer plus one
        uint32 startEpochId = epochPointers[scId_][payoutAssetId].latestRevocation + 1;

        for (uint32 epochId_ = startEpochId; epochId_ <= endEpochId; epochId_++) {
            EpochAmounts storage epochAmounts_ = epochAmounts[scId_][payoutAssetId][epochId_];

            // Skip deposit epochs
            if (epochAmounts_.redeemApproved == 0) {
                continue;
            }

            require(epochAmounts_.redeemApproved <= totalIssuance, RevokeMoreThanIssued());

            payoutPoolAmount += _revokeEpochShares(
                poolId,
                scId_,
                payoutAssetId,
                navPerShare,
                valuation,
                poolCurrency,
                epochAmounts_,
                totalIssuance,
                epochId_
            );
            payoutAssetAmount += epochAmounts_.redeemAssets;
            totalIssuance -= epochAmounts_.redeemApproved;
        }

        epochPointers[scId_][payoutAssetId].latestRevocation = endEpochId;
        metrics[scId_] = ShareClassMetrics(totalIssuance, navPerShare);
    }

    /// @inheritdoc IShareClassManager
    function claimDeposit(PoolId poolId, ShareClassId scId_, bytes32 investor, AssetId depositAssetId)
        external
        auth
        returns (uint128 payoutShareAmount, uint128 paymentAssetAmount)
    {
        return claimDepositUntilEpoch(
            poolId, scId_, investor, depositAssetId, epochPointers[scId_][depositAssetId].latestIssuance
        );
    }

    /// @inheritdoc IMultiShareClass
    function claimDepositUntilEpoch(
        PoolId poolId,
        ShareClassId scId_,
        bytes32 investor,
        AssetId depositAssetId,
        uint32 endEpochId
    ) public auth returns (uint128 payoutShareAmount, uint128 paymentAssetAmount) {
        require(exists(poolId, scId_), ShareClassNotFound());
        require(endEpochId < epochId[poolId], EpochNotFound());

        UserOrder storage userOrder = depositRequest[scId_][depositAssetId][investor];

        for (uint32 epochId_ = userOrder.lastUpdate; epochId_ <= endEpochId; epochId_++) {
            EpochAmounts storage epochAmounts_ = epochAmounts[scId_][depositAssetId][epochId_];

            // Skip redeem epochs
            if (epochAmounts_.depositApproved == 0) {
                continue;
            }

            // Skip epoch if user cannot claim
            uint128 approvedAssetAmount = userOrder.pending.mulDiv(epochAmounts_.depositApproved, epochAmounts_.depositPending).toUint128();
            if (approvedAssetAmount == 0) {
                emit ClaimDeposit(poolId, scId_, epochId_, investor, depositAssetId, 0, userOrder.pending, 0);
                continue;
            }

            uint128 claimableShareAmount = uint256(approvedAssetAmount).mulDiv(
                epochAmounts_.depositShares, epochAmounts_.depositApproved
            ).toUint128();

            // NOTE: During approvals, we reduce pendingDeposits by the approved asset amount. However, we only reduce the pending user amount if the claimable amount is non-zero.
            //
            // This extreme edge case has two implications:
            //  1. The sum of pending user orders <= pendingDeposits (instead of equality)
            //  2. The sum of claimable user amounts <= amount of minted share class tokens corresponding to the approved deposit asset amount (instead of equality).
            //     I.e., it is possible for an epoch to have an excess of a share class token atom which cannot be claimed by anyone.
            //
            // The first implication can be switched to equality if we reduce the pending user amount independent of the claimable amount.
            // However, in practice, it should be extremely unlikely to have users with non-zero pending but zero claimable for an epoch.
            if (claimableShareAmount > 0) {
                userOrder.pending -= approvedAssetAmount;
                payoutShareAmount += claimableShareAmount;
                paymentAssetAmount += approvedAssetAmount;
            }

            emit ClaimDeposit(
                poolId,
                scId_,
                epochId_,
                investor,
                depositAssetId,
                approvedAssetAmount,
                userOrder.pending,
                claimableShareAmount
            );
        }

        userOrder.lastUpdate = endEpochId + 1;
    }

    /// @inheritdoc IShareClassManager
    function claimRedeem(PoolId poolId, ShareClassId scId_, bytes32 investor, AssetId payoutAssetId)
        external
        auth
        returns (uint128 payoutAssetAmount, uint128 paymentShareAmount)
    {
        return claimRedeemUntilEpoch(
            poolId, scId_, investor, payoutAssetId, epochPointers[scId_][payoutAssetId].latestRevocation
        );
    }

    /// @inheritdoc IMultiShareClass
    function claimRedeemUntilEpoch(
        PoolId poolId,
        ShareClassId scId_,
        bytes32 investor,
        AssetId payoutAssetId,
        uint32 endEpochId
    ) public auth returns (uint128 payoutAssetAmount, uint128 paymentShareAmount) {
        require(exists(poolId, scId_), ShareClassNotFound());
        require(endEpochId < epochId[poolId], EpochNotFound());

        UserOrder storage userOrder = redeemRequest[scId_][payoutAssetId][investor];

        for (uint32 epochId_ = userOrder.lastUpdate; epochId_ <= endEpochId; epochId_++) {
            EpochAmounts storage epochAmounts_ = epochAmounts[scId_][payoutAssetId][epochId_];

            // Skip deposit epochs
            if (epochAmounts_.redeemApproved == 0) {
                continue;
            }

            // Skip epoch if user cannot claim
            uint128 approvedShareAmount = userOrder.pending.mulDiv(epochAmounts_.redeemApproved, epochAmounts_.redeemPending).toUint128();
            if (approvedShareAmount == 0) {
                emit ClaimRedeem(poolId, scId_, epochId_, investor, payoutAssetId, 0, userOrder.pending, 0);
                continue;
            }

            uint128 claimableAssetAmount = uint256(approvedShareAmount).mulDiv(
                epochAmounts_.redeemAssets, epochAmounts_.redeemApproved
            ).toUint128();

            // NOTE: During approvals, we reduce pendingRedeems by the approved share class token amount. However, we only reduce the pending user amount if the claimable amount is non-zero.
            //
            // This extreme edge case has two implications:
            //  1. The sum of pending user orders <= pendingRedeems (instead of equality)
            //  2. The sum of claimable user amounts <= amount of payout asset corresponding to the approved share class token amount (instead of equality).
            //     I.e., it is possible for an epoch to have an excess of a single payout asset atom which cannot be claimed by anyone.
            //
            // The first implication can be switched to equality if we reduce the pending user amount independent of the claimable amount.
            // However, in practice, it should be extremely unlikely to have users with non-zero pending but zero claimable for an epoch.
            if (claimableAssetAmount > 0) {
                paymentShareAmount += approvedShareAmount;
                payoutAssetAmount += claimableAssetAmount;
                userOrder.pending -= approvedShareAmount;
            }

            emit ClaimRedeem(
                poolId,
                scId_,
                epochId_,
                investor,
                payoutAssetId,
                approvedShareAmount,
                userOrder.pending,
                claimableAssetAmount
            );
        }

        userOrder.lastUpdate = endEpochId + 1;
    }

    function updateMetadata(PoolId poolId, ShareClassId scId_, string calldata name, string calldata symbol, bytes32 salt, bytes calldata) external auth {
        require(exists(poolId, scId_), ShareClassNotFound());

        _updateMetadata(scId_, name, symbol, salt);

        emit UpdateMetadata(poolId, scId_, name, symbol, salt);
    }


    /// @inheritdoc IShareClassManager
    function increaseShareClassIssuance(PoolId poolId, ShareClassId scId_, D18 navPerShare, uint128 amount) external auth {
        require(exists(poolId, scId_), ShareClassNotFound());

        uint128 newIssuance = metrics[scId_].totalIssuance + amount;
        metrics[scId_].totalIssuance = newIssuance;

        emit IssueShares(poolId, scId_, epochId[poolId], navPerShare, navPerShare.mulUint128(newIssuance), amount);
    }

    /// @inheritdoc IShareClassManager
    function decreaseShareClassIssuance(PoolId poolId, ShareClassId scId_, D18 navPerShare, uint128 amount) external auth {
        require(exists(poolId, scId_), ShareClassNotFound());
        require(metrics[scId_].totalIssuance >= amount, DecreaseMoreThanIssued());

        uint128 newIssuance = metrics[scId_].totalIssuance - amount;
        metrics[scId_].totalIssuance = newIssuance;

        emit RevokeShares(poolId, scId_, epochId[poolId], navPerShare, navPerShare.mulUint128(newIssuance), amount, 0);
    }


    /// @inheritdoc IShareClassManager
    function updateShareClassNav(PoolId poolId, ShareClassId scId_) external view auth returns (uint128, D18) {
        require(exists(poolId, scId_), ShareClassNotFound());
        revert("unsupported");
    }

    /// @inheritdoc IShareClassManager
    function previewNextShareClassId(PoolId poolId) public view returns (ShareClassId scId) {
        return newShareClassId(poolId, shareClassCount[poolId] + 1);
    }

    /// @inheritdoc IShareClassManager
    function previewShareClassId(PoolId poolId, uint32 index) public pure returns (ShareClassId scId) {
        return newShareClassId(poolId, index);
    }

    /// @inheritdoc IShareClassManager
    function update(PoolId, bytes calldata) external pure {
        revert("unsupported");
    }

    /// @notice Revokes shares for a single epoch, updates epoch ratio and emits event.
    ///
    /// @param poolId Identifier of the pool
    /// @param scId_ Identifier of the share class
    /// @param payoutAssetId Identifier of the payout asset
    /// @param navPerShare Total value of assets of the pool and share class per share
    /// @param valuation Source of truth for quotas, e.g. the price of a pool amount in payout asset
    /// @param poolCurrency The address of the pool currency
    /// @param epochAmounts_ Epoch ratio storage for the amount of revoked share class tokens and the corresponding
    /// amount
    /// in payout asset
    /// @param totalIssuance Total issuance of share class tokens before revoking
    /// @param epochId_ Identifier of the epoch for which we revoke
    /// @return payoutPoolAmount Converted amount of pool currency based on number of revoked shares
    function _revokeEpochShares(
        PoolId poolId,
        ShareClassId scId_,
        AssetId payoutAssetId,
        D18 navPerShare,
        IERC7726 valuation,
        address poolCurrency,
        EpochAmounts storage epochAmounts_,
        uint128 totalIssuance,
        uint32 epochId_
    ) private returns (uint128 payoutPoolAmount) {
        payoutPoolAmount = navPerShare.mulUint128(epochAmounts_.redeemApproved);
        epochAmounts_.redeemAssets =
            IERC7726(valuation).getQuote(payoutPoolAmount, poolCurrency, payoutAssetId.addr()).toUint128();

        uint128 nav = navPerShare.mulUint128(totalIssuance - epochAmounts_.redeemApproved);
        emit RevokeShares(
            poolId,
            scId_,
            epochId_,
            navPerShare,
            nav,
            epochAmounts_.redeemApproved,
            epochAmounts_.redeemAssets
        );
    }

    /// @inheritdoc IShareClassManager
    function exists(PoolId poolId, ShareClassId scId_) public view returns (bool) {
        return shareClassIds[poolId][scId_];
    }

    /// @notice Updates the amount of a request to deposit (exchange) an asset amount for share class tokens.
    ///
    /// @param poolId Identifier of the pool
    /// @param scId_ Identifier of the share class
    /// @param amount Asset token amount which is updated
    /// @param isIncrement Whether the amount is positive or negative
    /// @param investor Address of the entity which is depositing
    /// @param depositAssetId Identifier of the asset which the investor used for their deposit request
    function _updateDepositRequest(
        PoolId poolId,
        ShareClassId scId_,
        uint128 amount,
        bool isIncrement,
        bytes32 investor,
        AssetId depositAssetId
    ) private {
        UserOrder storage userOrder = depositRequest[scId_][depositAssetId][investor];

        // Block updates until pending amount does not impact claimable amount, i.e. last update happened after latest
        // approval
        uint32 latestApproval = epochPointers[scId_][depositAssetId].latestDepositApproval;
        require(
            userOrder.pending == 0 || latestApproval == 0 || userOrder.lastUpdate > latestApproval,
            ClaimDepositRequired()
        );

        userOrder.pending = isIncrement ? userOrder.pending + amount : userOrder.pending - amount;
        userOrder.lastUpdate = epochId[poolId];

        pendingDeposit[scId_][depositAssetId] = isIncrement
            ? pendingDeposit[scId_][depositAssetId] + amount
            : pendingDeposit[scId_][depositAssetId] - amount;

        emit UpdateDepositRequest(
            poolId,
            scId_,
            epochId[poolId],
            investor,
            depositAssetId,
            userOrder.pending,
            pendingDeposit[scId_][depositAssetId]
        );
    }

    /// @notice Updates the amount of a request to redeem (exchange) share class tokens for an asset.
    ///
    /// @param poolId Identifier of the pool
    /// @param scId_ Identifier of the share class
    /// @param amount Share class token amount which is updated
    /// @param isIncrement Whether the amount is positive or negative
    /// @param investor Address of the entity which is depositing
    /// @param payoutAssetId Identifier of the asset which the investor wants to offramp to
    function _updateRedeemRequest(
        PoolId poolId,
        ShareClassId scId_,
        uint128 amount,
        bool isIncrement,
        bytes32 investor,
        AssetId payoutAssetId
    ) private {
        UserOrder storage userOrder = redeemRequest[scId_][payoutAssetId][investor];

        // Block updates until pending amount does not impact claimable amount
        uint32 latestApproval = epochPointers[scId_][payoutAssetId].latestRedeemApproval;
        require(
            userOrder.pending == 0 || latestApproval == 0 || userOrder.lastUpdate > latestApproval,
            ClaimRedeemRequired()
        );

        userOrder.lastUpdate = epochId[poolId];
        userOrder.pending = isIncrement ? userOrder.pending + amount : userOrder.pending - amount;

        pendingRedeem[scId_][payoutAssetId] = isIncrement
            ? pendingRedeem[scId_][payoutAssetId] + amount
            : pendingRedeem[scId_][payoutAssetId] - amount;

        emit UpdateRedeemRequest(
            poolId,
            scId_,
            epochId[poolId],
            investor,
            payoutAssetId,
            userOrder.pending,
            pendingRedeem[scId_][payoutAssetId]
        );
    }

    function _updateMetadata(ShareClassId scId_, string calldata name, string calldata symbol, bytes32 salt) private {
        uint256 nLen = bytes(name).length;
        require(nLen> 0 && nLen <= 128, InvalidMetadataName());

        uint256 sLen = bytes(symbol).length;
        require(sLen > 0 && sLen <= 32, InvalidMetadataSymbol());

        require(salt != bytes32(0), InvalidSalt());
        // Either the salt has not changed, or the salt was never used before by any share class token
        require(salt == metadata[scId_].salt || !salts[salt], AlreadyUsedSalt());
        salts[salt] = true;

        metadata[scId_] = ShareClassMetadata(name, symbol, salt);

    }

    /// @notice Advances the current epoch of the given pool if it has not been incremented within the multicall. If the
    /// epoch has already been incremented, we don't bump it again to allow deposit and redeem approvals to point to the
    /// same epoch id. Emits NewEpoch event if the epoch is advanced.
    ///
    /// @param poolId Identifier of the pool for which we want to advance an epoch.
    /// @return epochIdCurrentBlock Identifier of the current epoch. E.g., if the epoch advanced from i to i+1, i is
    /// returned.
    function _advanceEpoch(PoolId poolId) private returns (uint32 epochIdCurrentBlock) {
        uint32 epochId_ = epochId[poolId];

        // Epoch doesn't necessarily advance, e.g. in case of multiple approvals inside the same multiCall
        if (_epochIncrement == 0) {
            _epochIncrement = 1;
            uint32 newEpochId = epochId_ + 1;
            epochId[poolId] = newEpochId;

            emit NewEpoch(poolId, newEpochId);

            return epochId_;
        } else {
            return uint32(uint128(epochId_ - 1).max(1));
        }
    }
}
