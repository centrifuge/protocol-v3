// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ChainId, ShareClassId, AssetId, Ratio, ItemId, AccountId} from "src/types/Domain.sol";
import {PoolId} from "src/types/PoolId.sol";

import {IAssetManager, IAccounting, IGateway} from "src/interfaces/ICommon.sol";
import {IPoolRegistry} from "src/interfaces/IPoolRegistry.sol";
import {IERC20Metadata} from "src/interfaces/IERC20Metadata.sol";
import {IShareClassManager} from "src/interfaces/IShareClassManager.sol";
import {IItemManager} from "src/interfaces/IItemManager.sol";
import {IAccountingItemManager} from "src/interfaces/IAccountingItemManager.sol";
import {IHoldings} from "src/interfaces/IHoldings.sol";
import {IPoolManager, Escrow} from "src/interfaces/IPoolManager.sol";
import {IMulticall} from "src/interfaces/IMulticall.sol";
import {IERC7726} from "src/interfaces/IERC7726.sol";

import {MathLib} from "src/libraries/MathLib.sol";

import {PoolLocker} from "src/PoolLocker.sol";
import {Auth} from "src/Auth.sol";

contract PoolManager is Auth, PoolLocker, IPoolManager {
    using MathLib for uint256;

    IPoolRegistry immutable poolRegistry;
    IAssetManager immutable assetManager;
    IAccounting immutable accounting;

    IHoldings holdings;
    IGateway gateway;

    /// @dev A requirement for methods that needs to be called by the gateway
    modifier onlyGateway() {
        require(msg.sender == address(gateway), NotAllowed());
        _;
    }

    constructor(
        address owner,
        IMulticall multicall,
        IPoolRegistry poolRegistry_,
        IAssetManager assetManager_,
        IAccounting accounting_,
        IHoldings holdings_,
        IGateway gateway_
    ) Auth(owner) PoolLocker(multicall) {
        poolRegistry = poolRegistry_;
        assetManager = assetManager_;
        accounting = accounting_;
        holdings = holdings_;
        gateway = gateway_;
    }

    function createPool(IERC20Metadata currency, IShareClassManager shareClassManager)
        external
        returns (PoolId poolId)
    {
        // TODO: add fees
        return poolRegistry.registerPool(msg.sender, currency, shareClassManager);
    }

    function allowPool(ChainId chainId) external poolUnlocked {
        // TODO: store somewhere the allowed info?
        gateway.sendAllowPool(chainId, unlockedPoolId());
    }

    function allowShareClass(ChainId chainId, ShareClassId scId) external poolUnlocked {
        // TODO: store somewhere the allowed info?
        gateway.sendAllowShareClass(chainId, unlockedPoolId(), scId);
    }

    function approveDeposit(ShareClassId scId, AssetId assetId, Ratio approvalRatio) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);
        ItemId itemId = holdings.itemIdFromAsset(poolId, scId, assetId);
        IERC7726 valuation = holdings.valuation(poolId, itemId);

        uint128 totalApproved = scm.approveDeposit(poolId, scId, assetId, approvalRatio, valuation);

        assetManager.transferFrom(
            _escrow(poolId, scId, Escrow.PENDING_SHARE_CLASS),
            _escrow(poolId, scId, Escrow.SHARE_CLASS),
            uint256(uint160(AssetId.unwrap(assetId))),
            totalApproved
        );
    }

    function approveRedemption(ShareClassId scId, AssetId assetId, Ratio approvalRatio) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);
        ItemId itemId = holdings.itemIdFromAsset(poolId, scId, assetId);
        IERC7726 valuation = holdings.valuation(poolId, itemId);

        scm.approveDeposit(poolId, scId, assetId, approvalRatio, valuation);
    }

    function issueShares(ShareClassId scId, uint128 nav) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);

        scm.issueShares(poolId, scId, nav);
    }

    function revokeShares(ShareClassId scId, uint128 nav) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);

        scm.revokeShares(poolId, scId, nav);
    }

    function increaseItem(IItemManager im, ItemId itemId, uint128 amount) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IAccountingItemManager.Accounts memory accounts = im.itemAccounts(poolId, itemId);
        uint128 valueChange = im.increase(poolId, itemId, amount);

        accounting.updateEntry(accounts.equity, accounts.asset, valueChange);
    }

    function decreaseItem(IItemManager im, ItemId itemId, uint128 amount) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IAccountingItemManager.Accounts memory accounts = im.itemAccounts(poolId, itemId);
        uint128 valueChange = im.decrease(poolId, itemId, amount);

        accounting.updateEntry(accounts.asset, accounts.equity, valueChange);
    }

    function updateItem(IItemManager im, ItemId itemId) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        int128 diff = im.update(poolId, itemId);

        IAccountingItemManager.Accounts memory accounts = im.itemAccounts(poolId, itemId);
        if (diff > 0) {
            accounting.updateEntry(accounts.asset, accounts.loss, uint128(diff));
        } else if (diff < 0) {
            accounting.updateEntry(accounts.gain, accounts.asset, uint128(-diff));
        }
    }

    function moveOut(ChainId chainId, ShareClassId scId, AssetId assetId, address receiver, uint128 assetAmount)
        external
        poolUnlocked
        returns (uint128 poolAmount)
    {
        PoolId poolId = unlockedPoolId();

        ItemId itemId = holdings.itemIdFromAsset(poolId, scId, assetId);

        assetManager.burn(_escrow(poolId, scId, Escrow.SHARE_CLASS), assetId, assetAmount);

        IERC7726 valuation = holdings.valuation(poolId, itemId);
        poolAmount = valuation.getQuote(
            assetAmount, AssetId.unwrap(assetId), address(poolRegistry.poolCurrencies(poolId))
        ).toUint128();

        gateway.sendUnlockTokens(chainId, assetId, receiver, poolAmount);
    }

    function requestDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, address investor, uint128 amount)
        external
        onlyGateway
    {
        address pendingShareClassEscrow = _escrow(poolId, scId, Escrow.PENDING_SHARE_CLASS);
        assetManager.mint(pendingShareClassEscrow, assetId, amount);

        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);
        scm.requestDeposit(poolId, scId, assetId, investor, amount);
    }

    function requestRedemption(PoolId poolId, ShareClassId scId, AssetId assetId, address investor, uint128 amount)
        external
        onlyGateway
    {
        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);
        scm.requestRedemption(poolId, scId, assetId, investor, amount);
    }

    function lockTokens(AssetId assetId, address recvAddr, uint128 amount) external {
        assetManager.mint(recvAddr, assetId, amount);
    }

    function claimShares(PoolId poolId, ShareClassId scId, AssetId assetId, address investor) external {
        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);

        (uint128 shares, uint128 tokens) = scm.claimShares(poolId, scId, assetId, investor);
        gateway.sendFulfilledDepositRequest(poolId, scId, assetId, investor, shares, tokens);
    }

    function claimTokens(PoolId poolId, ShareClassId scId, AssetId assetId, address investor) external {
        IShareClassManager scm = poolRegistry.shareClassManagers(poolId);

        (uint128 shares, uint128 tokens) = scm.claimShares(poolId, scId, assetId, investor);

        assetManager.burn(_escrow(poolId, scId, Escrow.SHARE_CLASS), assetId, tokens);

        gateway.sendFulfilledRedemptionRequest(poolId, scId, assetId, investor, shares, tokens);
    }

    function _escrow(PoolId poolId, ShareClassId scId, Escrow escrow) private view returns (address) {
        bytes32 key = keccak256(abi.encodePacked(scId, "escrow", escrow));
        return poolRegistry.addresses(poolId, key);
    }

    function _beforeUnlock(PoolId poolId) internal view override {
        require(poolRegistry.poolAdmins(poolId, msg.sender));
    }

    function _beforeLock() internal override {
        accounting.lock(unlockedPoolId());
    }
}
