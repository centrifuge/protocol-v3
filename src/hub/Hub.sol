// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18, d18} from "src/misc/types/D18.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {ConversionLib} from "src/misc/libraries/ConversionLib.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {Auth} from "src/misc/Auth.sol";
import {Multicall, IMulticall} from "src/misc/Multicall.sol";
import {Recoverable} from "src/misc/Recoverable.sol";
import {ITransientValuation} from "src/misc/interfaces/ITransientValuation.sol";

import {IGateway} from "src/common/interfaces/IGateway.sol";
import {MessageLib, UpdateContractType, VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {IHubGatewayHandler} from "src/common/interfaces/IGatewayHandlers.sol";
import {IPoolMessageSender} from "src/common/interfaces/IGatewaySenders.sol";

import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {AccountId, newAccountId} from "src/common/types/AccountId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {JournalEntry} from "src/common/libraries/JournalEntryLib.sol";

import {IAccounting} from "src/hub/interfaces/IAccounting.sol";
import {IHubRegistry} from "src/hub/interfaces/IHubRegistry.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";
import {IHoldings, Holding} from "src/hub/interfaces/IHoldings.sol";
import {IHub, AccountType} from "src/hub/interfaces/IHub.sol";

// @inheritdoc IHub
contract Hub is Multicall, Auth, Recoverable, IHub, IHubGatewayHandler {
    using CastLib for *;
    using MessageLib for *;
    using MathLib for uint256;

    IGateway public gateway;
    IHoldings public holdings;
    IAccounting public accounting;
    IHubRegistry public hubRegistry;
    IPoolMessageSender public sender;
    IShareClassManager public shareClassManager;
    ITransientValuation immutable transientValuation;

    constructor(
        IShareClassManager shareClassManager_,
        IHubRegistry hubRegistry_,
        IAccounting accounting_,
        IHoldings holdings_,
        IGateway gateway_,
        ITransientValuation transientValuation_,
        address deployer
    ) Auth(deployer) {
        shareClassManager = shareClassManager_;
        hubRegistry = hubRegistry_;
        accounting = accounting_;
        holdings = holdings_;
        gateway = gateway_;
        transientValuation = transientValuation_;
    }

    modifier unlocked(PoolId poolId) {
        require(hubRegistry.isAdmin(poolId, msg.sender), IHub.NotAuthorizedAdmin());

        accounting.unlock(poolId);
        _;
        accounting.lock();
    }

    //----------------------------------------------------------------------------------------------
    // System methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IHub
    function file(bytes32 what, address data) external auth {
        if (what == "sender") sender = IPoolMessageSender(data);
        else if (what == "holdings") holdings = IHoldings(data);
        else if (what == "hubRegistry") hubRegistry = IHubRegistry(data);
        else if (what == "shareClassManager") shareClassManager = IShareClassManager(data);
        else if (what == "gateway") gateway = IGateway(data);
        else if (what == "accounting") accounting = IAccounting(data);
        else revert FileUnrecognizedWhat();

        emit File(what, data);
    }

    /// @inheritdoc IMulticall
    /// @notice performs a multicall but all messages sent in the process will be batched
    function multicall(bytes[] calldata data) public payable override {
        bool wasBatching = gateway.isBatching();
        if (!wasBatching) {
            gateway.startBatching();
            gateway.payTransaction{value: msg.value}(msg.sender);
        }

        super.multicall(data);

        if (!wasBatching) {
            gateway.endBatching();
        }
    }

    //----------------------------------------------------------------------------------------------
    // Permissionless methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IHub
    function createPool(address admin, AssetId currency) external payable auth returns (PoolId poolId) {
        poolId = hubRegistry.registerPool(admin, sender.localCentrifugeId(), currency);
    }

    /// @inheritdoc IHub
    function claimDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor)
        external
        payable
        protected
    {
        _pay();

        (uint128 shares, uint128 tokens, uint128 cancelledAssetAmount) =
            shareClassManager.claimDeposit(poolId, scId, investor, assetId);
        sender.sendFulfilledDepositRequest(poolId, scId, assetId, investor, tokens, shares);

        // If cancellation was queued, notify about delayed cancellation
        if (cancelledAssetAmount > 0) {
            sender.sendFulfilledCancelDepositRequest(poolId, scId, assetId, investor, cancelledAssetAmount);
        }
    }

    /// @inheritdoc IHub
    function claimRedeem(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor)
        external
        payable
        protected
    {
        _pay();

        (uint128 tokens, uint128 shares, uint128 cancelledShareAmount) =
            shareClassManager.claimRedeem(poolId, scId, investor, assetId);

        sender.sendFulfilledRedeemRequest(poolId, scId, assetId, investor, tokens, shares);

        // If cancellation was queued, notify about delayed cancellation
        if (cancelledShareAmount > 0) {
            sender.sendFulfilledCancelRedeemRequest(poolId, scId, assetId, investor, cancelledShareAmount);
        }
    }

    //----------------------------------------------------------------------------------------------
    // Pool admin methods
    //----------------------------------------------------------------------------------------------
    /// @inheritdoc IHub
    function notifyPool(PoolId poolId, uint16 centrifugeId) external payable {
        _protected(poolId);
        _pay();

        sender.sendNotifyPool(centrifugeId, poolId);
    }

    /// @inheritdoc IHub
    function notifyShareClass(PoolId poolId, uint16 centrifugeId, ShareClassId scId, bytes32 hook) external payable {
        _protected(poolId);
        _pay();

        require(shareClassManager.exists(poolId, scId), IShareClassManager.ShareClassNotFound());

        (string memory name, string memory symbol, bytes32 salt) = shareClassManager.metadata(scId);
        uint8 decimals = hubRegistry.decimals(poolId);

        sender.sendNotifyShareClass(centrifugeId, poolId, scId, name, symbol, decimals, salt, hook);
    }

    /// @inheritdoc IHub
    function notifySharePrice(PoolId poolId, uint16 centrifugeId, ShareClassId scId) public payable {
        _protected(poolId);
        _pay();

        (, D18 poolPerShare) = shareClassManager.shareClassPrice(poolId, scId);

        sender.sendNotifyPricePoolPerShare(centrifugeId, poolId, scId, poolPerShare);
    }

    /// @inheritdoc IHub
    function notifyAssetPrice(PoolId poolId, ShareClassId scId, AssetId assetId) public payable {
        _protected(poolId);
        _pay();

        AssetId poolCurrency = hubRegistry.currency(poolId);
        // NOTE: We assume symmetric prices are provided by holdings valuation
        IERC7726 valuation = holdings.valuation(poolId, scId, assetId);

        // Retrieve amount of 1 asset unit in pool currency
        uint128 assetUnitAmount = (10 ** hubRegistry.decimals(assetId.raw())).toUint128();
        uint128 poolUnitAmount = (10 ** hubRegistry.decimals(poolCurrency.raw())).toUint128();
        uint128 poolAmountPerAsset =
            valuation.getQuote(assetUnitAmount, assetId.addr(), poolCurrency.addr()).toUint128();

        // Retrieve price by normalizing by pool denomination
        D18 pricePoolPerAsset = d18(poolAmountPerAsset, poolUnitAmount);
        sender.sendNotifyPricePoolPerAsset(poolId, scId, assetId, pricePoolPerAsset);
    }

    /// @inheritdoc IHub
    function setPoolMetadata(PoolId poolId, bytes calldata metadata) external payable {
        _protected(poolId);

        hubRegistry.setMetadata(poolId, metadata);
    }

    /// @inheritdoc IHub
    function allowPoolAdmin(PoolId poolId, address account, bool allow) external payable {
        _protected(poolId);

        hubRegistry.updateAdmin(poolId, account, allow);
    }

    /// @inheritdoc IHub
    function addShareClass(
        PoolId poolId,
        string calldata name,
        string calldata symbol,
        bytes32 salt,
        bytes calldata data
    ) external payable {
        _protected(poolId);

        shareClassManager.addShareClass(poolId, name, symbol, salt, data);
    }

    /// @inheritdoc IHub
    function approveDeposits(
        PoolId poolId,
        ShareClassId scId,
        AssetId paymentAssetId,
        uint128 maxApproval,
        IERC7726 valuation
    ) external payable unlocked(poolId) {
        _protected(poolId);

        (uint128 approvedAssetAmount,) =
            shareClassManager.approveDeposits(poolId, scId, maxApproval, paymentAssetId, valuation);

        uint128 valueChange = holdings.increase(poolId, scId, paymentAssetId, valuation, approvedAssetAmount);

        accounting.addCredit(holdings.accountId(poolId, scId, paymentAssetId, uint8(AccountType.Equity)), valueChange);
        accounting.addDebit(holdings.accountId(poolId, scId, paymentAssetId, uint8(AccountType.Asset)), valueChange);
    }

    /// @inheritdoc IHub
    function approveRedeems(PoolId poolId, ShareClassId scId, AssetId payoutAssetId, uint128 maxApproval)
        external
        payable
    {
        _protected(poolId);

        shareClassManager.approveRedeems(poolId, scId, maxApproval, payoutAssetId);
    }

    /// @inheritdoc IHub
    function issueShares(PoolId poolId, ShareClassId scId, AssetId depositAssetId, D18 navPerShare) external payable {
        _protected(poolId);

        shareClassManager.issueShares(poolId, scId, depositAssetId, navPerShare);
    }

    /// @inheritdoc IHub
    function revokeShares(PoolId poolId, ShareClassId scId, AssetId payoutAssetId, D18 navPerShare, IERC7726 valuation)
        external
        payable
        unlocked(poolId)
    {
        _protected(poolId);

        (uint128 payoutAssetAmount,) =
            shareClassManager.revokeShares(poolId, scId, payoutAssetId, navPerShare, valuation);

        uint128 valueChange = holdings.decrease(poolId, scId, payoutAssetId, valuation, payoutAssetAmount);

        accounting.addCredit(holdings.accountId(poolId, scId, payoutAssetId, uint8(AccountType.Asset)), valueChange);
        accounting.addDebit(holdings.accountId(poolId, scId, payoutAssetId, uint8(AccountType.Equity)), valueChange);
    }

    /// @inheritdoc IHub
    function updateRestriction(PoolId poolId, uint16 centrifugeId, ShareClassId scId, bytes calldata payload)
        external
        payable
    {
        _protected(poolId);
        _pay();

        require(shareClassManager.exists(poolId, scId), IShareClassManager.ShareClassNotFound());

        sender.sendUpdateRestriction(centrifugeId, poolId, scId, payload);
    }

    /// @inheritdoc IHub
    function updateContract(
        PoolId poolId,
        uint16 centrifugeId,
        ShareClassId scId,
        bytes32 target,
        bytes calldata payload
    ) external payable {
        _protected(poolId);
        _pay();

        require(shareClassManager.exists(poolId, scId), IShareClassManager.ShareClassNotFound());

        sender.sendUpdateContract(centrifugeId, poolId, scId, target, payload);
    }

    /// @inheritdoc IHub
    function updateVault(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        bytes32 target,
        bytes32 vaultOrFactory,
        VaultUpdateKind kind
    ) public payable protected {
        _protected(poolId);
        _pay();

        require(shareClassManager.exists(poolId, scId), IShareClassManager.ShareClassNotFound());

        sender.sendUpdateContract(
            assetId.centrifugeId(),
            poolId,
            scId,
            target,
            MessageLib.UpdateContractVaultUpdate({
                vaultOrFactory: vaultOrFactory,
                assetId: assetId.raw(),
                kind: uint8(kind)
            }).serialize()
        );
    }

    /// @inheritdoc IHub
    function updatePricePoolPerShare(PoolId poolId, ShareClassId scId, D18 navPerShare, bytes calldata data)
        public
        payable
    {
        _protected(poolId);

        shareClassManager.updateShareClass(poolId, scId, navPerShare, data);
    }

    /// @inheritdoc IHub
    function createHolding(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        IERC7726 valuation,
        bool isLiability,
        uint24 prefix
    ) external payable unlocked(poolId) {
        _protected(poolId);

        require(hubRegistry.isRegistered(assetId), IHubRegistry.AssetNotFound());

        AccountId[] memory accounts = new AccountId[](6);
        accounts[0] = newAccountId(prefix, uint8(AccountType.Asset));
        accounts[1] = newAccountId(prefix, uint8(AccountType.Equity));
        accounts[2] = newAccountId(prefix, uint8(AccountType.Loss));
        accounts[3] = newAccountId(prefix, uint8(AccountType.Gain));
        accounts[4] = newAccountId(prefix, uint8(AccountType.Expense));
        accounts[5] = newAccountId(prefix, uint8(AccountType.Liability));

        accounting.createAccount(poolId, accounts[0], true);
        accounting.createAccount(poolId, accounts[1], false);
        accounting.createAccount(poolId, accounts[2], false);
        accounting.createAccount(poolId, accounts[3], false);
        accounting.createAccount(poolId, accounts[4], true);
        accounting.createAccount(poolId, accounts[5], false);

        holdings.create(poolId, scId, assetId, valuation, isLiability, accounts);
    }

    /// @inheritdoc IHub
    function updateHolding(PoolId poolId, ShareClassId scId, AssetId assetId) public payable unlocked(poolId) {
        _protected(poolId);

        int128 diff = holdings.update(poolId, scId, assetId);

        if (diff > 0) {
            if (holdings.isLiability(poolId, scId, assetId)) {
                accounting.addCredit(
                    holdings.accountId(poolId, scId, assetId, uint8(AccountType.Liability)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(poolId, scId, assetId, uint8(AccountType.Expense)), uint128(diff)
                );
            } else {
                accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.Gain)), uint128(diff));
                accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.Asset)), uint128(diff));
            }
        } else if (diff < 0) {
            if (holdings.isLiability(poolId, scId, assetId)) {
                accounting.addCredit(
                    holdings.accountId(poolId, scId, assetId, uint8(AccountType.Expense)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(poolId, scId, assetId, uint8(AccountType.Liability)), uint128(diff)
                );
            } else {
                accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.Asset)), uint128(diff));
                accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(AccountType.Loss)), uint128(diff));
            }
        }
    }

    /// @inheritdoc IHub
    function updateHoldingValuation(PoolId poolId, ShareClassId scId, AssetId assetId, IERC7726 valuation)
        external
        payable
    {
        _protected(poolId);

        holdings.updateValuation(poolId, scId, assetId, valuation);
    }

    /// @inheritdoc IHub
    function setHoldingAccountId(PoolId poolId, ShareClassId scId, AssetId assetId, AccountId accountId)
        external
        payable
    {
        _protected(poolId);

        holdings.setAccountId(poolId, scId, assetId, accountId);
    }

    /// @inheritdoc IHub
    function createAccount(PoolId poolId, AccountId account, bool isDebitNormal) public payable {
        _protected(poolId);

        accounting.createAccount(poolId, account, isDebitNormal);
    }

    /// @inheritdoc IHub
    function setAccountMetadata(PoolId poolId, AccountId account, bytes calldata metadata) external payable {
        _protected(poolId);

        accounting.setAccountMetadata(poolId, account, metadata);
    }

    /// @inheritdoc IHub
    function addDebit(PoolId poolId, AccountId account, uint128 amount) external payable unlocked(poolId) {
        _protected(poolId);

        accounting.addDebit(account, amount);
    }

    /// @inheritdoc IHub
    function addCredit(PoolId poolId, AccountId account, uint128 amount) external payable unlocked(poolId) {
        _protected(poolId);

        accounting.addCredit(account, amount);
    }

    //----------------------------------------------------------------------------------------------
    // Gateway owner methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IHubGatewayHandler
    function registerAsset(AssetId assetId, uint8 decimals) external auth {
        hubRegistry.registerAsset(assetId, decimals);
    }

    /// @inheritdoc IHubGatewayHandler
    function depositRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId depositAssetId, uint128 amount)
        external
        auth
    {
        shareClassManager.requestDeposit(poolId, scId, amount, investor, depositAssetId);
    }

    /// @inheritdoc IHubGatewayHandler
    function redeemRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId payoutAssetId, uint128 amount)
        external
        auth
    {
        shareClassManager.requestRedeem(poolId, scId, amount, investor, payoutAssetId);
    }

    /// @inheritdoc IHubGatewayHandler
    function cancelDepositRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId depositAssetId)
        external
        auth
    {
        uint128 cancelledAssetAmount = shareClassManager.cancelDepositRequest(poolId, scId, investor, depositAssetId);

        // Cancellation might have been queued such that it will be executed in the future during claiming
        if (cancelledAssetAmount > 0) {
            sender.sendFulfilledCancelDepositRequest(poolId, scId, depositAssetId, investor, cancelledAssetAmount);
        }
    }

    /// @inheritdoc IHubGatewayHandler
    function cancelRedeemRequest(PoolId poolId, ShareClassId scId, bytes32 investor, AssetId payoutAssetId)
        external
        auth
    {
        uint128 cancelledShareAmount = shareClassManager.cancelRedeemRequest(poolId, scId, investor, payoutAssetId);

        // Cancellation might have been queued such that it will be executed in the future during claiming
        if (cancelledShareAmount > 0) {
            sender.sendFulfilledCancelRedeemRequest(poolId, scId, payoutAssetId, investor, cancelledShareAmount);
        }
    }

    /// @inheritdoc IHubGatewayHandler
    function updateHoldingAmount(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        uint128 amount,
        D18 pricePerUnit,
        bool isIncrease,
        JournalEntry[] memory debits,
        JournalEntry[] memory credits
    ) external auth unlocked(poolId) {
        address poolCurrency = hubRegistry.currency(poolId).addr();
        transientValuation.setPrice(assetId.addr(), poolCurrency, pricePerUnit);
        uint128 valueChange = transientValuation.getQuote(amount, assetId.addr(), poolCurrency).toUint128();

        (uint128 debited, uint128 credited) = _updateJournal(debits, credits);
        uint128 debitValueLeft = valueChange - debited;
        uint128 creditValueLeft = valueChange - credited;

        _updateHoldingWithPartialDebitsAndCredits(
            poolId, scId, assetId, amount, isIncrease, debitValueLeft, creditValueLeft
        );
    }

    /// @inheritdoc IHubGatewayHandler
    function updateHoldingValue(PoolId poolId, ShareClassId scId, AssetId assetId, D18 pricePoolPerAsset)
        external
        auth
        unlocked(poolId)
    {
        transientValuation.setPrice(assetId.addr(), hubRegistry.currency(poolId).addr(), pricePoolPerAsset);
        IERC7726 _valuation = holdings.valuation(poolId, scId, assetId);
        holdings.updateValuation(poolId, scId, assetId, transientValuation);

        updateHolding(poolId, scId, assetId);
        holdings.updateValuation(poolId, scId, assetId, _valuation);
    }

    /// @inheritdoc IHubGatewayHandler
    function updateJournal(PoolId poolId, JournalEntry[] memory debits, JournalEntry[] memory credits)
        external
        auth
        unlocked(poolId)
    {
        _updateJournal(debits, credits);
    }

    /// @inheritdoc IHubGatewayHandler
    function increaseShareIssuance(PoolId poolId, ShareClassId scId, D18 pricePerShare, uint128 amount) external auth {
        shareClassManager.increaseShareClassIssuance(poolId, scId, pricePerShare, amount);
    }

    /// @inheritdoc IHubGatewayHandler
    function decreaseShareIssuance(PoolId poolId, ShareClassId scId, D18 pricePerShare, uint128 amount) external auth {
        shareClassManager.decreaseShareClassIssuance(poolId, scId, pricePerShare, amount);
    }

    //----------------------------------------------------------------------------------------------
    //  Internal methods
    //----------------------------------------------------------------------------------------------

    /// @dev Ensure the method can be used without reentrancy issues, and the sender is a pool admin
    function _protected(PoolId poolId) internal protected {
        require(hubRegistry.isAdmin(poolId, msg.sender), IHub.NotAuthorizedAdmin());
    }

    /// @notice Send native tokens to the gateway for transaction payment if it's not in a multicall.
    function _pay() internal {
        if (!gateway.isBatching()) {
            gateway.payTransaction{value: msg.value}(msg.sender);
        }
    }

    /// @notice Update the journal with the given debits and credits. Can be unequal.
    function _updateJournal(JournalEntry[] memory debits, JournalEntry[] memory credits)
        internal
        returns (uint128 debited, uint128 credited)
    {
        for (uint256 i; i < debits.length; i++) {
            accounting.addDebit(debits[i].accountId, debits[i].amount);
            debited += debits[i].amount;
        }

        for (uint256 i; i < credits.length; i++) {
            accounting.addCredit(credits[i].accountId, credits[i].amount);
            credited += credits[i].amount;
        }
    }

    /// @notice Update a holding while debiting and/or crediting only a portion of the value change.
    function _updateHoldingWithPartialDebitsAndCredits(
        PoolId poolId,
        ShareClassId scId,
        AssetId assetId,
        uint128 amount,
        bool isIncrease,
        uint128 debitValue,
        uint128 creditValue
    ) internal {
        bool isLiability = holdings.isLiability(poolId, scId, assetId);
        AccountType debitAccountType = isLiability ? AccountType.Expense : AccountType.Asset;
        AccountType creditAccountType = isLiability ? AccountType.Liability : AccountType.Equity;

        if (isIncrease) {
            holdings.increase(poolId, scId, assetId, transientValuation, amount);
            accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(debitAccountType)), debitValue);
            accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(creditAccountType)), creditValue);
        } else {
            holdings.decrease(poolId, scId, assetId, transientValuation, amount);
            accounting.addDebit(holdings.accountId(poolId, scId, assetId, uint8(creditAccountType)), debitValue);
            accounting.addCredit(holdings.accountId(poolId, scId, assetId, uint8(debitAccountType)), creditValue);
        }
    }
}
