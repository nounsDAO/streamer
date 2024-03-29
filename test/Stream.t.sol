// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";
import { ReentranceToken, ReentranceRecipient } from "./helpers/Reentrance.sol";
import { ETHRejector } from "./helpers/ETHRejector.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";

contract StreamTest is Test {
    uint256 constant DURATION = 1000;
    uint256 constant STREAM_AMOUNT = 2000;

    uint256 startTime;
    uint256 stopTime;
    address payer = address(0x11);
    address recipient = address(0x22);
    address otherAddress = address(0x33);

    event TokensWithdrawn(address indexed msgSender, address indexed recipient, uint256 amount);

    event StreamCancelled(
        address indexed msgSender,
        address indexed payer,
        address indexed recipient,
        uint256 recipientBalance
    );

    event TokensRecovered(address indexed payer, address tokenAddress, uint256 amount, address to);

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
        s.withdrawFromActiveBalance(0);
    }

    function test_withdraw_revertsWhenCalledNotByRecipientOrPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayerOrRecipient.selector));
        s.withdrawFromActiveBalance(1);
    }

    function test_withdraw_revertsWhenAmountExceedsStreamTotal() public {
        vm.warp(stopTime + 1);

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdrawFromActiveBalance(STREAM_AMOUNT + 1);
    }

    function test_withdraw_revertsWhenAmountExceedsBalance() public {
        vm.warp(startTime + 1);
        uint256 balance = s.recipientActiveBalance();

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdrawFromActiveBalance(balance + 1);
    }

    function test_withdraw_revertsWhenStreamNotFunded() public {
        vm.warp(startTime + 1);
        uint256 balance = s.recipientActiveBalance();

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(recipient);
        s.withdrawFromActiveBalance(balance);
    }

    function test_withdraw_transfersTokensAndEmits() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(recipient, recipient, amount);

        vm.prank(recipient);
        s.withdrawFromActiveBalance(amount);

        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(s)), STREAM_AMOUNT - amount);
    }

    function test_withdraw_updatesRemainingBalance() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.prank(recipient);
        s.withdrawFromActiveBalance(amount);

        assertEq(s.remainingBalance(), STREAM_AMOUNT - amount);
    }

    function test_withdraw_payerCanWithdrawForRecipient() public {
        uint256 amount = STREAM_AMOUNT / 2;
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(payer, recipient, amount);

        vm.prank(payer);
        s.withdrawFromActiveBalance(amount);
    }

    function test_withdraw_takesPreviousWithdrawalsIntoAccount() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.startPrank(recipient);

        vm.warp(startTime + (DURATION / 10));
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 10);
        uint256 withdrawnAmount = STREAM_AMOUNT / 10;

        vm.warp(startTime + (DURATION / 2));
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);

        s.withdrawFromActiveBalance((STREAM_AMOUNT / 2) - withdrawnAmount);

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
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);
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
        emit StreamCancelled(address(rRecipient), payer, address(rRecipient), 0);

        vm.prank(address(rRecipient));
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);

        assertEq(rToken.balanceOf(address(rRecipient)), STREAM_AMOUNT / 2);
        // assertEq(s.balanceOf(payer), STREAM_AMOUNT / 2);
    }

    function test_withdrawAvailableBalance_withdrawsFromActiveBalance() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + DURATION / 10);

        vm.prank(recipient);
        s.withdraw(STREAM_AMOUNT / 10);
        assertEq(token.balanceOf(recipient), STREAM_AMOUNT / 10);
    }

    function test_withdrawAvailableBalance_withdrawsFromCancelBalance() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + DURATION / 10);

        vm.prank(payer);
        s.cancel();

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 10);

        vm.prank(recipient);
        s.withdraw(STREAM_AMOUNT / 10);
        assertEq(token.balanceOf(recipient), STREAM_AMOUNT / 10);
    }

    function test_withdrawAvailableBalance_revertsIfNotPayerOrRecipient() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + DURATION / 10);

        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayerOrRecipient.selector));
        s.withdraw(1);

        vm.prank(recipient);
        s.withdraw(1);

        vm.prank(payer);
        s.withdraw(1);
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
        assertEq(s.recipientActiveBalance(), 0);
    }

    function test_balanceOf_recipientBalanceIncreasesLinearlyWithTime() public {
        vm.warp(startTime + (DURATION / 10));
        assertEq(s.recipientActiveBalance(), STREAM_AMOUNT / 10);

        vm.warp(startTime + (DURATION / 5));
        assertEq(s.recipientActiveBalance(), STREAM_AMOUNT / 5);

        vm.warp(startTime + (DURATION / 2));
        assertEq(s.recipientActiveBalance(), STREAM_AMOUNT / 2);

        vm.warp(stopTime);
        assertEq(s.recipientActiveBalance(), STREAM_AMOUNT);
    }

    function test_balanceOf_takesWithdrawalsIntoAccount() public {
        token.mint(address(s), STREAM_AMOUNT);
        uint256 withdrawnAmount = 0;

        vm.warp(startTime + (DURATION / 10));
        uint256 expectedBalance = STREAM_AMOUNT / 10;
        assertEq(s.recipientActiveBalance(), expectedBalance);

        vm.prank(recipient);
        s.withdrawFromActiveBalance(expectedBalance);
        assertEq(s.recipientActiveBalance(), 0);
        withdrawnAmount += expectedBalance;

        vm.warp(startTime + (DURATION / 5));
        expectedBalance = (STREAM_AMOUNT / 5) - withdrawnAmount;
        assertEq(s.recipientActiveBalance(), expectedBalance);

        vm.prank(recipient);
        s.withdrawFromActiveBalance(expectedBalance - 1);
        assertEq(s.recipientActiveBalance(), 1);
        withdrawnAmount += expectedBalance - 1;

        vm.warp(startTime + (DURATION / 2));
        expectedBalance = (STREAM_AMOUNT / 2) - withdrawnAmount;
        assertEq(s.recipientActiveBalance(), expectedBalance);
    }

    function test_recipientBalance_worksAfterCancel() public {
        assertEq(s.recipientBalance(), 0);

        vm.warp(startTime + (DURATION / 2));
        assertEq(s.recipientBalance(), STREAM_AMOUNT / 2);

        vm.prank(payer);
        s.cancel();

        assertEq(s.recipientActiveBalance(), 0);
        assertEq(s.recipientBalance(), STREAM_AMOUNT / 2);
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

    function test_cancel_payerCanRecoverEverythingBeforeStartTime() public {
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, 0);
        vm.prank(payer);
        s.cancel();

        vm.prank(payer);
        s.recoverTokens(address(token), STREAM_AMOUNT, payer);
        assertEq(token.balanceOf(payer), STREAM_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        vm.prank(recipient);
        s.withdrawFromActiveBalance(1);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_cancel_payerCanRecoverEverythingBeforeStartTime_andSendToDifferentAddress()
        public
    {
        token.mint(address(s), STREAM_AMOUNT);

        vm.startPrank(payer);
        s.cancel();
        s.recoverTokens(otherAddress);

        assertEq(token.balanceOf(otherAddress), STREAM_AMOUNT);
    }

    function test_cancel_allocatesEverythingToRecipientAfterStopTimeAndNoWithdrawals() public {
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(stopTime);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, STREAM_AMOUNT);
        vm.prank(payer);
        s.cancel();

        vm.expectRevert(
            abi.encodeWithSelector(Stream.RescueTokenAmountExceedsExcessBalance.selector)
        );
        vm.prank(payer);
        s.recoverTokens(address(token), 1, payer);
        assertEq(token.balanceOf(payer), 0);

        vm.startPrank(recipient);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(1);

        s.withdrawAfterCancel(STREAM_AMOUNT);
        assertEq(token.balanceOf(recipient), STREAM_AMOUNT);
        vm.stopPrank();
    }

    function test_cancel_allocatesFairSharePerElapsedTimeNoWithdrawals(uint256 elapsedTime)
        public
    {
        // No need for elapsedTime = 0 because it's tested above
        elapsedTime = bound(elapsedTime, 1, DURATION);
        token.mint(address(s), STREAM_AMOUNT);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);
        uint256 expectedRecipientBalance = (STREAM_AMOUNT * elapsedTime) / DURATION;
        uint256 expectedPayerBalance = STREAM_AMOUNT - expectedRecipientBalance;

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, expectedRecipientBalance);
        vm.prank(payer);
        s.cancel();

        assertEq(s.recipientActiveBalance(), 0);
        assertEq(s.recipientCancelBalance(), expectedRecipientBalance);

        vm.startPrank(payer);
        vm.expectRevert(
            abi.encodeWithSelector(Stream.RescueTokenAmountExceedsExcessBalance.selector)
        );
        s.recoverTokens(address(token), expectedPayerBalance + 1, payer);

        s.recoverTokens(address(token), expectedPayerBalance, payer);

        if (expectedRecipientBalance > 0) {
            changePrank(recipient);
            vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
            s.withdrawFromActiveBalance(1);

            s.withdrawAfterCancel(expectedRecipientBalance);
            vm.stopPrank();
        }

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalance);
    }

    function test_recoverTokens_afterCancel(uint256 elapsedTime, uint256 amountFunded) public {
        // No need for elapsedTime = 0 because it's tested above
        elapsedTime = bound(elapsedTime, 1, DURATION);

        amountFunded = bound(amountFunded, 0, STREAM_AMOUNT);

        token.mint(address(s), amountFunded);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);
        uint256 expectedRecipientBalance =
            Math.min(amountFunded, (STREAM_AMOUNT * elapsedTime) / DURATION);
        uint256 expectedPayerBalance = amountFunded - expectedRecipientBalance;

        vm.startPrank(payer);
        s.cancel();
        uint256 tokensWithdrawn = s.recoverTokens(payer);

        assertEq(tokensWithdrawn, expectedPayerBalance);
        assertEq(token.balanceOf(payer), expectedPayerBalance);
    }

    function test_recoverTokens_revertsIfNotPayer() public {
        vm.prank(address(0x999));
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayer.selector));
        s.recoverTokens(payer);
    }

    function test_cancel_allocatesFairSharePerElapsedTimeAndWithdrawals(
        uint256 elapsedTime,
        uint256 withdrawalsPercents
    ) public {
        uint256 DECIMALS_FACTOR = 1e6;
        uint256 streamAmount = STREAM_AMOUNT * DECIMALS_FACTOR;
        s = Stream(
            factory.createStream(
                payer, recipient, streamAmount, address(token), startTime, stopTime
            )
        );

        uint256 ratePerSecond = streamAmount / DURATION;
        uint256 minElapsedSecondsSoOnePercentIsntZero = 100 * DECIMALS_FACTOR / ratePerSecond;
        elapsedTime = bound(elapsedTime, minElapsedSecondsSoOnePercentIsntZero, DURATION);
        withdrawalsPercents = bound(withdrawalsPercents, 1, 100);

        token.mint(address(s), streamAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);

        uint256 withdrawAmount = (withdrawalsPercents * s.recipientActiveBalance()) / 100;
        vm.prank(recipient);
        s.withdrawFromActiveBalance(withdrawAmount);
        assertEq(token.balanceOf(recipient), withdrawAmount);

        uint256 expectedRecipientBalanceBeforeWithdrawal = (streamAmount * elapsedTime) / DURATION;
        uint256 expectedPayerBalance = streamAmount - expectedRecipientBalanceBeforeWithdrawal;
        uint256 expectedRecipientBalance = expectedRecipientBalanceBeforeWithdrawal - withdrawAmount;

        if (withdrawAmount != streamAmount) {
            vm.expectEmit(true, true, true, true);
            emit StreamCancelled(payer, payer, recipient, expectedRecipientBalance);
        } else {
            // cancel reverts when recipient has no more balance.
            // this is to ensure cancel only executes when relevant and once per stream.
            vm.expectRevert(abi.encodeWithSelector(Stream.StreamNotActive.selector));
        }
        vm.prank(payer);
        s.cancel();

        vm.prank(payer);
        s.recoverTokens(address(token), expectedPayerBalance, payer);

        if (expectedRecipientBalance > 0) {
            vm.startPrank(recipient);
            vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
            s.withdrawFromActiveBalance(1);

            s.withdrawAfterCancel(expectedRecipientBalance);
            vm.stopPrank();
        }

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalanceBeforeWithdrawal);
    }

    function test_cancel_allocatesOnlyTokenBalanceToPayerWhenUnderfunded() public {
        uint256 fundedAmount = STREAM_AMOUNT - 1;
        token.mint(address(s), fundedAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(s.recipientActiveBalance(), 0);

        vm.startPrank(payer);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        s.recoverTokens(address(token), fundedAmount + 1, payer);

        s.recoverTokens(address(token), fundedAmount, payer);
        assertEq(token.balanceOf(payer), fundedAmount);

        vm.stopPrank();
    }

    function test_cancel_returnsOverfundedTokenBalanceToPayer() public {
        uint256 fundedAmount = STREAM_AMOUNT + 123;
        token.mint(address(s), fundedAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(s.recipientActiveBalance(), 0);

        vm.prank(payer);
        s.recoverTokens(address(token), fundedAmount, payer);
        assertEq(token.balanceOf(payer), fundedAmount);
    }

    function test_cancel_allocatesFairSharePerElapsedTimeAndWithdrawalsAndOverfunding(
        uint256 elapsedTime,
        uint256 withdrawalsPercents,
        uint256 overfundingAmount
    ) public {
        uint256 DECIMALS_FACTOR = 1e6;
        uint256 streamAmount = STREAM_AMOUNT * DECIMALS_FACTOR;
        s = Stream(
            factory.createStream(
                payer, recipient, streamAmount, address(token), startTime, stopTime
            )
        );

        uint256 ratePerSecond = streamAmount / DURATION;
        uint256 minElapsedSecondsSoOnePercentIsntZero = 100 * DECIMALS_FACTOR / ratePerSecond;
        elapsedTime = bound(elapsedTime, minElapsedSecondsSoOnePercentIsntZero, DURATION);
        withdrawalsPercents = bound(withdrawalsPercents, 1, 100);
        overfundingAmount = bound(overfundingAmount, 1, type(uint256).max - streamAmount);

        token.mint(address(s), streamAmount + overfundingAmount);
        assertEq(token.balanceOf(payer), 0);
        assertEq(token.balanceOf(recipient), 0);
        vm.warp(startTime + elapsedTime);

        uint256 withdrawAmount = (withdrawalsPercents * s.recipientActiveBalance()) / 100;

        vm.prank(recipient);
        s.withdrawFromActiveBalance(withdrawAmount);
        assertEq(token.balanceOf(recipient), withdrawAmount);

        uint256 expectedRecipientBalanceBeforeWithdrawal = (streamAmount * elapsedTime) / DURATION;
        uint256 expectedPayerBalance =
            streamAmount - expectedRecipientBalanceBeforeWithdrawal + overfundingAmount;
        uint256 expectedRecipientBalance = expectedRecipientBalanceBeforeWithdrawal - withdrawAmount;

        vm.expectEmit(true, true, true, true);
        emit StreamCancelled(payer, payer, recipient, expectedRecipientBalance);
        vm.prank(payer);
        s.cancel();

        assertEq(s.recipientActiveBalance(), 0);
        assertEq(s.recipientCancelBalance(), expectedRecipientBalance);

        vm.startPrank(payer);
        if (withdrawalsPercents < 100) {
            vm.expectRevert(
                abi.encodeWithSelector(Stream.RescueTokenAmountExceedsExcessBalance.selector)
            );
        } else {
            vm.expectRevert("ERC20: transfer amount exceeds balance");
        }
        s.recoverTokens(address(token), expectedPayerBalance + 1, payer);

        s.recoverTokens(address(token), expectedPayerBalance, payer);

        changePrank(recipient);
        if (expectedRecipientBalance > 0) {
            vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        } else {
            vm.expectRevert(abi.encodeWithSelector(Stream.CantWithdrawZero.selector));
        }
        s.withdrawFromActiveBalance(expectedRecipientBalance);

        if (expectedRecipientBalance == 0) {
            vm.expectRevert(abi.encodeWithSelector(Stream.CantWithdrawZero.selector));
        }
        s.withdrawAfterCancel(expectedRecipientBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(payer), expectedPayerBalance);
        assertEq(token.balanceOf(recipient), expectedRecipientBalanceBeforeWithdrawal);
    }

    function test_cancel_onceCancelledRecipientCantWithdrawFutureTokensAccidentallySent() public {
        vm.prank(payer);
        s.cancel();

        vm.warp(stopTime);
        token.mint(address(s), 1);

        vm.prank(recipient);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(1);
    }

    function test_cancel_revertsUponSecondCancel() public {
        vm.prank(payer);
        s.cancel();

        vm.expectRevert(abi.encodeWithSelector(Stream.StreamNotActive.selector));
        vm.prank(recipient);
        s.cancel();
    }

    function test_cancel_revertsIfCalledOnFullyWithdrawnStream() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(stopTime);
        vm.prank(recipient);
        s.withdrawFromActiveBalance(STREAM_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(Stream.StreamNotActive.selector));
        vm.prank(payer);
        s.cancel();
    }

    function test_withdrawAfterCancel_revertsWhenCalledByNonPayerOrRecipient() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayerOrRecipient.selector));
        s.withdrawAfterCancel(1);
    }

    function test_withdrawAfterCancel_revertsGivenZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CantWithdrawZero.selector));
        vm.prank(recipient);
        s.withdrawAfterCancel(0);
    }

    function test_withdrawAfterCancel_revertsGivenNoCancelBalance() public {
        vm.expectRevert(stdError.arithmeticError);
        vm.prank(recipient);
        s.withdrawAfterCancel(1);
    }

    function test_withdrawAfterCancel_transfersAndEmits() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));
        vm.startPrank(recipient);
        s.cancel();
        uint256 cancelBalance = s.recipientCancelBalance();

        vm.expectRevert(stdError.arithmeticError);
        s.withdrawAfterCancel(cancelBalance + 1);

        vm.expectEmit(true, true, true, true);
        emit TokensWithdrawn(recipient, recipient, cancelBalance);

        s.withdrawAfterCancel(cancelBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), cancelBalance);
    }

    function test_withdrawAfterCancel_worksWhenPayerExecutes() public {
        token.mint(address(s), STREAM_AMOUNT);
        vm.warp(startTime + (DURATION / 2));
        vm.startPrank(payer);
        s.cancel();
        uint256 cancelBalance = s.recipientCancelBalance();

        s.withdrawAfterCancel(cancelBalance);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), cancelBalance);
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

        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);
        (, remainingBalance) = s.tokenAndOutstandingBalance();
        assertEq(remainingBalance, STREAM_AMOUNT / 2);

        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);
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
    }

    function test_balanceOf_worksMidStream() public {
        vm.warp(startTime + 150);
        assertEq(s.recipientActiveBalance(), 1000000000);

        vm.warp(startTime + 200);
        assertEq(s.recipientActiveBalance(), 1333333333);
    }

    function test_withdraw_usesRateDecimalsMidStream() public {
        token.mint(address(s), s.tokenAmount());

        vm.startPrank(recipient);

        vm.warp(startTime + 150);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(1000000001);

        s.withdrawFromActiveBalance(1000000000);
        assertEq(token.balanceOf(recipient), 1000000000);

        vm.warp(startTime + 200);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(333333334);

        s.withdrawFromActiveBalance(333333333);
        assertEq(token.balanceOf(recipient), 1333333333);

        vm.stopPrank();
    }

    function test_balanceOf_noDustAtEndOfStream() public {
        vm.warp(stopTime);
        assertEq(s.recipientActiveBalance(), s.tokenAmount());
    }

    function test_withdraw_noDustAtEndOfStream() public {
        token.mint(address(s), s.tokenAmount());
        vm.warp(stopTime);
        vm.startPrank(recipient);

        s.withdrawFromActiveBalance(s.tokenAmount());

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
    }

    function test_balanceOf_worksMidStream() public {
        vm.warp(startTime + 7890000); // half way in
        assertEq(s.recipientActiveBalance(), 500000000000);

        vm.warp(startTime + 10520000); // two thirds in
        assertEq(s.recipientActiveBalance(), 666666666666);
    }

    function test_withdraw_usesRateDecimalsMidStream() public {
        token.mint(address(s), s.tokenAmount());

        vm.startPrank(recipient);

        vm.warp(startTime + 7890000);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(500_001 * 1e6);

        s.withdrawFromActiveBalance(500_000 * 1e6);
        assertEq(token.balanceOf(recipient), 500_000 * 1e6);

        vm.warp(startTime + 10520000);
        vm.expectRevert(abi.encodeWithSelector(Stream.AmountExceedsBalance.selector));
        s.withdrawFromActiveBalance(166666666667);

        s.withdrawFromActiveBalance(166666666666);
        assertEq(token.balanceOf(recipient), 666666666666);

        vm.stopPrank();
    }

    function test_balanceOf_noDustAtEndOfStream() public {
        vm.warp(stopTime);
        assertEq(s.recipientActiveBalance(), s.tokenAmount());
    }

    function test_withdraw_noDustAtEndOfStream() public {
        token.mint(address(s), s.tokenAmount());
        vm.warp(stopTime);
        vm.startPrank(recipient);

        s.withdrawFromActiveBalance(s.tokenAmount());

        assertEq(token.balanceOf(recipient), s.tokenAmount());
        vm.stopPrank();
    }
}

