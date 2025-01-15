// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {SingleShareClass, Epoch, EpochRatio, UserOrder, AssetEpochState} from "src/SingleShareClass.sol";
import {PoolId} from "src/types/PoolId.sol";
import {D18, d18} from "src/types/D18.sol";
import {IERC7726Ext} from "src/interfaces/IERC7726.sol";
import {IAuth} from "src/interfaces/IAuth.sol";
import {MathLib} from "src/libraries/MathLib.sol";
import {IShareClassManager} from "src/interfaces/IShareClassManager.sol";
import {ISingleShareClass} from "src/interfaces/ISingleShareClass.sol";
import {IPoolRegistry} from "src/interfaces/IPoolRegistry.sol";
import {IERC20Metadata} from "src/interfaces/IERC20Metadata.sol";

uint64 constant POOL_ID = 1;
bytes16 constant SHARE_CLASS_ID = bytes16(keccak256(abi.encode(PoolId.wrap(POOL_ID), 0)));
address constant POOL_CURRENCY = address(840);
address constant USDC = address(0x0123456);
address constant OTHER_STABLE = address(0x01234567);
uint256 constant DENO_USDC = 10 ** 6;
uint256 constant DENO_OTHER_STABLE = 10 ** 12;
uint256 constant DENO_POOL = 10 ** 4;
uint256 constant MIN_REQUEST_AMOUNT = 1e10;
uint256 constant MAX_REQUEST_AMOUNT = 1e40;
bool constant WITH_TRANSIENT = false;

contract PoolRegistryMock {
    function currency(PoolId) external pure returns (IERC20Metadata) {
        return IERC20Metadata(POOL_CURRENCY);
    }
}

contract OracleMock is IERC7726Ext {
    using MathLib for uint256;

    uint256 private constant _ONE = 1e18;

    function getQuote(uint256 baseAmount, address base, address quote) external view returns (uint256 quoteAmount) {
        return this.getFactor(base, quote).mulUint256(baseAmount);
    }

    function getFactor(address base, address quote) external pure returns (D18 factor) {
        // NOTE: Implicitly refer to D18 factors, i.e. 0.1 = 1e17
        if (base == USDC && quote == OTHER_STABLE) {
            return d18(_ONE.mulDiv(DENO_OTHER_STABLE, DENO_USDC).toUint128());
        } else if (base == USDC && quote == POOL_CURRENCY) {
            return d18(_ONE.mulDiv(DENO_POOL, DENO_USDC).toUint128());
        } else if (base == OTHER_STABLE && quote == USDC) {
            return d18(_ONE.mulDiv(DENO_USDC, DENO_OTHER_STABLE).toUint128());
        } else if (base == OTHER_STABLE && quote == POOL_CURRENCY) {
            return d18(_ONE.mulDiv(DENO_POOL, DENO_OTHER_STABLE).toUint128());
        } else if (base == POOL_CURRENCY && quote == USDC) {
            return d18(_ONE.mulDiv(DENO_USDC, DENO_POOL).toUint128());
        } else if (base == POOL_CURRENCY && quote == OTHER_STABLE) {
            return d18(_ONE.mulDiv(DENO_OTHER_STABLE, DENO_POOL).toUint128());
        } else if (base == POOL_CURRENCY && quote == address(bytes20(SHARE_CLASS_ID))) {
            return d18(_ONE.toUint128());
        } else {
            revert("Unsupported factor pair");
        }
    }
}

// TODO(@wischli): Remove before merge
contract OracleMockTest is Test {
    using MathLib for uint256;

    OracleMock public oracleMock = new OracleMock();

    function testGetQuoteUsdcToPool() public view {
        uint256 amount = 1e7;

        assertEq(oracleMock.getQuote(amount, USDC, POOL_CURRENCY), 1e5);
        assertEq(oracleMock.getQuote(amount, POOL_CURRENCY, USDC), 1e9);
    }

    function testGetFactorUsdcToPool() public view {
        assertEq(oracleMock.getFactor(USDC, POOL_CURRENCY).inner(), 1e16);
        assertEq(oracleMock.getFactor(POOL_CURRENCY, USDC).inner(), 1e20);
    }

    function testGetQuoteOtherStableToPool() public view {
        uint256 amount = 1e20;

        assertEq(oracleMock.getQuote(amount, OTHER_STABLE, POOL_CURRENCY), 1e12);
        assertEq(oracleMock.getQuote(amount, POOL_CURRENCY, OTHER_STABLE), 1e28);
    }

    function testGetFactorOtherStableToPool() public view {
        assertEq(oracleMock.getFactor(OTHER_STABLE, POOL_CURRENCY).inner(), 1e10);
        assertEq(oracleMock.getFactor(POOL_CURRENCY, OTHER_STABLE).inner(), 1e26);
    }
}

