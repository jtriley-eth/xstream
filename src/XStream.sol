// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IXStream} from "./interfaces/IXStream.sol";
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {IExecutor} from "nxtp/core/connext/interfaces/IExecutor.sol";
import {CallParams, XCallArgs} from "nxtp/core/connext/libraries/LibConnextStorage.sol";
import {ISuperfluid, ISuperToken} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {IConstantFlowAgreementV1} from "sf/interfaces/agreements/IConstantFlowAgreementV1.sol";

error InvalidCaller();
error InvalidDomain();
error InvalidOriginContract();

contract XStream is IXStream {

    event FlowMessageSent(
        address indexed sender,
        address indexed receiver,
        int96 flowRate,
        uint256 timestamp
    );

    event FlowMessageReceived(
        address indexed sender,
        address indexed receiver,
        int96 flowRate,
        uint256 xTime,
        uint256 localTime
    );

    /// @dev Contract on the other chain
    address public xContract;
    /// @dev Domain of the other chain
    uint32 xDomain;
    /// @dev Domain of this contract
    uint32 localDomain;

    IExecutor public immutable executor;
    IConnextHandler public immutable connext;
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;
    ISuperToken public immutable token;

    constructor(
        address _originContract,
        uint32 _originDomain,
        IConnextHandler _connext,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        ISuperToken _token
    ) {
        originContract = _originContract;
        originDomain = _originDomain;
        connext = _connext;
        executor = _connext.executor();
        host = _host;
        cfa = _cfa;
        token = _token;
    }

    modifier validMessage() {
        if (msg.sender != address(executor)) revert InvalidCaller();
        if (executor.origin() != xDomain) revert InvalidDomain();
        if (executor.originSender() != xContract) revert InvalidOriginContract();
        _;
    }

    function sendFlowMessage(
        address destinationDomain,
        address sender,
        address receiver,
        int96 flowRate,
        uint256 timestamp
    ) external {

        bytes memory callData = abi.encodeCall(
            IXStream.receiveFlowMessage,
            (sender, receiver, flowRate, timestamp)
        );

        CallParams memory params = CallParams({
            to: xContract,
            callData: callData,
            originDomain: localDomain,
            destinationDomain: destinationDomain,
            recovery: xContract,
            callback: address(0),
            callbackFee: 0,
            forceSlow: true,
            receiveLocal: false // TODO see if i have to change this.
        });

        XCallArgs memory xCallArgs = XCallArgs({
            params: params,
            transactingAssetId: address(token),
            amount: 0,
            relayerFee: 0
        });

        connext.xcall(xCallArgs);

        emit FlowMessageSent(sender, receiver, flowRate, timestamp);
    }

    function receiveFlowMessage(
        address sender,
        address receiver,
        int96 flowRate,
        uint256 timestamp
    ) external validMessage {

        uint256 deposit = cfa.getDepositRequiredForFlowRate(token, flowRate);

        if (token.balanceOf(address(this)) * 2 < deposit) {
            _throw(); // _returnData();
        }

        host.callAgreement(
            cfa,
            abi.encodeCall(cfa.createFlow, (token, receiver, flowRate, new bytes(0))),
            new bytes(0)
        );

        emit FlowMessageReceived(sender, receiver, flowRate, timestamp, block.timestamp);

    }

    // OPTION 1
    // THROW THAT HO

    error ChangeFlowFailed(
        address sender,
        address receiver,
        int96 flowRate,
        uint256 timestamp
    );

    function _throw(
        address sender,
        address receiver,
        int96 flowRate,
        uint256 timestamp
    ) internal {
        revert ChangeFlowFailed(sender, receiver, flowRate, timestamp);
    }

    // OPTION 2
    // RETURN TO SENDER

    function _returnData() internal {
        // I'm not rewriting this bc it's Friday afternoon, but:
        // INSERT MESSAGE TO SEND BACK OVER THE BRIDGE HERE
    }

}
