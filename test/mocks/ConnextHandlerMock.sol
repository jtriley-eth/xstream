// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import {XCallArgs} from "../../src/interfaces/IConnextHandler.sol";
import {IExecutor} from "../../src/interfaces/IExecutor.sol";

contract ConnextHandlerMock {
    event XCall(uint8 noop);

    IExecutor public executor;

    constructor(IExecutor _executooor) { executor = _executooor; }

    function xcall(XCallArgs calldata) public { emit XCall(0); }
}
