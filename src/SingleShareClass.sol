// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";

import {Auth} from "src/Auth.sol";
import {IShareClassManager} from "src/interfaces/IShareClassManager.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {D18, d18} from "src/types/D18.sol";
import {PoolId} from "src/types/PoolId.sol";
import {IERC7726Ext} from "src/interfaces/IERC7726.sol";
import {IInvestorPermissions} from "src/interfaces/IInvestorPermissions.sol";
import {IPoolRegistry} from "src/interfaces/IPoolRegistry.sol";

struct Epoch {
    /// @dev Price of one share class per pool token
    D18 shareToPoolQuote;
    /// @dev Valuation used for quotas
    IERC7726Ext valuation;
    /// @dev Amount of approved deposits (in pool denomination)
    uint256 approvedDeposits;
    /// @dev Amount of approved shares (in share denomination)
    uint256 approvedShares;
}

struct EpochRatio {
    /// @dev Percentage of approved redemptions
    D18 redeemRatio;
    /// @dev Percentage of approved deposits
    D18 depositRatio;
    /// @dev Price of one pool currency per asset
    D18 assetToPoolQuote;
}

struct UserOrder {
    /// @dev Index of epoch in which last order was made
    uint32 lastUpdate;
    /// @dev Pending amount
    uint256 pending;
}

