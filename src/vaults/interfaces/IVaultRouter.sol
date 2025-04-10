// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import {IMulticall} from "src/misc/interfaces/IMulticall.sol";

interface IVaultRouter is IMulticall {
    // --- Events ---
    event LockDepositRequest(
        address indexed vault, address indexed controller, address indexed owner, address sender, uint256 amount
    );
    event UnlockDepositRequest(address indexed vault, address indexed controller, address indexed receiver);
    event ExecuteLockedDepositRequest(address indexed vault, address indexed controller, address sender);

    /// @notice Check how much of the `vault`'s asset is locked for the current `controller`.
    /// @dev    This is a getter method
    function lockedRequests(address controller, address vault) external view returns (uint256 amount);

    // --- Manage permissionless claiming ---
    /// @notice Enable permissionless claiming
    /// @dev    After this is called, anyone can claim tokens to msg.sender.
    ///         Even any requests submitted directly to the vault (not through the VaultRouter) will be
    ///         permissionlessly claimable through the VaultRouter, until `disable()` is called.
    function enable(address vault) external payable;

    /// @notice Disable permissionless claiming
    function disable(address vault) external payable;

    // --- Deposit ---
    /// @notice Check `IERC7540Deposit.requestDeposit`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `VaultRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Deposit.requestDeposit.assets
    /// @param  controller Check @param IERC7540Deposit.requestDeposit.controller
    /// @param  owner Check @param IERC7540Deposit.requestDeposit.owner
    function requestDeposit(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Locks `amount` of `vault`'s asset in an escrow before actually sending a deposit LockDepositRequest
    ///         There are users that would like to interact with the protocol but don't have permissions yet. They can
    ///         lock the funds they would like to deposit beforehand.
    ///         Once permissions are granted, anyone can deposit on
    ///         their behalf by calling `executeLockedDepositRequest`.
    ///
    ///         Example: DAO with onchain governance, that wants to invest their treasury
    ///             The process that doesn't include calling this method is as follows:
    ///
    ///                 1. The DAO signs the legal agreements for the pool => no onchain action,
    ///                    but only after this the issuer can call update_member to add them as a whitelisted investor
    ///                 2. Call `requestDeposit` to lock funds
    ///                 3. After the pool has fulfilled their request, call `deposit` to claim their share class tokens
    ///
    ///
    ///             With the new router function the steps are as follows:
    ///
    ///                 1. DAO signs the legal agreement + calls  `openLockDepositRequest`  in 1 governance proposal
    ///
    ///                 2. Issuer then gives them permissions, then calls `executeLockDepositFunds` for them,
    ///                    then fulfills the request, then calls `claimDeposit` for them
    ///
    /// @dev    For initial interaction better use `openLockDepositRequest` which includes some of the message calls
    ///         that the caller must do execute before calling `lockDepositRequest`
    ///
    /// @param  vault The address of the vault to invest in
    /// @param  amount Amount to invest
    /// @param  controller Address of the owner of the position
    /// @param  owner Where the  funds to be deposited will be take from
    function lockDepositRequest(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Helper method to lock a deposit request, and enable permissionless claiming of that vault in 1 call.
    /// @dev    It starts interaction with the vault by calling `open`.
    ///         Vaults support assets that are wrapped one. When user calls this method
    ///         and the vault's asset is a wrapped one, first the balance of the wrapped asset is checked.
    ///         If balance >= `amount`, then this asset is used
    ///         else  amount is treat as an underlying asset one and it is wrapped.
    /// @param  vault Address of the vault
    /// @param  amount Amount to be deposited
    function enableLockDepositRequest(address vault, uint256 amount) external payable;

    /// @notice Unlocks all deposited assets of the current caller for a given vault
    ///
    /// @param  vault Address of the vault for which funds were locked
    /// @param  receiver Address of the received of the unlocked funds
    function unlockDepositRequest(address vault, address receiver) external payable;

    /// @notice After the controller is given permissions, anyone can call this method and
    ///         actually request a deposit with the locked funds on the behalf of the `controller`
    /// @param  vault The vault for which funds are locked
    /// @param  controller Owner of the deposit position
    function executeLockedDepositRequest(address vault, address controller) external payable;

    /// @notice Check IERC7540Deposit.mint
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7540Deposit.mint.receiver
    /// @param  controller Check IERC7540Deposit.mint.owner
    function claimDeposit(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540CancelDeposit.cancelDepositRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `VaultRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    function cancelDepositRequest(address vault) external payable;

    /// @notice Check IERC7540CancelDeposit.claimCancelDepositRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelDeposit.claimCancelDepositRequest.receiver
    /// @param  controller Check  IERC7540CancelDeposit.claimCancelDepositRequest.controller
    function claimCancelDepositRequest(address vault, address receiver, address controller) external payable;

    // --- Redeem ---
    /// @notice Check `IERC7540Redeem.requestRedeem`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `VaultRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault to deposit into
    /// @param  amount Check @param IERC7540Redeem.requestRedeem.shares
    /// @param  controller Check @param IERC7540Redeem.requestRedeem.controller
    /// @param  owner Check @param IERC7540Redeem.requestRedeem.owner
    function requestRedeem(address vault, uint256 amount, address controller, address owner) external payable;

    /// @notice Check IERC7575.withdraw
    /// @dev    If the underlying vault asset is a wrapped one,
    ///         `VaultRouter.unwrap` is called and the unwrapped
    ///         asset is sent to the receiver
    /// @param  vault Address of the vault
    /// @param  receiver Check IERC7575.withdraw.receiver
    /// @param  controller Check IERC7575.withdraw.owner
    function claimRedeem(address vault, address receiver, address controller) external payable;

    /// @notice Check `IERC7540CancelRedeem.cancelRedeemRequest`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `VaultRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  vault The vault where the deposit was initiated
    function cancelRedeemRequest(address vault) external payable;

    /// @notice Check IERC7540CancelRedeem.claimableCancelRedeemRequest
    ///
    /// @param  vault Address of the vault
    /// @param  receiver Check  IERC7540CancelRedeem.claimCancelRedeemRequest.receiver
    /// @param  controller Check  IERC7540CancelRedeem.claimCancelRedeemRequest.controller
    function claimCancelRedeemRequest(address vault, address receiver, address controller) external payable;

    // --- Transfer ---
    /// @notice Check `IPoolManager.transferShares`.
    /// @dev    This adds a mandatory prepayment for all the costs that will incur during the transaction.
    ///         The caller must call `VaultRouter.estimate` to get estimates how much the deposit will cost.
    ///
    /// @param  centrifugeId Chain to where transfer the shares
    /// @param  vault The vault for the corresponding share class token
    /// @param  receiver Check `IPoolManager.transferShares.receiver`
    /// @param  amount Check `IPoolManager.transferShares.amount`
    function transferShares(uint16 centrifugeId, address vault, bytes32 receiver, uint128 amount) external payable;

    /// @notice This is a more friendly version where the receiver is and EVM address
    /// @dev    The receiver address is padded to 32 bytes internally
    function transferShares(uint16 centrifugeId, address vault, address receiver, uint128 amount) external payable;

    /// @notice Register an asset to be used in a pool existing in centrifugeId
    /// @param centrifugeId Where the asset will be registered
    /// @param asset If tokenId == 0, an ERC20 address, if tokenId != 0, an ERC6909 address
    /// @param tokenId An ERC6909 tokenId
    function registerAsset(uint16 centrifugeId, address asset, uint256 tokenId) external payable;

    // --- ERC20 permit ---
    /// @notice Check IERC20.permit
    function permit(address asset, address spender, uint256 assets, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        payable;

    // --- ERC20 wrapping ---
    /// @notice There are vault which underlying asset is actuall a wrapped one.
    ///
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the wrapped tokens
    /// @param  owner The address from which `amount` is taken from
    function wrap(address wrapper, uint256 amount, address receiver, address owner) external payable;

    /// @notice There are vault which underlying asset is actuall a wrapped one.
    /// @dev    Wrapped tokens need to be held by the VaultRouter to be unwrapped.
    /// @param  wrapper The address of the wrapper
    /// @param  amount  Amount to be wrapped
    /// @param  receiver Receiver of the unwrapped tokens
    function unwrap(address wrapper, uint256 amount, address receiver) external payable;

    // --- View Methods ---
    /// @notice Check IPoolManager.getVault
    function getVault(uint64 poolId, bytes16 scId, address asset) external view returns (address);

    /// @notice Check IMessageDispatcher.estimate
    ///         If the destination and source chain ID are the same, this will always return 0.
    /// @param centrifugeId destination chain
    function estimate(uint16 centrifugeId, bytes memory batch) external view returns (uint256 amount);

    /// @notice Called to check if `user` has permissions on `vault` to execute requests
    ///
    /// @param vault Address of the `vault` the `user` wants to operate on
    /// @param user Address of the `user` that will operates on the `vault`
    /// @return Whether `user` has permissions to operate on `vault`
    function hasPermissions(address vault, address user) external view returns (bool);

    /// @notice Returns whether the controller has called `enable()` for the given `vault`
    function isEnabled(address vault, address controller) external view returns (bool);
}
