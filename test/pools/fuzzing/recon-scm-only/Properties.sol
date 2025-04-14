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
    // Soundness | TODO: Given overflow for now we can cap at a certain value
    function property_sound_loss() public {
        
        if(SKIP_ABOVE_INT128) {
            (uint128 totalDebit, uint128 totalCredit, , , ) = accounting.accounts(poolId, LOSS_ACCOUNT);
            if(totalDebit > uint128(type(int128).max) || totalCredit > uint128(type(int128).max)) {
                return;
            }
        }
        t(accounting.accountValue(poolId, LOSS_ACCOUNT) <= 0, "Loss is always negative"); // TODO: Seems to break, but I think it should never break
    }
    function property_sound_gain() public {
        if(SKIP_ABOVE_INT128) {
            (uint128 totalDebit, uint128 totalCredit, , , ) = accounting.accounts(poolId, GAIN_ACCOUNT);
            if(totalDebit > uint128(type(int128).max) || totalCredit > uint128(type(int128).max)) {
                return;
            }
        }
        t(accounting.accountValue(poolId, GAIN_ACCOUNT) >= 0, "Gain is always positive");
    }

    /// SUM of accounting
    function property_sum_of_losses() public {
        if(SKIP_ABOVE_INT128) {
            (uint128 totalDebit, uint128 totalCredit, , , ) = accounting.accounts(poolId, LOSS_ACCOUNT);
            if(totalDebit > uint128(type(int128).max) || totalCredit > uint128(type(int128).max)) {
                return;
            }
        }
        t(lossValue == int256(accounting.accountValue(poolId, LOSS_ACCOUNT)), "property_sum_of_losses");
    }

    function property_sum_of_gains() public {
        if(SKIP_ABOVE_INT128) {
            (uint128 totalDebit, uint128 totalCredit, , , ) = accounting.accounts(poolId, GAIN_ACCOUNT);
            if(totalDebit > uint128(type(int128).max) || totalCredit > uint128(type(int128).max)) {
                return;
            }
        }
        t(yieldValue == int256(accounting.accountValue(poolId, GAIN_ACCOUNT)), "property_sum_of_gains");
    }

    // Function global solvency property
    // Equity | Assets = Either Yield or Loss
    // Equity = Assets + Yield - Loss
    // But not just as accounts, more

    // Accounting Properties | TODO
    function property_total_yield() public {
        int128 assets = accounting.accountValue(poolId, ASSET_ACCOUNT);
        int128 equity = accounting.accountValue(poolId, EQUITY_ACCOUNT);

        if(assets > equity) {
            // Yield
            int128 yield = accounting.accountValue(poolId, GAIN_ACCOUNT);
            t(yield == assets - equity, "property_total_yield gain");
        } else if (assets < equity) {
            // Loss
            int128 loss = accounting.accountValue(poolId, LOSS_ACCOUNT);
            t(loss == assets - equity, "property_total_yield loss"); // Loss is negative
        }
    }

    function property_asset_soundness() public {
        int128 assets = accounting.accountValue(poolId, ASSET_ACCOUNT);
        int128 equity = accounting.accountValue(poolId, EQUITY_ACCOUNT);
        int128 loss = accounting.accountValue(poolId, LOSS_ACCOUNT);
        int128 gain = accounting.accountValue(poolId, GAIN_ACCOUNT);

        // assets = accountValue(Equity) + accountValue(Gain) - accountValue(Loss)
        t(assets == equity + gain + loss, "property_asset_soundness"); // Loss is already negative
    }

    function property_equity_soundness() public {
        int128 assets = accounting.accountValue(poolId, ASSET_ACCOUNT);
        int128 equity = accounting.accountValue(poolId, EQUITY_ACCOUNT);
        int128 loss = accounting.accountValue(poolId, LOSS_ACCOUNT);
        int128 gain = accounting.accountValue(poolId, GAIN_ACCOUNT);

        // equity = accountValue(Asset) + (ABS(accountValue(Loss)) - accountValue(Gain) // Loss comes back, gain is subtracted
        t(equity == assets + (-loss) - gain, "property_equity_soundness"); // Loss comes back, gain is subtracted, since loss is negative we need to negate it
    }

    function property_gain_soundness() public {
        int128 assets = accounting.accountValue(poolId, ASSET_ACCOUNT);
        int128 equity = accounting.accountValue(poolId, EQUITY_ACCOUNT);
        int128 loss = accounting.accountValue(poolId, LOSS_ACCOUNT);
        int128 gain = accounting.accountValue(poolId, GAIN_ACCOUNT);

        // Total Yield = // accountValue(Asset) - accountValue(Equity))
        // Gain = Total Yield + accountValue(loss) /// I had to gain yield + loss to get to yield
        int128 totalYield = assets - equity; // Can be positive or negative
        t(gain == totalYield + (-loss), "property_gain_soundness");
    }

    function property_loss_soundness() public {
        int128 assets = accounting.accountValue(poolId, ASSET_ACCOUNT);
        int128 equity = accounting.accountValue(poolId, EQUITY_ACCOUNT);
        int128 loss = accounting.accountValue(poolId, LOSS_ACCOUNT);
        int128 gain = accounting.accountValue(poolId, GAIN_ACCOUNT);

        // Loss = Total Yield (abs) - accountValue(gain) // Negative Loss (- of this is loss)
        int128 totalYield = assets - equity; // Can be positive or negative
        t(loss == totalYield - gain, "property_gain_soundness");
    }

    function property_accounting_and_holdings_soundness() public {
        // Accounting.assets is the value held
        // Holdings.value is the value held, they must match
        uint128 assets = uint128(accounting.accountValue(poolId, ASSET_ACCOUNT));
        uint128 holdingsValue = holdings.value(poolId, scId, depositAssetId);
        
        // This property holds all of the system accounting together
        eq(assets, holdingsValue, "Assets and Holdingsm must match");
    }

    // TODO: Holdings.amount should be equal to equity value / average price (minus rounding)
    // NOTE: Since we never change price the current formula should be somewhat simply

    function property_holdings_amount_is_consistent_with_average_valuation() public {
        // TODO: This property will prob take a while
    }
        
}