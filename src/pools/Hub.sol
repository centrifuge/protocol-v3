// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18} from "src/misc/types/D18.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
import {Auth} from "src/misc/Auth.sol";
import {Multicall, IMulticall} from "src/misc/Multicall.sol";

import {IGateway} from "src/common/interfaces/IGateway.sol";
import {MessageLib, UpdateContractType, VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {IHubGatewayHandler} from "src/common/interfaces/IGatewayHandlers.sol";
import {IPoolMessageSender} from "src/common/interfaces/IGatewaySenders.sol";

import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {AccountId, newAccountId} from "src/common/types/AccountId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {JournalEntry} from "src/common/libraries/JournalEntryLib.sol";

import {IAccounting} from "src/pools/interfaces/IAccounting.sol";
import {IHubRegistry} from "src/pools/interfaces/IHubRegistry.sol";
import {IShareClassManager} from "src/pools/interfaces/IShareClassManager.sol";
import {IHoldings, Holding} from "src/pools/interfaces/IHoldings.sol";
import {IHub, AccountType} from "src/pools/interfaces/IHub.sol";
import {ITransientValuation} from "src/misc/interfaces/ITransientValuation.sol";

// @inheritdoc IHub
contract Hub is Auth, Multicall, IHub, IHubGatewayHandler {
    using MessageLib for *;
    using MathLib for uint256;
    using CastLib for bytes;
    using CastLib for bytes32;
    using CastLib for address;

    /// @dev Represents the unlocked pool Id in the multicall
    PoolId public transient unlockedPoolId;

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
            gateway.payTransaction{value: msg.value}();
        }

        super.multicall(data);

        if (!wasBatching) {
            gateway.endBatching();
        }
    }

    /// @inheritdoc IHub
    function execute(PoolId poolId, bytes[] calldata data) external payable {
        require(unlockedPoolId.isNull(), IHub.PoolAlreadyUnlocked());
        require(hubRegistry.isAdmin(poolId, msg.sender), IHub.NotAuthorizedAdmin());

        accounting.unlock(poolId);
        unlockedPoolId = poolId;

        multicall(data);

        accounting.lock();
        unlockedPoolId = PoolId.wrap(0);
    }

    //----------------------------------------------------------------------------------------------
    // Permisionless methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IHub
    function createPool(address admin, AssetId currency)
        external
        payable
        auth
        returns (PoolId poolId)
    {
        poolId = hubRegistry.registerPool(admin, sender.localCentrifugeId(), currency);
    }

    /// @inheritdoc IHub
    function claimDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) external payable {
        _protected();
        _pay();

        (uint128 shares, uint128 tokens, uint128 cancelledAssetAmount) = shareClassManager.claimDeposit(poolId, scId, investor, assetId);
        sender.sendFulfilledDepositRequest(poolId, scId, assetId, investor, tokens, shares);

        // If cancellation was queued, notify about delayed cancellation
        if (cancelledAssetAmount > 0) {
            sender.sendFulfilledCancelDepositRequest(poolId, scId, assetId, investor, cancelledAssetAmount);
        }
    }

    /// @inheritdoc IHub
    function claimRedeem(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) external payable {
        _protected();
        _pay();

        (uint128 tokens, uint128 shares, uint128 cancelledShareAmount) = shareClassManager.claimRedeem(poolId, scId, investor, assetId);

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
    function notifyPool(uint16 centrifugeId) external payable {
        _protectedAndUnlocked();

        sender.sendNotifyPool(centrifugeId, unlockedPoolId);
    }

    /// @inheritdoc IHub
    function notifyShareClass(uint16 centrifugeId, ShareClassId scId, bytes32 hook) external payable {
        _protectedAndUnlocked();

        require(shareClassManager.exists(unlockedPoolId, scId), IShareClassManager.ShareClassNotFound());

        (string memory name, string memory symbol, bytes32 salt) = shareClassManager.metadata(scId);
        uint8 decimals = hubRegistry.decimals(unlockedPoolId);

        sender.sendNotifyShareClass(centrifugeId, unlockedPoolId, scId, name, symbol, decimals, salt, hook);
    }

    /// @inheritdoc IHub
    function setPoolMetadata(bytes calldata metadata) external payable {
        _protectedAndUnlocked();

        hubRegistry.setMetadata(unlockedPoolId, metadata);
    }

    /// @inheritdoc IHub
    function allowPoolAdmin(address account, bool allow) external payable {
        _protectedAndUnlocked();

        hubRegistry.updateAdmin(unlockedPoolId, account, allow);
    }

    /// @inheritdoc IHub
    function addShareClass(string calldata name, string calldata symbol, bytes32 salt, bytes calldata data)
        external
        payable
    {
        _protectedAndUnlocked();

        shareClassManager.addShareClass(unlockedPoolId, name, symbol, salt, data);
    }

    /// @inheritdoc IHub
    function approveDeposits(ShareClassId scId, AssetId paymentAssetId, uint128 maxApproval, IERC7726 valuation)
        external
        payable
    {
        _protectedAndUnlocked();

        (uint128 approvedAssetAmount,) =
            shareClassManager.approveDeposits(unlockedPoolId, scId, maxApproval, paymentAssetId, valuation);

        uint128 valueChange = holdings.increase(unlockedPoolId, scId, paymentAssetId, valuation, approvedAssetAmount);

        accounting.addCredit(
            holdings.accountId(unlockedPoolId, scId, paymentAssetId, uint8(AccountType.Equity)), valueChange
        );
        accounting.addDebit(
            holdings.accountId(unlockedPoolId, scId, paymentAssetId, uint8(AccountType.Asset)), valueChange
        );
    }

    /// @inheritdoc IHub
    function approveRedeems(ShareClassId scId, AssetId payoutAssetId, uint128 maxApproval) external payable {
        _protectedAndUnlocked();

        shareClassManager.approveRedeems(unlockedPoolId, scId, maxApproval, payoutAssetId);
    }

    /// @inheritdoc IHub
    function issueShares(ShareClassId scId, AssetId depositAssetId, D18 navPerShare) external payable {
        _protectedAndUnlocked();

        shareClassManager.issueShares(unlockedPoolId, scId, depositAssetId, navPerShare);
    }

    /// @inheritdoc IHub
    function revokeShares(ShareClassId scId, AssetId payoutAssetId, D18 navPerShare, IERC7726 valuation)
        external
        payable
    {
        _protectedAndUnlocked();

        (uint128 payoutAssetAmount,) = shareClassManager.revokeShares(unlockedPoolId, scId, payoutAssetId, navPerShare, valuation);

        uint128 valueChange = holdings.decrease(unlockedPoolId, scId, payoutAssetId, valuation, payoutAssetAmount);

        accounting.addCredit(
            holdings.accountId(unlockedPoolId, scId, payoutAssetId, uint8(AccountType.Asset)), valueChange
        );
        accounting.addDebit(
            holdings.accountId(unlockedPoolId, scId, payoutAssetId, uint8(AccountType.Equity)), valueChange
        );
    }

    /// @inheritdoc IHub
    function updateRestriction(uint16 centrifugeId, ShareClassId scId, bytes calldata payload)
        external
        payable
    {
        _protectedAndUnlocked();

        require(shareClassManager.exists(unlockedPoolId, scId), IShareClassManager.ShareClassNotFound());

        sender.sendUpdateRestriction(centrifugeId, unlockedPoolId, scId, payload);
    }

    /// @inheritdoc IHub
    function updateContract(uint16 centrifugeId, ShareClassId scId, bytes32 target, bytes calldata payload)
        external
        payable
    {
        _protectedAndUnlocked();

        sender.sendUpdateContract(centrifugeId, unlockedPoolId, scId, target, payload);
    }

    /// @inheritdoc IHub
    function updateVault(
        ShareClassId scId,
        AssetId assetId,
        bytes32 target,
        bytes32 vaultOrFactory,
        VaultUpdateKind kind
    ) public payable {
        _protectedAndUnlocked();

        sender.sendUpdateContract(
            assetId.centrifugeId(),
            unlockedPoolId,
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
    function createHolding(ShareClassId scId, AssetId assetId, IERC7726 valuation, bool isLiability, uint24 prefix)
        external
        payable
    {
        _protectedAndUnlocked();

        require(hubRegistry.isRegistered(assetId), IHubRegistry.AssetNotFound());

        AccountId[] memory accounts = new AccountId[](6);
        accounts[0] = newAccountId(prefix, uint8(AccountType.Asset));
        accounts[1] = newAccountId(prefix, uint8(AccountType.Equity));
        accounts[2] = newAccountId(prefix, uint8(AccountType.Loss));
        accounts[3] = newAccountId(prefix, uint8(AccountType.Gain));
        accounts[4] = newAccountId(prefix, uint8(AccountType.Expense));
        accounts[5] = newAccountId(prefix, uint8(AccountType.Liability));

        createAccount(accounts[0], true);
        createAccount(accounts[1], false);
        createAccount(accounts[2], false);
        createAccount(accounts[3], false);
        createAccount(accounts[4], true);
        createAccount(accounts[5], false);

        holdings.create(unlockedPoolId, scId, assetId, valuation, isLiability, accounts);
    }

    /// @inheritdoc IHub
    function updateHolding(ShareClassId scId, AssetId assetId) public payable {
        _protectedAndUnlocked();

        int128 diff = holdings.update(unlockedPoolId, scId, assetId);

        if (diff > 0) {
            if (holdings.isLiability(unlockedPoolId, scId, assetId)) {
                accounting.addCredit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Liability)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Expense)), uint128(diff)
                );
            } else {
                accounting.addCredit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Gain)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Asset)), uint128(diff)
                );
            }
        } else if (diff < 0) {
            if (holdings.isLiability(unlockedPoolId, scId, assetId)) {
                accounting.addCredit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Expense)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Liability)), uint128(diff)
                );
            } else {
                accounting.addCredit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Asset)), uint128(diff)
                );
                accounting.addDebit(
                    holdings.accountId(unlockedPoolId, scId, assetId, uint8(AccountType.Loss)), uint128(diff)
                );
            }
        }
    }

    /// @inheritdoc IHub
    function updateHoldingValuation(ShareClassId scId, AssetId assetId, IERC7726 valuation) external payable {
        _protectedAndUnlocked();

        holdings.updateValuation(unlockedPoolId, scId, assetId, valuation);
    }

    /// @inheritdoc IHub
    function setHoldingAccountId(ShareClassId scId, AssetId assetId, AccountId accountId) external payable {
        _protectedAndUnlocked();

        holdings.setAccountId(unlockedPoolId, scId, assetId, accountId);
    }

    /// @inheritdoc IHub
    function createAccount(AccountId account, bool isDebitNormal) public payable {
        _protectedAndUnlocked();

        accounting.createAccount(unlockedPoolId, account, isDebitNormal);
    }

    /// @inheritdoc IHub
    function setAccountMetadata(AccountId account, bytes calldata metadata) external payable {
        _protectedAndUnlocked();

        accounting.setAccountMetadata(unlockedPoolId, account, metadata);
    }

    /// @inheritdoc IHub
    function addDebit(AccountId account, uint128 amount) external payable {
        _protectedAndUnlocked();

        accounting.addDebit(account, amount);
    }

    /// @inheritdoc IHub
    function addCredit(AccountId account, uint128 amount) external payable {
        _protectedAndUnlocked();

        accounting.addCredit(account, amount);
    }

    //----------------------------------------------------------------------------------------------
    // Gateway owner methods
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IHubGatewayHandler
    function registerAsset(AssetId assetId, uint8 decimals)
        external
        auth
    {
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
    ) external auth {
        accounting.unlock(poolId);
        address poolCurrency = hubRegistry.currency(poolId).addr();
        transientValuation.setPrice(assetId.addr(), poolCurrency, pricePerUnit);
        uint128 valueChange = transientValuation.getQuote(amount, assetId.addr(), poolCurrency).toUint128();

        (uint128 debited, uint128 credited) = _updateJournal(debits, credits);
        uint128 debitValueLeft = valueChange - debited;
        uint128 creditValueLeft = valueChange - credited;

        _updateHoldingWithPartialDebitsAndCredits(
            poolId, scId, assetId, amount, isIncrease, debitValueLeft, creditValueLeft
        );
        accounting.lock();
    }

    /// @inheritdoc IHubGatewayHandler
    function updateHoldingValue(PoolId poolId, ShareClassId scId, AssetId assetId, D18 pricePerUnit) external auth {
        transientValuation.setPrice(assetId.addr(), hubRegistry.currency(poolId).addr(), pricePerUnit);
        IERC7726 _valuation = holdings.valuation(poolId, scId, assetId);
        holdings.updateValuation(poolId, scId, assetId, transientValuation);

        accounting.unlock(poolId);
        updateHolding(scId, assetId);
        accounting.lock();

        holdings.updateValuation(poolId, scId, assetId, _valuation);
    }

    /// @inheritdoc IHubGatewayHandler
    function updateJournal(PoolId poolId, JournalEntry[] memory debits, JournalEntry[] memory credits) external auth {
        accounting.unlock(poolId);
        _updateJournal(debits, credits);
        accounting.lock();
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
    // view / pure methods
    //----------------------------------------------------------------------------------------------

    /// @dev Ensure the method is protected (see `_protected()`) and the pool is unlocked,
    /// which mean the method must be called though `execute()`
    function _protectedAndUnlocked() internal protected {
        require(!unlockedPoolId.isNull(), IHub.PoolLocked());
    }

    /// @dev Ensure the method can be used without reentrancy issues
    function _protected() internal protected {}

    /// @notice Send native tokens to the gateway for transaction payment if it's not in a multicall.
    function _pay() internal {
        if (!gateway.isBatching()) {
            gateway.payTransaction{value: msg.value}();
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
