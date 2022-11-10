// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { Initializable } from "openzeppelin-contracts/proxy/utils/Initializable.sol";
import { ReentrancyGuard } from "openzeppelin-contracts/security/ReentrancyGuard.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Types } from "./Types.sol";
import { CarefulMath } from "./CarefulMath.sol";
import { IStream } from "./IStream.sol";

contract Stream is IStream, Initializable, ReentrancyGuard, CarefulMath {
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

    Types.Stream public stream;

    /**
     * @dev Throws if the caller is not the sender of the recipient of the stream.
     */
    modifier onlySenderOrRecipient() {
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

        stream = Types.Stream({
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

    function withdraw(uint256 amount) external nonReentrant onlySenderOrRecipient {
        if (amount == 0) revert CantWithdrawZero();

        uint256 balance = balanceOf(stream.recipient);
        if (balance < amount) revert AmountExceedsBalance();

        stream.remainingBalance = stream.remainingBalance - amount;

        IERC20(stream.tokenAddress).safeTransfer(stream.recipient, amount);
        emit TokensWithdrawn(stream.recipient, amount);
    }

    /**
     * @notice Returns the available funds for the given stream id and address.
     * @dev Throws if the id does not point to a valid stream.
     * @param who The address for which to query the balance.
     * @return balance The total funds allocated to `who` as uint256.
     */
    function balanceOf(address who) public view returns (uint256 balance) {
        // Types.Stream memory stream = streams[streamId];
        BalanceOfLocalVars memory vars;

        uint256 delta = deltaOf();
        (vars.mathErr, vars.recipientBalance) = mulUInt(delta, stream.ratePerSecond);
        require(vars.mathErr == MathError.NO_ERROR, "recipient balance calculation error");

        /*
         * If the stream `balance` does not equal `tokenAmount`, it means there have been withdrawals.
         * We have to subtract the total amount withdrawn from the amount of money that has been
         * streamed until now.
         */
        if (stream.tokenAmount > stream.remainingBalance) {
            (vars.mathErr, vars.withdrawalAmount) =
                subUInt(stream.tokenAmount, stream.remainingBalance);
            assert(vars.mathErr == MathError.NO_ERROR);
            (vars.mathErr, vars.recipientBalance) =
                subUInt(vars.recipientBalance, vars.withdrawalAmount);
            /* `withdrawalAmount` cannot and should not be bigger than `recipientBalance`. */
            assert(vars.mathErr == MathError.NO_ERROR);
        }

        if (who == stream.recipient) return vars.recipientBalance;
        if (who == stream.payer) {
            (vars.mathErr, vars.senderBalance) =
                subUInt(stream.remainingBalance, vars.recipientBalance);
            /* `recipientBalance` cannot and should not be bigger than `remainingBalance`. */
            assert(vars.mathErr == MathError.NO_ERROR);
            return vars.senderBalance;
        }
        return 0;
    }

    struct BalanceOfLocalVars {
        MathError mathErr;
        uint256 recipientBalance;
        uint256 withdrawalAmount;
        uint256 senderBalance;
    }

    /**
     * @notice Returns either the delta in seconds between `block.timestamp` and `startTime` or
     *  between `stopTime` and `startTime, whichever is smaller. If `block.timestamp` is before
     *  `startTime`, it returns 0.
     * @return delta The time delta in seconds.
     */
    function deltaOf() public view returns (uint256 delta) {
        if (block.timestamp <= stream.startTime) return 0;
        if (block.timestamp < stream.stopTime) return block.timestamp - stream.startTime;
        return stream.stopTime - stream.startTime;
    }
}
