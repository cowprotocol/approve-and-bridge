// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";

interface IApproveAndBridge {
    function approveAndBridge(IERC20 token, uint256 minAmount, bytes calldata data) external;

    function bridgeApprovalTarget() external view returns (address);
}
