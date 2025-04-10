// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {IAuth} from "src/misc/interfaces/IAuth.sol";
import {SafeTransferLib} from "src/misc/libraries/SafeTransferLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IERC6909} from "src/misc/interfaces/IERC6909.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {IERC20} from "src/misc/interfaces/IERC20.sol";
import {Recoverable} from "src/misc/Recoverable.sol";

import {IGateway} from "src/common/interfaces/IGateway.sol";
import {MessageLib, UpdateContractType} from "src/common/libraries/MessageLib.sol";
import {JournalEntry, Meta} from "src/common/libraries/JournalEntryLib.sol";
import {IVaultMessageSender} from "../common/interfaces/IGatewaySenders.sol";
import {IBalanceSheetGatewayHandler} from "src/common/interfaces/IGatewayHandlers.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";

import {IPoolManager} from "src/vaults/interfaces/IPoolManager.sol";
import {IBalanceSheet} from "src/vaults/interfaces/IBalanceSheet.sol";
import {IPerPoolEscrow} from "src/vaults/interfaces/IEscrow.sol";
import {IUpdateContract} from "src/vaults/interfaces/IUpdateContract.sol";
import {ISharePriceProvider, Prices} from "src/vaults/interfaces/investments/ISharePriceProvider.sol";
import {IShareToken} from "src/vaults/interfaces/token/IShareToken.sol";

