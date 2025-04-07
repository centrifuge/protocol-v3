// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";

import {D18, d18} from "src/misc/types/D18.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {IMulticall} from "src/misc/interfaces/IMulticall.sol";
import {IERC7726} from "src/misc/interfaces/IERC7726.sol";

import {MessageLib, VaultUpdateKind} from "src/common/libraries/MessageLib.sol";
import {IAdapter} from "src/common/interfaces/IAdapter.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId, newAssetId} from "src/common/types/AssetId.sol";
import {PoolId} from "src/common/types/PoolId.sol";
import {AccountId, newAccountId} from "src/common/types/AccountId.sol";
import {IGasService} from "src/common/interfaces/IGasService.sol";

import {PoolsDeployer, ISafe} from "script/PoolsDeployer.s.sol";
import {MESSAGE_COST_ENV, PROOF_COST_ENV} from "script/CommonDeployer.s.sol";
import {AccountType} from "src/pools/interfaces/IPoolRouter.sol";
import {JournalEntry} from "src/common/libraries/JournalEntryLib.sol";

import {MockVaults} from "test/pools/mocks/MockVaults.sol";
import {ShareClassIdTest} from "../unit/types/ShareClassId.t.sol";

contract BaseTest is PoolsDeployer, Test {
    uint16 constant CHAIN_CP = 5;
    uint16 constant CHAIN_CV = 6;

    string constant SC_NAME = "ExampleName";
    string constant SC_SYMBOL = "ExampleSymbol";
    bytes32 constant SC_SALT = bytes32("ExampleSalt");
    bytes32 constant SC_HOOK = bytes32("ExampleHookData");

    address immutable ADMIN = address(adminSafe);
    address immutable FM = makeAddr("FM");
    address immutable ANY = makeAddr("Anyone");
    bytes32 immutable INVESTOR = bytes32("Investor");

    AssetId immutable USDC_C2 = newAssetId(CHAIN_CV, 1);

    uint128 constant INVESTOR_AMOUNT = 100 * 1e6; // USDC_C2
    uint128 constant SHARE_AMOUNT = 10 * 1e18; // Share from USD
    uint128 constant APPROVED_INVESTOR_AMOUNT = INVESTOR_AMOUNT / 5;
    uint128 constant APPROVED_SHARE_AMOUNT = SHARE_AMOUNT / 5;
    D18 immutable NAV_PER_SHARE = d18(2, 1);

    uint64 constant GAS = 100 wei;

    MockVaults cv;

    function _mockStuff() private {
        cv = new MockVaults(CHAIN_CV, gateway);
        wire(CHAIN_CV, cv, address(this));
    }

    function setUp() public {
        // Pre deployment
        vm.setEnv(MESSAGE_COST_ENV, vm.toString(GAS));
        vm.setEnv(PROOF_COST_ENV, vm.toString(GAS));

        // Deployment
        deployPools(CHAIN_CP, ISafe(ADMIN), address(this));
        _mockStuff();
        removePoolsDeployerAccess(address(this));

        // Initialize accounts
        vm.deal(FM, 1 ether);

        // Label contracts & actors (for debugging)
        vm.label(address(transientValuation), "TransientValuation");
        vm.label(address(identityValuation), "IdentityValuation");
        vm.label(address(poolRegistry), "PoolRegistry");
        vm.label(address(assetRegistry), "AssetRegistry");
        vm.label(address(accounting), "Accounting");
        vm.label(address(holdings), "Holdings");
        vm.label(address(multiShareClass), "MultiShareClass");
        vm.label(address(poolRouter), "PoolRouter");
        vm.label(address(gateway), "Gateway");
        vm.label(address(messageProcessor), "MessageProcessor");
        vm.label(address(messageDispatcher), "MessageDispatcher");
        vm.label(address(cv), "CV");

        // We should not use the block ChainID
        vm.chainId(0xDEAD);
    }
}
