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

    uint256 public tokenAmount;
    uint256 public remainingBalance;
    uint256 public ratePerSecond;
    uint256 public startTime;
    uint256 public stopTime;
    address public recipient;
    address public payer;
    address public tokenAddress;

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     */
    modifier onlyPayerOrRecipient() {
        if (msg.sender != recipient && msg.sender != payer) {
            revert CallerNotPayerOrRecipient();
        }

        _;
    }

    function initialize(
        address _payer,
        address _recipient,
        uint256 _tokenAmount,
        address _tokenAddress,
        uint256 _startTime,
        uint256 _stopTime
    ) public initializer {
        if (_payer == address(0)) revert PayerIsAddressZero();
        if (_recipient == address(0)) revert RecipientIsAddressZero();
        if (_recipient == address(this)) revert RecipientIsStreamContract();
        if (_tokenAmount == 0) revert TokenAmountIsZero();
        if (_stopTime <= _startTime) revert DurationMustBePositive();

        uint256 duration = _stopTime - _startTime;

        if (_tokenAmount < duration) revert TokenAmountLessThanDuration();
        if (_tokenAmount % duration != 0) revert TokenAmountNotMultipleOfDuration();

        remainingBalance = _tokenAmount;
        tokenAmount = _tokenAmount;
        ratePerSecond = _tokenAmount / duration;
        recipient = _recipient;
        payer = _payer;
        startTime = _startTime;
        stopTime = _stopTime;
        tokenAddress = _tokenAddress;

        emit StreamCreated(payer, recipient, tokenAmount, tokenAddress, startTime, stopTime);
    }

    function withdraw(uint256 amount) external nonReentrant onlyPayerOrRecipient {
        if (amount == 0) revert CantWithdrawZero();
        address recipient_ = recipient;

        uint256 balance = balanceOf(recipient_);
        if (balance < amount) revert AmountExceedsBalance();

        remainingBalance = remainingBalance - amount;

        IERC20(tokenAddress).safeTransfer(recipient_, amount);
        emit TokensWithdrawn(recipient_, amount);
    }

    function cancel() external nonReentrant onlyPayerOrRecipient {
        address payer_ = payer;
        address recipient_ = recipient;

        uint256 payerBalance = Math.min(balanceOf(payer_), tokenBalance());
        uint256 recipientBalance = balanceOf(recipient_);

        IERC20 token = IERC20(tokenAddress);
        if (payerBalance > 0) {
            token.safeTransfer(payer_, payerBalance);
        }
        if (recipientBalance > 0) token.safeTransfer(recipient_, recipientBalance);

        emit StreamCancelled(payer_, recipient_, payerBalance, recipientBalance);
    }

    /**
     * @notice Returns the available funds to withdraw
     * @param who The address for which to query the balance.
     * @return balance The total funds allocated to `who` as uint256.
     */
    function balanceOf(address who) public view returns (uint256 balance) {
        uint256 tokenAmount_ = tokenAmount;
        uint256 remainingBalance_ = remainingBalance;
        uint256 recipientBalance = elapsedTime() * ratePerSecond;

        // Take withdrawals into account
        if (tokenAmount_ > remainingBalance_) {
            uint256 withdrawalAmount = tokenAmount_ - remainingBalance_;
            recipientBalance -= withdrawalAmount;
        }

        if (who == recipient) return recipientBalance;
        if (who == payer) {
            return remainingBalance_ - recipientBalance;
        }
        return 0;
    }

    /**
     * @notice Returns the time elapsed in this stream, or zero if it hasn't started yet.
     */
    function elapsedTime() public view returns (uint256) {
        if (block.timestamp <= startTime) return 0;
        if (block.timestamp < stopTime) return block.timestamp - startTime;
        return stopTime - startTime;
    }

    /**
     * @notice Get this stream's token balance vs the token amount required to meet the commitment
     * to recipient.
     */
    function tokenAndOutstandingBalance() public view returns (uint256, uint256) {
        return (tokenBalance(), remainingBalance);
    }

    function tokenBalance() internal view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }
}
