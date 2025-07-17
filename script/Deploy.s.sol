// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Script, console} from "forge-std/Script.sol";

import {BungeeApproveAndBridge, ISocketGateway} from "src/BungeeApproveAndBridge.sol";

interface ICreateX {
    function computeCreate3Address(bytes32 salt) external view returns (address computedAddress);
    function deployCreate3(bytes32 salt, bytes memory initCode) external payable returns (address newContract);
}

contract DeployScript is Script {
    BungeeApproveAndBridge public bungeeApproveAndBridge;

    ISocketGateway constant SOCKET_GATEWAY = ISocketGateway(0x3a23F943181408EAC424116Af7b7790c94Cb97a5);

    ICreateX constant createX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);

    function run() public {
        address deployer = msg.sender;
        uint256 saltSeed = 9999999999999999999999; // change this before deploying if needed
        console.log("Deployer: ", deployer);
        console.log("Salt Seed: ", saltSeed);

        bungeeApproveAndBridge = BungeeApproveAndBridge(deployCreate3(saltSeed, deployer));
        console.log("Deployed BungeeApproveAndBridge at: ", address(bungeeApproveAndBridge));
    }

    function deployCreate3(uint256 seed, address deployer) public returns (address addr) {
        (bytes32 salt, bytes32 guardedSalt) = generateGuardedSalt(seed, deployer);
        address computedAddress = createX.computeCreate3Address({salt: guardedSalt});

        console.log("computedAddress: %s", computedAddress);

        if (contractDeployed(computedAddress)) {
            console.log("Contract already deployed at: %s", computedAddress);
            return computedAddress;
        }

        bool ENABLE_TXNS = vm.envBool("ENABLE_TXNS");
        if (!ENABLE_TXNS) {
            console.log("Skipping deployment of contract due to ENABLE_TXNS flag");
            return computedAddress;
        }

        console.log("Deploying contract... %s", computedAddress);

        vm.startBroadcast();
        addr = createX.deployCreate3({
            salt: salt,
            initCode: abi.encodePacked(type(BungeeApproveAndBridge).creationCode, abi.encode(SOCKET_GATEWAY))
        });
        vm.stopBroadcast();

        console.log("Deployed contract to: %s", addr);

        require(addr == computedAddress, "Contract address mismatch due to mismatched deployer.");

        return addr;
    }

    // Generate a salt that is safeguarded against redeployments by other
    // deployers. CreateX has a safeguard mechanism that based on the following
    // salt format creates a guardedSalt that no one else can get to.
    //
    // @param seed: A random number to be used as the salt for deployment
    function generateGuardedSalt(uint256 seed, address deployer)
        public
        pure
        returns (bytes32 salt, bytes32 guardedSalt)
    {
        salt = bytes32(
            abi.encodePacked(
                deployer, // Deployment protection by our deployer
                uint8(0), // No crosschain replay protection
                seed
            )
        );

        // Mimic CreateX's guardedSalt mechanism only for our type of salt. Couldn't use CreateX's
        // _guard function because it is internal and inheriting it results in conflict with Script.
        guardedSalt = keccak256(abi.encode(bytes32(uint256(uint160(deployer))), salt));
    }

    function contractDeployed(address addr) public view returns (bool) {
        return addr.code.length > 0;
    }
}
