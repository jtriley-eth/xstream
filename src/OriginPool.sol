// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.0;

import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {IDestinationPool} from "./interfaces/IDestinationPool.sol";
import {IConnextHandler} from "nxtp/core/connext/interfaces/IConnextHandler.sol";
import {IExecutor} from "nxtp/core/connext/interfaces/IExecutor.sol";
import {CallParams, XCallArgs} from "nxtp/core/connext/libraries/LibConnextStorage.sol";
import {IConstantFlowAgreementV1} from "sf/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {
    ISuperfluid,
    ISuperToken,
    SuperAppDefinitions
} from "sf/interfaces/superfluid/ISuperfluid.sol";

error Unauthorized();
error InvalidAgreement();
error InvalidToken();
error StreamAlreadyActive();

contract OriginPool {
    event FlowMessageSent(
        address indexed account,
        int96 flowRate,
        int96 flowRateAdjusted
    );

    int96 public constant feeRate = 10; // 0.1%

    uint32 public immutable originDomain;
    uint32 public immutable destinationDomain;

    address public immutable destination;
    IConnextHandler public immutable connext;
    IExecutor public immutable executor;
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;
    ISuperToken public immutable token;

    modifier isCallbackValid(address _agreementClass, ISuperToken _token) {
        if (msg.sender != address(host)) revert Unauthorized();
        if (_agreementClass != address(cfa)) revert InvalidAgreement();
        if (_token != token) revert InvalidToken();
        _;
    }

    constructor(
        uint32 _originDomain,
        uint32 _destinationDomain,
        address _destination,
        IConnextHandler _connext,
        ISuperfluid _host,
        IConstantFlowAgreementV1 _cfa,
        ISuperToken _token
    ) {
        originDomain = _originDomain;
        destinationDomain = _destinationDomain;
        destination = _destination;
        connext = _connext;
        executor = _connext.executor();
        host = _host;
        cfa = _cfa;
        token = _token;

        // surely this can't go wrong
        IERC20(_token.getUnderlyingToken()).approve(address(_connext), type(uint256).max);

        _host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
    }

    function afterAgreementCreated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address,address));

        ( , int96 flowRate, , ) = cfa.getFlowByID(superToken, agreementId);

        _sendFlowMessage(sender, flowRate);

        return ctx;
    }

    function afterAgreementUpdated(
        ISuperToken superToken,
        address agreementClass,
        bytes32 agreementId,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address, address));

        ( , int96 flowRate, , ) = cfa.getFlowByID(superToken, agreementId);

        _sendFlowMessage(sender, flowRate);

        return ctx;
    }

    function afterAgreementTerminated(
        ISuperToken superToken,
        address agreementClass,
        bytes32,
        bytes calldata agreementData,
        bytes calldata, // cbdata
        bytes calldata ctx
    ) external isCallbackValid(agreementClass, superToken) returns (bytes memory) {
        (address sender, ) = abi.decode(agreementData, (address,address));

        _sendFlowMessage(sender, 0);

        return ctx;
    }

    function _sendFlowMessage(address account, int96 flowRate) internal {
        int96 flowRateAdjusted = _adjustFlowRate(flowRate);

        // we take a second buffer for the outpool
        uint256 buffer = cfa.getDepositRequiredForFlowRate(token, flowRateAdjusted);

        token.transferFrom(account, address(this), buffer);

        token.downgrade(buffer);

        bytes memory callData = abi.encodeCall(
            IDestinationPool(destination).receiveFlowMessage,
            (account, flowRateAdjusted)
        );

        CallParams memory params = CallParams({
            to: destination,
            callData: callData,
            originDomain: originDomain,
            destinationDomain: destinationDomain,
            recovery: destination,
            callback: address(0),
            callbackFee: 0,
            forceSlow: true, // permissioned call
            receiveLocal: false
        });

        XCallArgs memory xCallArgs = XCallArgs({
            params: params,
            transactingAssetId: token.getUnderlyingToken(),
            amount: buffer,
            relayerFee: 0
        });

        connext.xcall(xCallArgs);

        emit FlowMessageSent(account, flowRate, flowRateAdjusted);
    }

    function _adjustFlowRate(int96 flowRate) internal pure returns (int96) {
        return flowRate + (flowRate * feeRate / 10000);
    }
}
