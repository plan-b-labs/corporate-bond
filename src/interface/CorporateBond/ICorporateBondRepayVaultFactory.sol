// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface ICorporateBondRepayVaultFactory {
    event VaultCreated(
        address indexed vault,
        address indexed bondNFT,
        uint256 indexed tokenId,
        address debtor,
        address asset,
        uint256 debtAmount,
        uint64 bondMaturity,
        bool principalPaid,
        uint256 principalRepaid,
        uint48 feesBips,
        address feesRecipient
    );

    error InvalidBondMaturity(uint64 maturity);

    /**
     * @notice Creates a new CorporateBondRepayVault
     * @param bondNFT The bond NFT contract
     * @param tokenId The bond NFT token ID
     * @param debtor The debtor address
     * @param asset The asset token being used for repayment
     * @param debtAmount The total debt amount
     * @param bondMaturity The maturity timestamp of the bond
     * @param principalPaid Whether the principal has been paid
     * @param principalRepaid Amount of principal repaid
     * @param feesBips The fees in basis points
     * @param feesRecipient The recipient of the fees
     * @return vault The address of the created vault
     */
    function createVault(
        address bondNFT,
        uint256 tokenId,
        address debtor,
        address asset,
        uint256 debtAmount,
        uint64 bondMaturity,
        bool principalPaid,
        uint256 principalRepaid,
        uint48 feesBips,
        address feesRecipient
    ) external returns (address vault);
}
