// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    TeleporterFeeInfo,
    TeleporterMessageInput
} from "@ava-labs/icm-contracts/teleporter/ITeleporterMessenger.sol";
import {TeleporterRegistryOwnableApp} from
    "@ava-labs/icm-contracts/teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {AggregatorV3Interface} from
    "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

struct ChainlinkPriceData {
    uint80 roundId;
    int256 answer;
    uint256 startedAt;
    uint256 updatedAt;
    uint80 answeredInRound;
}

/**
 * @title ChainlinkPriceFeedProxy
 * @notice Proxies price data received from another chain via ICM as a Chainlink price feed
 * @dev This contract implements AggregatorV3Interface to be compatible with existing price feed consumers
 */
contract ChainlinkPriceFeedProxy is AggregatorV3Interface, TeleporterRegistryOwnableApp {
    // Price data storage
    mapping(uint80 => ChainlinkPriceData) private priceDataHistory;
    uint80 public latestRoundId;

    // Source chain information
    bytes32 public immutable priceFeedChainId;
    address public immutable priceFeedScraperAddress;

    // Chainlink price feed information
    string public description;
    uint8 public immutable decimals;

    // Events
    event PriceDataUpdated(
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );

    // Errors
    error InvalidSource(bytes32 sourceChainId, address sourceSender);
    error InvalidMessage();
    error RoundNotFound(uint80 roundId);

    // @notice Version of the price feed
    uint256 public constant version = 1;

    constructor(
        address teleporterRegistry_,
        uint256 minTeleporterVersion_,
        address owner_,
        bytes32 priceFeedChainId_,
        address priceFeedScraperAddress_,
        string memory description_,
        uint8 decimals_
    ) TeleporterRegistryOwnableApp(teleporterRegistry_, owner_, minTeleporterVersion_) {
        priceFeedChainId = priceFeedChainId_;
        priceFeedScraperAddress = priceFeedScraperAddress_;
        description = description_;
        decimals = decimals_;
    }

    /**
     * @notice Implements AggregatorV3Interface.latestRoundData()
     * @return roundId The round ID from the latest price update
     * @return answer The price
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
        ChainlinkPriceData memory data = priceDataHistory[latestRoundId];
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /**
     * @notice Implements AggregatorV3Interface.getRoundData()
     * @dev Returns price data for a specific round ID. Only historical data for rounds that have occurred since deployment is available.
     * @param _roundId The round ID to get price data for
     * @return roundId The round ID
     * @return answer The price
     * @return startedAt When the round started
     * @return updatedAt When the round was updated
     * @return answeredInRound The round in which the answer was computed
     */
    function getRoundData(
        uint80 _roundId
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
        ChainlinkPriceData memory data = priceDataHistory[_roundId];
        if (data.roundId == 0) {
            revert RoundNotFound(_roundId);
        }
        return (data.roundId, data.answer, data.startedAt, data.updatedAt, data.answeredInRound);
    }

    /**
     * @dev Receives and validates price data from the source chain
     */
    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override {
        // Validate source
        if (
            sourceBlockchainID != priceFeedChainId || originSenderAddress != priceFeedScraperAddress
        ) {
            revert InvalidSource(sourceBlockchainID, originSenderAddress);
        }

        // Decode price data
        ChainlinkPriceData memory newPriceData = abi.decode(message, (ChainlinkPriceData));

        // Store price data in history
        priceDataHistory[newPriceData.roundId] = newPriceData;
        latestRoundId = newPriceData.roundId;

        emit PriceDataUpdated(
            newPriceData.roundId,
            newPriceData.answer,
            newPriceData.startedAt,
            newPriceData.updatedAt,
            newPriceData.answeredInRound
        );
    }

    /**
     * @dev Implements access control for registry updates
     */
    function _checkTeleporterRegistryAppAccess() internal view override {
        _checkOwner();
    }
}
