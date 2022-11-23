// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";
import { ReentranceToken, ReentranceRecipient } from "./helpers/Reentrance.sol";

contract StreamTest is Test {
    uint256 constant DURATION = 1000;
    uint256 constant STREAM_AMOUNT = 2000;

    uint256 startTime;
    uint256 stopTime;
    address payer = address(0x11);
    address recipient = address(0x22);

    event TokensWithdrawn(address indexed msgSender, address indexed recipient, uint256 amount);

    event StreamCancelled(
        address indexed msgSender,
        address indexed payer,
        address indexed recipient,
        uint256 payerBalance,
        uint256 recipientBalance
    );

    ERC20Mock token;
    Stream s;
    StreamFactory factory;

    function setUp() public virtual {
        token = new ERC20Mock("Mock Token", "MOCK", address(1), 0);
        factory = new StreamFactory(address(new Stream()));

        startTime = block.timestamp;
        stopTime = block.timestamp + DURATION;
    }
}

contract StreamInitializeTest is StreamTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize_revertsWhenCalledNotByFactory() public {
        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );

        vm.expectRevert(abi.encodeWithSelector(Stream.OnlyFactory.selector));
        s.initialize();
    }
}

contract StreamWithdrawTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );
    }

    function test_withdraw_revertsGivenAmountZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CantWithdrawZero.selector));
        vm.prank(recipient);
        s.withdraw(0);
    }

    function test_withdraw_revertsWhenCalledNotByRecipientOrPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayerOrRecipient.selector));
        s.withdraw(1);
    }

    function test_withdraw_revertsWhenAmountExceedsStreamTotal() public {
        vm.warp(stopTime + 1);

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdraw(STREAM_AMOUNT + 1);
    }

    function test_withdraw_revertsWhenAmountExceedsBalance() public {
        vm.warp(startTime + 1);
        uint256 balance = s.balanceOf(recipient);

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdraw(balance + 1);
    }

    function test_withdraw_revertsWhenStreamNotFunded() public {
        vm.warp(startTime + 1);
        uint256 balance = s.balanceOf(recipient);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(recipient);
        s.withdraw(balance);
    }

    function test_withdraw_transfersTokensAndEmits() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(recipient, recipient, amount);

        vm.prank(recipient);
        s.withdraw(amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(s)), STREAM_AMOUNT - amount);
    }

    function test_withdraw_updatesRemainingBalance() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.prank(recipient);
        s.withdraw(amount);

        assertEq(s.remainingBalance(), STREAM_AMOUNT - amount);
    }

    function test_withdraw_payerCanWithdrawForRecipient() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(payer, recipient, amount);

        vm.prank(payer);
        s.withdraw(amount);
    }

    function test_withdraw_takesPreviousWithdrawalsIntoAccount() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.startPrank(recipient);

        vm.warp(startTime + (DURATION / 10));
        s.withdraw(STREAM_AMOUNT / 10);
        uint256 withdrawnAmount = STREAM_AMOUNT / 10;

        vm.warp(startTime + (DURATION / 2));
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(STREAM_AMOUNT / 2);

        s.withdraw((STREAM_AMOUNT / 2) - withdrawnAmount);

        vm.stopPrank();
    }

    function test_withdraw_preventsReentryToWithdraw() public {
        ReentranceToken rToken = new ReentranceToken("Reentrance Token", "RT", address(1), 0);
        ReentranceRecipient rRecipient = new ReentranceRecipient();

        s = Stream(
            factory.createStream(
                payer, address(rRecipient), STREAM_AMOUNT, address(rToken), startTime, stopTime
            )
        );
        rToken.mint(address(s), STREAM_AMOUNT);
        rToken.setStream(s);

        vm.warp(startTime + (DURATION / 2));

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(address(rRecipient));
        s.withdraw(STREAM_AMOUNT / 2);
    }

    function test_withdraw_reentryToCancelDoesNotBenefitRecipient() public {
        ReentranceToken rToken = new ReentranceToken("Reentrance Token", "RT", address(1), 0);
        ReentranceRecipient rRecipient = new ReentranceRecipient();
        rRecipient.setReenterCancel(true);
        s = Stream(
            factory.createStream(
                payer, address(rRecipient), STREAM_AMOUNT, address(rToken), startTime, stopTime
            )
        );
        rToken.mint(address(s), STREAM_AMOUNT);
        rToken.setStream(s);
        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(address(rRecipient), payer, address(rRecipient), STREAM_AMOUNT / 2, 0);

        vm.prank(address(rRecipient));
        s.withdraw(STREAM_AMOUNT / 2);

        assertEq(rToken.balanceOf(address(rRecipient)), STREAM_AMOUNT / 2);
        assertEq(rToken.balanceOf(payer), STREAM_AMOUNT / 2);
    }
}

