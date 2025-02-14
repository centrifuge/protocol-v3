// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {D18} from "misc/types/D18.sol";
import {IERC7726} from "misc/interfaces/IERC7726.sol";
import {IAuth} from "misc/interfaces/IAuth.sol";
import {IMulticall} from "misc/interfaces/IMulticall.sol";
import {Multicall} from "misc/Multicall.sol";

import {PoolId} from "src/types/PoolId.sol";
import {AssetId} from "src/types/AssetId.sol";
import {AccountId} from "src/types/AccountId.sol";
import {ShareClassId} from "src/types/ShareClassId.sol";
import {IPoolRegistry} from "src/interfaces/IPoolRegistry.sol";
import {IHoldings} from "src/interfaces/IHoldings.sol";
import {IAccounting} from "src/interfaces/IAccounting.sol";
import {IAssetManager} from "src/interfaces/IAssetManager.sol";
import {IShareClassManager} from "src/interfaces/IShareClassManager.sol";
import {IGateway} from "src/interfaces/IGateway.sol";
import {IPoolLocker} from "src/interfaces/IPoolLocker.sol";
import {IPoolManager, IPoolManagerHandler, IPoolManagerAdminMethods} from "src/interfaces/IPoolManager.sol";
import {PoolManager} from "src/PoolManager.sol";

contract TestCommon is Test {
    PoolId constant POOL_A = PoolId.wrap(1);
    ShareClassId constant SC_A = ShareClassId.wrap(bytes16(uint128(2)));
    AssetId constant ASSET_A = AssetId.wrap(3);

    IPoolRegistry immutable poolRegistry = IPoolRegistry(makeAddr("PoolRegistry"));
    IHoldings immutable holdings = IHoldings(makeAddr("Holdings"));
    IAccounting immutable accounting = IAccounting(makeAddr("Accounting"));
    IAssetManager immutable assetManager = IAssetManager(makeAddr("AssetManager"));
    IGateway immutable gateway = IGateway(makeAddr("Gateway"));
    IShareClassManager immutable scm = IShareClassManager(makeAddr("ShareClassManager"));

    Multicall multicall = new Multicall();
    PoolManager poolManager =
        new PoolManager(multicall, poolRegistry, assetManager, accounting, holdings, gateway, address(0));

    function _mockSuccessfulMulticall() private {
        vm.mockCall(
            address(poolRegistry),
            abi.encodeWithSelector(IPoolRegistry.isAdmin.selector, PoolId.wrap(1), address(this)),
            abi.encode(true)
        );

        vm.mockCall(
            address(accounting),
            abi.encodeWithSelector(IAccounting.unlock.selector, PoolId.wrap(1), bytes32("TODO")),
            abi.encode(true)
        );
    }

    function setUp() public {
        _mockSuccessfulMulticall();
    }
}

