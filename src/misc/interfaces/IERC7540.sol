// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

interface IERC7540Operator {
    /**
     * @dev The event emitted when an operator is set.
     *
     * @param controller The address of the controller.
     * @param operator The address of the operator.
     * @param approved The approval status.
     */
    event OperatorSet(address indexed controller, address indexed operator, bool approved);

    /**
     * @dev Sets or removes an operator for the caller.
     *
     * @param operator The address of the operator.
     * @param approved The approval status.
     * @return Whether the call was executed successfully or not
     */
    function setOperator(address operator, bool approved) external returns (bool);

    /**
     * @dev Returns `true` if the `operator` is approved as an operator for an `controller`.
     *
     * @param controller The address of the controller.
     * @param operator The address of the operator.
     * @return status The approval status
     */
    function isOperator(address controller, address operator) external view returns (bool status);
}

interface IERC7540Deposit is IERC7540Operator {
    event DepositRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 assets
    );
    /**
     * @dev Transfers assets from sender into the Vault and submits a Request for asynchronous deposit.
     *
     * - MUST support ERC-20 approve / transferFrom on asset as a deposit Request flow.
     * - MUST revert if all of assets cannot be requested for deposit.
     * - owner MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from owner to sender is NOT enough.
     *
     * @param assets the amount of deposit assets to transfer from owner
     * @param controller the controller of the request who will be able to operate the request
     * @param owner the source of the deposit assets
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's underlying asset token.
     */

    function requestDeposit(uint256 assets, address controller, address owner) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested assets in Pending state.
     *
     * - MUST NOT include any assets in Claimable state for deposit or mint.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingAssets);

    /**
     * @dev Returns the amount of requested assets in Claimable state for the controller to deposit or mint.
     *
     * - MUST NOT include any assets in Pending state.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableAssets);

    /**
     * @dev Mints shares Vault shares to receiver by claiming the Request of the controller.
     *
     * - MUST emit the Deposit event.
     * - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
     */
    function deposit(uint256 assets, address receiver, address controller) external returns (uint256 shares);

    /**
     * @dev Mints exactly shares Vault shares to receiver by claiming the Request of the controller.
     *
     * - MUST emit the Deposit event.
     * - controller MUST equal msg.sender unless the controller has approved the msg.sender as an operator.
     */
    function mint(uint256 shares, address receiver, address controller) external returns (uint256 assets);
}

interface IERC7540Redeem is IERC7540Operator {
    event RedeemRequest(
        address indexed controller, address indexed owner, uint256 indexed requestId, address sender, uint256 shares
    );

    /**
     * @dev Assumes control of shares from sender into the Vault and submits a Request for asynchronous redeem.
     *
     * - MUST support a redeem Request flow where the control of shares is taken from sender directly
     *   where msg.sender has ERC-20 approval over the shares of owner.
     * - MUST revert if all of shares cannot be requested for redeem.
     *
     * @param shares the amount of shares to be redeemed to transfer from owner
     * @param controller the controller of the request who will be able to operate the request
     * @param owner the source of the shares to be redeemed
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault's share token.
     */
    function requestRedeem(uint256 shares, address controller, address owner) external returns (uint256 requestId);

    /**
     * @dev Returns the amount of requested shares in Pending state.
     *
     * - MUST NOT include any shares in Claimable state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function pendingRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 pendingShares);

    /**
     * @dev Returns the amount of requested shares in Claimable state for the controller to redeem or withdraw.
     *
     * - MUST NOT include any shares in Pending state for redeem or withdraw.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT revert unless due to integer overflow caused by an unreasonably large input.
     */
    function claimableRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);
}

interface IERC7887Deposit {
    event CancelDepositRequest(address indexed controller, uint256 indexed requestId, address sender);
    event CancelDepositClaim(
        address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 assets
    );

