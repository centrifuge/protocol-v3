// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {IFreezable} from "./interfaces/IFreezable.sol";
import {IMemberlist} from "./interfaces/IMemberlist.sol";
import {UpdateRestrictionType, UpdateRestrictionMessageLib} from "./libraries/UpdateRestrictionMessageLib.sol";

import {Auth} from "../misc/Auth.sol";
import {CastLib} from "../misc/libraries/CastLib.sol";
import {BytesLib} from "../misc/libraries/BytesLib.sol";
import {IERC165} from "../misc/interfaces/IERC7575.sol";
import {BitmapLib} from "../misc/libraries/BitmapLib.sol";

import {IRoot} from "../common/interfaces/IRoot.sol";
import {ITransferHook, HookData, ESCROW_HOOK_ID} from "../common/interfaces/ITransferHook.sol";

import {IShareToken} from "../spoke/interfaces/IShareToken.sol";

/// @title  Full Restrictions
/// @notice Hook implementation that:
///         * Requires adding accounts to the memberlist before they can receive tokens
///         * Supports freezing accounts which blocks transfers both to and from them
///
/// @dev    The first 8 bytes (uint64) of hookData is used for the memberlist valid until date,
///         the last bit is used to denote whether the account is frozen.
contract FullRestrictions is Auth, IMemberlist, IFreezable, ITransferHook {
    using BitmapLib for *;
    using UpdateRestrictionMessageLib for *;
    using BytesLib for bytes;
    using CastLib for bytes32;

    /// @dev Least significant bit
    uint8 public constant FREEZE_BIT = 0;

    IRoot public immutable root;

    constructor(address root_, address deployer) Auth(deployer) {
        root = IRoot(root_);
    }

    //----------------------------------------------------------------------------------------------
    // Callback from share token
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc ITransferHook
    function onERC20Transfer(address from, address to, uint256 value, HookData calldata hookData)
        external
        virtual
        returns (bytes4)
    {
        require(checkERC20Transfer(from, to, value, hookData), TransferBlocked());
        return ITransferHook.onERC20Transfer.selector;
    }

    /// @inheritdoc ITransferHook
    function onERC20AuthTransfer(
        address, /* sender */
        address, /* from */
        address, /* to */
        uint256, /* value */
        HookData calldata /* hookData */
    ) external pure returns (bytes4) {
        return ITransferHook.onERC20AuthTransfer.selector;
    }

    /// @inheritdoc ITransferHook
    function checkERC20Transfer(address from, address to, uint256, /* value */ HookData calldata hookData)
        public
        view
        returns (bool)
    {
        if (uint128(hookData.from).getBit(FREEZE_BIT) == true && !root.endorsed(from) && from != ESCROW_HOOK_ID) {
            // Source is frozen and not endorsed
            return false;
        }

        if (root.endorsed(to) || to == address(0) || to == ESCROW_HOOK_ID) {
            // Destination is endorsed or escrow and source was already checked, so the transfer is allowed
            return true;
        }

        uint128 toHookData = uint128(hookData.to);
        if (toHookData.getBit(FREEZE_BIT) == true) {
            // Destination is frozen
            return false;
        }

        if (toHookData >> 64 < block.timestamp) {
            // Destination is not a member
            return false;
        }

        return true;
    }

    //----------------------------------------------------------------------------------------------
    // Restriction updates
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc ITransferHook
    function updateRestriction(address token, bytes memory payload) external auth {
        UpdateRestrictionType updateId = payload.updateRestrictionType();

        if (updateId == UpdateRestrictionType.Member) {
            UpdateRestrictionMessageLib.UpdateRestrictionMember memory m = payload.deserializeUpdateRestrictionMember();
            updateMember(token, m.user.toAddress(), m.validUntil);
        } else if (updateId == UpdateRestrictionType.Freeze) {
            UpdateRestrictionMessageLib.UpdateRestrictionFreeze memory m = payload.deserializeUpdateRestrictionFreeze();
            freeze(token, m.user.toAddress());
        } else if (updateId == UpdateRestrictionType.Unfreeze) {
            UpdateRestrictionMessageLib.UpdateRestrictionUnfreeze memory m =
                payload.deserializeUpdateRestrictionUnfreeze();
            unfreeze(token, m.user.toAddress());
        } else {
            revert InvalidUpdate();
        }
    }

    /// @inheritdoc IFreezable
    function freeze(address token, address user) public auth {
        require(user != address(0), CannotFreezeZeroAddress());
        require(!root.endorsed(user), EndorsedUserCannotBeFrozen());

        uint128 hookData = uint128(IShareToken(token).hookDataOf(user));
        IShareToken(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, true)));

        emit Freeze(token, user);
    }

    /// @inheritdoc IFreezable
    function unfreeze(address token, address user) public auth {
        uint128 hookData = uint128(IShareToken(token).hookDataOf(user));
        IShareToken(token).setHookData(user, bytes16(hookData.setBit(FREEZE_BIT, false)));

        emit Unfreeze(token, user);
    }

    /// @inheritdoc IFreezable
    function isFrozen(address token, address user) public view returns (bool) {
        return uint128(IShareToken(token).hookDataOf(user)).getBit(FREEZE_BIT);
    }

    /// @inheritdoc IMemberlist
    function updateMember(address token, address user, uint64 validUntil) public auth {
        require(block.timestamp <= validUntil, InvalidValidUntil());
        require(!root.endorsed(user), EndorsedUserCannotBeUpdated());

        uint128 hookData = uint128(validUntil) << 64;
        hookData.setBit(FREEZE_BIT, isFrozen(token, user));
        IShareToken(token).setHookData(user, bytes16(hookData));

        emit UpdateMember(token, user, validUntil);
    }

    /// @inheritdoc IMemberlist
    function isMember(address token, address user) external view returns (bool isValid, uint64 validUntil) {
        validUntil = abi.encodePacked(IShareToken(token).hookDataOf(user)).toUint64(0);
        isValid = validUntil >= block.timestamp;
    }

    //----------------------------------------------------------------------------------------------
    // ERC-165
    //----------------------------------------------------------------------------------------------

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ITransferHook).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
}
