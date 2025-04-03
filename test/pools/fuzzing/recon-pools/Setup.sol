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

// Dependencies
import {Accounting} from "src/pools/Accounting.sol";
import {AssetRegistry} from "src/pools/AssetRegistry.sol";
import {Gateway} from "src/common/Gateway.sol";
import {Holdings} from "src/pools/Holdings.sol";
import {PoolRegistry} from "src/pools/PoolRegistry.sol";
import {PoolRouter} from "src/pools/PoolRouter.sol";
import {MultiShareClass} from "src/pools/MultiShareClass.sol";
import {IPoolRegistry} from "src/pools/interfaces/IPoolRegistry.sol";
import {IAssetRegistry} from "src/pools/interfaces/IAssetRegistry.sol";
import {IAccounting} from "src/pools/interfaces/IAccounting.sol";
import {IHoldings} from "src/pools/interfaces/IHoldings.sol";
import {IMessageSender} from "src/common/interfaces/IMessageSender.sol";
import {IAsyncRequests} from "src/vaults/interfaces/investments/IAsyncRequests.sol";
import {IGateway} from "src/common/interfaces/IGateway.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";
import {TransientValuation, ITransientValuation} from "src/misc/TransientValuation.sol";
import {IdentityValuation} from "src/misc/IdentityValuation.sol";
import {MessageProcessor} from "src/common/MessageProcessor.sol";
import {Root} from "src/common/Root.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {D18, d18} from "src/misc/types/D18.sol";
import {MockAdapter} from "test/common/mocks/MockAdapter.sol";
import {MockGasService} from "test/common/mocks/MockGasService.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";

import {MockGateway} from "test/pools/fuzzing/recon-pools/mocks/MockGateway.sol";
import {MultiShareClassWrapper} from "test/pools/fuzzing/recon-pools/utils/MultiShareClassWrapper.sol";
import {MockMessageDispatcher} from "test/vaults/fuzzing/recon-vault/mocks/MockMessageDispatcher.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    enum Op {
        APPROVE_DEPOSITS,
        APPROVE_REDEEMS,
        REVOKE_SHARES
    }

    struct QueuedOp {
        Op op;
        ShareClassId scId;
    }

    Accounting accounting;
    AssetRegistry assetRegistry;
    Holdings holdings;
    PoolRegistry poolRegistry;
    PoolRouter poolRouter;
    MultiShareClassWrapper multiShareClass;
    TransientValuation transientValuation;
    IdentityValuation identityValuation;
    Root root;

    MockAdapter mockAdapter;
    MockGasService gasService;
    MockGateway gateway;
    MockMessageDispatcher messageDispatcher;
    bytes[] internal queuedCalls; // used for storing calls to PoolRouter to be executed in a single transaction
    PoolId[] internal createdPools;
    // QueuedOp[] internal queuedOps;
    
    // Canaries
    bool poolCreated;
    bool deposited;
    bool cancelledRedeemRequest;

    // set the initial price that gets used when creating an asset via a pool's shortcut to avoid stack too deep errors
    D18 internal INITIAL_PRICE = d18(1e18); 
    uint16 internal CENTIFUGE_CHAIN_ID = 1;

    event LogString(string);

    modifier stateless {
        revert("stateless");
        _;
    }

    /// @dev Clear queued calls so they don't interfere with executions in shortcut functions 
    modifier clearQueuedCalls {
        queuedCalls = new bytes[](0);
        _;
    }
    
    /// === Setup === ///
    /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry
    function setup() internal virtual override {
        // add two actors in addition to the default admin (address(this))
        _addActor(address(0x10000));
        _addActor(address(0x20000));

        gateway = new MockGateway();
        gasService = new MockGasService();
        root = new Root(7 days, address(this));
        accounting = new Accounting(address(this)); 
        assetRegistry = new AssetRegistry(address(this)); 
        poolRegistry = new PoolRegistry(address(this)); 
        transientValuation = new TransientValuation(assetRegistry, address(this));
        identityValuation = new IdentityValuation(assetRegistry, address(this));

        holdings = new Holdings(IPoolRegistry(address(poolRegistry)), address(this));
        poolRouter = new PoolRouter(IPoolRegistry(address(poolRegistry)), IAssetRegistry(address(assetRegistry)), IAccounting(address(accounting)), IHoldings(address(holdings)), IGateway(address(gateway)), ITransientValuation(address(transientValuation)), address(this));
        multiShareClass = new MultiShareClassWrapper(IPoolRegistry(address(poolRegistry)), address(this));
        messageDispatcher = new MockMessageDispatcher(PoolManager(address(this)), IAsyncRequests(address(this)), root, CENTIFUGE_CHAIN_ID);

        mockAdapter = new MockAdapter(CENTIFUGE_CHAIN_ID, IMessageHandler(address(gateway)));

        // set addresses on the PoolRouter
        poolRouter.file("sender", address(messageDispatcher));

        // set permissions for calling privileged functions
        poolRegistry.rely(address(poolRouter));
        assetRegistry.rely(address(poolRouter));
        accounting.rely(address(poolRouter));
        holdings.rely(address(poolRouter));
        multiShareClass.rely(address(poolRouter));
        poolRouter.rely(address(poolRouter));
        multiShareClass.rely(address(this));
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