// Assumptions:
// * ShareClassId is unique and derived from pool, i.e. bytes16(keccak256(poolId + salt))
contract SingleShareClass is Auth, IShareClassManager {
    using MathLib for uint128;
    using MathLib for uint256;

    /// Storage
    // TODO: Reorder for optimal storage layout
    uint32 private /*TODO: transient*/ _epochIncrement;
    address public immutable poolRegistry;
    address public immutable investorPermissions;
    mapping(PoolId poolId => bytes16) public shareClassIds;
    // User storage
    mapping(bytes16 => mapping(address paymentAssetId => mapping(address investor => UserOrder pending))) public
        depositRequests;
    mapping(bytes16 => mapping(address payoutAssetId => mapping(address investor => UserOrder pending))) public
        redeemRequests;
    // Share class storage
    mapping(bytes16 => mapping(address assetId => bool)) public allowedAssets;
    mapping(bytes16 => mapping(address paymentAssetId => uint256 pending)) public pendingDeposits;
    mapping(bytes16 => mapping(address payoutAssetId => uint256 pending)) public pendingRedemptions;
    // TODO(@review): Check whether needed for accounting. If not, remove
    mapping(bytes16 => uint256 approved) public approvedDeposits;
    mapping(bytes16 => uint256 approved) public approvedRedemptions;
    mapping(bytes16 => uint256 nav) public shareClassNav;
    mapping(bytes16 => uint256) public totalIssuance;
    // Share class + epoch storage
    mapping(PoolId poolId => uint32 epochId) public epochIds;
    mapping(bytes16 => uint32 epochId) latestIssuance;
    mapping(bytes16 => mapping(uint32 epochId => Epoch epoch)) public epochs;
    mapping(bytes16 => mapping(address assetId => uint32 epochId)) latestDepositApproval;
    mapping(bytes16 => mapping(address assetId => uint32 epochId)) latestRevocation;
    mapping(bytes16 => mapping(address assetId => mapping(uint32 epochId => EpochRatio epoch))) public epochRatios;

    /// Errors
    error NegativeNav();
    error Unauthorized();

    constructor(address deployer, address poolRegistry_, address investorPermissions_) Auth(deployer) {
        require(poolRegistry_ != address(0), "Empty poolRegistry");
        require(investorPermissions_ != address(0), "Empty investorPermissions");
        poolRegistry = poolRegistry_;
        investorPermissions = investorPermissions_;
    }

    // TODO(@wischli): Docs
    function setShareClassId(PoolId poolId, bytes16 shareClassId_) external auth {
        shareClassIds[poolId] = shareClassId_;
    }

    /// @inheritdoc IShareClassManager
    function allowAsset(PoolId poolId, bytes16 shareClassId, address assetId) external auth {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        allowedAssets[shareClassId][assetId] = true;

        emit IShareClassManager.AllowedAsset(poolId, shareClassId, assetId);
    }

    /// @inheritdoc IShareClassManager
    function disallowAsset(PoolId poolId, bytes16 shareClassId, address assetId) external auth {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        delete allowedAssets[shareClassId][assetId];

        emit IShareClassManager.DisallowedAsset(poolId, shareClassId, assetId);
    }

    /// @inheritdoc IShareClassManager
    function requestDeposit(
        PoolId poolId,
        bytes16 shareClassId,
        uint256 amount,
        address investor,
        address depositAssetId
    ) external {
        require(allowedAssets[shareClassId][depositAssetId] == true, IShareClassManager.AssetNotAllowed());

        _updateDepositRequest(poolId, shareClassId, int256(amount), investor, depositAssetId);
    }

    function cancelDepositRequest(PoolId poolId, bytes16 shareClassId, address investor, address depositAssetId)
        external
    {
        _updateDepositRequest(
            poolId,
            shareClassId,
            -int256(depositRequests[shareClassId][depositAssetId][investor].pending),
            investor,
            depositAssetId
        );
    }

    /// @inheritdoc IShareClassManager
    function requestRedeem(PoolId poolId, bytes16 shareClassId, uint256 amount, address investor, address payoutAssetId)
        external
    {
        require(allowedAssets[shareClassId][payoutAssetId] == true, IShareClassManager.AssetNotAllowed());

        _updateRedeemRequest(poolId, shareClassId, int256(amount), investor, payoutAssetId);
    }

    /// @inheritdoc IShareClassManager
    function cancelRedeemRequest(PoolId poolId, bytes16 shareClassId, address investor, address payoutAssetId)
        external
    {
        _updateRedeemRequest(
            poolId,
            shareClassId,
            -int256(depositRequests[shareClassId][payoutAssetId][investor].pending),
            investor,
            payoutAssetId
        );
    }

    /// @inheritdoc IShareClassManager
    function approveDeposits(
        PoolId poolId,
        bytes16 shareClassId,
        uint128 approvalRatio,
        address paymentAssetId,
        IERC7726Ext valuation
    ) external auth returns (uint256 approvedPoolAmount, uint256 approvedAssetAmount) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        // Advance epochId if it has not been advanced within this transaction (e.g. in case of multiCall context)
        uint32 approvalEpochId = _advanceEpoch(poolId);

        // Reduce pending
        approvedAssetAmount = d18(approvalRatio).mulUint256(pendingDeposits[shareClassId][paymentAssetId]);
        pendingDeposits[shareClassId][paymentAssetId] -= approvedAssetAmount;
        uint256 pendingDepositsPostUpdate = pendingDeposits[shareClassId][paymentAssetId];

        // Increase approved
        address poolCurrency = address(IPoolRegistry(poolRegistry).poolCurrencies(poolId));
        D18 paymentAssetPrice = d18(valuation.getFactor(paymentAssetId, poolCurrency).toUint128());
        approvedPoolAmount = paymentAssetPrice.mulUint256(approvedAssetAmount);
        approvedDeposits[shareClassId] += approvedPoolAmount;

        // Update epoch data
        Epoch storage epoch = epochs[shareClassId][approvalEpochId];
        epoch.valuation = valuation;
        epoch.approvedDeposits += approvedPoolAmount;

        EpochRatio storage epochRatio = epochRatios[shareClassId][paymentAssetId][approvalEpochId];
        epochRatio.depositRatio = d18(approvalRatio);
        epochRatio.assetToPoolQuote = paymentAssetPrice;

        latestDepositApproval[shareClassId][paymentAssetId] = approvalEpochId;

        emit IShareClassManager.ApprovedDeposits(
            poolId,
            shareClassId,
            approvalEpochId,
            paymentAssetId,
            approvalRatio,
            approvedPoolAmount,
            approvedAssetAmount,
            pendingDepositsPostUpdate,
            paymentAssetPrice.inner()
        );
    }

    /// @inheritdoc IShareClassManager
    function approveRedemptions(
        PoolId poolId,
        bytes16 shareClassId,
        uint128 approvalRatio,
        address payoutAssetId,
        IERC7726Ext valuation
    ) external auth returns (uint256 approvedShares, uint256 pendingShares) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        // Advance epochId if it has not been advanced within this transaction (e.g. in case of multiCall context)
        uint32 approvalEpochId = _advanceEpoch(poolId);

        // Reduce pending
        approvedShares = d18(approvalRatio).mulUint256(pendingRedemptions[shareClassId][payoutAssetId]);
        pendingRedemptions[shareClassId][payoutAssetId] -= approvedShares;
        pendingShares = pendingRedemptions[shareClassId][payoutAssetId];

        // Increase approved
        approvedRedemptions[shareClassId] += approvedShares;
        address poolCurrency = address(IPoolRegistry(poolRegistry).poolCurrencies(poolId));
        D18 payoutAssetPrice = d18(valuation.getFactor(payoutAssetId, poolCurrency).toUint128());

        // Update epoch data
        Epoch storage epoch = epochs[shareClassId][approvalEpochId];
        epoch.valuation = valuation;
        epoch.approvedShares = approvedShares;

        EpochRatio storage epochRatio = epochRatios[shareClassId][payoutAssetId][approvalEpochId];
        epochRatio.redeemRatio = d18(approvalRatio);
        epochRatio.assetToPoolQuote = payoutAssetPrice;

        emit IShareClassManager.ApprovedRedemptions(
            poolId,
            shareClassId,
            approvalEpochId,
            payoutAssetId,
            approvalRatio,
            approvedShares,
            pendingShares,
            payoutAssetPrice.inner()
        );
    }

    /// @inheritdoc IShareClassManager
    function issueShares(PoolId poolId, bytes16 shareClassId, uint256 nav) external auth {
        this.issueSharesUntilEpoch(poolId, shareClassId, nav, epochIds[poolId]);
    }

    /// @notice Emits new shares for the given identifier based on the provided NAV up to the desired epoch.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param nav Total value of assets of the pool and share class
    /// @param endEpochId Identifier of the maximum epoch until which shares are issued
    function issueSharesUntilEpoch(PoolId poolId, bytes16 shareClassId, uint256 nav, uint32 endEpochId) external auth {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(endEpochId <= epochIds[poolId], IShareClassManager.EpochNotFound(epochIds[poolId]));

        uint32 startEpochId = latestIssuance[shareClassId];
        for (uint32 epochId = startEpochId; epochId < endEpochId; epochId++) {
            uint256 newShares = _issueEpochShares(poolId, shareClassId, nav, epochId);

            emit IShareClassManager.IssuedShares(poolId, shareClassId, epochId, nav, newShares);
        }

        latestIssuance[shareClassId] = endEpochId;
    }

    /// @inheritdoc IShareClassManager
    function revokeShares(PoolId poolId, bytes16 shareClassId, address payoutAssetId, uint256 nav)
        external
        auth
        returns (uint256 payoutAssetAmount, uint256 payoutPoolAmount)
    {
        return this.revokeSharesUntilEpoch(poolId, shareClassId, payoutAssetId, nav, epochIds[poolId]);
    }

    /// @notice Revokes shares for an epoch span and sets the price based on amount of approved redemption shares and
    /// the
    /// provided NAV.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param payoutAssetId Identifier of the payout asset
    /// @param nav Total value of assets of the pool and share class
    /// @param endEpochId Identifier of the maximum epoch until which shares are revoked
    /// @return payoutAssetAmount Converted amount of payout asset based on number of revoked shares
    /// @return payoutPoolAmount Converted amount of pool currency based on number of revoked shares
    function revokeSharesUntilEpoch(
        PoolId poolId,
        bytes16 shareClassId,
        address payoutAssetId,
        uint256 nav,
        uint32 endEpochId
    ) external auth returns (uint256 payoutAssetAmount, uint256 payoutPoolAmount) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(endEpochId <= epochIds[poolId], IShareClassManager.EpochNotFound(epochIds[poolId]));

        uint32 startEpochId = latestRevocation[shareClassId][payoutAssetId];
        for (uint32 epochId = startEpochId; epochId < endEpochId; epochId++) {
            (uint256 revokedShares, uint256 epochPoolAmount) = _revokeEpochShares(poolId, shareClassId, nav, epochId);
            payoutPoolAmount += epochPoolAmount;

            // TODO(@wischli): Ensure correct decimals in tests
            payoutAssetAmount +=
                epochPoolAmount.mulDiv(1e18, epochRatios[shareClassId][payoutAssetId][epochId].assetToPoolQuote.inner());

            emit IShareClassManager.RevokedShares(poolId, shareClassId, epochId, nav, revokedShares);
        }

        latestRevocation[shareClassId][payoutAssetId] = endEpochId;
    }

    /// @inheritdoc IShareClassManager
    function claimDeposit(PoolId poolId, bytes16 shareClassId, address investor, address depositAssetId)
        external
        returns (uint256 payoutShareAmount, uint256 paymentAssetAmount)
    {
        return this.claimDepositUntilEpoch(poolId, shareClassId, investor, depositAssetId, latestIssuance[shareClassId]);
    }

    /// @notice Collects shares for an investor after their deposit request was (partially) approved and new shares were
    /// issued until the provided epoch.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param investor Address of the recipient of the share class tokens
    /// @param depositAssetId Identifier of the asset which the investor used for their deposit request
    /// @param endEpochId Identifier of the maximum epoch until it is claimed claim
    /// @return payoutShareAmount Amount of shares which the investor receives
    /// @return paymentAssetAmount Amount of deposit asset which was taken as payment
    function claimDepositUntilEpoch(
        PoolId poolId,
        bytes16 shareClassId,
        address investor,
        address depositAssetId,
        uint32 endEpochId
    ) external returns (uint256 payoutShareAmount, uint256 paymentAssetAmount) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(endEpochId < epochIds[poolId], IShareClassManager.EpochNotFound(epochIds[poolId]));

        UserOrder storage userOrder = depositRequests[shareClassId][depositAssetId][investor];

        for (uint32 epochId = userOrder.lastUpdate; epochId <= endEpochId; epochId++) {
            (uint256 approvedAssetAmount, uint256 pendingAssetAmount, uint256 investorShares) =
                _claimEpochDeposit(shareClassId, depositAssetId, userOrder, epochId);
            payoutShareAmount += investorShares;
            paymentAssetAmount += approvedAssetAmount;

            userOrder.pending -= approvedAssetAmount;

            emit IShareClassManager.ClaimedDeposit(
                poolId,
                shareClassId,
                epochId,
                investor,
                depositAssetId,
                approvedAssetAmount,
                pendingAssetAmount,
                investorShares
            );
        }

        userOrder.lastUpdate = endEpochId;
    }

    /// @inheritdoc IShareClassManager
    function claimRedeem(PoolId poolId, bytes16 shareClassId, address investor, address payoutAssetId)
        external
        returns (uint256 payoutAssetAmount, uint256 paymentShareAmount)
    {
        return this.claimRedeemUntilEpoch(poolId, shareClassId, investor, payoutAssetId, latestIssuance[shareClassId]);
    }

    /// @notice Reduces the share class token count of the investor in exchange for collecting an amount of payment
    /// asset for the specified range of epochs.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param investor Address of the recipient of the payout asset
    /// @param payoutAssetId Identifier of the asset which the investor committed to as payout when requesting the
    /// redemption
    /// @param endEpochId Identifier of the maximum epoch until it is claimed claim
    /// @return payoutAssetAmount Amount of payout asset which the investor receives
    /// @return paymentShareAmount Amount of shares which the investor redeemed
    function claimRedeemUntilEpoch(
        PoolId poolId,
        bytes16 shareClassId,
        address investor,
        address payoutAssetId,
        uint32 endEpochId
    ) external returns (uint256 payoutAssetAmount, uint256 paymentShareAmount) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(endEpochId < epochIds[poolId], IShareClassManager.EpochNotFound(epochIds[poolId]));

        UserOrder storage userOrder = redeemRequests[shareClassId][payoutAssetId][investor];

        for (uint32 epochId = userOrder.lastUpdate; epochId <= endEpochId; epochId++) {
            (uint256 approvedShares, uint256 pendingShares, uint256 approvedAssetAmount) =
                _claimEpochRedeem(shareClassId, payoutAssetId, userOrder, epochId);
            paymentShareAmount += approvedShares;
            payoutAssetAmount += approvedAssetAmount;

            userOrder.pending -= approvedShares;

            emit IShareClassManager.ClaimedRedeem(
                poolId, shareClassId, epochId, investor, payoutAssetId, approvedShares, pendingShares, payoutAssetAmount
            );
        }

        userOrder.lastUpdate = endEpochId;
    }

    /// @inheritdoc IShareClassManager
    function updateShareClassNav(PoolId poolId, bytes16 shareClassId, int256 navCorrection)
        external
        auth
        returns (uint256 nav)
    {
        require(navCorrection >= 0, NegativeNav());
        return this.updateShareClassNav(poolId, shareClassId, uint256(navCorrection));
    }

    function updateShareClassNav(PoolId poolId, bytes16 shareClassId, uint256 nav) external auth returns (uint256) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        shareClassNav[shareClassId] = nav;
        emit IShareClassManager.UpdatedNav(poolId, shareClassId, nav);

        return nav;
    }

    /// @inheritdoc IShareClassManager
    function addShareClass(PoolId, /*poolId*/ bytes memory /*_data*/ ) external pure returns (bytes16) {
        revert IShareClassManager.MaxShareClassNumberExceeded(1);
    }

    /// @inheritdoc IShareClassManager
    function isAllowedAsset(PoolId poolId, bytes16 shareClassId, address assetId) external view returns (bool) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        return allowedAssets[shareClassId][assetId];
    }

    /// @inheritdoc IShareClassManager
    function getShareClassNav(PoolId poolId, bytes16 shareClassId) external view returns (uint256 nav) {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));

        return shareClassNav[shareClassId];
    }

    /// @notice Updates the amount of a request to deposit (exchange) an asset amount for share class tokens.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param amount Asset token amount which is updated
    /// @param investor Address of the entity which is depositing
    /// @param depositAssetId Identifier of the asset which the investor used for their deposit request
    function _updateDepositRequest(
        PoolId poolId,
        bytes16 shareClassId,
        int256 amount,
        address investor,
        address depositAssetId
    ) private {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(IInvestorPermissions(investorPermissions).isUnfrozenInvestor(shareClassId, investor), Unauthorized());

        UserOrder storage userOrder = depositRequests[shareClassId][depositAssetId][investor];

        // Block updates until pending amount does not impact claimable amount
        uint32 latestDepositApproval_ = latestDepositApproval[shareClassId][depositAssetId];
        require(
            latestDepositApproval_ == 0 || userOrder.lastUpdate > latestDepositApproval_,
            IShareClassManager.ClaimDepositRequired()
        );
        // FIXME: Use issuance counter as well because approval does not imply claiming is possible
        // If issueShares is per assetId, this is fixed by using latestIssuance[shareClassId][depositAsset]

        userOrder.lastUpdate = epochIds[poolId];
        userOrder.pending = amount >= 0 ? userOrder.pending + uint256(amount) : userOrder.pending - uint256(-amount);

        pendingDeposits[shareClassId][depositAssetId] = amount >= 0
            ? pendingDeposits[shareClassId][depositAssetId] + uint256(amount)
            : pendingDeposits[shareClassId][depositAssetId] - uint256(-amount);

        emit IShareClassManager.UpdatedDepositRequest(
            poolId,
            shareClassId,
            epochIds[poolId],
            investor,
            depositAssetId,
            userOrder.pending,
            pendingDeposits[shareClassId][depositAssetId]
        );
    }

    // TODO(@wischli): Docs
    function _updateRedeemRequest(
        PoolId poolId,
        bytes16 shareClassId,
        int256 amount,
        address investor,
        address payoutAssetId
    ) private {
        require(shareClassIds[poolId] == shareClassId, IShareClassManager.ShareClassMismatch(shareClassIds[poolId]));
        require(IInvestorPermissions(investorPermissions).isUnfrozenInvestor(shareClassId, investor), Unauthorized());

        UserOrder storage userOrder = redeemRequests[shareClassId][payoutAssetId][investor];

        // Block updates until pending amount does not impact claimable amount
        uint32 latestRevocation_ = latestRevocation[shareClassId][payoutAssetId];
        require(
            latestRevocation_ == 0 || userOrder.lastUpdate > latestRevocation_, IShareClassManager.ClaimRedeemRequired()
        );

        userOrder.lastUpdate = epochIds[poolId];
        userOrder.pending = amount >= 0 ? userOrder.pending + uint256(amount) : userOrder.pending - uint256(-amount);

        pendingRedemptions[shareClassId][payoutAssetId] = amount >= 0
            ? pendingRedemptions[shareClassId][payoutAssetId] + uint256(amount)
            : pendingRedemptions[shareClassId][payoutAssetId] - uint256(-amount);

        emit IShareClassManager.UpdatedRedeemRequest(
            poolId,
            shareClassId,
            epochIds[poolId],
            investor,
            payoutAssetId,
            userOrder.pending,
            pendingRedemptions[shareClassId][payoutAssetId]
        );
    }

    /// @notice Emits new shares and sets price for the given identifier based on the provided NAV for the desired
    /// epoch.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param nav Total value of assets of the pool and share class
    /// @param epochId Identifier of the epoch for which shares are issued
    function _issueEpochShares(PoolId poolId, bytes16 shareClassId, uint256 nav, uint32 epochId)
        private
        returns (uint256 newShares)
    {
        Epoch storage epoch = epochs[shareClassId][epochId];
        // TODO(@review): Is it feasible to assume we feed quotes for pool currency to all share class tokens?
        D18 shareToPoolQuote = d18(
            (
                epoch.valuation.getQuote(
                    nav, address(IPoolRegistry(poolRegistry).poolCurrencies(poolId)), address(bytes20(shareClassId))
                ) / totalIssuance[shareClassId]
            ).toUint128()
        );
        newShares = shareToPoolQuote.mulUint256(epoch.approvedDeposits);

        epoch.shareToPoolQuote = shareToPoolQuote;
        totalIssuance[shareClassId] += newShares;
    }

    /// @notice Revokes shares for an epoch and sets the price based on amount of approved redemption shares and the
    /// provided NAV.
    ///
    /// @param poolId Identifier of the pool
    /// @param shareClassId Identifier of the share class
    /// @param nav Total value of assets of the pool and share class
    /// @param epochId Identifier of the epoch for which shares are revoked
    /// @return revokedShares Amount of shares which were approved for revocation
    /// @return payoutPoolAmount Converted amount of pool currency based on number of revoked shares
    function _revokeEpochShares(PoolId poolId, bytes16 shareClassId, uint256 nav, uint32 epochId)
        private
        returns (uint256 revokedShares, uint256 payoutPoolAmount)
    {
        Epoch storage epoch = epochs[shareClassId][epochId];
        // TODO(@wischli): Ensure double spending not possible
        epoch.shareToPoolQuote = d18(
            (
                epoch.valuation.getQuote(
                    nav, address(IPoolRegistry(poolRegistry).poolCurrencies(poolId)), address(bytes20(shareClassId))
                ) / totalIssuance[shareClassId]
            ).toUint128()
        );

        totalIssuance[shareClassId] -= epoch.approvedShares;
        payoutPoolAmount = epoch.shareToPoolQuote.mulUint256(epoch.approvedShares);

        return (epoch.approvedShares, payoutPoolAmount);
    }

    /// @notice Increments the given epoch id if it has not been incremented within the current block. If the epoch has
    /// already been bumped, we don't bump it again to allow deposit and redeem approvals to point to the same epoch id.
    ///
    /// @param epochId Identifier of the epoch which we want to increment.
    // TODO(@wischli): Fix
    /// @return checkEpochId Potentially incremented epoch identifier.
    /// @return newEpochId Potentially incremented epoch identifier.
    function _incrementEpoch(uint32 epochId) private returns (uint32 checkEpochId, uint32 newEpochId) {
        // FIXME: 2x approval in same block should write epochs[SAME_ID] instead of epochs[x] and epochs[x+1]
        if (_epochIncrement == 0) {
            _epochIncrement = 1;
            newEpochId = epochId + _epochIncrement;
            return (newEpochId, newEpochId);
        } else {
            return (epochId > 0 ? epochId - 1 : 0, epochId);
        }
    }

    function _advanceEpoch(PoolId poolId) private returns (uint32 epochIdCurrentBlock) {
        uint32 epochId = epochIds[poolId];

        // Epoch doesn't necessarily advance, e.g. in case of multiple approvals inside the same multiCall
        if (_epochIncrement == 0) {
            _epochIncrement = 1;
            epochIds[poolId] += 1;

            emit IShareClassManager.NewEpoch(poolId, epochId + 1);

            return epochId;
        } else {
            return epochId > 0 ? epochId - 1 : 0;
        }
    }

    /// @notice Collects shares for an investor after their deposit request was (partially) approved and new shares were
    /// issued until the provided epoch.
    ///
    /// @param shareClassId Identifier of the share class
    /// @param userOrder Pending order of the investor
    /// @param depositAssetId Identifier of the asset which the investor used for their deposit request
    /// @param epochId Identifier of the  epoch for which it is claimed
    /// @return approvedAssetAmount Amount of deposit asset which was approved and taken as payment
    /// @return pendingAssetAmount Amount of deposit asset which was is pending for approval
    /// @return investorShares Amount of shares which the investor receives
    function _claimEpochDeposit(
        bytes16 shareClassId,
        address depositAssetId,
        UserOrder storage userOrder,
        uint32 epochId
    ) private view returns (uint256 approvedAssetAmount, uint256 pendingAssetAmount, uint256 investorShares) {
        EpochRatio memory epochRatio = epochRatios[shareClassId][depositAssetId][epochId];

        approvedAssetAmount = epochRatio.depositRatio.mulUint256(userOrder.pending);

        D18 shareClassTokenToAssetQuote = epochs[shareClassId][epochId].shareToPoolQuote / epochRatio.assetToPoolQuote;
        investorShares = shareClassTokenToAssetQuote.mulUint256(approvedAssetAmount);

        return (approvedAssetAmount, userOrder.pending, investorShares);
    }

    /// @notice Reduces the share class token count of the investor in exchange for collecting an amount of payment
    /// asset for the specified epoch.
    ///
    /// @param shareClassId Identifier of the share class
    /// @param userOrder Pending order of the investor
    /// @param depositAssetId Identifier of the asset which the investor desires to receive
    /// @param epochId Identifier of the epoch for which it is claimed
    /// @return approvedShares Amount of shares which the investor redeemed
    /// @return pendingShares Amount of shares which are still pending for redemption
    /// @return approvedAssetAmount Amount of payout asset which the investor received
    function _claimEpochRedeem(
        bytes16 shareClassId,
        address depositAssetId,
        UserOrder storage userOrder,
        uint32 epochId
    ) private view returns (uint256 approvedShares, uint256 pendingShares, uint256 approvedAssetAmount) {
        EpochRatio memory epochRatio = epochRatios[shareClassId][depositAssetId][epochId];

        approvedShares = epochRatio.redeemRatio.mulUint256(userOrder.pending);

        // assetAmount = poolAmount / assetToPoolQuote
        approvedAssetAmount = epochs[shareClassId][epochId].shareToPoolQuote.mulUint256(approvedShares).mulDiv(
            1e18, epochRatio.assetToPoolQuote.inner()
        );

        return (approvedShares, userOrder.pending, approvedAssetAmount);
    }
}
