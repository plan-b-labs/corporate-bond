// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {CorporateBond} from "../../src/contracts/CorporateBond/CorporateBond.sol";
import {
    CorporateBondRepayVault,
    ICorporateBondRepayVault
} from "../../src/contracts/CorporateBond/CorporateBondRepayVault.sol";
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
    uint256 public tokenId;

    uint256 constant DEBT_AMOUNT = 1000 ether;
    uint48 constant VAULT_FEES_BIPS = 100;

    function setUp() public {
        owner = makeAddr("owner");
        debtor = makeAddr("debtor");
        creditor = makeAddr("creditor");

        // Deploy mock ERC20 token
        token = new MockERC20();
        token.mint(creditor, DEBT_AMOUNT);
        token.mint(debtor, DEBT_AMOUNT);

        // Deploy CorporateBond NFT
        bond = new CorporateBond(address(this));
        tokenId = bond.safeMint(creditor, "test-uri");

        // Deploy vault
        vault = new CorporateBondRepayVault(
            owner, bond, tokenId, debtor, token, DEBT_AMOUNT, false, 0, VAULT_FEES_BIPS
        );
    }

    modifier principalPaid() {
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();
        _;
    }

    function testVaultOwnerCanSetVaultFeesBips() public {
        vm.startPrank(owner);
        vault.setVaultFeesBips(200);
        vm.stopPrank();

        assertEq(vault.vaultFeesBips(), 200);
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

    function testCreditorCanDepositPrincipal() public {
        assertEq(vault.balanceOf(debtor), 0);
        vm.startPrank(creditor);
        token.approve(address(vault), DEBT_AMOUNT);
        vault.deposit(DEBT_AMOUNT, true);
        vm.stopPrank();

        assertEq(vault.balanceOf(debtor), DEBT_AMOUNT);
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

    function testDebtorCanPayInterest(
        uint256 interestAmount
    ) public principalPaid {
        vm.assume(interestAmount < type(uint256).max / VAULT_FEES_BIPS);
        token.mint(debtor, interestAmount);

        uint256 fees = (interestAmount * VAULT_FEES_BIPS) / 10_000;
        uint256 netInterestAmount = interestAmount - fees;

        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);
        vault.deposit(interestAmount, false);
        vm.stopPrank();

        assertEq(vault.balanceOf(creditor), netInterestAmount);
        assertEq(vault.balanceOf(owner), fees);
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

    function testStandardDepositNotAllowed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                ICorporateBondRepayVault.StandardDepositOrMintNotAllowed.selector
            )
        );
        vault.deposit(10 ether, address(this));
    }

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
}
