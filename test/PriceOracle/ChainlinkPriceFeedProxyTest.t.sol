// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ChainlinkPriceFeedProxy} from "../../src/contracts/PriceOracle/ChainlinkPriceFeedProxy.sol";
import {ChainlinkPriceData} from "../../src/contracts/PriceOracle/ChainlinkPriceFeedProxy.sol";

import {WarpMessengerMock} from "../../src/contracts/mocks/WarpMessengerMock.sol";
import {TeleporterMessenger} from "@ava-labs/icm-contracts/teleporter/TeleporterMessenger.sol";
import {
    ProtocolRegistryEntry,
    TeleporterRegistry
} from "@ava-labs/icm-contracts/teleporter/registry/TeleporterRegistry.sol";
import {Test} from "forge-std/Test.sol";

contract ChainlinkPriceFeedProxyTest is Test {
    ChainlinkPriceFeedProxy public proxy;
    TeleporterMessenger public teleporterMessenger;
    TeleporterRegistry public teleporterRegistry;

    bytes32 public constant SOURCE_CHAIN_ID = bytes32(uint256(1));
    address public constant SOURCE_ADDRESS = address(0x123);
    uint8 public constant DECIMALS = 8;
    string public constant DESCRIPTION = "ETH/USD";
    uint256 private constant MIN_TELEPORTER_VERSION = 1;

    address public owner;

    address private constant WARP_PRECOMPILE = 0x0200000000000000000000000000000000000005;
    WarpMessengerMock private mockWarpMessenger;

    function setUp() public {
        owner = makeAddr("owner");

        // Set up mock warp messenger
        mockWarpMessenger = new WarpMessengerMock(SOURCE_CHAIN_ID, bytes32(0));
        vm.etch(WARP_PRECOMPILE, address(mockWarpMessenger).code);

        // Set up ICM contracts
        teleporterMessenger = new TeleporterMessenger();
        ProtocolRegistryEntry[] memory entries = new ProtocolRegistryEntry[](1);
        entries[0] = ProtocolRegistryEntry(1, address(teleporterMessenger));
        teleporterRegistry = new TeleporterRegistry(entries);

        // Deploy proxy
        proxy = new ChainlinkPriceFeedProxy(
            address(teleporterRegistry),
            MIN_TELEPORTER_VERSION,
            owner,
            SOURCE_CHAIN_ID,
            SOURCE_ADDRESS,
            DESCRIPTION,
            DECIMALS
        );
    }

    function testInitialState() public view {
        assertEq(proxy.priceFeedChainId(), SOURCE_CHAIN_ID);
        assertEq(proxy.priceFeedScraperAddress(), SOURCE_ADDRESS);
        assertEq(proxy.description(), DESCRIPTION);
        assertEq(proxy.decimals(), DECIMALS);
        assertEq(proxy.version(), 1);
    }

    function testReceiveValidPriceUpdate() public {
        ChainlinkPriceData memory priceData = ChainlinkPriceData({
            roundId: 1,
            answer: 2000e8, // $2000.00
            startedAt: block.timestamp,
            updatedAt: block.timestamp,
            answeredInRound: 1
        });

        bytes memory message = abi.encode(priceData);

        vm.prank(address(teleporterMessenger));
        proxy.receiveTeleporterMessage(SOURCE_CHAIN_ID, SOURCE_ADDRESS, message);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = proxy.latestRoundData();

        assertEq(roundId, priceData.roundId);
        assertEq(answer, priceData.answer);
        assertEq(startedAt, priceData.startedAt);
        assertEq(updatedAt, priceData.updatedAt);
        assertEq(answeredInRound, priceData.answeredInRound);
    }

    function testCannotReceiveFromWrongSource() public {
        bytes memory message = abi.encode(
            ChainlinkPriceData({
                roundId: 1,
                answer: 2000e8,
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: 1
            })
        );

        // Try with wrong chain ID
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPriceFeedProxy.InvalidSource.selector, bytes32(uint256(2)), SOURCE_ADDRESS
            )
        );
        vm.prank(address(teleporterMessenger));
        proxy.receiveTeleporterMessage(bytes32(uint256(2)), SOURCE_ADDRESS, message);

        // Try with wrong source address
        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPriceFeedProxy.InvalidSource.selector, SOURCE_CHAIN_ID, address(0x456)
            )
        );
        vm.prank(address(teleporterMessenger));
        proxy.receiveTeleporterMessage(SOURCE_CHAIN_ID, address(0x456), message);
    }

    function testGetHistoricalRoundData() public {
        // Submit multiple rounds
        for (uint80 i = 1; i <= 3; i++) {
            ChainlinkPriceData memory priceData = ChainlinkPriceData({
                roundId: i,
                answer: int256(uint256(i)) * 1000e8,
                startedAt: block.timestamp,
                updatedAt: block.timestamp,
                answeredInRound: i
            });

            vm.prank(address(teleporterMessenger));
            proxy.receiveTeleporterMessage(SOURCE_CHAIN_ID, SOURCE_ADDRESS, abi.encode(priceData));
        }

        // Check historical data
        for (uint80 i = 1; i <= 3; i++) {
            (
                uint80 roundId,
                int256 answer,
                , // startedAt (unused)
                , // updatedAt (unused)
                uint80 answeredInRound
            ) = proxy.getRoundData(i);

            assertEq(roundId, i);
            assertEq(answer, int256(uint256(i)) * 1000e8);
            assertEq(answeredInRound, i);
        }
    }

    function testCannotGetNonexistentRound() public {
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceFeedProxy.RoundNotFound.selector, 999));
        proxy.getRoundData(999);
    }
}
