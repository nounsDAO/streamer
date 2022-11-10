// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

interface IStream {
    struct StreamState {
        uint256 tokenAmount;
        uint256 remainingBalance;
        uint256 ratePerSecond;
        uint256 startTime;
        uint256 stopTime;
        address recipient;
        address payer;
        address tokenAddress;
    }

    function initialize(
        address payer,
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) external;

    function withdraw(uint256 amount) external;
}
