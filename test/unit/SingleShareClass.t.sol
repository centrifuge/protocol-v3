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

bool constant WITH_TRANSIENT = false;
uint128 constant TRANSIENT_STORAGE_SHIFT = WITH_TRANSIENT ? 1 : 0;
uint64 constant POOL_ID = 42;
bytes16 constant SHARE_CLASS_ID = bytes16(uint128(POOL_ID));
address constant POOL_CURRENCY = address(840);
address constant USDC = address(0x0123456);
address constant OTHER_STABLE = address(0x01234567);
uint128 constant DENO_USDC = 10 ** 6;
uint128 constant DENO_OTHER_STABLE = 10 ** 12;
uint128 constant DENO_POOL = 10 ** 4;
uint128 constant MIN_REQUEST_AMOUNT = 1e10;
uint128 constant MAX_REQUEST_AMOUNT = 1e30;

contract PoolRegistryMock {
    function currency(PoolId) external pure returns (IERC20Metadata) {
        return IERC20Metadata(POOL_CURRENCY);
    }
}

contract OracleMock is IERC7726Ext {
    using MathLib for uint128;
    using MathLib for uint256;

    uint128 private constant _ONE = 1e18;

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

abstract contract SingleShareClassBaseTest is Test {
    using MathLib for uint128;

    SingleShareClass public shareClass;

    OracleMock oracleMock = new OracleMock();
    PoolRegistryMock poolRegistryMock = new PoolRegistryMock();

    PoolId poolId = PoolId.wrap(POOL_ID);
    bytes16 scId = SHARE_CLASS_ID;
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
        assertEq(IPoolRegistry(poolRegistryAddress).currency(poolId).addr(), address(IERC20Metadata(POOL_CURRENCY)));
    }

    function _assertDepositRequestEq(bytes16 shareClassId_, address asset, address investor_, UserOrder memory expected)
        internal
        view
    {
        (uint128 pending, uint32 lastUpdate) = shareClass.depositRequest(shareClassId_, asset, investor_);

        assertEq(pending, expected.pending, "pending mismatch");
        assertEq(lastUpdate, expected.lastUpdate, "lastUpdate mismatch");
    }

    function _assertRedeemRequestEq(bytes16 shareClassId_, address asset, address investor_, UserOrder memory expected)
        internal
        view
    {
        (uint128 pending, uint32 lastUpdate) = shareClass.redeemRequest(shareClassId_, asset, investor_);

        assertEq(pending, expected.pending, "pending mismatch");
        assertEq(lastUpdate, expected.lastUpdate, "lastUpdate mismatch");
    }

    function _assertEpochEq(bytes16 shareClassId_, uint32 epochId, Epoch memory expected) internal view {
        (uint128 approvedDepositAmount, uint128 approvedShareAmount) = shareClass.epoch(shareClassId_, epochId);

        assertEq(approvedDepositAmount, expected.approvedDepositAmount, "approvedDepositAmount mismatch");
        assertEq(approvedShareAmount, expected.approvedShareAmount, "approvedShareAmount mismatch");
    }

    function _assertEpochRatioEq(bytes16 shareClassId_, address assetId, uint32 epochId, EpochRatio memory expected)
        internal
        view
    {
        (
            D18 depositRatio,
            D18 redeemRatio,
            D18 depositAssetToPoolQuote,
            D18 redeemAssetToPoolQuote,
            D18 depositShareToPoolQuote,
            D18 redeemShareToPoolQuote
        ) = shareClass.epochRatio(shareClassId_, assetId, epochId);

        assertEq(depositRatio.inner(), expected.depositRatio.inner(), "depositRatio mismatch");
        assertEq(redeemRatio.inner(), expected.redeemRatio.inner(), "redeemRatio mismatch");
        assertEq(
            depositAssetToPoolQuote.inner(),
            expected.depositAssetToPoolQuote.inner(),
            "depositAssetToPoolQuote mismatch"
        );
        assertEq(
            redeemAssetToPoolQuote.inner(), expected.redeemAssetToPoolQuote.inner(), "redeemAssetToPoolQuote mismatch"
        );
        assertEq(
            depositShareToPoolQuote.inner(),
            expected.depositShareToPoolQuote.inner(),
            "depositShareToPoolQuote mismatch"
        );
        assertEq(
            redeemShareToPoolQuote.inner(), expected.redeemShareToPoolQuote.inner(), "redeemShareToPoolQuote mismatch"
        );
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
            bytes32 clearedValue = currentValue & ~bytes32(uint256(0xFFFFFFFF));

            // Set `_epochIncrement` to 0
            vm.store(address(shareClass), slot, clearedValue);
        }
    }

    function usdcToPool(uint128 usdcAmount) internal pure returns (uint128 poolAmount) {
        return usdcAmount / 100;
    }

    function poolToUsdc(uint128 poolAmount) internal pure returns (uint128 usdcAmount) {
        return poolAmount * 100;
    }
}

