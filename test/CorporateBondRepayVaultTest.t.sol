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

    address public borrower;
    address public lender;
    uint256 public tokenId;

    function setUp() public {
        borrower = makeAddr("borrower");
        lender = makeAddr("lender");

        // Deploy mock ERC20 token
        token = new MockERC20();

        // Deploy CorporateBond NFT
        bond = new CorporateBond(address(this));
        tokenId = bond.safeMint(lender, "test-uri");

        // Deploy vault
        vault = new CorporateBondRepayVault(bond, tokenId, borrower, token);
    }

    function testBorrowerCanDeposit() public {
        uint256 depositAmount = 1000e18;
        token.mint(borrower, depositAmount);

        vm.startPrank(borrower);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, lender);
        vm.stopPrank();

        assertEq(vault.balanceOf(lender), depositAmount);
    }

    function testNonBorrowerCannotDeposit() public {
        uint256 depositAmount = 1000e18;
        token.mint(address(this), depositAmount);

        token.approve(address(vault), depositAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyBorrower.selector, address(this), borrower
            )
        );
        vault.deposit(depositAmount, lender);
    }

    function testLenderCanWithdraw() public {
        uint256 depositAmount = 1000e18;
        token.mint(borrower, depositAmount);

        // Borrower deposits
        vm.startPrank(borrower);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, lender);
        vm.stopPrank();

        // Lender withdraws
        vm.startPrank(lender);
        vault.withdraw(depositAmount, lender, lender);
        vm.stopPrank();

        assertEq(token.balanceOf(lender), depositAmount);
    }

    function testNonLenderCannotWithdraw() public {
        uint256 depositAmount = 1000e18;
        token.mint(borrower, depositAmount);

        // Borrower deposits
        vm.startPrank(borrower);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, lender);
        vm.stopPrank();

        // Non-lender tries to withdraw
        address nonLender = makeAddr("nonLender");
        vm.startPrank(nonLender);
        vm.expectRevert(
            abi.encodeWithSelector(CorporateBondRepayVault.OnlyLender.selector, nonLender, lender)
        );
        vault.withdraw(depositAmount, nonLender, lender);
        vm.stopPrank();
    }

    function testDepositToNonLenderFails() public {
        uint256 depositAmount = 1000e18;
        token.mint(borrower, depositAmount);
        address nonLender = makeAddr("nonLender");

        vm.startPrank(borrower);
        token.approve(address(vault), depositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                CorporateBondRepayVault.OnlyLenderRecipient.selector, nonLender, lender
            )
        );
        vault.deposit(depositAmount, nonLender);
        vm.stopPrank();
    }

    function testLenderTransferUpdatesAccess() public {
        uint256 depositAmount = 1000e18;
        token.mint(borrower, depositAmount);
        address newLender = makeAddr("newLender");

        // Initial deposit
        vm.startPrank(borrower);
        token.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, lender);
        vm.stopPrank();

        // Transfer NFT to new lender
        vm.prank(lender);
        bond.transferFrom(lender, newLender, tokenId);

        // Original lender should no longer be able to withdraw
        vm.startPrank(lender);
        vm.expectRevert(
            abi.encodeWithSelector(CorporateBondRepayVault.OnlyLender.selector, lender, newLender)
        );
        vault.withdraw(depositAmount, lender, lender);
        vm.stopPrank();
    }
}
