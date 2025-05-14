// SPDX-License-Identifier: MIT

pragma solidity 0.8.25;

import {CorporateBond} from "../../src/contracts/CorporateBond/CorporateBond.sol";
import {
    CorporateBondRepayVault,
    ICorporateBondRepayVault
} from "../../src/contracts/CorporateBond/CorporateBondRepayVault.sol";
import {
    ChainlinkPriceData,
    ChainlinkPriceFeedProxy
} from "../../src/contracts/PriceOracle/ChainlinkPriceFeedProxy.sol";

import {WarpMessengerMock} from "../../src/contracts/mocks/WarpMessengerMock.sol";
import {TeleporterMessenger} from "@ava-labs/icm-contracts/teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry,
    TeleporterRegistry
} from "@ava-labs/icm-contracts/teleporter/registry/TeleporterRegistry.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Test} from "forge-std/Test.sol";

contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(
        uint8 decimals_
    ) ERC20("Mock Token", "MTK") {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CorporateBondRepayVaultTest is Test {
    CorporateBond public bond;
    CorporateBondRepayVault public vault;
    MockERC20 public token;
    ChainlinkPriceFeedProxy public priceFeed;
    TeleporterRegistry public registry;

    address public owner;
    address public debtor;
    address public creditor;
    address public feesRecipient;
    uint256 public tokenId;

    int256 constant INITIAL_PRICE = 10_156_452_126_332; // $101,564.52126332
    uint256 constant DEBT_AMOUNT = 10_000_000e8; // $10,000,000
    uint48 constant FEES_BIPS = 100; // 1%
    uint8 constant TOKEN_DECIMALS = 8;
    uint8 constant PRICE_FEED_DECIMALS = 8;
    uint256 constant TOKEN_DEPOSIT_AMOUNT = 100e8; // 100 BTC

    WarpMessengerMock private mockWarpMessenger;
    TeleporterMessenger public teleporterMessenger;

    function setUp() public {
        owner = makeAddr("owner");
        debtor = makeAddr("debtor");
        creditor = makeAddr("creditor");
        feesRecipient = makeAddr("feesRecipient");

        // Deploy mock ERC20 token with 18 decimals
        token = new MockERC20(TOKEN_DECIMALS);
        token.mint(creditor, TOKEN_DEPOSIT_AMOUNT);
        token.mint(debtor, TOKEN_DEPOSIT_AMOUNT);

        // Set up mock warp messenger
        mockWarpMessenger = new WarpMessengerMock(bytes32(uint256(1)), bytes32(0));
        vm.etch(0x0200000000000000000000000000000000000005, address(mockWarpMessenger).code);

        // Set up ICM contracts
        teleporterMessenger = new TeleporterMessenger();
        ProtocolRegistryEntry[] memory entries = new ProtocolRegistryEntry[](1);
        entries[0] = ProtocolRegistryEntry(1, address(teleporterMessenger));
        registry = new TeleporterRegistry(entries);

        // Deploy price feed
        priceFeed = new ChainlinkPriceFeedProxy(
            address(registry),
            1, // minTeleporterVersion
            owner,
            bytes32(uint256(1)), // sourceChainId
            address(0x123), // sourcePriceFeed
            "TOKEN/USD",
            PRICE_FEED_DECIMALS
        );

        // Set initial price
        vm.prank(address(teleporterMessenger));
        priceFeed.receiveTeleporterMessage(
            bytes32(uint256(1)),
            address(0x123),
            abi.encode(
                ChainlinkPriceData({
                    roundId: 1,
                    answer: INITIAL_PRICE,
                    startedAt: block.timestamp,
                    updatedAt: block.timestamp,
                    answeredInRound: 1
                })
            )
        );

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
            feesRecipient,
            address(priceFeed)
        );
    }

    modifier principalPaid() {
        vm.startPrank(creditor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();
        _;
    }

    function _calculateValue(
        uint256 assets
    ) internal pure returns (uint256) {
        // Convert BTC amount to USD: BTC * price in USD
        // Example: 100 BTC * $100,000 = $10M
        return (assets * uint256(INITIAL_PRICE)) / (10 ** TOKEN_DECIMALS);
    }

    function _calculateAssets(
        uint256 targetValue
    ) internal pure returns (uint256) {
        return (targetValue * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_PRICE);
    }

    // Principal-related tests
    function testCreditorCanDepositPrincipal() public {
        assertEq(vault.balanceOf(debtor), 0);
        vm.startPrank(creditor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();

        assertEq(vault.balanceOf(debtor), _calculateAssets(DEBT_AMOUNT));
        assertTrue(vault.principalPaid());
    }

    function testCreditorCannotDepositPrincipalTwice() public principalPaid {
        vm.startPrank(creditor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(ICorporateBondRepayVault.PrincipalAlreadyPaid.selector)
        );
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testDebtorCannotDepositPrincipalBeforeCreditor() public {
        vm.startPrank(debtor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ICorporateBondRepayVault.PrincipalNotPaid.selector));
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testDebtorCanWithdrawPrincipal() public principalPaid {
        // Debtor withdraws principal
        vm.startPrank(debtor);
        vault.withdraw(_calculateAssets(DEBT_AMOUNT), debtor, debtor);
        vm.stopPrank();

        assertEq(token.balanceOf(debtor), TOKEN_DEPOSIT_AMOUNT + _calculateAssets(DEBT_AMOUNT)); // Initial balance + withdrawn principal
        assertEq(vault.balanceOf(debtor), 0);
        assertTrue(vault.principalPaid());
    }

    function testDebtorCanRepayPrincipal() public principalPaid {
        // Debtor repays principal
        vm.startPrank(debtor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();

        assertEq(vault.balanceOf(creditor), _calculateAssets(DEBT_AMOUNT));
        assertEq(vault.principalRepaid(), DEBT_AMOUNT);
    }

    function testCreditorCanWithdrawRepaidPrincipal() public principalPaid {
        // Debtor repays principal
        vm.startPrank(debtor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();

        // Creditor withdraws principal
        vm.startPrank(creditor);
        vault.withdraw(_calculateAssets(DEBT_AMOUNT), creditor, creditor);
        vm.stopPrank();

        assertEq(token.balanceOf(creditor), TOKEN_DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(creditor), 0);
    }

    // Interest and fees tests
    function testDebtorCanPayInterest(
        uint256 interestAmount
    ) public principalPaid {
        // Bound interest amount between 0.01 BTC and 100 BTC
        interestAmount = bound(interestAmount, 1e6, 1e10);

        uint256 targetInterestValue = _calculateValue(interestAmount);
        token.mint(debtor, interestAmount);

        uint256 fees = (_calculateAssets(targetInterestValue) * FEES_BIPS) / 10_000;
        uint256 netInterestAmount = _calculateAssets(targetInterestValue) - fees;

        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);
        vault.deposit(interestAmount, targetInterestValue, false);
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
        vault.deposit(depositAmount, DEBT_AMOUNT, false);
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
        uint256 interestAmount = 1e7;
        uint256 targetInterestValue = 10_000e8;
        token.mint(debtor, interestAmount);

        // Debtor pays interest, generating fees
        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);
        (, uint256 assetsDeposited) = vault.deposit(interestAmount, targetInterestValue, false);
        vm.stopPrank();

        uint256 fees = (assetsDeposited * FEES_BIPS) / 10_000;

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

    function testEmitsPrincipalPaidEvent() public {
        uint256 value = DEBT_AMOUNT; // The USD value should match the debt amount

        vm.startPrank(creditor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.PrincipalPaid(
            _calculateAssets(DEBT_AMOUNT), value, creditor, debtor
        );
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testEmitsPrincipalRepaidEvent() public principalPaid {
        vm.startPrank(debtor);
        token.approve(address(vault), TOKEN_DEPOSIT_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.PrincipalRepaid(
            _calculateAssets(DEBT_AMOUNT), DEBT_AMOUNT, debtor, creditor
        );
        vault.deposit(TOKEN_DEPOSIT_AMOUNT, DEBT_AMOUNT, true);
        vm.stopPrank();
    }

    function testEmitsInterestPaidEvent() public {
        uint256 interestAmount = 1e7; // 0.1 BTC
        uint256 targetInterestValue = 10_000e8;

        vm.startPrank(debtor);
        token.approve(address(vault), interestAmount);

        vm.expectEmit(true, true, true, true);
        emit ICorporateBondRepayVault.InterestPaid(
            _calculateAssets(targetInterestValue), targetInterestValue, debtor, creditor
        );
        vault.deposit(interestAmount, targetInterestValue, false);
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
