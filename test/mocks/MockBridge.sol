// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

// Mock contract that always fails bridge calls
contract MockFailingBridge {
    fallback() external payable {
        revert("Bridge call failed");
    }
}
