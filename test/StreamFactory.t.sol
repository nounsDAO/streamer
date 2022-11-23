// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";
import { LibClone } from "solady/utils/LibClone.sol";

contract StreamFactoryTest is Test {
    event StreamCreated(
        address indexed msgSender,
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        address streamAddress
    );

    StreamFactory factory;

    address payer = address(0x1000);
    address recipient = address(0x1001);
    ERC20Mock token;

    function setUp() public {
        token = new ERC20Mock("Mock Token", "MOCK", address(1), 0);

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
        token.mint(payer, tokenAmount);

        address predictedAddress = factory.predictStreamAddress(
            payer, payer, recipient, tokenAmount, address(token), startTime, stopTime
        );

        // Proposal would do these txs
        vm.startPrank(payer);
        factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime);
        token.transfer(predictedAddress, tokenAmount);
        vm.stopPrank();
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
        address predictedStream = factory.predictStreamAddress(
            address(this), payer, recipient, tokenAmount, address(token), startTime, stopTime
        );

        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            address(this),
            payer,
            recipient,
            tokenAmount,
            address(token),
            startTime,
            stopTime,
            predictedStream
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
            frontrunner, honestSender, recipient, tokenAmount, address(token), startTime, stopTime
        );
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            frontrunner,
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
            honestSender, honestSender, recipient, tokenAmount, address(token), startTime, stopTime
        );
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            honestSender,
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

    function test_createAndFundStream_revertsWhenTokenApprovalIsInsufficent() public {
        uint256 tokenAmount = 1234;
        uint256 startTime = 1;
        uint256 stopTime = 1001;

        vm.expectRevert("ERC20: insufficient allowance");
        factory.createAndFundStream(recipient, tokenAmount, address(token), startTime, stopTime);
    }

    function test_createAndFundStream_revertsWhenPayerHasInsufficientFunds() public {
        uint256 tokenAmount = 1234;
        uint256 startTime = 1;
        uint256 stopTime = 1001;
        token.approve(address(factory), tokenAmount);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        factory.createAndFundStream(recipient, tokenAmount, address(token), startTime, stopTime);
    }

    function test_createAndFundStream_createsWorkingStreamGivenSufficientTokenApproval() public {
        uint256 tokenAmount = 1234;
        uint256 startTime = block.timestamp;
        uint256 stopTime = block.timestamp + 1000;
        token.approve(address(factory), tokenAmount);
        token.mint(address(this), tokenAmount);

        IStream stream = IStream(
            factory.createAndFundStream(recipient, tokenAmount, address(token), startTime, stopTime)
        );

        assertEq(token.balanceOf(address(stream)), tokenAmount);
        assertEq(token.balanceOf(recipient), 0);

        vm.warp(stopTime);
        vm.prank(recipient);
        stream.withdraw(tokenAmount);

        assertEq(token.balanceOf(address(stream)), 0);
        assertEq(token.balanceOf(recipient), tokenAmount);
    }

    function test_createStream_withoutNonceTwoStreamsWithSameParamtersRevertsOnSecondStreamCreation(
    ) public {
        uint256 startTime = block.timestamp;
        uint256 stopTime = startTime + 1000;
        uint256 tokenAmount = 1000;

        factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime);

        vm.expectRevert(abi.encodeWithSelector(LibClone.DeploymentFailed.selector));
        factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime);
    }

    function test_createStream_usingNonceCanCreateTwoStreamsWithSameParamters() public {
        uint256 startTime = block.timestamp;
        uint256 stopTime = startTime + 1000;
        uint256 tokenAmount = 1000;

        factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime, 0);

        factory.createStream(payer, recipient, tokenAmount, address(token), startTime, stopTime, 1);
    }

    function test_predictStreamAddress_predictsCorrectlyWithNonce() public {
        uint256 startTime = block.timestamp;
        uint256 stopTime = startTime + 1000;
        uint256 tokenAmount = 1000;

        assertEq(
            factory.predictStreamAddress(
                address(this), payer, recipient, tokenAmount, address(token), startTime, stopTime, 0
            ),
            factory.createStream(
                payer, recipient, tokenAmount, address(token), startTime, stopTime, 0
            )
        );

        assertEq(
            factory.predictStreamAddress(
                address(this), payer, recipient, tokenAmount, address(token), startTime, stopTime, 1
            ),
            factory.createStream(
                payer, recipient, tokenAmount, address(token), startTime, stopTime, 1
            )
        );
    }

    function test_createStream_revertsWhenStreamAddressDoesntMatchExpectedAddress() public {
        uint256 startTime = block.timestamp;
        uint256 stopTime = startTime + 1000;
        uint256 tokenAmount = 1000;
        address predictedAddress = factory.predictStreamAddress(
            address(this),
            address(this),
            recipient,
            tokenAmount,
            address(token),
            startTime,
            stopTime,
            0
        );

        vm.expectRevert(abi.encodeWithSelector(StreamFactory.UnexpectedStreamAddress.selector));
        // changing stopTime to result in a different address
        factory.createStream(
            recipient, tokenAmount, address(token), startTime, stopTime - 1, predictedAddress
        );
    }

    function test_createStream_worksWhenStreamAddressMatchesExpectedAddress() public {
        uint256 startTime = block.timestamp;
        uint256 stopTime = startTime + 1000;
        uint256 tokenAmount = 1000;
        address predictedAddress = factory.predictStreamAddress(
            address(this),
            address(this),
            recipient,
            tokenAmount,
            address(token),
            startTime,
            stopTime,
            0
        );

        address streamAddress = factory.createStream(
            recipient, tokenAmount, address(token), startTime, stopTime, predictedAddress
        );

        assertEq(predictedAddress, streamAddress);
    }
}

