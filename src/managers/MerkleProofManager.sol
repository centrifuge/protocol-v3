// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Auth} from "src/misc/Auth.sol";
import {Recoverable} from "src/misc/Recoverable.sol";
import {MathLib} from "src/misc/libraries/MathLib.sol";
import {MerkleProofLib} from "src/misc/libraries/MerkleProofLib.sol";

import {PoolId} from "src/common/types/PoolId.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {MessageLib, UpdateContractType} from "src/common/libraries/MessageLib.sol";

import {IBalanceSheet} from "src/vaults/interfaces/IBalanceSheet.sol";
import {IUpdateContract} from "src/vaults/interfaces/IUpdateContract.sol";

/// @title MerkleProofManager
/// @author Modified from Boring Vaults
/// (https://github.com/Se7en-Seas/boring-vault/blob/main/src/base/Roles/ManagerWithMerkleVerification.sol)
contract MerkleProofManager is Auth, Recoverable, IUpdateContract {
    using MathLib for uint256;

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

    PoolId public immutable poolId;
    IBalanceSheet public immutable balanceSheet;

    mapping(address strategist => bytes32 root) public policy;

    constructor(PoolId poolId_, IBalanceSheet balanceSheet_, address deployer) Auth(deployer) {
        poolId = poolId_;
        balanceSheet = balanceSheet_;
    }

    //----------------------------------------------------------------------------------------------
    // Owner actions
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IUpdateContract
    function update(PoolId, /* poolId */ ShareClassId, /* scId */ bytes calldata payload) external auth {
        uint8 kind = uint8(MessageLib.updateContractType(payload));

        // TODO: add updatePolicy
    }

    //----------------------------------------------------------------------------------------------
    // Strategist actions
    //----------------------------------------------------------------------------------------------

    function execute(
        bytes32[][] calldata proofs,
        address[] calldata decoders,
        address[] calldata targets,
        bytes[] calldata targetData,
        uint256[] calldata values
    ) external {
        uint256 targetsLength = targets.length;
        require(targetsLength == proofs.length, InvalidManageProofLength());
        require(targetsLength == decoders.length, InvalidDecodersAndSanitizersLength());
        require(targetsLength == targetData.length, InvalidTargetDataLength());
        require(targetsLength == values.length, InvalidValuesLength());

        bytes32 strategistPolicy = policy[msg.sender];
        require(strategistPolicy != bytes32(0), NotAStrategist());

        for (uint256 i; i < targetsLength; ++i) {
            _verifyCallData(strategistPolicy, proofs[i], decoders[i], targets[i], values[i], targetData[i]);
            _functionCallWithValue(targets[i], targetData[i], values[i]);
        }

        emit CallsExecuted(targetsLength);
    }

    //----------------------------------------------------------------------------------------------
    // ERC-165
    //----------------------------------------------------------------------------------------------

    // /// @inheritdoc IERC165
    // function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
    //     return interfaceId == type(IERC165).interfaceId;
    // }

    //----------------------------------------------------------------------------------------------
    // Helper methods
    //----------------------------------------------------------------------------------------------

    function _verifyCallData(
        bytes32 root,
        bytes32[] calldata proof,
        address decoder,
        address target,
        uint256 value,
        bytes calldata targetData
    ) internal view {
        bytes memory addresses = abi.decode(_functionStaticCall(decoder, targetData), (bytes));
        bytes32 leaf = keccak256(abi.encodePacked(decoder, target, value > 0, bytes4(targetData), addresses));
        require(MerkleProofLib.verify(proof, root, leaf), FailedToVerifyManageProof(target, targetData, value));
    }

    function _functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returnData) = target.staticcall(data);
        require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), CallFailed());

        return returnData;
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        require(address(this).balance >= value, InsufficientBalance());

        (bool success, bytes memory returnData) = target.call{value: value}(data);
        require(success && (returnData.length == 0 || abi.decode(returnData, (bool))), CallFailed());

        return returnData;
    }
}
