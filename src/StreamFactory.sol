// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { IStream } from "./IStream.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Stream Factory
 * @notice Creates minimal clones of `Stream`.
 */
contract StreamFactory {
    using SafeERC20 for IERC20;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   EVENTS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    event StreamCreated(
        address indexed payer,
        address indexed recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        address streamAddress
    );

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   IMMUTABLES
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    address immutable streamImplementation;

    constructor(address streamImplementation_) {
        streamImplementation = streamImplementation_;
    }

    /**
     * @notice Create a new stream contract instance.
     * The payer is assumed to be `msg.sender`.
     * @param recipient the recipient of the stream.
     * @param tokenAmount the total token amount payer is streaming to recipient.
     * @param tokenAddress the contract address of the payment token.
     * @param startTime the stream start timestamp in seconds.
     * @param stopTime the stream end timestamp in seconds.
     * @return stream the address of the new stream contract.
     */
    function createStream(
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        return createStream(msg.sender, recipient, tokenAmount, tokenAddress, startTime, stopTime);
    }

    /**
     * @notice Create a new stream contract instance, and fully fund it.
     * The payer is assumed to be `msg.sender`.
     * `msg.sender` must approve this contract to spend at least `tokenAmount`, otherwise the transaction
     * will revert.
     * @param recipient the recipient of the stream.
     * @param tokenAmount the total token amount payer is streaming to recipient.
     * @param tokenAddress the contract address of the payment token.
     * @param startTime the stream start timestamp in seconds.
     * @param stopTime the stream end timestamp in seconds.
     * @return stream the address of the new stream contract.
     */
    function createAndFundStream(
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        stream = createStream(recipient, tokenAmount, tokenAddress, startTime, stopTime);
        IERC20(tokenAddress).safeTransferFrom(msg.sender, stream, tokenAmount);
    }

    /**
     * @notice Create a new stream contract instance.
     * @param payer the account responsible for funding the stream.
     * @param recipient the recipient of the stream.
     * @param tokenAmount the total token amount payer is streaming to recipient.
     * @param tokenAddress the contract address of the payment token.
     * @param startTime the stream start timestamp in seconds.
     * @param stopTime the stream end timestamp in seconds.
     * @return stream the address of the new stream contract.
     */
    function createStream(
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public returns (address stream) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                msg.sender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime
            )
        );
        stream = Clones.cloneDeterministic(streamImplementation, salt);
        IStream(stream).initialize(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime);

        emit StreamCreated(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, stream);
    }

    /**
     * @notice Get the expected contract address of a stream created with the provided parameters.
     */
    function predictStreamAddress(
        address msgSender,
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public view returns (address) {
        bytes32 salt = keccak256(
            abi.encodePacked(
                msgSender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime
            )
        );
        return Clones.predictDeterministicAddress(streamImplementation, salt);
    }
}
