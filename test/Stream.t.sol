// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamTest is Test {
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
    }
}

contract StreamInitializeTest is StreamTest {
    function setUp() public override {
        super.setUp();
    }

    function test_initialize_revertsWhenCalledTwice() public {
        s.initialize(
            address(0x11),
            address(0x22),
            1000,
            address(token),
            block.timestamp,
            block.timestamp + 1000
        );

        vm.expectRevert("Initializable: contract is already initialized");
        s.initialize(
            address(0x11),
            address(0x22),
            1000,
            address(token),
            block.timestamp,
            block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenPayerIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.PayerIsAddressZero.selector));
        s.initialize(
            address(0), address(0x22), 1000, address(token), block.timestamp, block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenRecipientIsAddressZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.RecipientIsAddressZero.selector));
        s.initialize(
            address(0x11), address(0), 1000, address(token), block.timestamp, block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenRecipientIsTheStreamContract() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.RecipientIsStreamContract.selector));
        s.initialize(
            address(0x11), address(s), 1000, address(token), block.timestamp, block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenTokenAmountIsZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountIsZero.selector));
        s.initialize(
            address(0x11), address(0x22), 0, address(token), block.timestamp, block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenDurationIsNotPositive() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.DurationMustBePositive.selector));
        s.initialize(
            address(0x11), address(0x22), 1000, address(token), block.timestamp, block.timestamp
        );
    }

    function test_initialize_revertsWhenAmountLessThanDuration() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountLessThanDuration.selector));
        s.initialize(
            address(0x11),
            address(0x22),
            999,
            address(token),
            block.timestamp,
            block.timestamp + 1000
        );
    }

    function test_initialize_revertsWhenAmountModDurationNotZero() public {
        vm.expectRevert(abi.encodeWithSelector(Stream.TokenAmountNotMultipleOfDuration.selector));
        s.initialize(
            address(0x11),
            address(0x22),
            1001,
            address(token),
            block.timestamp,
            block.timestamp + 1000
        );
    }

    function test_initialize_savesStreamAndEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit StreamCreated(
            address(0x11),
            address(0x22),
            2000,
            address(token),
            block.timestamp,
            block.timestamp + 1000
            );

        s.initialize(
            address(0x11),
            address(0x22),
            2000,
            address(token),
            block.timestamp,
            block.timestamp + 1000
        );

        (
            uint256 tokenAmount,
            uint256 remainingBalance,
            uint256 ratePerSecond,
            uint256 startTime,
            uint256 stopTime,
            address recipient,
            address payer,
            address tokenAddress
        ) = s.stream();
        assertEq(tokenAmount, 2000);
        assertEq(remainingBalance, 2000);
        assertEq(ratePerSecond, 2);
        assertEq(startTime, block.timestamp);
        assertEq(stopTime, block.timestamp + 1000);
        assertEq(recipient, address(0x22));
        assertEq(payer, address(0x11));
        assertEq(tokenAddress, address(token));
    }
}

contract StreamWithdrawTest is StreamTest {
    uint256 constant DURATION = 1000;
    uint256 constant STREAM_AMOUNT = 2000;

    uint256 startTime;
    uint256 stopTime;
    address payer = address(0x11);
    address recipient = address(0x22);

    function setUp() public override {
        super.setUp();

        startTime = block.timestamp;
        stopTime = block.timestamp + DURATION;

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
}
