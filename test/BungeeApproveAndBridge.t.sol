// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "../src/vendored/IERC20.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFailingBridge} from "./mocks/MockBridge.sol";

import {BungeeApproveAndBridge, ApproveAndBridge} from "src/BungeeApproveAndBridge.sol";

contract PublicBungeeApproveAndBridge is BungeeApproveAndBridge {
    constructor(address _socketGateway) BungeeApproveAndBridge(_socketGateway) {}

    function applyPctDiff(uint256 _base, uint256 _compare, uint256 _target) public view returns (uint256) {
        return super._applyPctDiff(_base, _compare, _target);
    }

    function replaceUint256(bytes memory _original, uint256 _start, uint256 _amount)
        public
        pure
        returns (bytes memory original, bytes memory modified)
    {
        return (_original, super._replaceUint256(_original, _start, _amount));
    }

    function readUint256(bytes memory _data, uint256 _index) public pure returns (uint256) {
        return super._readUint256(_data, _index);
    }

    function parseCalldata(bytes calldata _data)
        public
        pure
        returns (bytes memory, BungeeApproveAndBridge.ModifyCalldataParams memory)
    {
        return super._parseCalldata(_data);
    }

    function parseAndModifyCalldata(uint256 amount, bytes calldata data) public pure returns (bytes memory) {
        return super._parseAndModifyCalldata(amount, data);
    }
}