contract BalanceSheet is Auth, Recoverable, IBalanceSheet, IBalanceSheetGatewayHandler, IUpdateContract {
    using MathLib for *;
    using CastLib for bytes32;

    IPerPoolEscrow public immutable escrow;

    IGateway public gateway;
    IPoolManager public poolManager;
    IVaultMessageSender public sender;
    ISharePriceProvider public sharePriceProvider;

    mapping(PoolId => mapping(ShareClassId => mapping(address => bool))) public permission;

    constructor(address escrow_) Auth(msg.sender) {
        escrow = IPerPoolEscrow(escrow_);
    }

    /// @dev Check if the msg.sender has permissions
    modifier authOrPermission(PoolId poolId, ShareClassId scId) {
        require(wards[msg.sender] == 1 || permission[poolId][scId][msg.sender], IAuth.NotAuthorized());
        _;
    }

    // --- Administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = IGateway(data);
        else if (what == "poolManager") poolManager = IPoolManager(data);
        else if (what == "sender") sender = IVaultMessageSender(data);
        else if (what == "sharePriceProvider") sharePriceProvider = ISharePriceProvider(data);
        else revert("BalanceSheet/file-unrecognized-param");
        emit File(what, data);
    }

    /// --- IUpdateContract Implementation ---
    function update(uint64 poolId_, bytes16 scId_, bytes calldata payload) external auth {
        uint8 kind = uint8(MessageLib.updateContractType(payload));

        if (kind == uint8(UpdateContractType.Permission)) {
            MessageLib.UpdateContractPermission memory m = MessageLib.deserializeUpdateContractPermission(payload);

            PoolId poolId = PoolId.wrap(poolId_);
            ShareClassId scId = ShareClassId.wrap(scId_);
            address who = m.who.toAddress();

            permission[poolId][scId][who] = m.allowed;

            emit Permission(poolId, scId, who, m.allowed);
        } else {
            revert("BalanceSheet/unknown-update-contract-type");
        }
    }

    /// --- External ---
    /// @inheritdoc IBalanceSheet
    function deposit(
        PoolId poolId,
        ShareClassId scId,
        address asset,
        uint256 tokenId,
        address provider,
        uint128 amount,
        D18 pricePoolPerAsset,
        Meta calldata m
    ) external authOrPermission(poolId, scId) {
        _deposit(
            poolId,
            scId,
            AssetId.wrap(poolManager.assetToId(asset, tokenId)),
            asset,
            tokenId,
            provider,
            amount,
            pricePoolPerAsset,
            m
        );
    }

    /// @inheritdoc IBalanceSheet
    function withdraw(
        PoolId poolId,
        ShareClassId scId,
        address asset,
        uint256 tokenId,
        address receiver,
        uint128 amount,
        D18 pricePoolPerAsset,
        Meta calldata m
    ) external authOrPermission(poolId, scId) {
        _withdraw(
            poolId,
            scId,
            AssetId.wrap(poolManager.assetToId(asset, tokenId)),
            asset,
            tokenId,
            receiver,
            amount,
            pricePoolPerAsset,
            m
        );
    }

    /// @inheritdoc IBalanceSheet
    function updateValue(PoolId poolId, ShareClassId scId, address asset, uint256 tokenId, D18 pricePoolPerAsset)
        external
        auth
    {
        uint128 assetId = poolManager.assetToId(asset, tokenId);
        sender.sendUpdateHoldingValue(poolId, scId, AssetId.wrap(assetId), pricePoolPerAsset);
        emit UpdateValue(poolId, scId, asset, tokenId, pricePoolPerAsset, uint64(block.timestamp));
    }

    /// @inheritdoc IBalanceSheet
    function revoke(PoolId poolId, ShareClassId scId, address from, D18 pricePoolPerShare, uint128 shares)
        external
        authOrPermission(poolId, scId)
    {
        _revoke(poolId, scId, from, pricePoolPerShare, shares);
    }

    /// @inheritdoc IBalanceSheet
    function issue(PoolId poolId, ShareClassId scId, address to, D18 pricePoolPerShare, uint128 shares)
        external
        authOrPermission(poolId, scId)
    {
        _issue(poolId, scId, to, pricePoolPerShare, shares);
    }

    /// @inheritdoc IBalanceSheet
    function journalEntry(PoolId poolId, ShareClassId scId, Meta calldata m) external authOrPermission(poolId, scId) {
        // We do not need to ensure the meta here. Could be part of a batch and does not have to be balanced
        sender.sendJournalEntry(poolId, m.debits, m.credits);
        emit UpdateEntry(poolId, scId, m.debits, m.credits);
    }

    /// --- IBalanceSheetHandler ---
    /// @inheritdoc IBalanceSheetGatewayHandler
    function triggerDeposit(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address provider,
        uint128 amount,
        D18 priceAssetPerShare,
        Meta calldata m
    ) external auth {
        (address asset, uint256 tokenId) = poolManager.idToAsset(assetId.raw());

        _deposit(poolId, scId, assetId, asset, tokenId, provider, amount, priceAssetPerShare, m);
    }

    /// @inheritdoc IBalanceSheetGatewayHandler
    function triggerWithdraw(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address receiver,
        uint128 amount,
        D18 priceAssetPerShare,
        Meta calldata m
    ) external auth {
        (address asset, uint256 tokenId) = poolManager.idToAsset(assetId.raw());
        _withdraw(poolId, scId, assetId, asset, tokenId, receiver, amount, priceAssetPerShare, m);
    }

    /// @inheritdoc IBalanceSheetGatewayHandler
    function triggerIssueShares(PoolId poolId, ShareClassId scId, address to, D18 pricePoolPerShare, uint128 shares)
        external
        auth
    {
        _issue(poolId, scId, to, pricePoolPerShare, shares);
    }

    /// @inheritdoc IBalanceSheetGatewayHandler
    function triggerRevokeShares(PoolId poolId, ShareClassId scId, address from, D18 pricePoolPerShare, uint128 shares)
        external
        auth
    {
        _revoke(poolId, scId, from, pricePoolPerShare, shares);
    }

    /// @inheritdoc IBalanceSheetGatewayHandler
    function approvedDeposits(PoolId poolId, ShareClassId scId, AssetId assetId, uint128 assetAmount) external auth {
        (address asset, uint256 tokenId) = poolManager.idToAsset(assetId.raw());
        Prices memory prices = sharePriceProvider.prices(poolId.raw(), scId.raw(), assetId.raw(), asset, tokenId);

        JournalEntry[] memory journalEntries = new JournalEntry[](0);
        Meta memory meta = Meta(journalEntries, journalEntries);

        escrow.deposit(asset, tokenId, poolId.raw(), scId.raw(), assetAmount);
        sender.sendUpdateHoldingAmount(
            poolId, scId, assetId, address(escrow), assetAmount, prices.poolPerAsset, true, meta
        );
    }

    /// @inheritdoc IBalanceSheetGatewayHandler
    function revokedShares(PoolId poolId, ShareClassId scId, AssetId assetId, uint128 assetAmount) external auth {
        (address asset, uint256 tokenId) = poolManager.idToAsset(assetId.raw());
        escrow.reserveIncrease(asset, tokenId, poolId.raw(), scId.raw(), assetAmount);
    }

    // --- Internal ---
    function _issue(PoolId poolId, ShareClassId scId, address to, D18 pricePoolPerShare, uint128 shares) internal {
        address token = poolManager.shareToken(poolId.raw(), scId.raw());
        IShareToken(token).mint(address(to), shares);

        sender.sendUpdateShares(poolId, scId, to, pricePoolPerShare, shares, true);
        emit Issue(poolId, scId, to, pricePoolPerShare, shares);
    }

    function _revoke(PoolId poolId, ShareClassId scId, address from, D18 pricePoolPerShare, uint128 shares) internal {
        address token = poolManager.shareToken(poolId.raw(), scId.raw());
        IShareToken(token).burn(address(from), shares);

        sender.sendUpdateShares(poolId, scId, from, pricePoolPerShare, shares, false);
        emit Revoke(poolId, scId, from, pricePoolPerShare, shares);
    }

    function _withdraw(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address asset,
        uint256 tokenId,
        address receiver,
        uint128 amount,
        D18 pricePoolPerAsset,
        Meta calldata m
    ) internal {
        _ensureBalancedEntries(pricePoolPerAsset.mulUint128(amount), m);
        escrow.withdraw(asset, tokenId, poolId.raw(), scId.raw(), amount);

        if (tokenId == 0) {
            SafeTransferLib.safeTransferFrom(asset, address(escrow), receiver, amount);
        } else {
            IERC6909(asset).transferFrom(address(escrow), receiver, tokenId, amount);
        }

        sender.sendUpdateHoldingAmount(poolId, scId, assetId, receiver, amount, pricePoolPerAsset, true, m);

        emit Withdraw(
            poolId,
            scId,
            asset,
            tokenId,
            receiver,
            amount,
            pricePoolPerAsset,
            uint64(block.timestamp),
            m.debits,
            m.credits
        );
    }

    function _deposit(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        address asset,
        uint256 tokenId,
        address provider,
        uint128 amount,
        D18 pricePoolPerAsset,
        Meta calldata m
    ) internal {
        _ensureBalancedEntries(pricePoolPerAsset.mulUint128(amount), m);
        escrow.pendingDepositIncrease(asset, tokenId, poolId.raw(), scId.raw(), amount);

        if (tokenId == 0) {
            SafeTransferLib.safeTransferFrom(asset, provider, address(escrow), amount);
        } else {
            IERC6909(asset).transferFrom(provider, address(escrow), tokenId, amount);
        }

        escrow.deposit(asset, tokenId, poolId.raw(), scId.raw(), amount);
        sender.sendUpdateHoldingAmount(poolId, scId, assetId, provider, amount, pricePoolPerAsset, false, m);

        emit Deposit(
            poolId,
            scId,
            asset,
            tokenId,
            provider,
            amount,
            pricePoolPerAsset,
            uint64(block.timestamp),
            m.debits,
            m.credits
        );
    }

    function _ensureBalancedEntries(uint128 amount, Meta calldata m) internal pure {
        uint128 totalDebits;
        uint128 totalCredits;

        for (uint256 i = 0; i < m.debits.length; i++) {
            totalDebits += m.debits[i].amount;
        }

        for (uint256 i = 0; i < m.credits.length; i++) {
            totalCredits += m.credits[i].amount;
        }

        require(totalDebits <= amount && totalCredits <= amount, EntriesUnbalanced());
    }
}
