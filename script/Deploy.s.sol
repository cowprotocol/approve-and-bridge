// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";
import {BungeeApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract DeployScript is Script {
    BungeeApproveAndBridge public bungeeApproveAndBridge;

    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function run() public {
        address txOrigin = msg.sender;
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C; // foundry uses this contract by default
        bytes32 salt = keccak256(abi.encode(uint256(9999999999999999999999))); // change this before deploying if needed
        console.log("Deployer: ", txOrigin);
        console.log("Create2 Deployer: ", create2Deployer);
        console.logBytes32(salt);

        address computedAddress = vm.computeCreate2Address(
            salt,
            keccak256(abi.encodePacked(type(BungeeApproveAndBridge).creationCode, abi.encode(SOCKET_GATEWAY))),
            create2Deployer
        );
        console.log("Computed address: ", computedAddress);

        bungeeApproveAndBridge = BungeeApproveAndBridge(deploy(salt));
        console.log("Deployed BungeeApproveAndBridge at: ", address(bungeeApproveAndBridge));
    }

    function deploy(bytes32 salt) public returns (address addr) {
        vm.broadcast();
        BungeeApproveAndBridge _bungeeApproveAndBridge = new BungeeApproveAndBridge{salt: salt}(SOCKET_GATEWAY);
        addr = address(_bungeeApproveAndBridge);
        console.log("Deployed contract to: %s", address(addr));

        return addr;
    }
}
