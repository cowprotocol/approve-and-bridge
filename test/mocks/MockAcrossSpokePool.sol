// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IAcrossSpokePoolV3} from "src/interface/IAcrossSpokePoolV3.sol";

/// @dev Mock SpokePool that records the most recent `depositV3` call.
/// @dev We capture the calldata via fallback and decode lazily, since a
///      function taking 12 arguments + storing them all causes
///      stack-too-deep with the legacy code generator.
contract MockAcrossSpokePool {
    address public lastDepositor;
    address public lastRecipient;
    address public lastInputToken;
    address public lastOutputToken;
    uint256 public lastInputAmount;
    uint256 public lastOutputAmount;
    uint256 public lastDestinationChainId;
    address public lastExclusiveRelayer;
    uint32 public lastQuoteTimestamp;
    uint32 public lastFillDeadline;
    uint32 public lastExclusivityDeadline;
    bytes public lastMessage;
    uint256 public lastValue;
    uint256 public callCount;

    fallback() external payable {
        require(bytes4(msg.data[:4]) == IAcrossSpokePoolV3.depositV3.selector, "MockSpokePool: bad selector");
        _recordStaticHead(msg.data[4:]);
        _recordDynamicTail(msg.data[4:]);
        lastValue = msg.value;
        callCount += 1;
    }

    receive() external payable {}

    /// @dev Decodes and stores the static-head fields (everything except `message`).
    function _recordStaticHead(bytes calldata args) private {
        (
            address depositor,
            address recipient,
            address inputToken,
            address outputToken,
            uint256 inputAmount,
            uint256 outputAmount,
            uint256 destinationChainId,
            address exclusiveRelayer
        ) = abi.decode(args, (address, address, address, address, uint256, uint256, uint256, address));
        lastDepositor = depositor;
        lastRecipient = recipient;
        lastInputToken = inputToken;
        lastOutputToken = outputToken;
        lastInputAmount = inputAmount;
        lastOutputAmount = outputAmount;
        lastDestinationChainId = destinationChainId;
        lastExclusiveRelayer = exclusiveRelayer;
    }

    /// @dev Decodes and stores the deadlines and the dynamic `message`.
    function _recordDynamicTail(bytes calldata args) private {
        // Skip first 8 head slots (= 256 bytes) we already decoded.
        bytes calldata rest = args[256:];
        (uint32 quoteTimestamp, uint32 fillDeadline, uint32 exclusivityDeadline, bytes memory message) =
            _decodeTail(args, rest);
        lastQuoteTimestamp = quoteTimestamp;
        lastFillDeadline = fillDeadline;
        lastExclusivityDeadline = exclusivityDeadline;
        lastMessage = message;
    }

    function _decodeTail(bytes calldata fullArgs, bytes calldata rest)
        private
        pure
        returns (uint32, uint32, uint32, bytes memory)
    {
        (uint32 q, uint32 f, uint32 e, uint256 messageOffset) = abi.decode(rest, (uint32, uint32, uint32, uint256));
        // messageOffset is relative to start of args (after selector). Read length + data.
        bytes memory message = abi.decode(fullArgs[messageOffset:], (bytes));
        return (q, f, e, message);
    }
}
