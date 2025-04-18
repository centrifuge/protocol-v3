// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IBaseInvestmentManager {
    // --- Events ---
    event File(bytes32 indexed what, address data);

    error FileUnrecognizedParam();

    /// @notice Address of the escrow
    function escrow() external view returns (address);

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
}
