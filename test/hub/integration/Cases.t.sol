// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "test/hub/integration/BaseTest.sol";

contract TestCases is BaseTest {
    using CastLib for string;
    using CastLib for bytes32;
    using MathLib for *;
    using MessageLib for *;

    /// forge-config: default.isolate = true
    function testPoolCreation() public returns (PoolId poolId, ShareClassId scId) {
        cv.registerAsset(USDC_C2, 6);
        cv.registerAsset(EUR_STABLE_C2, 12);

        vm.prank(ADMIN);
        poolId = guardian.createPool(FM, USD);

        scId = shareClassManager.previewNextShareClassId(poolId);

        vm.startPrank(FM);
        hub.setPoolMetadata(poolId, bytes("Testing pool"));
        hub.addShareClass(poolId, SC_NAME, SC_SYMBOL, SC_SALT, bytes(""));
        hub.notifyPool{value: GAS}(poolId, CHAIN_CV);
        hub.notifyShareClass{value: GAS}(poolId, CHAIN_CV, scId, SC_HOOK);
        hub.createHolding(poolId, scId, USDC_C2, identityValuation, false, 0x01);
        hub.createHolding(poolId, scId, EUR_STABLE_C2, transientValuation, false, 0x02);
        hub.updateContract{value: GAS}(
            poolId,
            CHAIN_CV,
            scId,
            bytes32("target"),
            MessageLib.UpdateContractVaultUpdate({
                vaultOrFactory: bytes32("factory"),
                assetId: USDC_C2.raw(),
                kind: uint8(VaultUpdateKind.DeployAndLink)
            }).serialize()
        );
        vm.stopPrank();

        assertEq(hubRegistry.metadata(poolId), "Testing pool");
        assertEq(shareClassManager.exists(poolId, scId), true);

        MessageLib.NotifyPool memory m0 = MessageLib.deserializeNotifyPool(cv.lastMessages(0));
        assertEq(m0.poolId, poolId.raw());

        MessageLib.NotifyShareClass memory m1 = MessageLib.deserializeNotifyShareClass(cv.lastMessages(1));
        assertEq(m1.poolId, poolId.raw());
        assertEq(m1.scId, scId.raw());
        assertEq(m1.name, SC_NAME);
        assertEq(m1.symbol, SC_SYMBOL.toBytes32());
        assertEq(m1.decimals, 18);
        assertEq(m1.salt, SC_SALT);
        assertEq(m1.hook, SC_HOOK);

        MessageLib.UpdateContract memory m2 = MessageLib.deserializeUpdateContract(cv.lastMessages(2));
        assertEq(m2.scId, scId.raw());
        assertEq(m2.target, bytes32("target"));

        MessageLib.UpdateContractVaultUpdate memory m3 = MessageLib.deserializeUpdateContractVaultUpdate(m2.payload);
        assertEq(m3.assetId, USDC_C2.raw());
        assertEq(m3.vaultOrFactory, bytes32("factory"));
        assertEq(m3.kind, uint8(VaultUpdateKind.DeployAndLink));

        cv.resetMessages();
    }

    /// forge-config: default.isolate = true
    function testDeposit() public returns (PoolId poolId, ShareClassId scId) {
        (poolId, scId) = testPoolCreation();

        cv.requestDeposit(poolId, scId, USDC_C2, INVESTOR, INVESTOR_AMOUNT);

        IERC7726 valuation = holdings.valuation(poolId, scId, USDC_C2);

        vm.startPrank(FM);
        hub.approveDeposits(poolId, scId, USDC_C2, APPROVED_INVESTOR_AMOUNT, valuation);
        hub.issueShares(poolId, scId, USDC_C2, NAV_PER_SHARE);
        vm.stopPrank();

        vm.prank(ANY);
        vm.deal(ANY, GAS);
        hub.claimDeposit{value: GAS}(poolId, scId, USDC_C2, INVESTOR);

        assertEq(cv.messageCount(), 2);

        MessageLib.ApprovedDeposits memory m0 = MessageLib.deserializeApprovedDeposits(cv.lastMessages(0));
        assertEq(m0.poolId, poolId.raw());
        assertEq(m0.scId, scId.raw());
        assertEq(m0.assetId, USDC_C2.raw());
        assertEq(m0.assetAmount, APPROVED_INVESTOR_AMOUNT);

        MessageLib.FulfilledDepositRequest memory m1 = MessageLib.deserializeFulfilledDepositRequest(cv.lastMessages(1));
        assertEq(m1.poolId, poolId.raw());
        assertEq(m1.scId, scId.raw());
        assertEq(m1.investor, INVESTOR);
        assertEq(m1.assetId, USDC_C2.raw());
        assertEq(m1.assetAmount, APPROVED_INVESTOR_AMOUNT);
        assertEq(m1.shareAmount, SHARE_AMOUNT);

        cv.resetMessages();
    }

    /// forge-config: default.isolate = true
    function testRedeem() public returns (PoolId poolId, ShareClassId scId) {
        (poolId, scId) = testDeposit();

        cv.requestRedeem(poolId, scId, USDC_C2, INVESTOR, SHARE_AMOUNT);

        IERC7726 valuation = holdings.valuation(poolId, scId, USDC_C2);
        uint128 revokedAssetAmount =
            NAV_PER_SHARE.mulUint128(uint128(valuation.getQuote(APPROVED_SHARE_AMOUNT, USD.addr(), USDC_C2.addr())));

        vm.startPrank(FM);
        hub.approveRedeems(poolId, scId, USDC_C2, APPROVED_SHARE_AMOUNT);
        hub.revokeShares(poolId, scId, USDC_C2, NAV_PER_SHARE, valuation);
        vm.stopPrank();

        vm.prank(ANY);
        vm.deal(ANY, GAS);
        hub.claimRedeem{value: GAS}(poolId, scId, USDC_C2, INVESTOR);

        assertEq(cv.messageCount(), 2);

        MessageLib.RevokedShares memory m0 = MessageLib.deserializeRevokedShares(cv.lastMessages(0));
        assertEq(m0.poolId, poolId.raw());
        assertEq(m0.scId, scId.raw());
        assertEq(m0.assetId, USDC_C2.raw());
        assertEq(m0.assetAmount, revokedAssetAmount);

        MessageLib.FulfilledRedeemRequest memory m1 = MessageLib.deserializeFulfilledRedeemRequest(cv.lastMessages(1));
        assertEq(m1.poolId, poolId.raw());
        assertEq(m1.scId, scId.raw());
        assertEq(m1.investor, INVESTOR);
        assertEq(m1.assetId, USDC_C2.raw());
        assertEq(m1.assetAmount, revokedAssetAmount);
        assertEq(m1.shareAmount, APPROVED_SHARE_AMOUNT);
    }

    /// forge-config: default.isolate = true
    function testCalUpdateJournal() public {
        (PoolId poolId, ShareClassId scId) = testPoolCreation();

        AccountId extraAccountId = newAccountId(123, uint8(AccountType.Asset));

        vm.prank(FM);
        hub.createAccount(poolId, extraAccountId, true);

        (JournalEntry[] memory debits, uint256 i) = (new JournalEntry[](3), 0);
        debits[i++] = JournalEntry(1000, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Asset)));
        debits[i++] = JournalEntry(250, extraAccountId);
        debits[i++] = JournalEntry(130, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Equity)));

        (JournalEntry[] memory credits, uint256 j) = (new JournalEntry[](2), 0);
        credits[j++] = JournalEntry(1250, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Equity)));
        credits[j++] = JournalEntry(130, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Loss)));

        cv.updateJournal(poolId, debits, credits);
    }

    /// forge-config: default.isolate = true
    function testCalUpdateHolding() public {
        (PoolId poolId, ShareClassId scId) = testPoolCreation();
        uint128 poolDecimals = (10 ** hubRegistry.decimals(USD.raw())).toUint128();
        uint128 assetDecimals = (10 ** hubRegistry.decimals(USDC_C2.raw())).toUint128();

        JournalEntry[] memory debits = new JournalEntry[](0);
        (JournalEntry[] memory credits, uint256 i) = (new JournalEntry[](1), 0);
        credits[i++] =
            JournalEntry(130 * poolDecimals, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Gain)));

        cv.updateHoldingAmount(poolId, scId, USDC_C2, 1000 * assetDecimals, D18.wrap(1e18), true, debits, credits);

        assertEq(holdings.amount(poolId, scId, USDC_C2), 1000 * assetDecimals);
        assertEq(holdings.value(poolId, scId, USDC_C2), 1000 * poolDecimals);
        assertEq(
            accounting.accountValue(poolId, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Gain))),
            int128(130 * poolDecimals)
        );
        assertEq(
            accounting.accountValue(poolId, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Equity))),
            int128(870 * poolDecimals)
        );

        (debits, i) = (new JournalEntry[](1), 0);
        debits[i++] =
            JournalEntry(12 * poolDecimals, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Expense)));
        (credits, i) = (new JournalEntry[](1), 0);
        credits[i++] =
            JournalEntry(12 * poolDecimals, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Loss)));

        cv.updateHoldingAmount(poolId, scId, USDC_C2, 500 * assetDecimals, D18.wrap(1e18), false, debits, credits);

        assertEq(holdings.amount(poolId, scId, USDC_C2), 500 * assetDecimals);
        assertEq(holdings.value(poolId, scId, USDC_C2), 500 * poolDecimals);
        assertEq(
            accounting.accountValue(poolId, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Loss))),
            int128(12 * poolDecimals)
        );
        assertEq(
            accounting.accountValue(poolId, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Expense))),
            int128(12 * poolDecimals)
        );
        assertEq(
            accounting.accountValue(poolId, holdings.accountId(poolId, scId, USDC_C2, uint8(AccountType.Equity))),
            // 1000 - 130 - (500-12) = 382
            int128(382 * poolDecimals)
        );
    }

    /// forge-config: default.isolate = true
    function testCalUpdateShares() public {
        (PoolId poolId, ShareClassId scId) = testPoolCreation();

        cv.updateShares(poolId, scId, 100, true);

        (uint128 totalIssuance,) = shareClassManager.metrics(scId);
        assertEq(totalIssuance, 100);

        cv.updateShares(poolId, scId, 45, false);

        (uint128 totalIssuance2,) = shareClassManager.metrics(scId);
        assertEq(totalIssuance2, 55);
    }

    function testNotifyPricePoolPerShare() public {
        (PoolId poolId, ShareClassId scId) = testPoolCreation();
        D18 sharePrice = d18(100, 1);
        D18 identityPrice = d18(1, 1);
        D18 poolPerEurPrice = d18(4, 1);
        AssetId poolCurrency = hubRegistry.currency(poolId);

        transientValuation.setPrice(EUR_STABLE_C2.addr(), poolCurrency.addr(), poolPerEurPrice);

        vm.startPrank(FM);
        hub.updatePricePoolPerShare(poolId, scId, sharePrice, "");
        hub.notifyAssetPrice{value: GAS}(poolId, scId, EUR_STABLE_C2);
        hub.notifyAssetPrice{value: GAS}(poolId, scId, USDC_C2);
        hub.notifySharePrice{value: GAS}(poolId, CHAIN_CV, scId);
        vm.stopPrank();

        assertEq(cv.messageCount(), 3);

        MessageLib.NotifyPricePoolPerShare memory m0 = MessageLib.deserializeNotifyPricePoolPerShare(cv.popMessage());
        assertEq(m0.poolId, poolId.raw());
        assertEq(m0.scId, scId.raw());
        assertEq(m0.price, sharePrice.raw(), "Share price mismatch");
        assertEq(m0.timestamp, block.timestamp.toUint64());

        MessageLib.NotifyPricePoolPerAsset memory m1 = MessageLib.deserializeNotifyPricePoolPerAsset(cv.popMessage());
        assertEq(m1.poolId, poolId.raw());
        assertEq(m1.scId, scId.raw());
        assertEq(m1.assetId, USDC_C2.raw());
        assertEq(m1.price, identityPrice.inner(), "USDC price mismatch");
        assertEq(m1.timestamp, block.timestamp.toUint64());

        MessageLib.NotifyPricePoolPerAsset memory m2 = MessageLib.deserializeNotifyPricePoolPerAsset(cv.popMessage());
        assertEq(m2.poolId, poolId.raw());
        assertEq(m2.scId, scId.raw());
        assertEq(m2.assetId, EUR_STABLE_C2.raw());
        assertEq(m2.price, poolPerEurPrice.inner(), "EUR price mismatch");
        assertEq(m2.timestamp, block.timestamp.toUint64());
    }
}
