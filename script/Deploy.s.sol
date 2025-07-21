// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";
import {BungeeApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract DeployScript is Script {
    BungeeApproveAndBridge public bungeeApproveAndBridge;

    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function run() public {
        address deployer = msg.sender;
        address create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C; // foundry uses this contract by default
        uint256 salt = 9999999999999999999999; // change this before deploying if needed
        console.log("Deployer: ", deployer);
        console.log("create2Deployer: ", create2Deployer);
        console.log("Salt Seed: ", salt);

        bungeeApproveAndBridge = BungeeApproveAndBridge(deploy(salt, create2Deployer));
        console.log("Deployed BungeeApproveAndBridge at: ", address(bungeeApproveAndBridge));
    }

    function deploy(uint256 salt, address deployer) public returns (address addr) {
        bytes memory initCode = getInitCode();
        address computedAddress = computeCreate2Address(salt, deployer, initCode);
        console.log("computedAddress: %s", computedAddress);

        bool ENABLE_TXNS = vm.envBool("ENABLE_TXNS");
        if (!ENABLE_TXNS) {
            console.log("Skipping deployment of contract due to ENABLE_TXNS flag");
            return computedAddress;
        }

        if (contractDeployed(computedAddress)) {
            console.log("Contract already deployed at: %s", computedAddress);
            return computedAddress;
        }
        console.log("Deploying contract... %s", computedAddress);

        BungeeApproveAndBridge _bungeeApproveAndBridge = new BungeeApproveAndBridge{salt: bytes32(salt)}(SOCKET_GATEWAY);
        addr = address(_bungeeApproveAndBridge);

        console.log("Deployed contract to: %s", address(addr));
        require(addr == computedAddress, "Contract address mismatch due to mismatched deployer.");

        return addr;
    }

    function getInitCode() public pure returns (bytes memory) {
        bytes memory initCode = abi.encodePacked(type(BungeeApproveAndBridge).creationCode, abi.encode(SOCKET_GATEWAY));
        return initCode;
    }

    function computeCreate2Address(uint256 salt, address deployer, bytes memory initCode)
        public
        pure
        returns (address)
    {
        bytes32 _hash = keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(initCode)));
        address computedAddress = address(uint160(uint256(_hash)));
        return computedAddress;
    }

    function contractDeployed(address addr) public view returns (bool) {
        return addr.code.length > 0;
    }
}
