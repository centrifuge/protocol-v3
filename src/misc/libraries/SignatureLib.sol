// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

interface IERC1271 {
    function isValidSignature(bytes32, bytes memory) external view returns (bytes4);
}

/// @title  Signature Lib
library SignatureLib {
    error InvalidSigner();

    function isValidSignature(address signer, bytes32 digest, bytes memory signature)
        internal
        view
        returns (bool valid)
    {
        require(signer != address(0), InvalidSigner());

        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            if (signer == ecrecover(digest, v, r, s)) {
                return true;
            }
        }

        if (signer.code.length > 0) {
            (bool success, bytes memory result) =
                signer.staticcall(abi.encodeCall(IERC1271.isValidSignature, (digest, signature)));
            valid =
                (success && result.length == 32 && abi.decode(result, (bytes4)) == IERC1271.isValidSignature.selector);
        }
    }
}
