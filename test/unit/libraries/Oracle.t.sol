// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "src/Oracle.sol";
import "src/interfaces/IERC7726.sol";

contract Contract {}

contract TestOracle is Test {
    address constant FEEDER = address(1);
    bytes32 constant SALT = bytes32(uint256(42));

    address CURR_A = address(new Contract()); //ERC20 contract address => 6 decimals
    address CURR_B = address(this); // Contract address => 18 decimals
    address CURR_C = address(123); // Non contract address => 18 decimals

    OracleFactory factory = new OracleFactory();

    function testDeploy() public {
        vm.expectEmit();
        emit IOracleFactory.NewOracleDeployed(factory.getAddress(FEEDER, SALT));

        factory.deploy(FEEDER, SALT);
    }

    function testSetQuote() public {
        IOracle oracle = factory.deploy(FEEDER, SALT);

        vm.expectEmit();
        vm.warp(1 days);
        emit IOracle.NewQuoteSet(CURR_A, CURR_B, 100, 1 days);

        vm.prank(FEEDER);
        oracle.setQuote(CURR_A, CURR_B, 100);
    }

    function testGetQuoteERC20() public {
        IOracle oracle = factory.deploy(address(this), SALT);
        oracle.setQuote(CURR_A, CURR_B, 100);

        vm.mockCall(CURR_A, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode(uint8(6)));
        assertEq(oracle.getQuote(5 * 10 ** 6, CURR_A, CURR_B), 500);
    }

    function testGetQuoteNonERC20Contract() public {
        IOracle oracle = factory.deploy(address(this), SALT);
        oracle.setQuote(CURR_B, CURR_A, 100);

        assertEq(oracle.getQuote(5 * 10 ** 18, CURR_B, CURR_A), 500);
    }

    function testGetQuoteNonContract() public {
        IOracle oracle = factory.deploy(address(this), SALT);
        oracle.setQuote(CURR_C, CURR_A, 100);

        assertEq(oracle.getQuote(5 * 10 ** 18, CURR_C, CURR_A), 500);
    }

    function testGetQuoteWithErrInERC20() public {
        IOracle oracle = factory.deploy(address(this), SALT);
        oracle.setQuote(CURR_A, CURR_B, 100);

        vm.mockCallRevert(CURR_A, abi.encodeWithSelector(IERC20.decimals.selector), abi.encode("error"));
        assertEq(oracle.getQuote(5 * 10 ** 18, CURR_A, CURR_B), 500);
    }

    function testNonFeeder() public {
        IOracle oracle = factory.deploy(FEEDER, SALT);

        vm.expectRevert(abi.encodeWithSelector(IOracle.NotValidFeeder.selector));
        oracle.setQuote(CURR_A, CURR_B, 100);
    }

    function testNeverFed() public {
        IOracle oracle = factory.deploy(address(this), SALT);

        vm.expectRevert(abi.encodeWithSelector(IOracle.NoQuote.selector));
        oracle.getQuote(1, CURR_A, CURR_B);
    }
}
