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

    /**
     * @dev This function isn't intended to be called directly, it should be delegatecalled instead.
     * @param token The token to bridge
     * @param minAmount The minimum amount of tokens to bridge. minAmount should not be too small if the sell amount is big
     * @param nativeTokenExtraFee The extra fee to pay in native tokens
     * @param data The data to pass to the bridge
     */
    function approveAndBridge(IERC20 token, uint256 minAmount, uint256 nativeTokenExtraFee, bytes calldata data)
        external
    {
        address target = bridgeApprovalTarget();
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
            uint256 current = token.allowance(address(this), target);
            if (current < balance) {
                // Try direct approval first to bypass zero-intolerant reverts
                (bool success, bytes memory returnData) = address(token).call(
                    abi.encodeWithSelector(IERC20.approve.selector, target, balance)
                );

                // Success if call didn't revert and (no return data or true boolean)
                bool approved = success && (returnData.length == 0 || abi.decode(returnData, (bool)));

                // Fallback to forceApprove if direct fails (e.g. USDT)
                if (!approved) {
                    token.forceApprove(target, balance);
                }
            }
        }

        // bridge the token
        bridge(token, balance, nativeTokenExtraFee, data);

        // POST-BRIDGE: Conditional Silent Cleanup
        if (address(token) != NATIVE_TOKEN_ADDRESS) {
            if (token.allowance(address(this), target) > 0) {
                (bool success, ) = address(token).call(abi.encodeWithSelector(IERC20.approve.selector, target, 0));
                success;
            }
            
        }
    }

    /**
     * @dev Returns the address of the contract that should be approved to bridge the token
     */
    function bridgeApprovalTarget() public view virtual returns (address);

    /**
     * @dev Bridges the token
     */
    function bridge(IERC20 token, uint256 amount, uint256 nativeTokenExtraFee, bytes calldata data) internal virtual;
}
