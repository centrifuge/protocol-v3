// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {BeforeAfter, OpType} from "./BeforeAfter.sol";

import {console2} from "forge-std/console2.sol";

abstract contract Properties is BeforeAfter, Asserts {
    // Sum of requests

    // Sum of pending

    // Sum of received?



    // Current NAV (To compute values)
    // Change NAV (To compute deltas)

    // TODO: Holdings??
}