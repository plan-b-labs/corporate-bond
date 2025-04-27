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
 * @title ChainlinkPriceFeedScraper
 * @notice Scrapes price data from Chainlink price feeds and prepares it for cross-chain messaging
 * @dev This contract will be used to send price data through ICM (Inter-Chain Messaging)
 */
contract ChainlinkPriceFeedScraper is TeleporterRegistryOwnableApp {
    // The Chainlink price feed to scrape
    AggregatorV3Interface public immutable priceFeed;

    // Events
    event PriceDataScraped(
        uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound
    );

    // Errors
    error ZeroAddress();
    error UnexpectedMessage();

    constructor(
        address teleporterRegistry_,
        uint256 minTeleporterVersion_,
        address owner_,
        address priceFeed_
    ) TeleporterRegistryOwnableApp(teleporterRegistry_, owner_, minTeleporterVersion_) {
        if (priceFeed_ == address(0)) {
            revert ZeroAddress();
        }

        priceFeed = AggregatorV3Interface(priceFeed_);
    }

    /**
     * @notice Send the latest price data from the Chainlink price feed via ICM
     * @dev This function will be called by the ICM system to get price data
     * @return messageID The message ID of the sent message
     */
    function sendLatestRoundData(
        bytes32 destinationBlockchainID,
        address destinationAddress,
        address feeTokenAddress,
        uint256 feeAmount,
        uint256 requiredGasLimit
    ) external returns (bytes32 messageID) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        return _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: destinationAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: feeTokenAddress, amount: feeAmount}),
                requiredGasLimit: requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(
                    ChainlinkPriceData({
                        roundId: roundId,
                        answer: answer,
                        startedAt: startedAt,
                        updatedAt: updatedAt,
                        answeredInRound: answeredInRound
                    })
                )
            })
        );
    }

    /**
     * @dev Implements the abstract function from TeleporterRegistryApp
     * Since this contract is primarily a sender of price data, this function
     * can be left minimal unless you need to handle incoming messages
     */
    function _receiveTeleporterMessage(
        bytes32, /*sourceBlockchainID*/
        address, /*originSenderAddress*/
        bytes memory /*message*/
    ) internal pure override {
        // This contract primarily sends data, so we revert with a custom error
        revert UnexpectedMessage();
    }

    /**
     * @dev Implements the abstract function from TeleporterRegistryApp
     * Since this inherits from TeleporterRegistryOwnableApp, this is already
     * handled by the parent contract using the Ownable pattern
     */
    function _checkTeleporterRegistryAppAccess() internal view override {
        _checkOwner();
    }

    /**
     * @notice Get the latest round data from the price feed without sending it
     * @return The latest price data from the feed
     */
    function getLatestRoundData() external view returns (ChainlinkPriceData memory) {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();

        return ChainlinkPriceData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });
    }
}
