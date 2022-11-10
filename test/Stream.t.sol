// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { StreamFactory } from "../src/StreamFactory.sol";
import { Stream } from "../src/Stream.sol";
import { IStream } from "../src/IStream.sol";

contract StreamTest is Test {
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
}
