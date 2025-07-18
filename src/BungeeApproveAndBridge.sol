// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {ApproveAndBridge, IERC20} from "./mixin/ApproveAndBridge.sol";

/// ! @dev UNAUDITED UNTESTED Do not use in production
/// @dev Performs two steps before bridging:
/// 1. Modify input amount in calldata
/// 2. Modify output amount in calldata
contract BungeeApproveAndBridge is ApproveAndBridge {
    error InvalidInput();
    error PositionOutOfBounds();
    error BridgeFailed();

    struct ModifyCalldataParams {
        uint256 inputAmountIdx;
        bool modifyOutput;
        uint256 outputAmountIdx;
    }

    uint8 private constant EXTRA_DATA_PARAMS_COUNT = 3;
    uint8 private constant EXTRA_DATA_LENGTH_BYTES = 32;
    uint8 private constant EXTRA_DATA_LENGTH = EXTRA_DATA_PARAMS_COUNT * EXTRA_DATA_LENGTH_BYTES;

    address immutable SOCKET_GATEWAY;

    constructor(address socketGateway_) {
        SOCKET_GATEWAY = socketGateway_;
    }

    function bridgeApprovalTarget() public view override returns (address) {
        return address(SOCKET_GATEWAY);
    }

    function bridge(IERC20 token, uint256 amount, uint256 nativeTokenExtraFee, bytes calldata data) internal override {
        // decode & parse data to find positions in calldata to modify
        bytes memory modifiedCalldata = _parseAndModifyCalldata(amount, data);

        // execute using the modified calldata via SocketGateway.fallback()
        (bool success,) = address(token) == NATIVE_TOKEN_ADDRESS
            ? address(SOCKET_GATEWAY).call{value: amount + nativeTokenExtraFee}(modifiedCalldata)
            : address(SOCKET_GATEWAY).call{value: nativeTokenExtraFee}(modifiedCalldata);
        if (!success) revert BridgeFailed();
    }

    function _parseAndModifyCalldata(uint256 amount, bytes calldata data) internal pure returns (bytes memory) {
        // Parse the data into route calldata and extra data
        (bytes memory routeCalldata, ModifyCalldataParams memory modifyCalldataParams) = _parseCalldata(data);

        // Read the original input amount from the calldata
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

    function _parseCalldata(bytes calldata _data) internal pure returns (bytes memory, ModifyCalldataParams memory) {
        // Calculate the length of the route execution calldata (excluding the extra data struct)
        if (_data.length < EXTRA_DATA_LENGTH + 4) revert InvalidInput();
        uint256 routeCalldataLength = _data.length - EXTRA_DATA_LENGTH;

        // Extract the route execution calldata
        bytes memory routeCalldata = _data[:routeCalldataLength];

        // Extract the extra data struct
        ModifyCalldataParams memory modifyCalldataParams;
        (modifyCalldataParams.inputAmountIdx, modifyCalldataParams.modifyOutput, modifyCalldataParams.outputAmountIdx) =
            abi.decode(_data[routeCalldataLength:], (uint256, bool, uint256));

        return (routeCalldata, modifyCalldataParams);
    }

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

    // Helper to read a uint256 at a given byte index in a bytes array
    function _readUint256(bytes memory _data, uint256 _index) internal pure returns (uint256 value) {
        if (_data.length < _index + 32) revert PositionOutOfBounds();
        assembly {
            value := mload(add(add(_data, 0x20), _index))
        }
    }

    function _applyPctDiff(uint256 _base, uint256 _compare, uint256 _target) internal pure returns (uint256) {
        if (_compare > _base) {
            return _addPctDiff(_base, _compare, _target);
        } else {
            return _subPctDiff(_base, _compare, _target);
        }
    }

    /// @notice Calculates positive percentage difference between two numbers and applies it to a third number
    /// @param _base The base number to compare against
    /// @param _compare The number to compare with the base (should be >= _base)
    /// @param _target The number to apply the percentage difference to
    /// @return The target number adjusted by the percentage difference
    function _addPctDiff(uint256 _base, uint256 _compare, uint256 _target) internal pure returns (uint256) {
        // Base number must be greater than 0
        // Compare number must be greater than or equal to base number
        if (_base <= 0 || _compare < _base) revert InvalidInput();

        // Calculate the percentage difference
        uint256 difference = ((_compare - _base) * 1e18) / _base;
        // Apply percentage increase
        return _target + ((_target * difference) / 1e18);
    }

    /// @notice Calculates negative percentage difference between two numbers and applies it to a third number
    /// @param _base The base number to compare against
    /// @param _compare The number to compare with the base (should be >= _base)
    /// @param _target The number to apply the percentage difference to
    /// @return The target number adjusted by the percentage difference
    function _subPctDiff(uint256 _base, uint256 _compare, uint256 _target) internal pure returns (uint256) {
        // Base number must be greater than 0
        // Compare number must be less than or equal to base number
        if (_base <= 0 || _compare > _base) revert InvalidInput();

        // Calculate the percentage difference
        uint256 difference = ((_base - _compare) * 1e18) / _base;
        // Apply percentage decrease
        return _target - ((_target * difference) / 1e18);
    }
}
