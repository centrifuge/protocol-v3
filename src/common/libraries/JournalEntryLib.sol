// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {D18, d18} from "src/misc/types/D18.sol";
import {AccountId} from "src/common/types/AccountId.sol";
import {BytesLib} from "src/misc/libraries/BytesLib.sol";

struct JournalEntry {
    uint128 amount;
    AccountId accountId;
}

struct Meta {
    JournalEntry[] debits;
    JournalEntry[] credits;
}

library JournalEntryLib {
    using BytesLib for bytes;

    /**
     * @dev Packs an array of JournalEntry into a tight bytes array of length (entries.length * 20).
     *      Each entry = 20 bytes:
     *         - amount (uint128) is stored in 16 bytes (big-endian)
     *         - accountId (uint32) in 4 bytes (big-endian)
     */
    function toBytes(JournalEntry[] memory entries) internal pure returns (bytes memory) {
        // Each entry = 20 bytes
        bytes memory packed = new bytes(entries.length * 20);

        for (uint256 i = 0; i < entries.length; i++) {
            uint256 offset = i * 20;

            // Store `amount` as 16 bytes (big-endian)
            uint128 amount = entries[i].amount;
            for (uint256 j = 0; j < 16; j++) {
                // shift right by 8*(15-j) to get the correct byte
                packed[offset + j] = bytes1(uint8(amount >> (8 * (15 - j))));
            }

            // Store `accountId` as 4 bytes (big-endian)
            uint32 accountId = entries[i].accountId.raw();
            for (uint256 j = 0; j < 4; j++) {
                packed[offset + 16 + j] = bytes1(uint8(accountId >> (8 * (3 - j))));
            }
        }

        return packed;
    }

    /**
     * @dev Decodes a big-endian, tight-encoded bytes array back into an array of JournalEntry.
     *      The array length must be a multiple of 20 bytes.
     */
    function toJournalEntries(bytes memory _bytes, uint256 _start, uint16 _length)
        internal
        pure
        returns (JournalEntry[] memory)
    {
        require(_bytes.length >= _start + _length, "decodeJournalEntries_outOfBounds");
        require(_length % 20 == 0, "decodeJournalEntries_invalidLength");

        uint256 count = _length / 20;

        JournalEntry[] memory entries = new JournalEntry[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 offset = _start + i * 20;

            uint128 amount = _bytes.toUint128(offset);
            uint32 accountId = _bytes.toUint32(offset + 16);

            entries[i] = JournalEntry({amount: amount, accountId: AccountId.wrap(accountId)});
        }

        return entries;
    }
}
