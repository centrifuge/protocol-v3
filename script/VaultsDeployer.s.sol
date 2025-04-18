// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAuth} from "src/misc/interfaces/IAuth.sol";

import {ISafe} from "src/common/Guardian.sol";
import {Gateway} from "src/common/Gateway.sol";

import {AsyncRequests} from "src/vaults/AsyncRequests.sol";
import {BalanceSheet} from "src/vaults/BalanceSheet.sol";
import {TokenFactory} from "src/vaults/factories/TokenFactory.sol";
import {AsyncVaultFactory} from "src/vaults/factories/AsyncVaultFactory.sol";
import {SyncDepositVaultFactory} from "src/vaults/factories/SyncDepositVaultFactory.sol";
import {RestrictedTransfers} from "src/hooks/RestrictedTransfers.sol";
import {FreelyTransferable} from "src/hooks/FreelyTransferable.sol";
import {SyncRequests} from "src/vaults/SyncRequests.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";
import {Escrow} from "src/vaults/Escrow.sol";
import {VaultRouter} from "src/vaults/VaultRouter.sol";
import {IBaseInvestmentManager} from "src/vaults/interfaces/investments/IBaseInvestmentManager.sol";

import "forge-std/Script.sol";
import {CommonDeployer} from "script/CommonDeployer.s.sol";

