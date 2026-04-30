// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ApproveAndBridge, IERC20} from "./mixin/ApproveAndBridge.sol";
import {IAcrossSpokePoolV3} from "./interface/IAcrossSpokePoolV3.sol";
import {Math} from "./vendored/Math.sol";

/// ! @dev UNAUDITED UNTESTED Do not use in production
/// @dev Approves and deposits funds into an Across V3 SpokePool by calling
///      `depositV3` with the provided calldata, after patching `inputAmount`
///      and scaling `outputAmount` to the actual contract balance. This
///      ensures any surplus from the upstream swap is honored by relayers.
/// @dev `depositV3` has all static arguments before the trailing dynamic
///      `message`, so `inputAmount` and `outputAmount` always live at fixed
///      byte offsets within the calldata.
contract AcrossApproveAndBridge is ApproveAndBridge {
    error InvalidInput();
    error BridgeFailed();

    /// @dev `depositV3` selector length
    uint8 private constant SELECTOR_LENGTH = 4;
    /// @dev Byte offset (within calldata) of `inputAmount` — selector + 4 head slots
    uint16 private constant INPUT_AMOUNT_OFFSET = SELECTOR_LENGTH + 4 * 32;
    /// @dev Byte offset (within calldata) of `outputAmount` — selector + 5 head slots
    uint16 private constant OUTPUT_AMOUNT_OFFSET = SELECTOR_LENGTH + 5 * 32;
    /// @dev Minimum data length: selector + 11 static head slots + 1 offset slot for `message`
    uint16 private constant MIN_DATA_LENGTH = SELECTOR_LENGTH + 12 * 32;

    /// @dev Across V3 SpokePool address
    address public immutable SPOKE_POOL;

    constructor(address spokePool_) {
        require(spokePool_.code.length > 0, "Spoke pool contract not deployed");

        SPOKE_POOL = spokePool_;
    }

    /**
     * @notice Approval should be given to the SpokePool address
     * @dev Returns the SpokePool address
     */
    function bridgeApprovalTarget() public view override returns (address) {
        return SPOKE_POOL;
    }

    /**
     * @notice Deposit into the Across V3 SpokePool.
     * @dev Patches the `inputAmount` and `outputAmount` fields in the encoded
     *      `depositV3` calldata, then forwards the call to the SpokePool.
     * @param token The token to bridge. Use `NATIVE_TOKEN_ADDRESS` to bridge the native asset.
     * @param amount The actual amount of `token` held by this contract.
     * @param nativeTokenExtraFee Extra value forwarded with the call on top of the bridged amount.
     * @param data Encoded `depositV3` calldata. Must select `depositV3(address,address,address,address,uint256,uint256,uint256,address,uint32,uint32,uint32,bytes)`.
     */
    function bridge(IERC20 token, uint256 amount, uint256 nativeTokenExtraFee, bytes calldata data) internal override {
        bytes memory modifiedCalldata = _patchAmounts(amount, data);

        uint256 callValue = address(token) == NATIVE_TOKEN_ADDRESS ? amount + nativeTokenExtraFee : nativeTokenExtraFee;

        (bool success,) = SPOKE_POOL.call{value: callValue}(modifiedCalldata);
        if (!success) revert BridgeFailed();
    }

    /**
     * @dev Reads the original `inputAmount` and `outputAmount` from the
     *      depositV3 calldata, replaces `inputAmount` with `amount`, and
     *      scales `outputAmount` proportionally.
     */
    function _patchAmounts(uint256 amount, bytes calldata data) internal pure returns (bytes memory) {
        if (data.length < MIN_DATA_LENGTH) revert InvalidInput();
        if (bytes4(data[:SELECTOR_LENGTH]) != IAcrossSpokePoolV3.depositV3.selector) revert InvalidInput();

        bytes memory modified = data;

        uint256 originalInput = _readUint256(modified, INPUT_AMOUNT_OFFSET);
        if (originalInput == 0) revert InvalidInput();

        uint256 originalOutput = _readUint256(modified, OUTPUT_AMOUNT_OFFSET);
        uint256 newOutput = Math.mulDiv({x: originalOutput, y: amount, denominator: originalInput});

        _writeUint256(modified, INPUT_AMOUNT_OFFSET, amount);
        _writeUint256(modified, OUTPUT_AMOUNT_OFFSET, newOutput);

        return modified;
    }

    /// @dev Reads a uint256 at a given byte index in a bytes array
    function _readUint256(bytes memory _data, uint256 _index) internal pure returns (uint256 value) {
        assembly {
            value := mload(add(add(_data, 0x20), _index))
        }
    }

    /// @dev Writes a uint256 at a given byte index in a bytes array, in place.
    function _writeUint256(bytes memory _data, uint256 _index, uint256 _amount) internal pure {
        assembly {
            mstore(add(add(_data, 0x20), _index), _amount)
        }
    }
}
