// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {Test, console2} from "forge-std/Test.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {Helpers} from "test/pools/fuzzing/recon-pools/utils/Helpers.sol";

import {AssetId} from "src/common/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";

// forge test --match-contract CryticToFoundry --match-path test/pools/fuzzing/recon-scm-only/CryticToFoundry.sol -vv
contract CryticToFoundry is Test, TargetFunctions, FoundryAsserts {
    
    function setUp() public {
        setup();
    }

    function test_basic() public {
      shareClassManager_requestDeposit(123);
    //   _switchActor(1);
      shareClassManager_requestDeposit(123);
    //   shareClassManager_approveDeposits(123);
      _logRequests();

    //   _switchActor(0);
    //   shareClassManager_cancelDepositRequest();
    //   _logRequests();
      // They cannot queue again since they requested cancelling
    //   shareClassManager_requestDeposit(123);
    //   _logRequests();
    }

    function test_basics() public {
      shareClassManager_requestDeposit(100);
      approveDeposits(100);
      setMultiplier(101);
      updateHolding();
    }

    // forge test --match-test test_property_trackingOfValues_0 -vvv 
function test_property_trackingOfValues_0() public {

    shareClassManager_requestDeposit(100);

    approveDeposits(100);

    _logValueAndDepositValue();

    setMultiplier(1);

    updateHolding(); /// @audit Rounding up somewhere?

    _logValueAndDepositValue();

    property_trackingOfValues();

 }

 // forge test --match-test test_property_sound_loss_0 -vvv 
function test_property_sound_loss_0() public {

    shareClassManager_requestDeposit(38985021616332776005721838188067962871);

    setMultiplier(440);

    approveDeposits(38792186940037273484818655409910407055);

    setMultiplier(2);

    updateHolding();

    setMultiplier(0);

    console2.log("lossValue", lossValue);

    updateHolding();

    console2.log("lossValue", lossValue);

    property_sound_loss();

 }

 // forge test --match-test test_property_sum_of_losses_1 -vvv 
function test_property_sum_of_losses_1() public {

    shareClassManager_requestDeposit(43764355266177282889117198556747624317);

    setMultiplier(391);

    approveDeposits(43899286528186883990784102317729252210);

    setMultiplier(3);

    updateHolding();

    setMultiplier(0);

    updateHolding();

    property_sum_of_losses();

 }

 function _logValueAndDepositValue() internal {
    (, uint128 value) = _getAmountAndValue();
    console2.log("Holding Value", value);
    console2.log("depositValue", depositValue);
 }

// forge test --match-test test_property_sum_of_losses_0 -vvv 
function test_property_sum_of_losses_0() public {

    shareClassManager_requestDeposit(101);

    setMultiplier(1);

    approveDeposits(102);

    setMultiplier(0);

    updateHolding();

    console2.log("lossValue", lossValue);
    console2.log("int256(accounting.accountValue(poolId, LOSS_ACCOUNT))", int256(accounting.accountValue(poolId, LOSS_ACCOUNT)));
    property_sum_of_losses();

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