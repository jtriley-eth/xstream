// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

interface IDestinationPool {
    function receiveFlowMessage(address, int96) external;
    function receiveRebalanceMessage() external;
}
