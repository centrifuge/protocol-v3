// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

/// @notice Allows to call several calls in the same transactions
interface IMulticall {
    /// @notice Dispatched when the `targets` and `datas` length parameters in `execute()` do not matched.
    error WrongExecutionParams();

    /// @notice Execute a generic multicall.
    /// If one call fails, it reverts the whole transaction.
    function aggregate(address[] calldata targets, bytes[] calldata datas) external returns (bytes[] memory results);
}
