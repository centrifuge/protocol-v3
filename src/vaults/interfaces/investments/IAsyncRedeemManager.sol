// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IRedeemManager} from "src/vaults/interfaces/investments/IRedeemManager.sol";
import {IVaultManager} from "src/vaults/interfaces/IVaultManager.sol";

/// @dev Vault requests and deposit/redeem bookkeeping per user
struct AsyncRedeemState {
    /// @dev Assets that can be claimed using `withdraw()`
    uint128 maxWithdraw;
    /// @dev Weighted average price of redemptions, used to convert maxWithdraw to maxRedeem
    uint256 redeemPrice;
    /// @dev Remaining redeem request in shares
    uint128 pendingRedeemRequest;
    /// @dev Shares that can be claimed using `claimCancelRedeemRequest()`
    uint128 claimableCancelRedeemRequest;
    /// @dev Indicates whether the redeemRequest was requested to be cancelled
    bool pendingCancelRedeemRequest;
}

interface IAsyncRedeemManager is IRedeemManager, IVaultManager {
    /// @notice Requests share redemption. Vaults have to request redemptions
    ///         from Centrifuge before actual asset payouts can be done. The redemption
    ///         requests are added to the order book on the corresponding CP instance. Once the next epoch is
    ///         executed on the corresponding CP instance, vaults can proceed with asset payouts
    ///         in case the order got fulfilled.
    /// @dev    The shares required to fulfill the redemption request have to be locked and are transferred from the
    ///         owner to the escrow, even though the asset payout can only happen after epoch execution.
    ///         The receiver becomes the owner of redeem request fulfillment.
    function requestRedeem(address vaultAddr, uint256 shares, address receiver, address, /* owner */ address source)
        external
        returns (bool);

    /// @notice Requests the cancellation of an pending redeem request. Vaults have to request the
    ///         cancellation of outstanding requests from Centrifuge before actual shares can be unlocked and
    ///         transferred to the owner.
    ///         While users have outstanding cancellation requests no new redeem requests can be submitted (exception:
    ///         trigger through governance).
    ///         Once the next epoch is executed on the corresponding CP instance, vaults can proceed with share payouts
    ///         if the orders could be cancelled successfully.
    /// @dev    The cancellation request might fail in case the pending redeem order already got fulfilled on
    ///         Centrifuge.
    function cancelRedeemRequest(address vaultAddr, address owner, address source) external;

    /// @notice Processes owner's redeem request cancellation after the epoch has been executed on the corresponding CP
    /// instance and the
    ///         redeem order cancellation has been successfully processed (partial fulfillment possible).
    ///         Shares are transferred from the escrow to the receiver.
    /// @dev    The shares required to fulfill the claim have already been reserved for the owner in escrow on
    ///         fulfillCancelRedeemRequest.
    ///         Receiver has to pass all the share token restrictions in order to receive the shares.
    function claimCancelRedeemRequest(address vaultAddr, address receiver, address owner)
        external
        returns (uint256 shares);

    /// @notice Indicates whether a user has pending redeem requests and returns the total share request value.
    function pendingRedeemRequest(address vaultAddr, address user) external view returns (uint256 shares);

    /// @notice Indicates whether a user has pending redeem request cancellations.
    function pendingCancelRedeemRequest(address vaultAddr, address user) external view returns (bool isPending);

    /// @notice Indicates whether a user has claimable redeem request cancellation and returns the total claim
    ///         value in shares.
    function claimableCancelRedeemRequest(address vaultAddr, address user) external view returns (uint256 shares);
}
