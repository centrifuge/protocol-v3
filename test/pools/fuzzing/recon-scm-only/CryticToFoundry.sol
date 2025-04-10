// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {Test, console2} from "forge-std/Test.sol";

import {PoolId, raw, newPoolId} from "src/common/types/PoolId.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId, newAssetId} from "src/common/types/AssetId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";
import {JournalEntry} from "src/common/libraries/JournalEntryLib.sol";
import {AccountId} from "src/common/types/AccountId.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {Helpers} from "test/pools/fuzzing/recon-pools/utils/Helpers.sol";

// forge test --match-contract CryticToFoundry --match-path test/pools/fuzzing/recon-scm-only/CryticToFoundry.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    
    function setUp() public {
        setup();
    }


    
    function test_request_deposit() public {
      
    }
}