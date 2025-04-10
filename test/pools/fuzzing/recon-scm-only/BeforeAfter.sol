// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {PoolId} from "src/common/types/PoolId.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {EpochPointers, UserOrder} from "src/hub/interfaces/IShareClassManager.sol";
import {Helpers} from "test/pools/fuzzing/recon-pools/utils/Helpers.sol";
import {AccountId} from "src/hub/interfaces/IAccounting.sol";
import {IAccounting} from "src/hub/interfaces/IAccounting.sol";
import {Setup} from "./Setup.sol";

enum OpType {
    GENERIC,
    DEPOSIT,
    REDEEM,
    BATCH // batch operations that make multiple calls in one transaction
}

// ghost variables for tracking state variable values before and after function calls
abstract contract BeforeAfter is Setup {
    struct Vars {
        uint256 ignore;
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
        
    }

    function __after() internal {
        
    }
}