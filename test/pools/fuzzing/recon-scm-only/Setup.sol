// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {console2} from "forge-std/console2.sol";
// Managers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";

// Helpers
import {Utils} from "@recon/Utils.sol";

// Dependencies
import {Accounting} from "src/hub/Accounting.sol";
import {HubRegistry} from "src/hub/HubRegistry.sol";
import {Gateway} from "src/common/Gateway.sol";
import {Holdings} from "src/hub/Holdings.sol";
import {HubRegistry} from "src/hub/HubRegistry.sol";
import {Hub} from "src/hub/Hub.sol";

import {ShareClassManager} from "src/hub/ShareClassManager.sol";

// Interfaces
import {IHubRegistry} from "src/hub/interfaces/IHubRegistry.sol";
import {AccountId, newAccountId} from "src/common/types/AccountId.sol";
import {IAccounting} from "src/hub/interfaces/IAccounting.sol";
import {IHoldings} from "src/hub/interfaces/IHoldings.sol";
import {IMessageSender} from "src/common/interfaces/IMessageSender.sol";
import {IAsyncRequests} from "src/vaults/interfaces/investments/IAsyncRequests.sol";
import {IShareClassManager} from "src/hub/interfaces/IShareClassManager.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";
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
import {IHub, AccountType} from "src/hub/interfaces/IHub.sol";



contract MockHubRegistry {
    function currency(PoolId poolId) external view returns (AssetId) {
        return AssetId.wrap(123);
    }
}


contract MockValuation {

    uint256 MULTIPLIER; // In 100 | // TODO: You may want to always revert here
    
    function setMultiplier(uint256 multiplier) external {
        require(multiplier < 10_000);
        MULTIPLIER = multiplier;
    }

    function getQuote(uint256 baseAmount, address base, address quote) external view returns (uint256 quoteAmount) {
        return baseAmount * MULTIPLIER / 100;
    }

}

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {

    ShareClassManager shareClassManager;
    MockHubRegistry mockRegistry;
    // TODO: Add Handlers for valuation AND Track Value properties
    IERC7726 valuation;
    IERC7726 transientValuation;
    //
    PoolId poolId;
    ShareClassId scId;
    AssetId depositAssetId = AssetId.wrap(123);
    AssetId payoutAssetId = AssetId.wrap(123);

    Accounting accounting;
    Holdings holdings;

    /// GLOBAL TRACKING
    uint256 totalApprovedDeposits;

    modifier stateless {
        _;
        revert("stateless");
    }

    AccountId ASSET_ACCOUNT;
    AccountId EQUITY_ACCOUNT;
    AccountId LOSS_ACCOUNT;
    AccountId GAIN_ACCOUNT;

    uint256 depositAmt;
    uint256 depositValue;
    
    // These can go either side?
    int256 yieldValue;
    int256 lossValue;

    // DYNAMIC REPLACEMENT
    bool SKIP_ABOVE_INT128 = bool(true); // Should we ignore soundness properties past u128?


    /// === Setup === ///
    /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry
    function setup() internal virtual override {
        // add two actors in addition to the default admin (address(this))
        _addActor(address(0x411c3));
        _addActor(address(0xb0b));

        mockRegistry = new MockHubRegistry();
        valuation = IERC7726(address(new MockValuation()));
        transientValuation = IERC7726(address(new MockValuation()));
        accounting = new Accounting(address(this)); 
        holdings  = new Holdings(IHubRegistry(address(mockRegistry)), address(this));
        holdings.rely(address(this));

        shareClassManager = new ShareClassManager(IHubRegistry(address(mockRegistry)), address(this));
        shareClassManager.rely(address(this));

        poolId = PoolId.wrap(1); // Create Pool ID
        scId = shareClassManager.addShareClass(poolId, "Name", "Symbol", bytes32(uint256(1)), hex"");

        // TODO: I am HUB AFAICT
        // I can test stuff against Accounting directly
        // I can do this:
        ASSET_ACCOUNT = newAccountId(1, uint8(AccountType.Asset));
        EQUITY_ACCOUNT = newAccountId(1, uint8(AccountType.Equity));
        LOSS_ACCOUNT = newAccountId(1, uint8(AccountType.Loss));
        GAIN_ACCOUNT = newAccountId(1, uint8(AccountType.Gain));
        accounting.createAccount(poolId, ASSET_ACCOUNT, true);
        accounting.createAccount(poolId, EQUITY_ACCOUNT, false);
        accounting.createAccount(poolId, LOSS_ACCOUNT, false);
        accounting.createAccount(poolId, GAIN_ACCOUNT, false);

        // TODO: Create holdings but simplified
        // TODO: depositAssetId vs payoutAssetId
        // NOTE: Only non liability
        AccountId[] memory accounts = new AccountId[](0);
        holdings.create(poolId, scId, depositAssetId, valuation, false, accounts);
    }


    // Clamp investors
    // Use them as actors?

    /// === MODIFIERS === ///
    /// Prank admin and actor
    
    modifier asAdmin {
        vm.prank(address(this));
        _;
    }

    modifier asActor {
        vm.prank(address(_getActor()));
        _;
    }
}
