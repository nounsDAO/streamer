// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

interface IStream {
    function initialize(
        address payer,
        address recipient,
        uint256 deposit,
        address tokenAddress,
        uint256 startTime,
        uint256 stopTime
    ) external;

    function withdrawFromStream(uint256 amount) external returns (bool);
}
