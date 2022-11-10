// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IStream } from "./IStream.sol";

contract Stream is IStream, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error PayerIsAddressZero();
    error RecipientIsAddressZero();
    error RecipientIsStreamContract();
    error TokenAmountIsZero();
    error DurationMustBePositive();
    error TokenAmountLessThanDuration();
    error TokenAmountNotMultipleOfDuration();
    error CantWithdrawZero();
    error AmountExceedsBalance();
    error CallerNotPayerOrRecipient();

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

    StreamState public stream;

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     */
    modifier onlyPayerOrRecipient() {
        if (msg.sender != stream.recipient && msg.sender != stream.payer) {
            revert CallerNotPayerOrRecipient();
        }

        _;
    }

    function initialize(
        address payer,
        address recipient,
        uint256 tokenAmount,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) public initializer {
        if (payer == address(0)) revert PayerIsAddressZero();
        if (recipient == address(0)) revert RecipientIsAddressZero();
        if (recipient == address(this)) revert RecipientIsStreamContract();
        if (tokenAmount == 0) revert TokenAmountIsZero();
        if (stopTime <= startTime) revert DurationMustBePositive();

        uint256 duration = stopTime - startTime;

        if (tokenAmount < duration) revert TokenAmountLessThanDuration();
        if (tokenAmount % duration != 0) revert TokenAmountNotMultipleOfDuration();

        stream = StreamState({
            remainingBalance: tokenAmount,
            tokenAmount: tokenAmount,
            ratePerSecond: tokenAmount / duration,
            recipient: recipient,
            payer: payer,
            startTime: startTime,
            stopTime: stopTime,
            tokenAddress: tokenAddress
        });

        emit StreamCreated(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime);
    }

    function withdraw(uint256 amount) external nonReentrant onlyPayerOrRecipient {
        if (amount == 0) revert CantWithdrawZero();
        address recipient = stream.recipient;

        uint256 balance = balanceOf(recipient);
        if (balance < amount) revert AmountExceedsBalance();

        stream.remainingBalance = stream.remainingBalance - amount;

        IERC20(stream.tokenAddress).safeTransfer(recipient, amount);
        emit TokensWithdrawn(recipient, amount);
    }

    function cancel() external nonReentrant onlyPayerOrRecipient {
        address payer = stream.payer;
        address recipient = stream.recipient;

        uint256 payerBalance = Math.min(balanceOf(payer), tokenBalance());
        uint256 recipientBalance = balanceOf(recipient);

        IERC20 token = IERC20(stream.tokenAddress);
        if (payerBalance > 0) {
            token.safeTransfer(payer, payerBalance);
        }
        if (recipientBalance > 0) token.safeTransfer(recipient, recipientBalance);

        emit StreamCancelled(payer, recipient, payerBalance, recipientBalance);
    }

    /**
     * @notice Returns the available funds to withdraw
     * @param who The address for which to query the balance.
     * @return balance The total funds allocated to `who` as uint256.
     */
    function balanceOf(address who) public view returns (uint256 balance) {
        uint256 streamTokenAmount = stream.tokenAmount;
        uint256 streamRemainingBalance = stream.remainingBalance;
        uint256 recipientBalance = elapsedTime() * stream.ratePerSecond;

        // Take withdrawals into account
        if (streamTokenAmount > streamRemainingBalance) {
            uint256 withdrawalAmount = streamTokenAmount - streamRemainingBalance;
            recipientBalance -= withdrawalAmount;
        }

        if (who == stream.recipient) return recipientBalance;
        if (who == stream.payer) {
            return streamRemainingBalance - recipientBalance;
        }
        return 0;
    }

    /**
     * @notice Returns the time elapsed in this stream, or zero if it hasn't started yet.
     */
    function elapsedTime() public view returns (uint256) {
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp < stream.stopTime) return block.timestamp - stream.startTime;
        return stream.stopTime - stream.startTime;
    }

    function tokenBalance() internal view returns (uint256) {
        return IERC20(stream.tokenAddress).balanceOf(address(this));
    }
}
