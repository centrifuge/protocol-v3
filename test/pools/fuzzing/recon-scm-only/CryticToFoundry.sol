// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {Test, console2} from "forge-std/Test.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {Helpers} from "test/pools/fuzzing/recon-pools/utils/Helpers.sol";

import {AssetId} from "src/common/types/AssetId.sol";


// forge test --match-contract CryticToFoundry --match-path test/pools/fuzzing/recon-scm-only/CryticToFoundry.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    
    function setUp() public {
        setup();
    }


    
    function test_basic() public {
      shareClassManager_requestDeposit(123);
      _switchActor(1);
      shareClassManager_requestDeposit(123);
      shareClassManager_approveDeposits(123);
      _logRequests();

      _switchActor(0);
      shareClassManager_cancelDepositRequest();
      _logRequests();
      // They cannot queue again since they requested cancelling
    //   shareClassManager_requestDeposit(123);
    //   _logRequests();
    }

    uint256 count;
    function _logRequests() public {
        console2.log("");
        console2.log("");
        console2.log("_logRequests", count++);

        {
            (uint128 depositRequest, uint32 lastUpdate) = shareClassManager.depositRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));
            console2.log("depositRequest", depositRequest);
        }

        {
            (uint128 redeemRequest, uint32 lastUpdateRedeem) = shareClassManager.redeemRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));        
            console2.log("redeemRequest", redeemRequest);
        }

        {
            (bool isCancelling, uint128 queuedDepositRequest) = shareClassManager.queuedDepositRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));
            console2.log("queuedDepositRequest", queuedDepositRequest);
        }

        {
            (bool isCancelling, uint128 queuedRedeemRequest) = shareClassManager.queuedRedeemRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));
            console2.log("queuedRedeemRequest", queuedRedeemRequest);
        }
    }
}