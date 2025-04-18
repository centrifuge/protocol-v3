// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IRestrictedTransfers {
    // --- Events ---
    event UpdateMember(address indexed token, address indexed user, uint64 validUntil);
    event Freeze(address indexed token, address indexed user);
    event Unfreeze(address indexed token, address indexed user);

    // --- Errors ---
    error InvalidValidUntil();
    error CannotFreezeZeroAddress();
    error EndorsedUserCannotBeFrozen();
    error EndorsedUserCannotBeUpdated();

    // --- Handling freezes ---
    /// @notice Freeze a user balance. Frozen users cannot receive nor send tokens
    function freeze(address token, address user) external;

    /// @notice Unfreeze a user balance
    function unfreeze(address token, address user) external;

    /// @notice Returns whether the user's tokens are frozen
    function isFrozen(address token, address user) external view returns (bool);

    // --- Managing members ---
    /// @notice Add a member. Non-members cannot receive tokens, but can send tokens to valid members
    /// @param  validUntil Timestamp until which the user will be a valid member
    function updateMember(address token, address user, uint64 validUntil) external;

    /// @notice Returns whether the user is a valid member of the token
    function isMember(address token, address user) external view returns (bool isValid, uint64 validUntil);
}