contract StreamRecoverTokensTest is StreamTest {
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

    function test_recoverTokens_revertsWhenCallerIsntPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayer.selector));
        s.recoverTokens(address(otherToken), 0, payer);
    }

    function test_recoverTokens_revertsWhenAmountIsGreaterThanBalance() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(payer);
        s.recoverTokens(address(otherToken), 1, payer);
    }

    function test_recoverTokens_streamToken_revertsWhenTryingToRecoverTooManyStreamTokens()
        public
    {
        token.mint(address(s), STREAM_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(Stream.RescueTokenAmountExceedsExcessBalance.selector)
        );
        vm.prank(payer);
        s.recoverTokens(address(token), 1, payer);
    }

    function test_recoverTokens_otherToken_worksWhenAmountDoesntExceedBalance() public {
        otherToken.mint(address(s), 1234);
        assertEq(otherToken.balanceOf(payer), 0);

        vm.expectEmit(true, true, true, true);
        emit TokensRecovered(payer, address(otherToken), 1234, payer);

        vm.prank(payer);
        s.recoverTokens(address(otherToken), 1234, payer);

        assertEq(otherToken.balanceOf(payer), 1234);
    }

    function test_recoverTokens_streamToken_worksWhenAmountDoesntExceedExcessBalance() public {
        token.mint(address(s), STREAM_AMOUNT + 1234);

        vm.expectEmit(true, true, true, true);
        emit TokensRecovered(payer, address(token), 1234, payer);

        vm.prank(payer);
        s.recoverTokens(address(token), 1234, payer);

        assertEq(token.balanceOf(payer), 1234);
    }

    function test_recoverTokens_streamToken_worksAfterWithdrawals() public {
        token.mint(address(s), STREAM_AMOUNT + 1234);

        vm.warp(startTime + (DURATION / 2));
        vm.prank(recipient);
        s.withdrawFromActiveBalance(STREAM_AMOUNT / 2);

        vm.expectEmit(true, true, true, true);
        emit TokensRecovered(payer, address(token), 1234, payer);

        vm.prank(payer);
        s.recoverTokens(address(token), 1234, payer);

        assertEq(token.balanceOf(payer), 1234);
    }

    function test_recoverTokens_streamToken_revertsWhenUnderfunded() public {
        token.mint(address(s), STREAM_AMOUNT - 1);

        vm.expectRevert(
            abi.encodeWithSelector(Stream.RescueTokenAmountExceedsExcessBalance.selector)
        );
        vm.prank(payer);
        s.recoverTokens(address(token), STREAM_AMOUNT - 2, payer);
    }
}

contract StreamRescueETHTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s = Stream(
            factory.createStream(
                payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime
            )
        );
    }

    function test_rescueETH_revertsWhenCallerIsntPayer() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.CallerNotPayer.selector));
        s.rescueETH(address(0x42), 0);
    }

    function test_rescueETH_revertsWhenBalanceIsBelowRequestedAmount() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.ETHRescueFailed.selector));
        vm.prank(payer);
        s.rescueETH(address(0x42), 1);

        vm.deal(address(s), 42 ether);

        vm.expectRevert(abi.encodeWithSelector(Stream.ETHRescueFailed.selector));
        vm.prank(payer);
        s.rescueETH(address(0x42), 42.1 ether);
    }

    function test_rescueETH_revertsWhenSendingToRejectingContract() public {
        ETHRejector rejector = new ETHRejector();
        vm.deal(address(s), 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Stream.ETHRescueFailed.selector));
        vm.prank(payer);
        s.rescueETH(address(rejector), 1 ether);
    }

    function test_rescueETH_worksAndEmits() public {
        vm.deal(address(s), 1 ether);

        vm.prank(payer);
        s.rescueETH(address(0x42), 1 ether);

        assertEq(address(0x42).balance, 1 ether);
    }
}