contract StreamFactoryCreatesCorrectStreamTest is Test {
    uint256 constant DURATION = 1000;
    uint256 constant STREAM_AMOUNT = 2000;

    StreamFactory factory;
    ERC20Mock token;

    address payer = address(0x1000);
    address recipient = address(0x1001);
    uint256 startTime;
    uint256 stopTime;

    function setUp() public {
        token = new ERC20Mock("mock-token", "MOK", address(1), 0);
        factory = new StreamFactory(address(new Stream()));

        startTime = block.timestamp;
        stopTime = startTime + DURATION;
    }

    function test_createStream_revertsWhenPayerIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(StreamFactory.PayerIsAddressZero.selector));
        factory.createStream(
            address(0), recipient, STREAM_AMOUNT, address(token), startTime, stopTime
        );
    }

    function test_createStream_revertsWhenRecipientIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(StreamFactory.RecipientIsAddressZero.selector));

        factory.createStream(payer, address(0), STREAM_AMOUNT, address(token), startTime, stopTime);
    }

    function test_createStream_revertsWhenTokenAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(StreamFactory.TokenAmountIsZero.selector));
        factory.createStream(payer, recipient, 0, address(token), startTime, stopTime);
    }

    function test_createStream_revertsWhenDurationIsNotPositive() public {
        vm.expectRevert(abi.encodeWithSelector(StreamFactory.DurationMustBePositive.selector));
        factory.createStream(payer, recipient, STREAM_AMOUNT, address(token), startTime, startTime);
    }

    function test_createStream_revertsWhenAmountLessThanDuration() public {
        vm.expectRevert(abi.encodeWithSelector(StreamFactory.TokenAmountLessThanDuration.selector));
        factory.createStream(payer, recipient, DURATION - 1, address(token), startTime, stopTime);
    }

    function test_createStream_savesStreamParameters() public {
        Stream s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );

        assertEq(s.tokenAmount(), STREAM_AMOUNT);
        assertEq(s.ratePerSecond(), 2 * s.RATE_DECIMALS_MULTIPLIER());
        assertEq(s.startTime(), startTime);
        assertEq(s.stopTime(), stopTime);
        assertEq(s.recipient(), recipient);
        assertEq(s.payer(), payer);
        assertEq(address(s.token()), address(token));
        assertEq(s.remainingBalance(), STREAM_AMOUNT);
    }
}
