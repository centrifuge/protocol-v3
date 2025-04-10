// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAuth} from "src/misc/interfaces/IAuth.sol";
import {IERC20} from "src/misc/interfaces/IERC20.sol";

import {MockRoot} from "test/common/mocks/MockRoot.sol";

import "src/vaults/interfaces/IERC7575.sol";
import "src/vaults/interfaces/IERC7540.sol";
import {CentrifugeToken} from "src/vaults/token/ShareToken.sol";

import "forge-std/Test.sol";
import {MockRestrictedTransfers} from "test/vaults/mocks/MockRestrictedTransfers.sol";
import {IHook} from "src/vaults/interfaces/token/IHook.sol";
import {IShareToken} from "src/vaults/interfaces/token/IShareToken.sol";

interface ERC20Like {
    function balanceOf(address) external view returns (uint256);
}

contract ShareTokenTest is Test {
    CentrifugeToken token;
    MockRestrictedTransfers restrictedTransfers;

    address self;
    address escrow = makeAddr("escrow");
    address targetUser = makeAddr("targetUser");
    address randomUser = makeAddr("random");
    uint64 validUntil = uint64(block.timestamp + 7 days);

    function setUp() public {
        self = address(this);
        token = new CentrifugeToken(18);
        token.file("name", "Some Token");
        token.file("symbol", "ST");

        restrictedTransfers = new MockRestrictedTransfers(address(new MockRoot()), address(this));
        token.file("hook", address(restrictedTransfers));
    }

    // --- Admnistration ---
    function testFile(address asset, address vault) public {
        address hook = makeAddr("hook");

        // fail: unrecognized param
        vm.expectRevert(IShareToken.FileUnrecognizedParam.selector);
        token.file("random", hook);

        // success
        token.file("hook", hook);
        assertEq(address(token.hook()), hook);

        token.updateVault(asset, vault);
        assertEq(address(token.vault(asset)), vault);

        // remove self from wards
        token.deny(self);

        // auth fail
        vm.expectRevert(IShareToken.NotAuthorizedOrHook.selector);
        token.file("hook", hook);

        vm.expectRevert(IAuth.NotAuthorized.selector);
        token.updateVault(asset, vault);
    }

    // --- erc165 checks ---
    function testERC165Support(bytes4 unsupportedInterfaceId) public view {
        bytes4 erc165 = 0x01ffc9a7;
        bytes4 erc7575Share = 0xf815c03d;

        vm.assume(unsupportedInterfaceId != erc165 && unsupportedInterfaceId != erc7575Share);

        assertEq(type(IERC165).interfaceId, erc165);
        assertEq(type(IERC7575Share).interfaceId, erc7575Share);

        assertEq(token.supportsInterface(erc165), true);
        assertEq(token.supportsInterface(erc7575Share), true);

        assertEq(token.supportsInterface(unsupportedInterfaceId), false);
    }

    // --- erc1404 checks ---
    function testERC1404Support() public view {
        assertEq(token.messageForTransferRestriction(0), "transfer-allowed");
        assertEq(token.messageForTransferRestriction(1), "transfer-blocked");
    }

    // --- RestrictedTransfers ---
    // transferFrom
    /// forge-config: default.isolate = true
    function testTransferFrom() public {
        _testTransferFrom(1, true);
    }

    // --- RestrictedTransfers ---
    // transferFrom
    /// forge-config: default.isolate = true
    function testTransferFromFuzz(uint256 amount) public {
        _testTransferFrom(amount, false);
    }

    function _testTransferFrom(uint256 amount, bool snap) internal {
        amount = bound(amount, 0, type(uint128).max / 2);

        restrictedTransfers.updateMember(address(token), self, uint64(validUntil));
        token.mint(self, amount * 2);

        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictedTransfers.updateMember(address(token), targetUser, uint64(validUntil));
        (bool _isMember, uint64 _validUntil) = restrictedTransfers.isMember(address(token), targetUser);
        assertTrue(_isMember);
        assertEq(_validUntil, validUntil);

        restrictedTransfers.freeze(address(token), self);
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictedTransfers.unfreeze(address(token), self);
        restrictedTransfers.freeze(address(token), targetUser);
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transferFrom(self, targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictedTransfers.unfreeze(address(token), targetUser);
        if (snap) {
            vm.startSnapshotGas("ShareToken", "transferFrom");
        }
        token.transferFrom(self, targetUser, amount);
        if (snap) {
            vm.stopSnapshotGas();
        }
        assertEq(token.balanceOf(targetUser), amount);
        afterTransferAssumptions(self, targetUser, amount);

        vm.warp(validUntil + 1);
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transferFrom(self, targetUser, amount);
    }

    function testTransferFromTokensWithApproval(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);
        address sender = makeAddr("sender");
        restrictedTransfers.updateMember(address(token), sender, uint64(validUntil));
        token.mint(sender, amount);

        restrictedTransfers.updateMember(address(token), targetUser, uint64(validUntil));

        vm.expectRevert(IERC20.InsufficientAllowance.selector);
        token.transferFrom(sender, targetUser, amount);

        vm.prank(sender);
        token.approve(self, amount);
        token.transferFrom(sender, targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        assertEq(token.balanceOf(sender), 0);
    }

    // transfer
    function testTransfer(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max / 2);

        restrictedTransfers.updateMember(address(token), self, uint64(validUntil));
        token.mint(self, amount * 2);

        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictedTransfers.updateMember(address(token), targetUser, uint64(validUntil));
        (bool _isMember, uint64 _validUntil) = restrictedTransfers.isMember(address(token), targetUser);
        assertTrue(_isMember);
        assertEq(_validUntil, validUntil);

        restrictedTransfers.freeze(address(token), self);
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), 0);

        restrictedTransfers.unfreeze(address(token), self);
        token.transfer(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        afterTransferAssumptions(self, targetUser, amount);

        vm.warp(validUntil + 1);
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.transfer(targetUser, amount);
    }

    // auth transfer
    function testAuthTransferFrom(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max);
        address sourceUser = makeAddr("sourceUser");
        restrictedTransfers.updateMember(address(token), sourceUser, uint64(validUntil));
        token.mint(sourceUser, amount);

        vm.prank(address(2));
        vm.expectRevert(IAuth.NotAuthorized.selector);
        token.authTransferFrom(sourceUser, sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), amount);
        assertEq(token.balanceOf(self), 0);

        token.authTransferFrom(sourceUser, sourceUser, self, amount);
        assertEq(token.balanceOf(sourceUser), 0);
        assertEq(token.balanceOf(self), amount);
    }

    // mint
    function testMintTokensToMemberWorks(uint256 amount) public {
        amount = bound(amount, 0, type(uint128).max / 2);

        // mint fails -> self not a member
        vm.expectRevert(IHook.TransferBlocked.selector);
        token.mint(targetUser, amount);

        restrictedTransfers.updateMember(address(token), targetUser, uint64(validUntil));
        (bool _isMember, uint64 _validUntil) = restrictedTransfers.isMember(address(token), targetUser);
        assertTrue(_isMember);
        assertEq(_validUntil, validUntil);

        token.mint(targetUser, amount);
        assertEq(token.balanceOf(targetUser), amount);
        afterTransferAssumptions(address(0), targetUser, amount);

        vm.warp(validUntil + 1);

        vm.expectRevert(IHook.TransferBlocked.selector);
        token.mint(targetUser, amount);
    }

    function afterTransferAssumptions(address from, address to, uint256 value) internal view {
        assertEq(restrictedTransfers.values_address("onERC20Transfer_from"), from);
        assertEq(restrictedTransfers.values_address("onERC20Transfer_to"), to);
        assertEq(restrictedTransfers.values_uint256("onERC20Transfer_value"), value);
    }
}
