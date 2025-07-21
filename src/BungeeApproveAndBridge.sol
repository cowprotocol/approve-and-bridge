// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ApproveAndBridge, IERC20} from "./mixin/ApproveAndBridge.sol";
import {Math} from "./vendored/Math.sol";

/// ! @dev UNAUDITED UNTESTED Do not use in production
/// @dev Performs two steps before bridging:
/// 1. Modify input amount in calldata
/// 2. Modify output amount in calldata
contract BungeeApproveAndBridge is ApproveAndBridge {
    error InvalidInput();
    error PositionOutOfBounds();
    error BridgeFailed();

    /// @dev ModifyCalldataParams is a struct that contains information required to modify SocketGateway calldata
    /// @dev the input amount index, modify output flag, and output amount index
    struct ModifyCalldataParams {
        uint256 inputAmountIdx;
        bool modifyOutput;
        uint256 outputAmountIdx;
    }

    /// @dev routeIds on SocketGateway are 4 bytes
    uint8 private constant ROUTE_ID_BYTES_LENGTH = 4;
    /// @dev there are 3 params in ModifyCalldataParams
    uint8 private constant MODIFY_CALLDATA_PARAMS_COUNT = 3;
    /// @dev each ModifyCalldataParams is 32 bytes
    uint8 private constant MODIFY_CALLDATA_LENGTH_BYTES = 32;
    /// @dev total length of the modify calldata bytes
    uint8 private constant MODIFY_CALLDATA_LENGTH = MODIFY_CALLDATA_PARAMS_COUNT * MODIFY_CALLDATA_LENGTH_BYTES;
    /// @dev minimum length of the data payload
    /// @dev should atleast include the routeId and the ModifyCalldataParams
    uint8 private constant MIN_DATA_LENGTH = ROUTE_ID_BYTES_LENGTH + MODIFY_CALLDATA_LENGTH;

    /// @dev SocketGateway address
    address public immutable SOCKET_GATEWAY;

    constructor(address socketGateway_) {
        SOCKET_GATEWAY = socketGateway_;
    }

    /**
     * @notice Approval should be given to the SocketGateway address
     * @dev Returns the SocketGateway address
     */
    function bridgeApprovalTarget() public view override returns (address) {
        return address(SOCKET_GATEWAY);
    }

    /**
     * @notice Bridge the token via SocketGateway
     * @dev Modifies SocketGateway calldata to modify the input and output amounts before bridging
     * @param token The token to bridge
     * @param amount The amount of token to bridge
     * @param nativeTokenExtraFee extra fee in native token, if any
     * @param data encoded bytes including SocketGateway calldata and ModifyCalldataParams
     */
    function bridge(IERC20 token, uint256 amount, uint256 nativeTokenExtraFee, bytes calldata data) internal override {
        // decode & parse data to find positions in calldata to modify
        bytes memory modifiedCalldata = _parseAndModifyCalldata(amount, data);

        // execute using the modified calldata via SocketGateway.fallback()
        (bool success,) = address(token) == NATIVE_TOKEN_ADDRESS
            ? address(SOCKET_GATEWAY).call{value: amount + nativeTokenExtraFee}(modifiedCalldata)
            : address(SOCKET_GATEWAY).call{value: nativeTokenExtraFee}(modifiedCalldata);
        if (!success) revert BridgeFailed();
    }

    /**
     * @dev Parses and modifies the calldata to modify the input and output amounts before bridging
     * @param amount Updated input amount to use to modify the calldata
     * @param data encoded bytes including SocketGateway calldata and ModifyCalldataParams
     * @return modifiedCalldata The modified calldata
     */
    function _parseAndModifyCalldata(uint256 amount, bytes calldata data) internal pure returns (bytes memory) {
        // Parse the data into route calldata and ModifyCalldataParams
        (bytes memory routeCalldata, ModifyCalldataParams memory modifyCalldataParams) = _parseCalldata(data);

        // Read the original input amount from the calldata
        // before modifying input amount
        uint256 originalInput = _readUint256({_data: routeCalldata, _index: modifyCalldataParams.inputAmountIdx});

        // Replace the input amount in the calldata
        bytes memory modifiedCalldata =
            _replaceUint256({_original: routeCalldata, _start: modifyCalldataParams.inputAmountIdx, _amount: amount});

        // Optionally replace the output amount if required
        // in case of bridges like Across, need to modify both input and output amounts
        // - decode current input and output amounts from calldata
        // - calculate and apply the percentage diff bw new and old input amount on the old output amount
        // - replace the output amount at the index with the new amount
        // - assumes output amount is always uint256 in SocketGateway impls
        if (modifyCalldataParams.modifyOutput) {
            uint256 originalOutput = _readUint256({_data: routeCalldata, _index: modifyCalldataParams.outputAmountIdx});
            uint256 newOutput = _applyPctDiff({_base: originalInput, _compare: amount, _target: originalOutput});
            modifiedCalldata = _replaceUint256({
                _original: modifiedCalldata,
                _start: modifyCalldataParams.outputAmountIdx,
                _amount: newOutput
            });
        }

        return modifiedCalldata;
    }

    /**
     * @dev Parses the calldata to extract the route calldata and ModifyCalldataParams
     * @param _data The calldata to parse
     * @return routeCalldata The SocketGateway route calldata
     * @return modifyCalldataParams The ModifyCalldataParams
     */
    function _parseCalldata(bytes calldata _data) internal pure returns (bytes memory, ModifyCalldataParams memory) {
        // calldata should have minimum of routeId and ModifyCalldataParams
        if (_data.length < MIN_DATA_LENGTH) revert InvalidInput();
        uint256 routeCalldataLength = _data.length - MODIFY_CALLDATA_LENGTH;

        // Extract the route execution calldata
        bytes memory routeCalldata = _data[:routeCalldataLength];

        // Extract the ModifyCalldataParams
        ModifyCalldataParams memory modifyCalldataParams;
        (modifyCalldataParams.inputAmountIdx, modifyCalldataParams.modifyOutput, modifyCalldataParams.outputAmountIdx) =
            abi.decode(_data[routeCalldataLength:], (uint256, bool, uint256));

        return (routeCalldata, modifyCalldataParams);
    }

    /**
     * @dev Replaces a uint256 at a given position in a bytes data with a new uint256
     * @dev Directly modifies the original bytes data in-place without creating a new copy
     */
    function _replaceUint256(bytes memory _original, uint256 _start, uint256 _amount)
        internal
        pure
        returns (bytes memory)
    {
        // check if the _start is out of bounds
        if (_start + 32 > _original.length) revert PositionOutOfBounds();

        // Directly modify externalData in-place without creating a new copy
        assembly {
            // Calculate position in memory where we need to write the new amount
            // Write the amount at that position
            mstore(add(add(_original, 32), _start), _amount)
        }

        return _original;
    }

    /**
     * @dev Reads a uint256 at a given byte index in a bytes array
     */
    function _readUint256(bytes memory _data, uint256 _index) internal pure returns (uint256 value) {
        if (_data.length < _index + 32) revert PositionOutOfBounds();
        assembly {
            value := mload(add(add(_data, 0x20), _index))
        }
    }

    /**
     * @dev Applies a percentage difference to a target number
     */
    function _applyPctDiff(uint256 _base, uint256 _compare, uint256 _target) internal pure returns (uint256) {
        if (_base == 0) revert InvalidInput();
        return Math.mulDiv({x: _target, y: _compare, denominator: _base});
    }
}
