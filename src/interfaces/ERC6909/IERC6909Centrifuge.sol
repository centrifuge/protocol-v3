// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {IERC6909} from "src/interfaces/ERC6909/IERC6909.sol";
import {IERC6909URIExtension} from "src/interfaces/ERC6909/IERC6909URIExtension.sol";

interface IERC6909Centrifuge is IERC6909, IERC6909URIExtension {
    /// Errors
    error UnknownTokenId(address owner, uint256 tokenId);
    error EmptyOwner();
    error EmptyAmount();
    error EmptyURI();
    error MaxSupplyReached();
    error Burn_InsufficientBalance(address owner, uint256 id);
    error LessThanMinimalDecimal(uint8 minimal, uint8 actual);

    /// Functions
    /// @notice             Get total supply of a given token.
    /// @dev                To increase the total supply call mint(address _owner, uint256 _tokenId, uint256 _amount).
    ///                     The total supply will be increased by _amount and cannot go over type(uint256).max.
    /// @param _tokenId     Token Id.
    function totalSupply(uint256 _tokenId) external returns (uint256);

    /// @notice             Provide URI for a specific tokenId.
    /// @param _tokenId     Token Id.
    /// @param _URI         URI to a document defining the collection as a whole.
    function setTokenURI(uint256 _tokenId, string memory _URI) external;

    /// @dev                Optional method to set up the contract URI if needed.
    /// @param _URI         URI to a document defining the collection as a whole.
    function setContractURI(string memory _URI) external;

    /// @notice             Mint new tokens for a given _owner and sets _tokenURI.
    /// @dev                For non-fungible tokens, call with amount = 1, for fungible it could be any amount.
    ///                     TokenId is auto incremented by one.
    ///
    /// @param _owner       Creates supply of a given _tokenId by _amount for _owner.
    /// @param _tokenURI    URI fortestBurningToken the newly minted token.
    /// @param _amount      Amount of newly created supply.
    /// @return _tokenId    Id of the newly minted token.
    function mint(address _owner, string memory _tokenURI, uint256 _amount) external returns (uint256 _tokenId);

    /// @dev                Used to increase the supply for a given _tokenId.
    ///
    /// @param _owner       Creates supply of a given _tokenId by _amount for _owner.
    /// @param _tokenId     The token id  of the item which supply will be increased.
    /// @param _amount      Amount by which the supply for _tokenId of _owner is increased by.
    /// @return             New supply of item with _tokenId.
    function mint(address _owner, uint256 _tokenId, uint256 _amount) external returns (uint256);

    /// @notice             Destroy supply of a given _tokenId by _amount.
    /// @dev                The msg.sender MUST be the owner.
    ///
    /// @param _tokenId     Item which have reduced supply.
    /// @param _amount      Amount to be burnt.
    /// @return             Amount that is left after burning the _amount tokens.
    function burn(uint256 _tokenId, uint256 _amount) external returns (uint256);
}
