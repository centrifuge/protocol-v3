// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PoolId} from "src/types/Domain.sol";
import {PoolLocker} from "src/PoolLocker.sol";
import {IPoolLocker} from "src/interfaces/IPoolLocker.sol";
import {IMulticall} from "src/interfaces/IMulticall.sol";
import {Multicall} from "src/Multicall.sol";

contract PoolManagerMock is PoolLocker {
    PoolId public wasUnlockWithPool;
    bool public wasLock;

    constructor(IMulticall multicall) PoolLocker(multicall) {}

    function poolRelatedMethod() external view poolUnlocked returns (PoolId) {
        return unlockedPoolId();
    }

    function _beforeUnlock(PoolId poolId) internal override {
        wasUnlockWithPool = poolId;
    }

    function _afterLock() internal override {
        wasLock = true;
    }
}

contract PoolLockerTest is Test {
    PoolId constant POOL_A = PoolId.wrap(42);

    Multicall multicall = new Multicall();
    PoolManagerMock poolManager = new PoolManagerMock(multicall);

    function testWithPoolUnlockerMethod() public {
        address[] memory targets = new address[](1);
        targets[0] = address(poolManager);

        bytes[] memory methods = new bytes[](1);
        methods[0] = abi.encodeWithSelector(poolManager.poolRelatedMethod.selector);

        bytes[] memory results = poolManager.execute(POOL_A, targets, methods);
        assertEq(PoolId.unwrap(abi.decode(results[0], (PoolId))), PoolId.unwrap(POOL_A));

        assertEq(PoolId.unwrap(poolManager.wasUnlockWithPool()), PoolId.unwrap(POOL_A));
        assertEq(poolManager.wasLock(), true);
    }

    function testErrPoolAlreadyUnlocked() public {
        address[] memory innerTargets = new address[](1);
        innerTargets[0] = address(poolManager);

        bytes[] memory innerMethods = new bytes[](1);
        innerMethods[0] = abi.encodeWithSelector(poolManager.poolRelatedMethod.selector);

        address[] memory targets = new address[](1);
        targets[0] = address(poolManager);

        bytes[] memory methods = new bytes[](1);
        methods[0] = abi.encodeWithSelector(poolManager.execute.selector, POOL_A, innerTargets, innerMethods);

        vm.expectRevert(IPoolLocker.PoolAlreadyUnlocked.selector);
        poolManager.execute(POOL_A, targets, methods);
    }

    function testErrPoolLocked() public {
        vm.expectRevert(IPoolLocker.PoolLocked.selector);
        poolManager.poolRelatedMethod();
    }
}
