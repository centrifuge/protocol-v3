// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {PoolId} from "src/common/types/PoolId.sol";

interface IGasService {
    event File(bytes32 indexed what, uint64 value);

    error FileUnrecognizedParam();

    /// @notice Using file patter to update state variables;
    /// @dev    Used to update the messageGasLimit and proofGasLimit;
    ///         It is used in occasions where update is done rarely.
    function file(bytes32 what, uint64 value) external;

    /// @notice The cost of 'message' execution on the recipient chain.
    /// @dev    This is a getter method
    /// @return Amount in gas
    function messageGasLimit() external returns (uint64);

    /// @notice The cost of 'proof' execution on the recipient chain.
    /// @dev    This is a getter method
    /// @return Amount in gas
    function proofGasLimit() external returns (uint64);

    /// @notice Estimate the total execution cost on the remote chain in ETH.
    /// @dev    Currently payload is disregarded and not included in the calculation.
    /// @param  payload Estimates the execution cost based on the payload
    /// @return Estimated cost in WEI units
    function estimate(uint16 chainId, bytes calldata payload) external view returns (uint256);
}
