// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISuperToken, ISuperTokenFactory} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {SuperfluidFrameworkDeployer} from "sf/utils/SuperfluidFrameworkDeployer.sol";
import {ERC1820RegistryCompiled} from "sf/libs/ERC1820RegistryCompiled.sol";
import {Test} from "std/Test.sol";

import {DestinationPool} from "../src/DestinationPool.sol";
import {IConnextHandler} from "../src/interfaces/IConnextHandler.sol";
import {IExecutor, ExecutorArgs} from "../src/interfaces/IExecutor.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ConnextHandlerMock} from "./mocks/ConnextHandlerMock.sol";
import {ExecutorMock} from "./mocks/ExecutorMock.sol";

contract DestinationPoolTest is Test {
    event FlowMessageReceived(
        address indexed account,
        int96 flowRate
    );

    event RebalanceMessageReceived();

    address internal constant deployer = address(1);
    address internal constant alice = address(2);
    address internal constant originSenderMock = address(3);
    address internal constant destinationMock = address(4);

    uint32 internal constant originDomainMock = uint32(1);
    uint32 internal constant destinationDomainMock = uint32(2);

    int96 internal constant flowRate = int96(1e8);
    int96 internal constant flowRateUpdate = int96(2e8);

    uint256 internal constant initialBalance = uint256(1e20);
    uint256 internal constant bufferMock = uint256(uint96(flowRate)) * 4 hours;

    IConnextHandler internal connextMock;
    IExecutor internal executorMock;

    SuperfluidFrameworkDeployer.Framework internal sf;
    ERC20Mock internal underlyingToken;
    ISuperToken internal superToken;
    DestinationPool internal destinationPool;

    function setUp() external {
        vm.startPrank(deployer);

        // ERC1820
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        // SUPERFLUID
        sf = new SuperfluidFrameworkDeployer().getFramework();

        // TOKEN
        underlyingToken = new ERC20Mock("My Token", "MyT");

        // SUPER TOKEN
        superToken = ISuperToken(
            sf.superTokenFactory.createERC20Wrapper(
                underlyingToken,
                18,
                ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE,
                "Super My Token",
                "MyTx"
            )
        );

        // CONNEXT
        executorMock = IExecutor(address(new ExecutorMock(originDomainMock, originSenderMock)));
        connextMock = IConnextHandler(
            address(new ConnextHandlerMock(executorMock))
        );

        // DESTINATION POOL
        destinationPool = new DestinationPool(
            originDomainMock,
            originSenderMock,
            connextMock,
            sf.host,
            sf.cfa,
            superToken
        );

        vm.stopPrank();

        // ALICE SET UP
        vm.startPrank(alice);

        // send `initialBalance` to pool. TODO formal LP process.
        underlyingToken.mint(alice, initialBalance);
        underlyingToken.approve(address(superToken), initialBalance);
        superToken.upgrade(initialBalance);
        superToken.transfer(address(destinationPool), initialBalance);

        vm.stopPrank();
    }

    // //////////////////////////////////////////////////
    // DESTINATION POOL TESTS
    // //////////////////////////////////////////////////
    function testReceiveFlowMessage() external {
        bytes memory callData = abi.encodeCall(
            destinationPool.receiveFlowMessage,
            (alice, flowRate)
        );

        ExecutorArgs memory executorArgs = ExecutorArgs({
            transferId: bytes32(0x00),
            amount: bufferMock,
            to: address(destinationPool),
            recovery: address(destinationPool),
            assetId: address(underlyingToken),
            properties: new bytes(0),
            callData: callData
        });

        vm.expectEmit(true, false, false, true, address(destinationPool));
        emit FlowMessageReceived(alice, flowRate);

        executorMock.execute(executorArgs);

        (, int96 createdFlowRate, , ) = sf.cfa.getFlow(superToken, address(destinationPool), alice);

        assertEq(flowRate, createdFlowRate);
    }

    function testReceiveRebalanceMessage() external {
        bytes memory callData = abi.encodeWithSelector(
            destinationPool.receiveRebalanceMessage.selector
        );

        ExecutorArgs memory executorArgs = ExecutorArgs({
            transferId: bytes32(0x00),
            amount: bufferMock,
            to: address(destinationPool),
            recovery: address(destinationPool),
            assetId: address(underlyingToken),
            properties: new bytes(0),
            callData: callData
        });

        vm.expectEmit(false, false, false, false, address(destinationPool));
        emit RebalanceMessageReceived();

        executorMock.execute(executorArgs);
    }
}
