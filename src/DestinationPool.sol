// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {IDestinationPool} from "./interfaces/IDestinationPool.sol";
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {IExecutor} from "nxtp/core/connext/interfaces/IExecutor.sol";
import {IConstantFlowAgreementV1} from "sf/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";

error Unauthorized();
error InvalidDomain();
error InvalidOriginContract();

struct FlowData {
    int96 flowRate;
    uint64 lastUpdate;
}

contract DestinationPool is IDestinationPool {
    event FlowMessageReceived(
        address indexed account,
        int96 flowRate
    );

    mapping(address => FlowData) public flow;

    uint32 public immutable originDomain;
    address public immutable originContract;

    IExecutor public immutable executor;
    IConnextHandler public immutable connext;
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;
    ISuperToken public immutable token;

    modifier isMessageValid() {
        if (msg.sender != address(executor)) revert Unauthorized();
        if (executor.origin() != originDomain) revert InvalidDomain();
        if (executor.originSender() != originContract) revert InvalidOriginContract();
        _;
    }

    constructor(
        uint32 _originDomain,
        address _originContract,
        IConnextHandler _connext,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        ISuperToken _token
    ) {
        originDomain = _originDomain;
        originContract = _originContract;
        connext = _connext;
        executor = _connext.executor();
        host = _host;
        cfa = _cfa;
        token = _token;

        // approve token to upgrade
        IERC20(_token.getUnderlyingToken()).approve(address(token), type(uint256).max);
    }

    function receiveFlowMessage(
        address account,
        int96 flowRate
    ) external override isMessageValid {
        // if possible, upgrade all non-super tokens in the pool
        uint256 balance = IERC20(token.getUnderlyingToken()).balanceOf(address(this));

        if (balance > 0) token.upgrade(balance);

        (,int96 existingFlowRate,,) = cfa.getFlow(token, address(this), account);

        bytes memory callData;

        if (existingFlowRate == 0) {
            if (flowRate == 0) return; // do not revert
            // create
            callData = abi.encodeCall(cfa.createFlow, (token, account, flowRate, new bytes(0)));
        } else if (flowRate > 0) {
            // update
            callData = abi.encodeCall(cfa.updateFlow, (token, account, flowRate, new bytes(0)));
        } else {
            // delete
            callData = abi.encodeCall(
                cfa.deleteFlow,
                (token, address(this), account, new bytes(0))
            );
        }

        host.callAgreement(cfa, callData, new bytes(0));
    }
}
