// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IMerkleProofManager {
    event ManageRootUpdated(address indexed strategist, bytes32 oldRoot, bytes32 newRoot);
    event CallsExecuted(uint256 callsMade);

    error InsufficientBalance();
    error CallFailed();
    error InvalidManageProofLength();
    error InvalidTargetDataLength();
    error InvalidValuesLength();
    error InvalidDecodersAndSanitizersLength();
    error FailedToVerifyManageProof(address target, bytes targetData, uint256 value);
    error NotAStrategist();

    function execute(
        bytes32[][] calldata proofs,
        address[] calldata decoders,
        address[] calldata targets,
        bytes[] calldata targetData,
        uint256[] calldata values
    ) external;
}
