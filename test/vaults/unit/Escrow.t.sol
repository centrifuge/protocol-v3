// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import {MockERC6909} from "test/misc/mocks/MockERC6909.sol";

import {ERC20} from "src/misc/ERC20.sol";
import {IAuth} from "src/misc/interfaces/IAuth.sol";
import {ISharedDependency} from "src/misc/interfaces/ISharedDependency.sol";

import {Escrow, PoolEscrow} from "src/vaults/Escrow.sol";
import {IEscrow, IPoolEscrow} from "src/vaults/interfaces/IEscrow.sol";

contract EscrowTestBase is Test {
    address spender = makeAddr("spender");
    address randomUser = makeAddr("randomUser");
    Escrow escrow = new Escrow(address(this));
    ERC20 erc20 = new ERC20(6);
    MockERC6909 erc6909 = new MockERC6909();
    ISharedDependency sharedGateway = ISharedDependency(makeAddr("ISharedGateway"));

    function _mint(address escrow_, uint256 tokenId, uint256 amount) internal {
        if (tokenId == 0) {
            erc20.mint(escrow_, amount);
        } else {
            erc6909.mint(escrow_, tokenId, amount);
        }
    }

    function _asset(uint256 tokenId) internal view returns (address) {
        return tokenId == 0 ? address(erc20) : address(erc6909);
    }
}

contract EscrowTestERC20 is EscrowTestBase {
    function testApproveMax() public {
        assertEq(erc20.allowance(address(escrow), spender), 0);

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.approveMax(address(erc20), spender);

        vm.expectEmit();
        emit IEscrow.Approve(address(erc20), spender, type(uint256).max);
        escrow.approveMax(address(erc20), spender);
        assertEq(erc20.allowance(address(escrow), spender), type(uint256).max);
    }

    function testUnapprove() public {
        escrow.approveMax(address(erc20), spender);
        assertEq(erc20.allowance(address(escrow), spender), type(uint256).max);

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.unapprove(address(erc20), spender);

        vm.expectEmit();
        emit IEscrow.Approve(address(erc20), spender, 0);
        escrow.unapprove(address(erc20), spender);
        assertEq(erc20.allowance(address(escrow), spender), 0);
    }
}

contract EscrowTestERC6909 is EscrowTestBase {
    function testApproveMaxERC6909(uint8 decimals_) public {
        uint256 tokenId = uint256(bound(decimals_, 2, 18));

        assertEq(erc6909.allowance(address(escrow), spender, tokenId), 0);

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.approveMax(address(erc6909), tokenId, spender);

        vm.expectEmit();
        emit IEscrow.Approve(address(erc6909), tokenId, spender, type(uint256).max);
        escrow.approveMax(address(erc6909), tokenId, spender);
        assertEq(erc6909.allowance(address(escrow), spender, tokenId), type(uint256).max);
    }

    function testUnapproveERC6909(uint8 decimals_) public {
        uint256 tokenId = uint256(bound(decimals_, 2, 18));

        escrow.approveMax(address(erc6909), tokenId, spender);
        assertEq(erc6909.allowance(address(escrow), spender, tokenId), type(uint256).max);

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.unapprove(address(erc6909), tokenId, spender);

        vm.expectEmit();
        emit IEscrow.Approve(address(erc6909), tokenId, spender, 0);
        escrow.unapprove(address(erc6909), tokenId, spender);
        assertEq(erc6909.allowance(address(escrow), spender, tokenId), 0);
    }
}

