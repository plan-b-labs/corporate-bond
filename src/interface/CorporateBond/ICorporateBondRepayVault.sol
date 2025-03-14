// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface ICorporateBondRepayVault is IERC4626 {
    event PrincipalPaid(uint256 amount, address creditor, address debtor);
    event PrincipalRepaid(uint256 amount, address debtor, address creditor);
    event InterestPaid(uint256 amount, address debtor, address creditor);
    event VaultFeesSet(uint48 oldBips, uint48 newBips);

    error ZeroAddress();
    error OnlyDebtor(address addr, address debtor);
    error OnlyDebtorOrCreditor(address addr, address debtor, address creditor);
    error InvalidPrincipalAmount(uint256 amount, uint256 debtAmount);
    error PrincipalAlreadyPaid();
    error PrincipalNotPaid();
    error StandardDepositOrMintNotAllowed();

    /**
     * @notice Deposits assets into the vault.
     * @dev The creditor can deposit the principal amount.
     * @dev The debtor can deposit any amount to repay the principal or pay interest.
     * @param assets The amount of assets to deposit.
     * @param principal Whether this is a principal deposit or not.
     * @return shares The amount of shares minted.
     */
    function deposit(uint256 assets, bool principal) external returns (uint256 shares);

    /// @dev Standard ERC4626 deposit not allowed
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @dev Standard ERC4626 mint not allowed
    function mint(uint256 shares, address receiver) external returns (uint256 assets);
}
