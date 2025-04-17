// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

/// @title  Escrow for holding assets
interface IEscrow {
    // --- Events ---
    /// @notice Emitted when an approval is made
    /// @param asset The address of the asset
    /// @param spender The address of the spender
    /// @param value The new total allowance
    event Approve(address indexed asset, address indexed spender, uint256 value);

    /// @notice Emitted when an approval is made
    /// @param asset The address of the asset
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param spender The address of the spender
    /// @param value The new total allowance
    event Approve(address indexed asset, uint256 indexed tokenId, address indexed spender, uint256 value);

    // --- Token approvals ---
    /// @notice sets the allowance of `spender` to `type(uint256).max` if it is currently 0
    function approveMax(address asset, uint256 tokenId, address spender) external;

    /// @notice sets the allowance of `spender` to `type(uint256).max` if it is currently 0
    function approveMax(address asset, address spender) external;

    /// @notice sets the allowance of `spender` to 0
    function unapprove(address asset, uint256 tokenId, address spender) external;

    /// @notice sets the allowance of `spender` to 0
    function unapprove(address asset, address spender) external;
}

/// @title PerPoolEscrow separating funds by pool and share class
interface IPoolEscrow is IEscrow {
    // --- Events ---
    /// @notice Emitted when a deposit will be made in the future
    /// @param asset The address of the to be deposited asset
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param poolId The id of the pool
    /// @param scId The id of the share class
    /// @param value The amount to be deposited
    event PendingDeposit(
        address indexed asset, uint256 indexed tokenId, uint64 indexed poolId, bytes16 scId, uint256 value
    );

    /// @notice Emitted when a deposit is made
    /// @param asset The address of the deposited asset
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param poolId The id of the pool
    /// @param scId The id of the share class
    /// @param value The amount deposited
    event Deposit(address indexed asset, uint256 indexed tokenId, uint64 indexed poolId, bytes16 scId, uint256 value);

    /// @notice Emitted when an amount is reserved
    /// @param asset The address of the reserved asset
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param poolId The id of the pool
    /// @param scId The id of the share class
    /// @param value The amount reserved
    event Reserve(address indexed asset, uint256 indexed tokenId, uint64 indexed poolId, bytes16 scId, uint256 value);

    /// @notice Emitted when a withdraw is made
    /// @param asset The address of the withdrawn asset
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param poolId The id of the pool
    /// @param scId The id of the share class
    /// @param value The amount withdrawn
    event Withdraw(address indexed asset, uint256 indexed tokenId, uint64 indexed poolId, bytes16 scId, uint256 value);

    // --- Errors ---
    /// @notice Dispatched when pending deposits are insufficient
    error InsufficientPendingDeposit();

    /// @notice Dispatched when the balance of the escrow did not increase sufficiently
    error InsufficientDeposit();

    /// @notice Dispatched when the the outstanding reserved amount is insufficient for the decrease
    error InsufficientReservedAmount();

    /// @notice Dispatched when the balance of the escrow is insufficient for the withdrawal
    error InsufficientBalance();

    // --- Functions ---
    /// @notice Increases the pending deposit of `value` for `asset` in underlying `poolId` and given `scId`
    /// @dev MUST be made prior to calling `deposit`
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be deposited
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to increase
    function pendingDepositIncrease(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Decreases the pending deposit of `value` for `asset` in underlying `poolId` and given `scId`
    /// @dev MUST fail if `value` is greater than the current pending deposit
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be deposited
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to decrease
    function pendingDepositDecrease(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Deposits `value` of `asset` in underlying `poolId` and given `scId`
    /// @dev MUST be made after calling `pendingDepositIncrease`. Fails if `value` is greater than the current pending
    /// deposit
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be deposited
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to deposit
    function deposit(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Increases the reserved amount of `value` for `asset` in underlying `poolId` and given `scId`
    /// @dev MUST prevent the reserved amount from being withdrawn
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be reserved
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to reserve
    function reserveIncrease(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Decreases the reserved amount of `value` for `asset` in underlying `poolId` and given `scId`
    /// @dev MUST fail if `value` is greater than the current reserved amount
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be reserved
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to decrease
    function reserveDecrease(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Withdraws `value` of `asset` in underlying `poolId` and given `scId`
    /// @dev MUST ensure that reserved amounts are not withdrawn
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be withdrawn
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @param value The amount to withdraw
    function withdraw(bytes16 scId, address asset, uint256 tokenId, uint256 value) external;

    /// @notice Provides the available balance of `asset` in underlying `poolId` and given `scId`
    /// @dev MUST return the balance minus the reserved amount
    /// @param scId The id of the share class
    /// @param asset The address of the asset to be checked
    /// @param tokenId The id of the asset - 0 for ERC20
    /// @return The available balance
    function availableBalanceOf(bytes16 scId, address asset, uint256 tokenId) external view returns (uint256);
}
