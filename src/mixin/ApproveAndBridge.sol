// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IApproveAndBridge} from "../interface/IApproveAndBridge.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";

abstract contract ApproveAndBridge is IApproveAndBridge {
    using SafeERC20 for IERC20;

    error MinAmountNotMet();

    /// @dev Address used to represent the native token
    address public constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @dev This function isn't intended to be called directly, it should be
    /// delegatecalled instead.
    function approveAndBridge(IERC20 token, uint256 minAmount, uint256 nativeTokenExtraFee, bytes calldata data)
        external
    {
        // get the balance of the token
        uint256 balance = address(token) == NATIVE_TOKEN_ADDRESS
            // if native token, reduce the extra fee from balance
            // if not enough balance, it will underflow and revert
            ? address(this).balance - nativeTokenExtraFee
            : token.balanceOf(address(this));

        // check if the balance is greater than the minAmount
        if (balance < minAmount) revert MinAmountNotMet();

        // approve the bridgeApprovalTarget if ERC20
        if (address(token) != NATIVE_TOKEN_ADDRESS) {
            token.forceApprove(bridgeApprovalTarget(), balance);
        }

        // bridge the token
        bridge(token, balance, nativeTokenExtraFee, data);
    }

    function bridgeApprovalTarget() public view virtual returns (address);

    function bridge(IERC20 token, uint256 amount, uint256 nativeTokenExtraFee, bytes calldata data) internal virtual;
}
