// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @dev See:
/// https://arbiscan.io/address/0x3a23F943181408EAC424116Af7b7790c94Cb97a5#code
interface ISocketGateway {
    function executeRoute(uint32 routeId, bytes calldata routeData) external payable returns (bytes memory);
}
