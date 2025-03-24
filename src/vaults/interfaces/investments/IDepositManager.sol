// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

interface IDepositManager {
    /// @notice Processes owner's asset deposit after the epoch has been executed on Centrifuge and the deposit order
    ///         has been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver. Amount of shares is computed based of the amount
    ///         of assets and the owner's share price.
    /// @dev    The assets required to fulfill the deposit are already locked in escrow upon calling requestDeposit.
    ///         The shares required to fulfill the deposit have already been minted and transferred to the escrow on
    ///         fulfillDepositRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function deposit(address vaultAddr, uint256 assets, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice Processes owner's share mint after the epoch has been executed on Centrifuge and the deposit order has
    ///         been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver. Amount of assets is computed based of the amount
    ///         of shares and the owner's share price.
    /// @dev    The assets required to fulfill the mint are already locked in escrow upon calling requestDeposit.
    ///         The shares required to fulfill the mint have already been minted and transferred to the escrow on
    ///         fulfillDepositRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function mint(address vaultAddr, uint256 shares, address receiver, address owner)
        external
        returns (uint256 assets);

    /// @notice Returns the max amount of assets based on the unclaimed amount of shares after at least one successful
    ///         deposit order fulfillment on Centrifuge.
    function maxDeposit(address vaultAddr, address user) external view returns (uint256);

    /// @notice Returns the max amount of shares a user can claim after at least one successful deposit order
    ///         fulfillment on Centrifuge.
    function maxMint(address vaultAddr, address user) external view returns (uint256 shares);
}
