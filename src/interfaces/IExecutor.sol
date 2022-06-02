// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

struct ExecutorArgs {
    bytes32 transferId;
    uint256 amount;
    address to;
    address recovery;
    address assetId;
    bytes properties;
    bytes callData;
}

interface IExecutor {
    function origin() external view returns (uint32);
    function originSender() external view returns(address);
    function execute(ExecutorArgs calldata args) external;
}
