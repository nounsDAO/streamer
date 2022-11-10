// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamFactoryTest is Test {
    event StreamCreated(
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        address streamAddress
    );

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
        uint256 tokenAmount = 999975024000; // ~1M * 1e6

        vm.warp(startTime);

        IStream stream = IStream(
            factory.createStream(recipient, tokenAmount, address(token), startTime, stopTime)
        );

        vm.warp(startTime + 30 days);

        vm.prank(recipient);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        stream.withdraw(10_000e6);

        token.mint(address(stream), tokenAmount);

        vm.prank(recipient);
        stream.withdraw(10_000e6);

        assertEq(token.balanceOf(recipient), 10_000e6);
    }

    function testFundingStreamLikeInProposal() public {
        uint256 startTime = 1640988000; // 2022-01-01 00:00:00
        uint256 stopTime = 1672524000; // 2023-01-01 00:00:00
        uint256 tokenAmount = 999975024000; // ~1M * 1e6

        address predictedAddress = factory.predictStreamAddress(
            address(this), recipient, tokenAmount, address(token), startTime, stopTime
        );

        // Proposal would do these txs
        factory.createStream(recipient, tokenAmount, address(token), startTime, stopTime);
        token.mint(predictedAddress, tokenAmount);
        // End proposal

        vm.warp(startTime + 30 days);

        vm.prank(recipient);
        IStream(predictedAddress).withdraw(10_000e6);

        assertEq(token.balanceOf(recipient), 10_000e6);
    }

    function test_createStream_setsPayerParamAsStreamPayer() public {
        uint256 startTime = 1640988000;
        uint256 stopTime = 1672524000;
        uint256 tokenAmount = 999975024000;
        address payer = address(0x4242);
        address predictedStream = factory.predictStreamAddress(
            address(this), recipient, tokenAmount, address(token), startTime, stopTime
        );

        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            payer, recipient, tokenAmount, address(token), startTime, stopTime, predictedStream
            );
        address newStream =
            factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime);

        Stream s = Stream(newStream);
        assertEq(s.payer(), payer);
    }

    function test_createStream_defaultPayerIsMsgSender() public {
        uint256 startTime = 1640988000;
        uint256 stopTime = 1672524000;
        uint256 tokenAmount = 999975024000;

        address newStream =
            factory.createStream(recipient, tokenAmount, address(token), startTime, stopTime);

        Stream s = Stream(newStream);
        assertEq(s.payer(), address(this));
    }

    function test_createStream_differentSenderCantFrontrunToFailCreation() public {
        uint256 startTime = 1640988000;
        uint256 stopTime = 1672524000;
        uint256 tokenAmount = 999975024000;
        address honestSender = address(0x4242);
        address frontrunner = address(0x1234);

        address predictedStream = factory.predictStreamAddress(
            frontrunner, recipient, tokenAmount, address(token), startTime, stopTime
        );
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            honestSender,
            recipient,
            tokenAmount,
            address(token),
            startTime,
            stopTime,
            predictedStream
            );
        vm.prank(frontrunner);
        factory.createStream(
            honestSender, recipient, tokenAmount, address(token), startTime, stopTime
        );

        predictedStream = factory.predictStreamAddress(
            honestSender, recipient, tokenAmount, address(token), startTime, stopTime
        );
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            honestSender,
            recipient,
            tokenAmount,
            address(token),
            startTime,
            stopTime,
            predictedStream
            );
        vm.prank(honestSender);
        factory.createStream(
            honestSender, recipient, tokenAmount, address(token), startTime, stopTime
        );
    }
}
