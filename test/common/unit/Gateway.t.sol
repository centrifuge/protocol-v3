// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "forge-std/Test.sol";

import {IAuth} from "src/misc/interfaces/IAuth.sol";

import {Gateway, IRoot, IGasService, IGateway, MessageProofLib} from "src/common/Gateway.sol";
import {IAdapter} from "src/common/interfaces/IAdapter.sol";
import {PoolId} from "src/common/types/PoolId.sol";

import {BytesLib} from "src/misc/libraries/BytesLib.sol";

import {IMessageProperties} from "src/common/interfaces/IMessageProperties.sol";
import {IMessageProcessor} from "src/common/interfaces/IMessageProcessor.sol";
import {IMessageHandler} from "src/common/interfaces/IMessageHandler.sol";

// -----------------------------------------
//     MESSAGE MOCKING
// -----------------------------------------

PoolId constant POOL_A = PoolId.wrap(23);
PoolId constant POOL_0 = PoolId.wrap(0);

enum MessageKind {
    _Invalid,
    _MessageProof,
    Recovery,
    WithPool0,
    WithPoolA10,
    WithPoolA10Fail,
    WithPoolA15
}

function length(MessageKind kind) pure returns (uint16) {
    if (kind == MessageKind.WithPool0) return 5;
    if (kind == MessageKind.WithPoolA10) return 10;
    if (kind == MessageKind.WithPoolA10Fail) return 10;
    if (kind == MessageKind.WithPoolA15) return 15;
    return 2;
}

function asBytes(MessageKind kind) pure returns (bytes memory) {
    bytes memory encoded = new bytes(length(kind));
    encoded[0] = bytes1(uint8(kind));
    return encoded;
}

using {asBytes, length} for MessageKind;

// A MessageLib agnostic processor
contract MockProcessor is IMessageProperties {
    using BytesLib for bytes;

    error HandleError();

    mapping(uint16 => bytes[]) public processed;
    bool shouldNotFail;

    function disableFailure() public {
        shouldNotFail = true;
    }

    function handle(uint16 centrifugeId, bytes memory payload) external {
        if (payload.toUint8(0) == uint8(MessageKind.WithPoolA10Fail) && !shouldNotFail) {
            revert HandleError();
        }
        processed[centrifugeId].push(payload);
    }

    function count(uint16 centrifugeId) external view returns (uint256) {
        return processed[centrifugeId].length;
    }

    function isMessageRecovery(bytes calldata message) external pure returns (bool) {
        return message.toUint8(0) == uint8(MessageKind.Recovery);
    }

    function messageLength(bytes calldata message) external pure returns (uint16) {
        return MessageKind(message.toUint8(0)).length();
    }

    function messagePoolId(bytes calldata message) external pure returns (PoolId) {
        if (message.toUint8(0) == uint8(MessageKind.WithPool0)) return POOL_0;
        if (message.toUint8(0) == uint8(MessageKind.WithPoolA10)) return POOL_A;
        if (message.toUint8(0) == uint8(MessageKind.WithPoolA15)) return POOL_A;
        revert("Unreachable: message never asked for pool");
    }
}

// -----------------------------------------
//     GATEWAY EXTENSION
// -----------------------------------------

contract GatewayExt is Gateway {
    constructor(uint16 localCentrifugeId_, IRoot root_, IGasService gasService_)
        Gateway(localCentrifugeId_, root_, gasService_)
    {}

    function activeAdapters(uint16 centrifugeId, IAdapter adapter) public view returns (IGateway.Adapter memory) {
        return _activeAdapters[centrifugeId][adapter];
    }
}

// -----------------------------------------
//     GATEWAY TESTS
// -----------------------------------------

