// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {MockV3Aggregator} from "@foundry-starter-kit/src/test/mocks/MockV3Aggregator.sol";
import {Script} from "forge-std/Script.sol";

contract DeployMockV3Aggregator is Script {
    function run(uint8 decimals, int256 initialPrice) external returns (address) {
        vm.startBroadcast();

        MockV3Aggregator aggregator = new MockV3Aggregator(decimals, initialPrice);

        vm.stopBroadcast();

        return address(aggregator);
    }
}
