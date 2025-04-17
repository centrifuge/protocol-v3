// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IPoolManager} from "src/vaults/interfaces/IPoolManager.sol";

interface IBaseInvestmentManager {
    // --- Events ---
    event File(bytes32 indexed what, address data);

    error FileUnrecognizedParam();
    error SenderNotVault();

    /// @notice Updates contract parameters of type address.
    /// @param what The bytes32 representation of 'gateway' or 'poolManager'.
    /// @param data The new contract address.
    function file(bytes32 what, address data) external;

    /// @notice Converts the assets value to share decimals.
    function convertToShares(address vaultAddr, uint256 _assets) external view returns (uint256 shares);

    /// @notice Converts the shares value to assets decimals.
    function convertToAssets(address vaultAddr, uint256 _shares) external view returns (uint256 assets);

    /// @notice Returns the timestamp of the last share price update for a vaultAddr.
    function priceLastUpdated(address vaultAddr) external view returns (uint64 lastUpdated);

    /// @notice Returns the PoolManager contract address.
    function poolManager() external view returns (IPoolManager poolManager);

    /// @notice Returns the escrow contract address for the corresponding vault
    ///
    /// @dev NOTE: MUST only be called from vaults in order to derive the pool id.
    /// @dev This naming MUST NOT change due to requirements of legacy vaults (v2)
    ///
    /// @return escrow The address of the escrow contract for this vault
    function escrow() external view returns (address escrow);

    /// @notice Wrapper call for pool ids necessary due to legacy v2 vaults with pre-existing pool ids.
    function mapPoolId(uint64 poolId) external pure returns (uint64 mappedPoolId);
}
