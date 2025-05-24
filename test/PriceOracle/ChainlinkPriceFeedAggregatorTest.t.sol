// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ChainlinkPriceFeedAggregator} from
    "../../src/contracts/PriceOracle/ChainlinkPriceFeedAggregator.sol";
import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {Test} from "forge-std/Test.sol";

contract MockPriceFeed is AggregatorV3Interface {
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;
    uint8 public decimals;
    string public description;

    constructor(uint8 decimals_, string memory description_) {
        decimals = decimals_;
        description = description_;
    }

    function setPriceData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) external {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId_,
            int256 answer_,
            uint256 startedAt_,
            uint256 updatedAt_,
            uint80 answeredInRound_
        )
    {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId_,
            int256 answer_,
            uint256 startedAt_,
            uint256 updatedAt_,
            uint80 answeredInRound_
        )
    {
        require(_roundId == roundId, "Round not found");
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

contract ChainlinkPriceFeedAggregatorTest is Test {
    ChainlinkPriceFeedAggregator public aggregator;
    MockPriceFeed public priceFeed1;
    MockPriceFeed public priceFeed2;

    uint8 constant DECIMALS = 8;
    string constant DESCRIPTION = "BTC/ETH";

    function setUp() public {
        priceFeed1 = new MockPriceFeed(DECIMALS, "BTC/USD");
        priceFeed2 = new MockPriceFeed(DECIMALS, "ETH/USD");

        aggregator = new ChainlinkPriceFeedAggregator(
            address(priceFeed1), address(priceFeed2), DESCRIPTION, DECIMALS
        );
    }

    function testInitialState() public view {
        assertEq(address(aggregator.priceFeed1()), address(priceFeed1));
        assertEq(address(aggregator.priceFeed2()), address(priceFeed2));
        assertEq(aggregator.description(), DESCRIPTION);
        assertEq(aggregator.decimals(), DECIMALS);
    }

    function testCannotDeployWithZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceFeedAggregator.ZeroAddress.selector));
        new ChainlinkPriceFeedAggregator(address(0), address(priceFeed2), DESCRIPTION, DECIMALS);

        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceFeedAggregator.ZeroAddress.selector));
        new ChainlinkPriceFeedAggregator(address(priceFeed1), address(0), DESCRIPTION, DECIMALS);
    }

    function testLatestRoundData() public {
        // Set up price data
        uint256 timestamp = block.timestamp;
        priceFeed1.setPriceData(1, 100_000e8, timestamp, timestamp, 1); // BTC = $100,000
        priceFeed2.setPriceData(1, 2000e8, timestamp, timestamp, 1); // ETH = $2,000

        // Get latest round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();

        // BTC/ETH = 100,000/2,000 = 50
        assertEq(answer, 50e8);
        assertEq(roundId, 1);
        assertEq(startedAt, timestamp);
        assertEq(updatedAt, timestamp);
        assertEq(answeredInRound, 1);
    }

    function testGetRoundData() public {
        // Set up price data
        uint256 timestamp = block.timestamp;
        priceFeed1.setPriceData(1, 100_000e8, timestamp, timestamp, 1); // BTC = $100,000
        priceFeed2.setPriceData(1, 2000e8, timestamp, timestamp, 1); // ETH = $2,000

        // Get round data
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.getRoundData(1);

        // BTC/ETH = 100,000/2,000 = 50
        assertEq(answer, 50e8);
        assertEq(roundId, 1);
        assertEq(startedAt, timestamp);
        assertEq(updatedAt, timestamp);
        assertEq(answeredInRound, 1);
    }

    function testTimeMismatch() public {
        uint256 timestamp = block.timestamp;
        priceFeed1.setPriceData(1, 100_000e8, timestamp, timestamp, 1);
        priceFeed2.setPriceData(1, 2000e8, timestamp, timestamp + 2 hours, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ChainlinkPriceFeedAggregator.PriceFeedsTimeMismatch.selector,
                timestamp,
                timestamp + 2 hours
            )
        );
        aggregator.latestRoundData();
    }

    function testVersion() public view {
        assertEq(aggregator.version(), 1);
    }
}
