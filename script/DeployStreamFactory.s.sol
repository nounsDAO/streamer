// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import { Stream } from "../src/Stream.sol";
import { StreamFactory } from "../src/StreamFactory.sol";

contract DeployStreamFactory is Script {
    function setUp() public { }

    function run() public {
        vm.startBroadcast();

        address streamLogicAddress = address(new Stream());
        new StreamFactory(streamLogicAddress);

        vm.stopBroadcast();
    }
}