contract BungeeApproveAndBridgeTest is Test {
    PublicBungeeApproveAndBridge public bungeeApproveAndBridge;

    MockERC20 public mockToken;
    MockFailingBridge public failingBridge;

    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant SOCKET_GATEWAY = 0x3a23F943181408EAC424116Af7b7790c94Cb97a5;

    function setUp() public {
        // bypass the code size check
        vm.etch(SOCKET_GATEWAY, bytes("Hello, World!"));

        bungeeApproveAndBridge = new PublicBungeeApproveAndBridge(SOCKET_GATEWAY);
        mockToken = new MockERC20(1000e18);
        failingBridge = new MockFailingBridge();
    }

    function test_constructor() public {
        assertEq(bungeeApproveAndBridge.SOCKET_GATEWAY(), SOCKET_GATEWAY);
    }

    function test_constructor_shouldRevert_nonContractAddress() public {
        // Should revert when passing non-contract address
        address nonContract = address(0x123);
        vm.expectRevert("Socket gateway contract not deployed");
        new PublicBungeeApproveAndBridge(nonContract);

        // Should revert when passing address with no code
        address emptyContract = address(0x456);
        vm.etch(emptyContract, ""); // Empty code
        vm.expectRevert("Socket gateway contract not deployed");
        new PublicBungeeApproveAndBridge(emptyContract);
    }

    function test_bridgeApprovalTarget() public {
        assertEq(bungeeApproveAndBridge.bridgeApprovalTarget(), SOCKET_GATEWAY);
    }

    /*//////////////////////////////////////////////////////////////
                            _applyPctDiff()
    //////////////////////////////////////////////////////////////*/
    function test_applyPctDiff_basic() public {
        // Basic percentage calculations
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 110, _target: 100}), 110);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 90, _target: 100}), 90);

        // 20 + 10% = 22
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 110, _target: 20}), 22);
        // 20 - 10% = 18
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 90, _target: 20}), 18);
    }

    function test_applyPctDiff_equal() public {
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 100, _target: 100}), 100);
    }

    function test_applyPctDiff_shouldRevert_InvalidInput_zeroBase() public {
        // When _base is 0, should revert (handled by InvalidInput error)
        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.applyPctDiff({_base: 0, _compare: 100, _target: 100});
    }

    function test_applyPctDiff_zeroValues() public {
        // Edge cases with zero values
        // When _target is 0, result should be 0 regardless of other values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 200, _target: 0}), 0);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1000, _compare: 500, _target: 0}), 0);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1, _target: 0}), 0);

        // When _compare is 0, result should be 0
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 0, _target: 100}), 0);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1000, _compare: 0, _target: 500}), 0);
    }

    function test_applyPctDiff_largeNumbers() public {
        uint256 maxUint = type(uint256).max;

        // Test with various _target values beyond 100
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 150, _target: 1000}), 1500); // 1000 + 50% = 1500
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 50, _target: 1000}), 500); // 1000 - 50% = 500
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1000, _compare: 2000, _target: 100}), 200); // 100 + 100% = 200

        // Large numbers and precision testing
        // Test with large values
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: 100000e18, _compare: 200000e18, _target: 100000e18}), 200000e18
        );
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: 200000e18, _compare: 100000e18, _target: 200000e18}), 100000e18
        );

        // Test with very large _target values
        // maxUint - 1, and not maxUint since there will be integer match truncation
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 200, _target: maxUint / 2}), maxUint - 1);
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: 50, _target: maxUint / 2}), ((maxUint / 2) / 2)
        );
    }

    function test_applyPctDiff_smallNumbers() public {
        // Test with very small values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1, _target: 1}), 1);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 2, _target: 1}), 2);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 2, _compare: 1, _target: 2}), 1);
    }

    function test_applyPctDiff_maxUint256() public {
        // Test with maximum uint256 values
        uint256 maxUint = type(uint256).max;
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: maxUint, _compare: maxUint, _target: 100}), 100);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: maxUint, _compare: maxUint, _target: maxUint}), maxUint);
        // Test 1: When _target is maxUint and we scale it down
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: maxUint, _compare: maxUint / 2, _target: maxUint}), maxUint / 2
        );
        // Test 2: When _target is maxUint and we scale it up (should overflow/revert or handle gracefully)
        // This tests if the function can handle cases where result would exceed maxUint
        vm.expectRevert(); // or handle gracefully depending on implementation
        bungeeApproveAndBridge.applyPctDiff({_base: maxUint / 2, _compare: maxUint, _target: maxUint});
        // Test 3: Test with maxUint as _compare but different _base and _target
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: maxUint, _target: 100}), maxUint);
        // Test 4: Test with maxUint as _base but different _compare and _target
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: maxUint, _compare: 100, _target: maxUint}), 100);

        uint256 nearMax = maxUint - 1000;
        // Test 1: Test with different ratios using nearMax values
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: nearMax, _compare: nearMax / 2, _target: nearMax}), nearMax / 2
        );
        // Test 2: Test scaling up with nearMax (should cause overflow)
        vm.expectRevert(); // Should revert when result would exceed maxUint
        bungeeApproveAndBridge.applyPctDiff({_base: nearMax / 2, _compare: nearMax, _target: nearMax});
        // Test 3: Test with nearMax and small values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: nearMax, _compare: 100, _target: nearMax}), 100);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 100, _compare: nearMax, _target: 100}), nearMax);
        // Test 4: Test with nearMax and values that might cause precision loss
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: nearMax, _compare: nearMax - 1, _target: nearMax}), nearMax - 1
        );
        // Test 5: Test with nearMax and values that might cause intermediate overflow
        vm.expectRevert(); // Should revert when _target * _compare > uint256.max
        bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: nearMax, _target: 2});
        // Test 6: Test with values just below the overflow threshold
        uint256 safeValue = 2 ** 255 - 1; // Just below overflow threshold
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 2, _target: safeValue}), safeValue * 2);
        // Test 7: Test with nearMax and values that test rounding behavior
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: nearMax, _compare: nearMax / 3, _target: nearMax}), nearMax / 3
        );
        // Test 8: Test with values that are very close to maxUint
        uint256 veryNearMax = maxUint - 1;
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: veryNearMax, _compare: veryNearMax, _target: 100}), 100);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: veryNearMax, _compare: 1, _target: veryNearMax}), 1);
    }

    function test_applyPctDiff_rounding() public {
        // Rounding behavior tests
        // Test cases where division might result in rounding
        // 100 * 3 / 7 = 42.857... should round down to 42
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 7, _compare: 3, _target: 100}), 42);
        // 100 * 5 / 3 = 166.666... should round down to 166
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 3, _compare: 5, _target: 100}), 166);
    }

    function test_applyPctDiff_specialNumbers() public {
        // Test with prime numbers and coprime values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 17, _compare: 19, _target: 17}), 19);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 19, _compare: 17, _target: 19}), 17);
        // Case 1: Different target values to test actual ratio calculations
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 17, _compare: 19, _target: 34}), 38); // 34 * 19/17 = 38
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 19, _compare: 17, _target: 38}), 34); // 38 * 17/19 = 34
        // Case 2: Test with prime numbers that don't divide evenly
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 17, _compare: 19, _target: 100}), 111); // 100 * 19/17 = 111.76... rounds to 111
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 19, _compare: 17, _target: 100}), 89); // 100 * 17/19 = 89.47... rounds to 89
        // Case 3: Test with larger prime numbers
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 23, _compare: 29, _target: 46}), 58); // 46 * 29/23 = 58
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 29, _compare: 23, _target: 58}), 46); // 58 * 23/29 = 46

        // Test with powers of 2
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 256, _compare: 512, _target: 256}), 512);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 512, _compare: 256, _target: 512}), 256);
    }

    function test_applyPctDiff_intermediateOverflow() public {
        // Test with values that might cause intermediate overflow
        // These should cause intermediate overflow in _target * _compare but final result is valid

        // Test 1: Intermediate overflow with large _target and _compare, but large _base
        // _target = 2^200, _compare = 2^56, _base = 2^200
        // Intermediate: 2^200 * 2^56 = 2^256 (overflows)
        // Final: 2^256 / 2^200 = 2^56 (valid)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 2 ** 200, _compare: 2 ** 56, _target: 2 ** 200}), 2 ** 56);

        // Test 2: Intermediate overflow with maxUint values
        // _target = maxUint, _compare = 2, _base = maxUint
        // Intermediate: maxUint * 2 (overflows)
        // Final: (maxUint * 2) / maxUint = 2 (valid)
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: type(uint256).max, _compare: 2, _target: type(uint256).max}), 2
        );

        // Test 3: Intermediate overflow with values close to overflow threshold
        // _target = 2^255, _compare = 2, _base = 2^255
        // Intermediate: 2^255 * 2 = 2^256 (overflows)
        // Final: 2^256 / 2^255 = 2 (valid)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 2 ** 255, _compare: 2, _target: 2 ** 255}), 2);

        // Test 4: Intermediate overflow with large values that would result in small final result
        // _target = 2^200, _compare = 2^100, _base = 2^250
        // Intermediate: 2^200 * 2^100 = 2^300 (overflows)
        // Final: 2^300 / 2^250 = 2^50 (valid)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 2 ** 250, _compare: 2 ** 100, _target: 2 ** 200}), 2 ** 50);

        // Test 5: Test values just below intermediate overflow threshold (should work)
        // _target = 2^255 - 1, _compare = 2, _base = 2^255 - 1
        // Intermediate: (2^255 - 1) * 2 = 2^256 - 2 (just below overflow)
        // Final: (2^256 - 2) / (2^255 - 1) ≈ 2 (valid)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 2 ** 255 - 1, _compare: 2, _target: 2 ** 255 - 1}), 2);

        // Test 6: Intermediate overflow with very large values
        // _target = maxUint, _compare = maxUint, _base = maxUint
        // Intermediate: maxUint * maxUint (massive overflow)
        // Final: (maxUint * maxUint) / maxUint = maxUint (valid)
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({
                _base: type(uint256).max,
                _compare: type(uint256).max,
                _target: type(uint256).max
            }),
            type(uint256).max
        );

        // Test 7: Cases where final result WOULD overflow (should revert)
        // _target = 2^255, _compare = 2^255, _base = 1
        // Final: 2^255 * 2^255 / 1 = 2^510 (overflows)
        vm.expectRevert(); // Should revert when final result > uint256.max
        bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 2 ** 255, _target: 2 ** 255});

        // Test 8: Cases where final result is exactly at the limit
        // _target = 2^255, _compare = 2^255, _base = 2^255
        // Final: 2^255 * 2^255 / 2^255 = 2^255 (valid)
        assertEq(
            bungeeApproveAndBridge.applyPctDiff({_base: 2 ** 255, _compare: 2 ** 255, _target: 2 ** 255}), 2 ** 255
        );
    }

    function test_applyPctDiff_underflow() public {
        uint256 maxUint = type(uint256).max;
        // Test with values that might cause underflow
        // These should not underflow due to Math.mulDiv's protection
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 0, _target: 1e18}), 0);
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: maxUint, _compare: 0, _target: maxUint}), 0);
    }

    function test_applyPctDiff_extremeRatios() public {
        // Test with very small ratios
        // Test 1: Very small ratio where _compare << _base
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 100}), 0); // 100 * 1/1e18 = 0 (rounds down)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e18}), 1); // 1e18 * 1/1e18 = 1
        // Test 2: Small ratio with different target values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e17, _target: 100}), 10); // 100 * 1e17/1e18 = 10
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e17, _target: 1e18}), 1e17); // 1e18 * 1e17/1e18 = 1e17
        // Test 3: Very small ratio with large target
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e20}), 100); // 1e20 * 1/1e18 = 100
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e16}), 0); // 1e16 * 1/1e18 = 0 (rounds down)
        // Test 4: Extremely small ratios
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e15}), 0); // 1e15 * 1/1e18 = 0.001 (rounds to 0)
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e17}), 0); // 1e17 * 1/1e18 = 0.1 (rounds to 0)
        // Test 5: Small ratio with precision testing
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e16, _target: 1e18}), 1e16); // 1e18 * 1e16/1e18 = 1e16
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e16, _target: 100}), 1); // 100 * 1e16/1e18 = 1
        // Test 6: Small ratio with values that test rounding behavior
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e17, _target: 1e17}), 1e16); // 1e17 * 1e17/1e18 = 1e16
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e17, _target: 1e16}), 1e15); // 1e16 * 1e17/1e18 = 1e15
        // Test with values that might cause precision loss
        // 1 * 1e18 / 1e18 = 1
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1e18, _target: 1}), 1);
        // 1e18 * 1 / 1e18 = 1
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e18, _compare: 1, _target: 1e18}), 1);

        // Test with very large ratios
        // Test 1: Very large ratio where _compare >> _base
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1e18, _target: 100}), 100e18); // 100 * 1e18/1 = 100e18
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1e18, _target: 1e18}), 1e36); // 1e18 * 1e18/1 = 1e36
        // Test 2: Large ratio with different target values
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e17, _compare: 1e18, _target: 100}), 1000); // 100 * 1e18/1e17 = 1000
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e17, _compare: 1e18, _target: 1e18}), 1e19); // 1e18 * 1e18/1e17 = 1e19
        // Test 3: Very large ratio with small target
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1e20, _target: 1}), 1e20); // 1 * 1e20/1 = 1e20
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1e20, _target: 100}), 100e20); // 100 * 1e20/1 = 100e20
        // Test 4: Large ratio
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 1e18, _target: 1e18}), 1e36); // 1e18 * 1e18/1 = 1e36
        // Test 5: Large ratio with values that test overflow thresholds
        vm.expectRevert(); // Should revert when _target * _compare > uint256.max
        bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 2 ** 255, _target: 2}); // 2 * 2^255/1 = 2^256 (overflows)
        // Test 6: Large ratio with values just below overflow threshold
        uint256 safeValue = 2 ** 255 - 1; // Just below overflow threshold
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1, _compare: 2, _target: safeValue}), safeValue * 2);
        // Test 7: Large ratio with precision testing
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e16, _compare: 1e18, _target: 1e16}), 1e18); // 1e16 * 1e18/1e16 = 1e18
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 1e16, _compare: 1e18, _target: 100}), 100e2); // 100 * 1e18/1e16 = 100e2
        // Test 8: Large ratio with values that test rounding behavior
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 3, _compare: 10, _target: 100}), 333); // 100 * 10/3 = 333.33... rounds to 333
        assertEq(bungeeApproveAndBridge.applyPctDiff({_base: 7, _compare: 22, _target: 100}), 314); // 100 * 22/7 = 314.28... rounds to 314
    }

    /*//////////////////////////////////////////////////////////////
                            _replaceUint256()
    //////////////////////////////////////////////////////////////*/
    function test_replaceUint256_emptyBytes() public {
        // Test with empty bytes - should revert with PositionOutOfBounds
        bytes memory emptyBytes = "";
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(emptyBytes, 0, 123);
    }

    function test_replaceUint256_exactly32Bytes() public {
        // Test with exactly 32 bytes
        bytes memory data = new bytes(32);
        // Fill with some initial data
        for (uint256 i = 0; i < 32; i++) {
            data[i] = bytes1(uint8(i));
        }

        uint256 newAmount = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        // Replace at start (offset 0)
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, newAmount);

        // Verify the replacement worked
        uint256 readValue = bungeeApproveAndBridge.readUint256(result, 0);
        assertEq(readValue, newAmount);

        // Test that trying to replace at offset 1 should revert (would exceed bounds)
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(data, 1, newAmount);
    }

    function test_replaceUint256_largerPayload() public {
        // Test with a larger payload (64 bytes)
        bytes memory data = new bytes(64);
        // Fill with some initial data
        for (uint256 i = 0; i < 64; i++) {
            data[i] = bytes1(uint8(i));
        }

        uint256 newAmount = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

        // Test replacement at start (offset 0)
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, newAmount);
        uint256 readValue = bungeeApproveAndBridge.readUint256(result, 0);
        assertEq(readValue, newAmount);

        // Test replacement at middle (offset 32)
        (, result) = bungeeApproveAndBridge.replaceUint256(data, 32, newAmount);
        readValue = bungeeApproveAndBridge.readUint256(result, 32);
        assertEq(readValue, newAmount);

        // Test that trying to replace at offset 33 should revert (would exceed bounds)
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(data, 33, newAmount);
    }

    function test_replaceUint256_veryLargePayload() public {
        // Test with a very large payload (128 bytes)
        bytes memory data = new bytes(128);
        // Fill with some initial data
        for (uint256 i = 0; i < 128; i++) {
            data[i] = bytes1(uint8(i));
        }

        uint256 newAmount = 0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;

        // Test replacement at start (offset 0)
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, newAmount);
        uint256 readValue = bungeeApproveAndBridge.readUint256(result, 0);
        assertEq(readValue, newAmount);

        // Test replacement at middle (offset 64)
        (, result) = bungeeApproveAndBridge.replaceUint256(data, 64, newAmount);
        readValue = bungeeApproveAndBridge.readUint256(result, 64);
        assertEq(readValue, newAmount);

        // Test replacement at end (offset 96)
        (, result) = bungeeApproveAndBridge.replaceUint256(data, 96, newAmount);
        readValue = bungeeApproveAndBridge.readUint256(result, 96);
        assertEq(readValue, newAmount);

        // Test that trying to replace at offset 97 should revert (would exceed bounds)
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(data, 97, newAmount);
    }

    function test_replaceUint256_multipleReplacements() public {
        // Test multiple replacements on the same data
        bytes memory data = new bytes(96); // 3 * 32 bytes
        // Fill with some initial data
        for (uint256 i = 0; i < 96; i++) {
            data[i] = bytes1(uint8(i));
        }

        uint256 amount1 = 0x1111111111111111111111111111111111111111111111111111111111111111;
        uint256 amount2 = 0x2222222222222222222222222222222222222222222222222222222222222222;
        uint256 amount3 = 0x3333333333333333333333333333333333333333333333333333333333333333;

        // Replace at offset 0
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, amount1);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), amount1);

        // Replace at offset 32
        (, result) = bungeeApproveAndBridge.replaceUint256(result, 32, amount2);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), amount1); // First value unchanged
        assertEq(bungeeApproveAndBridge.readUint256(result, 32), amount2); // Second value changed

        // Replace at offset 64
        (, result) = bungeeApproveAndBridge.replaceUint256(result, 64, amount3);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), amount1); // First value unchanged
        assertEq(bungeeApproveAndBridge.readUint256(result, 32), amount2); // Second value unchanged
        assertEq(bungeeApproveAndBridge.readUint256(result, 64), amount3); // Third value changed
    }

    function test_replaceUint256_edgeCases() public {
        // Test edge cases with different amounts
        bytes memory data = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            data[i] = bytes1(uint8(i));
        }

        // Test with zero amount
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, 0);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), 0);

        // Test with maximum uint256
        uint256 maxUint = type(uint256).max;
        (, result) = bungeeApproveAndBridge.replaceUint256(data, 32, maxUint);
        assertEq(bungeeApproveAndBridge.readUint256(result, 32), maxUint);

        // Test with a specific pattern
        uint256 pattern = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        (, result) = bungeeApproveAndBridge.replaceUint256(data, 0, pattern);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), pattern);
    }

    function test_replaceUint256_boundsChecking() public {
        // Test various bounds checking scenarios
        bytes memory data = new bytes(64);

        // Test with _start = 0 (valid)
        bungeeApproveAndBridge.replaceUint256(data, 0, 123);

        // Test with _start = 32 (valid)
        bungeeApproveAndBridge.replaceUint256(data, 32, 123);

        // Test with _start = 33 (invalid - would exceed bounds)
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(data, 33, 123);

        // Test with _start = 64 (invalid - would exceed bounds)
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.replaceUint256(data, 64, 123);

        // Test with very large _start value
        // will revert since start + 32 will overflow
        vm.expectRevert();
        bungeeApproveAndBridge.replaceUint256(data, type(uint256).max, 123);
    }

    function test_replaceUint256_memorySafety() public {
        // Test memory safety by ensuring the function doesn't corrupt memory
        bytes memory data = new bytes(96);

        // Fill with a specific pattern
        for (uint256 i = 0; i < 96; i++) {
            data[i] = bytes1(uint8(i % 256));
        }

        uint256 newAmount = 0xdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef;

        // Replace only the middle 32 bytes
        (, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 32, newAmount);

        // Verify that only the target location was modified
        assertEq(bungeeApproveAndBridge.readUint256(result, 32), newAmount);

        // Verify that other locations remain unchanged
        // Check first 32 bytes are unchanged
        for (uint256 i = 0; i < 32; i++) {
            assertEq(result[i], data[i]);
        }

        // Check last 32 bytes are unchanged
        for (uint256 i = 64; i < 96; i++) {
            assertEq(result[i], data[i]);
        }
    }

    function test_replaceUint256_inPlaceModification() public {
        // Test that the function modifies the original data in-place
        bytes memory data = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            data[i] = bytes1(uint8(i));
        }

        uint256 originalValue = bungeeApproveAndBridge.readUint256(data, 0);
        uint256 newAmount = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

        // Replace the value
        (bytes memory original, bytes memory result) = bungeeApproveAndBridge.replaceUint256(data, 0, newAmount);

        // Verify the result is the same as the original data (in-place modification)
        assertEq(result.length, data.length);
        assertEq(bungeeApproveAndBridge.readUint256(result, 0), newAmount);
        // this will not modify the original data variable, but a copy of it since data is outside the scope of the function
        assertNotEq(bungeeApproveAndBridge.readUint256(result, 0), bungeeApproveAndBridge.readUint256(data, 0));
        // but this is returning the modified input value, so this should be the new value
        assertEq(bungeeApproveAndBridge.readUint256(original, 0), newAmount);
    }

    /*//////////////////////////////////////////////////////////////
                             _parseCalldata()
    //////////////////////////////////////////////////////////////*/
    function test_parseCalldata_minimumLength() public {
        // Test with minimum valid length (4 bytes routeId + 96 bytes BungeeApproveAndBridge.ModifyCalldataParams = 100 bytes)
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 32;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 64;

        bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        // Verify route calldata is correct
        assertEq(routeCalldata.length, 4);
        assertEq(routeCalldata, routeId);

        // Verify BungeeApproveAndBridge.ModifyCalldataParams are correct
        assertEq(params.inputAmountIdx, inputAmountIdx);
        assertEq(params.modifyOutput, modifyOutput);
        assertEq(params.outputAmountIdx, outputAmountIdx);
    }

    function test_parseCalldata_largerRouteCalldata() public {
        // Test with larger route calldata
        bytes memory routeId = hex"12345678";
        bytes memory additionalData = hex"deadbeefdeadbeefdeadbeefdeadbeef";
        uint256 inputAmountIdx = 32;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;

        bytes memory routeCalldata = abi.encodePacked(routeId, additionalData);
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory parsedRouteCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        // Verify route calldata is correct
        assertEq(parsedRouteCalldata.length, 20); // routeId(4) + additionalData(16)
        assertEq(parsedRouteCalldata, routeCalldata);

        // Verify BungeeApproveAndBridge.ModifyCalldataParams are correct
        assertEq(params.inputAmountIdx, inputAmountIdx);
        assertEq(params.modifyOutput, modifyOutput);
        assertEq(params.outputAmountIdx, outputAmountIdx);
    }

    function test_parseCalldata_complexRouteCalldata() public {
        // Test with complex route calldata containing multiple parameters
        bytes memory routeId = hex"12345678";
        bytes memory param1 = hex"1111111111111111111111111111111111111111111111111111111111111111";
        bytes memory param2 = hex"2222222222222222222222222222222222222222222222222222222222222222";
        bytes memory param3 = hex"3333333333333333333333333333333333333333333333333333333333333333";

        uint256 inputAmountIdx = 68; // After routeId (4) + param1 (32) + param2 (32)
        bool modifyOutput = true;
        uint256 outputAmountIdx = 100; // After routeId (4) + param1 (32) + param2 (32) + param3 (32)

        bytes memory routeCalldata = abi.encodePacked(routeId, param1, param2, param3);
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory parsedRouteCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        // Verify route calldata is correct
        assertEq(parsedRouteCalldata.length, 100); // 4 + 32 + 32 + 32
        assertEq(parsedRouteCalldata, routeCalldata);

        // Verify BungeeApproveAndBridge.ModifyCalldataParams are correct
        assertEq(params.inputAmountIdx, inputAmountIdx);
        assertEq(params.modifyOutput, modifyOutput);
        assertEq(params.outputAmountIdx, outputAmountIdx);
    }

    function test_parseCalldata_edgeCaseValues() public {
        // Test with edge case values for BungeeApproveAndBridge.ModifyCalldataParams
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 0;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;

        bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        assertEq(routeCalldata, routeId);
        assertEq(params.inputAmountIdx, 0);
        assertEq(params.modifyOutput, false);
        assertEq(params.outputAmountIdx, 0);
    }

    function test_parseCalldata_maxValues() public {
        // Test with maximum uint256 values
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = type(uint256).max;
        bool modifyOutput = true;
        uint256 outputAmountIdx = type(uint256).max;

        bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        assertEq(routeCalldata, routeId);
        assertEq(params.inputAmountIdx, type(uint256).max);
        assertEq(params.modifyOutput, true);
        assertEq(params.outputAmountIdx, type(uint256).max);
    }

    function test_parseCalldata_shouldRevert_InvalidInput_tooShort() public {
        // Test with data shorter than minimum length (100 bytes)
        bytes memory shortData = hex"12345678"; // Only 4 bytes, should revert

        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.parseCalldata(shortData);
    }

    function test_parseCalldata_shouldRevert_InvalidInput_emptyData() public {
        // Test with empty data
        bytes memory emptyData = "";

        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.parseCalldata(emptyData);
    }

    function test_parseCalldata_shouldRevert_InvalidInput_exactlyOneByteShort() public {
        // Test with data exactly one byte shorter than minimum
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 32;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 64;

        // Create data that's 99 bytes (1 byte short of minimum 100)
        bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        bytes memory shortData = new bytes(data.length - 1);
        for (uint256 i = 0; i < shortData.length; i++) {
            shortData[i] = data[i];
        }

        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.parseCalldata(shortData);
    }

    function test_parseCalldata_veryLargeRouteCalldata() public {
        // Test with very large route calldata
        bytes memory routeId = hex"12345678";
        bytes memory largeData = new bytes(1000);
        for (uint256 i = 0; i < 1000; i++) {
            largeData[i] = bytes1(uint8(i % 256));
        }

        uint256 inputAmountIdx = 32;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 64;

        bytes memory routeCalldata = abi.encodePacked(routeId, largeData);
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        (bytes memory parsedRouteCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        // Verify route calldata is correct
        assertEq(parsedRouteCalldata.length, 1004); // 4 + 1000
        assertEq(parsedRouteCalldata, routeCalldata);

        // Verify BungeeApproveAndBridge.ModifyCalldataParams are correct
        assertEq(params.inputAmountIdx, inputAmountIdx);
        assertEq(params.modifyOutput, modifyOutput);
        assertEq(params.outputAmountIdx, outputAmountIdx);
    }

    function test_parseCalldata_multipleTestCases() public {
        // Test multiple different scenarios
        bytes memory routeId = hex"12345678";

        // Test case 1: Basic case
        {
            uint256 inputAmountIdx = 32;
            bool modifyOutput = true;
            uint256 outputAmountIdx = 64;

            bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
            (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
                bungeeApproveAndBridge.parseCalldata(data);

            assertEq(routeCalldata, routeId);
            assertEq(params.inputAmountIdx, inputAmountIdx);
            assertEq(params.modifyOutput, modifyOutput);
            assertEq(params.outputAmountIdx, outputAmountIdx);
        }

        // Test case 2: Different values
        {
            uint256 inputAmountIdx = 100;
            bool modifyOutput = false;
            uint256 outputAmountIdx = 200;

            bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
            (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
                bungeeApproveAndBridge.parseCalldata(data);

            assertEq(routeCalldata, routeId);
            assertEq(params.inputAmountIdx, inputAmountIdx);
            assertEq(params.modifyOutput, modifyOutput);
            assertEq(params.outputAmountIdx, outputAmountIdx);
        }

        // Test case 3: Large indices
        {
            uint256 inputAmountIdx = 1000000;
            bool modifyOutput = true;
            uint256 outputAmountIdx = 2000000;

            bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
            (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
                bungeeApproveAndBridge.parseCalldata(data);

            assertEq(routeCalldata, routeId);
            assertEq(params.inputAmountIdx, inputAmountIdx);
            assertEq(params.modifyOutput, modifyOutput);
            assertEq(params.outputAmountIdx, outputAmountIdx);
        }
    }

    function test_parseCalldata_abiEncodingConsistency() public {
        // Test that the ABI encoding/decoding is consistent
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 32;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 64;

        // Create data using ABI encoding
        bytes memory data = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Parse the data
        (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(data);

        // Re-encode the params and verify they match
        bytes memory reEncodedParams = abi.encode(params.inputAmountIdx, params.modifyOutput, params.outputAmountIdx);
        bytes memory originalParams = abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx);

        assertEq(reEncodedParams, originalParams);
        assertEq(routeCalldata, routeId);
    }

    function test_parseCalldata_boundaryConditions() public {
        // Test boundary conditions around the minimum length
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 32;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 64;

        // Test exactly at minimum length (should work)
        bytes memory minData = abi.encodePacked(routeId, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        (bytes memory routeCalldata, BungeeApproveAndBridge.ModifyCalldataParams memory params) =
            bungeeApproveAndBridge.parseCalldata(minData);

        assertEq(routeCalldata, routeId);
        assertEq(params.inputAmountIdx, inputAmountIdx);
        assertEq(params.modifyOutput, modifyOutput);
        assertEq(params.outputAmountIdx, outputAmountIdx);

        // Test one byte less than minimum (should revert)
        bytes memory shortData = new bytes(minData.length - 1);
        for (uint256 i = 0; i < shortData.length; i++) {
            shortData[i] = minData[i];
        }

        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.parseCalldata(shortData);
    }

    /*//////////////////////////////////////////////////////////////
                        _parseAndModifyCalldata()
    //////////////////////////////////////////////////////////////*/
    function test_parseAndModifyCalldata_onlyInput() public {
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(100));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        bytes memory modified = bungeeApproveAndBridge.parseAndModifyCalldata(200, data);
        uint256 newInput = bungeeApproveAndBridge.readUint256(modified, inputAmountIdx);
        assertEq(newInput, 200);
        for (uint256 i = 0; i < 4; i++) {
            assertEq(modified[i], routeId[i]);
        }
    }

    function test_parseAndModifyCalldata_inputAndOutput() public {
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = true;
        uint256 outputAmountIdx = 36;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(100), uint256(50));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        bytes memory modified = bungeeApproveAndBridge.parseAndModifyCalldata(200, data);
        uint256 newInput = bungeeApproveAndBridge.readUint256(modified, inputAmountIdx);
        assertEq(newInput, 200);
        uint256 newOutput = bungeeApproveAndBridge.readUint256(modified, outputAmountIdx);
        assertEq(newOutput, 100);
    }

    function test_parseAndModifyCalldata_outOfBounds() public {
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 1000;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(100));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        vm.expectRevert(BungeeApproveAndBridge.PositionOutOfBounds.selector);
        bungeeApproveAndBridge.parseAndModifyCalldata(200, data);
    }

    function test_parseAndModifyCalldata_modifyOutputFalse() public {
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 36;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(100), uint256(50));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));
        bytes memory modified = bungeeApproveAndBridge.parseAndModifyCalldata(200, data);
        uint256 output = bungeeApproveAndBridge.readUint256(modified, outputAmountIdx);
        assertEq(output, 50);
    }

    function test_parseAndModifyCalldata_minimumLength() public {
        bytes memory data = hex"12345678";
        vm.expectRevert(BungeeApproveAndBridge.InvalidInput.selector);
        bungeeApproveAndBridge.parseAndModifyCalldata(100, data);
    }

    /*//////////////////////////////////////////////////////////////
                        INSUFFICIENT BALANCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_insufficientBalance_ERC20() public {
        // Give test contract some tokens but not enough
        mockToken.mint(address(bungeeApproveAndBridge), 100e18);

        uint256 minAmount = 200e18; // More than available balance

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, 0, hex"");
    }

    function test_insufficientBalance_nativeToken() public {
        // Give test contract some ETH but not enough
        vm.deal(address(bungeeApproveAndBridge), 1e18);

        uint256 minAmount = 2e18; // More than available balance

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, 0, hex"");
    }

    function test_insufficientBalance_withExtraFee() public {
        // Give test contract exactly the min amount but with extra fee
        uint256 minAmount = 1e18;
        uint256 nativeTokenExtraFee = 0.1e18;
        vm.deal(address(bungeeApproveAndBridge), minAmount + nativeTokenExtraFee - 0.01e18); // Slightly less than needed

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, hex"");
    }

    function test_zeroBalance_ERC20() public {
        // Test contract has no tokens
        uint256 minAmount = 1e18;
        bytes memory routeId = hex"12345678";

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, 0, hex"");
    }

    function test_zeroBalance_nativeToken() public {
        // Test contract has no ETH
        uint256 minAmount = 1e18;

        vm.expectRevert(ApproveAndBridge.MinAmountNotMet.selector);
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, 0, hex"");
    }

    /*//////////////////////////////////////////////////////////////
                        FAILED BRIDGE CALL TESTS
    //////////////////////////////////////////////////////////////*/

    function test_failedBridgeCall_ERC20() public {
        // Create a new bridge contract with failing gateway
        PublicBungeeApproveAndBridge failingBridgeApproveAndBridgeContract =
            new PublicBungeeApproveAndBridge(address(failingBridge));

        // Give test contract enough tokens
        mockToken.mint(address(failingBridgeApproveAndBridgeContract), 100e18);

        uint256 minAmount = 50e18;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(50e18));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        vm.expectRevert(BungeeApproveAndBridge.BridgeFailed.selector);
        failingBridgeApproveAndBridgeContract.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);
    }

    function test_failedBridgeCall_nativeToken() public {
        // Create a new bridge contract with failing gateway
        PublicBungeeApproveAndBridge failingBridgeApproveAndBridgeContract =
            new PublicBungeeApproveAndBridge(address(failingBridge));

        // Give test contract enough ETH
        vm.deal(address(failingBridgeApproveAndBridgeContract), 2e18);

        uint256 minAmount = 1e18;
        uint256 nativeTokenExtraFee = 0.1e18;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(1e18));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        vm.expectRevert(BungeeApproveAndBridge.BridgeFailed.selector);
        failingBridgeApproveAndBridgeContract.approveAndBridge(
            IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data
        );
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES - ZERO AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function test_zeroMinAmount_ERC20() public {
        // Give test contract some tokens
        mockToken.mint(address(bungeeApproveAndBridge), 100e18);

        uint256 minAmount = 0; // Zero minimum amount
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(50e18));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with zero min amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);

        // Should succeed with zero min amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data);
    }

    function test_zeroBalance_zeroMinAmount() public {
        // Test contract has no tokens but zero min amount
        uint256 minAmount = 0;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(0));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Will succeed with zero min amount and zero balance
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES - EXACT MINIMUM AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function test_exactMinimumAmount_ERC20() public {
        // Give test contract exactly the minimum amount
        uint256 minAmount = 50e18;
        mockToken.mint(address(bungeeApproveAndBridge), minAmount);

        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(minAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with exact minimum amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);
    }

    function test_exactMinimumAmount_nativeToken() public {
        // Give test contract exactly the minimum amount plus extra fee
        uint256 minAmount = 1e18;
        uint256 nativeTokenExtraFee = 0.1e18;
        vm.deal(address(bungeeApproveAndBridge), minAmount + nativeTokenExtraFee);

        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(minAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with exact minimum amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data);
    }

    function test_exactMinimumAmount_withExtraFee() public {
        // Give test contract exactly the minimum amount plus extra fee
        uint256 minAmount = 1e18;
        uint256 nativeTokenExtraFee = 0.1e18;
        vm.deal(address(bungeeApproveAndBridge), minAmount + nativeTokenExtraFee);

        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(minAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with exact minimum amount plus extra fee
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES - LARGE AMOUNTS
    //////////////////////////////////////////////////////////////*/

    function test_largeAmount_ERC20() public {
        // Test with very large amounts
        uint256 largeAmount = type(uint256).max / 2;
        mockToken.mint(address(bungeeApproveAndBridge), largeAmount);

        uint256 minAmount = largeAmount;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(largeAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with large amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);
    }

    function test_largeAmount_nativeToken() public {
        // Test with very large amounts (but not max to avoid overflow)
        uint256 largeAmount = 1e20; // 100 ETH
        vm.deal(address(bungeeApproveAndBridge), largeAmount);

        uint256 minAmount = largeAmount;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(largeAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with large amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES - MAXIMUM VALUES
    //////////////////////////////////////////////////////////////*/

    function test_maxUint256_minAmount() public {
        // Test with maximum uint256 as min amount
        MockERC20 newToken = new MockERC20(0);
        uint256 maxAmount = type(uint256).max;
        newToken.mint(address(bungeeApproveAndBridge), maxAmount);

        uint256 minAmount = maxAmount;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(maxAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with maximum amount
        bungeeApproveAndBridge.approveAndBridge(IERC20(newToken), minAmount, nativeTokenExtraFee, data);
    }

    function test_maxUint256_extraFee() public {
        // Test with maximum uint256 as extra fee
        uint256 minAmount = 1e18;
        uint256 nativeTokenExtraFee = type(uint256).max - 1e18;
        vm.deal(address(bungeeApproveAndBridge), minAmount + nativeTokenExtraFee);

        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(minAmount));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed with maximum extra fee
        bungeeApproveAndBridge.approveAndBridge(IERC20(NATIVE_TOKEN_ADDRESS), minAmount, nativeTokenExtraFee, data);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES - APPROVAL BEHAVIOR
    //////////////////////////////////////////////////////////////*/

    function test_approval_calledForERC20() public {
        // Give test contract tokens
        mockToken.mint(address(bungeeApproveAndBridge), 100e18);

        uint256 minAmount = 50e18;
        uint256 nativeTokenExtraFee = 0;
        bytes memory routeId = hex"12345678";
        uint256 inputAmountIdx = 4;
        bool modifyOutput = false;
        uint256 outputAmountIdx = 0;
        bytes memory routeCalldata = abi.encodePacked(routeId, uint256(50e18));
        bytes memory data = abi.encodePacked(routeCalldata, abi.encode(inputAmountIdx, modifyOutput, outputAmountIdx));

        // Should succeed and call approval for ERC20 token
        vm.expectCall(address(mockToken), abi.encodeCall(IERC20.approve, (address(SOCKET_GATEWAY), 100e18)));
        bungeeApproveAndBridge.approveAndBridge(IERC20(mockToken), minAmount, nativeTokenExtraFee, data);
    }
}
