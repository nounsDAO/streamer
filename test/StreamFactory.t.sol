// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamFactoryTest is Test {
    StreamFactory factory;

    address recipient = address(0x1001);
    ERC20Mock token;

    function setUp() public {
        token = new ERC20Mock("mock-token", "MOK", address(1), 0);

        Stream streamImplementation = new Stream();
        factory = new StreamFactory(address(streamImplementation));
    }

    function testStream() public {
        uint256 startTime = 1640988000; // 2022-01-01 00:00:00
        uint256 stopTime = 1672524000; // 2023-01-01 00:00:00
        uint256 deposit = 999975024000; // ~1M * 1e6

        vm.warp(startTime);

        IStream stream =
            IStream(factory.createStream(recipient, deposit, address(token), startTime, stopTime));

        vm.warp(startTime + 30 days);

        vm.prank(recipient);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        stream.withdrawFromStream(10_000e6);

        token.mint(address(stream), deposit);

        vm.prank(recipient);
        stream.withdrawFromStream(10_000e6);

        assertEq(token.balanceOf(recipient), 10_000e6);
    }

    function testFundingStreamLikeInProposal() public {
        uint256 startTime = 1640988000; // 2022-01-01 00:00:00
        uint256 stopTime = 1672524000; // 2023-01-01 00:00:00
        uint256 deposit = 999975024000; // ~1M * 1e6

        address predictedAddress =
            factory.predictStreamAddress(recipient, deposit, address(token), startTime, stopTime);

        // Proposal would do these txs
        IStream(factory.createStream(recipient, deposit, address(token), startTime, stopTime));
        token.mint(predictedAddress, deposit);
        // End proposal

        vm.warp(startTime + 30 days);

        vm.prank(recipient);
        IStream(predictedAddress).withdrawFromStream(10_000e6);

        assertEq(token.balanceOf(recipient), 10_000e6);
    }
}
