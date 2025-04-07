// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {SafeTransferLib} from "src/misc/libraries/SafeTransferLib.sol";
import "src/misc/interfaces/IERC20.sol";
import {IMulticall} from "src/misc/interfaces/IMulticall.sol";
import {ReentrancyProtection} from "src/misc/ReentrancyProtection.sol";

import {MessageLib} from "src/common/libraries/MessageLib.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";

import "test/vaults/BaseTest.sol";
import "src/vaults/interfaces/IERC7575.sol";
import "src/vaults/interfaces/IERC7540.sol";
import {VaultRouter} from "src/vaults/VaultRouter.sol";
import {MockERC20Wrapper} from "test/vaults/mocks/MockERC20Wrapper.sol";
import {MockReentrantERC20Wrapper1, MockReentrantERC20Wrapper2} from "test/vaults/mocks/MockReentrantERC20Wrapper.sol";

contract VaultRouterTest is BaseTest {
    using MessageLib for *;

    uint256 constant GAS_BUFFER = 10 gwei;
    bytes PAYLOAD_FOR_GAS_ESTIMATION = MessageLib.NotifyPool(1).serialize();

    /// forge-config: default.isolate = true
    function testCFGRouterDeposit() public {
        _testCFGRouterDeposit(4, true);
    }

    /// forge-config: default.isolate = true
    function testCFGRouterDepositFuzz(uint256 amount) public {
        vm.assume(amount % 2 == 0);
        _testCFGRouterDeposit(amount, false);
    }

    function _testCFGRouterDeposit(uint256 amount, bool snap) internal {
        // If lower than 4 or odd, rounding down can lead to not receiving any tokens
        amount = uint128(bound(amount, 4, MAX_UINT128));

        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);

        vm.expectRevert(bytes("AsyncVault/invalid-owner"));
        vaultRouter.requestDeposit{value: 1 wei}(vault_, amount, self, self);

        vaultRouter.enable(vault_);
        vm.expectRevert(bytes("AsyncRequests/transfer-not-allowed"));
        vaultRouter.requestDeposit{value: 1 wei}(vault_, amount, self, self);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);

        uint256 gas = estimateGas() + GAS_BUFFER;

        vm.expectRevert(SafeTransferLib.SafeTransferFromFailed.selector);
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        erc20.approve(vault_, amount);

        address nonOwner = makeAddr("NonOwner");
        vm.deal(nonOwner, 10 ether);
        vm.prank(nonOwner);
        vm.expectRevert(bytes("VaultRouter/invalid-owner"));
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);

        if (snap) {
            snapStart("VaultRouter_requestDeposit");
        }
        vaultRouter.requestDeposit{value: gas}(vault_, amount, self, self);
        if (snap) {
            snapEnd();
        }

        assertEq(address(gateway).balance, GAS_BUFFER, "Gateway balance mismatch");
        for (uint8 i; i < testAdapters.length; i++) {
            MockAdapter adapter = MockAdapter(address(testAdapters[i]));
            uint256[] memory payCalls = adapter.callsWithValue("send");
            // Messages: registerAsset and requestDeposit
            assertEq(payCalls.length, 2);
            assertEq(
                payCalls[1],
                adapter.estimate(
                    OTHER_CHAIN_ID,
                    PAYLOAD_FOR_GAS_ESTIMATION,
                    mockedGasService.gasLimit(OTHER_CHAIN_ID, PAYLOAD_FOR_GAS_ESTIMATION)
                ),
                "payload gas mismatch"
            );
        }

        // trigger - deposit order fulfillment
        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), sharePayout);
        assertEq(vault.maxDeposit(self), amount);
        IShareToken shareToken = IShareToken(address(vault.share()));
        assertEq(shareToken.balanceOf(address(escrow)), sharePayout);

        if (snap) {
            snapStart("VaultRouter_claimDeposit");
        }
        vaultRouter.claimDeposit(vault_, self, self);
        if (snap) {
            snapEnd();
        }
        assertApproxEqAbs(shareToken.balanceOf(self), sharePayout, 1);
        assertApproxEqAbs(shareToken.balanceOf(self), sharePayout, 1);
        assertApproxEqAbs(shareToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    function testEnableDisableVaults() public {
        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        root.veto(address(vaultRouter));
        vm.expectRevert(bytes("AsyncVault/not-endorsed"));
        vaultRouter.enable(vault_);
        assertEq(vault.isOperator(address(this), address(vaultRouter)), false);
        assertEq(vaultRouter.isEnabled(vault_, address(this)), false);

        root.endorse(address(vaultRouter));
        vaultRouter.enable(vault_);
        assertEq(vault.isOperator(address(this), address(vaultRouter)), true);
        assertEq(vaultRouter.isEnabled(vault_, address(this)), true);

        root.veto(address(vaultRouter));
        vm.expectRevert(bytes("AsyncVault/not-endorsed"));
        vaultRouter.disable(vault_);
        assertEq(vault.isOperator(address(this), address(vaultRouter)), true);
        assertEq(vaultRouter.isEnabled(vault_, address(this)), true);

        root.endorse(address(vaultRouter));
        vaultRouter.disable(vault_);
        assertEq(vault.isOperator(address(this), address(vaultRouter)), false);
        assertEq(vaultRouter.isEnabled(vault_, address(this)), false);
    }

    function testRouterAsyncDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        vaultRouter.enableLockDepositRequest(vault_, amount);

        uint256 fuel = estimateGas();

        // Any address should be able to call executeLockedDepositRequest for an investor
        address randomAddress = address(0x123);
        vm.label(randomAddress, "randomAddress");
        vm.deal(randomAddress, 10 ether);
        vm.startPrank(randomAddress);
        vaultRouter.executeLockedDepositRequest{value: fuel}(vault_, address(this));
        vm.stopPrank();

        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), sharePayout);
        assertEq(vault.maxDeposit(self), amount);
        IShareToken shareToken = IShareToken(address(vault.share()));
        assertEq(shareToken.balanceOf(address(escrow)), sharePayout);

        // Any address should be able to call claimDeposit for an investor
        vm.prank(randomUser);
        vaultRouter.claimDeposit(vault_, self, self);
        assertApproxEqAbs(shareToken.balanceOf(self), sharePayout, 1);
        assertApproxEqAbs(shareToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), amount, 1);
    }

    /// forge-config: default.isolate = true
    function testRouterRedeem() public {
        _testRouterRedeem(4, true);
    }

    /// forge-config: default.isolate = true
    function testRouterRedeemFuzz(uint256 amount) public {
        vm.assume(amount % 2 == 0);
        _testRouterRedeem(amount, false);
    }

    function _testRouterRedeem(uint256 amount, bool snap) internal {
        amount = uint128(bound(amount, 4, MAX_UINT128));

        // deposit
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        if (snap) {
            snapStart("VaultRouter_enable");
        }
        vaultRouter.enable(vault_);
        if (snap) {
            snapEnd();
        }

        uint256 fuel = estimateGas();
        vaultRouter.requestDeposit{value: fuel}(vault_, amount, self, self);

        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, self);
        IShareToken shareToken = IShareToken(address(vault.share()));
        vaultRouter.claimDeposit(vault_, self, self);
        shareToken.approve(address(vaultRouter), sharePayout);

        address nonOwner = makeAddr("NonOwner");
        vm.deal(nonOwner, 10 ether);
        vm.prank(nonOwner);
        vm.expectRevert(bytes("VaultRouter/invalid-owner"));
        vaultRouter.requestRedeem{value: fuel}(vault_, sharePayout, self, self);

        // redeem
        if (snap) {
            snapStart("VaultRouter_requestRedeem");
        }
        vaultRouter.requestRedeem{value: fuel}(vault_, sharePayout, self, self);
        if (snap) {
            snapEnd();
        }
        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, sharePayout, self);
        assertApproxEqAbs(shareToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(shareToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
        vaultRouter.claimRedeem(vault_, self, self);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(self), assetPayout, 1);
    }

    function testRouterDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        uint256 fuel = estimateGas();
        (ERC20 erc20X, ERC20 erc20Y, AsyncVault vault1, AsyncVault vault2) = setUpMultipleVaults(amount1, amount2);

        vaultRouter.enable(address(vault1));
        vaultRouter.enable(address(vault2));

        vaultRouter.requestDeposit{value: fuel}(address(vault1), amount1, self, self);
        vaultRouter.requestDeposit{value: fuel}(address(vault2), amount2, self, self);

        // trigger - deposit order fulfillment
        uint128 assetId1 = poolManager.assetToId(address(erc20X), erc20TokenId);
        uint128 assetId2 = poolManager.assetToId(address(erc20Y), erc20TokenId);
        (uint128 sharePayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 sharePayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);

        assertEq(vault1.maxMint(self), sharePayout1);
        assertEq(vault2.maxMint(self), sharePayout2);
        assertEq(vault1.maxDeposit(self), amount1);
        assertEq(vault2.maxDeposit(self), amount2);
        IShareToken shareToken1 = IShareToken(address(vault1.share()));
        IShareToken shareToken2 = IShareToken(address(vault2.share()));
        assertEq(shareToken1.balanceOf(address(escrow)), sharePayout1);
        assertEq(shareToken2.balanceOf(address(escrow)), sharePayout2);

        vaultRouter.claimDeposit(address(vault1), self, self);
        vaultRouter.claimDeposit(address(vault2), self, self);
        assertApproxEqAbs(shareToken1.balanceOf(self), sharePayout1, 1);
        assertApproxEqAbs(shareToken2.balanceOf(self), sharePayout2, 1);
        assertApproxEqAbs(shareToken1.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(shareToken2.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), amount1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), amount2, 1);
    }

    function testRouterRedeemFromMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        uint256 fuel = estimateGas();
        // deposit
        (ERC20 erc20X, ERC20 erc20Y, AsyncVault vault1, AsyncVault vault2) = setUpMultipleVaults(amount1, amount2);

        vaultRouter.enable(address(vault1));
        vaultRouter.enable(address(vault2));

        vaultRouter.requestDeposit{value: fuel}(address(vault1), amount1, self, self);
        vaultRouter.requestDeposit{value: fuel}(address(vault2), amount2, self, self);

        uint128 assetId1 = poolManager.assetToId(address(erc20X), erc20TokenId);
        uint128 assetId2 = poolManager.assetToId(address(erc20Y), erc20TokenId);
        (uint128 sharePayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 sharePayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);
        vaultRouter.claimDeposit(address(vault1), self, self);
        vaultRouter.claimDeposit(address(vault2), self, self);

        // redeem
        IShareToken(address(vault1.share())).approve(address(vaultRouter), sharePayout1);
        IShareToken(address(vault2.share())).approve(address(vaultRouter), sharePayout2);
        vaultRouter.requestRedeem{value: fuel}(address(vault1), sharePayout1, self, self);
        vaultRouter.requestRedeem{value: fuel}(address(vault2), sharePayout2, self, self);
        (uint128 assetPayout1) = fulfillRedeemRequest(vault1, assetId1, sharePayout1, self);
        (uint128 assetPayout2) = fulfillRedeemRequest(vault2, assetId2, sharePayout2, self);
        assertApproxEqAbs(IShareToken(address(vault1.share())).balanceOf(self), 0, 1);
        assertApproxEqAbs(IShareToken(address(vault2.share())).balanceOf(self), 0, 1);
        assertApproxEqAbs(IShareToken(address(vault1.share())).balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(IShareToken(address(vault2.share())).balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), assetPayout2, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), 0, 1);
        vaultRouter.claimRedeem(address(vault1), self, self);
        vaultRouter.claimRedeem(address(vault2), self, self);
        assertApproxEqAbs(erc20X.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20Y.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20X.balanceOf(self), assetPayout1, 1);
        assertApproxEqAbs(erc20Y.balanceOf(self), assetPayout2, 1);
    }

    /// forge-config: default.isolate = true
    function testMulticallingApproveVaultAndExecuteLockedDepositRequest() public {
        _testMulticallingApproveVaultAndExecuteLockedDepositRequest(4, true);
    }

    /// forge-config: default.isolate = true
    function testMulticallingApproveVaultAndExecuteLockedDepositRequestFuzz(uint256 amount) public {
        vm.assume(amount % 2 == 0);
        _testMulticallingApproveVaultAndExecuteLockedDepositRequest(amount, false);
    }

    function _testMulticallingApproveVaultAndExecuteLockedDepositRequest(uint256 amount, bool snap) internal {
        amount = uint128(bound(amount, 4, MAX_UINT128));

        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);
        erc20.approve(address(vaultRouter), amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        vaultRouter.enable(address(vault_));
        if (snap) {
            snapStart("VaultRouter_lockDepositRequest");
        }
        vaultRouter.lockDepositRequest(vault_, amount, self, self);
        if (snap) {
            snapEnd();
        }

        // multicall
        uint256 fuel = estimateGas();
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(vaultRouter.executeLockedDepositRequest.selector, vault_, self, fuel);
        vaultRouter.multicall{value: fuel}(calls);

        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, self);

        assertEq(vault.maxMint(self), sharePayout);
        assertEq(vault.maxDeposit(self), amount);
        IShareToken shareToken = IShareToken(address(vault.share()));
        assertEq(shareToken.balanceOf(address(escrow)), sharePayout);
    }

    function testMulticallingDepositClaimAndRequestRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        // deposit
        (, address vault_, uint128 assetId) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");
        erc20.mint(self, amount);
        erc20.approve(vault_, amount);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        vaultRouter.enable(vault_);

        uint256 fuel = estimateGas();
        vaultRouter.requestDeposit{value: fuel}(vault_, amount, self, self);

        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, self);
        IShareToken shareToken = IShareToken(address(vault.share()));
        shareToken.approve(address(vaultRouter), sharePayout);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(vaultRouter.claimDeposit.selector, vault_, self, self);
        calls[1] = abi.encodeWithSelector(vaultRouter.requestRedeem.selector, vault_, sharePayout, self, self, fuel);
        vaultRouter.multicall{value: fuel}(calls);

        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, sharePayout, self);
        assertApproxEqAbs(shareToken.balanceOf(self), 0, 1);
        assertApproxEqAbs(shareToken.balanceOf(address(escrow)), 0, 1);
        assertApproxEqAbs(erc20.balanceOf(address(escrow)), assetPayout, 1);
        assertApproxEqAbs(erc20.balanceOf(self), 0, 1);
    }

    function testMulticallingDepositIntoMultipleVaults(uint256 amount1, uint256 amount2) public {
        amount1 = uint128(bound(amount1, 4, MAX_UINT128));
        vm.assume(amount1 % 2 == 0);
        amount2 = uint128(bound(amount2, 4, MAX_UINT128));
        vm.assume(amount2 % 2 == 0);

        (ERC20 erc20X, ERC20 erc20Y, AsyncVault vault1, AsyncVault vault2) = setUpMultipleVaults(amount1, amount2);

        vaultRouter.enable(address(vault1));
        vaultRouter.enable(address(vault2));

        uint256 gas = estimateGas();
        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(vaultRouter.requestDeposit.selector, vault1, amount1, self, self);
        calls[1] = abi.encodeWithSelector(vaultRouter.requestDeposit.selector, vault2, amount2, self, self);
        vaultRouter.multicall{value: gas * calls.length}(calls);

        // trigger - deposit order fulfillment
        uint128 assetId1 = poolManager.assetToId(address(erc20X), erc20TokenId);
        uint128 assetId2 = poolManager.assetToId(address(erc20Y), erc20TokenId);
        (uint128 sharePayout1) = fulfillDepositRequest(vault1, assetId1, amount1, self);
        (uint128 sharePayout2) = fulfillDepositRequest(vault2, assetId2, amount2, self);

        assertEq(vault1.maxMint(self), sharePayout1);
        assertEq(vault2.maxMint(self), sharePayout2);
        assertEq(vault1.maxDeposit(self), amount1);
        assertEq(vault2.maxDeposit(self), amount2);
        IShareToken shareToken1 = IShareToken(address(vault1.share()));
        IShareToken shareToken2 = IShareToken(address(vault2.share()));
        assertEq(shareToken1.balanceOf(address(escrow)), sharePayout1);
        assertEq(shareToken2.balanceOf(address(escrow)), sharePayout2);
    }

    function testLockAndExecuteDepositRequest(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        (, address vault_, uint128 assetId) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        vm.deal(investor, 10 ether);
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        erc20.approve(address(vaultRouter), amount);

        uint256 fuel = estimateGas() + GAS_BUFFER;

        // multicall
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(vaultRouter.wrap.selector, wrapper, amount, address(vaultRouter), investor);
        calls[1] = abi.encodeWithSelector(
            vaultRouter.lockDepositRequest.selector, vault_, amount, investor, address(vaultRouter)
        );
        calls[2] = abi.encodeWithSelector(vaultRouter.executeLockedDepositRequest.selector, vault_, investor, fuel);
        vaultRouter.multicall{value: fuel}(calls);

        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, investor);

        assertEq(vault.maxMint(investor), sharePayout);
        assertEq(vault.maxDeposit(investor), amount);
        IShareToken shareToken = IShareToken(address(vault.share()));
        assertEq(shareToken.balanceOf(address(escrow)), sharePayout);
    }

    function testWrapAndUnwrap(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        (, address vault_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        vaultRouter.enable(vault_);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        erc20.approve(address(vaultRouter), amount);

        assertEq(erc20.balanceOf(investor), amount);

        // multicall
        bytes[] memory calls = new bytes[](2);
        calls[0] =
            abi.encodeWithSelector(vaultRouter.wrap.selector, address(wrapper), amount, address(vaultRouter), investor);
        calls[1] = abi.encodeWithSelector(vaultRouter.unwrap.selector, address(wrapper), amount, investor);
        vaultRouter.multicall(calls);

        assertEq(erc20.balanceOf(investor), amount);
    }

    function testWrapAndDeposit(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        (, address vault_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        vaultRouter.enable(vault_);

        erc20.mint(investor, amount);
        vm.startPrank(investor);
        erc20.approve(address(vaultRouter), amount);

        assertEq(erc20.balanceOf(investor), amount);

        vm.deal(investor, 10 ether);
        uint256 fuel = estimateGas();
        vaultRouter.wrap(address(wrapper), amount, address(vaultRouter), investor);
        vaultRouter.requestDeposit{value: fuel}(address(vault), amount, investor, address(vaultRouter));
    }

    function testWrapAndAutoUnwrapOnRedeem(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        (, address vault_, uint128 assetId) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");

        erc20.mint(investor, amount);

        // Investor locks deposit request and enables permissionless lcaiming
        vm.startPrank(investor);
        erc20.approve(address(vaultRouter), amount);
        vaultRouter.enableLockDepositRequest(vault_, amount);
        vm.stopPrank();

        // Anyone else can execute the request and claim the deposit
        uint256 fuel = estimateGas();
        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), investor, type(uint64).max);
        vaultRouter.executeLockedDepositRequest{value: fuel}(vault_, investor);
        (uint128 sharePayout) = fulfillDepositRequest(vault, assetId, amount, investor);

        IShareToken shareToken = IShareToken(address(vault.share()));
        vaultRouter.claimDeposit(vault_, investor, investor);

        // Investors submits redemption  request
        vm.deal(investor, 10 ether);
        vm.startPrank(investor);
        shareToken.approve(address(vaultRouter), sharePayout);
        vaultRouter.requestRedeem{value: fuel}(vault_, sharePayout, investor, investor);
        vm.stopPrank();

        // Anyone else claims the redeem
        (uint128 assetPayout) = fulfillRedeemRequest(vault, assetId, sharePayout, investor);
        assertEq(wrapper.balanceOf(address(escrow)), assetPayout);
        assertEq(erc20.balanceOf(address(investor)), 0);
        vaultRouter.claimRedeem(vault_, investor, investor);

        // Token was immediately unwrapped
        assertEq(wrapper.balanceOf(address(escrow)), 0);
        assertEq(erc20.balanceOf(investor), assetPayout);
    }

    function testEnableLockDepositRequest(uint256 wrappedAmount, uint256 underlyingAmount) public {
        wrappedAmount = uint128(bound(wrappedAmount, 4, MAX_UINT128));
        vm.assume(wrappedAmount % 2 == 0);

        underlyingAmount = uint128(bound(underlyingAmount, 4, MAX_UINT128));
        vm.assume(underlyingAmount % 2 == 0);

        vm.assume(wrappedAmount != underlyingAmount);
        vm.assume(wrappedAmount < underlyingAmount);

        address routerEscrowAddress = address(routerEscrow);

        MockERC20Wrapper wrapper = new MockERC20Wrapper(address(erc20));
        (, address vault_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        vm.label(vault_, "vault");

        erc20.mint(self, underlyingAmount);
        erc20.approve(address(vaultRouter), underlyingAmount);
        wrapper.mint(self, wrappedAmount);
        wrapper.approve(address(vaultRouter), wrappedAmount);

        // Testing partial of wrapped asset balance
        uint256 wrappedBalance = wrapper.balanceOf(self);
        uint256 deposit = wrappedBalance / 2;
        uint256 remainingWrapped = wrappedBalance / 2;
        uint256 remainingUnderlying = erc20.balanceOf(self);
        uint256 escrowBalance = deposit;
        vaultRouter.enableLockDepositRequest(vault_, deposit);
        assertEq(wrapper.balanceOf(routerEscrowAddress), escrowBalance);
        assertEq(wrapper.balanceOf(self), remainingWrapped);
        assertEq(erc20.balanceOf(routerEscrowAddress), 0);
        assertEq(erc20.balanceOf(self), remainingUnderlying);

        // Testing more than the wrapped asset balance
        wrappedBalance = wrapper.balanceOf(self);
        deposit = wrappedBalance + 1;
        remainingWrapped = wrappedBalance;
        remainingUnderlying = erc20.balanceOf(self) - deposit;
        escrowBalance = escrowBalance + deposit;
        vaultRouter.enableLockDepositRequest(vault_, deposit);
        assertEq(wrapper.balanceOf(routerEscrowAddress), escrowBalance); // amount was used from the underlying asset
            // and wrapped
        assertEq(wrapper.balanceOf(self), remainingWrapped);
        assertEq(erc20.balanceOf(routerEscrowAddress), 0);
        assertEq(erc20.balanceOf(self), remainingUnderlying);

        // Testing whole wrapped amount
        wrappedBalance = wrapper.balanceOf(self);
        deposit = wrappedBalance;
        remainingUnderlying = erc20.balanceOf(self);
        escrowBalance = escrowBalance + deposit;
        vaultRouter.enableLockDepositRequest(vault_, deposit);
        assertEq(wrapper.balanceOf(routerEscrowAddress), escrowBalance);
        assertEq(wrapper.balanceOf(self), 0);
        assertEq(erc20.balanceOf(routerEscrowAddress), 0);
        assertEq(erc20.balanceOf(self), remainingUnderlying);

        // Testing more than the underlying
        uint256 underlyingBalance = erc20.balanceOf(self);
        deposit = underlyingBalance + 1;
        remainingUnderlying = underlyingBalance;
        vm.expectRevert(SafeTransferLib.SafeTransferFromFailed.selector);
        vaultRouter.enableLockDepositRequest(vault_, deposit);
        assertEq(wrapper.balanceOf(routerEscrowAddress), escrowBalance);
        assertEq(wrapper.balanceOf(self), 0);
        assertEq(erc20.balanceOf(routerEscrowAddress), 0);
        assertEq(erc20.balanceOf(self), remainingUnderlying);

        // Testing all the underlying
        deposit = erc20.balanceOf(self);
        escrowBalance = escrowBalance + deposit;
        vaultRouter.enableLockDepositRequest(vault_, deposit);
        assertEq(wrapper.balanceOf(routerEscrowAddress), escrowBalance);
        assertEq(wrapper.balanceOf(self), 0);
        assertEq(erc20.balanceOf(routerEscrowAddress), 0);
        assertEq(erc20.balanceOf(self), 0);

        // Testing with empty balance for both wrapped and underlying
        vm.expectRevert(bytes("VaultRouter/zero-balance"));
        vaultRouter.enableLockDepositRequest(vault_, wrappedAmount);
    }

    function testMultipleTopUpScenarios(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        (, address vault_,) = deploySimpleVault(VaultKind.Async);
        AsyncVault vault = AsyncVault(vault_);
        vm.label(vault_, "vault");

        erc20.mint(self, amount);

        centrifugeChain.updateMember(vault.poolId(), vault.trancheId(), self, type(uint64).max);
        erc20.approve(vault_, amount);
        vaultRouter.enable(vault_);

        uint256 gasLimit = estimateGas();
        uint256 lessGas = gasLimit - 1;

        vm.expectRevert(IGateway.NotEnoughTransactionGas.selector);
        vaultRouter.requestDeposit{value: lessGas}(vault_, amount, self, self);

        vm.expectRevert("PoolManager/unknown-vault");
        vaultRouter.requestDeposit{value: lessGas}(makeAddr("maliciousVault"), amount, self, self);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(vaultRouter.requestDeposit.selector, vault_, amount / 2, self, self);
        calls[1] = abi.encodeWithSelector(vaultRouter.requestDeposit.selector, vault_, amount / 2, self, self);

        assertEq(address(vaultRouter).balance, 0);
        vaultRouter.multicall{value: gasLimit}(calls);
    }

    // --- helpers ---
    function fulfillDepositRequest(AsyncVault vault, uint128 assetId, uint256 amount, address user)
        public
        returns (uint128 sharePayout)
    {
        uint128 price = 2 * 10 ** 18;
        sharePayout = uint128(amount * 10 ** 18 / price);
        assertApproxEqAbs(sharePayout, amount / 2, 2);
        centrifugeChain.isFulfilledDepositRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(user)), assetId, uint128(amount), sharePayout
        );
    }

    function fulfillRedeemRequest(AsyncVault vault, uint128 assetId, uint256 amount, address user)
        public
        returns (uint128 assetPayout)
    {
        uint128 price = 2 * 10 ** 18;
        assetPayout = uint128(amount * price / 10 ** 18);
        assertApproxEqAbs(assetPayout, amount * 2, 2);
        centrifugeChain.isFulfilledRedeemRequest(
            vault.poolId(), vault.trancheId(), bytes32(bytes20(user)), assetId, assetPayout, uint128(amount)
        );
    }

    function setUpMultipleVaults(uint256 amount1, uint256 amount2)
        public
        returns (ERC20 erc20X, ERC20 erc20Y, AsyncVault vault1, AsyncVault vault2)
    {
        erc20X = _newErc20("X's Dollar", "USDX", 6);
        erc20Y = _newErc20("Y's Dollar", "USDY", 6);
        vm.label(address(erc20X), "erc20X");
        vm.label(address(erc20Y), "erc20Y");
        (, address vault1_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(erc20X), 0, 0);
        (, address vault2_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("2")), address(erc20Y), 0, 0);
        vault1 = AsyncVault(vault1_);
        vault2 = AsyncVault(vault2_);
        vm.label(vault1_, "vault1");
        vm.label(vault2_, "vault2");

        erc20X.mint(self, amount1);
        erc20Y.mint(self, amount2);

        erc20X.approve(address(vault1_), amount1);
        erc20Y.approve(address(vault2_), amount2);

        centrifugeChain.updateMember(vault1.poolId(), vault1.trancheId(), self, type(uint64).max);
        centrifugeChain.updateMember(vault2.poolId(), vault2.trancheId(), self, type(uint64).max);
    }

    function testReentrancyCheck(uint256 amount) public {
        amount = uint128(bound(amount, 4, MAX_UINT128));
        vm.assume(amount % 2 == 0);

        MockReentrantERC20Wrapper1 wrapper = new MockReentrantERC20Wrapper1(address(erc20), address(vaultRouter));
        (, address vault_,) =
            deployVault(VaultKind.Async, 6, restrictedTransfers, bytes16(bytes("1")), address(wrapper), 0, 0);
        vm.label(vault_, "vault");

        address investor = makeAddr("investor");

        erc20.mint(investor, amount);

        // Investor locks deposit request and enables permissionless lcaiming
        vm.startPrank(investor);
        erc20.approve(address(vaultRouter), amount);
        vm.expectRevert(ReentrancyProtection.UnauthorizedSender.selector);
        vaultRouter.enableLockDepositRequest(vault_, amount);
        vm.stopPrank();
    }

    function estimateGas() internal view returns (uint256 total) {
        (, total) = gateway.estimate(OTHER_CHAIN_ID, PAYLOAD_FOR_GAS_ESTIMATION);
    }
}
