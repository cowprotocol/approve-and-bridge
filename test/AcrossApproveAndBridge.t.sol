// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "../src/vendored/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFailingBridge} from "./mocks/MockBridge.sol";
import {MockAcrossSpokePool} from "./mocks/MockAcrossSpokePool.sol";

import {AcrossApproveAndBridge, ApproveAndBridge} from "src/AcrossApproveAndBridge.sol";
import {IAcrossSpokePoolV3} from "src/interface/IAcrossSpokePoolV3.sol";

contract AcrossApproveAndBridgeTest is Test {
    AcrossApproveAndBridge public acrossApproveAndBridge;
    MockAcrossSpokePool public spokePool;
    MockERC20 public mockToken;
    MockFailingBridge public failingBridge;

    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0x4200000000000000000000000000000000000006;

    address public depositor = makeAddr("depositor");
    address public recipient = makeAddr("recipient");
    address public outputToken = makeAddr("outputToken");

    function setUp() public {
        spokePool = new MockAcrossSpokePool();
        acrossApproveAndBridge = new AcrossApproveAndBridge(address(spokePool));
        mockToken = new MockERC20(0);
        failingBridge = new MockFailingBridge();
    }

    /// @dev Builds a depositV3 calldata blob with the given input/output amounts.
    /// @dev Built in chunks to avoid stack-too-deep when encoding 12 args.
    function _buildDepositCalldata(address inputToken, uint256 inputAmount, uint256 outputAmount, bytes memory message)
        internal
        view
        returns (bytes memory)
    {
        bytes memory addrPart = abi.encode(depositor, recipient, inputToken, outputToken);
        bytes memory amountsPart = abi.encode(inputAmount, outputAmount, uint256(42161), address(0));
        // 11 fixed head slots + 1 offset slot for message = 12 slots = 384 bytes offset
        bytes memory deadlinesPart = abi.encode(uint32(1700000000), uint32(1700003600), uint32(0), uint256(384));
        bytes memory tail = abi.encode(message);
        return abi.encodePacked(IAcrossSpokePoolV3.depositV3.selector, addrPart, amountsPart, deadlinesPart, tail);
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    function test_constructor() public view {
        assertEq(acrossApproveAndBridge.SPOKE_POOL(), address(spokePool));
    }

    function test_constructor_shouldRevert_nonContractAddress() public {
        address nonContract = address(0x123);
        vm.expectRevert("Spoke pool contract not deployed");
        new AcrossApproveAndBridge(nonContract);

        address emptyContract = address(0x456);
        vm.etch(emptyContract, "");
        vm.expectRevert("Spoke pool contract not deployed");
        new AcrossApproveAndBridge(emptyContract);
    }

    function test_bridgeApprovalTarget() public view {
        assertEq(acrossApproveAndBridge.bridgeApprovalTarget(), address(spokePool));
    }

    /*//////////////////////////////////////////////////////////////
                          ERC20 BRIDGE FLOW
    //////////////////////////////////////////////////////////////*/
    function test_approveAndBridge_ERC20_exactBalance() public {
        uint256 balance = 100e18;
        mockToken.mint(address(acrossApproveAndBridge), balance);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");

        vm.expectCall(address(mockToken), abi.encodeCall(IERC20.approve, (address(spokePool), balance)));
        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);

        assertEq(spokePool.callCount(), 1);
        assertEq(spokePool.lastDepositor(), depositor);
        assertEq(spokePool.lastRecipient(), recipient);
        assertEq(spokePool.lastInputToken(), address(mockToken));
        assertEq(spokePool.lastOutputToken(), outputToken);
        assertEq(spokePool.lastInputAmount(), balance);
        // exact balance == original input -> output unchanged
        assertEq(spokePool.lastOutputAmount(), 99e18);
        assertEq(spokePool.lastDestinationChainId(), 42161);
        assertEq(spokePool.lastExclusiveRelayer(), address(0));
        assertEq(spokePool.lastQuoteTimestamp(), 1700000000);
        assertEq(spokePool.lastFillDeadline(), 1700003600);
        assertEq(spokePool.lastExclusivityDeadline(), 0);
        assertEq(spokePool.lastMessage(), hex"");
        assertEq(spokePool.lastValue(), 0);
    }

    function test_approveAndBridge_ERC20_scalesOutputWithSurplus() public {
        // Surplus: contract holds 110 of input but quote was for 100 -> output 99 * 110/100 = 108.9
        uint256 balance = 110e18;
        mockToken.mint(address(acrossApproveAndBridge), balance);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");

        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 100e18, 0, data);

        assertEq(spokePool.lastInputAmount(), balance);
        assertEq(spokePool.lastOutputAmount(), (99e18 * balance) / 100e18);
    }

    function test_approveAndBridge_ERC20_scalesOutputWhenBelowQuote() public {
        uint256 balance = 90e18;
        mockToken.mint(address(acrossApproveAndBridge), balance);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");

        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);

        assertEq(spokePool.lastInputAmount(), balance);
        assertEq(spokePool.lastOutputAmount(), (99e18 * balance) / 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                          NATIVE BRIDGE FLOW
    //////////////////////////////////////////////////////////////*/
    function test_approveAndBridge_native_forwardsValue() public {
        uint256 balance = 5e18;
        vm.deal(address(acrossApproveAndBridge), balance);

        bytes memory data = _buildDepositCalldata(WETH, 5e18, 4.95e18, "");

        acrossApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), 1e18, 0, data);

        assertEq(spokePool.lastInputToken(), WETH);
        assertEq(spokePool.lastInputAmount(), balance);
        assertEq(spokePool.lastValue(), balance);
    }

    function test_approveAndBridge_native_forwardsExtraFee() public {
        uint256 balance = 5e18;
        uint256 extraFee = 0.05e18;
        vm.deal(address(acrossApproveAndBridge), balance + extraFee);

        bytes memory data = _buildDepositCalldata(WETH, 5e18, 4.95e18, "");

        acrossApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), 1e18, extraFee, data);

        assertEq(spokePool.lastInputAmount(), balance);
        assertEq(spokePool.lastValue(), balance + extraFee);
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION
    //////////////////////////////////////////////////////////////*/
    function test_approveAndBridge_revertsOnInsufficientBalance() public {
        mockToken.mint(address(acrossApproveAndBridge), 10e18);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);
    }

    function test_approveAndBridge_revertsOnFailedDeposit() public {
        AcrossApproveAndBridge failing = new AcrossApproveAndBridge(address(failingBridge));
        mockToken.mint(address(failing), 100e18);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");

        vm.expectRevert(AcrossApproveAndBridge.BridgeFailed.selector);
        failing.approveAndBridge(IERC20(mockToken), 50e18, 0, data);
    }

    function test_approveAndBridge_revertsOnZeroOriginalInput() public {
        mockToken.mint(address(acrossApproveAndBridge), 100e18);

        bytes memory data = _buildDepositCalldata(address(mockToken), 0, 99e18, "");

        vm.expectRevert(AcrossApproveAndBridge.InvalidInput.selector);
        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);
    }

    function test_approveAndBridge_revertsOnTooShortCalldata() public {
        mockToken.mint(address(acrossApproveAndBridge), 100e18);

        bytes memory data = hex"7b939232"; // selector only

        vm.expectRevert(AcrossApproveAndBridge.InvalidInput.selector);
        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);
    }

    function test_approveAndBridge_revertsOnWrongSelector() public {
        mockToken.mint(address(acrossApproveAndBridge), 100e18);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, "");
        // Corrupt the selector
        data[0] = 0xff;

        vm.expectRevert(AcrossApproveAndBridge.InvalidInput.selector);
        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);
    }

    /*//////////////////////////////////////////////////////////////
                              MESSAGES
    //////////////////////////////////////////////////////////////*/
    function test_approveAndBridge_passesMessageThrough() public {
        mockToken.mint(address(acrossApproveAndBridge), 100e18);

        bytes memory data = _buildDepositCalldata(address(mockToken), 100e18, 99e18, hex"deadbeefcafebabe");

        acrossApproveAndBridge.approveAndBridge(IERC20(mockToken), 50e18, 0, data);

        assertEq(spokePool.lastMessage(), hex"deadbeefcafebabe");
    }
}
