// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "src/misc/interfaces/IERC20.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";

import {MessageLib} from "src/common/libraries/MessageLib.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";

import "src/vaults/interfaces/IERC7575.sol";
import "src/vaults/interfaces/IERC7540.sol";
import {VaultRouter} from "src/vaults/VaultRouter.sol";
import {IVaultRouter} from "src/vaults/interfaces/IVaultRouter.sol";
import {IPoolManager} from "src/vaults/interfaces/IPoolManager.sol";

import {MockERC6909} from "test/misc/mocks/MockERC6909.sol";
import {MockERC20Wrapper} from "test/vaults/mocks/MockERC20Wrapper.sol";
import "test/vaults/BaseTest.sol";
import {IAsyncRequests} from "src/vaults/interfaces/investments/IAsyncRequests.sol";

interface Authlike {
    function rely(address) external;
}

contract ERC20WrapperFake {
    address public underlying;

    constructor(address underlying_) {
        underlying = underlying_;
    }
}

contract VaultRouterTest is BaseTest {
    using CastLib for *;
    using MessageLib for *;

    uint16 constant CHAIN_ID = 1;
    uint256 constant GAS_BUFFER = 10 gwei;
    bytes PAYLOAD_FOR_GAS_ESTIMATION = MessageLib.NotifyPool(1).serialize();

    function testInitialization() public {
        // redeploying within test to increase coverage
        new VaultRouter(address(routerEscrow), address(gateway), address(poolManager), messageDispatcher, address(this));

        assertEq(address(vaultRouter.escrow()), address(routerEscrow));
        assertEq(address(vaultRouter.gateway()), address(gateway));
        assertEq(address(vaultRouter.poolManager()), address(poolManager));
    }

    function testGetVault() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        assertEq(vaultRouter.getVault(vault.poolId(), vault.trancheId(), address(erc20)), vault_);
    }

    function testRequestDeposit() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 gas = estimateGas();

        vm.expectRevert(IAsyncVault.InvalidOwner.selector);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        vaultRouter.enable(vault_);

        vm.expectRevert(IGateway.NotEnoughTransactionGas.selector);
        vaultRouter.requestDeposit{value: gas - 1}(vault_, amount, self, self);

        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(escrow)), amount);
    }

    function testLockDepositRequests() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);

        vm.expectRevert(IPoolManager.UnknownVault.selector);
        vaultRouter.lockDepositRequest(makeAddr("maliciousVault"), amount, self, self);

        vaultRouter.lockDepositRequest(vault_, amount, self, self);

        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
    }

    function testUnlockDepositRequests() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");

        uint256 amount = 100 * 10 ** 18;

        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);

        vm.expectRevert(IVaultRouter.NoLockedBalance.selector);
        vaultRouter.unlockDepositRequest(vault_, self);

        vaultRouter.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
        assertEq(erc20.balanceOf(self), 0);
        vaultRouter.unlockDepositRequest(vault_, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testCancelDepositRequest() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);

        uint256 amount = 100 * 10 ** 18;
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);

        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);

        vaultRouter.enable(vault_);
        vaultRouter.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);
        assertEq(vault.pendingCancelDepositRequest(0, self), false);

        uint256 fuel = estimateGas();
        vm.deal(address(this), 10 ether);

        vm.expectRevert(IAsyncRequests.NoPendingRequest.selector);
        vaultRouter.cancelDepositRequest{value: fuel}(vault_);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        vaultRouter.executeLockedDepositRequest{value: fuel}(vault_, self);
        assertEq(vault.pendingDepositRequest(0, self), amount);

        vm.expectRevert(IGateway.NotEnoughTransactionGas.selector);
        vaultRouter.cancelDepositRequest{value: 0}(vault_);

        vaultRouter.cancelDepositRequest{value: fuel}(vault_);
        assertTrue(vault.pendingCancelDepositRequest(0, self));
    }

    function testClaimCancelDepositRequest() public {
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);

        uint256 amount = 100 * 10 ** 18;

        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 gas = estimateGas() + GAS_BUFFER;
        vaultRouter.enable(vault_);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(escrow)), amount);

        vaultRouter.cancelDepositRequest{value: gas}(vault_);
        assertEq(vault.pendingCancelDepositRequest(0, self), true);
        assertEq(erc20.balanceOf(address(escrow)), amount);
        centrifugeChain.isFulfilledCancelDepositRequest(
            vault.poolId(), vault.trancheId(), self.toBytes32(), assetId, uint128(amount)
        );
        assertEq(vault.claimableCancelDepositRequest(0, self), amount);

        address nonMember = makeAddr("nonMember");
        vm.prank(nonMember);
        vm.expectRevert(IVaultRouter.InvalidSender.selector);
        vaultRouter.claimCancelDepositRequest(vault_, nonMember, self);

        vm.expectRevert(IAsyncRequests.TransferNotAllowed.selector);
        vaultRouter.claimCancelDepositRequest(vault_, nonMember, self);

        vaultRouter.claimCancelDepositRequest(vault_, self, self);
        assertEq(erc20.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(self), amount);
    }

    function testRequestRedeem() external {
        // Deposit first
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 gas = estimateGas();
        vaultRouter.enable(vault_);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), assetId, uint128(amount), uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(address(vaultRouter), amount);

        vm.expectRevert(IGateway.NotEnoughTransactionGas.selector);
        vaultRouter.requestRedeem{value: gas - 1}(vault_, amount, self, self);

        vaultRouter.requestRedeem{value: gas}(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);
    }

    function testCancelRedeemRequest() public {
        // Deposit first
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 gas = estimateGas();
        vaultRouter.enable(vault_);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), assetId, uint128(amount), uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(address(vaultRouter), amount);
        vaultRouter.requestRedeem{value: gas}(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);

        vm.deal(address(this), 10 ether);

        vm.expectRevert(IGateway.NotEnoughTransactionGas.selector);
        vaultRouter.cancelRedeemRequest{value: gas - 1}(vault_);

        vaultRouter.cancelRedeemRequest{value: gas}(vault_);
        assertEq(vault.pendingCancelRedeemRequest(0, self), true);
    }

    function testClaimCancelRedeemRequest() public {
        // Deposit first
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);
        uint256 amount = 100 * 10 ** 18;
        erc20.mint(self, amount);
        erc20.approve(address(vault_), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        uint256 gas = estimateGas() + GAS_BUFFER;
        vaultRouter.enable(vault_);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        IERC20 share = IERC20(address(vault.share()));
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(self)), assetId, uint128(amount), uint128(amount)
        );
        vault.deposit(amount, self, self);
        assertEq(share.balanceOf(address(self)), amount);

        // Then redeem
        share.approve(vault_, amount);
        share.approve(address(vaultRouter), amount);
        vaultRouter.requestRedeem{value: gas}(vault_, amount, self, self);
        assertEq(share.balanceOf(address(self)), 0);

        vaultRouter.cancelRedeemRequest{value: gas}(vault_);
        assertEq(vault.pendingCancelRedeemRequest(0, self), true);

        centrifugeChain.isFulfilledCancelRedeemRequest(
            vault.poolId(), vault.trancheId(), self.toBytes32(), assetId, uint128(amount)
        );

        address sender = makeAddr("maliciousUser");
        vm.prank(sender);
        vm.expectRevert(IVaultRouter.InvalidSender.selector);
        vaultRouter.claimCancelRedeemRequest(vault_, sender, self);

        vaultRouter.claimCancelRedeemRequest(vault_, self, self);
        assertEq(share.balanceOf(address(self)), amount);
    }

    function testPermit() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");

        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        vm.label(owner, "owner");
        vm.label(address(vaultRouter), "spender");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    erc20.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(vaultRouter), 1e18, 0, block.timestamp))
                )
            )
        );

        vm.prank(owner);
        vaultRouter.permit(address(erc20), address(vaultRouter), 1e18, block.timestamp, v, r, s);

        assertEq(erc20.allowance(owner, address(vaultRouter)), 1e18);
        assertEq(erc20.nonces(owner), 1);
    }

    function testEnableAndDisable() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");

        assertFalse(AsyncVault(vault_).isOperator(self, address(vaultRouter)));
        assertEq(vaultRouter.isEnabled(vault_, self), false);
        vaultRouter.enable(vault_);
        assertTrue(AsyncVault(vault_).isOperator(self, address(vaultRouter)));
        assertEq(vaultRouter.isEnabled(vault_, self), true);
        vaultRouter.disable(vault_);
        assertFalse(AsyncVault(vault_).isOperator(self, address(vaultRouter)));
        assertEq(vaultRouter.isEnabled(vault_, self), false);
    }

    function testWrap() public {
        uint256 amount = 150 * 10 ** 18;
        uint256 balance = 100 * 10 ** 18;
        address receiver = makeAddr("receiver");
        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));

        vm.expectRevert(IVaultRouter.InvalidOwner.selector);
        vaultRouter.wrap(address(wrapper), amount, receiver, makeAddr("ownerIsNeitherCallerNorRouter"));

        vm.expectRevert(IVaultRouter.ZeroBalance.selector);
        vaultRouter.wrap(address(wrapper), amount, receiver, self);

        erc20.mint(self, balance);
        erc20.approve(address(vaultRouter), amount);
        wrapper.setFail("depositFor", true);
        vm.expectRevert(IVaultRouter.WrapFailed.selector);
        vaultRouter.wrap(address(wrapper), amount, receiver, self);

        wrapper.setFail("depositFor", false);
        vaultRouter.wrap(address(wrapper), amount, receiver, self);
        assertEq(wrapper.balanceOf(receiver), balance);
        assertEq(erc20.balanceOf(self), 0);

        erc20.mint(address(vaultRouter), balance);
        vaultRouter.wrap(address(wrapper), amount, receiver, address(vaultRouter));
        assertEq(wrapper.balanceOf(receiver), 200 * 10 ** 18);
        assertEq(erc20.balanceOf(address(vaultRouter)), 0);
    }

    function testUnwrap() public {
        uint256 amount = 150 * 10 ** 18;
        uint256 balance = 100 * 10 ** 18;
        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        erc20.mint(self, balance);
        erc20.approve(address(vaultRouter), amount);

        vm.expectRevert(IVaultRouter.ZeroBalance.selector);
        vaultRouter.unwrap(address(wrapper), amount, self);

        vaultRouter.wrap(address(wrapper), amount, address(vaultRouter), self);
        wrapper.setFail("withdrawTo", true);
        vm.expectRevert(IVaultRouter.UnwrapFailed.selector);
        vaultRouter.unwrap(address(wrapper), amount, self);
        wrapper.setFail("withdrawTo", false);

        assertEq(wrapper.balanceOf(address(vaultRouter)), balance);
        assertEq(erc20.balanceOf(self), 0);
        vaultRouter.unwrap(address(wrapper), amount, self);
        assertEq(wrapper.balanceOf(address(vaultRouter)), 0);
        assertEq(erc20.balanceOf(self), balance);
    }

    function testEstimate() public view {
        bytes memory message = MessageLib.NotifyPool(1).serialize();
        uint256 estimated = vaultRouter.estimate(CHAIN_ID, message);
        uint256 gatewayEstimated = gateway.estimate(CHAIN_ID, message);
        assertEq(estimated, gatewayEstimated);
    }

    function testIfUserIsPermittedToExecuteRequests() public {
        uint256 amount = 100 * 10 ** 18;
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        vm.label(vault_, "vault");
        AsyncVault vault = AsyncVault(vault_);

        vm.deal(self, 1 ether);
        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);

        bool canUserExecute = vaultRouter.hasPermissions(vault_, self);
        assertFalse(canUserExecute);

        vaultRouter.lockDepositRequest(vault_, amount, self, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), amount);

        uint256 gasLimit = vaultRouter.estimate(CHAIN_ID, PAYLOAD_FOR_GAS_ESTIMATION);

        vm.expectRevert(IAsyncRequests.TransferNotAllowed.selector);
        vaultRouter.executeLockedDepositRequest{value: gasLimit}(vault_, self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        canUserExecute = vaultRouter.hasPermissions(vault_, self);
        assertTrue(canUserExecute);

        vaultRouter.executeLockedDepositRequest{value: gasLimit}(vault_, self);
        assertEq(erc20.balanceOf(address(routerEscrow)), 0);
        assertEq(erc20.balanceOf(address(escrow)), amount);
    }

    function estimateGas() internal view returns (uint256) {
        return gateway.estimate(CHAIN_ID, PAYLOAD_FOR_GAS_ESTIMATION);
    }
}
