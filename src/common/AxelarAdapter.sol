// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IAxelarAdapter, IAdapter, IAxelarGateway, IAxelarGasService} from "src/common/interfaces/IAxelarAdapter.sol";
import {Auth} from "src/misc/Auth.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";

/// @title  Axelar Adapter
/// @notice Routing contract that integrates with an Axelar Gateway
contract AxelarAdapter is Auth, IAxelarAdapter {
    string public constant CENTRIFUGE_ID = "centrifuge";
    string public constant CENTRIFUGE_AXELAR_EXECUTABLE = "0xc1757c6A0563E37048869A342dF0651b9F267e41";

    IMessageHandler public immutable gateway;
    bytes32 public immutable centrifugeIdHash;
    bytes32 public immutable centrifugeAddressHash;
    IAxelarGateway public immutable axelarGateway;
    IAxelarGasService public immutable axelarGasService;

    constructor(IMessageHandler gateway_, address axelarGateway_, address axelarGasService_) Auth(msg.sender) {
        gateway = gateway_;
        axelarGateway = IAxelarGateway(axelarGateway_);
        axelarGasService = IAxelarGasService(axelarGasService_);

        centrifugeIdHash = keccak256(bytes(CENTRIFUGE_ID));
        centrifugeAddressHash = keccak256(bytes("0x7369626CEF070000000000000000000000000000"));
    }

    // --- Incoming ---
    /// @inheritdoc IAxelarAdapter
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) public {
        require(keccak256(bytes(sourceChain)) == centrifugeIdHash, InvalidChain());
        require(keccak256(bytes(sourceAddress)) == centrifugeAddressHash, InvalidAddress());
        require(
            axelarGateway.validateContractCall(commandId, sourceChain, sourceAddress, keccak256(payload)),
            NotApprovedByAxelarGateway()
        );

        //TODO extract the Id from the storage of this contract
        gateway.handle(0, payload);
    }

    // --- Outgoing ---
    function send(uint32, /*chainId*/ bytes calldata payload) public {
        //TODO (chainName, chainExecutable) = chainConfig[chainId];
        require(msg.sender == address(gateway), NotGateway());
        axelarGateway.callContract(CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload);
    }

    /// @inheritdoc IAdapter
    function estimate(uint32, /*chainId*/ bytes calldata payload, uint256 gasLimit) public view returns (uint256) {
        return
            axelarGasService.estimateGasFee(CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload, gasLimit, bytes(""));
    }

    /// @inheritdoc IAdapter
    function pay(uint32, /*chainId*/ bytes calldata payload, address refund) public payable {
        //TODO (chainName, chainExecutable) = chainConfig[chainId];
        axelarGasService.payNativeGasForContractCall{value: msg.value}(
            address(this), CENTRIFUGE_ID, CENTRIFUGE_AXELAR_EXECUTABLE, payload, refund
        );
    }
}