///@dev Contains all simple tests which are expected to succeed
contract SingleShareClassSimpleTest is SingleShareClassBaseTest {
    using MathLib for uint128;

    function testDeployment(address nonWard) public view notThisContract(poolRegistryAddress) {
        vm.assume(nonWard != address(shareClass.poolRegistry()) && nonWard != address(this));

        assertEq(address(shareClass.poolRegistry()), poolRegistryAddress);
        assertEq(shareClass.shareClassId(poolId), scId);

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
        (D18 navPerShare, uint128 nav) = shareClass.shareClassNavPerShare(poolId, scId);
        assertEq(nav, 0);
        assertEq(navPerShare.inner(), 0);
    }
}

///@dev Contains all deposit related tests which are expected to succeed and don't make use of transient storage
contract SingleShareClassDepositsNonTransientTest is SingleShareClassBaseTest {
    using MathLib for uint128;

    function testRequestDeposit(uint128 amount) public notThisContract(poolRegistryAddress) {
        amount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));

        assertEq(shareClass.pendingDeposit(scId, USDC), 0);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(0, 0));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedDepositRequest(poolId, scId, 1, investor, USDC, amount, amount);
        shareClass.requestDeposit(poolId, scId, amount, investor, USDC);

        assertEq(shareClass.pendingDeposit(scId, USDC), amount);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(amount, 1));
    }

    function testCancelDepositRequest(uint128 amount) public notThisContract(poolRegistryAddress) {
        amount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        shareClass.requestDeposit(poolId, scId, amount, investor, USDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedDepositRequest(poolId, scId, 1, investor, USDC, 0, 0);
        (uint128 cancelledAmount) = shareClass.cancelDepositRequest(poolId, scId, investor, USDC);

        assertEq(cancelledAmount, amount);
        assertEq(shareClass.pendingDeposit(scId, USDC), 0);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(0, 1));
    }

    function testApproveDepositsSingleAssetManyInvestors(
        uint128 depositAmount,
        uint8 numInvestors,
        uint128 approvalRatio_
    ) public notThisContract(poolRegistryAddress) {
        depositAmount = uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        numInvestors = uint8(bound(numInvestors, 1, 100));

        uint128 deposits = 0;
        for (uint16 i = 0; i < numInvestors; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            uint128 investorDeposit = depositAmount + i;
            deposits += investorDeposit;
            shareClass.requestDeposit(poolId, scId, investorDeposit, investor, USDC);

            assertEq(shareClass.pendingDeposit(scId, USDC), deposits);
        }
        assertEq(shareClass.epochId(poolId), 1);

        uint128 approvedUSDC = approvalRatio.mulUint128(deposits);
        uint128 approvedPool = usdcToPool(approvedUSDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.NewEpoch(poolId, 2);
        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ApprovedDeposits(
            poolId, scId, 1, USDC, approvalRatio, approvedPool, approvedUSDC, deposits - approvedUSDC, d18(1e16)
        );
        shareClass.approveDeposits(poolId, scId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.pendingDeposit(scId, USDC), deposits - approvedUSDC);

        // Only one epoch should have passed
        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(scId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(scId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), d18(0), d18(0), d18(0)));
    }

    function testApproveDepositsTwoAssetsSameEpoch(uint128 depositAmount, uint128 approvalRatio)
        public
        notThisContract(poolRegistryAddress)
    {
        uint128 depositAmountUsdc = uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        uint128 depositAmountOther = uint128(bound(depositAmount, 1e8, MAX_REQUEST_AMOUNT));
        D18 approvalRatioUsdc = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        D18 approvalRatioOther = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        address investorUsdc = makeAddr("investorUsdc");
        address investorOther = makeAddr("investorOther");

        uint128 approvedPool = d18(1e16).mulUint128(approvalRatioUsdc.mulUint128(depositAmountUsdc))
            + d18(1e10).mulUint128(approvalRatioOther.mulUint128(depositAmountOther));

        shareClass.requestDeposit(poolId, scId, depositAmountUsdc, investorUsdc, USDC);
        shareClass.requestDeposit(poolId, scId, depositAmountOther, investorOther, OTHER_STABLE);

        shareClass.approveDeposits(poolId, scId, approvalRatioUsdc, USDC, oracleMock);
        shareClass.approveDeposits(poolId, scId, approvalRatioOther, OTHER_STABLE, oracleMock);

        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(scId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(scId, USDC, 1, EpochRatio(approvalRatioUsdc, d18(0), d18(1e16), d18(0), d18(0), d18(0)));
        _assertEpochRatioEq(
            scId, OTHER_STABLE, 1, EpochRatio(approvalRatioOther, d18(0), d18(1e10), d18(0), d18(0), d18(0))
        );
    }

    function testIssueSharesSingleEpoch(uint128 depositAmount, uint128 shareToPoolQuote_, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        depositAmount = uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 shareToPoolQuote = d18(uint128(bound(shareToPoolQuote_, 1e14, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 approvedUSDC = approvalRatio.mulUint128(depositAmount);
        uint128 approvedPool = usdcToPool(approvedUSDC);
        uint128 shares = shareToPoolQuote.reciprocalMulUint128(approvedPool);

        shareClass.requestDeposit(poolId, scId, depositAmount, investor, USDC);
        shareClass.approveDeposits(poolId, scId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.totalIssuance(scId), 0);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(1, 0, 0, 0));

        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(shareClass.totalIssuance(scId), shares);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(1, 0, 1, 0));
        _assertEpochEq(scId, 1, Epoch(approvedPool, 0));
        _assertEpochRatioEq(
            scId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), d18(0), shareToPoolQuote, d18(0))
        );
    }

    function testClaimDepositSingleEpoch(uint128 depositAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        depositAmount = uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 approvedUSDC = approvalRatio.mulUint128(depositAmount);
        uint128 approvedPool = usdcToPool(approvedUSDC);
        uint128 shares = shareToPoolQuote.reciprocalMulUint128(approvedPool);
        uint128 pending = depositAmount - approvedUSDC;

        shareClass.requestDeposit(poolId, scId, depositAmount, investor, USDC);
        shareClass.approveDeposits(poolId, scId, approvalRatio, USDC, oracleMock);
        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(shareClass.totalIssuance(scId), shares);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(depositAmount, 1));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ClaimedDeposit(poolId, scId, 1, investor, USDC, approvedUSDC, pending, shares);
        (uint128 userShares, uint128 payment) = shareClass.claimDeposit(poolId, scId, investor, USDC);

        assertEq(shares, userShares, "shares mismatch");
        assertEq(approvedUSDC, payment, "payment mismatch");
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(pending, 2));
        assertEq(shareClass.totalIssuance(scId), shares);

        // Ensure another claim has no impact
        (userShares, payment) = shareClass.claimDeposit(poolId, scId, investor, USDC);
        assertEq(userShares + payment, 0, "replay must not be possible");
    }

    function testClaimDepositSkipped() public notThisContract(poolRegistryAddress) {
        uint128 pending = MAX_REQUEST_AMOUNT;
        uint32 mockLatestIssuance = 10;
        uint32 mockEpochId = mockLatestIssuance + 1;
        shareClass.requestDeposit(poolId, scId, pending, investor, USDC);

        // Mock latestIssuance to 10
        vm.store(
            address(shareClass),
            keccak256(abi.encode(USDC, keccak256(abi.encode(scId, uint256(7 + TRANSIENT_STORAGE_SHIFT))))),
            bytes32(
                (uint256(0)) // latestDepositApproval
                    | (uint256(0) << 32) // latestRedeemApproval
                    | (uint256(mockLatestIssuance) << 64) // latestIssuance
                    | (uint256(0) << 96) // latestRevocation
            )
        );
        // Mock epochId to 11
        vm.store(
            address(shareClass),
            keccak256(abi.encode(poolId, uint256(4 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(mockEpochId))
        );

        (uint128 payout, uint128 payment) = shareClass.claimDeposit(poolId, scId, investor, USDC);
        assertEq(payout + payment, 0);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(pending, mockEpochId));
    }
}

