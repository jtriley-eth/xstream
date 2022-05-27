// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IXStream {
    function sendFlowMessage(address, address, int96, uint256) external;
    function receiveFlowMessage(address, address, int96, uint256) external;
}