contract StreamBalanceOfTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );
    }

    function test_balanceOf_zeroBeforeStreamStarts() public {
        assertEq(s.balanceOf(recipient), 0);
    }

    function test_balanceOf_zeroForNonPayerOrRecipient() public {
        vm.warp(stopTime);
        assertEq(s.balanceOf(address(0x4242)), 0);
    }

    function test_balanceOf_recipientBalanceIncreasesLinearlyWithTime() public {
        vm.warp(startTime + (DURATION / 10));
        assertEq(s.balanceOf(recipient), STREAM_AMOUNT / 10);

        vm.warp(startTime + (DURATION / 5));
        assertEq(s.balanceOf(recipient), STREAM_AMOUNT / 5);

        vm.warp(startTime + (DURATION / 2));
        assertEq(s.balanceOf(recipient), STREAM_AMOUNT / 2);

        vm.warp(stopTime);
        assertEq(s.balanceOf(recipient), STREAM_AMOUNT);
    }

    function test_balanceOf_payerBalanceDecreasesLinearlyWithTime() public {
        vm.warp(startTime + (DURATION / 10));
        assertEq(s.balanceOf(payer), STREAM_AMOUNT - (STREAM_AMOUNT / 10));

        vm.warp(startTime + (DURATION / 5));
        assertEq(s.balanceOf(payer), STREAM_AMOUNT - (STREAM_AMOUNT / 5));

        vm.warp(startTime + (DURATION / 2));
        assertEq(s.balanceOf(payer), STREAM_AMOUNT / 2);

        vm.warp(stopTime);
        assertEq(s.balanceOf(payer), 0);
    }

    function test_balanceOf_takesWithdrawalsIntoAccount() public {
        token.mint(address(s), STREAM_AMOUNT);
        uint256 withdrawnAmount = 0;

        vm.warp(startTime + (DURATION / 10));
        uint256 expectedBalance = STREAM_AMOUNT / 10;
        assertEq(s.balanceOf(recipient), expectedBalance);

        vm.prank(recipient);
        s.withdraw(expectedBalance);
        assertEq(s.balanceOf(recipient), 0);
        withdrawnAmount += expectedBalance;

        vm.warp(startTime + (DURATION / 5));
        expectedBalance = (STREAM_AMOUNT / 5) - withdrawnAmount;
        assertEq(s.balanceOf(recipient), expectedBalance);

        vm.prank(recipient);
        s.withdraw(expectedBalance - 1);
        assertEq(s.balanceOf(recipient), 1);
        withdrawnAmount += expectedBalance - 1;

        vm.warp(startTime + (DURATION / 2));
        expectedBalance = (STREAM_AMOUNT / 2) - withdrawnAmount;
        assertEq(s.balanceOf(recipient), expectedBalance);
    }
}