abstract contract SingleShareClassBaseTest is Test {
    using MathLib for uint256;

    SingleShareClass public shareClass;

    OracleMock oracleMock = new OracleMock();
    PoolRegistryMock poolRegistryMock = new PoolRegistryMock();

    PoolId poolId = PoolId.wrap(POOL_ID);
    bytes16 shareClassId = SHARE_CLASS_ID;
    address poolRegistryAddress = makeAddr("poolRegistry");
    address investor = makeAddr("investor");

    modifier notThisContract(address addr) {
        vm.assume(address(this) != addr);
        _;
    }

    function setUp() public virtual {
        shareClass = new SingleShareClass(poolRegistryAddress, address(this));
        shareClass.addShareClass(poolId, bytes(""));

        // Mock IPoolRegistry.currency call
        vm.mockCall(
            poolRegistryAddress,
            abi.encodeWithSelector(IPoolRegistry.currency.selector, poolId),
            abi.encode(IERC20Metadata(POOL_CURRENCY))
        );
        assertEq(address(IPoolRegistry(poolRegistryAddress).currency(poolId)), address(IERC20Metadata(POOL_CURRENCY)));
    }

    function _assertDepositRequestEq(bytes16 shareClassId_, address asset, address investor_, UserOrder memory expected)
        internal
        view
    {
        (uint256 pending, uint32 lastUpdate) = shareClass.depositRequest(shareClassId_, asset, investor_);

        assertEq(pending, expected.pending, "pending mismatch");
        assertEq(lastUpdate, expected.lastUpdate, "lastUpdate mismatch");
    }

    function _assertRedeemRequestEq(bytes16 shareClassId_, address asset, address investor_, UserOrder memory expected)
        internal
        view
    {
        (uint256 pending, uint32 lastUpdate) = shareClass.redeemRequest(shareClassId_, asset, investor_);

        assertEq(pending, expected.pending, "pending mismatch");
        assertEq(lastUpdate, expected.lastUpdate, "lastUpdate mismatch");
    }

    function _assertEpochEq(bytes16 shareClassId_, uint32 epochId, Epoch memory expected) internal view {
        (uint256 approvedDeposits, uint256 approvedShares) = shareClass.epoch(shareClassId_, epochId);

        assertEq(approvedDeposits, expected.approvedDeposits, "approveDeposits mismatch");
        assertEq(approvedShares, expected.approvedShares, "approvedShares mismatch");
    }

    function _assertEpochRatioEq(bytes16 shareClassId_, address assetId, uint32 epochId, EpochRatio memory expected)
        internal
        view
    {
        (D18 redeemRatio, D18 depositRatio, D18 assetToPoolQuote, D18 poolToShareQuote) =
            shareClass.epochRatio(shareClassId_, assetId, epochId);

        assertEq(poolToShareQuote.inner(), expected.poolToShareQuote.inner(), "poolToShareQuote mismatch");
        assertEq(redeemRatio.inner(), expected.redeemRatio.inner(), "redeemRatio mismatch");
        assertEq(depositRatio.inner(), expected.depositRatio.inner(), "depositRatio mismatch");
        assertEq(assetToPoolQuote.inner(), expected.assetToPoolQuote.inner(), "assetToPoolQuote mismatch");
    }

    function _assertAssetEpochStateEq(bytes16 shareClassId_, address assetId, AssetEpochState memory expected)
        internal
        view
    {
        (uint32 latestDepositApproval, uint32 latestRedeemApproval, uint32 latestIssuance, uint32 latestRevocation) =
            shareClass.assetEpochState(shareClassId_, assetId);

        assertEq(latestDepositApproval, expected.latestDepositApproval, "latestDepositApproval mismatch");
        assertEq(latestRedeemApproval, expected.latestRedeemApproval, "latestRedeemApproval mismatch");
        assertEq(latestIssuance, expected.latestIssuance, "latestIssuance mismatch");
        assertEq(latestRevocation, expected.latestRevocation, "latestRevocation mismatch");
    }

    /// @dev Temporarily necessary for tests until forge supports transient storage setting, i.e.
    /// https://github.com/foundry-rs/foundry/issues/8165 is merged
    function _resetTransientEpochIncrement() internal {
        if (!WITH_TRANSIENT) {
            // Slot 1 for `_epochIncrement`, `poolRegistry`, and `shareClassIdCounter`
            bytes32 slot = bytes32(uint256(1));

            // Load the current value of the storage slot
            bytes32 currentValue = vm.load(address(shareClass), slot);

            // Clear only the first 4 bytes (corresponding to `_epochIncrement`)
            // and preserve the rest
            bytes32 clearedValue = currentValue & ~bytes32(uint256(0xFFFFFFFF)) // Clear `_epochIncrement` (first 4
                // bytes)
                & ~(bytes32(uint256(0xFFFFFFFF)) << 192); // Preserve `shareClassIdCounter` (last 4 bytes)

            // Set `_epochIncrement` to 0
            vm.store(address(shareClass), slot, clearedValue);
        }
    }

    function usdcToPool(uint256 usdcAmount) internal pure returns (uint256 poolAmount) {
        return usdcAmount / 100;
    }

    function poolToUsdc(uint256 poolAmount) internal pure returns (uint256 usdcAmount) {
        return poolAmount * 100;
    }
}

///@dev Contains all simple tests which are expected to succeed
contract SingleShareClassSimpleTest is SingleShareClassBaseTest {
    using MathLib for uint256;

    function testDeployment(address nonWard) public view notThisContract(poolRegistryAddress) {
        vm.assume(nonWard != address(shareClass.poolRegistry()) && nonWard != address(this));

        assertEq(address(shareClass.poolRegistry()), poolRegistryAddress);
        assertEq(shareClass.shareClassIds(poolId), shareClassId);

        assertEq(shareClass.wards(address(this)), 1);
        assertEq(shareClass.wards(address(shareClass.poolRegistry())), 0);

        assertEq(shareClass.wards(nonWard), 0);
    }

    function testFile() public {
        address poolRegistryNew = makeAddr("poolRegistryNew");
        vm.expectEmit(true, true, true, true);
        emit ISingleShareClass.File("poolRegistry", poolRegistryNew);
        shareClass.file("poolRegistry", poolRegistryNew);

        assertEq(address(shareClass.poolRegistry()), poolRegistryNew);
    }

    function testDefaultGetShareClassNavPerShare() public view notThisContract(poolRegistryAddress) {
        (D18 navPerShare, uint256 nav) = shareClass.shareClassNavPerShare(poolId, shareClassId);
        assertEq(nav, 0);
        assertEq(navPerShare.inner(), 0);
    }
}

