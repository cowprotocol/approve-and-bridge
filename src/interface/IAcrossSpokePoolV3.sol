// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @dev Minimal interface for the Across V3 SpokePool. See:
/// https://github.com/across-protocol/contracts/blob/master/contracts/interfaces/V3SpokePoolInterface.sol
interface IAcrossSpokePoolV3 {
    /// @notice Deposit funds into the SpokePool to be bridged to the destination chain.
    /// @dev When `inputToken` is the wrapped native token, ETH may be sent via `msg.value`
    ///      equal to `inputAmount` and the SpokePool will wrap it internally.
    function depositV3(
        address depositor,
        address recipient,
        address inputToken,
        address outputToken,
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 destinationChainId,
        address exclusiveRelayer,
        uint32 quoteTimestamp,
        uint32 fillDeadline,
        uint32 exclusivityDeadline,
        bytes calldata message
    ) external payable;
}
