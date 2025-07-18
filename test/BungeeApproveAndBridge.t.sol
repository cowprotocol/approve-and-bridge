// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {BungeeApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract BungeeApproveAndBridgeTest is Test {
    BungeeApproveAndBridge public bungeeApproveAndBridge;

    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function setUp() public {
        bungeeApproveAndBridge = new BungeeApproveAndBridge(SOCKET_GATEWAY);
    }

    function test_constructor() public {
        assertEq(bungeeApproveAndBridge.SOCKET_GATEWAY(), SOCKET_GATEWAY);
    }
}