///@dev Contains all redeem related tests which are expected to succeed and don't make use of transient storage
contract SingleShareClassRedeemsNonTransientTest is SingleShareClassBaseTest {
    using MathLib for uint128;

    function testRequestRedeem(uint128 amount) public notThisContract(poolRegistryAddress) {
        amount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));

        assertEq(shareClass.pendingRedeem(scId, USDC), 0);
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(0, 0));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedRedeemRequest(poolId, scId, 1, investor, USDC, amount, amount);
        shareClass.requestRedeem(poolId, scId, amount, investor, USDC);

        assertEq(shareClass.pendingRedeem(scId, USDC), amount);
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(amount, 1));
    }

    function testCancelRedeemRequest(uint128 amount) public notThisContract(poolRegistryAddress) {
        amount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        shareClass.requestRedeem(poolId, scId, amount, investor, USDC);

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.UpdatedRedeemRequest(poolId, scId, 1, investor, USDC, 0, 0);
        (uint128 cancelledAmount) = shareClass.cancelRedeemRequest(poolId, scId, investor, USDC);

        assertEq(cancelledAmount, amount);
        assertEq(shareClass.pendingRedeem(scId, USDC), 0);
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(0, 1));
    }

    function testApproveRedeemsSingleAssetManyInvestors(uint128 amount, uint8 numInvestors, uint128 approvalRatio_)
        public
    {
        amount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        numInvestors = uint8(bound(numInvestors, 1, 100));

        uint128 totalRedeems = 0;
        for (uint16 i = 0; i < numInvestors; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            uint128 investorRedeem = amount + i;
            totalRedeems += investorRedeem;
            shareClass.requestRedeem(poolId, scId, investorRedeem, investor, USDC);

            assertEq(shareClass.pendingRedeem(scId, USDC), totalRedeems);
        }
        assertEq(shareClass.epochId(poolId), 1);

        uint128 approvedShares = approvalRatio.mulUint128(totalRedeems);
        uint128 pendingRedeems_ = totalRedeems - approvedShares;

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.NewEpoch(poolId, 2);
        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ApprovedRedeems(
            poolId, scId, 1, USDC, approvalRatio, approvedShares, pendingRedeems_, d18(1e16)
        );
        shareClass.approveRedeems(poolId, scId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.pendingRedeem(scId, USDC), pendingRedeems_);

        // Only one epoch should have passed
        assertEq(shareClass.epochId(poolId), 2);

        _assertEpochEq(scId, 1, Epoch(0, approvedShares));
        _assertEpochRatioEq(scId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(0), d18(1e16), d18(0), d18(0)));
    }

    function testApproveRedeemsTwoAssetsSameEpoch(uint128 redeemAmount, uint128 approvalRatio)
        public
        notThisContract(poolRegistryAddress)
    {
        uint128 redeemAmountUsdc = uint128(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        uint128 redeemAmountOther = uint128(bound(redeemAmount, 1e8, MAX_REQUEST_AMOUNT));
        D18 approvalRatioUsdc = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        D18 approvalRatioOther = d18(uint128(bound(approvalRatio, 1e14, 1e18)));
        address investorUsdc = makeAddr("investorUsdc");
        address investorOther = makeAddr("investorOther");
        uint128 approvedShares =
            approvalRatioUsdc.mulUint128(redeemAmountUsdc) + approvalRatioOther.mulUint128(redeemAmountOther);

        shareClass.requestRedeem(poolId, scId, redeemAmountUsdc, investorUsdc, USDC);
        shareClass.requestRedeem(poolId, scId, redeemAmountOther, investorOther, OTHER_STABLE);

        (uint128 approvedUsdc, uint128 pendingUsdc) =
            shareClass.approveRedeems(poolId, scId, approvalRatioUsdc, USDC, oracleMock);
        (uint128 approvedOther, uint128 pendingOther) =
            shareClass.approveRedeems(poolId, scId, approvalRatioOther, OTHER_STABLE, oracleMock);

        assertEq(shareClass.epochId(poolId), 2);
        assertEq(approvedUsdc, approvalRatioUsdc.mulUint128(redeemAmountUsdc), "approved shares USDC mismatch");
        assertEq(
            pendingUsdc,
            redeemAmountUsdc - approvalRatioUsdc.mulUint128(redeemAmountUsdc),
            "pending shares USDC mismatch"
        );
        assertEq(
            approvedOther, approvalRatioOther.mulUint128(redeemAmountOther), "approved shares OtherCurrency mismatch"
        );
        assertEq(
            pendingOther,
            redeemAmountOther - approvalRatioOther.mulUint128(redeemAmountOther),
            "pending shares OtherCurrency mismatch"
        );

        _assertEpochEq(scId, 1, Epoch(0, approvedShares));
        _assertEpochRatioEq(scId, USDC, 1, EpochRatio(d18(0), approvalRatioUsdc, d18(0), d18(1e16), d18(0), d18(0)));
        _assertEpochRatioEq(
            scId, OTHER_STABLE, 1, EpochRatio(d18(0), approvalRatioOther, d18(0), d18(1e10), d18(0), d18(0))
        );
    }

    function testRevokeSharesSingleEpoch(uint128 redeemAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        redeemAmount = uint128(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare, 1e14, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 approvedRedeem = approvalRatio.mulUint128(redeemAmount);
        uint128 poolAmount = shareToPoolQuote.mulUint128(approvedRedeem);
        uint128 assetAmount = poolToUsdc(poolAmount);

        // Mock total issuance to equal redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(scId, uint256(3 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(redeemAmount))
        );
        assertEq(shareClass.totalIssuance(scId), redeemAmount);

        shareClass.requestRedeem(poolId, scId, redeemAmount, investor, USDC);
        shareClass.approveRedeems(poolId, scId, approvalRatio, USDC, oracleMock);

        assertEq(shareClass.totalIssuance(scId), redeemAmount);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(0, 1, 0, 0));

        (uint128 payoutAssetAmount, uint128 payoutPoolAmount) =
            shareClass.revokeShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(assetAmount, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(poolAmount, payoutPoolAmount, "payout pool amount mismatch");

        assertEq(shareClass.totalIssuance(scId), redeemAmount - approvedRedeem);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(0, 1, 0, 1));

        _assertEpochEq(scId, 1, Epoch(0, approvedRedeem));
        _assertEpochRatioEq(
            scId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(0), d18(1e16), d18(0), shareToPoolQuote)
        );
    }

    function testClaimRedeemSingleEpoch(uint128 redeemAmount, uint128 navPerShare, uint128 approvalRatio_)
        public
        notThisContract(poolRegistryAddress)
    {
        redeemAmount = uint128(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 approvedRedeem = approvalRatio.mulUint128(redeemAmount);
        uint128 pendingRedeem = redeemAmount - approvedRedeem;
        uint128 payout = poolToUsdc(shareToPoolQuote.mulUint128(approvedRedeem));

        // Mock total issuance to equal redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(scId, uint256(3 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(redeemAmount))
        );
        assertEq(shareClass.totalIssuance(scId), redeemAmount);

        shareClass.requestRedeem(poolId, scId, redeemAmount, investor, USDC);
        shareClass.approveRedeems(poolId, scId, approvalRatio, USDC, oracleMock);
        shareClass.revokeShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(shareClass.totalIssuance(scId), pendingRedeem);
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(redeemAmount, 1));

        vm.expectEmit(true, true, true, true);
        emit IShareClassManager.ClaimedRedeem(poolId, scId, 1, investor, USDC, approvedRedeem, pendingRedeem, payout);
        (uint128 payoutAssetAmount, uint128 paymentShareAmount) = shareClass.claimRedeem(poolId, scId, investor, USDC);

        assertEq(payout, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(approvedRedeem, paymentShareAmount, "payment shares mismatch");
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(pendingRedeem, 2));

        // Ensure another claim has no impact
        (payoutAssetAmount, paymentShareAmount) = shareClass.claimRedeem(poolId, scId, investor, USDC);
        assertEq(payoutAssetAmount + paymentShareAmount, 0, "replay must not be possible");
    }

    function testClaimRedeemSkipped() public notThisContract(poolRegistryAddress) {
        uint128 pending = MAX_REQUEST_AMOUNT;
        uint32 mockLatestRevocation = 10;
        uint32 mockEpochId = mockLatestRevocation + 1;
        shareClass.requestRedeem(poolId, scId, pending, investor, USDC);

        // Mock latestRevocation to 10
        vm.store(
            address(shareClass),
            keccak256(abi.encode(USDC, keccak256(abi.encode(scId, uint256(7 + TRANSIENT_STORAGE_SHIFT))))),
            bytes32(
                (uint256(0)) // latestDepositApproval
                    | (uint256(0) << 32) // latestRedeemApproval
                    | (uint256(0) << 64) // latestIssuance
                    | (uint256(mockLatestRevocation) << 96) // latestRevocation
            )
        );
        // Mock epochId to 11
        vm.store(
            address(shareClass),
            keccak256(abi.encode(poolId, uint256(4 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(mockEpochId))
        );

        (uint128 payout, uint128 payment) = shareClass.claimRedeem(poolId, scId, investor, USDC);
        assertEq(payout + payment, 0);
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(pending, mockEpochId));
    }
}

