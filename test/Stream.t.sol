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

    function test_initialize_revertsWhenAmountModDurationNotZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountNotMultipleOfDuration.selector));
        s.initialize(payer, recipient, DURATION + 1, address(token), startTime, stopTime);
    }

    function test_initialize_savesStreamAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);

        s.initialize(payer, recipient, STREAM_AMOUNT, address(token), startTime, stopTime);

        (
            uint256 tokenAmount,
            uint256 remainingBalance,
            uint256 ratePerSecond,
            uint256 actualStartTime,
            uint256 actualStopTime,
            address actualRecipient,
            address actualPayer,
            address tokenAddress
        ) = s.stream();
        assertEq(tokenAmount, STREAM_AMOUNT);
        assertEq(remainingBalance, STREAM_AMOUNT);
        assertEq(ratePerSecond, 2);
        assertEq(actualStartTime, startTime);
        assertEq(actualStopTime, stopTime);
        assertEq(actualRecipient, recipient);
        assertEq(actualPayer, payer);
        assertEq(tokenAddress, address(token));
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

        (, uint256 remainingBalance,,,,,,) = s.stream();
        assertEq(remainingBalance, STREAM_AMOUNT - amount);
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
