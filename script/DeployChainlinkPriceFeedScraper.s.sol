// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ChainlinkPriceFeedScraper} from "../src/contracts/PriceOracle/ChainlinkPriceFeedScraper.sol";
import {Script} from "forge-std/Script.sol";

contract DeployChainlinkPriceFeedScraper is Script {
    function run(
        address teleporterRegistry,
        uint256 minTeleporterVersion,
        address owner,
        address priceFeed
    ) external returns (address) {
        vm.startBroadcast();

        ChainlinkPriceFeedScraper scraper = new ChainlinkPriceFeedScraper(
            teleporterRegistry, minTeleporterVersion, owner, priceFeed
        );

        vm.stopBroadcast();

        return address(scraper);
    }
}