contract GatewayTest is Test {
    uint16 constant LOCAL_CENTRIFUGE_ID = 23;
    uint16 constant REMOTE_CENTRIFUGE_ID = 24;

    uint256 constant FIRST_ADAPTER_ESTIMATE = 1.5 gwei;
    uint256 constant SECOND_ADAPTER_ESTIMATE = 1 gwei;
    uint256 constant THIRD_ADAPTER_ESTIMATE = 0.5 gwei;
    uint256 constant MESSAGE_GAS_LIMIT = 10.0 gwei;
    uint256 constant MAX_BATCH_SIZE = 100.0 gwei;

    IGasService gasService = IGasService(makeAddr("GasService"));
    IRoot root = IRoot(makeAddr("Root"));
    IAdapter batchAdapter = IAdapter(makeAddr("BatchAdapter"));
    IAdapter proofAdapter1 = IAdapter(makeAddr("ProofAdapter1"));
    IAdapter proofAdapter2 = IAdapter(makeAddr("ProofAdapter2"));
    IAdapter[] oneAdapter;
    IAdapter[] threeAdapters;

    address immutable ANY = makeAddr("ANY");

    MockProcessor processor = new MockProcessor();
    GatewayExt gateway = new GatewayExt(LOCAL_CENTRIFUGE_ID, IRoot(address(root)), IGasService(address(gasService)));

    function _mockGasService() internal {
        vm.mockCall(
            address(gasService), abi.encodeWithSelector(IGasService.gasLimit.selector), abi.encode(MESSAGE_GAS_LIMIT)
        );
        vm.mockCall(
            address(gasService), abi.encodeWithSelector(IGasService.maxBatchSize.selector), abi.encode(MAX_BATCH_SIZE)
        );
    }

    function _mockPause(bool isPaused) internal {
        vm.mockCall(address(root), abi.encodeWithSelector(IRoot.paused.selector), abi.encode(isPaused));
    }

    function assertVotes(bytes memory message, uint16 r1, uint16 r2, uint16 r3) internal view {
        uint16[8] memory votes = gateway.votes(REMOTE_CENTRIFUGE_ID, keccak256(message));
        assertEq(votes[0], r1);
        assertEq(votes[1], r2);
        assertEq(votes[2], r3);
    }

    function setUp() public {
        oneAdapter.push(batchAdapter);
        threeAdapters.push(batchAdapter);
        threeAdapters.push(proofAdapter1);
        threeAdapters.push(proofAdapter2);
        gateway.file("processor", address(processor));

        _mockPause(false);
        _mockGasService();
    }

    function testConstructor() public view {
        assertEq(gateway.localCentrifugeId(), LOCAL_CENTRIFUGE_ID);
        assertEq(address(gateway.root()), address(root));
        assertEq(address(gateway.gasService()), address(gasService));

        (, address refund) = gateway.subsidy(POOL_0);
        assertEq(refund, address(gateway));

        assertEq(gateway.wards(address(this)), 1);
    }

    function testMessageProofLib(bytes32 hash_) public pure {
        assertEq(hash_, MessageProofLib.deserializeMessageProof(MessageProofLib.serializeMessageProof(hash_)));
    }
}

contract GatewayFileTest is GatewayTest {
    function testErrNotAuthorized() public {
        vm.prank(makeAddr("unauthorizedAddress"));
        vm.expectRevert(IAuth.NotAuthorized.selector);
        gateway.file("unknown", address(1));
    }

    function testErrFileUnrecognizedParam() public {
        vm.expectRevert(IGateway.FileUnrecognizedParam.selector);
        gateway.file("unknown", address(1));
    }

    function testGatewayFileSuccess() public {
        vm.expectEmit();
        emit IGateway.File("processor", address(23));
        gateway.file("processor", address(23));
        assertEq(address(gateway.processor()), address(23));

        gateway.file("gasService", address(42));
        assertEq(address(gateway.gasService()), address(42));
    }
}