contract TestMainMethodsChecks is TestCommon {
    function testErrPoolLocked() public {
        vm.startPrank(makeAddr("notPoolAdmin"));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.notifyPool(0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.notifyShareClass(0, ShareClassId.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.notifyAllowedAsset(ShareClassId.wrap(0), AssetId.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.setPoolMetadata(bytes(""));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.allowPoolAdmin(address(0), false);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.allowInvestorAsset(AssetId.wrap(0), false);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.addShareClass(bytes(""));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.approveDeposits(ShareClassId.wrap(0), AssetId.wrap(0), D18.wrap(0), IERC7726(address(0)));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.approveRedeems(ShareClassId.wrap(0), AssetId.wrap(0), D18.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.issueShares(ShareClassId.wrap(0), AssetId.wrap(0), D18.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.revokeShares(ShareClassId.wrap(0), AssetId.wrap(0), D18.wrap(0), IERC7726(address(0)));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.createHolding(ShareClassId.wrap(0), AssetId.wrap(0), IERC7726(address(0)), 0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.increaseHolding(ShareClassId.wrap(0), AssetId.wrap(0), IERC7726(address(0)), 0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.decreaseHolding(ShareClassId.wrap(0), AssetId.wrap(0), IERC7726(address(0)), 0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.updateHolding(ShareClassId.wrap(0), AssetId.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.updateHoldingValuation(ShareClassId.wrap(0), AssetId.wrap(0), IERC7726(address(0)));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.setHoldingAccountId(ShareClassId.wrap(0), AssetId.wrap(0), AccountId.wrap(0));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.createAccount(AccountId.wrap(0), false);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.setAccountMetadata(AccountId.wrap(0), bytes(""));

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.addDebit(AccountId.wrap(0), 0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.addCredit(AccountId.wrap(0), 0);

        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.unlockAssets(ShareClassId.wrap(0), AssetId.wrap(0), bytes32(0), 0);

        vm.stopPrank();
    }

    function testErrNotGateway() public {
        vm.startPrank(makeAddr("notGateway"));

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleRegisterAsset(AssetId.wrap(0), "", "", 0);

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleRequestDeposit(PoolId.wrap(0), ShareClassId.wrap(0), bytes32(0), AssetId.wrap(0), 0);

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleRequestRedeem(PoolId.wrap(0), ShareClassId.wrap(0), bytes32(0), AssetId.wrap(0), 0);

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleCancelDepositRequest(PoolId.wrap(0), ShareClassId.wrap(0), bytes32(0), AssetId.wrap(0));

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleCancelRedeemRequest(PoolId.wrap(0), ShareClassId.wrap(0), bytes32(0), AssetId.wrap(0));

        vm.expectRevert(IPoolManagerHandler.NotGateway.selector);
        poolManager.handleLockedTokens(AssetId.wrap(0), address(0), 0);

        vm.stopPrank();
    }

    function testErrNotAuthoredAdmin() public {
        vm.mockCall(
            address(poolRegistry),
            abi.encodeWithSelector(poolRegistry.isAdmin.selector, PoolId.wrap(1), address(this)),
            abi.encode(false)
        );

        vm.expectRevert(IPoolManagerAdminMethods.NotAuthorizedAdmin.selector);
        poolManager.execute(PoolId.wrap(1), new IMulticall.Call[](0));
    }
}

contract TestNotifyShareClass is TestCommon {
    function testErrShareClassNotFound() public {
        vm.mockCall(
            address(poolRegistry),
            abi.encodeWithSelector(poolRegistry.shareClassManager.selector, POOL_A),
            abi.encode(scm)
        );

        vm.mockCall(address(scm), abi.encodeWithSelector(scm.exists.selector, POOL_A, SC_A), abi.encode(false));

        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(
            address(poolManager), abi.encodeWithSelector(poolManager.notifyShareClass.selector, 23, SC_A)
        );

        vm.expectRevert(IShareClassManager.ShareClassNotFound.selector);
        poolManager.execute(POOL_A, calls);
    }
}

contract TestAllowInvestorAsset is TestCommon {
    function testErrHoldingAssetNotFound() public {
        vm.mockCall(
            address(assetManager),
            abi.encodeWithSelector(assetManager.isRegistered.selector, ASSET_A),
            abi.encode(false)
        );

        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(
            address(poolManager), abi.encodeWithSelector(poolManager.allowInvestorAsset.selector, ASSET_A, false)
        );

        vm.expectRevert(IAssetManager.AssetNotFound.selector);
        poolManager.execute(POOL_A, calls);
    }

    function testErrAssetNotAllowed() public {
        vm.mockCall(
            address(assetManager), abi.encodeWithSelector(assetManager.isRegistered.selector, ASSET_A), abi.encode(true)
        );

        vm.mockCall(
            address(holdings),
            abi.encodeWithSelector(holdings.isAssetAllowed.selector, POOL_A, ASSET_A),
            abi.encode(false)
        );

        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(
            address(poolManager), abi.encodeWithSelector(poolManager.allowInvestorAsset.selector, ASSET_A, false)
        );

        vm.expectRevert(IPoolManagerAdminMethods.HoldingAssetNotAllowed.selector);
        poolManager.execute(POOL_A, calls);
    }
}
