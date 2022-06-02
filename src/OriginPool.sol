// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {IDestinationPool} from "./interfaces/IDestinationPool.sol";
import {IConnextHandler, CallParams, XCallArgs} from "./interfaces/IConnextHandler.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
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

    event RebalanceMessageSent(uint256 amount);

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
        ERC20(_token.getUnderlyingToken()).approve(address(_connext), type(uint256).max);

        _host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
    }

    // //////////////////////////////////////////////////////////////
    // REBALANCER
    // //////////////////////////////////////////////////////////////
    function rebalance() external {
        _sendRebalanceMessage();
    }

    // //////////////////////////////////////////////////////////////
    // SUPER APP CALLBACKS
    // //////////////////////////////////////////////////////////////
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

    // //////////////////////////////////////////////////////////////
    // MESSAGE SENDERS
    // //////////////////////////////////////////////////////////////
    function _sendRebalanceMessage() internal {
        uint256 balance = token.balanceOf(address(this));

        bytes memory callData = abi.encodeWithSelector(
            IDestinationPool.receiveRebalanceMessage.selector
        );

        token.downgrade(balance);

        CallParams memory params = CallParams({
            to: destination,
            callData: callData,
            originDomain: originDomain,
            destinationDomain: destinationDomain,
            recovery: destination,
            callback: address(0),
            callbackFee: 0,
            forceSlow: true,
            receiveLocal: false
        });

        XCallArgs memory xCallArgs = XCallArgs({
            params: params,
            transactingAssetId: token.getUnderlyingToken(),
            amount: balance,
            relayerFee: 0
        });

        connext.xcall(xCallArgs);

        emit RebalanceMessageSent(balance);
    }

    function _sendFlowMessage(address account, int96 flowRate) internal {
        uint256 buffer;

        if (flowRate > 0) {
            // we take a second buffer for the outpool
            buffer = cfa.getDepositRequiredForFlowRate(token, flowRate);

            token.transferFrom(account, address(this), buffer);

            token.downgrade(buffer);
        }

        bytes memory callData = abi.encodeCall(
            IDestinationPool(destination).receiveFlowMessage,
            (account, flowRate)
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

        emit FlowMessageSent(account, flowRate, flowRate);
    }
}
