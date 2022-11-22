// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";

contract DeployMockToken is Script {
    function setUp() public { }

    function run() public {
        vm.startBroadcast();

        new ERC20Mock("ERC20 Mock", "MOCK", address(1), 0);

        vm.stopBroadcast();
    }
}
