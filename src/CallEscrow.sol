// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ICallEscrow} from "src/interfaces/ICallEscrow.sol";
import {Auth} from "src/Auth.sol";

import "forge-std/Test.sol";

contract CallEscrow is Auth, ICallEscrow {
    constructor(address deployer) Auth(deployer) {}

    /// @inheritdoc ICallEscrow
    function doCall(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = target.call(data);

        // Forward the error happened in target.call().
        if (!success) {
            assembly {
                // Reverting the error originated in the above call.
                // First 32 bytes contains the size of the array, rest the error data
                revert(add(result, 32), mload(result))
            }
        }

        return result;
    }
}