///@dev Contains all deposit related tests which are expected to succeed and don't make use of transient storage
contract SingleShareClassDepositsNonTransientTest is SingleShareClassBaseTest {
    using MathLib for uint256;

    function testRequestDeposit(uint256 amount) public notThisContract(poolRegistryAddress) {
        amount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));

        assertEq(shareClass.pendingDeposit(shareClassId, USDC), 0);
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(0, 0));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedDepositRequest(poolId, shareClassId, 1, investor, USDC, amount, amount);
        shareClass.requestDeposit(poolId, shareClassId, amount, investor, USDC);

        assertEq(shareClass.pendingDeposit(shareClassId, USDC), amount);
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(amount, 1));
    }

    function testCancelDepositRequest(uint256 amount) public notThisContract(poolRegistryAddress) {
        amount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        shareClass.requestDeposit(poolId, shareClassId, amount, investor, USDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedDepositRequest(poolId, shareClassId, 1, investor, USDC, 0, 0);
        shareClass.cancelDepositRequest(poolId, shareClassId, investor, USDC);

        assertEq(shareClass.pendingDeposit(shareClassId, USDC), 0);
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(0, 1));
    }

    function testApproveDepositsSingleAssetManyInvestors(
        uint256 depositAmount,
        uint8 numInvestors,
        uint128 approvalRatio_
    ) public notThisContract(poolRegistryAddress) {
        depositAmount = uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        numInvestors = uint8(bound(numInvestors, 1, 100));

        uint256 deposits = 0;
        for (uint16 i = 0; i < numInvestors; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            uint256 investorDeposit = depositAmount + i;
            deposits += investorDeposit;
            shareClass.requestDeposit(poolId, shareClassId, investorDeposit, investor, USDC);

            assertEq(shareClass.pendingDeposit(shareClassId, USDC), deposits);
        }
        assertEq(shareClass.epochId(poolId), 1);

        uint256 approvedUSDC = approvalRatio.mulUint256(deposits);
        uint256 approvedPool = usdcToPool(approvedUSDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.NewEpoch(poolId, 2);
        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ApprovedDeposits(
            poolId, shareClassId, 1, USDC, approvalRatio, approvedPool, approvedUSDC, deposits - approvedUSDC, d18(1e16)
        );
        shareClass.approveDeposits(poolId, shareClassId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.pendingDeposit(shareClassId, USDC), deposits - approvedUSDC);

        // Only one epoch should have passed
        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(shareClassId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(1e16), d18(0)));
    }

    function testApproveDepositsTwoAssetsSameEpoch(uint256 depositAmount, uint128 approvalRatio)
        public
        notThisContract(poolRegistryAddress)
    {
        uint256 depositAmountUsdc = uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        uint256 depositAmountOther = uint256(bound(depositAmount, 1e8, MAX_REQUEST_AMOUNT));
        D18 approvalRatioUsdc = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        D18 approvalRatioOther = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        address investorUsdc = makeAddr("investorUsdc");
        address investorOther = makeAddr("investorOther");

        uint256 approvedPool = d18(1e16).mulUint256(approvalRatioUsdc.mulUint256(depositAmountUsdc))
            + d18(1e10).mulUint256(approvalRatioOther.mulUint256(depositAmountOther));

        shareClass.requestDeposit(poolId, shareClassId, depositAmountUsdc, investorUsdc, USDC);
        shareClass.requestDeposit(poolId, shareClassId, depositAmountOther, investorOther, OTHER_STABLE);

        shareClass.approveDeposits(poolId, shareClassId, approvalRatioUsdc, USDC, oracleMock);
        shareClass.approveDeposits(poolId, shareClassId, approvalRatioOther, OTHER_STABLE, oracleMock);

        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(shareClassId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(d18(0), approvalRatioUsdc, d18(1e16), d18(0)));
        _assertEpochRatioEq(shareClassId, OTHER_STABLE, 1, EpochRatio(d18(0), approvalRatioOther, d18(1e10), d18(0)));
    }

    function testIssueSharesSingleEpoch(uint256 depositAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        depositAmount = uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare, 1e14, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 approvedUSDC = approvalRatio.mulUint256(depositAmount);
        uint256 approvedPool = usdcToPool(approvedUSDC);
        uint256 shares = poolToShareQuote.mulUint256(approvedPool);

        shareClass.requestDeposit(poolId, shareClassId, depositAmount, investor, USDC);
        shareClass.approveDeposits(poolId, shareClassId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.totalIssuance(shareClassId), 0);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(1, 0, 0, 0));

        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(shareClass.totalIssuance(shareClassId), shares);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(1, 0, 1, 0));
        _assertEpochEq(shareClassId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(1e16), poolToShareQuote));
    }

    function testClaimDepositSingleEpoch(uint256 depositAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        depositAmount = uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 approvedUSDC = approvalRatio.mulUint256(depositAmount);
        uint256 approvedPool = usdcToPool(approvedUSDC);
        uint256 shares = poolToShareQuote.mulUint256(approvedPool);
        uint256 pending = depositAmount - approvedUSDC;

        shareClass.requestDeposit(poolId, shareClassId, depositAmount, investor, USDC);
        shareClass.approveDeposits(poolId, shareClassId, approvalRatio, USDC, oracleMock);
        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(shareClass.totalIssuance(shareClassId), shares);
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(depositAmount, 1));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ClaimedDeposit(poolId, shareClassId, 1, investor, USDC, approvedUSDC, pending, shares);
        (uint256 userShares, uint256 payment) = shareClass.claimDeposit(poolId, shareClassId, investor, USDC);

        assertEq(shares, userShares, "shares mismatch");
        assertEq(approvedUSDC, payment, "payment mismatch");
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(pending, 2));
        assertEq(shareClass.totalIssuance(shareClassId), shares);

        // Ensure another claim has no impact
        (userShares, payment) = shareClass.claimDeposit(poolId, shareClassId, investor, USDC);
        assertEq(userShares + payment, 0, "replay must not be possible");
    }
}

