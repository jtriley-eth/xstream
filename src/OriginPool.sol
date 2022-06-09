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

/// @title Origin Pool to Receive Streams.
/// @author jtriley.eth
/// @notice This is a super app. On stream (create|update|delete), this contract sends a message
/// accross the bridge to the DestinationPool.
contract OriginPool {

    /// @dev Emitted when flow message is sent across the bridge.
    /// @param account Streamer account (only one-to-one address streaming for now).
    /// @param flowRate Flow Rate, unadjusted to the pool.
    event FlowMessageSent(
        address indexed account,
        int96 flowRate
    );

    /// @dev Emitted when rebalance message is sent across the bridge.
    /// @param amount Amount rebalanced (sent).
    event RebalanceMessageSent(uint256 amount);

    /// @dev Nomad Domain of this contract.
    uint32 public immutable originDomain;

    /// @dev Nomad Domain of the destination contract.
    uint32 public immutable destinationDomain;

    /// @dev Destination contract address
    address public destination;

    /// @dev Connext contracts.
    IConnextHandler public immutable connext;
    IExecutor public immutable executor;

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;
    ISuperToken public immutable token;

    /// @dev Validates callbacks.
    /// @param _agreementClass MUST be CFA.
    /// @param _token MUST be supported token.
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

        // register app
        _host.registerApp(
            SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP
        );
    }

    // demoday hack. this is not permanent.
    bool done;
    error Done();
    function setDomain(address _destination) external {
        if (done) revert Done();
        done = true;
        destination = _destination;
    }

    // //////////////////////////////////////////////////////////////
    // REBALANCER
    // //////////////////////////////////////////////////////////////

    /// @dev Rebalances pools. This sends funds over the bridge to the destination.
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

    /// @dev Sends rebalance message with the full balance of this pool. No need to collect dust.
    function _sendRebalanceMessage() internal {
        uint256 balance = token.balanceOf(address(this));

        // downgrade for sending across the bridge
        token.downgrade(balance);

        // encode call
        bytes memory callData = abi.encodeWithSelector(
            IDestinationPool.receiveRebalanceMessage.selector
        );

        // partial call params
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

        // full call params
        XCallArgs memory xCallArgs = XCallArgs({
            params: params,
            transactingAssetId: token.getUnderlyingToken(),
            amount: balance,
            relayerFee: 0
        });

        // call that thang
        connext.xcall(xCallArgs);

        emit RebalanceMessageSent(balance);
    }

    /// @dev Sends the flow message across the bridge.
    /// @param account The account streaming.
    /// @param flowRate Flow rate, unadjusted.
    function _sendFlowMessage(address account, int96 flowRate) internal {
        uint256 buffer;

        if (flowRate > 0) {
            // we take a second buffer for the outpool
            buffer = cfa.getDepositRequiredForFlowRate(token, flowRate);

            token.transferFrom(account, address(this), buffer);

            token.downgrade(buffer);
        }

        // encode call
        bytes memory callData = abi.encodeCall(
            IDestinationPool(destination).receiveFlowMessage,
            (account, flowRate)
        );

        // partial call params
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

        // full call params
        XCallArgs memory xCallArgs = XCallArgs({
            params: params,
            transactingAssetId: token.getUnderlyingToken(),
            amount: buffer,
            relayerFee: 0
        });

        // call that thang
        connext.xcall(xCallArgs);

        emit FlowMessageSent(account, flowRate);
    }
}