    /**
     * @dev Submits a Request for cancelling the pending deposit Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelDepositRequest to `true` for the returned requestId after request
     * - MUST increase claimableCancelDepositRequest for the returned requestId after fulfillment
     * - SHOULD be claimable using `claimCancelDepositRequest`
     * Note: while `pendingCancelDepositRequest` is `true`, `requestDeposit` cannot be called
     */
    function cancelDepositRequest(uint256 requestId, address controller) external;

    /**
     * @dev Returns whether the deposit Request is pending cancellation
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function pendingCancelDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (bool isPending);

    /**
     * @dev Returns the amount of assets that were canceled from a deposit Request, and can now be claimed.
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function claimableCancelDepositRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableAssets);

    /**
     * @dev Claims the canceled deposit assets, and removes the pending cancellation Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelDepositRequest to `false` for the returned requestId after request
     * - MUST set claimableCancelDepositRequest to 0 for the returned requestId after fulfillment
     */
    function claimCancelDepositRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 assets);
}

interface IERC7887Redeem {
    event CancelRedeemRequest(address indexed controller, uint256 indexed requestId, address sender);
    event CancelRedeemClaim(
        address indexed controller, address indexed receiver, uint256 indexed requestId, address sender, uint256 shares
    );

    /**
     * @dev Submits a Request for cancelling the pending redeem Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelRedeemRequest to `true` for the returned requestId after request
     * - MUST increase claimableCancelRedeemRequest for the returned requestId after fulfillment
     * - SHOULD be claimable using `claimCancelRedeemRequest`
     * Note: while `pendingCancelRedeemRequest` is `true`, `requestRedeem` cannot be called
     */
    function cancelRedeemRequest(uint256 requestId, address controller) external;

    /**
     * @dev Returns whether the redeem Request is pending cancellation
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function pendingCancelRedeemRequest(uint256 requestId, address controller) external view returns (bool isPending);

    /**
     * @dev Returns the amount of shares that were canceled from a redeem Request, and can now be claimed.
     *
     * - MUST NOT show any variations depending on the caller.
     */
    function claimableCancelRedeemRequest(uint256 requestId, address controller)
        external
        view
        returns (uint256 claimableShares);

    /**
     * @dev Claims the canceled redeem shares, and removes the pending cancellation Request
     *
     * - controller MUST be msg.sender unless some unspecified explicit approval is given by the caller,
     *    approval of ERC-20 tokens from controller to sender is NOT enough.
     * - MUST set pendingCancelRedeemRequest to `false` for the returned requestId after request
     * - MUST set claimableCancelRedeemRequest to 0 for the returned requestId after fulfillment
     */
    function claimCancelRedeemRequest(uint256 requestId, address receiver, address controller)
        external
        returns (uint256 shares);
}

interface IERC7741 {
    /**
     * @dev Grants or revokes permissions for `operator` to manage Requests on behalf of the
     *      `msg.sender`, using an [EIP-712](./eip-712.md) signature.
     */
    function authorizeOperator(
        address controller,
        address operator,
        bool approved,
        bytes32 nonce,
        uint256 deadline,
        bytes memory signature
    ) external returns (bool);

    /**
     * @dev Revokes the given `nonce` for `msg.sender` as the `owner`.
     */
    function invalidateNonce(bytes32 nonce) external;

    /**
     * @dev Returns whether the given `nonce` has been used for the `controller`.
     */
    function authorizations(address controller, bytes32 nonce) external view returns (bool used);

    /**
     * @dev Returns the `DOMAIN_SEPARATOR` as defined according to EIP-712. The `DOMAIN_SEPARATOR
     *      should be unique to the contract and chain to prevent replay attacks from other domains,
     *      and satisfy the requirements of EIP-712, but is otherwise unconstrained.
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

interface IERC7714 {
    /**
     * @dev Returns `true` if the `user` is permissioned to interact with the contract.
     */
    function isPermissioned(address controller) external view returns (bool);
}