contract StreamCancelTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );
    }

    function test_cancel_revertsWhenCalledNotByRecipientOrPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayerOrRecipient.selector));
        s.cancel();
    }

    function test_cancel_returnsEverythingToPayerBeforeTimeElapses() public {
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, STREAM_AMOUNT, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), STREAM_AMOUNT);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_cancel_sendsEverythingToRecipientAfterStopTimeAndNoWithdrawals() public {
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(stopTime);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, 0, STREAM_AMOUNT);
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), STREAM_AMOUNT);
    }

    function test_cancel_sendsFairSharePerElapsedTimeNoWithdrawals(uint256 elapsedTime) public {
        vm.assume(elapsedTime <= DURATION);
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);
        uint256 expectedRecipientBalance = (STREAM_AMOUNT * elapsedTime) / DURATION;
        uint256 expectedPayerBalance = STREAM_AMOUNT - expectedRecipientBalance;

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(
            payer, payer, recipient, expectedPayerBalance, expectedRecipientBalance
            );
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalance);
    }

    function test_cancel_sendsFairSharePerElapsedTimeAndWithdrawals(
        uint256 elapsedTime,
        uint256 withdrawalsPercents
    ) public {
        uint256 ratePerSecond = STREAM_AMOUNT / DURATION;
        uint256 minElapsedSecondsSoOnePercentIsntZero = 100 / ratePerSecond;
        vm.assume(elapsedTime > minElapsedSecondsSoOnePercentIsntZero && elapsedTime <= DURATION);
        vm.assume(withdrawalsPercents > 0 && withdrawalsPercents <= 100);

        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);

        uint256 withdrawAmount = (withdrawalsPercents * s.balanceOf(recipient)) / 100;
        vm.prank(recipient);
        s.withdraw(withdrawAmount);
        assertEq(token.balanceOf(recipient), withdrawAmount);

        uint256 expectedRecipientBalance = (STREAM_AMOUNT * elapsedTime) / DURATION;
        uint256 expectedPayerBalance = STREAM_AMOUNT - expectedRecipientBalance;

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(
            payer, payer, recipient, expectedPayerBalance, expectedRecipientBalance - withdrawAmount
            );
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalance);
    }

    function test_cancel_returnsOnlyTokenBalanceToPayerIfNotFullyFunded() public {
        uint256 fundedAmount = STREAM_AMOUNT - 1;
        token.mint(address(s), fundedAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, fundedAmount, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), fundedAmount);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_cancel_returnsOverfundedTokenBalanceToPayer() public {
        uint256 fundedAmount = STREAM_AMOUNT + 123;
        token.mint(address(s), fundedAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, fundedAmount, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), fundedAmount);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_cancel_sendsFairSharePerElapsedTimeAndWithdrawalsAndOverfunding(
        uint256 elapsedTime,
        uint256 withdrawalsPercents,
        uint256 overfundingAmount
    ) public {
        uint256 ratePerSecond = STREAM_AMOUNT / DURATION;
        uint256 minElapsedSecondsSoOnePercentIsntZero = 100 / ratePerSecond;
        vm.assume(elapsedTime > minElapsedSecondsSoOnePercentIsntZero && elapsedTime <= DURATION);
        vm.assume(withdrawalsPercents > 0 && withdrawalsPercents <= 100);
        vm.assume(overfundingAmount > 0 && overfundingAmount <= type(uint256).max - STREAM_AMOUNT);

        token.mint(address(s), STREAM_AMOUNT + overfundingAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);

        uint256 withdrawAmount = (withdrawalsPercents * s.balanceOf(recipient)) / 100;
        vm.prank(recipient);
        s.withdraw(withdrawAmount);
        assertEq(token.balanceOf(recipient), withdrawAmount);

        uint256 expectedRecipientBalance = (STREAM_AMOUNT * elapsedTime) / DURATION;
        uint256 expectedPayerBalance = STREAM_AMOUNT - expectedRecipientBalance + overfundingAmount;

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(
            payer, payer, recipient, expectedPayerBalance, expectedRecipientBalance - withdrawAmount
            );
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalance);
    }

    function test_cancel_onceCancelledRecipientCantWithdrawFutureTokensAccidentallySent() public {
        vm.prank(payer);
        s.cancel();

        vm.warp(stopTime);
        token.mint(address(s), 1);

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(1);
    }

    function test_cancel_onceCancelledRecipientCantCancelToGetFutureTokensAccidentallySent()
        public
    {
        vm.prank(payer);
        s.cancel();

        vm.warp(stopTime);
        token.mint(address(s), STREAM_AMOUNT);

        vm.prank(recipient);
        s.cancel();
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_cancel_preventsReentryToWithdraw() public {
        ReentranceToken rToken = new ReentranceToken("Reentrance Token", "RT", address(1), 0);
        ReentranceRecipient rRecipient = new ReentranceRecipient();

        s = Stream(
            factory.createStream(
                payer, address(rRecipient), STREAM_AMOUNT, address(rToken), startTime, stopTime
            )
        );
        rToken.mint(address(s), STREAM_AMOUNT);
        rToken.setStream(s);

        vm.warp(startTime + (DURATION / 2));

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(address(rRecipient));
        s.cancel();
    }

    function test_cancel_reentryToCancelDoesNotBenefitRecipient() public {
        ReentranceToken rToken = new ReentranceToken("Reentrance Token", "RT", address(1), 0);
        ReentranceRecipient rRecipient = new ReentranceRecipient();
        rRecipient.setReenterCancel(true);
        s = Stream(
            factory.createStream(
                payer, address(rRecipient), STREAM_AMOUNT, address(rToken), startTime, stopTime
            )
        );
        rToken.mint(address(s), STREAM_AMOUNT);
        rToken.setStream(s);

        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        // The first event is from the reentry, when recipient's balance is zero, and payer's balance is still
        // half the stream's value.
        // The second event is from the origial call as it resumes, when the recipient's balance was 1000, while the
        // payer's balance is checked after, when it's already zero.
        emit StreamCancelled(address(rRecipient), payer, address(rRecipient), STREAM_AMOUNT / 2, 0);
        emit StreamCancelled(address(rRecipient), payer, address(rRecipient), 0, STREAM_AMOUNT / 2);

        vm.prank(address(rRecipient));
        s.cancel();
    }
}

contract StreamTokenAndOutstandingBalanceTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );
    }

    function test_tokenAndOutstandingBalance_tokenBalanceWorks() public {
        (uint256 tokenBalance,) = s.tokenAndOutstandingBalance();
        assertEq(tokenBalance, 0);

        token.mint(address(s), 111);
        (tokenBalance,) = s.tokenAndOutstandingBalance();
        assertEq(tokenBalance, 111);

        token.mint(address(s), 111);
        (tokenBalance,) = s.tokenAndOutstandingBalance();
        assertEq(tokenBalance, 222);

        token.burn(address(s), 222);
        (tokenBalance,) = s.tokenAndOutstandingBalance();
        assertEq(tokenBalance, 0);
    }

    function test_tokenAndOutstandingBalance_remainingBalanceWorks() public {
        token.mint(address(s), STREAM_AMOUNT);
        (, uint256 remainingBalance) = s.tokenAndOutstandingBalance();
        assertEq(remainingBalance, STREAM_AMOUNT);
        vm.warp(stopTime);

        vm.startPrank(recipient);

        s.withdraw(STREAM_AMOUNT / 2);
        (, remainingBalance) = s.tokenAndOutstandingBalance();
        assertEq(remainingBalance, STREAM_AMOUNT / 2);

        s.withdraw(STREAM_AMOUNT / 2);
        (, remainingBalance) = s.tokenAndOutstandingBalance();
        assertEq(remainingBalance, 0);

        vm.stopPrank();
    }
}

