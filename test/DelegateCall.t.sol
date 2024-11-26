pragma solidity 0.8.28;

import "forge-std/Test.sol";

contract PoolRegistry {
    function registerPool() external {
        console.log("PoolRegistry/registerPool execution env address", address(this));
        console.log("PoolRegistry/registerPool msg.sender is:", msg.sender);
    }
}

contract PoolManager {
    PoolRegistry immutable poolRegistry;

    constructor(PoolRegistry poolRegistry_) {
        poolRegistry = poolRegistry_;
    }

    function registerPool() external {
        console.log("PoolManager/registerPool execution env address", address(this));
        console.log("PoolManager/registerPool msg.sender is:", msg.sender);
        poolRegistry.registerPool();
    }
}

contract MultiDelegateCall {
    function delegate(address delegatee) external {
        console.log("MultiDeleateCall execution env address:", address(this));
        delegatee.delegatecall(abi.encodeWithSignature("registerPool()"));
    }
}

contract DelegateCallTest is Test {
    function testCallDelegation() public {
        PoolRegistry registry = new PoolRegistry();
        PoolManager manager = new PoolManager(registry);
        MultiDelegateCall multicall = new MultiDelegateCall();

        // This test contract simulates the Fund managers.
        // The address of this (DelegateCallTest) contract is like FM
        console.log("FundManager (DelegateCallTest) address is: ", address(this));
        console.log("Registry address is: ", address(registry));
        console.log("Manager address is: ", address(manager));
        console.log("Multiall address is: ", address(multicall));

        multicall.delegate(address(manager));
    }
}