contract PoolEscrowTestBase is EscrowTestBase {
    function _testPendingDepositIncrease(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.pendingDepositIncrease(scId, asset, tokenId, 100);

        vm.expectEmit();
        emit IPoolEscrow.PendingDeposit(asset, tokenId, poolId, scId, 100);
        escrow.pendingDepositIncrease(scId, asset, tokenId, 100);
    }

    function _testPendingDepositDecrease(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        escrow.pendingDepositIncrease(scId, asset, tokenId, 200);

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.pendingDepositDecrease(scId, asset, tokenId, 50);

        vm.expectEmit();
        emit IPoolEscrow.PendingDeposit(asset, tokenId, poolId, scId, 150);
        escrow.pendingDepositDecrease(scId, asset, tokenId, 50);

        vm.expectRevert(IPoolEscrow.InsufficientPendingDeposit.selector);
        escrow.pendingDepositDecrease(scId, asset, tokenId, 300);
    }

    function _testDeposit(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));
        escrow.pendingDepositIncrease(scId, asset, tokenId, 500);

        _mint(address(escrow), tokenId, 300);

        vm.expectRevert(IPoolEscrow.InsufficientDeposit.selector);
        escrow.deposit(scId, asset, tokenId, 500);

        vm.expectRevert(IPoolEscrow.InsufficientPendingDeposit.selector);
        escrow.deposit(scId, asset, tokenId, 600);

        vm.expectEmit();
        emit IPoolEscrow.Deposit(asset, tokenId, poolId, scId, 300);
        emit IPoolEscrow.PendingDeposit(asset, tokenId, poolId, scId, 200);
        escrow.deposit(scId, asset, tokenId, 300);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 300, "holdings should be 300 after deposit");

        vm.expectRevert(IPoolEscrow.InsufficientDeposit.selector);
        escrow.deposit(scId, asset, tokenId, 200);

        _mint(address(escrow), tokenId, 200);

        vm.expectRevert(IPoolEscrow.InsufficientPendingDeposit.selector);
        escrow.deposit(scId, asset, tokenId, 201);

        vm.expectEmit();
        emit IPoolEscrow.Deposit(asset, tokenId, poolId, scId, 200);
        emit IPoolEscrow.PendingDeposit(asset, tokenId, poolId, scId, 0);
        escrow.deposit(scId, asset, tokenId, 200);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 500, "holdings should be 500 after deposit");
    }

    function _testReserveIncrease(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.reserveIncrease(scId, asset, tokenId, 100);

        vm.expectEmit();
        emit IPoolEscrow.Reserve(asset, tokenId, poolId, scId, 100);
        escrow.reserveIncrease(scId, asset, tokenId, 100);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Still zero, nothing is in holdings");

        escrow.pendingDepositIncrease(scId, asset, tokenId, 300);
        _mint(address(escrow), tokenId, 300);
        escrow.deposit(scId, asset, tokenId, 100);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "100 - 100 = 0");

        escrow.deposit(scId, asset, tokenId, 200);
        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 200, "300 - 100 = 200");
    }

    function _testReserveDecrease(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        vm.prank(randomUser);
        vm.expectRevert(IAuth.NotAuthorized.selector);
        escrow.reserveIncrease(scId, asset, tokenId, 100);

        escrow.reserveIncrease(scId, asset, tokenId, 100);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Still zero, nothing is in holdings");

        escrow.pendingDepositIncrease(scId, asset, tokenId, 300);
        _mint(address(escrow), tokenId, 300);
        escrow.deposit(scId, asset, tokenId, 100);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "100 - 100 = 0");

        escrow.deposit(scId, asset, tokenId, 200);
        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 200, "300 - 100 = 200");

        vm.expectRevert(IPoolEscrow.InsufficientReservedAmount.selector);
        escrow.reserveDecrease(scId, asset, tokenId, 200);

        vm.expectEmit();
        emit IPoolEscrow.Reserve(asset, tokenId, poolId, scId, 0);
        escrow.reserveDecrease(scId, asset, tokenId, 100);
        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 300, "300 - 0 = 300");
    }

    function _testWithdraw(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        _mint(address(escrow), tokenId, 1000);
        escrow.pendingDepositIncrease(scId, asset, tokenId, 1000);
        escrow.deposit(scId, asset, tokenId, 1000);
        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 1000, "initial holdings should be 1000");

        escrow.reserveIncrease(scId, asset, tokenId, 500);

        vm.expectRevert(IPoolEscrow.InsufficientBalance.selector);
        escrow.withdraw(scId, asset, tokenId, 600);

        vm.expectEmit();
        emit IPoolEscrow.Withdraw(asset, tokenId, poolId, scId, 500);
        escrow.withdraw(scId, asset, tokenId, 500);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0);
    }

    function _testAvailableBalanceOf(uint64 poolId, bytes16 scId, uint256 tokenId) internal {
        address asset = _asset(tokenId);
        PoolEscrow escrow = new PoolEscrow(poolId, sharedGateway, address(this));

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Default available balance should be zero");

        _mint(address(escrow), tokenId, 500);
        escrow.pendingDepositIncrease(scId, asset, tokenId, 500);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Available balance needs deposit first.");

        escrow.deposit(scId, asset, tokenId, 500);

        escrow.reserveIncrease(scId, asset, tokenId, 200);

        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 300, "Should be 300 after reserve increase");

        escrow.reserveIncrease(scId, asset, tokenId, 300);
        assertEq(escrow.availableBalanceOf(scId, asset, tokenId), 0, "Should be zero if pendingWithdraw >= holdings");
    }
}

contract PoolEscrowTestERC20 is PoolEscrowTestBase {
    uint256 tokenId = 0;

    function testPendingDepositIncrease(uint64 poolId, bytes16 scId) public {
        _testPendingDepositIncrease(poolId, scId, tokenId);
    }

    function testPendingDepositDecrease(uint64 poolId, bytes16 scId) public {
        _testPendingDepositDecrease(poolId, scId, tokenId);
    }

    function testDeposit(uint64 poolId, bytes16 scId) public {
        _testDeposit(poolId, scId, tokenId);
    }

    function testReserveIncrease(uint64 poolId, bytes16 scId) public {
        _testReserveIncrease(poolId, scId, tokenId);
    }

    function testReserveDecrease(uint64 poolId, bytes16 scId) public {
        _testReserveDecrease(poolId, scId, tokenId);
    }

    function testWithdraw(uint64 poolId, bytes16 scId) public {
        _testWithdraw(poolId, scId, tokenId);
    }

    function testAvailableBalanceOf(uint64 poolId, bytes16 scId) public {
        _testAvailableBalanceOf(poolId, scId, tokenId);
    }
}

contract PoolEscrowTestERC6909 is PoolEscrowTestBase {
    function testPendingDepositIncrease(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testPendingDepositIncrease(poolId, scId, tokenId);
    }

    function testPendingDepositDecrease(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testPendingDepositDecrease(poolId, scId, tokenId);
    }

    function testDeposit(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testDeposit(poolId, scId, tokenId);
    }

    function testReserveIncrease(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testReserveIncrease(poolId, scId, tokenId);
    }

    function testReserveDecrease(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testReserveDecrease(poolId, scId, tokenId);
    }

    function testWithdraw(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testWithdraw(poolId, scId, tokenId);
    }

    function testAvailableBalanceOf(uint64 poolId, bytes16 scId, uint8 tokenId_) public {
        uint256 tokenId = uint256(bound(tokenId_, 2, 18));

        _testAvailableBalanceOf(poolId, scId, tokenId);
    }
}
