// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0

pragma solidity 0.8.25;

import {ICorporateBondRepayVault} from "../../interface/CorporateBond/ICorporateBondRepayVault.sol";
import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
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
    AggregatorV3Interface public immutable priceFeed;
    address public feesRecipient;

    // Whether the principal has been paid to the debtor
    bool public principalPaid;
    // The amount of principal repaid to the creditor
    uint256 public principalRepaid;
    // The amount of fees paid to the vault in bips
    uint48 public feesBips;

    uint48 constant MAX_FEES_BIPS = 1000; // 10%

    constructor(
        address owner_,
        IERC721 bondNFTContract_,
        uint256 bondNFTTokenId_,
        address debtor_,
        IERC20 paymentAsset_,
        uint256 debtAmount_,
        uint64 bondMaturity_,
        bool principalPaid_,
        uint256 principalRepaid_,
        uint48 feesBips_,
        address feesRecipient_,
        address priceFeed_
    ) ERC4626(paymentAsset_) ERC20("CorporateBondRepayVault", "CBRV") Ownable(owner_) {
        if (debtor_ == address(0)) {
            revert ZeroAddress();
        }
        if (debtAmount_ == 0) {
            revert ZeroAmount();
        }
        if (feesBips_ > MAX_FEES_BIPS) {
            revert ExcessiveVaultFees(feesBips_);
        }
        if (feesRecipient_ == address(0)) {
            revert ZeroAddress();
        }
        if (priceFeed_ == address(0)) {
            revert ZeroAddress();
        }

        // Check that the NFT exists by trying to get its owner
        bondNFTContract_.ownerOf(bondNFTTokenId_);

        debtor = debtor_;
        bondNFTContract = bondNFTContract_;
        bondNFTTokenId = bondNFTTokenId_;
        debtAmount = debtAmount_;
        principalPaid = principalPaid_;
        principalRepaid = principalRepaid_;
        feesBips = feesBips_;
        bondMaturity = bondMaturity_;
        feesRecipient = feesRecipient_;
        priceFeed = AggregatorV3Interface(priceFeed_);

        emit FeesSet(feesBips_);
        emit FeesRecipientSet(feesRecipient_);
    }

    /// @inheritdoc ICorporateBondRepayVault
    function setFeesRecipient(
        address newFeesRecipient
    ) external onlyOwner {
        if (newFeesRecipient == address(0)) {
            revert ZeroAddress();
        }
        feesRecipient = newFeesRecipient;
        emit FeesRecipientSet(newFeesRecipient);
    }

    /// @inheritdoc ICorporateBondRepayVault
    function setFeesBips(
        uint48 feesBips_
    ) external onlyOwner {
        if (feesBips_ > MAX_FEES_BIPS) {
            revert ExcessiveVaultFees(feesBips_);
        }
        feesBips = feesBips_;
        emit FeesSet(feesBips_);
    }

    /**
     * @dev Prices an amount of assets using the price feed
     * Reverts if price is stale or invalid
     */
    function _priceAssets(
        uint256 assetAmount
    ) internal view returns (uint256) {
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();

        // Check for stale price (25 hours)
        if (block.timestamp - updatedAt > 25 hours) {
            revert StalePrice(updatedAt);
        }

        // Ensure positive price
        if (price <= 0) {
            revert InvalidPriceValue(price);
        }

        uint256 assetDecimals = decimals();

        return (assetAmount * uint256(price)) / (10 ** assetDecimals);
    }

    function deposit(uint256 assets, bool principal) public returns (uint256 shares) {
        address _creditor = creditor();

        if (principal) {
            // Principal deposits can be made by creditor or debtor
            if (_msgSender() != _creditor && _msgSender() != debtor) {
                revert OnlyDebtorOrCreditor(_msgSender(), debtor, _creditor);
            }

            if (_msgSender() == _creditor) {
                // Check that the principal value matches the debt amount
                uint256 value = _priceAssets(assets);
                if (value != debtAmount) {
                    revert InvalidPrincipalAmount(value, debtAmount);
                }

                if (principalPaid) {
                    revert PrincipalAlreadyPaid();
                }

                principalPaid = true;
                emit PrincipalPaid(assets, value, _creditor, debtor);
            } else if (_msgSender() == debtor) {
                // If debtor is depositing, check that the principal has been paid
                if (!principalPaid) {
                    revert PrincipalNotPaid();
                }

                // Check that the repayment amount doesn't exceed remaining principal
                uint256 value = _priceAssets(assets);
                if (value > debtAmount - principalRepaid) {
                    revert InvalidPrincipalAmount(value, debtAmount - principalRepaid);
                }

                principalRepaid += value;
                emit PrincipalRepaid(assets, value, debtor, _creditor);
            }

            // Deposit to debtor if creditor is depositing, otherwise to creditor
            return super.deposit(assets, _msgSender() == _creditor ? debtor : _creditor);
        } else {
            // Interest payments can only be made by debtor
            if (_msgSender() != debtor) {
                revert OnlyDebtor(_msgSender(), debtor);
            }

            // Calculate fees and net interest amount
            uint256 fees = (assets * feesBips) / 10_000;
            uint256 netAssets = assets - fees;

            uint256 value = _priceAssets(assets);
            emit InterestPaid(assets, value, debtor, _creditor);

            // Deposit fees to recipient and interest to creditor
            super.deposit(fees, feesRecipient);
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

    /// @inheritdoc ICorporateBondRepayVault
    function creditor() public view returns (address) {
        return bondNFTContract.ownerOf(bondNFTTokenId);
    }
}