///@dev Contains all redeem related tests which are expected to succeed and don't make use of transient storage
contract SingleShareClassRedeemsNonTransientTest is SingleShareClassBaseTest {
    using MathLib for uint256;

    function testRequestRedeem(uint256 amount) public notThisContract(poolRegistryAddress) {
        amount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));

        assertEq(shareClass.pendingRedeem(shareClassId, USDC), 0);
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(0, 0));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedRedeemRequest(poolId, shareClassId, 1, investor, USDC, amount, amount);
        shareClass.requestRedeem(poolId, shareClassId, amount, investor, USDC);

        assertEq(shareClass.pendingRedeem(shareClassId, USDC), amount);
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(amount, 1));
    }

    function testCancelRedeemRequest(uint256 amount) public notThisContract(poolRegistryAddress) {
        amount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        shareClass.requestRedeem(poolId, shareClassId, amount, investor, USDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedRedeemRequest(poolId, shareClassId, 1, investor, USDC, 0, 0);
        shareClass.cancelRedeemRequest(poolId, shareClassId, investor, USDC);

        assertEq(shareClass.pendingRedeem(shareClassId, USDC), 0);
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(0, 1));
    }

    function testApproveRedeemsSingleAssetManyInvestors(uint256 amount, uint8 numInvestors, uint128 approvalRatio_)
        public
    {
        amount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        numInvestors = uint8(bound(numInvestors, 1, 100));

        uint256 totalRedeems = 0;
        for (uint16 i = 0; i < numInvestors; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            uint256 investorRedeem = amount + i;
            totalRedeems += investorRedeem;
            shareClass.requestRedeem(poolId, shareClassId, investorRedeem, investor, USDC);

            assertEq(shareClass.pendingRedeem(shareClassId, USDC), totalRedeems);
        }
        assertEq(shareClass.epochId(poolId), 1);

        uint256 approvedShares = approvalRatio.mulUint256(totalRedeems);
        uint256 pendingRedeems_ = totalRedeems - approvedShares;

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.NewEpoch(poolId, 2);
        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ApprovedRedeems(
            poolId, shareClassId, 1, USDC, approvalRatio, approvedShares, pendingRedeems_, d18(1e16)
        );
        shareClass.approveRedeems(poolId, shareClassId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.pendingRedeem(shareClassId, USDC), pendingRedeems_);

        // Only one epoch should have passed
        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(shareClassId, 1, Epoch(0, approvedShares));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), d18(0)));
    }

    function testApproveRedeemsTwoAssetsSameEpoch(uint256 redeemAmount, uint128 approvalRatio)
        public
        notThisContract(poolRegistryAddress)
    {
        uint256 redeemAmountUsdc = uint256(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        uint256 redeemAmountOther = uint256(bound(redeemAmount, 1e8, MAX_REQUEST_AMOUNT));
        D18 approvalRatioUsdc = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        D18 approvalRatioOther = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        address investorUsdc = makeAddr("investorUsdc");
        address investorOther = makeAddr("investorOther");
        uint256 approvedShares =
            approvalRatioUsdc.mulUint256(redeemAmountUsdc) + approvalRatioOther.mulUint256(redeemAmountOther);

        shareClass.requestRedeem(poolId, shareClassId, redeemAmountUsdc, investorUsdc, USDC);
        shareClass.requestRedeem(poolId, shareClassId, redeemAmountOther, investorOther, OTHER_STABLE);

        (uint256 approvedUsdc, uint256 pendingUsdc) =
            shareClass.approveRedeems(poolId, shareClassId, approvalRatioUsdc, USDC, oracleMock);
        (uint256 approvedOther, uint256 pendingOther) =
            shareClass.approveRedeems(poolId, shareClassId, approvalRatioOther, OTHER_STABLE, oracleMock);

        assertEq(shareClass.epochId(poolId), 2);
        assertEq(approvedUsdc, approvalRatioUsdc.mulUint256(redeemAmountUsdc), "approved shares USDC mismatch");
        assertEq(
            pendingUsdc,
            redeemAmountUsdc - approvalRatioUsdc.mulUint256(redeemAmountUsdc),
            "pending shares USDC mismatch"
        );
        assertEq(
            approvedOther, approvalRatioOther.mulUint256(redeemAmountOther), "approved shares OtherCurrency mismatch"
        );
        assertEq(
            pendingOther,
            redeemAmountOther - approvalRatioOther.mulUint256(redeemAmountOther),
            "pending shares OtherCurrency mismatch"
        );

        _assertEpochEq(shareClassId, 1, Epoch(0, approvedShares));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(approvalRatioUsdc, d18(0), d18(1e16), d18(0)));
        _assertEpochRatioEq(shareClassId, OTHER_STABLE, 1, EpochRatio(approvalRatioOther, d18(0), d18(1e10), d18(0)));
    }

    function testRevokeSharesSingleEpoch(uint256 redeemAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        redeemAmount = uint256(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare, 1e14, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 approvedRedeem = approvalRatio.mulUint256(redeemAmount);
        uint256 poolAmount = poolToShareQuote.reciprocalMulUint256(approvedRedeem);
        uint256 assetAmount = poolToUsdc(poolAmount);

        // Mock total issuance to equal redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(shareClassId, uint256(WITH_TRANSIENT ? 7 : 8))),
            bytes32(uint256(redeemAmount))
        );
        assertEq(shareClass.totalIssuance(shareClassId), redeemAmount);

        shareClass.requestRedeem(poolId, shareClassId, redeemAmount, investor, USDC);
        shareClass.approveRedeems(poolId, shareClassId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.totalIssuance(shareClassId), redeemAmount);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(0, 1, 0, 0));

        (uint256 payoutAssetAmount, uint256 payoutPoolAmount) =
            shareClass.revokeShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(assetAmount, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(poolAmount, payoutPoolAmount, "payout pool amount mismatch");

        assertEq(shareClass.totalIssuance(shareClassId), redeemAmount - approvedRedeem);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(0, 1, 0, 1));

        _assertEpochEq(shareClassId, 1, Epoch(0, approvedRedeem));
        _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), poolToShareQuote));
    }

    function testClaimRedeemSingleEpoch(uint256 redeemAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        redeemAmount = uint256(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 approvedRedeem = approvalRatio.mulUint256(redeemAmount);
        uint256 pendingRedeem = redeemAmount - approvedRedeem;
        uint256 payout = poolToUsdc(poolToShareQuote.reciprocalMulUint256(approvedRedeem));

        // Mock total issuance to equal redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(shareClassId, uint256(WITH_TRANSIENT ? 7 : 8))),
            bytes32(uint256(redeemAmount))
        );
        assertEq(shareClass.totalIssuance(shareClassId), redeemAmount);

        shareClass.requestRedeem(poolId, shareClassId, redeemAmount, investor, USDC);
        shareClass.approveRedeems(poolId, shareClassId, approvalRatio, USDC, oracleMock);
        shareClass.revokeShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(shareClass.totalIssuance(shareClassId), pendingRedeem);
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(redeemAmount, 1));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ClaimedRedeem(
            poolId, shareClassId, 1, investor, USDC, approvedRedeem, pendingRedeem, payout
        );
        (uint256 payoutAssetAmount, uint256 paymentShareAmount) =
            shareClass.claimRedeem(poolId, shareClassId, investor, USDC);

        assertEq(payout, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(approvedRedeem, paymentShareAmount, "payment shares mismatch");
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(pendingRedeem, 2));

        // Ensure another claim has no impact
        (payoutAssetAmount, paymentShareAmount) = shareClass.claimRedeem(poolId, shareClassId, investor, USDC);
        assertEq(payoutAssetAmount + paymentShareAmount, 0, "replay must not be possible");
    }
}

