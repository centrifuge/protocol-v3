// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Source
import {AssetId, newAssetId} from "src/pools/types/AssetId.sol";
import "src/pools/PoolManager.sol";

import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";

abstract contract PoolManagerTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///

    // === PoolManager === //
    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    function poolManager_createPool(address admin, uint32 isoCode, IShareClassManager shareClassManager) public asActor returns (PoolId poolId) {
        AssetId assetId_ = newAssetId(isoCode); 
        
        poolId = poolManager.createPool(admin, assetId_, shareClassManager);

        return poolId;
    }

    function poolManager_claimDeposit(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) public asActor {
        poolManager.claimDeposit(poolId, scId, assetId, investor);
    }

    function poolManager_claimRedeem(PoolId poolId, ShareClassId scId, AssetId assetId, bytes32 investor) public asActor {
        poolManager.claimRedeem(poolId, scId, assetId, investor);
    }

}