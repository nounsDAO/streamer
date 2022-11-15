// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { IStream } from "./IStream.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { LibClone } from "solady/utils/LibClone.sol";

/**
 * @title Stream Factory
 * @notice Creates minimal clones of `Stream`.
 */
contract StreamFactory {
    using LibClone for address;
    using SafeERC20 for IERC20;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   ERRORS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    error PayerIsAddressZero();
    error RecipientIsAddressZero();
    error TokenAmountIsZero();
    error DurationMustBePositive();
    error TokenAmountLessThanDuration();

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
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   EXTERNAL TXS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

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
        return createStream(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, 0);
    }

    /**
     * @notice Create a new stream contract instance.
     * This version allows you to specify an additional `nonce` in case payer wants to create multiple streams
     * with the same parameters. In all other versions nonce is zero.
     * @dev The added nonce helps payer avoid stream contract address collisions among streams where all other
     * parameters are identical.
     * @param payer the account responsible for funding the stream.
     * @param recipient the recipient of the stream.
     * @param tokenAmount the total token amount payer is streaming to recipient.
     * @param tokenAddress the contract address of the payment token.
     * @param startTime the stream start timestamp in seconds.
     * @param stopTime the stream end timestamp in seconds.
     * @param nonce the nonce for this stream creation.
     * @return stream the address of the new stream contract.
     */
    function createStream(
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint8 nonce
    ) public returns (address stream) {
        if (payer == address(0)) revert PayerIsAddressZero();
        if (recipient == address(0)) revert RecipientIsAddressZero();
        if (tokenAmount == 0) revert TokenAmountIsZero();
        if (stopTime <= startTime) revert DurationMustBePositive();
        if (tokenAmount < stopTime - startTime) revert TokenAmountLessThanDuration();

        stream = streamImplementation.cloneDeterministic(
            encodeData(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime),
            salt(
                msg.sender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, nonce
            )
        );
        IStream(stream).initialize();

        emit StreamCreated(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, stream);
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   VIEW FUNCTIONS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

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
        return predictStreamAddress(
            msgSender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, 0
        );
    }

    /**
     * @notice Get the expected contract address of a stream created with the provided parameters.
     * Use this version when creating streams with a non-zero `nonce`. Should only be used on the rare occasion
     * when a payer wants to create multiple streams with identical parameters.
     */
    function predictStreamAddress(
        address msgSender,
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint8 nonce
    ) public view returns (address) {
        return streamImplementation.predictDeterministicAddress(
            encodeData(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime),
            salt(msgSender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, nonce),
            address(this)
        );
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   INTERNAL FUNCTIONS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    function encodeData(
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(this), payer, recipient, tokenAmount, tokenAddress, startTime, stopTime
        );
    }

    function salt(
        address msgSender,
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime,
        uint8 nonce
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                msgSender, payer, recipient, tokenAmount, tokenAddress, startTime, stopTime, nonce
            )
        );
    }
}
