// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamTest is Test {
    event CreateStream(
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    );

    ERC20Mock token;
    Stream s;

    function setUp() public {
        token = new ERC20Mock("mock-token", "MOK", address(1), 0);
        s = new Stream();
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
        emit CreateStream(
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
