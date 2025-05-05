// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ChainlinkPriceFeedProxy} from "../../src/contracts/PriceOracle/ChainlinkPriceFeedProxy.sol";
import {Script} from "forge-std/Script.sol";

contract DeployChainlinkPriceFeedProxy is Script {
    function run(
        address teleporterRegistry,
        uint256 minTeleporterVersion,
        address owner,
        bytes32 priceFeedChainId,
        address priceFeedScraperAddress,
        string memory description,
        uint8 decimals
    ) external returns (address) {
        vm.startBroadcast();

        ChainlinkPriceFeedProxy proxy = new ChainlinkPriceFeedProxy(
            teleporterRegistry,
            minTeleporterVersion,
            owner,
            priceFeedChainId,
            priceFeedScraperAddress,
            description,
            decimals
        );

        vm.stopBroadcast();

        return address(proxy);
    }
}
