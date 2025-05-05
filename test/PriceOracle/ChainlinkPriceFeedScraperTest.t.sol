// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    ChainlinkPriceData,
    ChainlinkPriceFeedScraper
} from "../../src/contracts/PriceOracle/ChainlinkPriceFeedScraper.sol";
import {WarpMessengerMock} from "../../src/contracts/mocks/WarpMessengerMock.sol";
import {TeleporterMessenger} from "@ava-labs/icm-contracts/teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry,
    TeleporterRegistry
} from "@ava-labs/icm-contracts/teleporter/registry/TeleporterRegistry.sol";
import {MockV3Aggregator} from "@foundry-starter-kit/src/test/mocks/MockV3Aggregator.sol";
import {Test} from "forge-std/Test.sol";

contract ChainlinkPriceFeedScraperTest is Test {
    ChainlinkPriceFeedScraper private scraper;
    MockV3Aggregator private mockPriceFeed;
    WarpMessengerMock private mockWarpMessenger;
    TeleporterMessenger private teleporterMessenger;
    TeleporterRegistry private teleporterRegistry;

    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    address private constant OWNER = address(0x1);
    bytes32 private constant DESTINATION_BLOCKCHAIN_ID = bytes32(uint256(1));
    bytes32 private constant MESSAGE_ID =
        0x1d18bfb34f561bded9d9f0ee259d6b79524cdbacbb4e63abd056aa555f513510;
    address private constant DESTINATION_ADDRESS = address(0x2);
    address private constant FEE_TOKEN_ADDRESS = address(0x3);
    uint256 private constant FEE_AMOUNT = 0;
    uint256 private constant REQUIRED_GAS = 100_000;
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    // MockV3Aggregator configuration
    uint8 private constant DECIMALS = 8;
    int256 private constant INITIAL_PRICE = 2000e8;

    function setUp() public {
        ProtocolRegistryEntry[] memory protocolRegistryEntry = new ProtocolRegistryEntry[](1);

        mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE);
        mockWarpMessenger = new WarpMessengerMock(DESTINATION_BLOCKCHAIN_ID, MESSAGE_ID);
        vm.etch(WARP_PRECOMPILE, address(mockWarpMessenger).code);

        teleporterMessenger = new TeleporterMessenger();
        protocolRegistryEntry[0] = ProtocolRegistryEntry(1, address(teleporterMessenger));
        teleporterRegistry = new TeleporterRegistry(protocolRegistryEntry);

        vm.prank(OWNER);
        scraper = new ChainlinkPriceFeedScraper(
            address(teleporterRegistry), MIN_TELEPORTER_VERSION, OWNER, address(mockPriceFeed)
        );
    }

    function test_constructor() public view {
        assertEq(address(scraper.priceFeed()), address(mockPriceFeed));
        assertEq(scraper.owner(), OWNER);
    }

    function test_RevertConstructorZeroAddress() public {
        vm.expectRevert(ChainlinkPriceFeedScraper.ZeroAddress.selector);
        new ChainlinkPriceFeedScraper(
            address(teleporterRegistry), MIN_TELEPORTER_VERSION, OWNER, address(0)
        );
    }

    function test_getLatestRoundData() public view {
        ChainlinkPriceData memory data = scraper.getLatestRoundData();

        assertEq(data.roundId, 1);
        assertEq(data.answer, INITIAL_PRICE);
        assertEq(data.answeredInRound, 1);
    }

    function test_sendLatestRoundData() public {
        bytes32 messageId = scraper.sendLatestRoundData(
            DESTINATION_BLOCKCHAIN_ID,
            DESTINATION_ADDRESS,
            FEE_TOKEN_ADDRESS,
            FEE_AMOUNT,
            REQUIRED_GAS
        );

        assertEq(messageId, MESSAGE_ID);
    }

    function test_RevertOnReceiveTeleporterMessage() public {
        vm.expectRevert(ChainlinkPriceFeedScraper.UnexpectedMessage.selector);
        vm.prank(address(teleporterMessenger));
        scraper.receiveTeleporterMessage(DESTINATION_BLOCKCHAIN_ID, DESTINATION_ADDRESS, bytes(""));
    }

    function test_updatePriceData() public {
        int256 newPrice = 2500e8;
        mockPriceFeed.updateAnswer(newPrice);

        ChainlinkPriceData memory data = scraper.getLatestRoundData();
        assertEq(data.answer, newPrice);
        assertEq(data.roundId, 2);
    }
}
