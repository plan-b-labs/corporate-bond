// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.28;

import {ICorporateBondRepayVault} from "../../interface/CorporateBond/ICorporateBondRepayVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title CorporateBondRepayVault
 * @notice A vault that allows a debtor to repay a corporate bond to the creditor.
 * @notice The creditor is identified by owning the CorporateBond NFT.
 * @dev This contract is a ERC4626 vault with additional access control.
 * @dev The creditor can deposit assets into the vault to provide the principal.
 * @dev The debtor can deposit assets into the vault to repay the principal or interest.
 */
contract CorporateBondRepayVault is ICorporateBondRepayVault, ERC4626, Ownable {
    address public immutable debtor;
    IERC721 public immutable bondNFTContract;
    uint256 public immutable bondNFTTokenId;
    uint256 public immutable debtAmount;
    uint64 public immutable bondMaturity;

    // Whether the principal has been paid to the debtor
    bool public principalPaid;
    // The amount of principal repaid to the creditor
    uint256 public principalRepaid;
    // The amount of fees paid to the vault in bips
    uint48 public vaultFeesBips;

    uint48 constant MAX_VAULT_FEES_BIPS = 1000; // 10%

    constructor(
        address owner_,
        IERC721 bondNFTContract_,
        uint256 bondNFTTokenId_,
        address debtor_,
        IERC20 repayAsset_,
        uint256 debtAmount_,
        bool principalPaid_,
        uint256 principalRepaid_,
        uint48 vaultFeesBips_,
        uint64 bondMaturity_
    ) ERC4626(repayAsset_) ERC20("CorporateBondRepayVault", "CBRV") Ownable(owner_) {
        if (debtor_ == address(0)) {
            revert ZeroAddress();
        }

        if (debtAmount_ == 0) {
            revert ZeroAmount();
        }

        if (vaultFeesBips_ > MAX_VAULT_FEES_BIPS) {
            revert ExcessiveVaultFees(vaultFeesBips_);
        }

        // Check that the NFT exists by trying to get its owner
        bondNFTContract_.ownerOf(bondNFTTokenId_);

        debtor = debtor_;
        bondNFTContract = bondNFTContract_;
        bondNFTTokenId = bondNFTTokenId_;
        debtAmount = debtAmount_;
        principalPaid = principalPaid_;
        principalRepaid = principalRepaid_;
        vaultFeesBips = vaultFeesBips_;
        bondMaturity = bondMaturity_;
    }

    function setVaultFeesBips(
        uint48 vaultFeesBips_
    ) external onlyOwner {
        if (vaultFeesBips_ > MAX_VAULT_FEES_BIPS) {
            revert ExcessiveVaultFees(vaultFeesBips_);
        }
        uint48 oldBips = vaultFeesBips;
        vaultFeesBips = vaultFeesBips_;
        emit VaultFeesSet(oldBips, vaultFeesBips_);
    }

    /// @inheritdoc ICorporateBondRepayVault
    function deposit(uint256 assets, bool principal) public returns (uint256 shares) {
        address _creditor = creditor();

        if (principal) {
            // Principal deposits can be made by creditor or debtor
            if (_msgSender() != _creditor && _msgSender() != debtor) {
                revert OnlyDebtorOrCreditor(_msgSender(), debtor, _creditor);
            }

            if (_msgSender() == _creditor) {
                // Principal amount must match debt amount if creditor is depositing
                if (assets != debtAmount) {
                    revert InvalidPrincipalAmount(assets, debtAmount);
                }

                // Check that the principal has not already been paid
                if (principalPaid) {
                    revert PrincipalAlreadyPaid();
                }

                principalPaid = true;
                emit PrincipalPaid(assets, _creditor, debtor);
            } else if (_msgSender() == debtor) {
                // If debtor is depositing, check that the principal has been paid
                if (!principalPaid) {
                    revert PrincipalNotPaid();
                }

                // If principal is being repaid, check that the amount is not greater than the debt amount
                if (assets > debtAmount - principalRepaid) {
                    revert InvalidPrincipalAmount(assets, debtAmount - principalRepaid);
                }

                // Update the principal repaid amount
                principalRepaid += assets;
                emit PrincipalRepaid(assets, debtor, _creditor);
            }

            // Deposit the principal amount to debtor if creditor is depositing
            // Otherwise deposit to creditor if debtor is depositing
            return super.deposit(assets, _msgSender() == _creditor ? debtor : _creditor);
        } else {
            // Non-principal deposits can only be made by debtor
            if (_msgSender() != debtor) {
                revert OnlyDebtor(_msgSender(), debtor);
            }

            // Calculate the amount of fees to pay to the vault
            uint256 fees = (assets * vaultFeesBips) / 10_000;
            // Subtract the fees from the amount of interest to pay
            uint256 netAssets = assets - fees;

            emit InterestPaid(assets, debtor, _creditor);

            // Deposit the fees to the vault owner
            super.deposit(fees, owner());
            // Deposit to creditor
            return super.deposit(netAssets, _creditor);
        }
    }

    /// @inheritdoc ICorporateBondRepayVault
    function deposit(
        uint256,
        address
    ) public pure override (ICorporateBondRepayVault, ERC4626) returns (uint256) {
        revert StandardDepositOrMintNotAllowed();
    }

    /// @inheritdoc ICorporateBondRepayVault
    function mint(
        uint256,
        address
    ) public pure override (ICorporateBondRepayVault, ERC4626) returns (uint256) {
        revert StandardDepositOrMintNotAllowed();
    }

    function creditor() public view returns (address) {
        return bondNFTContract.ownerOf(bondNFTTokenId);
    }
}
