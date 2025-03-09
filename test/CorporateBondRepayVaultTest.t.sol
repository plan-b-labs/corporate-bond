// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {CorporateBond} from "../src/CorporateBond/CorporateBond.sol";
import {CorporateBondRepayVault} from "../src/CorporateBond/CorporateBondRepayVault.sol";
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

    address public debtor;
    address public creditor;
    uint256 public tokenId;

    function setUp() public {
        debtor = makeAddr("debtor");
        creditor = makeAddr("creditor");

        // Deploy mock ERC20 token
        token = new MockERC20();

        // Deploy CorporateBond NFT
        bond = new CorporateBond(address(this));
        tokenId = bond.safeMint(creditor, "test-uri");

        // Deploy vault
        vault = new CorporateBondRepayVault(bond, tokenId, debtor, token);
    }

    function testDebtorCanDeposit() public {
        uint256 depositAmount = 1000e18;
        token.mint(debtor, depositAmount);

        vm.startPrank(debtor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, creditor);
        vm.stopPrank();

        assertEq(vault.balanceOf(creditor), depositAmount);
    }

    function testNonDebtorCannotDeposit() public {
        uint256 depositAmount = 1000e18;
        token.mint(address(this), depositAmount);

        token.approve(address(vault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyDebtor.selector, address(this), debtor
            )
        );
        vault.deposit(depositAmount, creditor);
    }

    function testCreditorCanWithdraw() public {
        uint256 depositAmount = 1000e18;
        token.mint(debtor, depositAmount);

        // Debtor deposits
        vm.startPrank(debtor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, creditor);
        vm.stopPrank();

        // Creditor withdraws
        vm.startPrank(creditor);
        vault.withdraw(depositAmount, creditor, creditor);
        vm.stopPrank();

        assertEq(token.balanceOf(creditor), depositAmount);
    }

    function testNonCreditorCannotWithdraw() public {
        uint256 depositAmount = 1000e18;
        token.mint(debtor, depositAmount);

        // Debtor deposits
        vm.startPrank(debtor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, creditor);
        vm.stopPrank();

        // Non-creditor tries to withdraw
        address nonCreditor = makeAddr("nonCreditor");
        vm.startPrank(nonCreditor);
        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyCreditor.selector, nonCreditor, creditor
            )
        );
        vault.withdraw(depositAmount, nonCreditor, creditor);
        vm.stopPrank();
    }

    function testDepositToNonCreditorFails() public {
        uint256 depositAmount = 1000e18;
        token.mint(debtor, depositAmount);
        address nonCreditor = makeAddr("nonCreditor");

        vm.startPrank(debtor);
        token.approve(address(vault), depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyCreditorRecipient.selector, nonCreditor, creditor
            )
        );
        vault.deposit(depositAmount, nonCreditor);
        vm.stopPrank();
    }

    function testCreditorTransferUpdatesAccess() public {
        uint256 depositAmount = 1000e18;
        token.mint(debtor, depositAmount);
        address newCreditor = makeAddr("newCreditor");

        // Initial deposit
        vm.startPrank(debtor);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, creditor);
        vm.stopPrank();

        // Transfer NFT to new creditor
        vm.prank(creditor);
        bond.transferFrom(creditor, newCreditor, tokenId);

        // Original creditor should no longer be able to withdraw
        vm.startPrank(creditor);
        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyCreditor.selector, creditor, newCreditor
            )
        );
        vault.withdraw(depositAmount, creditor, creditor);
        vm.stopPrank();
    }
}
