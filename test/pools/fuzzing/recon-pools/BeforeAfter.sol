// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {PoolId} from "src/pools/types/PoolId.sol";
import {Setup} from "./Setup.sol";

enum OpType {
    GENERIC,
    DEPOSIT
}

// ghost variables for tracking state variable values before and after function calls
abstract contract BeforeAfter is Setup {
    struct Vars {
        PoolId ghostUnlockedPoolId;
        uint128 ghostDebited;
        uint128 ghostCredited;
    }

    Vars internal _before;
    Vars internal _after;
    OpType internal currentOperation;

    modifier updateGhosts() {
        currentOperation = OpType.GENERIC;
        __before();
        _;
        __after();
    }

    modifier updateGhostsWithType(OpType op) {
        currentOperation = op;
        __before();
        _;
        __after();
    }

    function __before() internal {
        _before.ghostUnlockedPoolId = poolRouter.unlockedPoolId();
        _before.ghostDebited = accounting.debited();
        _before.ghostCredited = accounting.credited();
    }

    function __after() internal {
        _after.ghostUnlockedPoolId = poolRouter.unlockedPoolId();
        _after.ghostDebited = accounting.debited();
        _after.ghostCredited = accounting.credited();
    }
}