// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import "test/vaults/BaseTest.sol";
import {CastLib} from "src/misc/libraries/CastLib.sol";
import {D18, d18} from "src/misc/types/D18.sol";

import {MessageLib} from "src/common/libraries/MessageLib.sol";
import {ShareClassId} from "src/common/types/ShareClassId.sol";
import {AssetId} from "src/common/types/AssetId.sol";

import {BalanceSheet} from "src/vaults/BalanceSheet.sol";

import {MerkleProofManager} from "src/managers/MerkleProofManager.sol";
import {VaultDecoderAndSanitizer} from "src/managers/decoders/VaultDecoderAndSanitizer.sol";
import {console} from "forge-std/console.sol";

contract BalanceSheetTest is BaseTest {
    using MessageLib for *;
    using CastLib for *;

    uint128 defaultAmount;
    D18 defaultPricePoolPerShare;
    D18 defaultPricePoolPerAsset;
    AssetId assetId;
    ShareClassId defaultTypedShareClassId;

    MerkleProofManager manager;
    VaultDecoderAndSanitizer decoder;

    function setUp() public override {
        super.setUp();
        defaultAmount = 100;
        defaultPricePoolPerShare = d18(1, 1);
        defaultPricePoolPerAsset = d18(1, 1);
        defaultTypedShareClassId = ShareClassId.wrap(defaultShareClassId);

        assetId = poolManager.registerAsset{value: 0.1 ether}(OTHER_CHAIN_ID, address(erc20), erc20TokenId);
        poolManager.addPool(POOL_A);
        poolManager.addShareClass(
            POOL_A,
            defaultTypedShareClassId,
            "testShareClass",
            "tsc",
            defaultDecimals,
            bytes32(""),
            fullRestrictionsHook
        );
        poolManager.updatePricePoolPerShare(
            POOL_A, defaultTypedShareClassId, defaultPricePoolPerShare.raw(), uint64(block.timestamp)
        );
        poolManager.updatePricePoolPerAsset(
            POOL_A, defaultTypedShareClassId, assetId, defaultPricePoolPerShare.raw(), uint64(block.timestamp)
        );
        poolManager.updateRestriction(
            POOL_A,
            defaultTypedShareClassId,
            MessageLib.UpdateRestrictionMember({user: address(this).toBytes32(), validUntil: MAX_UINT64}).serialize()
        );

        manager = new MerkleProofManager(POOL_A, balanceSheet, address(this));
    }

    function testExecute(uint128 amount) public {
        address receiver = makeAddr("receiver");
        decoder = new VaultDecoderAndSanitizer();

        // Deposit ERC20 in balance sheet
        balanceSheet.setQueue(POOL_A, defaultTypedShareClassId, true);

        erc20.mint(address(this), amount);
        erc20.approve(address(balanceSheet), amount);
        balanceSheet.deposit(POOL_A, defaultTypedShareClassId, address(erc20), erc20TokenId, amount);

        // Set merkle proof manager as balance sheet manager
        balanceSheet.update(
            POOL_A,
            defaultTypedShareClassId,
            MessageLib.UpdateContractUpdateManager({who: bytes20(address(manager)), canManage: true}).serialize()
        );

        // Generate policy root hash
        ManageLeaf[] memory leafs = new ManageLeaf[](2);
        leafs[0] = ManageLeaf(
            address(balanceSheet),
            false,
            "withdraw(uint64,bytes16,address,uint256,address,uint128)",
            new address[](2),
            "",
            address(decoder)
        );
        leafs[0].argumentAddresses[0] = address(erc20);
        leafs[0].argumentAddresses[1] = address(manager);

        // leafs[1] = ManageLeaf(
        //     address(balanceSheet),
        //     false,
        //     "deposit(uint64,bytes16,address,uint256,uint128)",
        //     new address[](1),
        //     "",
        //     address(decoder)
        // );
        // leafs[1].argumentAddresses[0] = address(erc20);

        leafs[1] = ManageLeaf(address(erc20), false, "approve(address,uint256)", new address[](1), "", address(decoder));
        leafs[1].argumentAddresses[0] = address(balanceSheet);

        bytes32[][] memory manageTree = _generateMerkleTree(leafs);
        manager.setPolicy(address(this), manageTree[1][0]);

        // Generate proof for execution
        (bytes32[][] memory manageProofs) = _getProofsUsingTree(leafs, manageTree);

        // Execute
        bytes[] memory targetData = new bytes[](2);
        targetData[0] = abi.encodeWithSelector(
            BalanceSheet.withdraw.selector,
            POOL_A,
            defaultTypedShareClassId,
            address(erc20),
            erc20TokenId,
            address(manager),
            amount
        );
        targetData[1] = abi.encodeWithSelector(ERC20.approve.selector, address(balanceSheet), amount / 2);
        // targetData[2] = abi.encodeWithSelector(
        //     BalanceSheet.deposit.selector, POOL_A, defaultTypedShareClassId, address(erc20), erc20TokenId, amount / 2
        // );

        address[] memory targets = new address[](2);
        targets[0] = address(balanceSheet);
        targets[1] = address(erc20);
        // targets[2] = address(balanceSheet);

        uint256[] memory values = new uint256[](2);

        console.log("5");
        address[] memory decodersAndSanitizers = new address[](2);
        decodersAndSanitizers[0] = address(decoder);
        decodersAndSanitizers[1] = address(decoder);
        // decodersAndSanitizers[2] = address(decoder);

        assertEq(erc20.balanceOf(receiver), 0);
        manager.execute(manageProofs, decodersAndSanitizers, targets, targetData, values);
        assertApproxEqAbs(erc20.balanceOf(address(manager)), amount, 1);
        // assertApproxEqAbs(erc20.balanceOf(address(balanceSheet.escrow(POOL_A))), amount / 2, 1);
    }

    // From
    // https://github.com/Se7en-Seas/boring-vault/blob/0e23e7fd3a9a7735bd3fea61dd33c1700e75c528/test/resources/MerkleTreeHelper/MerkleTreeHelper.sol#L6246C1-L6291C6

    struct ManageLeaf {
        address target;
        bool canSendValue;
        string signature;
        address[] argumentAddresses;
        string description;
        address decoderAndSanitizer;
    }

    function _buildTrees(bytes32[][] memory merkleTreeIn) internal pure returns (bytes32[][] memory merkleTreeOut) {
        // We are adding another row to the merkle tree, so make merkleTreeOut be 1 longer.
        uint256 merkleTreeIn_length = merkleTreeIn.length;
        merkleTreeOut = new bytes32[][](merkleTreeIn_length + 1);
        uint256 layer_length;
        // Iterate through merkleTreeIn to copy over data.
        for (uint256 i; i < merkleTreeIn_length; ++i) {
            layer_length = merkleTreeIn[i].length;
            merkleTreeOut[i] = new bytes32[](layer_length);
            for (uint256 j; j < layer_length; ++j) {
                merkleTreeOut[i][j] = merkleTreeIn[i][j];
            }
        }

        uint256 next_layer_length;
        if (layer_length % 2 != 0) {
            next_layer_length = (layer_length + 1) / 2;
        } else {
            next_layer_length = layer_length / 2;
        }
        merkleTreeOut[merkleTreeIn_length] = new bytes32[](next_layer_length);
        uint256 count;
        for (uint256 i; i < layer_length; i += 2) {
            merkleTreeOut[merkleTreeIn_length][count] =
                _hashPair(merkleTreeIn[merkleTreeIn_length - 1][i], merkleTreeIn[merkleTreeIn_length - 1][i + 1]);
            count++;
        }

        if (next_layer_length > 1) {
            // We need to process the next layer of leaves.
            merkleTreeOut = _buildTrees(merkleTreeOut);
        }
    }

    function _generateMerkleTree(ManageLeaf[] memory manageLeafs) internal view returns (bytes32[][] memory tree) {
        uint256 leafsLength = manageLeafs.length;
        bytes32[][] memory leafs = new bytes32[][](1);
        leafs[0] = new bytes32[](leafsLength);
        for (uint256 i; i < leafsLength; ++i) {
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                address(decoder), // TODO replace address(decoder)
                manageLeafs[i].target,
                manageLeafs[i].canSendValue,
                selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            leafs[0][i] = keccak256(rawDigest);
        }
        tree = _buildTrees(leafs);
    }

    function _hashPair(bytes32 a, bytes32 b) private pure returns (bytes32) {
        return a < b ? _efficientHash(a, b) : _efficientHash(b, a);
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function _getProofsUsingTree(ManageLeaf[] memory manageLeafs, bytes32[][] memory tree)
        internal
        view
        returns (bytes32[][] memory proofs)
    {
        proofs = new bytes32[][](manageLeafs.length);
        for (uint256 i; i < manageLeafs.length; ++i) {
            // Generate manage proof.
            bytes4 selector = bytes4(keccak256(abi.encodePacked(manageLeafs[i].signature)));
            bytes memory rawDigest = abi.encodePacked(
                address(decoder), // TODO more generic
                manageLeafs[i].target,
                manageLeafs[i].canSendValue,
                selector
            );
            uint256 argumentAddressesLength = manageLeafs[i].argumentAddresses.length;
            for (uint256 j; j < argumentAddressesLength; ++j) {
                rawDigest = abi.encodePacked(rawDigest, manageLeafs[i].argumentAddresses[j]);
            }
            bytes32 leaf = keccak256(rawDigest);
            proofs[i] = _generateProof(leaf, tree);
        }
    }

    function _generateProof(bytes32 leaf, bytes32[][] memory tree) internal pure returns (bytes32[] memory proof) {
        // The length of each proof is the height of the tree - 1.
        uint256 tree_length = tree.length;
        proof = new bytes32[](tree_length - 1);

        // Build the proof
        for (uint256 i; i < tree_length - 1; ++i) {
            // For each layer we need to find the leaf.
            for (uint256 j; j < tree[i].length; ++j) {
                if (leaf == tree[i][j]) {
                    // We have found the leaf, so now figure out if the proof needs the next leaf or the previous one.
                    proof[i] = j % 2 == 0 ? tree[i][j + 1] : tree[i][j - 1];
                    leaf = _hashPair(leaf, proof[i]);
                    break;
                } else if (j == tree[i].length - 1) {
                    // We have reached the end of the layer and have not found the leaf.
                    revert("Leaf not found in tree");
                }
            }
        }
    }
}
