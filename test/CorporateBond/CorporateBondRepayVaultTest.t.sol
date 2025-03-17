// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {CorporateBond} from "../../src/contracts/CorporateBond/CorporateBond.sol";
import {
    CorporateBondRepayVault,
    ICorporateBondRepayVault
} from "../../src/contracts/CorporateBond/CorporateBondRepayVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CorporateBondRepayVaultTest is Test {
    CorporateBond public bond;
    CorporateBondRepayVault public vault;
    MockERC20 public token;

    address public owner;
    address public debtor;
    address public creditor;
    address public feesRecipient;
    uint256 public tokenId;

    uint256 constant DEBT_AMOUNT = 1000 ether;
    uint48 constant FEES_BIPS = 100;

    function setUp() public {
        owner = makeAddr("owner");
        debtor = makeAddr("debtor");
        creditor = makeAddr("creditor");
        feesRecipient = makeAddr("feesRecipient");

        // Deploy mock ERC20 token
        token = new MockERC20();
        token.mint(creditor, DEBT_AMOUNT);
        token.mint(debtor, DEBT_AMOUNT);

        // Deploy CorporateBond NFT
        bond = new CorporateBond(address(this));
        tokenId = bond.safeMint(creditor, "test-uri");

        // Deploy vault
        vault = new CorporateBondRepayVault(
            owner,
            bond,
            tokenId,
            debtor,
            token,
            DEBT_AMOUNT,
            uint64(block.timestamp + 365 days),
            false,
            0,
            FEES_BIPS,
            feesRecipient
        );
    }

    modifier principalPaid() {
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
        _;
    }

    // Principal-related tests
    function testCreditorCanDepositPrincipal() public {
        assertEq(vault.balanceOf(debtor), 0);
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();

        assertEq(vault.balanceOf(debtor), DEBT_AMOUNT);
        assertTrue(vault.principalPaid());
    }

    function testCreditorCannotDepositPrincipalTwice() public principalPaid {
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ICorporateBondRepayVault.PrincipalAlreadyPaid.selector)
        );
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testDebtorCannotDepositPrincipalBeforeCreditor() public {
        vm.startPrank(debtor);
        token.approve(address(vault), DEBT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ICorporateBondRepayVault.PrincipalNotPaid.selector));
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testDebtorCanWithdrawPrincipal() public principalPaid {
        // Debtor withdraws principal
        vm.startPrank(debtor);
        vault.withdraw(DEBT_AMOUNT, debtor, debtor);
        vm.stopPrank();

        assertEq(token.balanceOf(debtor), DEBT_AMOUNT * 2); // Initial balance + withdrawn principal
        assertEq(vault.balanceOf(debtor), 0);
        assertTrue(vault.principalPaid());
    }

    function testDebtorCanRepayPrincipal() public principalPaid {
        // Debtor repays principal
        vm.startPrank(debtor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();

        assertEq(vault.balanceOf(creditor), DEBT_AMOUNT);
        assertEq(vault.principalRepaid(), DEBT_AMOUNT);
    }

    function testCreditorCanWithdrawRepaidPrincipal() public principalPaid {
        // Debtor repays principal
        vm.startPrank(debtor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();

        // Creditor withdraws principal
        vm.startPrank(creditor);
        vault.withdraw(DEBT_AMOUNT, creditor, creditor);
        vm.stopPrank();

        assertEq(token.balanceOf(creditor), DEBT_AMOUNT);
        assertEq(vault.balanceOf(creditor), 0);
    }

    // Interest and fees tests
    function testDebtorCanPayInterest(
        uint256 interestAmount
    ) public principalPaid {
        vm.assume(interestAmount < type(uint256).max / FEES_BIPS);
        token.mint(debtor, interestAmount);

        uint256 fees = (interestAmount * FEES_BIPS) / 10_000;
        uint256 netInterestAmount = interestAmount - fees;

        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);
        vault.deposit(interestAmount, false);
        vm.stopPrank();

        assertEq(vault.balanceOf(creditor), netInterestAmount);
        assertEq(vault.balanceOf(feesRecipient), fees);
    }

    function testNonDebtorCannotDeposit() public {
        uint256 depositAmount = 10 ether;
        token.mint(owner, depositAmount);

        vm.startPrank(owner);
        token.approve(address(vault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(ICorporateBondRepayVault.OnlyDebtor.selector, owner, debtor)
        );
        vault.deposit(depositAmount, false);
        vm.stopPrank();
    }

    function testStandardDepositNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICorporateBondRepayVault.StandardDepositOrMintNotAllowed.selector
            )
        );
        vault.deposit(10 ether, address(this));
    }

    function testVaultOwnerCanSetVaultFeesBips() public {
        vm.startPrank(owner);
        vault.setFeesBips(200);
        vm.stopPrank();

        assertEq(vault.feesBips(), 200);
    }

    function testFeesRecipientCanWithdrawFees() public {
        uint256 interestAmount = 100 ether;
        token.mint(debtor, interestAmount);

        // Debtor pays interest, generating fees
        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);
        vault.deposit(interestAmount, false);
        vm.stopPrank();

        uint256 fees = (interestAmount * FEES_BIPS) / 10_000;

        // Fees recipient withdraws fees
        vm.startPrank(feesRecipient);
        vault.withdraw(fees, feesRecipient, feesRecipient);
        vm.stopPrank();

        assertEq(token.balanceOf(feesRecipient), fees);
        assertEq(vault.balanceOf(feesRecipient), 0);
    }

    function testOwnerCanSetFeesRecipient() public {
        address newFeesRecipient = makeAddr("newFeesRecipient");

        vm.startPrank(owner);
        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.FeesRecipientSet(newFeesRecipient);
        vault.setFeesRecipient(newFeesRecipient);
        vm.stopPrank();

        assertEq(vault.feesRecipient(), newFeesRecipient);
    }

    function testNonOwnerCannotSetFeesRecipient() public {
        address newFeesRecipient = makeAddr("newFeesRecipient");

        vm.startPrank(debtor);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, debtor));
        vault.setFeesRecipient(newFeesRecipient);
        vm.stopPrank();
    }

    function testCannotSetZeroAddressAsFeesRecipient() public {
        vm.startPrank(owner);
        vm.expectRevert(abi.encodeWithSelector(ICorporateBondRepayVault.ZeroAddress.selector));
        vault.setFeesRecipient(address(0));
        vm.stopPrank();
    }

    // Event emission tests
    function testEmitsPrincipalPaidEvent() public {
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.PrincipalPaid(DEBT_AMOUNT, creditor, debtor);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testEmitsPrincipalRepaidEvent() public principalPaid {
        vm.startPrank(debtor);
        token.approve(address(vault), DEBT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.PrincipalRepaid(DEBT_AMOUNT, debtor, creditor);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testEmitsInterestPaidEvent() public {
        uint256 interestAmount = 10 ether;

        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.InterestPaid(interestAmount, debtor, creditor);
        vault.deposit(interestAmount, false);
        vm.stopPrank();
    }

    function testEmitsVaultFeesSetEvent() public {
        vm.startPrank(owner);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.FeesSet(200);
        vault.setFeesBips(200);

        vm.stopPrank();
    }
}
