// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";

import {SyncDepositVault} from "src/vaults/SyncDepositVault.sol";
import {IVaultFactory} from "src/vaults/interfaces/factories/IVaultFactory.sol";

/// @title  Sync Vault Factory
/// @dev    Utility for deploying new vault contracts
contract SyncVaultFactory is Auth, IVaultFactory {
    address public immutable root;
    address public immutable investmentManager;

    constructor(address _root, address investmentManager_) Auth(msg.sender) {
        root = _root;
        investmentManager = investmentManager_;
    }

    /// @inheritdoc IVaultFactory
    function newVault(
        uint64 poolId,
        bytes16 trancheId,
        address asset,
        uint256 tokenId,
        address tranche,
        address, /* escrow */
        address[] calldata wards_
    ) public auth returns (address) {
        SyncDepositVault vault =
            new SyncDepositVault(poolId, trancheId, asset, tokenId, tranche, root, investmentManager);

        vault.rely(root);
        vault.rely(investmentManager);

        uint256 wardsCount = wards_.length;
        for (uint256 i; i < wardsCount; i++) {
            vault.rely(wards_[i]);
        }

        vault.deny(address(this));
        return address(vault);
    }
}
