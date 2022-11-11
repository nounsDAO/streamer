// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamTest is Test {
    uint256 constant DURATION = 1000;
    uint256 constant STREAM_AMOUNT = 2000;

    uint256 startTime;
    uint256 stopTime;
    address payer = address(0x11);
    address recipient = address(0x22);

    event StreamCreated(
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    );

    event TokensWithdrawn(address indexed recipient, uint256 amount);

    event StreamCancelled(
        address indexed payer,
        address indexed recipient,
        uint256 payerBalance,
        uint256 recipientBalance
    );

    ERC20Mock token;
    Stream s;

    function setUp() public virtual {
        token = new ERC20Mock("mock-token", "MOK", address(1), 0);
        s = new Stream();

        startTime = block.timestamp;
        stopTime = block.timestamp + DURATION;
    }
}

contract StreamInitializeTest is StreamTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize_revertsWhenCalledTwice() public {
        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);

        vm.expectRevert("Initializable: contract is already initialized");
        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
    }

    function test_initialize_revertsWhenPayerIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.PayerIsAddressZero.selector));
        s.initialize(address(0), recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
    }

    function test_initialize_revertsWhenRecipientIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.RecipientIsAddressZero.selector));
        s.initialize(payer, address(0), STREAM_AMOUNT, address(token), startTime, stopTime);
    }

    function test_initialize_revertsWhenRecipientIsTheStreamContract() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.RecipientIsStreamContract.selector));
        s.initialize(payer, address(s), STREAM_AMOUNT, address(token), startTime, stopTime);
    }

    function test_initialize_revertsWhenTokenAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountIsZero.selector));
        s.initialize(payer, recipient, 0, address(token), startTime, stopTime);
    }

    function test_initialize_revertsWhenDurationIsNotPositive() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.DurationMustBePositive.selector));
        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, startTime);
    }

    function test_initialize_revertsWhenAmountLessThanDuration() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountLessThanDuration.selector));
        s.initialize(payer, recipient, DURATION - 1, address(token), startTime, stopTime);
    }

    function test_initialize_savesStreamAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);

        assertEq(s.tokenAmount(), STREAM_AMOUNT);
        assertEq(s.remainingBalance(), STREAM_AMOUNT);
        assertEq(s.ratePerSecond(), 2 * s.RATE_DECIMALS());
        assertEq(s.startTime(), startTime);
        assertEq(s.stopTime(), stopTime);
        assertEq(s.recipient(), recipient);
        assertEq(s.payer(), payer);
        assertEq(s.tokenAddress(), address(token));
    }
}

contract StreamWithdrawTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
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
        emit TokensWithdrawn(recipient, amount);

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
        emit TokensWithdrawn(recipient, amount);

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
}

contract StreamBalanceOfTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
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

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
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
        emit StreamCancelled(payer, recipient, STREAM_AMOUNT, 0);
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
        emit StreamCancelled(payer, recipient, 0, STREAM_AMOUNT);
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
        emit StreamCancelled(payer, recipient, expectedPayerBalance, expectedRecipientBalance);
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
            payer, recipient, expectedPayerBalance, expectedRecipientBalance - withdrawAmount
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
        emit StreamCancelled(payer, recipient, fundedAmount, 0);
        vm.prank(payer);
        s.cancel();

        assertEq(token.balanceOf(payer), fundedAmount);
        assertEq(token.balanceOf(recipient), 0);
    }
}

contract StreamTokenAndOutstandingBalanceTest is StreamTest {
    function setUp() public override {
        super.setUp();

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);
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

        s.initialize(payer, recipient, streamAmount, address(token), startTime, stopTime);

        // streamAmount / duration = 6666666.66666667
        // assuming RATE_DECIMALS = 6, we get 6666666666666
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
