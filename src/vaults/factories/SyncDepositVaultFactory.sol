// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";

import {SyncDepositVault} from "src/vaults/SyncDepositVault.sol";
import {IVaultFactory} from "src/vaults/interfaces/factories/IVaultFactory.sol";

/// @title  Sync Vault Factory
/// @dev    Utility for deploying new vault contracts
contract SyncDepositVaultFactory is Auth, IVaultFactory {
    address public immutable root;
    address public immutable syncRequests;
    address public immutable asyncRequests;

    constructor(address root_, address syncRequests_, address asyncRequests_, address deployer) Auth(deployer) {
        root = root_;
        syncRequests = syncRequests_;
        asyncRequests = asyncRequests_;
    }

    /// @inheritdoc IVaultFactory
    function newVault(
        uint64 poolId,
        bytes16 scId,
        address asset,
        uint256 tokenId,
        address token,
        address, /* escrow */
        address[] calldata wards_
    ) public auth returns (address) {
        SyncDepositVault vault =
            new SyncDepositVault(poolId, scId, asset, tokenId, token, root, syncRequests, asyncRequests);

        vault.rely(root);
        vault.rely(syncRequests);

        uint256 wardsCount = wards_.length;
        for (uint256 i; i < wardsCount; i++) {
            vault.rely(wards_[i]);
        }

        vault.deny(address(this));
        return address(vault);
    }
}
