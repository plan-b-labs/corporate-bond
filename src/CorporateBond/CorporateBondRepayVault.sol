// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title CorporateBondRepayVault
 * @notice A vault that allows a borrower to repay a corporate bond to the lender.
 * @notice The lender is identified by owning the CorporateBond NFT.
 * @dev This contract is a ERC4626 vault with additional access control.
 * @dev Only the borrower can deposit assets into the vault and the recipient has to be the lender.
 * @dev Only the lender can redeem the vault's assets.
 */
contract CorporateBondRepayVault is ERC4626 {
    error OnlyBorrower(address addr, address borrower);
    error OnlyLender(address addr, address lender);
    error OnlyLenderRecipient(address addr, address lender);

    address public immutable borrower;
    IERC721 public immutable bondNFTContract;
    uint256 public immutable bondNFTTokenId;

    constructor(
        IERC721 bondNFTContract_,
        uint256 bondNFTTokenId_,
        address borrower_,
        IERC20 repayAsset_
    ) ERC4626(repayAsset_) ERC20("CorporateBondRepayVault", "CBRV") {
        borrower = borrower_;
        bondNFTContract = bondNFTContract_;
        bondNFTTokenId = bondNFTTokenId_;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != borrower) {
            revert OnlyBorrower(caller, borrower);
        }
        if (!_isLender(receiver)) {
            revert OnlyLenderRecipient(receiver, bondNFTContract.ownerOf(bondNFTTokenId));
        }

        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (!_isLender(caller)) {
            revert OnlyLender(caller, bondNFTContract.ownerOf(bondNFTTokenId));
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _isLender(
        address addr
    ) internal view returns (bool) {
        return bondNFTContract.ownerOf(bondNFTTokenId) == addr;
    }
}
