// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import {ExecutorArgs, IExecutor} from "../../src/interfaces/IExecutor.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

error ExecutorCallFail(bytes revertdata);

contract ExecutorMock is IExecutor {
    uint32 public origin;

    address public originSender;

    constructor(uint32 _origin, address _originSender) {
        origin = _origin;
        originSender = _originSender;
    }

    function execute(ExecutorArgs calldata args) public override {
        // send token
        ERC20Mock(args.assetId).mint(args.to, args.amount);

        // call that thang
        (bool success, bytes memory data) = args.to.call(args.callData);

        if (!success) revert ExecutorCallFail(data);
    }
}
