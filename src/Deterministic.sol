// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

abstract contract Deterministic {
    function _previewAddress(address deployer, bytes32 salt, bytes memory bytecode)
        internal
        pure
        returns (address instance)
    {
        instance =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(bytecode))))));
    }
}