contract GatewayFileAdaptersTest is GatewayTest {
    function testErrNotAuthorized() public {
        vm.prank(makeAddr("unauthorizedAddress"));
        vm.expectRevert(IAuth.NotAuthorized.selector);
        gateway.file("unknown", REMOTE_CENTRIFUGE_ID, new IAdapter[](0));
    }

    function testErrFileUnrecognizedParam() public {
        vm.expectRevert(IGateway.FileUnrecognizedParam.selector);
        gateway.file("unknown", REMOTE_CENTRIFUGE_ID, new IAdapter[](0));
    }

    function testErrEmptyAdapterFile() public {
        vm.expectRevert(IGateway.EmptyAdapterSet.selector);
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, new IAdapter[](0));
    }

    function testErrExceedsMax() public {
        IAdapter[] memory tooMuchAdapters = new IAdapter[](gateway.MAX_ADAPTER_COUNT() + 1);
        vm.expectRevert(IGateway.ExceedsMax.selector);
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, tooMuchAdapters);
    }

    function testErrNoDuplicatedAllowed() public {
        IAdapter[] memory duplicatedAdapters = new IAdapter[](2);
        duplicatedAdapters[0] = IAdapter(address(10));
        duplicatedAdapters[1] = IAdapter(address(10));

        vm.expectRevert(IGateway.NoDuplicatesAllowed.selector);
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, duplicatedAdapters);
    }

    function testGatewayFileAdaptersSuccess() public {
        vm.expectEmit();
        emit IGateway.File("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        assertEq(gateway.activeSessionId(REMOTE_CENTRIFUGE_ID), 0);
        assertEq(gateway.quorum(REMOTE_CENTRIFUGE_ID), threeAdapters.length);

        for (uint256 i; i < threeAdapters.length; i++) {
            IGateway.Adapter memory adapter = gateway.activeAdapters(REMOTE_CENTRIFUGE_ID, threeAdapters[i]);

            assertEq(adapter.id, i + 1);
            assertEq(adapter.quorum, threeAdapters.length);
            assertEq(adapter.activeSessionId, 0);
            assertEq(address(gateway.adapters(REMOTE_CENTRIFUGE_ID, i)), address(threeAdapters[i]));
        }
    }

    function testGatewayFileAdaptersAdvanceSession() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);
        assertEq(gateway.activeSessionId(REMOTE_CENTRIFUGE_ID), 0);

        // Using another chain uses a different active session counter
        gateway.file("adapters", LOCAL_CENTRIFUGE_ID, threeAdapters);
        assertEq(gateway.activeSessionId(LOCAL_CENTRIFUGE_ID), 0);

        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);
        assertEq(gateway.activeSessionId(REMOTE_CENTRIFUGE_ID), 1);
    }
}

contract GatewayReceiveTest is GatewayTest {
    function testGatewayReceiveSuccess() public {
        (bool success,) = address(gateway).call{value: 100}(new bytes(0));

        assertEq(success, true);

        (uint96 value,) = gateway.subsidy(POOL_0);
        assertEq(value, 100);

        assertEq(address(gateway).balance, 100);
    }
}

