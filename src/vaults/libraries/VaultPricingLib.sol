// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import {MathLib} from "src/misc/libraries/MathLib.sol";
import {IBaseVault} from "src/vaults/interfaces/IERC7540.sol";
import {IERC20Metadata} from "src/misc/interfaces/IERC20.sol";
import {IERC6909MetadataExt} from "src/misc/interfaces/IERC6909.sol";

library VaultPricingLib {
    using MathLib for uint256;

    /// @dev Prices are fixed-point integers with 18 decimals
    uint8 internal constant PRICE_DECIMALS = 18;

    /// @dev    Calculates share amount based on asset amount and share price. Returned value is in share decimals.
    function calculateShares(
        address shareToken,
        address asset,
        uint256 tokenId,
        uint128 assets,
        uint256 price,
        MathLib.Rounding rounding
    ) internal view returns (uint128 shares) {
        if (price == 0 || assets == 0) {
            shares = 0;
        } else {
            uint8 assetDecimals = getAssetDecimals(asset, tokenId);
            uint8 shareDecimals = IERC20Metadata(shareToken).decimals();

            uint256 sharesInPriceDecimals =
                toPriceDecimals(assets, assetDecimals).mulDiv(10 ** PRICE_DECIMALS, price, rounding);

            shares = fromPriceDecimals(sharesInPriceDecimals, shareDecimals);
        }
    }

    /// @dev    Calculates asset amount based on share amount and share price. Returned value is in asset decimals.
    function calculateAssets(
        address shareToken,
        uint128 shares,
        address asset,
        uint256 tokenId,
        uint256 price,
        MathLib.Rounding rounding
    ) internal view returns (uint128 assets) {
        if (price == 0 || shares == 0) {
            assets = 0;
        } else {
            uint8 assetDecimals = getAssetDecimals(asset, tokenId);
            uint8 shareDecimals = IERC20Metadata(shareToken).decimals();

            uint256 assetsInPriceDecimals =
                toPriceDecimals(shares, shareDecimals).mulDiv(price, 10 ** PRICE_DECIMALS, rounding);

            assets = fromPriceDecimals(assetsInPriceDecimals, assetDecimals);
        }
    }

    /// @dev    Calculates share price and returns the value in price decimals
    function calculatePrice(address shareToken, uint128 shares, address asset, uint256 tokenId, uint128 assets)
        internal
        view
        returns (uint256)
    {
        if (assets == 0 || shares == 0) {
            return 0;
        }

        uint8 assetDecimals = getAssetDecimals(asset, tokenId);
        uint8 shareDecimals = IERC20Metadata(shareToken).decimals();
        return toPriceDecimals(assets, assetDecimals).mulDiv(
            10 ** PRICE_DECIMALS, toPriceDecimals(shares, shareDecimals), MathLib.Rounding.Down
        );
    }

    /// @dev    When converting assets to shares using the price,
    ///         all values are normalized to PRICE_DECIMALS
    /// @dev    NOTE: We require all assets to have 2 <= decimals <= 18, see `PoolManager.registerAsset`
    function toPriceDecimals(uint128 _value, uint8 decimals) internal pure returns (uint256) {
        if (PRICE_DECIMALS == decimals) return uint256(_value);
        return uint256(_value) * 10 ** (PRICE_DECIMALS - decimals);
    }

    /// @dev    Converts decimals of the value from the price decimals back to the intended decimals
    /// @dev    NOTE: We require all assets to have 2 <= decimals <= 18, see `PoolManager.registerAsset`
    function fromPriceDecimals(uint256 _value, uint8 decimals) internal pure returns (uint128) {
        if (PRICE_DECIMALS == decimals) return _value.toUint128();
        return (_value / 10 ** (PRICE_DECIMALS - decimals)).toUint128();
    }

    /// @dev    Returns the asset decimals
    function getAssetDecimals(address asset, uint256 tokenId) internal view returns (uint8 assetDecimals) {
        return tokenId == 0 ? IERC20Metadata(asset).decimals() : IERC6909MetadataExt(asset).decimals(tokenId);
    }
}
