// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";

// Managers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";

// Helpers
import {Utils} from "@recon/Utils.sol";

// Your deps
import "src/pools/Accounting.sol";
import "src/pools/AssetRegistry.sol";
import "src/common/Gateway.sol";
import "src/pools/Holdings.sol";
import "src/pools/PoolManager.sol";
import "src/pools/PoolRegistry.sol";
import "src/pools/PoolRouter.sol";
import "src/pools/SingleShareClass.sol";
import "src/pools/interfaces/IPoolRegistry.sol";
import "src/pools/interfaces/IAssetRegistry.sol";
import "src/pools/interfaces/IAccounting.sol";
import "src/pools/interfaces/IHoldings.sol";
import "src/common/interfaces/IGateway.sol";
import "src/pools/interfaces/IPoolManager.sol";
import "src/misc/TransientValuation.sol";
import "src/misc/IdentityValuation.sol";
import "src/pools/MessageProcessor.sol";
import "test/vaults/mocks/MockAdapter.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    Accounting accounting;
    AssetRegistry assetRegistry;
    Gateway gateway;
    Holdings holdings;
    PoolManager poolManager;
    PoolRegistry poolRegistry;
    PoolRouter poolRouter;
    SingleShareClass singleShareClass;
    MessageProcessor messageProcessor;
    TransientValuation transientValuation;
    IdentityValuation identityValuation;

    MockAdapter mockAdapter;
    
    /// === Setup === ///
    /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry
    function setup() internal virtual override {
        accounting = new Accounting(address(this)); 
        assetRegistry = new AssetRegistry(address(this)); 
        gateway = new Gateway(address(this));
        poolRegistry = new PoolRegistry(address(this)); 

        holdings = new Holdings(IPoolRegistry(address(poolRegistry)), address(this));
        poolManager = new PoolManager(IPoolRegistry(address(poolRegistry)), IAssetRegistry(address(assetRegistry)), IAccounting(address(accounting)), IHoldings(address(holdings)), IGateway(address(gateway)), address(this));
        poolRouter = new PoolRouter(IPoolManager(address(poolManager)));
        singleShareClass = new SingleShareClass(IPoolRegistry(address(poolRegistry)), address(this));
        messageProcessor = new MessageProcessor(gateway, poolManager, address(this));
        mockAdapter = new MockAdapter(address(gateway));

        transientValuation = new TransientValuation(assetRegistry, address(this));
        identityValuation = new IdentityValuation(assetRegistry, address(this));

        // set addresses on the PoolManager and Gateway
        poolManager.file("sender", address(messageProcessor));
        gateway.file("handle", address(messageProcessor));
        gateway.file("adapter", address(mockAdapter));
        
        // set permissions for calling privileged functions
        poolRegistry.rely(address(poolManager));
        assetRegistry.rely(address(poolManager));
        accounting.rely(address(poolManager));
        holdings.rely(address(poolManager));
        gateway.rely(address(poolManager));
        gateway.rely(address(messageProcessor));
        singleShareClass.rely(address(poolManager));
        poolManager.rely(address(poolRouter));
        messageProcessor.rely(address(poolManager));
    }

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
