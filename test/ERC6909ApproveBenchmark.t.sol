// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.28;

import {ERC6909Centrifuge} from "src/ERC6909/ERC6909Centrifuge.sol";
import "forge-std/Test.sol";

interface ERC6909TokenLike {
    function approve(address spender, uint256 id, uint256 amount) external returns (bool);
    function approveAlways(address spender, uint256 id, uint256 amount) external returns (bool);
    function approveOnDifferentValueEmitAlways(address spender, uint256 id, uint256 amount) external returns (bool);
    function mint(address _owner, string memory _tokenURI, uint256 _amount) external returns (uint256 _tokenId);
}

contract ERC6909ApproveBenchmark is Test {
    ERC6909TokenLike token;
    uint256 tokenId;
    address delegate;

    function setUp() public {
        delegate = makeAddr("Delegate");
        token = ERC6909TokenLike(address(new ERC6909Centrifuge(address(this))));
        tokenId = token.mint(address(this), "random/uri", 1);
        token.approve(delegate, tokenId, 1);
    }

    function testConditionalApprove() public {
        token.approve(delegate, tokenId, 1);
    }

    function testAlwaysApprove() public {
        token.approveAlways(delegate, tokenId, 1);
    }

    function testApproveOnDifferentValueEmitAlways() public {
        token.approveOnDifferentValueEmitAlways(delegate, tokenId, 1);
    }

    function testConditionalApproveWithDifferentValue() public {
        token.approve(delegate, tokenId, 2);
    }

    function testAlwaysApproveWithDifferentValue() public {
        token.approveAlways(delegate, tokenId, 2);
    }

    function testApproveOnDifferentValueEmitAlwaysWithDifferentValue() public {
        token.approveOnDifferentValueEmitAlways(delegate, tokenId, 2);
    }
}