///@dev Contains all tests which require transient storage to reset between calls
contract SingleShareClassTransientTest is SingleShareClassBaseTest {
    using MathLib for uint128;

    function testIssueSharesManyEpochs(
        uint128 depositAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        depositAmount = uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT));
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 shares = 0;
        uint128 pendingUSDC = depositAmount;

        // Bump up latestApproval epochs
        for (uint8 i = 1; i < maxEpochId; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            _resetTransientEpochIncrement();
            shareClass.requestDeposit(poolId, scId, depositAmount, investor, USDC);
            shareClass.approveDeposits(poolId, scId, approvalRatio, USDC, oracleMock);
        }
        assertEq(shareClass.totalIssuance(scId), 0);

        // Assert issued events
        uint128 totalIssuance_;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 approvedUSDC = approvalRatio.mulUint128(pendingUSDC);
            pendingUSDC += depositAmount - approvedUSDC;
            uint128 epochShares = shareToPoolQuote.reciprocalMulUint128(usdcToPool(approvedUSDC));
            totalIssuance_ += epochShares;
            uint128 nav = shareToPoolQuote.mulUint128(totalIssuance_);

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.IssuedShares(poolId, scId, i, shareToPoolQuote, nav, epochShares);
        }

        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(maxEpochId - 1, 0, maxEpochId - 1, 0));

        // Ensure each epoch is issued separately
        pendingUSDC = depositAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 approvedUSDC = approvalRatio.mulUint128(pendingUSDC);
            pendingUSDC += depositAmount - approvedUSDC;
            uint128 approvedPool = usdcToPool(approvedUSDC);
            shares += shareToPoolQuote.reciprocalMulUint128(approvedPool);

            _assertEpochEq(scId, i, Epoch(approvedPool, 0));
            _assertEpochRatioEq(
                scId, USDC, 1, EpochRatio(approvalRatio, d18(0), d18(1e16), d18(0), shareToPoolQuote, d18(0))
            );
        }
        assertEq(shareClass.totalIssuance(scId), shares, "totalIssuance mismatch");
        (D18 navPerShare, uint128 issuance) = shareClass.shareClassNavPerShare(poolId, scId);
        assertEq(navPerShare.inner(), shareToPoolQuote.inner());
        assertEq(issuance, shares, "totalIssuance mismatch");

        // Ensure another issuance reverts
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
    }

    function testClaimDepositManyEpochs(
        uint128 depositAmount,
        uint128 navPerShare,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        depositAmount = maxEpochId * uint128(bound(depositAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e10, 1e16)));
        uint128 approvedUSDC = 0;
        uint128 pending = depositAmount;
        uint128 shares = 0;

        shareClass.requestDeposit(poolId, scId, depositAmount, investor, USDC);

        // Approve many epochs and issue shares
        for (uint8 i = 1; i < maxEpochId; i++) {
            shareClass.approveDeposits(poolId, scId, approvalRatio, USDC, oracleMock);
            shares += shareToPoolQuote.reciprocalMulUint128(usdcToPool(approvalRatio.mulUint128(pending)));
            approvedUSDC += approvalRatio.mulUint128(pending);
            pending = depositAmount - approvedUSDC;
            _resetTransientEpochIncrement();
        }
        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(shareClass.totalIssuance(scId), shares, "totalIssuance mismatch");

        // Ensure each epoch is claimed separately
        approvedUSDC = 0;
        pending = depositAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 epochShares = shareToPoolQuote.reciprocalMulUint128(usdcToPool(approvalRatio.mulUint128(pending)));
            uint128 epochApprovedUSDC = approvalRatio.mulUint128(pending);
            approvedUSDC += epochApprovedUSDC;
            pending -= epochApprovedUSDC;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.ClaimedDeposit(
                poolId, scId, i, investor, USDC, epochApprovedUSDC, pending, epochShares
            );
        }
        (uint128 userShares, uint128 payment) = shareClass.claimDeposit(poolId, scId, investor, USDC);

        assertEq(approvedUSDC + pending, depositAmount, "approved + pending must equal request amount");
        assertEq(shares, userShares, "shares mismatch");
        assertEq(approvedUSDC, payment, "payment mismatch");
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(pending, maxEpochId));
    }

    function testRevokeSharesManyEpochs(
        uint128 redeemAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        redeemAmount = uint128(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e14, 1e18)));
        uint128 totalIssuance_ = maxEpochId * redeemAmount;
        uint128 redeemedShares = 0;
        uint128 pendingRedeems = redeemAmount;

        // Mock total issuance to equal total redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(scId, uint256(3 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(totalIssuance_))
        );

        // Bump up latestApproval epochs
        for (uint8 i = 1; i < maxEpochId; i++) {
            address investor = address(uint160(uint256(keccak256(abi.encodePacked("investor_", i)))));
            _resetTransientEpochIncrement();
            shareClass.requestRedeem(poolId, scId, redeemAmount, investor, USDC);
            shareClass.approveRedeems(poolId, scId, approvalRatio, USDC, oracleMock);
        }
        assertEq(shareClass.totalIssuance(scId), totalIssuance_);

        // Assert revoked events
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 approvedRedeems = approvalRatio.mulUint128(pendingRedeems);
            totalIssuance_ -= approvedRedeems;
            uint128 nav = shareToPoolQuote.mulUint128(totalIssuance_);
            pendingRedeems += redeemAmount - approvedRedeems;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.RevokedShares(poolId, scId, i, shareToPoolQuote, nav, approvedRedeems);
        }

        shareClass.revokeShares(poolId, scId, USDC, shareToPoolQuote);
        _assertAssetEpochStateEq(scId, USDC, AssetEpochState(0, maxEpochId - 1, 0, maxEpochId - 1));

        // Ensure each epoch was revoked separately
        pendingRedeems = redeemAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 approvedRedeems = approvalRatio.mulUint128(pendingRedeems);
            pendingRedeems += redeemAmount - approvedRedeems;
            redeemedShares += approvedRedeems;

            _assertEpochEq(scId, i, Epoch(0, approvedRedeems));
            _assertEpochRatioEq(
                scId, USDC, 1, EpochRatio(d18(0), approvalRatio, d18(0), d18(1e16), d18(0), shareToPoolQuote)
            );
        }
        assertEq(shareClass.totalIssuance(scId), totalIssuance_);
        (D18 navPerShare, uint128 issuance) = shareClass.shareClassNavPerShare(poolId, scId);
        assertEq(navPerShare.inner(), shareToPoolQuote.inner());
        assertEq(issuance, totalIssuance_);

        // Ensure another issuance reverts
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.revokeShares(poolId, scId, USDC, shareToPoolQuote);
    }

    function testClaimRedeemManyEpochs(
        uint128 redeemAmount,
        uint128 navPerShare_,
        uint128 approvalRatio_,
        uint8 maxEpochId
    ) public notThisContract(poolRegistryAddress) {
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        maxEpochId = uint8(bound(maxEpochId, 3, 50));
        redeemAmount = maxEpochId * uint128(bound(redeemAmount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 approvalRatio = d18(uint128(bound(approvalRatio_, 1e10, 1e16)));
        uint128 pendingRedeem = redeemAmount;
        uint128 payout = 0;
        uint128 approvedRedeem = 0;

        // Mock total issuance to equal total redeemAmount
        vm.store(
            address(shareClass),
            keccak256(abi.encode(scId, uint256(3 + TRANSIENT_STORAGE_SHIFT))),
            bytes32(uint256(redeemAmount))
        );

        shareClass.requestRedeem(poolId, scId, redeemAmount, investor, USDC);

        // Approve many epochs and revoke shares
        for (uint8 i = 1; i < maxEpochId; i++) {
            _resetTransientEpochIncrement();
            shareClass.approveRedeems(poolId, scId, approvalRatio, USDC, oracleMock);
            pendingRedeem -= approvalRatio.mulUint128(pendingRedeem);
        }
        shareClass.revokeShares(poolId, scId, USDC, shareToPoolQuote);
        assertEq(shareClass.totalIssuance(scId), pendingRedeem, "totalIssuance mismatch");

        // Ensure each epoch is claimed separately
        pendingRedeem = redeemAmount;
        for (uint8 i = 1; i < maxEpochId; i++) {
            uint128 epochApproved = approvalRatio.mulUint128(pendingRedeem);
            uint128 epochPayout = poolToUsdc(shareToPoolQuote.mulUint128(epochApproved));
            pendingRedeem -= approvalRatio.mulUint128(pendingRedeem);
            payout += epochPayout;
            approvedRedeem += epochApproved;

            vm.expectEmit(true, true, true, true);
            emit IShareClassManager.ClaimedRedeem(
                poolId, scId, i, investor, USDC, epochApproved, pendingRedeem, epochPayout
            );
        }
        (uint128 payoutAssetAmount, uint128 paymentShareAmount) = shareClass.claimRedeem(poolId, scId, investor, USDC);

        assertEq(approvedRedeem + pendingRedeem, redeemAmount, "approved + pending must equal request amount");
        assertEq(payout, payoutAssetAmount, "payout asset amount mismatch");
        assertEq(approvedRedeem, paymentShareAmount, "payment shares mismatch");
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(pendingRedeem, maxEpochId));
    }

    function testDepositsWithRedeemsFullFlow(uint128 amount, uint128 approvalRatio, uint128 navPerShare_)
        // uint8 maxEpochId
        public
        notThisContract(poolRegistryAddress)
    {
        D18 shareToPoolQuote = d18(uint128(bound(navPerShare_, 1e10, type(uint128).max / 1e18)));
        D18 navPerShareRedeem = shareToPoolQuote - d18(1e6);
        uint128 depositAmount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        uint128 redeemAmount = uint128(bound(amount, MIN_REQUEST_AMOUNT, MAX_REQUEST_AMOUNT / 1e18));
        D18 depositApprovalRatio = d18(uint128(bound(approvalRatio, 1e10, 1e16)));
        D18 redeemApprovalRatio = d18(uint128(bound(approvalRatio, 1e10, depositApprovalRatio.inner())));

        // Step 1: Do initial deposit flow with 100% deposit approval rate to add sufficient shares for later redemption
        uint32 epochId = 2;
        shareClass.requestDeposit(poolId, scId, MAX_REQUEST_AMOUNT, investor, USDC);
        shareClass.approveDeposits(poolId, scId, d18(1e18), USDC, oracleMock);
        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        shareClass.claimDeposit(poolId, scId, investor, USDC);

        uint128 shares = shareToPoolQuote.reciprocalMulUint128(usdcToPool(MAX_REQUEST_AMOUNT));
        assertEq(shareClass.totalIssuance(scId), shares);
        assertEq(shareClass.epochId(poolId), 2);
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(0, 2));
        _assertEpochEq(scId, 1, Epoch(usdcToPool(MAX_REQUEST_AMOUNT), 0));
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(0, 2));

        // Step 2a: Deposit + redeem at same
        _resetTransientEpochIncrement();
        shareClass.requestDeposit(poolId, scId, depositAmount, investor, USDC);
        shareClass.requestRedeem(poolId, scId, redeemAmount, investor, USDC);
        uint128 pendingDepositUSDC = depositAmount;
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(pendingDepositUSDC, epochId));
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(redeemAmount, epochId));
        _assertEpochEq(scId, epochId, Epoch(0, 0));

        // Step 2b: Approve deposits
        shareClass.approveDeposits(poolId, scId, depositApprovalRatio, USDC, oracleMock);
        uint128 approvedDepositUSDC = depositApprovalRatio.mulUint128(pendingDepositUSDC);
        _assertEpochEq(scId, epochId, Epoch(usdcToPool(approvedDepositUSDC), 0));

        // Step 2c: Approve redeems
        shareClass.approveRedeems(poolId, scId, redeemApprovalRatio, USDC, oracleMock);
        uint128 approvedRedeem = redeemApprovalRatio.mulUint128(redeemAmount);
        _assertEpochEq(scId, epochId, Epoch(usdcToPool(approvedDepositUSDC), approvedRedeem));
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(depositAmount, epochId));
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(redeemAmount, epochId));

        // Step 2d: Issue shares
        shareClass.issueShares(poolId, scId, USDC, shareToPoolQuote);
        epochId += 1;
        shares += shareToPoolQuote.reciprocalMulUint128(usdcToPool(approvedDepositUSDC));
        assertEq(shareClass.totalIssuance(scId), shares);

        // Step 2e: Revoke shares
        shareClass.revokeShares(poolId, scId, USDC, navPerShareRedeem);
        shares -= approvedRedeem;
        (D18 navPerShare, uint128 issuance) = shareClass.shareClassNavPerShare(poolId, scId);
        assertEq(issuance, shares);
        assertEq(navPerShare.inner(), navPerShareRedeem.inner());

        // Step 2f: Claim deposit and redeem
        shareClass.claimDeposit(poolId, scId, investor, USDC);
        shareClass.claimRedeem(poolId, scId, investor, USDC);
        pendingDepositUSDC -= approvedDepositUSDC;
        _assertDepositRequestEq(scId, USDC, investor, UserOrder(pendingDepositUSDC, epochId));
        uint128 pendingRedeem = redeemAmount - approvedRedeem;
        _assertRedeemRequestEq(scId, USDC, investor, UserOrder(pendingRedeem, epochId));
    }
}

