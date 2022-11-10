// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";
import { IStream } from "./IStream.sol";

/**
 * @title Stream
 * @notice Allows a payer to pay a recipient an amount of tokens over time, at a regular rate per second.
 * Once the stream begins vested tokens can be withdrawn at any time.
 * Either party can choose to cancel, in which case the stream distributes each party's fair share of tokens.
 * @dev A fork of Sablier https://github.com/sablierhq/sablier/blob/%40sablier/protocol%401.1.0/packages/protocol/contracts/Sablier.sol
 */
contract Stream is IStream, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   ERRORS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

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
        uint256 stopTime
    );

    event TokensWithdrawn(address indexed recipient, uint256 amount);

    event StreamCancelled(
        address indexed payer,
        address indexed recipient,
        uint256 payerBalance,
        uint256 recipientBalance
    );

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   STORAGE VARIABLES
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    uint256 public tokenAmount;
    uint256 public remainingBalance;
    uint256 public ratePerSecond;
    uint256 public startTime;
    uint256 public stopTime;
    address public recipient;
    address public payer;
    address public tokenAddress;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   MODIFIERS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @dev Reverts if the caller is not the payer or the recipient of the stream.
     */
    modifier onlyPayerOrRecipient() {
        if (msg.sender != recipient && msg.sender != payer) {
            revert CallerNotPayerOrRecipient();
        }

        _;
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   INITIALIZER
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

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

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   EXTERNAL TXS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Withdraw tokens to recipient's account.
     * Execution fails if the requested amount is greater than recipient's withdrawable balance.
     * Only this stream's payer or recipient can call this function.
     * @param amount the amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external nonReentrant onlyPayerOrRecipient {
        if (amount == 0) revert CantWithdrawZero();
        address recipient_ = recipient;

        uint256 balance = balanceOf(recipient_);
        if (balance < amount) revert AmountExceedsBalance();

        remainingBalance = remainingBalance - amount;

        IERC20(tokenAddress).safeTransfer(recipient_, amount);
        emit TokensWithdrawn(recipient_, amount);
    }

    /**
     * @notice Cancel the stream and send payer and recipient their fair share of the funds.
     * If the stream is sufficiently funded to pay recipient, execution will always succeed.
     * Payer receives the stream's token balance after paying recipient, which is fair if payer
     * hadn't fully funded the stream.
     * Only this stream's payer or recipient can call this function.
     */
    function cancel() external nonReentrant onlyPayerOrRecipient {
        address payer_ = payer;
        address recipient_ = recipient;
        IERC20 token = IERC20(tokenAddress);

        uint256 recipientBalance = balanceOf(recipient_);
        if (recipientBalance > 0) token.safeTransfer(recipient_, recipientBalance);

        uint256 payerBalance = tokenBalance();
        if (payerBalance > 0) {
            token.safeTransfer(payer_, payerBalance);
        }

        emit StreamCancelled(payer_, recipient_, payerBalance, recipientBalance);
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   VIEW FUNCTIONS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Returns the available funds to withdraw.
     * @param who The address for which to query the balance.
     * @return uint256 The total funds allocated to `who` as uint256.
     */
    function balanceOf(address who) public view returns (uint256) {
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

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   INTERNAL FUNCTIONS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @dev Helper function that makes the rest of the code look nicer.
     */
    function tokenBalance() internal view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }
}
