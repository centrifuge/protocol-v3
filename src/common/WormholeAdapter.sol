// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";
import {
    IWormholeAdapter,
    IAdapter,
    IWormholeRelayer,
    IWormholeReceiver,
    WormholeSource,
    WormholeDestination
} from "src/common/interfaces/IWormholeAdapter.sol";

/// @title  Wormhole Adapter
/// @notice Routing contract that integrates with the Wormhole Relayer service
contract WormholeAdapter is Auth, IWormholeAdapter {
    using CastLib for bytes32;

    uint16 public immutable refundChain;
    IMessageHandler public immutable gateway;
    IWormholeRelayer public immutable relayer;

    mapping(uint16 wormholeId => WormholeSource) public sources;
    mapping(uint16 centrifugeChainId => WormholeDestination) public destinations;

    constructor(IMessageHandler gateway_, address relayer_, uint16 refundChain_, address deployer) Auth(deployer) {
        gateway = gateway_;
        relayer = IWormholeRelayer(relayer_);
        refundChain = refundChain_;
    }

    // --- Administrative ---
    /// @inheritdoc IWormholeAdapter
    function file(bytes32 what, uint16 centrifugeChainId, uint16 wormholeId, address addr) external auth {
        if (what == "sources") sources[wormholeId] = WormholeSource(centrifugeChainId, addr);
        else if (what == "destinations") destinations[centrifugeChainId] = WormholeDestination(wormholeId, addr);
        else revert FileUnrecognizedParam();
        emit File(what, centrifugeChainId, wormholeId, addr);
    }

    // --- Incoming ---
    /// @inheritdoc IWormholeReceiver
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, /* additionalVaas */
        bytes32 sourceAddress,
        uint16 sourceWormholeId,
        bytes32 /* deliveryHash */
    ) external payable {
        WormholeSource memory source = sources[sourceWormholeId];
        require(source.addr == sourceAddress.toAddressLeftPadded(), InvalidSource());
        require(msg.sender == address(relayer), NotWormholeRelayer());

        gateway.handle(source.centrifugeChainId, payload);
    }

    // --- Outgoing ---
    /// @inheritdoc IAdapter
    function send(uint16 centrifugeChainId, bytes calldata payload, uint256 gasLimit, address refund)
        external
        payable
    {
        require(msg.sender == address(gateway), NotGateway());
        WormholeDestination memory destination = destinations[centrifugeChainId];
        require(destination.wormholeId != 0, UnknownChainId());

        relayer.sendPayloadToEvm{value: msg.value}(
            destination.wormholeId, destination.addr, payload, 0, gasLimit, refundChain, refund
        );
    }

    /// @inheritdoc IAdapter
    function estimate(uint16 centrifugeChainId, bytes calldata, uint256 gasLimit)
        public
        view
        returns (uint256 nativePriceQuote)
    {
        (nativePriceQuote,) = relayer.quoteEVMDeliveryPrice(destinations[centrifugeChainId].wormholeId, 0, gasLimit);
    }
}
