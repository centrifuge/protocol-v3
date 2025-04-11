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
            depositValue -= uint256(int256(-diff)); // Negative

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
        require(maxApproval < 1e26); // Cap to more realistic values

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
    
    // AFTER
    // function updateHoldingAmount(
    //     PoolId poolId,
    //     ShareClassId scId,
    //     AssetId assetId,
    //     uint128 amount,
    //     D18 pricePerUnit,
    //     bool isIncrease,
    //     JournalEntry[] memory debits,
    //     JournalEntry[] memory credits
    // ) public auth {
    //     accounting.unlock(poolId);
    //     address poolCurrency = hubRegistry.currency(poolId).addr();
    //     transientValuation.setPrice(assetId.addr(), poolCurrency, pricePerUnit);
    //     uint128 valueChange = transientValuation.getQuote(amount, assetId.addr(), poolCurrency).toUint128();
    //     /// @audit the update here desynchs the holdings as the holdings remain unchanged, but we add values
    //     (uint128 debited, uint128 credited) = _updateJournal(debits, credits);
    //     uint128 debitValueLeft = valueChange - debited;
    //     uint128 creditValueLeft = valueChange - credited;

    //     _updateHoldingWithPartialDebitsAndCredits(
    //         poolId, scId, assetId, amount, isIncrease, debitValueLeft, creditValueLeft
    //     );
    //     accounting.lock();
    // }

    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
