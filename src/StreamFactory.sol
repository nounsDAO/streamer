// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IStream } from "./IStream.sol";

contract StreamFactory {
    event StreamCreated(
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        address streamAddress
    );

    address immutable streamImplementation;

    constructor(address streamImplementation_) {
        streamImplementation = streamImplementation_;
    }

    function createStream(
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        return createStream(msg.sender, recipient, tokenAmount, tokenAddress, startTime, stopTime);
    }

    function createStream(
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        bytes32 salt = keccak256(
            abi.encodePacked(msg.sender, recipient, tokenAmount, tokenAddress, startTime, stopTime)
        );
        stream = Clones.cloneDeterministic(streamImplementation, salt);
        IStream(stream).initialize(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime);

        emit StreamCreated(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, stream);
    }

    function predictStreamAddress(
        address msgSender,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(msgSender, recipient, tokenAmount, tokenAddress, startTime, stopTime)
        );
        return Clones.predictDeterministicAddress(streamImplementation, salt);
    }
}