///@dev Contains all tests which require transient storage to reset between calls
contract SingleShareClassTransientTest is SingleShareClassBaseTest {
    using MathLib for uint256;

    function testIssueSharesManyEpochs(
        uint256 depositAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        depositAmount = uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 shares = 0;
        uint256 pendingUSDC = depositAmount;

        // Bump up latestApproval epochs
        for (uint8 i = 1; i < maxEpochId; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            _resetTransientEpochIncrement();
            shareClass.requestDeposit(poolId, shareClassId, depositAmount, investor, USDC);
            shareClass.approveDeposits(poolId, shareClassId, approvalRatio, USDC, oracleMock);
        }
        assertEq(shareClass.totalIssuance(shareClassId), 0);

        // Assert issued events
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 approvedUSDC = approvalRatio.mulUint256(pendingUSDC);
            pendingUSDC += depositAmount - approvedUSDC;
            uint256 epochShares = poolToShareQuote.mulUint256(usdcToPool(approvedUSDC));
            uint256 nav = poolToShareQuote.mulUint256(epochShares);

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.IssuedShares(poolId, shareClassId, i, poolToShareQuote, nav, epochShares);
        }

        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(maxEpochId - 1, 0, maxEpochId - 1, 0));

        // Ensure each epoch is issued separately
        pendingUSDC = depositAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 approvedUSDC = approvalRatio.mulUint256(pendingUSDC);
            pendingUSDC += depositAmount - approvedUSDC;
            uint256 approvedPool = usdcToPool(approvedUSDC);
            shares += poolToShareQuote.mulUint256(approvedPool);

            _assertEpochEq(shareClassId, i, Epoch(approvedPool, 0));
            _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(1e16), poolToShareQuote));
        }
        assertEq(shareClass.totalIssuance(shareClassId), shares, "totalIssuance mismatch");
        (D18 navPerShare, uint256 issuance) = shareClass.shareClassNavPerShare(poolId, shareClassId);
        assertEq(navPerShare.inner(), poolToShareQuote.inner());
        assertEq(issuance, shares, "totalIssuance mismatch");

        // Ensure another issuance reverts
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
    }

    function testClaimDepositManyEpochs(
        uint256 depositAmount,
        uint128 navPerShare,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        D18 poolToShareQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        depositAmount = maxEpochId * uint256(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e10, 1e16)));
        uint256 approvedUSDC = 0;
        uint256 pending = depositAmount;
        uint256 shares = 0;

        shareClass.requestDeposit(poolId, shareClassId, depositAmount, investor, USDC);

        // Approve many epochs and issue shares
        for (uint8 i = 1; i < maxEpochId; i++) {
            shareClass.approveDeposits(poolId, shareClassId, approvalRatio, USDC, oracleMock);
            shares += poolToShareQuote.mulUint256(usdcToPool(approvalRatio.mulUint256(pending)));
            approvedUSDC += approvalRatio.mulUint256(pending);
            pending = depositAmount - approvedUSDC;
            _resetTransientEpochIncrement();
        }
        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(shareClass.totalIssuance(shareClassId), shares, "totalIssuance mismatch");

        // Ensure each epoch is claimed separately
        approvedUSDC = 0;
        pending = depositAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 epochShares = poolToShareQuote.mulUint256(usdcToPool(approvalRatio.mulUint256(pending)));
            uint256 epochApprovedUSDC = approvalRatio.mulUint256(pending);
            approvedUSDC += epochApprovedUSDC;
            pending -= epochApprovedUSDC;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.ClaimedDeposit(
                poolId, shareClassId, i, investor, USDC, epochApprovedUSDC, pending, epochShares
            );
        }
        (uint256 userShares, uint256 payment) = shareClass.claimDeposit(poolId, shareClassId, investor, USDC);

        assertEq(approvedUSDC + pending, depositAmount, "approved + pending must equal request amount");
        assertEq(shares, userShares, "shares mismatch");
        assertEq(approvedUSDC, payment, "payment mismatch");
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(pending, maxEpochId));
    }

    function testRevokeSharesManyEpochs(
        uint256 redeemAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        redeemAmount = uint256(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 poolToShareQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint256 initialShares = maxEpochId * redeemAmount;
        uint256 redeemedShares = 0;
        uint256 pendingRedeems = redeemAmount;

        // Mock total issuance to equal total redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(shareClassId, uint256(WITH_TRANSIENT ? 7 : 8))),
            bytes32(uint256(initialShares))
        );

        // Bump up latestApproval epochs
        for (uint8 i = 1; i < maxEpochId; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            _resetTransientEpochIncrement();
            shareClass.requestRedeem(poolId, shareClassId, redeemAmount, investor, USDC);
            shareClass.approveRedeems(poolId, shareClassId, approvalRatio, USDC, oracleMock);
        }
        assertEq(shareClass.totalIssuance(shareClassId), initialShares);

        // Assert revoked events
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 approvedRedeems = approvalRatio.mulUint256(pendingRedeems);
            uint256 nav = poolToShareQuote.mulUint256(approvedRedeems);
            pendingRedeems += redeemAmount - approvedRedeems;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.RevokedShares(poolId, shareClassId, i, poolToShareQuote, nav, approvedRedeems);
        }

        shareClass.revokeShares(poolId, shareClassId, USDC, poolToShareQuote);
        _assertAssetEpochStateEq(shareClassId, USDC, AssetEpochState(0, maxEpochId - 1, 0, maxEpochId - 1));

        // Ensure each epoch was revoked separately
        pendingRedeems = redeemAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 approvedRedeems = approvalRatio.mulUint256(pendingRedeems);
            pendingRedeems += redeemAmount - approvedRedeems;
            redeemedShares += approvedRedeems;

            _assertEpochEq(shareClassId, i, Epoch(0, approvedRedeems));
            _assertEpochRatioEq(shareClassId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), poolToShareQuote));
        }
        assertEq(shareClass.totalIssuance(shareClassId), initialShares - redeemedShares);
        (D18 navPerShare, uint256 issuance) = shareClass.shareClassNavPerShare(poolId, shareClassId);
        assertEq(navPerShare.inner(), poolToShareQuote.inner());
        assertEq(issuance, initialShares - redeemedShares);

        // Ensure another issuance reverts
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.revokeShares(poolId, shareClassId, USDC, poolToShareQuote);
    }

    function testClaimRedeemManyEpochs(
        uint256 redeemAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        D18 poolToShareQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        redeemAmount = maxEpochId * uint256(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e10, 1e16)));
        uint256 pendingRedeem = redeemAmount;
        uint256 payout = 0;
        uint256 approvedRedeem = 0;

        // Mock total issuance to equal total redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(shareClassId, uint256(WITH_TRANSIENT ? 7 : 8))),
            bytes32(uint256(redeemAmount))
        );

        shareClass.requestRedeem(poolId, shareClassId, redeemAmount, investor, USDC);

        // Approve many epochs and revoke shares
        for (uint8 i = 1; i < maxEpochId; i++) {
            _resetTransientEpochIncrement();
            shareClass.approveRedeems(poolId, shareClassId, approvalRatio, USDC, oracleMock);
            pendingRedeem -= approvalRatio.mulUint256(pendingRedeem);
        }
        shareClass.revokeShares(poolId, shareClassId, USDC, poolToShareQuote);
        assertEq(shareClass.totalIssuance(shareClassId), pendingRedeem, "totalIssuance mismatch");

        // Ensure each epoch is claimed separately
        pendingRedeem = redeemAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint256 epochApproved = approvalRatio.mulUint256(pendingRedeem);
            uint256 epochPayout = poolToUsdc(poolToShareQuote.reciprocalMulUint256(epochApproved));
            pendingRedeem -= approvalRatio.mulUint256(pendingRedeem);
            payout += epochPayout;
            approvedRedeem += epochApproved;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.ClaimedRedeem(
                poolId, shareClassId, i, investor, USDC, epochApproved, pendingRedeem, epochPayout
            );
        }
        (uint256 payoutAssetAmount, uint256 paymentShareAmount) =
            shareClass.claimRedeem(poolId, shareClassId, investor, USDC);

        assertEq(approvedRedeem + pendingRedeem, redeemAmount, "approved + pending must equal request amount");
        assertEq(payout, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(approvedRedeem, paymentShareAmount, "payment shares mismatch");
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(pendingRedeem, maxEpochId));
    }

    function testDepositsWithRedeemsFullFlow(uint256 amount, uint128 approvalRatio, uint128 navPerShare_)
        // uint8 maxEpochId
        public
        notThisContract(poolRegistryAddress)
    {
        D18 poolToShareQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        D18 navPerShareRedeem = poolToShareQuote - d18(1e6);
        uint256 depositAmount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        uint256 redeemAmount = uint256(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 depositApprovalRatio = d18(uint128(bound(approvalRatio, 1e10, 1e16)));
        D18 redeemApprovalRatio = d18(uint128(bound(approvalRatio, 1e10, depositApprovalRatio.inner())));

        // Step 1: Do initial deposit flow with 100% deposit approval rate to add sufficient shares for later redemption
        uint32 epochId = 2;
        shareClass.requestDeposit(poolId, shareClassId, MAX_REQUEST_AMOUNT, investor, USDC);
        shareClass.approveDeposits(poolId, shareClassId, d18(1e18), USDC, oracleMock);
        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        shareClass.claimDeposit(poolId, shareClassId, investor, USDC);

        uint256 shares = poolToShareQuote.mulUint256(usdcToPool(MAX_REQUEST_AMOUNT));
        assertEq(shareClass.totalIssuance(shareClassId), shares);
        assertEq(shareClass.epochId(poolId), 2);
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(0, 2));
        _assertEpochEq(shareClassId, 1, Epoch(usdcToPool(MAX_REQUEST_AMOUNT), 0));
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(0, 2));

        // Step 2a: Deposit + redeem at same
        _resetTransientEpochIncrement();
        shareClass.requestDeposit(poolId, shareClassId, depositAmount, investor, USDC);
        shareClass.requestRedeem(poolId, shareClassId, redeemAmount, investor, USDC);
        uint256 pendingDepositUSDC = depositAmount;
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(pendingDepositUSDC, epochId));
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(redeemAmount, epochId));
        _assertEpochEq(shareClassId, epochId, Epoch(0, 0));

        // Step 2b: Approve deposits
        shareClass.approveDeposits(poolId, shareClassId, depositApprovalRatio, USDC, oracleMock);
        uint256 approvedDepositUSDC = depositApprovalRatio.mulUint256(pendingDepositUSDC);
        _assertEpochEq(shareClassId, epochId, Epoch(usdcToPool(approvedDepositUSDC), 0));

        // Step 2c: Approve redeems
        shareClass.approveRedeems(poolId, shareClassId, redeemApprovalRatio, USDC, oracleMock);
        uint256 approvedRedeem = redeemApprovalRatio.mulUint256(redeemAmount);
        _assertEpochEq(shareClassId, epochId, Epoch(usdcToPool(approvedDepositUSDC), approvedRedeem));
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(depositAmount, epochId));
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(redeemAmount, epochId));

        // Step 2d: Issue sahres
        shareClass.issueShares(poolId, shareClassId, USDC, poolToShareQuote);
        epochId += 1;
        shares += poolToShareQuote.mulUint256(usdcToPool(approvedDepositUSDC));
        assertEq(shareClass.totalIssuance(shareClassId), shares);

        // Step 2e: Revoke shares
        shareClass.revokeShares(poolId, shareClassId, USDC, navPerShareRedeem);
        shares -= approvedRedeem;
        (D18 navPerShare, uint256 issuance) = shareClass.shareClassNavPerShare(poolId, shareClassId);
        assertEq(issuance, shares);
        assertEq(navPerShare.inner(), navPerShareRedeem.inner());

        // Step 2f: Claim deposit and redeem
        shareClass.claimDeposit(poolId, shareClassId, investor, USDC);
        shareClass.claimRedeem(poolId, shareClassId, investor, USDC);
        pendingDepositUSDC -= approvedDepositUSDC;
        _assertDepositRequestEq(shareClassId, USDC, investor, UserOrder(pendingDepositUSDC, epochId));
        uint256 pendingRedeem = redeemAmount - approvedRedeem;
        _assertRedeemRequestEq(shareClassId, USDC, investor, UserOrder(pendingRedeem, epochId));
    }
}

