// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test, Vm} from "forge-std/Test.sol";

import {ForkedRpc} from "./lib/ForkedRpc.sol";
import {BungeeApproveAndBridge, IERC20} from "src/BungeeApproveAndBridge.sol";

import {IApproveAndBridge} from "src/interface/IApproveAndBridge.sol";
import {ISocketGateway} from "src/interface/ISocketGateway.sol";

interface COWShedFactory {
    function initializeProxy(address user, bool withEns) external;
    function proxyOf(address who) external view returns (address);
}

interface COWShed {
    struct Call {
        address target;
        uint256 value;
        bytes callData;
        bool allowFailure;
        bool isDelegateCall;
    }

    function trustedExecuteHooks(Call[] calldata calls) external;
}

contract E2EBungeeApproveAndBridgeTest is Test {
    using ForkedRpc for Vm;

    uint256 private constant BASE_FORK_BLOCK = 32853375;
    ISocketGateway constant SOCKET_GATEWAY = ISocketGateway(0x3a23F943181408EAC424116Af7b7790c94Cb97a5);
    IERC20 constant USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    // https://github.com/cowdao-grants/cow-shed/blob/96cbe1ef68f5fd16a3d2899a13cd3dca52444c17/networks.json
    COWShedFactory constant factory = COWShedFactory(0x00E989b87700514118Fa55326CD1cCE82faebEF6);
    address constant user = 0x8D43954F116A4BF1dd9b75712631402F37dE5eAc; // Some USDC holder

    BungeeApproveAndBridge public approveAndBridge;
    address public receiver;

    function setUp() public {
        vm.label(user, "user");
        vm.label(address(SOCKET_GATEWAY), "socket gateway");
        vm.label(address(USDC), "USDC");

        vm.forkBaseAtBlock(BASE_FORK_BLOCK);
        approveAndBridge = new BungeeApproveAndBridge(SOCKET_GATEWAY);
        receiver = makeAddr("E2EBungeeApproveAndBridgeTest: receiver");
    }

    function test_happyPath() external {
        // Note: deployment and initialization is handled in `executeHooks` and
        // doesn't need to be done in the actual trade setting.
        // However, it's easier to build the test without handling the
        // authentication part needed for that and use `trustedExecuteHooks`
        // through the factory instead.
        factory.initializeProxy(user, false);
        COWShed shed = COWShed(factory.proxyOf(user));
        vm.label(address(shed), "shed");
        assertGt(address(shed).code.length, 0);

        uint256 orderProceeds = 5e6;
        uint256 minProceeds = 4.9e6;
        assertGt(orderProceeds, minProceeds);

        // For simplicity we take the funds from the user, but they should come
        // from an order.
        vm.prank(user);
        USDC.transfer(address(shed), orderProceeds);
        assertEq(USDC.balanceOf(address(shed)), orderProceeds);

        /* Across */
        // bytes memory BungeeApiCalldata =
        //     hex"0000019b792ebcb900000000000000000000000000000000000000000000000000000000004bea47000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000001f9a0000000000000000000000000000000000000000000000000000000000000a2d00000000000000000000000000000000000000000000000000000000000000020000000000000000000000007851b96b5798774258437195183d7c8094583c40000000000000000000000000daee4d2156de6fe6f7d50ca047136d758f96a6f00000000000000000000000000000000000000000000000000000000000000002000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000af88d065e77c8cc2239327c5edb3a432268e5831000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000004bcaad000000000000000000000000000000000000000000000000000000000000a4b10000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000006874f43f0000000000000000000000000000000000000000000000000000000068754845d00dfeeddeadbeef765753be7f7a64d5509974b0d678e1e3149b02f4";
        // uint256 inputAmountStartIndex = 8;
        // bool modifyOutputAmount = true;
        // uint256 outputAmountStartIndex = 488;
        // uint256 additionalValue = 0;

        /* CCTP */
        bytes memory BungeeApiCalldata =
            hex"0000018db7dfe9d000000000000000000000000000000000000000000000000000000000000ef52f0000000000000000000000000000000000000000000000000000000000000a2d000000000000000000000000daee4d2156de6fe6f7d50ca047136d758f96a6f0000000000000000000000000833589fcd6edb6e08f4c7c32d4f71b54bda02913000000000000000000000000000000000000000000000000000000000000a4b100000000000000000000000000000000000000000000000000000000000000030000000000000000000000000000000000000000000000000000000000061a80000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        uint256 inputAmountStartIndex = 8;
        bool modifyOutputAmount = false;
        uint256 outputAmountStartIndex = 0;
        uint256 additionalValue = 0;

        bytes memory extraData = abi.encode(inputAmountStartIndex, modifyOutputAmount, outputAmountStartIndex);
        bytes memory _calldata = abi.encodePacked(BungeeApiCalldata, extraData);

        COWShed.Call[] memory calls = new COWShed.Call[](1);
        calls[0] = COWShed.Call({
            target: address(approveAndBridge),
            value: 0,
            callData: abi.encodeCall(IApproveAndBridge.approveAndBridge, (USDC, minProceeds, additionalValue, _calldata)),
            allowFailure: false,
            isDelegateCall: true
        });

        vm.prank(address(factory));
        shed.trustedExecuteHooks(calls);
        assertEq(USDC.balanceOf(address(shed)), 0);
    }
}
