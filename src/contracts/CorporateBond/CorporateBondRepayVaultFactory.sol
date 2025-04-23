// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ICorporateBondRepayVaultFactory} from
    "../../interface/CorporateBond/ICorporateBondRepayVaultFactory.sol";
import {CorporateBondRepayVault} from "./CorporateBondRepayVault.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract CorporateBondRepayVaultFactory is ICorporateBondRepayVaultFactory, Ownable {
    constructor(
        address owner_
    ) Ownable(owner_) {}

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
    ) external returns (address vault) {
        // Check that bond maturity is in the future
        if (bondMaturity <= uint64(block.timestamp)) {
            revert InvalidBondMaturity(bondMaturity);
        }

        // Create new vault
        vault = address(
            new CorporateBondRepayVault(
                owner(),
                IERC721(bondNFT),
                tokenId,
                debtor,
                IERC20(asset),
                debtAmount,
                bondMaturity,
                principalPaid,
                principalRepaid,
                feesBips,
                feesRecipient
            )
        );

        emit VaultCreated(
            vault,
            bondNFT,
            tokenId,
            debtor,
            asset,
            debtAmount,
            bondMaturity,
            principalPaid,
            principalRepaid,
            feesBips,
            feesRecipient
        );
    }
}
