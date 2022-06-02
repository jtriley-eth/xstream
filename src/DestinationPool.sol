// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import {IDestinationPool} from "./interfaces/IDestinationPool.sol";
import {IConnextHandler} from "./interfaces/IConnextHandler.sol";
import {IExecutor} from "./interfaces/IExecutor.sol";
import {IConstantFlowAgreementV1} from "sf/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {ISuperfluid, ISuperToken} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";

error Unauthorized();
error InvalidDomain();
error InvalidOriginContract();

contract DestinationPool is IDestinationPool, ERC4626 {

    /// @dev Emitted when connext delivers a flow message.
    /// @param account Account to stream to.
    /// @param flowRate Adjusted flow rate.
    event FlowMessageReceived(
        address indexed account,
        int96 flowRate
    );

    /// @dev Emitted when connext delivers a rebalance message. // TODO Add amount?
    event RebalanceMessageReceived();

    /// @dev Nomad domain of origin contract.
    uint32 public immutable originDomain;

    /// @dev Origin contract address.
    address public immutable originContract;

    /// @dev Connext executor.
    IExecutor public immutable executor;

    /// @dev Superfluid contracts.
    ISuperfluid public immutable host;
    IConstantFlowAgreementV1 public immutable cfa;
    ISuperToken public immutable token;

    /// @dev Virtual "flow rate" of fees being accrued in real time.
    int96 public feeAccrualRate;

    /// @dev Last update's timestamp of the `feeAccrualRate`.
    uint256 public lastFeeAccrualUpdate;

    /// @dev Fees pending that are NOT included in the `feeAccrualRate`
    // TODO this might not be necessary since the full balance is sent on flow update.
    uint256 public feesPending;

    /// @dev Validates message sender, origin, and originContract.
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
    ) ERC4626(
        ERC20(address(_token)),
        // xPool Super DAI
        string(abi.encodePacked("xPool ", _token.name())),
        // xpDAIx // kek
        string(abi.encodePacked("xp", _token.symbol()))
    ) {
        originDomain = _originDomain;
        originContract = _originContract;
        executor = _connext.executor();
        host = _host;
        cfa = _cfa;
        token = _token;

        // approve token to upgrade
        ERC20(_token.getUnderlyingToken()).approve(address(token), type(uint256).max);
    }

    // //////////////////////////////////////////////////////////////
    // ERC4626 OVERRIDES
    // //////////////////////////////////////////////////////////////

    /// @dev Total assets including fees not yet rebalanced.
    function totalAssets() public view override returns (uint256) {
        uint256 balance = token.balanceOf(address(this));

        uint256 feesSinceUpdate =
            uint256(uint96(feeAccrualRate)) * (lastFeeAccrualUpdate - block.timestamp);

        return balance + feesPending + feesSinceUpdate;
    }

    // //////////////////////////////////////////////////////////////
    // MESSAGE RECEIVERS
    // //////////////////////////////////////////////////////////////

    /// @dev Flow message receiver.
    /// @param account Account streaming.
    /// @param flowRate Unadjusted flow rate.
    function receiveFlowMessage(address account, int96 flowRate)
        external
        override
        isMessageValid
    {
        // 0.1%
        int96 feeFlowRate = flowRate * 10 / 10000;

        // update fee accrual rate
        _updateFeeFlowRate(feeFlowRate);

        // Adjust for fee on the destination for fee computation.
        int96 flowRateAdjusted = flowRate - feeFlowRate;

        // if possible, upgrade all non-super tokens in the pool
        uint256 balance = ERC20(token.getUnderlyingToken()).balanceOf(address(this));

        if (balance > 0) token.upgrade(balance);

        (,int96 existingFlowRate,,) = cfa.getFlow(token, address(this), account);

        bytes memory callData;

        if (existingFlowRate == 0) {
            if (flowRateAdjusted == 0) return; // do not revert
            // create
            callData = abi.encodeCall(
                cfa.createFlow,
                (token, account, flowRateAdjusted, new bytes(0))
            );
        } else if (flowRateAdjusted > 0) {
            // update
            callData = abi.encodeCall(
                cfa.updateFlow,
                (token, account, flowRateAdjusted, new bytes(0))
            );
        } else {
            // delete
            callData = abi.encodeCall(
                cfa.deleteFlow,
                (token, address(this), account, new bytes(0))
            );
        }

        host.callAgreement(cfa, callData, new bytes(0));

        emit FlowMessageReceived(account, flowRateAdjusted);
    }

    /// @dev Rebalance message receiver.
    function receiveRebalanceMessage() external override isMessageValid {
        uint256 underlyingBalance = ERC20(token.getUnderlyingToken()).balanceOf(address(this));

        uint256 tokenBalance = token.balanceOf(address(this));

        token.upgrade(underlyingBalance);

        tokenBalance -= token.balanceOf(address(this));

        _updatePendingFees(tokenBalance);

        emit RebalanceMessageReceived();
    }

    /// @dev Updates the pending fees on a rebalance call.
    function _updatePendingFees(uint256 received) internal {
        feesPending -= received;
    }

    /// @dev Updates the pending fees, feeAccrualRate, and lastFeeAccrualUpdate on a flow call.
    function _updateFeeFlowRate(int96 feeFlowRate) internal {
        feesPending += uint256(uint96(feeFlowRate)) * (lastFeeAccrualUpdate * block.timestamp);

        feeAccrualRate += feeFlowRate;

        lastFeeAccrualUpdate = block.timestamp;
    }
}
