// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAuth} from "src/misc/interfaces/IAuth.sol";

import {Root} from "src/common/Root.sol";
import {GasService} from "src/common/GasService.sol";
import {Guardian, ISafe} from "src/common/Guardian.sol";
import {IAdapter} from "src/common/interfaces/IAdapter.sol";
import {Gateway} from "src/common/Gateway.sol";

import {InvestmentManager} from "src/vaults/InvestmentManager.sol";
import {TrancheFactory} from "src/vaults/factories/TrancheFactory.sol";
import {ERC7540VaultFactory} from "src/vaults/factories/ERC7540VaultFactory.sol";
import {RestrictionManager} from "src/vaults/token/RestrictionManager.sol";
import {RestrictedRedemptions} from "src/vaults/token/RestrictedRedemptions.sol";
import {PoolManager} from "src/vaults/PoolManager.sol";
import {Escrow} from "src/vaults/Escrow.sol";
import {VaultsRouter} from "src/vaults/VaultsRouter.sol";
import {MessageProcessor} from "src/vaults/MessageProcessor.sol";
import "forge-std/Script.sol";

contract Deployer is Script {
    uint256 internal constant delay = 48 hours;
    ISafe adminSafe;
    IAdapter[] adapters;

    Root public root;
    InvestmentManager public investmentManager;
    PoolManager public poolManager;
    Escrow public escrow;
    Escrow public routerEscrow;
    Guardian public guardian;
    Gateway public gateway;
    MessageProcessor public messageProcessor;
    GasService public gasService;
    VaultsRouter public router;
    address public vaultFactory;
    address public restrictionManager;
    address public restrictedRedemptions;
    address public trancheFactory;

    function deploy(address deployer) public {
        // If no salt is provided, a pseudo-random salt is generated,
        // thus effectively making the deployment non-deterministic
        bytes32 salt = vm.envOr(
            "DEPLOYMENT_SALT", keccak256(abi.encodePacked(string(abi.encodePacked(blockhash(block.number - 1)))))
        );

        uint64 messageCost = uint64(vm.envOr("MESSAGE_COST", uint256(20000000000000000))); // in Weight
        uint64 proofCost = uint64(vm.envOr("PROOF_COST", uint256(20000000000000000))); // in Weigth
        uint128 gasPrice = uint128(vm.envOr("GAS_PRICE", uint256(2500000000000000000))); // Centrifuge Chain
        uint256 tokenPrice = vm.envOr("TOKEN_PRICE", uint256(178947400000000)); // CFG/ETH

        escrow = new Escrow{salt: salt}(deployer);
        routerEscrow = new Escrow{salt: keccak256(abi.encodePacked(salt, "escrow2"))}(deployer);
        root = new Root{salt: salt}(delay, deployer);
        restrictionManager = address(new RestrictionManager{salt: salt}(address(root), deployer));
        restrictedRedemptions = address(new RestrictedRedemptions{salt: salt}(address(root), address(escrow), deployer));
        trancheFactory = address(new TrancheFactory{salt: salt}(address(root), deployer));
        investmentManager = new InvestmentManager(address(root), address(escrow));
        vaultFactory = address(new ERC7540VaultFactory(address(root), address(investmentManager)));

        address[] memory vaultFactories = new address[](1);
        vaultFactories[0] = vaultFactory;

        poolManager = new PoolManager(address(escrow), trancheFactory, vaultFactories);
        gasService = new GasService(messageCost, proofCost, gasPrice, tokenPrice);
        gateway = new Gateway(root, gasService);
        messageProcessor = new MessageProcessor(gateway, poolManager, investmentManager, root, gasService, deployer);
        router = new VaultsRouter(address(routerEscrow), address(gateway), address(poolManager));
        guardian = new Guardian(adminSafe, root, gateway);

        _endorse();
        _rely();
        _file();
    }

    function _endorse() internal {
        root.endorse(address(router));
        root.endorse(address(escrow));
    }

    function _rely() internal {
        // Rely on PoolManager
        escrow.rely(address(poolManager));
        IAuth(vaultFactory).rely(address(poolManager));
        IAuth(trancheFactory).rely(address(poolManager));
        IAuth(investmentManager).rely(address(poolManager));
        IAuth(restrictionManager).rely(address(poolManager));
        IAuth(restrictedRedemptions).rely(address(poolManager));
        messageProcessor.rely(address(poolManager));

        // Rely on InvestmentManager
        messageProcessor.rely(address(investmentManager));

        // Rely on Root
        router.rely(address(root));
        poolManager.rely(address(root));
        investmentManager.rely(address(root));
        gateway.rely(address(root));
        gasService.rely(address(root));
        escrow.rely(address(root));
        routerEscrow.rely(address(root));
        IAuth(vaultFactory).rely(address(root));
        IAuth(trancheFactory).rely(address(root));
        IAuth(restrictionManager).rely(address(root));
        IAuth(restrictedRedemptions).rely(address(root));

        // Rely on guardian
        root.rely(address(guardian));
        gateway.rely(address(guardian));

        // Rely on gateway
        messageProcessor.rely(address(gateway));
        investmentManager.rely(address(gateway));
        poolManager.rely(address(gateway));
        gasService.rely(address(gateway));

        // Rely on others
        routerEscrow.rely(address(router));

        // Rely on messageProcessor
        gateway.rely(address(messageProcessor));
        poolManager.rely(address(messageProcessor));
        investmentManager.rely(address(messageProcessor));
        root.rely(address(messageProcessor));
        gasService.rely(address(messageProcessor));
    }

    function _file() public {
        poolManager.file("gateway", address(gateway));
        poolManager.file("sender", address(messageProcessor));

        investmentManager.file("poolManager", address(poolManager));
        investmentManager.file("gateway", address(gateway));
        investmentManager.file("sender", address(messageProcessor));

        gateway.file("payers", address(router), true);
        gateway.file("handler", address(messageProcessor));
    }

    function wire(IAdapter adapter) public {
        adapters.push(adapter);
        gateway.file("adapters", adapters);
        IAuth(address(adapter)).rely(address(root));
    }

    function removeDeployerAccess(address adapter, address deployer) public {
        IAuth(adapter).deny(deployer);
        IAuth(vaultFactory).deny(deployer);
        IAuth(trancheFactory).deny(deployer);
        IAuth(restrictionManager).deny(deployer);
        IAuth(restrictedRedemptions).deny(deployer);
        root.deny(deployer);
        investmentManager.deny(deployer);
        poolManager.deny(deployer);
        escrow.deny(deployer);
        routerEscrow.deny(deployer);
        gateway.deny(deployer);
        router.deny(deployer);
        gasService.deny(deployer);
    }
}
