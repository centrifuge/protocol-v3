// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {ConversionLib} from "src/libraries/ConversionLib.sol";
import {d18} from "src/types/D18.sol";

import {IERC7726} from "src/interfaces/IERC7726.sol";
import {IOneToOneValuation} from "src/interfaces/IOneToOneValuation.sol";
import {IERC6909MetadataExt} from "src/interfaces/IERC6909.sol";

import {BaseValuation} from "src/BaseValuation.sol";

contract OneToOneValuation is BaseValuation, IOneToOneValuation {
    constructor(IERC6909MetadataExt erc6909, address deployer) BaseValuation(erc6909, deployer) {}

    /// @inheritdoc IERC7726
    function getQuote(uint256 baseAmount, address base, address quote) external view returns (uint256 quoteAmount) {
        return ConversionLib.convertWithPrice(baseAmount, _getDecimals(base), _getDecimals(quote), d18(1e18));
    }
}
