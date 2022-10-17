// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IStream } from "./IStream.sol";

contract StreamFactory {
    address immutable streamImplementation;

    constructor(address streamImplementation_) {
        streamImplementation = streamImplementation_;
    }

    function createStream(
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        bytes32 salt =
            keccak256(abi.encodePacked(recipient, deposit, tokenAddress, startTime, stopTime));
        stream = Clones.cloneDeterministic(streamImplementation, salt);
        IStream(stream).initialize(recipient, deposit, tokenAddress, startTime, stopTime);
    }

    function predictStreamAddress(
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public view returns (address) {
        bytes32 salt =
            keccak256(abi.encodePacked(recipient, deposit, tokenAddress, startTime, stopTime));
        return Clones.predictDeterministicAddress(streamImplementation, salt);
    }
}
