// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {BeforeAfter, OpType} from "./BeforeAfter.sol";

import {console2} from "forge-std/console2.sol";

abstract contract Properties is BeforeAfter, Asserts {

    // Other stuff
    // epochAmounts_.depositApproved can only increase


    // Sum of requests
    // TODO: Come back to this
    // function property_sum_of_requests() public {
    //     /// Pending deposit - Approved Asset Amount
    //     /// epochAmounts_.depositApproved = approvedAssetAmount;
    //     // NOTE: I'm using same values for all
    //     // pendingDeposit -= approvedAssetAmount


    //     // TODO: Grab `epochAmounts_.depositApproved` for each epoch to determine the amount processed
    //     // This should be equal to `totalApprovedDeposits`

    //     // TODO: SCM Queuein needs to be tested differently


    //     uint256 pendingDeposit = shareClassManager.pendingDeposit(scId, depositAssetId);
    //     (uint128 pending, uint32 lastUpdate) = shareClassManager.depositRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));

    //     (bool isCancelling, uint128 queued) = shareClassManager.queuedDepositRequest(scId, depositAssetId, bytes32(uint256(uint160(_getActor()))));

    //     eq(totalApprovedDeposits + pendingDeposit, pending, "property_sum_of_requests");
    // }

    

    // Sum of pending

    // Sum of received?



    // Current NAV (To compute values)
    // Change NAV (To compute deltas)

    // TODO: Holdings??
}