contract VaultsDeployer is CommonDeployer {
    BalanceSheet public balanceSheet;
    AsyncRequests public asyncRequests;
    SyncRequests public syncRequests;
    PoolManager public poolManager;
    Escrow public escrow;
    Escrow public routerEscrow;
    VaultRouter public vaultRouter;
    address public asyncVaultFactory;
    address public syncDepositVaultFactory;
    address public tokenFactory;

    // Hooks
    address public restrictedTransfers;
    address public freelyTransferable;

    function deployVaults(uint16 centrifugeId, ISafe adminSafe_, address deployer, bool isTests) public {
        deployCommon(centrifugeId, adminSafe_, deployer, isTests);

        escrow = new Escrow{salt: SALT}(deployer);
        routerEscrow = new Escrow{salt: keccak256(abi.encodePacked(SALT, "escrow2"))}(deployer);
        tokenFactory = address(new TokenFactory{salt: SALT}(address(root), deployer));
        asyncRequests = new AsyncRequests(address(root), address(escrow), deployer);
        syncRequests = new SyncRequests(address(root), address(escrow), deployer);
        asyncVaultFactory = address(new AsyncVaultFactory(address(root), address(asyncRequests), deployer));
        syncDepositVaultFactory =
            address(new SyncDepositVaultFactory(address(root), address(syncRequests), address(asyncRequests), deployer));
        address[] memory vaultFactories = new address[](2);
        vaultFactories[0] = asyncVaultFactory;
        vaultFactories[1] = syncDepositVaultFactory;

        poolManager = new PoolManager(address(escrow), tokenFactory, vaultFactories, deployer);
        balanceSheet = new BalanceSheet(address(escrow), deployer);
        vaultRouter =
            new VaultRouter(address(routerEscrow), address(gateway), address(poolManager), messageDispatcher, deployer);

        // Hooks
        restrictedTransfers = address(new RestrictedTransfers{salt: SALT}(address(root), deployer));
        freelyTransferable = address(new FreelyTransferable{salt: SALT}(address(root), address(escrow), deployer));

        _vaultsRegister();
        _vaultsEndorse();
        _vaultsRely();
        _vaultsFile();
    }

    function _vaultsRegister() private {
        register("escrow", address(escrow));
        register("routerEscrow", address(routerEscrow));
        register("restrictedTransfers", address(restrictedTransfers));
        register("freelyTransferable", address(freelyTransferable));
        register("tokenFactory", address(tokenFactory));
        register("asyncRequests", address(asyncRequests));
        register("syncRequests", address(syncRequests));
        register("asyncVaultFactory", address(asyncVaultFactory));
        register("syncDepositVaultFactory", address(syncDepositVaultFactory));
        register("poolManager", address(poolManager));
        register("vaultRouter", address(vaultRouter));
    }

    function _vaultsEndorse() private {
        root.endorse(address(vaultRouter));
        root.endorse(address(escrow));
    }

    function _vaultsRely() private {
        // Rely PoolManager
        escrow.rely(address(poolManager));
        IAuth(asyncVaultFactory).rely(address(poolManager));
        IAuth(syncDepositVaultFactory).rely(address(poolManager));
        IAuth(tokenFactory).rely(address(poolManager));
        asyncRequests.rely(address(poolManager));
        syncRequests.rely(address(poolManager));
        IAuth(restrictedTransfers).rely(address(poolManager));
        IAuth(freelyTransferable).rely(address(poolManager));
        messageDispatcher.rely(address(poolManager));
        gateway.rely(address(poolManager));

        // Rely async investment manager
        balanceSheet.rely(address(asyncRequests));
        messageDispatcher.rely(address(asyncRequests));
        escrow.rely(address(asyncRequests));

        // Rely sync investment manager
        balanceSheet.rely(address(syncRequests));
        asyncRequests.rely(address(syncRequests));

        // Rely BalanceSheet
        messageDispatcher.rely(address(balanceSheet));
        escrow.rely(address(balanceSheet));

        // Rely Root
        vaultRouter.rely(address(root));
        poolManager.rely(address(root));
        asyncRequests.rely(address(root));
        syncRequests.rely(address(root));
        balanceSheet.rely(address(root));
        escrow.rely(address(root));
        routerEscrow.rely(address(root));
        IAuth(asyncVaultFactory).rely(address(root));
        IAuth(syncDepositVaultFactory).rely(address(root));
        IAuth(tokenFactory).rely(address(root));
        IAuth(restrictedTransfers).rely(address(root));
        IAuth(freelyTransferable).rely(address(root));

        // Rely gateway
        asyncRequests.rely(address(gateway));
        poolManager.rely(address(gateway));

        // Rely others
        routerEscrow.rely(address(vaultRouter));
        syncRequests.rely(address(syncDepositVaultFactory));

        // Rely messageProcessor
        poolManager.rely(address(messageProcessor));
        asyncRequests.rely(address(messageProcessor));
        balanceSheet.rely(address(messageProcessor));

        // Rely messageDispatcher
        poolManager.rely(address(messageDispatcher));
        asyncRequests.rely(address(messageDispatcher));
        balanceSheet.rely(address(messageDispatcher));

        // Rely VaultRouter
        gateway.rely(address(vaultRouter));
        poolManager.rely(address(vaultRouter));
    }

    function _vaultsFile() public {
        messageDispatcher.file("poolManager", address(poolManager));
        messageDispatcher.file("investmentManager", address(asyncRequests));
        messageDispatcher.file("balanceSheet", address(balanceSheet));

        messageProcessor.file("poolManager", address(poolManager));
        messageProcessor.file("investmentManager", address(asyncRequests));
        messageProcessor.file("balanceSheet", address(balanceSheet));

        poolManager.file("gateway", address(gateway));
        poolManager.file("balanceSheet", address(balanceSheet));
        poolManager.file("sender", address(messageDispatcher));

        asyncRequests.file("poolManager", address(poolManager));
        asyncRequests.file("sender", address(messageDispatcher));
        asyncRequests.file("balanceSheet", address(balanceSheet));
        asyncRequests.file("sharePriceProvider", address(syncRequests));

        syncRequests.file("poolManager", address(poolManager));
        syncRequests.file("balanceSheet", address(balanceSheet));

        balanceSheet.file("poolManager", address(poolManager));
        balanceSheet.file("gateway", address(gateway));
        balanceSheet.file("sender", address(messageDispatcher));
        balanceSheet.file("sharePriceProvider", address(syncRequests));
    }

    function removeVaultsDeployerAccess(address deployer) public {
        removeCommonDeployerAccess(deployer);

        IAuth(asyncVaultFactory).deny(deployer);
        IAuth(syncDepositVaultFactory).deny(deployer);
        IAuth(tokenFactory).deny(deployer);
        IAuth(restrictedTransfers).deny(deployer);
        IAuth(freelyTransferable).deny(deployer);
        asyncRequests.deny(deployer);
        syncRequests.deny(deployer);
        poolManager.deny(deployer);
        balanceSheet.deny(deployer);
        escrow.deny(deployer);
        routerEscrow.deny(deployer);
        vaultRouter.deny(deployer);
    }
}
