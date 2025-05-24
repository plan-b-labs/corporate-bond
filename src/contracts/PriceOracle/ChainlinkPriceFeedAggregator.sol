// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title ChainlinkPriceFeedAggregator
 * @notice Aggregates two Chainlink price feeds to create a composite price feed
 * @dev Implements AggregatorV3Interface to be compatible with existing price feed consumers
 */
contract ChainlinkPriceFeedAggregator is AggregatorV3Interface {
    AggregatorV3Interface public immutable priceFeed1;
    AggregatorV3Interface public immutable priceFeed2;
    string public description;
    uint8 public immutable decimals;

    error PriceFeedsTimeMismatch(uint256 time1, uint256 time2);
    error ZeroAddress();

    // Maximum allowed time difference between price feed updates (1 hour)
    uint256 constant MAX_TIME_DIFF = 1 hours;

    constructor(
        address priceFeed1_,
        address priceFeed2_,
        string memory description_,
        uint8 decimals_
    ) {
        if (priceFeed1_ == address(0) || priceFeed2_ == address(0)) {
            revert ZeroAddress();
        }

        priceFeed1 = AggregatorV3Interface(priceFeed1_);
        priceFeed2 = AggregatorV3Interface(priceFeed2_);
        description = description_;
        decimals = decimals_;
    }

    /**
     * @notice Returns the latest round data from both price feeds and calculates the composite price
     * @dev Reverts if the price feeds are not on the same round
     * @return roundId The round ID from the latest price update
     * @return answer The composite price (price1 / price2)
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (
            uint80 roundId1,
            int256 price1,
            uint256 startedAt1,
            uint256 updatedAt1,
            uint80 answeredInRound1
        ) = priceFeed1.latestRoundData();

        (, int256 price2,, uint256 updatedAt2,) = priceFeed2.latestRoundData();

        // Ensure price updates are close in time
        if (updatedAt1 > updatedAt2) {
            if (updatedAt1 - updatedAt2 > MAX_TIME_DIFF) {
                revert PriceFeedsTimeMismatch(updatedAt1, updatedAt2);
            }
        } else {
            if (updatedAt2 - updatedAt1 > MAX_TIME_DIFF) {
                revert PriceFeedsTimeMismatch(updatedAt1, updatedAt2);
            }
        }

        // Calculate composite price: price1 / price2
        answer = (price1 * int256(10 ** decimals)) / price2;

        return (roundId1, answer, startedAt1, updatedAt1, answeredInRound1);
    }

    /**
     * @notice Returns the round data for a specific round ID
     * @dev Reverts if the price feeds don't have data for the requested round
     * @param roundId_ The round ID to get price data for
     * @return roundId The round ID
     * @return answer The composite price
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function getRoundData(
        uint80 roundId_
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (
            uint80 roundId1,
            int256 price1,
            uint256 startedAt1,
            uint256 updatedAt1,
            uint80 answeredInRound1
        ) = priceFeed1.getRoundData(roundId_);

        (, int256 price2,, uint256 updatedAt2,) = priceFeed2.getRoundData(roundId_);

        // Ensure price updates are close in time
        if (updatedAt1 > updatedAt2) {
            if (updatedAt1 - updatedAt2 > MAX_TIME_DIFF) {
                revert PriceFeedsTimeMismatch(updatedAt1, updatedAt2);
            }
        } else {
            if (updatedAt2 - updatedAt1 > MAX_TIME_DIFF) {
                revert PriceFeedsTimeMismatch(updatedAt1, updatedAt2);
            }
        }

        // Calculate composite price: price1 / price2
        answer = (price1 * int256(10 ** decimals)) / price2;

        return (roundId1, answer, startedAt1, updatedAt1, answeredInRound1);
    }

    /**
     * @notice Returns the version of the price feed
     * @return The version number
     */
    function version() external pure returns (uint256) {
        return 1;
    }
}
