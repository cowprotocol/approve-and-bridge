// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";
import {BungeeApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract DeployScript is Script {
    BungeeApproveAndBridge public bungeeApproveAndBridge;

    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function run() public {
        address deployer = msg.sender;
        uint256 salt = 9999999999999999999999; // change this before deploying if needed
        console.log("Deployer: ", deployer);
        console.log("Salt Seed: ", salt);

        bungeeApproveAndBridge = BungeeApproveAndBridge(deploy(salt));
        console.log("Deployed BungeeApproveAndBridge at: ", address(bungeeApproveAndBridge));
    }

    function deploy(uint256 salt) public returns (address addr) {
        bool ENABLE_TXNS = vm.envBool("ENABLE_TXNS");
        if (!ENABLE_TXNS) {
            console.log("Skipping deployment of contract due to ENABLE_TXNS flag");
        }

        BungeeApproveAndBridge _bungeeApproveAndBridge = new BungeeApproveAndBridge{salt: bytes32(salt)}(SOCKET_GATEWAY);
        addr = address(_bungeeApproveAndBridge);
        console.log("Deployed contract to: %s", address(addr));

        return addr;
    }
}
