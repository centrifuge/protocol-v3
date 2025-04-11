// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {Asserts} from "@chimera/Asserts.sol";
import {BeforeAfter, OpType} from "./BeforeAfter.sol";

import {console2} from "forge-std/console2.sol";


import {Holding} from "src/hub/interfaces/IHoldings.sol";



abstract contract Properties is BeforeAfter, Asserts {

    // Holdings property should be the following:
    // Sum of Deposit - Sum of withdrawals = 
    // Sum of ASSETS
    function property_trackingOfAmounts() public {
        (uint128 amt, ) = _getAmountAndValue();
        eq(amt, depositAmt, "property_trackingOfAmounts");
    }
    function property_trackingOfValues() public {
        (, uint128 value) = _getAmountAndValue();
        eq(value, depositValue, "property_trackingOfValues");
    }

    function _getAmountAndValue() internal view returns (uint128, uint128) {
        (uint128 assetAmount, uint128 assetAmountValue, ,) = holdings.holding(poolId, scId, payoutAssetId);
        return (assetAmount, assetAmountValue);
    }
    
    // SUM OF VALUE

    /// FOUNDATIONAL PROPERTIES
    // Soundness
    function property_sound_loss() public {
        t(accounting.accountValue(poolId, LOSS_ACCOUNT) <= 0, "Loss is always negative");
    }
    function property_sound_gain() public {
        t(accounting.accountValue(poolId, GAIN_ACCOUNT) >= 0, "Gain is always positive");
    }

    /// SUM of accounting
    function property_sum_of_losses() public {
        t(lossValue == int256(accounting.accountValue(poolId, LOSS_ACCOUNT)), "property_sum_of_losses");
    }

    function property_sum_of_gains() public {
        t(yieldValue == int256(accounting.accountValue(poolId, GAIN_ACCOUNT)), "property_sum_of_gains");
    }

    // Function global solvency property
    // Equity | Assets = Either Yield or Loss
    // Equity = Assets + Yield - Loss
    // But not just as accounts, more
}