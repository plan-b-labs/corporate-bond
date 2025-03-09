// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title CorporateBondRepayVault
 * @notice A vault that allows a debtor to repay a corporate bond to the creditor.
 * @notice The creditor is identified by owning the CorporateBond NFT.
 * @dev This contract is a ERC4626 vault with additional access control.
 * @dev Only the debtor can deposit assets into the vault and the recipient has to be the creditor.
 * @dev Only the creditor can redeem the vault's assets.
 */
contract CorporateBondRepayVault is ERC4626 {
    error OnlyDebtor(address addr, address debtor);
    error OnlyCreditor(address addr, address creditor);
    error OnlyCreditorRecipient(address addr, address creditor);

    address public immutable debtor;
    IERC721 public immutable bondNFTContract;
    uint256 public immutable bondNFTTokenId;

    constructor(
        IERC721 bondNFTContract_,
        uint256 bondNFTTokenId_,
        address debtor_,
        IERC20 repayAsset_
    ) ERC4626(repayAsset_) ERC20("CorporateBondRepayVault", "CBRV") {
        debtor = debtor_;
        bondNFTContract = bondNFTContract_;
        bondNFTTokenId = bondNFTTokenId_;
    }

    function _deposit(
        address caller,
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        if (caller != debtor) {
            revert OnlyDebtor(caller, debtor);
        }
        if (!_isCreditor(receiver)) {
            revert OnlyCreditorRecipient(receiver, bondNFTContract.ownerOf(bondNFTTokenId));
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
        if (!_isCreditor(caller)) {
            revert OnlyCreditor(caller, bondNFTContract.ownerOf(bondNFTTokenId));
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function _isCreditor(
        address addr
    ) internal view returns (bool) {
        return bondNFTContract.ownerOf(bondNFTTokenId) == addr;
    }
}