contract GatewayHandleTest is GatewayTest {
    function testErrPaused() public {
        _mockPause(true);
        vm.expectRevert(IGateway.Paused.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, new bytes(0));
    }

    function testErrInvalidAdapter() public {
        vm.expectRevert(IGateway.InvalidAdapter.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, new bytes(0));
    }

    function testErrNonProofAdapter() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        vm.prank(address(batchAdapter));
        vm.expectRevert(IGateway.NonProofAdapter.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, MessageProofLib.serializeMessageProof(bytes32("1")));
    }

    function testErrNonProofAdapterWithOneAdapter() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        vm.prank(address(batchAdapter));
        vm.expectRevert(IGateway.NonProofAdapter.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, MessageProofLib.serializeMessageProof(bytes32("1")));
    }

    function testErrNonBatchAdapter() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        vm.prank(address(proofAdapter1));
        vm.expectRevert(IGateway.NonBatchAdapter.selector);
        gateway.handle(REMOTE_CENTRIFUGE_ID, MessageKind.WithPool0.asBytes());
    }

    function testErrEmptyMessage() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        vm.prank(address(batchAdapter));
        vm.expectRevert("toUint8_outOfBounds");
        gateway.handle(REMOTE_CENTRIFUGE_ID, new bytes(0));
    }

    function testMessageSuccess() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory batch = MessageKind.WithPool0.asBytes();

        vm.prank(address(batchAdapter));
        vm.expectEmit();
        emit IGateway.ExecuteMessage(REMOTE_CENTRIFUGE_ID, batch);
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), batch);
    }

    function testMessageFailed() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory batch = MessageKind.WithPoolA10Fail.asBytes();

        vm.prank(address(batchAdapter));
        vm.expectEmit();
        emit IGateway.FailMessage(REMOTE_CENTRIFUGE_ID, batch, abi.encodeWithSignature("HandleError()"));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(batch)), 1);
    }

    function testMessageAndProofs() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));
        bytes32 batchId = keccak256(abi.encodePacked(REMOTE_CENTRIFUGE_ID, LOCAL_CENTRIFUGE_ID, batch));
        bytes32 proofId = keccak256(abi.encodePacked(REMOTE_CENTRIFUGE_ID, LOCAL_CENTRIFUGE_ID, proof));

        vm.prank(address(batchAdapter));
        vm.expectEmit();
        emit IGateway.ProcessBatch(REMOTE_CENTRIFUGE_ID, batchId, batch, batchAdapter);
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 1, 0, 0);

        vm.prank(address(proofAdapter1));
        vm.expectEmit();
        emit IGateway.ProcessProof(REMOTE_CENTRIFUGE_ID, proofId, keccak256(batch), proofAdapter1);
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 1, 1, 0);

        vm.prank(address(proofAdapter2));
        vm.expectEmit();
        emit IGateway.ProcessProof(REMOTE_CENTRIFUGE_ID, proofId, keccak256(batch), proofAdapter2);
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), batch);
        assertVotes(batch, 0, 0, 0);
    }

    function testSameMessageAndProofs() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch, 1, 0, 0);

        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch, 1, 1, 0);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 1), batch);
        assertVotes(batch, 0, 0, 0);
    }

    function testOtherMessageAndProofs() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);

        bytes memory batch2 = MessageKind.WithPoolA10.asBytes();
        bytes memory proof2 = MessageProofLib.serializeMessageProof(keccak256(batch2));

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch2);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch2, 1, 0, 0);

        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof2);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch2, 1, 1, 0);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof2);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 1), batch2);
        assertVotes(batch2, 0, 0, 0);
    }

    function testMessageAfterProofs() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));

        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 0, 1, 0);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 0, 1, 1);

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch, 0, 0, 0);
    }

    function testOneFasterAdapter() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 2, 0, 0);

        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 2, 1, 0);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch, 1, 0, 0);

        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 1);
        assertVotes(batch, 1, 1, 0);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertVotes(batch, 0, 0, 0);
    }

    function testVotesAfterNewSession() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        bytes memory batch = MessageKind.WithPool0.asBytes();
        bytes memory proof = MessageProofLib.serializeMessageProof(keccak256(batch));

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(proofAdapter1));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);

        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, threeAdapters);

        vm.prank(address(proofAdapter2));
        gateway.handle(REMOTE_CENTRIFUGE_ID, proof);
        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 0);
        assertVotes(batch, 0, 0, 1);
    }

    function testBatchProcessing() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory message1 = MessageKind.WithPoolA10.asBytes();
        bytes memory message2 = MessageKind.WithPoolA15.asBytes();
        bytes memory batch = abi.encodePacked(message1, message2);

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), message1);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 1), message2);
    }

    function testBatchWithFailingMessages() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory message1 = MessageKind.WithPoolA10.asBytes();
        bytes memory message2 = MessageKind.WithPoolA10Fail.asBytes();
        bytes memory message3 = MessageKind.WithPoolA15.asBytes();
        bytes memory batch = abi.encodePacked(message1, message2, message3);

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), message1);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 1), message3);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(message2)), 1);
    }

    function testMultipleSameFailingMessages() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory batch = MessageKind.WithPoolA10Fail.asBytes();

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(batch)), 2);
    }

    function testBatchWithMultipleSameFailingMessages() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory message = MessageKind.WithPoolA10Fail.asBytes();
        bytes memory batch = abi.encodePacked(message, message);

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(message)), 2);
    }
}

contract GatewayRetryTest is GatewayTest {
    function testErrPaused() public {
        _mockPause(true);
        vm.expectRevert(IGateway.Paused.selector);
        gateway.retry(REMOTE_CENTRIFUGE_ID, bytes(""));
    }

    function testErrNotFailedMessage() public {
        vm.expectRevert(IGateway.NotFailedMessage.selector);
        gateway.retry(REMOTE_CENTRIFUGE_ID, bytes("noMessage"));
    }

    function testRecoverFailingMessage() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory batch = MessageKind.WithPoolA10Fail.asBytes();

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        processor.disableFailure();

        vm.prank(ANY);
        emit IGateway.ExecuteMessage(REMOTE_CENTRIFUGE_ID, batch);
        gateway.retry(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(batch)), 0);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), batch);
    }

    function testRecoverMultipleFailingMessage() public {
        gateway.file("adapters", REMOTE_CENTRIFUGE_ID, oneAdapter);

        bytes memory batch = MessageKind.WithPoolA10Fail.asBytes();

        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(address(batchAdapter));
        gateway.handle(REMOTE_CENTRIFUGE_ID, batch);

        processor.disableFailure();

        vm.prank(ANY);
        gateway.retry(REMOTE_CENTRIFUGE_ID, batch);
        vm.prank(ANY);
        gateway.retry(REMOTE_CENTRIFUGE_ID, batch);

        assertEq(processor.count(REMOTE_CENTRIFUGE_ID), 2);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 0), batch);
        assertEq(processor.processed(REMOTE_CENTRIFUGE_ID, 1), batch);
        assertEq(gateway.failedMessages(REMOTE_CENTRIFUGE_ID, keccak256(batch)), 0);
    }
}
