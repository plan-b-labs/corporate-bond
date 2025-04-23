// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CorporateBond} from "../../src/contracts/CorporateBond/CorporateBond.sol";
import {CorporateBondRepayVault} from
    "../../src/contracts/CorporateBond/CorporateBondRepayVault.sol";
import {
    CorporateBondRepayVaultFactory,
    ICorporateBondRepayVaultFactory
} from "../../src/contracts/CorporateBond/CorporateBondRepayVaultFactory.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CorporateBondRepayVaultFactoryTest is Test {
    CorporateBondRepayVaultFactory public factory;
    CorporateBond public bond;
    MockERC20 public token;

    address public owner;
    address public debtor;
    address public creditor;
    address public feesRecipient;
    uint256 public tokenId;

    uint256 constant DEBT_AMOUNT = 1000 ether;
    uint48 constant FEES_BIPS = 100;
    uint64 constant BOND_MATURITY = 365 days;

    function setUp() public {
        owner = makeAddr("owner");
        debtor = makeAddr("debtor");
        creditor = makeAddr("creditor");
        feesRecipient = makeAddr("feesRecipient");

        // Deploy mock ERC20 token
        token = new MockERC20();

        // Deploy CorporateBond NFT
        bond = new CorporateBond(address(this));
        tokenId = bond.safeMint(creditor, "test-uri");

        // Deploy factory
        factory = new CorporateBondRepayVaultFactory(owner);
    }

    function testCreateVault() public {
        uint64 maturity = uint64(block.timestamp + BOND_MATURITY);

        vm.expectEmit(false, true, true, true);
        emit ICorporateBondRepayVaultFactory.VaultCreated(
            address(0), // We don't know the vault address yet
            address(bond),
            tokenId,
            debtor,
            address(token),
            DEBT_AMOUNT,
            maturity,
            false,
            0,
            FEES_BIPS,
            feesRecipient
        );

        address vault = factory.createVault(
            address(bond),
            tokenId,
            debtor,
            address(token),
            DEBT_AMOUNT,
            maturity,
            false,
            0,
            FEES_BIPS,
            feesRecipient
        );

        CorporateBondRepayVault vaultContract = CorporateBondRepayVault(vault);

        // Verify vault configuration
        assertEq(vaultContract.owner(), owner);
        assertEq(address(vaultContract.bondNFTContract()), address(bond));
        assertEq(vaultContract.bondNFTTokenId(), tokenId);
        assertEq(vaultContract.debtor(), debtor);
        assertEq(address(vaultContract.asset()), address(token));
        assertEq(vaultContract.debtAmount(), DEBT_AMOUNT);
        assertEq(vaultContract.bondMaturity(), maturity);
        assertEq(vaultContract.principalPaid(), false);
        assertEq(vaultContract.principalRepaid(), 0);
        assertEq(vaultContract.feesBips(), FEES_BIPS);
        assertEq(vaultContract.feesRecipient(), feesRecipient);
    }

    function testCannotCreateVaultWithPastMaturity() public {
        uint64 pastMaturity = uint64(block.timestamp - 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ICorporateBondRepayVaultFactory.InvalidBondMaturity.selector, pastMaturity
            )
        );

        factory.createVault(
            address(bond),
            tokenId,
            debtor,
            address(token),
            DEBT_AMOUNT,
            pastMaturity,
            false,
            0,
            FEES_BIPS,
            feesRecipient
        );
    }

    function testCreateVaultWithPrincipalPaid() public {
        uint64 maturity = uint64(block.timestamp + BOND_MATURITY);

        address vault = factory.createVault(
            address(bond),
            tokenId,
            debtor,
            address(token),
            DEBT_AMOUNT,
            maturity,
            true,
            DEBT_AMOUNT / 2,
            FEES_BIPS,
            feesRecipient
        );

        CorporateBondRepayVault vaultContract = CorporateBondRepayVault(vault);

        assertTrue(vaultContract.principalPaid());
        assertEq(vaultContract.principalRepaid(), DEBT_AMOUNT / 2);
    }

    function testAnyoneCanCreateVault() public {
        uint64 maturity = uint64(block.timestamp + BOND_MATURITY);

        vm.prank(makeAddr("random"));
        address vault = factory.createVault(
            address(bond),
            tokenId,
            debtor,
            address(token),
            DEBT_AMOUNT,
            maturity,
            false,
            0,
            FEES_BIPS,
            feesRecipient
        );

        assertTrue(vault != address(0));
    }
}
