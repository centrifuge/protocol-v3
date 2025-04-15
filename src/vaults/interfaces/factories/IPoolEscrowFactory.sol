// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IPoolEscrowProvider {
    /// @notice Returns the deterministic address of an escrow contract based on a given pool id
    /// @dev Does not check, whether the escrow was already deployed.
    function escrow(uint64 poolId) external view returns (address);

    /// @notice Returns the address of the corresponding deployed escrow contract if it exists
    function escrows(uint64 poolId) external view returns (address);
}

interface IPoolEscrowFactory is IPoolEscrowProvider {
    event DeployPoolEscrow(uint64 indexed poolId, address indexed escrow);
    event File(bytes32 what, address data);

    error FileUnrecognizedParam();
    error EscrowAlreadyDeployed();

    /// @notice Deploys new escrow.
    /// @dev All share classes of a pool are represented by the same escrow contract.
    ///
    /// @param poolId Id of the pool this escrow is deployed for
    function newEscrow(uint64 poolId) external returns (address);

    /// @notice Updates contract parameters of type address.
    function file(bytes32 what, address data) external;
}
