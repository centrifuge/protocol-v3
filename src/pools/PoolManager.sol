// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18} from "src/misc/types/D18.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IMulticall} from "src/misc/interfaces/IMulticall.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {Auth} from "src/misc/Auth.sol";

import {ShareClassId} from "src/pools/types/ShareClassId.sol";
import {AssetId} from "src/pools/types/AssetId.sol";
import {AccountId, newAccountId} from "src/pools/types/AccountId.sol";
import {PoolId} from "src/pools/types/PoolId.sol";
import {IAccounting} from "src/pools/interfaces/IAccounting.sol";
import {IGateway} from "src/pools/interfaces/IGateway.sol";
import {IPoolRegistry} from "src/pools/interfaces/IPoolRegistry.sol";
import {IAssetRegistry} from "src/pools/interfaces/IAssetRegistry.sol";
import {IShareClassManager} from "src/pools/interfaces/IShareClassManager.sol";
import {IHoldings} from "src/pools/interfaces/IHoldings.sol";
import {
    IPoolManager,
    IPoolManagerAdminMethods,
    IPoolManagerHandler,
    EscrowId,
    AccountType
} from "src/pools/interfaces/IPoolManager.sol";
import {PoolLocker} from "src/pools/PoolLocker.sol";

// @inheritdoc IPoolManager
contract PoolManager is Auth, PoolLocker, IPoolManager, IPoolManagerHandler {
    using MathLib for uint256;
    using CastLib for bytes;
    using CastLib for bytes32;
    using CastLib for address;

    IPoolRegistry public poolRegistry;
    IAssetRegistry public assetRegistry;
    IAccounting public accounting;
    IHoldings public holdings;
    IGateway public gateway;

    /// @dev A requirement for methods that needs to be called by the gateway
    modifier onlyGateway() {
        require(msg.sender == address(gateway), NotGateway());
        _;
    }

    constructor(
        IMulticall multicall,
        IPoolRegistry poolRegistry_,
        IAssetRegistry assetRegistry_,
        IAccounting accounting_,
        IHoldings holdings_,
        IGateway gateway_,
        address deployer
    ) Auth(deployer) PoolLocker(multicall) {
        poolRegistry = poolRegistry_;
        assetRegistry = assetRegistry_;
        accounting = accounting_;
        holdings = holdings_;
        gateway = gateway_;
    }

    //----------------------------------------------------------------------------------------------
    // Deployer methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IPoolManager
    function file(bytes32 what, address data) external auth {
        if (what == "gateway") gateway = IGateway(data);
        else if (what == "holdings") holdings = IHoldings(data);
        else if (what == "poolRegistry") poolRegistry = IPoolRegistry(data);
        else if (what == "assetRegistry") assetRegistry = IAssetRegistry(data);
        else if (what == "accounting") accounting = IAccounting(data);
        else revert FileUnrecognizedWhat();

        emit File(what, data);
    }

    //----------------------------------------------------------------------------------------------
    // Permisionless methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IPoolManager
    function createPool(AssetId currency, IShareClassManager shareClassManager) external returns (PoolId poolId) {
        // TODO: add fees
        return poolRegistry.registerPool(msg.sender, currency, shareClassManager);
    }

    /// @inheritdoc IPoolManager
    function claimDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) external {
        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        (uint128 shares, uint128 tokens) = scm.claimDeposit(poolId, scId, investor, assetId);
        gateway.sendFulfilledDepositRequest(poolId, scId, assetId, investor, shares, tokens);
    }

    /// @inheritdoc IPoolManager
    function claimRedeem(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) external {
        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        (uint128 shares, uint128 tokens) = scm.claimRedeem(poolId, scId, investor, assetId);

        assetRegistry.burn(escrow(poolId, scId, EscrowId.PENDING_SHARE_CLASS), assetId.raw(), tokens);

        gateway.sendFulfilledRedeemRequest(poolId, scId, assetId, investor, shares, tokens);
    }

    //----------------------------------------------------------------------------------------------
    // Pool admin methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IPoolManagerAdminMethods
    function notifyPool(uint32 chainId) external poolUnlocked {
        gateway.sendNotifyPool(chainId, unlockedPoolId());
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function notifyShareClass(uint32 chainId, ShareClassId scId) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        require(scm.exists(poolId, scId), IShareClassManager.ShareClassNotFound());

        gateway.sendNotifyShareClass(
            chainId,
            poolId,
            scId,
            string("TODO"),
            string("TODO"),
            assetRegistry.decimals(poolRegistry.currency(poolId).raw()),
            bytes32("TODO")
        );
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function setPoolMetadata(bytes calldata metadata) external poolUnlocked {
        poolRegistry.setMetadata(unlockedPoolId(), metadata);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function allowPoolAdmin(address account, bool allow) external poolUnlocked {
        poolRegistry.updateAdmin(unlockedPoolId(), account, allow);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function allowInvestorAsset(ShareClassId scId, AssetId assetId, bool allow) external poolUnlocked {
        PoolId poolId = unlockedPoolId();
        require(holdings.exists(poolId, scId, assetId), IHoldings.HoldingNotFound());

        poolRegistry.allowInvestorAsset(poolId, assetId, allow);

        gateway.sendNotifyAllowedAsset(poolId, scId, assetId, poolRegistry.isInvestorAssetAllowed(poolId, assetId));
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function addShareClass(bytes calldata data) external poolUnlocked returns (ShareClassId) {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        return scm.addShareClass(poolId, data);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function approveDeposits(ShareClassId scId, AssetId paymentAssetId, D18 approvalRatio, IERC7726 valuation)
        external
        poolUnlocked
    {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        (uint128 approvedAssetAmount,) = scm.approveDeposits(poolId, scId, approvalRatio, paymentAssetId, valuation);

        assetRegistry.authTransferFrom(
            escrow(poolId, scId, EscrowId.PENDING_SHARE_CLASS),
            escrow(poolId, scId, EscrowId.SHARE_CLASS),
            uint256(uint160(AssetId.unwrap(paymentAssetId))),
            approvedAssetAmount
        );

        increaseHolding(scId, paymentAssetId, valuation, approvedAssetAmount);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function approveRedeems(ShareClassId scId, AssetId payoutAssetId, D18 approvalRatio) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        scm.approveRedeems(poolId, scId, approvalRatio, payoutAssetId);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function issueShares(ShareClassId scId, AssetId depositAssetId, D18 navPerShare) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        scm.issueShares(poolId, scId, depositAssetId, navPerShare);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function revokeShares(ShareClassId scId, AssetId payoutAssetId, D18 navPerShare, IERC7726 valuation)
        external
        poolUnlocked
    {
        PoolId poolId = unlockedPoolId();

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);

        (uint128 payoutAssetAmount,) = scm.revokeShares(poolId, scId, payoutAssetId, navPerShare, valuation);

        assetRegistry.authTransferFrom(
            escrow(poolId, scId, EscrowId.SHARE_CLASS),
            escrow(poolId, scId, EscrowId.PENDING_SHARE_CLASS),
            uint256(uint160(AssetId.unwrap(payoutAssetId))),
            payoutAssetAmount
        );

        decreaseHolding(scId, payoutAssetId, valuation, payoutAssetAmount);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function createHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint24 prefix)
        external
        poolUnlocked
    {
        require(assetRegistry.isRegistered(assetId), IAssetRegistry.AssetNotFound());

        AccountId[] memory accounts = new AccountId[](4);
        accounts[0] = newAccountId(prefix, uint8(AccountType.ASSET));
        accounts[1] = newAccountId(prefix, uint8(AccountType.EQUITY));
        accounts[2] = newAccountId(prefix, uint8(AccountType.LOSS));
        accounts[3] = newAccountId(prefix, uint8(AccountType.GAIN));

        createAccount(accounts[0], true);
        createAccount(accounts[1], false);
        createAccount(accounts[2], false);
        createAccount(accounts[3], false);

        holdings.create(unlockedPoolId(), scId, assetId, valuation, accounts);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function increaseHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint128 amount)
        public
        poolUnlocked
    {
        PoolId poolId = unlockedPoolId();

        uint128 valueChange = holdings.increase(poolId, scId, assetId, valuation, amount);

        accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.EQUITY)), valueChange);
        accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.ASSET)), valueChange);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function decreaseHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, uint128 amount)
        public
        poolUnlocked
    {
        PoolId poolId = unlockedPoolId();

        uint128 valueChange = holdings.decrease(poolId, scId, assetId, valuation, amount);

        accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.ASSET)), valueChange);
        accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.EQUITY)), valueChange);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function updateHolding(ShareClassId scId, AssetId assetId) external poolUnlocked {
        PoolId poolId = unlockedPoolId();

        int128 diff = holdings.update(poolId, scId, assetId);

        if (diff > 0) {
            accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.GAIN)), uint128(diff));
            accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.ASSET)), uint128(diff));
        } else if (diff < 0) {
            accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.ASSET)), uint128(diff));
            accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.LOSS)), uint128(diff));
        }
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function updateHoldingValuation(ShareClassId scId, AssetId assetId, IERC7726 valuation) external poolUnlocked {
        holdings.updateValuation(unlockedPoolId(), scId, assetId, valuation);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function setHoldingAccountId(ShareClassId scId, AssetId assetId, AccountId accountId) external poolUnlocked {
        holdings.setAccountId(unlockedPoolId(), scId, assetId, accountId);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function createAccount(AccountId account, bool isDebitNormal) public poolUnlocked {
        accounting.createAccount(unlockedPoolId(), account, isDebitNormal);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function setAccountMetadata(AccountId account, bytes calldata metadata) external poolUnlocked {
        accounting.setAccountMetadata(unlockedPoolId(), account, metadata);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function addDebit(AccountId account, uint128 amount) external poolUnlocked {
        accounting.addDebit(account, amount);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function addCredit(AccountId account, uint128 amount) external poolUnlocked {
        accounting.addCredit(account, amount);
    }

    /// @inheritdoc IPoolManagerAdminMethods
    function unlockAssets(ShareClassId scId, AssetId assetId, bytes32 receiver, uint128 assetAmount)
        external
        poolUnlocked
    {
        assetRegistry.burn(escrow(unlockedPoolId(), scId, EscrowId.SHARE_CLASS), assetId.raw(), assetAmount);

        gateway.sendUnlockAssets(assetId, receiver, assetAmount);
    }

    //----------------------------------------------------------------------------------------------
    // Gateway owner methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IPoolManagerHandler
    function handleRegisterAsset(AssetId assetId, string calldata name, string calldata symbol, uint8 decimals)
        external
        onlyGateway
    {
        assetRegistry.registerAsset(assetId, name, symbol, decimals);
    }

    /// @inheritdoc IPoolManagerHandler
    function handleRequestDeposit(
        PoolId poolId,
        ShareClassId scId,
        bytes32 investor,
        AssetId depositAssetId,
        uint128 amount
    ) external onlyGateway {
        address pendingShareClassEscrow = escrow(poolId, scId, EscrowId.PENDING_SHARE_CLASS);
        assetRegistry.mint(pendingShareClassEscrow, depositAssetId.raw(), amount);

        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        scm.requestDeposit(poolId, scId, amount, investor, depositAssetId);
    }

    /// @inheritdoc IPoolManagerHandler
    function handleRequestRedeem(
        PoolId poolId,
        ShareClassId scId,
        bytes32 investor,
        AssetId payoutAssetId,
        uint128 amount
    ) external onlyGateway {
        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        scm.requestRedeem(poolId, scId, amount, investor, payoutAssetId);
    }

    /// @inheritdoc IPoolManagerHandler
    function handleCancelDepositRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId depositAssetId)
        external
        onlyGateway
    {
        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        (uint128 cancelledAssetAmount) = scm.cancelDepositRequest(poolId, scId, investor, depositAssetId);

        address pendingShareClassEscrow = escrow(poolId, scId, EscrowId.PENDING_SHARE_CLASS);
        assetRegistry.burn(pendingShareClassEscrow, depositAssetId.raw(), cancelledAssetAmount);

        gateway.sendFulfilledCancelDepositRequest(poolId, scId, depositAssetId, investor, cancelledAssetAmount);
    }

    /// @inheritdoc IPoolManagerHandler
    function handleCancelRedeemRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId payoutAssetId)
        external
        onlyGateway
    {
        IShareClassManager scm = poolRegistry.shareClassManager(poolId);
        uint128 cancelledShareAmount = scm.cancelRedeemRequest(poolId, scId, investor, payoutAssetId);

        gateway.sendFulfilledCancelRedeemRequest(poolId, scId, payoutAssetId, investor, cancelledShareAmount);
    }

    /// @inheritdoc IPoolManagerHandler
    function handleLockedTokens(AssetId assetId, address receiver, uint128 amount) external onlyGateway {
        assetRegistry.mint(receiver, assetId.raw(), amount);
    }

    //----------------------------------------------------------------------------------------------
    // view / pure methods
    //----------------------------------------------------------------------------------------------

    function escrow(PoolId poolId, ShareClassId scId, EscrowId escrow_) public pure returns (address) {
        return address(bytes20(keccak256(abi.encodePacked("escrow", poolId, scId, escrow_))));
    }

    //----------------------------------------------------------------------------------------------
    // internal / private methods
    //----------------------------------------------------------------------------------------------

    function _beforeUnlock(PoolId poolId) internal override {
        require(poolRegistry.isAdmin(poolId, msg.sender), NotAuthorizedAdmin());
        accounting.unlock(poolId, bytes32("TODO"));
    }

    function _beforeLock() internal override {
        accounting.lock();
    }
}
