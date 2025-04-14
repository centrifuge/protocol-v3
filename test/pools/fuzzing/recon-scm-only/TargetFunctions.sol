// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";
import {console2} from "forge-std/console2.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Source
import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";

import {Properties} from "./Properties.sol";

import {IHubRegistry} from "src/hub/interfaces/IHubRegistry.sol";
import {IAccounting} from "src/hub/interfaces/IAccounting.sol";
import {IHoldings, Holding} from "src/hub/interfaces/IHoldings.sol";
import {IMessageSender} from "src/common/interfaces/IMessageSender.sol";
import {IAsyncRequests} from "src/vaults/interfaces/investments/IAsyncRequests.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";
import {TransientValuation, ITransientValuation} from "src/misc/TransientValuation.sol";
import {IdentityValuation} from "src/misc/IdentityValuation.sol";
import {MessageProcessor} from "src/common/MessageProcessor.sol";
import {Root} from "src/common/Root.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {MockAdapter} from "test/common/mocks/MockAdapter.sol";
import {MockGasService} from "test/common/mocks/MockGasService.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";
import {AccountId} from "src/common/types/AccountId.sol";

import {ShareClassManagerTargets} from "./targets/ShareClassManagerTargets.sol";
import {MockValuation} from "./Setup.sol";

abstract contract TargetFunctions is
    ShareClassManagerTargets
{

    // Update valuation
    function setMultiplier(uint256 val) public {
        MockValuation(address(valuation)).setMultiplier(val);
    }

    // TODO: We are the HUB NOW
    // NEED TO FUZZ AT A DIFFERENT LEVEL
    function updateHolding() public {

        // TODO: YIELD AND LOSSES
        int128 diff = holdings.update(poolId, scId, depositAssetId);

        _unlock();
        if (diff > 0) {

            yieldValue += diff;
            depositValue += uint128(diff);
            
            accounting.addCredit(
                GAIN_ACCOUNT, uint128(diff)
            );
            accounting.addDebit(
                ASSET_ACCOUNT, uint128(diff)
            );
        } else if (diff < 0) {

            lossValue += diff; // Loss value <= 0
            console2.log("loss diff", diff);
            depositValue -= uint256(-int256(diff)); // Negative

            accounting.addCredit(
                ASSET_ACCOUNT, uint128(uint256(-int256(diff)))
            );
            accounting.addDebit(
                LOSS_ACCOUNT, uint128(uint256(-int256(diff)))
            );
        }
        _lock();
    }

    // TODO: How would this work here?
    function approveDeposits(uint128 maxApproval)
        public
    {
        (uint128 approvedAssetAmount,) = /// Some amount at time X (dust) and new amounts at time closer to now
            shareClassManager.approveDeposits(poolId, scId, maxApproval, depositAssetId, valuation);
            
        /// @audit there is value that is tracked in SCM that is not added to HOLDINGS
        uint128 valueChange = holdings.increase(poolId, scId, depositAssetId, valuation, approvedAssetAmount);

        // TODO: Value increase
        depositAmt += approvedAssetAmount;
        depositValue += valueChange;

        _unlock();
        accounting.addCredit(
            EQUITY_ACCOUNT, valueChange
        );
        accounting.addDebit(
            ASSET_ACCOUNT, valueChange
        );
        _lock();
    }

    // TODO: How would this work here? | // TODO: Nav per share modelling
    function revokeShares(D18 navPerShare)
        public
    {
        (uint128 payoutAssetAmount,) = shareClassManager.revokeShares(poolId, scId, payoutAssetId, navPerShare, valuation); /// @audit nav and valuation to be modelled

        uint128 valueChange = holdings.decrease(poolId, scId, payoutAssetId, valuation, payoutAssetAmount);

        // TODO: Overflow Properties here as well
        lte(payoutAssetAmount, depositAmt, "payoutAssetAmount > depositAmt");
        lte(valueChange, depositValue, "valueChange > depositValue");
            
        depositAmt -= payoutAssetAmount;
        depositValue -= valueChange;

        
        _unlock();
        accounting.addCredit(
            ASSET_ACCOUNT, valueChange
        );
        accounting.addDebit(
            EQUITY_ACCOUNT, valueChange
        );
        _lock();

        
        
    }


    function _unlock() internal {
        try accounting.unlock(poolId) {} catch { t(false, "Account didn't unlock");}
    }
    function _lock() internal {
        try accounting.lock() {} catch { t(false, "Account didn't lock correctly"); }
    }

    // Put rest of state exploration for `shareClassManager`
    

    // JournalEntry needs to be for one of the 4 accounts
    // Same for the other

    // Then we investigate the rest


    // AFTER
    function updateHoldingAmount(
        uint128 amount,
        // D18 pricePerUnit, NOTE: We skip updating price, it's updated by TargetFunctions
        bool isIncrease,
        uint256 debitIndex,
        uint256 creditIndex,
        uint128 debits,
        uint128 credits
    ) public {
        _unlock();

        // NOTE: Addresses are ignored
        uint256 fullPrecisionChange = transientValuation.getQuote(amount, address(0), address(0));
        require(fullPrecisionChange <= type(uint128).max, "Full precision change is too large");
        uint128 valueChange = uint128(fullPrecisionChange);

        /// @audit the update here desynchs the holdings as the holdings remain unchanged, but we add values

        // Apply some debit and some credits
        // Could be imbalanced | TODO: Which accounts can we use?
        (uint128 debited, uint128 credited) = _updateJournal(debitIndex, debits, creditIndex, credits);
        uint128 debitValueLeft = valueChange - debited;
        uint128 creditValueLeft = valueChange - credited;

        _updateHoldingWithPartialDebitsAndCredits(
            amount,
            isIncrease,
            debitValueLeft,
            creditValueLeft
        );

        _lock();
        // TODO: Remove stateless and allow proper tracking
        
        eq(debitValueLeft, creditValueLeft, "We can never go past this with different values");
            
        revert("stateless");
    }
    
    /// Simplified variant
    function _updateJournal(uint256 debitIndex, uint128 debits, uint256 creditIndex, uint128 credits)
        internal
        returns (uint128 debited, uint128 credited)
    {
        
        AccountId debitId = _getAccountIdFromNumber(debitIndex);
        AccountId creditId = _getAccountIdFromNumber(creditIndex);

        accounting.addDebit(debitId, debits);

        accounting.addCredit(creditId, credits);

        return (debits, credits);
    }

    function _getAccountIdFromNumber(uint256 index) internal returns (AccountId) {
        uint256 normalizedIndex = index % 4;
        // 0, 1, 2, 3
        if(normalizedIndex == 0) {
            return ASSET_ACCOUNT;
        }

        if(normalizedIndex == 1) {
            return EQUITY_ACCOUNT;
        }

        if(normalizedIndex == 2) {
            return LOSS_ACCOUNT;
        }

        if(normalizedIndex == 3) {
            return GAIN_ACCOUNT;
        }

        t(false, "Invalid index");
    }

    function _updateHoldingWithPartialDebitsAndCredits(
        uint128 amount,
        bool isIncrease,
        uint128 debitValue,
        uint128 creditValue
    ) internal {
        bool isLiability = holdings.isLiability(poolId, scId, payoutAssetId); // False all the time
        t(!isLiability, "isLiability"); // Always false

        // 
        // AccountType debitAccountType = isLiability ? AccountType.Expense : AccountType.Asset;
        // AccountType creditAccountType = isLiability ? AccountType.Liability : AccountType.Equity;
        

        // Add X, Remove Y
        /// Add Z - X on one side, add Z + Y  on the other, I think either there's zeros or they must be the same value

        if (isIncrease) {
            holdings.increase(poolId, scId, payoutAssetId, transientValuation, amount); /// @audit I think this breaks the property
            // accounting.addDebit(, debitValue);
            // accounting.addCredit(, creditValue);

            // TODO: Are these correct? NOTE: NO THIS CAN'T BE
            // TODO: How would this become correct? TOOD: Go back to properties
            // depositValue = depositValue + (int256(uint256(creditValue)) - int256(uint256(debitValue)));
            yieldValue = yieldValue + (int256(uint256(creditValue)) - int256(uint256(debitValue)));

            // Increase in equity, decrease in asset?
            accounting.addCredit(EQUITY_ACCOUNT, creditValue);
            accounting.addDebit(ASSET_ACCOUNT, debitValue); /// @audit this could be both higher or lower

        } else {
            // Loss of equity, increase in asset?
            holdings.decrease(poolId, scId, payoutAssetId, transientValuation, amount);
            accounting.addCredit(ASSET_ACCOUNT, creditValue);
            accounting.addDebit(EQUITY_ACCOUNT, debitValue);
            
            // depositValue = depositValue + ((debitValue)) - int256(uint256(creditValue)));
            yieldValue = yieldValue + (int256(uint256(debitValue)) - int256(uint256(creditValue)));
        }
    }


    /// Q: from first principles are we adding Principal or Yield?

            
            


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
