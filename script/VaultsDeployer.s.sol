// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAuth} from "src/misc/interfaces/IAuth.sol";

import {ISafe} from "src/common/Guardian.sol";
import {Gateway} from "src/common/Gateway.sol";

import {InvestmentManager} from "src/vaults/InvestmentManager.sol";
import {BalanceSheetManager} from "src/vaults/BalanceSheetManager.sol";
import {TrancheFactory} from "src/vaults/factories/TrancheFactory.sol";
import {ERC7540VaultFactory} from "src/vaults/factories/ERC7540VaultFactory.sol";
import {RestrictionManager} from "src/vaults/token/RestrictionManager.sol";
import {RestrictedRedemptions} from "src/vaults/token/RestrictedRedemptions.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";
import {Escrow} from "src/vaults/Escrow.sol";
import {VaultRouter} from "src/vaults/VaultRouter.sol";

import "forge-std/Script.sol";
import {CommonDeployer} from "script/CommonDeployer.s.sol";

contract VaultsDeployer is CommonDeployer {
    BalanceSheetManager public balanceSheetManager;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    Escrow public routerEscrow;
    VaultRouter public vaultRouter;
    address public vaultFactory;
    address public restrictionManager;
    address public restrictedRedemptions;
    address public trancheFactory;

    function deployVaults(uint16 chainId, ISafe adminSafe_) public {
        deployCommon(chainId, adminSafe_);

        escrow = new Escrow{salt: SALT}(address(this));
        routerEscrow = new Escrow{salt: keccak256(abi.encodePacked(SALT, "escrow2"))}(address(this));
        restrictionManager = address(new RestrictionManager{salt: SALT}(address(root), address(this)));
        restrictedRedemptions =
            address(new RestrictedRedemptions{salt: SALT}(address(root), address(escrow), address(this)));
        trancheFactory = address(new TrancheFactory{salt: SALT}(address(root), address(this)));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        vaultFactory = address(new ERC7540VaultFactory(address(root), address(investmentManager)));

        address[] memory vaultFactories = new address[](1);
        vaultFactories[0] = vaultFactory;

        poolManager = new PoolManager(address(escrow), trancheFactory, vaultFactories);
        balanceSheetManager = new BalanceSheetManager(address(escrow));
        vaultRouter = new VaultRouter(address(routerEscrow), address(gateway), address(poolManager));

        _vaultsRegister();
        _vaultsEndorse();
        _vaultsRely();
        _vaultsFile();
    }

    function _vaultsRegister() private {
        register("escrow", address(escrow));
        register("routerEscrow", address(routerEscrow));
        register("restrictionManager", address(restrictionManager));
        register("restrictedRedemptions", address(restrictedRedemptions));
        register("trancheFactory", address(trancheFactory));
        register("investmentManager", address(investmentManager));
        register("vaultFactory", address(vaultFactory));
        register("poolManager", address(poolManager));
        register("vaultRouter", address(vaultRouter));
    }

    function _vaultsEndorse() private {
        root.endorse(address(vaultRouter));
        root.endorse(address(escrow));
    }

    function _vaultsRely() private {
        // Rely on PoolManager
        escrow.rely(address(poolManager));
        IAuth(vaultFactory).rely(address(poolManager));
        IAuth(trancheFactory).rely(address(poolManager));
        IAuth(investmentManager).rely(address(poolManager));
        IAuth(restrictionManager).rely(address(poolManager));
        IAuth(restrictedRedemptions).rely(address(poolManager));
        messageDispatcher.rely(address(poolManager));

        // Rely on InvestmentManager
        messageDispatcher.rely(address(investmentManager));

        // Rely on BalanceSheetManager
        messageDispatcher.rely(address(balanceSheetManager));
        escrow.rely(address(balanceSheetManager));

        // Rely on Root
        vaultRouter.rely(address(root));
        poolManager.rely(address(root));
        investmentManager.rely(address(root));
        balanceSheetManager.rely(address(root));
        escrow.rely(address(root));
        routerEscrow.rely(address(root));
        IAuth(vaultFactory).rely(address(root));
        IAuth(trancheFactory).rely(address(root));
        IAuth(restrictionManager).rely(address(root));
        IAuth(restrictedRedemptions).rely(address(root));

        // Rely on vaultGateway
        investmentManager.rely(address(gateway));
        poolManager.rely(address(gateway));

        // Rely on others
        routerEscrow.rely(address(vaultRouter));

        // Rely on messageProcessor
        poolManager.rely(address(messageProcessor));
        investmentManager.rely(address(messageProcessor));
        balanceSheetManager.rely(address(messageProcessor));

        poolManager.rely(address(messageDispatcher));
        investmentManager.rely(address(messageDispatcher));
        balanceSheetManager.rely(address(messageDispatcher));

        // Rely on VaultRouter
        gateway.rely(address(vaultRouter));
        poolManager.rely(address(vaultRouter));
    }

    function _vaultsFile() public {
        messageDispatcher.file("poolManager", address(poolManager));
        messageDispatcher.file("investmentManager", address(investmentManager));
        messageDispatcher.file("balanceSheetManager", address(investmentManager));

        messageProcessor.file("poolManager", address(poolManager));
        messageProcessor.file("investmentManager", address(investmentManager));
        messageProcessor.file("balanceSheetManager", address(investmentManager));

        poolManager.file("balanceSheetManager", address(balanceSheetManager));
        poolManager.file("sender", address(messageDispatcher));

        investmentManager.file("poolManager", address(poolManager));
        investmentManager.file("gateway", address(gateway));
        investmentManager.file("sender", address(messageDispatcher));

        balanceSheetManager.file("poolManager", address(poolManager));
        balanceSheetManager.file("gateway", address(gateway));
        balanceSheetManager.file("sender", address(messageDispatcher));
    }

    function removeVaultsDeployerAccess() public {
        removeCommonDeployerAccess();

        IAuth(vaultFactory).deny(msg.sender);
        IAuth(trancheFactory).deny(msg.sender);
        IAuth(restrictionManager).deny(msg.sender);
        IAuth(restrictedRedemptions).deny(msg.sender);
        investmentManager.deny(msg.sender);
        poolManager.deny(msg.sender);
        escrow.deny(msg.sender);
        routerEscrow.deny(msg.sender);
        vaultRouter.deny(msg.sender);
    }
}
