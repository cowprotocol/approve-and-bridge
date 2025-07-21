// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {BungeeApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract PublicBungeeApproveAndBridge is BungeeApproveAndBridge {
    constructor(address _socketGateway) BungeeApproveAndBridge(_socketGateway) {}

    function applyPctDiff(uint256 _base, uint256 _compare, uint256 _target) public view returns (uint256) {
        return super._applyPctDiff(_base, _compare, _target);
    }
}

contract BungeeApproveAndBridgeTest is Test {
    PublicBungeeApproveAndBridge public bungeeApproveAndBridge;

    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function setUp() public {
        bungeeApproveAndBridge = new PublicBungeeApproveAndBridge(SOCKET_GATEWAY);
    }

    function test_constructor() public {
        assertEq(bungeeApproveAndBridge.SOCKET_GATEWAY(), SOCKET_GATEWAY);
    }

    function test_applyPctDiff() public {
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 110, _target: 100}), 110);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 90, _target: 100}), 90);
    }

    function test_applyPctDiff_equal() public {
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 100, _target: 100}), 100);
    }
}