///@dev Contains all tests which are expected to revert
contract SingleShareClassRevertsTest is SingleShareClassBaseTest {
    using MathLib for uint256;

    bytes16 wrongShareClassId = bytes16("otherId");
    address unauthorized = makeAddr("unauthorizedAddress");

    function testFile(bytes32 what) public {
        vm.assume(what != "poolRegistry");
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.UnrecognizedFileParam.selector));
        shareClass.file(what, address(0));
    }

    function testSetShareClassIdAlreadySet() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.MaxShareClassNumberExceeded.selector, 1));
        shareClass.addShareClass(poolId, bytes(""));
    }

    function testRequestDepositWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.requestDeposit(poolId, wrongShareClassId, 1, investor, USDC);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.requestDeposit(poolId, wrongShareClassId, 1, investor, USDC);
    }

    function testCancelRequestDepositWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.cancelDepositRequest(poolId, wrongShareClassId, investor, USDC);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.cancelDepositRequest(poolId, wrongShareClassId, investor, USDC);
    }

    function testRequestRedeemWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.requestRedeem(poolId, wrongShareClassId, 1, investor, USDC);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.requestRedeem(poolId, wrongShareClassId, 1, investor, USDC);
    }

    function testCancelRedeemRequestWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.cancelRedeemRequest(poolId, wrongShareClassId, investor, USDC);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.cancelRedeemRequest(poolId, wrongShareClassId, investor, USDC);
    }

    function testApproveDepositsWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.approveDeposits(poolId, wrongShareClassId, d18(1), USDC, IERC7726Ext(address(this)));

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.approveDeposits(poolId, wrongShareClassId, d18(1), USDC, IERC7726Ext(address(this)));
    }

    function testApproveRedeemsWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.approveRedeems(poolId, wrongShareClassId, d18(1), USDC, IERC7726Ext(address(this)));

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.approveRedeems(poolId, wrongShareClassId, d18(1), USDC, IERC7726Ext(address(this)));
    }

    function testIssueSharesWrongShareClassId() public {
        // Mock latestDepositApproval to epoch 1
        vm.store(
            address(shareClass),
            keccak256(abi.encode(USDC, keccak256(abi.encode(wrongShareClassId, uint256(WITH_TRANSIENT ? 10 : 11))))),
            bytes32(
                (uint256(1)) // latestDepositApproval
                    | (uint256(0) << 32) // latestRedeemApproval
                    | (uint256(0) << 64) // latestIssuance
                    | (uint256(0) << 96) // latestRevocation
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.issueShares(poolId, wrongShareClassId, USDC, d18(1));

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.issueShares(poolId, wrongShareClassId, USDC, d18(1));
    }

    function testIssueSharesUntilEpochWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.issueSharesUntilEpoch(poolId, wrongShareClassId, USDC, d18(1), 0);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.issueSharesUntilEpoch(poolId, wrongShareClassId, USDC, d18(1), 0);
    }

    function testRevokeSharesWrongShareClassId() public {
        // Mock latestRedeemApproval to epoch 1
        vm.store(
            address(shareClass),
            keccak256(abi.encode(USDC, keccak256(abi.encode(wrongShareClassId, uint256(WITH_TRANSIENT ? 10 : 11))))),
            bytes32(
                (uint256(0)) // latestDepositApproval
                    | (uint256(1) << 32) // latestRedeemApproval
                    | (uint256(0) << 64) // latestIssuance
                    | (uint256(0) << 96) // latestRevocation
            )
        );

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.revokeShares(poolId, wrongShareClassId, USDC, d18(1));

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.revokeShares(poolId, wrongShareClassId, USDC, d18(1));
    }

    function testRevokeSharesUntilEpochWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.revokeSharesUntilEpoch(poolId, wrongShareClassId, USDC, d18(1), 0);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        vm.prank(unauthorized);
        shareClass.revokeSharesUntilEpoch(poolId, wrongShareClassId, USDC, d18(1), 0);
    }

    function testClaimDepositWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.claimDeposit(poolId, wrongShareClassId, investor, USDC);
    }

    function testClaimDepositUntilEpochWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.claimDepositUntilEpoch(poolId, wrongShareClassId, investor, USDC, 0);
    }

    function testClaimRedeemWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.claimRedeem(poolId, wrongShareClassId, investor, USDC);
    }

    function testClaimRedeemUntilEpochWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.claimRedeemUntilEpoch(poolId, wrongShareClassId, investor, USDC, 0);
    }

    function testUpdateShareClassNavWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.updateShareClassNav(poolId, wrongShareClassId);
    }

    function testGetShareClassNavWrongShareClassId() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ShareClassNotFound.selector));
        shareClass.shareClassNavPerShare(poolId, wrongShareClassId);
    }

    function testAddShareClass() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.MaxShareClassNumberExceeded.selector, 1));
        shareClass.addShareClass(poolId, bytes(""));
    }

    function testIssueSharesBeforeApproval() public {
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.issueShares(poolId, shareClassId, USDC, d18(1));
    }

    function testRevokeSharesBeforeApproval() public {
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.revokeShares(poolId, shareClassId, USDC, d18(1));
    }

    function testIssueSharesUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.issueSharesUntilEpoch(poolId, shareClassId, USDC, d18(1), 2);
    }

    function testRevokeSharesUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.revokeSharesUntilEpoch(poolId, shareClassId, USDC, d18(1), 2);
    }

    function testClaimDepositUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.claimDepositUntilEpoch(poolId, shareClassId, investor, USDC, 2);
    }

    function testClaimRedeemUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.claimRedeemUntilEpoch(poolId, shareClassId, investor, USDC, 2);
    }

    function testUpdateShareClassUnsupported() public {
        vm.expectRevert(bytes("unsupported"));
        shareClass.updateShareClassNav(poolId, shareClassId);
    }

    function testUpdateUnsupported() public {
        vm.expectRevert(bytes("unsupported"));
        shareClass.update(poolId, bytes(""));
    }

    function testRequestDepositRequiresClaim() public {
        shareClass.requestDeposit(poolId, shareClassId, 1, investor, USDC);
        shareClass.approveDeposits(poolId, shareClassId, d18(1), USDC, oracleMock);

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ClaimDepositRequired.selector));
        shareClass.requestDeposit(poolId, shareClassId, 1, investor, USDC);
    }

    function testRequestRedeemRequiresClaim() public {
        shareClass.requestRedeem(poolId, shareClassId, 1, investor, USDC);
        shareClass.approveRedeems(poolId, shareClassId, d18(1), USDC, oracleMock);

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ClaimRedeemRequired.selector));
        shareClass.requestRedeem(poolId, shareClassId, 1, investor, USDC);
    }

    function testApproveDepositsAlreadyApproved() public {
        shareClass.approveDeposits(poolId, shareClassId, d18(1), USDC, oracleMock);

        vm.expectRevert(ISingleShareClass.AlreadyApproved.selector);
        shareClass.approveDeposits(poolId, shareClassId, d18(1), USDC, oracleMock);
    }

    function testApproveRedeemssAlreadyApproved() public {
        shareClass.approveRedeems(poolId, shareClassId, d18(1), USDC, oracleMock);

        vm.expectRevert(ISingleShareClass.AlreadyApproved.selector);
        shareClass.approveRedeems(poolId, shareClassId, d18(1), USDC, oracleMock);
    }

    function testApproveDepositsRatioExcess() public {
        vm.expectRevert(ISingleShareClass.MaxApprovalRatioExceeded.selector);
        shareClass.approveDeposits(poolId, shareClassId, d18(1e18 + 1), USDC, oracleMock);
    }

    function testApproveRedeemsRatioExcess() public {
        vm.expectRevert(ISingleShareClass.MaxApprovalRatioExceeded.selector);
        shareClass.approveRedeems(poolId, shareClassId, d18(1e18 + 1), USDC, oracleMock);
    }
}
