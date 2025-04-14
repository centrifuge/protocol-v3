// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {FoundryAsserts} from "@chimera/FoundryAsserts.sol";

import {Test, console2} from "forge-std/Test.sol";

import {TargetFunctions} from "./TargetFunctions.sol";
import {Helpers} from "test/pools/fuzzing/recon-pools/utils/Helpers.sol";

import {AssetId} from "src/common/types/AssetId.sol";
import {D18} from "src/misc/types/D18.sol";

// forge test --match-contract SimpleToFoundry --match-path test/pools/fuzzing/recon-scm-only/SimpleToFoundry.sol -vv
contract SimpleToFoundry is Test, TargetFunctions, FoundryAsserts {
    
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

 // forge test --match-test test_property_total_yield_0 -vvv 
function test_property_total_yield_0() public {

    shareClassManager_requestDeposit(38798458659217211618845882225298602406);

    setMultiplier(439);

    approveDeposits(38792186940037273484818655409910407055);

    setMultiplier(1);

    updateHolding();

    setMultiplier(0);

    updateHolding();

    _logALot();

    property_total_yield();

 }



 function _logValueAndDepositValue() internal {
    (, uint128 value) = _getAmountAndValue();
    console2.log("Holding Value", value);
    console2.log("depositValue", depositValue);
 }



 function _logALot() internal {
    _logRequests();
    _logAccounts();
    _logCounters();

    (uint128 totalDebit, uint128 totalCredit, , , ) = accounting.accounts(poolId, LOSS_ACCOUNT);
    console2.log("totalDebit", totalDebit);
    console2.log("totalCredit", totalCredit);


    console2.log("lossValue", lossValue);
    console2.log("int256(accounting.accountValue(poolId, LOSS_ACCOUNT))", int256(accounting.accountValue(poolId, LOSS_ACCOUNT)));
 }

    uint256 count;

    function _logCounters() internal {
      console2.log("depositAmt", depositAmt)  ;
      console2.log("depositValue", depositValue);
      console2.log("yieldValue", yieldValue);
      console2.log("lossValue", lossValue);
    }
    function _logRequests() internal {
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

    function _logAccounts() public {
      console2.log("accounting.accountValue(poolId, LOSS_ACCOUNT)", accounting.accountValue(poolId, LOSS_ACCOUNT));
      console2.log("accounting.accountValue(poolId, GAIN_ACCOUNT)", accounting.accountValue(poolId, GAIN_ACCOUNT));
      console2.log("accounting.accountValue(poolId, ASSET_ACCOUNT)", accounting.accountValue(poolId, ASSET_ACCOUNT));
      console2.log("accounting.accountValue(poolId, EQUITY_ACCOUNT)", accounting.accountValue(poolId, EQUITY_ACCOUNT));
    }


}