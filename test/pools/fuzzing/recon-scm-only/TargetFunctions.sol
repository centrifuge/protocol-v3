// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";
import {console2} from "forge-std/console2.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Source
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "./Properties.sol";


abstract contract TargetFunctions is
    BaseTargetFunctions,
    Properties
{

    function theCall() public {
        
    }

    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
