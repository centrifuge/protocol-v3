// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Targets
// NOTE: Always import and apply them in alphabetical order, so much easier to debug!
import { PoolManagerTargets } from "./targets/PoolManagerTargets.sol";
import { PoolRouterTargets } from "./targets/PoolRouterTargets.sol";
import { AdminTargets } from "./targets/AdminTargets.sol";
import { ManagerTargets } from "./targets/ManagerTargets.sol";

abstract contract TargetFunctions is
    PoolManagerTargets,
    PoolRouterTargets, 
    AdminTargets,
    ManagerTargets
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
