// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PoolId} from "src/types/PoolId.sol";
import {PoolLocker} from "src/PoolLocker.sol";
import {IPoolLocker} from "src/interfaces/IPoolLocker.sol";
import {IMulticall} from "src/interfaces/IMulticall.sol";
import {ICallEscrow} from "src/interfaces/ICallEscrow.sol";
import {Multicall} from "src/Multicall.sol";
import {CallEscrow} from "src/CallEscrow.sol";

uint64 constant NO_CALL_ESCROW = 42;
uint64 constant WITH_CALL_ESCROW = 43;

contract MockPoolManager is PoolLocker {
    PoolId public wasUnlockWithPool;
    bool public wasLock;
    ICallEscrow callEscrow;

    constructor(IMulticall multicall, ICallEscrow callEscrow_) PoolLocker(multicall) {
        callEscrow = callEscrow_;
    }

    function poolLockedMethod() external view poolUnlocked returns (PoolId, address) {
        return (unlockedPoolId(), msg.sender);
    }

    function _beforeUnlock(PoolId poolId) internal override returns (ICallEscrow) {
        wasUnlockWithPool = poolId;
        if (PoolId.unwrap(poolId) == 42) {
            return ICallEscrow(address(0));
        }
        return callEscrow;
    }

    function _beforeLock() internal override {
        wasLock = true;
    }
}

contract PoolLockerTest is Test {
    PoolId constant POOL_A = PoolId.wrap(NO_CALL_ESCROW);
    PoolId constant POOL_B = PoolId.wrap(WITH_CALL_ESCROW); // Has escrow

    Multicall multicall = new Multicall();
    ICallEscrow callEscrow = new CallEscrow(address(this));
    MockPoolManager poolManager = new MockPoolManager(multicall, callEscrow);

    function testUnlockedMethod() public {
        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(address(poolManager), abi.encodeWithSelector(poolManager.poolLockedMethod.selector));

        bytes[] memory results = poolManager.execute(POOL_A, calls);

        (PoolId poolId, address sender) = abi.decode(results[0], (PoolId, address));

        assertEq(PoolId.unwrap(poolId), PoolId.unwrap(POOL_A));
        assertEq(sender, address(multicall));
        assertEq(PoolId.unwrap(poolManager.wasUnlockWithPool()), PoolId.unwrap(POOL_A));
        assertEq(poolManager.wasLock(), true);
    }

    function testUnlockedMethodWithCallEscrow() public {
        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(address(poolManager), abi.encodeWithSelector(poolManager.poolLockedMethod.selector));

        bytes[] memory results = poolManager.execute(POOL_B, calls);

        (, address sender) = abi.decode(results[0], (PoolId, address));

        assertEq(sender, address(callEscrow));
    }

    function testErrPoolAlreadyUnlocked() public {
        IMulticall.Call[] memory innerCalls = new IMulticall.Call[](1);
        innerCalls[0] =
            IMulticall.Call(address(poolManager), abi.encodeWithSelector(poolManager.poolLockedMethod.selector));

        IMulticall.Call[] memory calls = new IMulticall.Call[](1);
        calls[0] = IMulticall.Call(
            address(poolManager), abi.encodeWithSelector(poolManager.execute.selector, POOL_A, innerCalls)
        );

        vm.expectRevert(IPoolLocker.PoolAlreadyUnlocked.selector);
        poolManager.execute(POOL_A, calls);
    }

    function testErrPoolLocked() public {
        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.poolLockedMethod();
    }
}
