// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.25;

import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ICorporateBondRepayVault is IERC4626 {
    event PrincipalPaid(uint256 assets, uint256 value, address creditor, address debtor);
    event PrincipalRepaid(uint256 assets, uint256 value, address debtor, address creditor);
    event InterestPaid(uint256 assets, uint256 value, address debtor, address creditor);
    event FeesSet(uint48 bips);
    event FeesRecipientSet(address recipient);

    error ZeroAddress();
    error OnlyDebtor(address addr, address debtor);
    error OnlyDebtorOrCreditor(address addr, address debtor, address creditor);
    error InvalidPrincipalAmount(uint256 amount, uint256 debtAmount);
    error PrincipalAlreadyPaid();
    error PrincipalNotPaid();
    error StandardDepositOrMintNotAllowed();
    error ZeroAmount();
    error ExcessiveVaultFees(uint48 bips);
    error StalePrice(uint256 updatedAt);
    error InvalidPriceValue(int256 price);
    error InsufficientAssets(uint256 required, uint256 provided);

    /**
     * @notice Gets the price feed used for valuation
     * @return The price feed contract
     */
    function priceFeed() external view returns (AggregatorV3Interface);

    /**
     * @notice Deposits assets into the vault with a target value.
     * @dev The vault will only take the necessary assets to meet the target value.
     * @dev The creditor can deposit the principal amount.
     * @dev The debtor can deposit any amount to repay the principal or pay interest.
     * @param maxAssets Maximum amount of assets to deposit
     * @param targetValue Target value in price feed units
     * @param principal Whether this is a principal deposit
     * @return shares Amount of shares minted
     * @return assetsUsed Amount of assets actually used
     */
    function deposit(
        uint256 maxAssets,
        uint256 targetValue,
        bool principal
    ) external returns (uint256 shares, uint256 assetsUsed);

    /// @dev Standard ERC4626 deposit not allowed
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @dev Standard ERC4626 mint not allowed
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @notice Sets the vault fees recipient.
     * @param newFeesRecipient The new fees recipient.
     */
    function setFeesRecipient(
        address newFeesRecipient
    ) external;

    /**
     * @notice Sets the vault fees.
     * @param newFeesBips The new fees in bips.
     */
    function setFeesBips(
        uint48 newFeesBips
    ) external;

    /**
     * @notice Returns the creditor of the vault.
     * @return The creditor of the vault.
     */
    function creditor() external view returns (address);
}