contract StreamWithRemainderTest is StreamTest {
    function setUp() public override {
        super.setUp();

        uint256 streamAmount = 2_000 * 1e6; // 2K USDC; USDC has 6 decimals
        uint256 duration = 300;
        startTime = block.timestamp;
        stopTime = startTime + duration;

        s = Stream(
            factory.createStream(
                payer, recipient, streamAmount, address(token), startTime, stopTime
            )
        );

        // streamAmount / duration = 6666666.66666667
        // assuming RATE_DECIMALS_MULTIPLIER = 6, we get 6666666666666
        assertEq(s.ratePerSecond(), 6666666666666);
    }

    function test_balanceOf_usesRateDecimalsMidStream() public {
        vm.warp(startTime + 150);
        assertEq(s.balanceOf(recipient), 999999999);

        vm.warp(startTime + 200);
        assertEq(s.balanceOf(recipient), 1333333333);
    }

    function test_withdraw_usesRateDecimalsMidStream() public {
        token.mint(address(s), s.tokenAmount());

        vm.startPrank(recipient);

        vm.warp(startTime + 150);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(1000000000);

        s.withdraw(999999999);
        assertEq(token.balanceOf(recipient), 999999999);

        vm.warp(startTime + 200);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(333333335);

        s.withdraw(333333334);
        assertEq(token.balanceOf(recipient), 1333333333);

        vm.stopPrank();
    }

    function test_balanceOf_noDustAtEndOfStream() public {
        vm.warp(stopTime);
        assertEq(s.balanceOf(recipient), s.tokenAmount());
    }

    function test_withdraw_noDustAtEndOfStream() public {
        token.mint(address(s), s.tokenAmount());
        vm.warp(stopTime);
        vm.startPrank(recipient);

        s.withdraw(s.tokenAmount());

        assertEq(token.balanceOf(recipient), s.tokenAmount());
        vm.stopPrank();
    }
}

contract StreamWithRemainderHighDurationAndAmountTest is StreamTest {
    function setUp() public override {
        super.setUp();

        uint256 streamAmount = 1_000_000 * 1e6; // 1M USDC
        uint256 duration = 15780000; // 6 months
        startTime = block.timestamp;
        stopTime = startTime + duration;

        s = Stream(
            factory.createStream(
                payer, recipient, streamAmount, address(token), startTime, stopTime
            )
        );

        // streamAmount / duration = 63371.35614702
        // assuming RATE_DECIMALS_MULTIPLIER = 1e6, we get 63371356147
        assertEq(s.ratePerSecond(), 63371356147);
    }

    function test_balanceOf_usesRateDecimalsMidStream() public {
        vm.warp(startTime + 7890000); // half way in
        assertEq(s.balanceOf(recipient), 499999999999);

        vm.warp(startTime + 10520000); // two thirds in
        assertEq(s.balanceOf(recipient), 666666666666);
    }

    function test_withdraw_usesRateDecimalsMidStream() public {
        token.mint(address(s), s.tokenAmount());

        vm.startPrank(recipient);

        vm.warp(startTime + 7890000);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(500_000 * 1e6);

        s.withdraw(499999999999);
        assertEq(token.balanceOf(recipient), 499999999999);

        vm.warp(startTime + 10520000);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdraw(166666666668);

        s.withdraw(166666666667);
        assertEq(token.balanceOf(recipient), 666666666666);

        vm.stopPrank();
    }

    function test_balanceOf_noDustAtEndOfStream() public {
        vm.warp(stopTime);
        assertEq(s.balanceOf(recipient), s.tokenAmount());
    }

    function test_withdraw_noDustAtEndOfStream() public {
        token.mint(address(s), s.tokenAmount());
        vm.warp(stopTime);
        vm.startPrank(recipient);

        s.withdraw(s.tokenAmount());

        assertEq(token.balanceOf(recipient), s.tokenAmount());
        vm.stopPrank();
    }
}

contract StreamRescueERC20Test is StreamTest {
    ERC20Mock otherToken;

    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );

        otherToken = new ERC20Mock("Other Token", "OTHER", address(1), 0);
    }

    function test_rescueERC20_revertsWhenCallerIsntPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayer.selector));
        s.rescueERC20(address(otherToken), 0);
    }

    function test_rescueERC20_revertsWhenTryingToRecoverStreamToken() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CannotRescueStreamToken.selector));
        vm.prank(payer);
        s.rescueERC20(address(token), 0);
    }

    function test_rescueERC20_revertsWhenAmountIsGreaterThanBalance() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(payer);
        s.rescueERC20(address(otherToken), 1);
    }

    function test_rescueERC20_worksWhenAmountDoesntExceedBalance() public {
        otherToken.mint(address(s), 1234);
        assertEq(otherToken.balanceOf(payer), 0);

        vm.prank(payer);
        s.rescueERC20(address(otherToken), 1234);

        assertEq(otherToken.balanceOf(payer), 1234);
    }
}
