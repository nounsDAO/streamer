// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.17;

import { ERC20Mock } from "openzeppelin-contracts/mocks/ERC20Mock.sol";
import { Stream } from "../../src/Stream.sol";

contract ReentranceRecipient {
    bool public attemptedReentry;
    bool public reenterCancel;

    function afterTransfer(Stream stream, uint256 amount) public {
        if (!attemptedReentry) {
            attemptedReentry = true;
            if (reenterCancel) {
                stream.cancel();
            } else {
                stream.withdraw(amount);
            }
        }
    }

    function setReenterCancel(bool _reenterCancel) public {
        reenterCancel = _reenterCancel;
    }
}

contract ReentranceToken is ERC20Mock {
    Stream public stream;

    constructor(
        string memory name,
        string memory symbol,
        address initialAccount,
        uint256 initialBalance
    ) payable ERC20Mock(name, symbol, initialAccount, initialBalance) { }

    function _afterTokenTransfer(address, address to, uint256 amount) internal override {
        if (address(stream) != address(0) && to == stream.recipient()) {
            ReentranceRecipient(stream.recipient()).afterTransfer(stream, amount);
        }
    }

    function setStream(Stream _stream) public {
        stream = Stream(_stream);
    }
}