///@dev Contains all tests which are expected to revert
contract SingleShareClassRevertsTest is SingleShareClassBaseTest {
    using MathLib for uint128;

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
            keccak256(abi.encode(USDC, keccak256(abi.encode(wrongShareClassId, uint256(7 + TRANSIENT_STORAGE_SHIFT))))),
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
            keccak256(abi.encode(USDC, keccak256(abi.encode(wrongShareClassId, uint256(7 + TRANSIENT_STORAGE_SHIFT))))),
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

    function testIssueSharesBeforeApproval() public {
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.issueShares(poolId, scId, USDC, d18(1));
    }

    function testRevokeSharesBeforeApproval() public {
        vm.expectRevert(abi.encodeWithSelector(ISingleShareClass.ApprovalRequired.selector));
        shareClass.revokeShares(poolId, scId, USDC, d18(1));
    }

    function testIssueSharesUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.issueSharesUntilEpoch(poolId, scId, USDC, d18(1), 2);
    }

    function testRevokeSharesUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.revokeSharesUntilEpoch(poolId, scId, USDC, d18(1), 2);
    }

    function testClaimDepositUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.claimDepositUntilEpoch(poolId, scId, investor, USDC, 2);
    }

    function testClaimRedeemUntilEpochNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.EpochNotFound.selector));
        shareClass.claimRedeemUntilEpoch(poolId, scId, investor, USDC, 2);
    }

    function testUpdateShareClassUnsupported() public {
        vm.expectRevert(bytes("unsupported"));
        shareClass.updateShareClassNav(poolId, scId);
    }

    function testUpdateUnsupported() public {
        vm.expectRevert(bytes("unsupported"));
        shareClass.update(poolId, bytes(""));
    }

    function testRequestDepositRequiresClaim() public {
        shareClass.requestDeposit(poolId, scId, 1, investor, USDC);
        shareClass.approveDeposits(poolId, scId, d18(1), USDC, oracleMock);

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ClaimDepositRequired.selector));
        shareClass.requestDeposit(poolId, scId, 1, investor, USDC);
    }

    function testRequestRedeemRequiresClaim() public {
        shareClass.requestRedeem(poolId, scId, 1, investor, USDC);
        shareClass.approveRedeems(poolId, scId, d18(1), USDC, oracleMock);

        vm.expectRevert(abi.encodeWithSelector(IShareClassManager.ClaimRedeemRequired.selector));
        shareClass.requestRedeem(poolId, scId, 1, investor, USDC);
    }

    function testApproveDepositsAlreadyApproved() public {
        shareClass.approveDeposits(poolId, scId, d18(1), USDC, oracleMock);

        vm.expectRevert(ISingleShareClass.AlreadyApproved.selector);
        shareClass.approveDeposits(poolId, scId, d18(1), USDC, oracleMock);
    }

    function testApproveRedeemssAlreadyApproved() public {
        shareClass.approveRedeems(poolId, scId, d18(1), USDC, oracleMock);

        vm.expectRevert(ISingleShareClass.AlreadyApproved.selector);
        shareClass.approveRedeems(poolId, scId, d18(1), USDC, oracleMock);
    }

    function testApproveDepositsRatioExcess() public {
        vm.expectRevert(ISingleShareClass.MaxApprovalRatioExceeded.selector);
        shareClass.approveDeposits(poolId, scId, d18(1e18 + 1), USDC, oracleMock);
    }

    function testApproveRedeemsRatioExcess() public {
        vm.expectRevert(ISingleShareClass.MaxApprovalRatioExceeded.selector);
        shareClass.approveRedeems(poolId, scId, d18(1e18 + 1), USDC, oracleMock);
    }
}
