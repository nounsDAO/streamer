// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { IStream } from "./IStream.sol";
import { Clone } from "solady/utils/Clone.sol";
import { IERC20 } from "openzeppelin-contracts/interfaces/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "openzeppelin-contracts/utils/math/Math.sol";

/**
 * @title Stream
 * @notice Allows a payer to pay a recipient an amount of tokens over time, at a regular rate per second.
 * Once the stream begins vested tokens can be withdrawn at any time.
 * Either party can choose to cancel, in which case the stream distributes each party's fair share of tokens.
 * @dev A fork of Sablier https://github.com/sablierhq/sablier/blob/%40sablier/protocol%401.1.0/packages/protocol/contracts/Sablier.sol.
 * Inherits from `Clone`, which allows Stream to read immutable arguments from its code section rather than state, resulting
 * in significant gas savings for users.
 */
contract Stream is IStream, Clone {
    using SafeERC20 for IERC20;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   ERRORS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    error OnlyFactory();
    error CantWithdrawZero();
    error AmountExceedsBalance();
    error CallerNotPayerOrRecipient();
    error CallerNotPayer();
    error RescueTokenAmountExceedsExcessBalance();

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   EVENTS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /// @dev msgSender is part of the event to enable event indexing with which account performed this action.
    event TokensWithdrawn(address indexed msgSender, address indexed recipient, uint256 amount);

    /// @dev msgSender is part of the event to enable event indexing with which account performed this action.
    event StreamCancelled(
        address indexed msgSender,
        address indexed payer,
        address indexed recipient,
        uint256 payerBalance,
        uint256 recipientBalance
    );

    event TokensRecovered(address tokenAddress, uint256 amount);

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   IMMUTABLES
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice Used to add precision to `ratePerSecond`, to minimize the impact of rounding down.
     * See `ratePerSecond()` implementation for more information.
     */
    uint256 public constant RATE_DECIMALS_MULTIPLIER = 1e6;

    /**
     * @notice Get the address of the factory contract that cloned this Stream instance.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function factory() public pure returns (address) {
        return _getArgAddress(0);
    }

    /**
     * @notice Get this stream's payer address.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function payer() public pure returns (address) {
        return _getArgAddress(20);
    }

    /**
     * @notice Get this stream's recipient address.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function recipient() public pure returns (address) {
        return _getArgAddress(40);
    }

    /**
     * @notice Get this stream's total token amount.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function tokenAmount() public pure returns (uint256) {
        return _getArgUint256(60);
    }

    /**
     * @notice Get this stream's ERC20 token.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function token() public pure returns (IERC20) {
        return IERC20(_getArgAddress(92));
    }

    /**
     * @notice Get this stream's start timestamp in seconds.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function startTime() public pure returns (uint256) {
        return _getArgUint256(112);
    }

    /**
     * @notice Get this stream's end timestamp in seconds.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function stopTime() public pure returns (uint256) {
        return _getArgUint256(144);
    }

    /**
     * @notice Get this stream's token streaming rate per second.
     * @dev Uses clone-with-immutable-args to read the value from the contract's code region rather than state to save gas.
     */
    function ratePerSecond() public pure returns (uint256) {
        uint256 duration = stopTime() - startTime();

        unchecked {
            // ratePerSecond can lose precision as its being rounded down here
            // the value lost in rounding down results in less income per second for recipient
            // max round down impact is duration - 1; e.g. one year, that's 31_557_599
            // e.g. using USDC (w/ 6 decimals) that's ~32 USDC
            // since ratePerSecond has 6 decimals, 31_557_599 / 1e6 = 0.00003156; round down impact becomes negligible
            // finally, this remainder dust becomes available to recipient when stream duration is fully elapsed
            // see `_recipientBalance` where `blockTime >= stopTime`
            return RATE_DECIMALS_MULTIPLIER * tokenAmount() / duration;
        }
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   STORAGE VARIABLES
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @notice The maximum token balance remaining in the stream when taking withdrawals into account.
     * Should be equal to the stream's token balance once fully funded.
     * @dev using remaining balance rather than a growing sum of withdrawals for gas optimization reasons.
     * This approach warms up this slot upon stream creation, so that withdrawals cost less gas.
     * If this were the sum of withdrawals, recipient would pay 20K extra gas on their first withdrawal.
     */
    uint256 public remainingBalance;

    /**
     * @notice The recipient's balance once the stream is cancelled. It is set to the recipient's balance
     * at the moment of cancellation, and is decremented when recipient withdraws post-cancellation.
     * @dev It's assumed to be zero as long as the stream has not been cancelled.
     */
    uint256 public recipientCancelBalance;

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   MODIFIERS
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @dev Reverts if the caller is not the payer or the recipient of the stream.
     */
    modifier onlyPayerOrRecipient() {
        if (msg.sender != recipient() && msg.sender != payer()) {
            revert CallerNotPayerOrRecipient();
        }

        _;
    }

    /**
     * @dev Reverts if the caller is not the payer of the stream.
     */
    modifier onlyPayer() {
        if (msg.sender != payer()) {
            revert CallerNotPayer();
        }

        _;
    }

    /**
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     *   INITIALIZER
     * ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
     */

    /**
     * @dev Limiting calls to factory only to prevent abuse. This approach is more gas efficient than using
     * OpenZeppelin's Initializable since we avoid the storage writes that entails.
     * This does create the possibility for the factory to initialize the same stream twice; this risk seems low
     * and worth the gas savings.
     */
    function initialize() external {
        if (msg.sender != factory()) revert OnlyFactory();

        remainingBalance = tokenAmount();
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
     * @dev Until a stream is cancelled, `remainingBalance` is used to capture withdrawal information.
     * Once cancelled, recipientCancelBalance is used to capture withdrawal information.
     * Either variable is decremented by `amount` tokens.
     * @param amount the amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external onlyPayerOrRecipient {
        if (amount == 0) revert CantWithdrawZero();
        address recipient_ = recipient();
        uint256 recipientCancelBalance_ = recipientCancelBalance;

        if (recipientCancelBalance_ > 0) {
            if (recipientCancelBalance_ < amount) revert AmountExceedsBalance();
            // Safe because of the above check and revert.
            unchecked {
                recipientCancelBalance = recipientCancelBalance_ - amount;
            }
        } else {
            uint256 balance = balanceOf(recipient_);
            if (balance < amount) revert AmountExceedsBalance();

            // This is safe because it should always be the case that:
            // remainingBalance >= balance >= amount.
            unchecked {
                remainingBalance = remainingBalance - amount;
            }
        }

        token().safeTransfer(recipient_, amount);
        emit TokensWithdrawn(msg.sender, recipient_, amount);
    }

    /**
     * @notice Cancel the stream and update recipient's fair share of the funds to their current balance.
     * Each party must take additional action to withdraw their funds:
     * recipient must call `withdraw`.
     * payer must call `recoverTokens`.
     * Only this stream's payer or recipient can call this function.
     */
    function cancel() external onlyPayerOrRecipient {
        address payer_ = payer();
        address recipient_ = recipient();
        uint256 tokenBalance_ = tokenBalance();

        uint256 recipientBalance = balanceOf(recipient_);

        // This overrides `withdraw` logic to allow recipient to withdraw their fair share.
        recipientCancelBalance = recipientBalance;

        // This zeroing is important because without it, it's possible for recipient to obtain additional funds
        // from this contract if anyone (e.g. payer) sends it tokens after cancellation.
        // Thanks to this state update, `balanceOf(recipient_)` will only return zero in future calls.
        remainingBalance = 0;

        // When the stream is underfunded payer might not have an outstanding balance.
        // Calculating payer's balance using the stream's token balance also accounts for when the stream might be overfunded.
        uint256 payerBalance = 0;
        if (tokenBalance_ > recipientBalance) {
            unchecked {
                payerBalance = tokenBalance_ - recipientBalance;
            }
        }

        emit StreamCancelled(msg.sender, payer_, recipient_, payerBalance, recipientBalance);
    }

    /**
     * @notice Recover excess stream payment tokens, or other ERC20 tokens accidentally sent to this stream.
     * When a stream is cancelled payer uses this function to recover their fair share of tokens.
     * Reverts when trying to recover stream's payment token at an amount that exceeds
     * the excess token balance; any rescue should always leave sufficient tokens to
     * fully pay recipient.
     * Reverts when msg.sender is not this stream's payer.
     * @dev Checking token balance before and after to defend against the case of multiple contracts
     * updating the balance of the same token.
     * @param tokenAddress the contract address of the token to recover.
     * @param amount the amount to recover.
     */
    function recoverTokens(address tokenAddress, uint256 amount) external onlyPayer {
        // When the stream is under-funded, it should keep its current balance
        // When it's sufficiently-funded, it should keep the full balance committed to recipient
        // i.e. `remainingBalance` or `recipientCancelBalance`
        uint256 requiredBalanceAfter =
            Math.min(tokenBalance(), Math.max(remainingBalance, recipientCancelBalance));

        IERC20(tokenAddress).safeTransfer(msg.sender, amount);

        if (tokenBalance() < requiredBalanceAfter) revert RescueTokenAmountExceedsExcessBalance();

        emit TokensRecovered(tokenAddress, amount);
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
        uint256 recipientBalance = _recipientBalance();

        if (who == recipient()) return recipientBalance;
        if (who == payer()) {
            uint256 tokenTotal_ = Math.max(tokenBalance(), remainingBalance);
            // tokenBalance can be less than recipientBalance, e.g. when a stream is cancelled after recipient
            // accumulated vested balance, and before payer funded the stream.
            if (tokenTotal_ > recipientBalance) {
                unchecked {
                    return tokenTotal_ - recipientBalance;
                }
            }
        }
        return 0;
    }

    /**
     * @notice Returns the time elapsed in this stream, or zero if it hasn't started yet.
     */
    function elapsedTime() public view returns (uint256) {
        uint256 startTime_ = startTime();
        if (block.timestamp <= startTime_) return 0;

        uint256 stopTime_ = stopTime();
        if (block.timestamp < stopTime_) return block.timestamp - startTime_;

        return stopTime_ - startTime_;
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
     * @dev Helper function for `balanceOf` in calculating recipient's fair share of tokens, taking withdrawals into account.
     * When a stream is cancelled the balance will be `recipientCancelBalance` until it's fully withdrawan, then
     * it will remain at zero.
     */
    function _recipientBalance() internal view returns (uint256) {
        uint256 startTime_ = startTime();
        uint256 blockTime = block.timestamp;

        if (blockTime <= startTime_) return 0;

        uint256 recipientCancelBalance_ = recipientCancelBalance;
        if (recipientCancelBalance_ > 0) return recipientCancelBalance_;

        uint256 tokenAmount_ = tokenAmount();
        uint256 balance;
        if (blockTime >= stopTime()) {
            balance = tokenAmount_;
        } else {
            // This is safe because: blockTime > startTime_ (checked above).
            unchecked {
                uint256 elapsedTime_ = blockTime - startTime_;
                balance = (elapsedTime_ * ratePerSecond()) / RATE_DECIMALS_MULTIPLIER;
            }
        }

        uint256 remainingBalance_ = remainingBalance;

        // When this function is called after the stream has been cancelled, when balance is less than
        // tokenAmount, without this early exit, the withdrawal calculation below results in an underflow error.
        if (remainingBalance_ == 0) return 0;

        // Take withdrawals into account
        if (tokenAmount_ > remainingBalance_) {
            // Should be safe because remainingBalance_ starts as equal to
            // tokenAmount_ when the stream starts and only grows smaller due to
            // withdrawals, so tokenAmount_ >= remainingBalance_ is always true.
            // Should also be always true that balance >= withdrawalAmount, since
            // at this point balance represents the total amount streamed to recipient
            // so far, which is always the upper bound of what could have been withdrawn.
            unchecked {
                uint256 withdrawalAmount = tokenAmount_ - remainingBalance_;
                balance -= withdrawalAmount;
            }
        }

        return balance;
    }

    /**
     * @dev Helper function that makes the rest of the code look nicer.
     */
    function tokenBalance() internal view returns (uint256) {
        return token().balanceOf(address(this));
    }
}
