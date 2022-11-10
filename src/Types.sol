// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

/**
 * @title Sablier Types
 * @author Sablier
 */
library Types {
    struct Stream {
        uint256 tokenAmount;
        uint256 remainingBalance;
        uint256 ratePerSecond;
        uint256 startTime;
        uint256 stopTime;
        address recipient;
        address payer;
        address tokenAddress;
    }
}
