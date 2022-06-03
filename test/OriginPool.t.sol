// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ISuperToken, ISuperTokenFactory} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {
    SuperfluidFrameworkDeployer,
    ERC20WithTokenInfo
} from "sf/utils/SuperfluidFrameworkDeployer.sol";
import {ERC1820RegistryCompiled} from "sf/libs/ERC1820RegistryCompiled.sol";
import {IERC20} from "oz/token/ERC20/ERC20.sol";
import {Test} from "std/Test.sol";

import {OriginPool} from "../src/OriginPool.sol";
import {IConnextHandler} from "../src/interfaces/IConnextHandler.sol";
import {IExecutor, ExecutorArgs} from "../src/interfaces/IExecutor.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {ConnextHandlerMock} from "./mocks/ConnextHandlerMock.sol";
import {ExecutorMock} from "./mocks/ExecutorMock.sol";

contract OriginPoolTest is Test {
    event XCall(uint8 noop);

    address internal constant deployer = address(1);
    address internal constant alice = address(2);
    address internal constant originSenderMock = address(3);
    address internal constant destinationMock = address(4);

    uint32 internal constant originDomainMock = uint32(1);
    uint32 internal constant destinationDomainMock = uint32(2);

    int96 internal constant flowRate = int96(1e8);
    int96 internal constant flowRateUpdate = int96(2e8);

    uint256 internal constant initialBalance = uint256(1e20);

    IConnextHandler internal connextMock;
    IExecutor internal executorMock;

    SuperfluidFrameworkDeployer.Framework internal sf;
    ERC20Mock internal underlyingToken;
    ISuperToken internal superToken;
    OriginPool internal originPool;

    function setUp() public {
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
                ERC20WithTokenInfo(address(underlyingToken)),
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

        // ORIGIN POOL
        originPool = new OriginPool(
            originDomainMock,
            destinationDomainMock,
            destinationMock,
            connextMock,
            sf.host,
            sf.cfa,
            superToken
        );

        vm.stopPrank();

        // ALICE SET UP
        vm.startPrank(alice);

        underlyingToken.mint(alice, initialBalance);
        underlyingToken.approve(address(superToken), type(uint256).max);
        superToken.upgrade(initialBalance);
        superToken.approve(address(originPool), type(uint256).max);

        vm.stopPrank();
    }

    // //////////////////////////////////////////////////
    // ORIGIN POOL TESTS
    // //////////////////////////////////////////////////
    function testCreateFlow() public {
        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.createFlow,
                (superToken, address(originPool), flowRate, new bytes(0))
            ),
            new bytes(0)
        );

        (, int96 createdFlowRate,,) = sf.cfa.getFlow(superToken, alice, address(originPool));

        assertEq(createdFlowRate, flowRate);
    }

    function testUpdateFlow() public {
        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.createFlow,
                (superToken, address(originPool), flowRate, new bytes(0))
            ),
            new bytes(0)
        );

        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.updateFlow,
                (superToken, address(originPool), flowRateUpdate, new bytes(0))
            ),
            new bytes(0)
        );

        (, int96 updatedFlowRate,,) = sf.cfa.getFlow(superToken, alice, address(originPool));

        assertEq(updatedFlowRate, flowRateUpdate);
    }

    function testDeleteFlow() public {
        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.createFlow,
                (superToken, address(originPool), flowRate, new bytes(0))
            ),
            new bytes(0)
        );

        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.deleteFlow,
                (superToken, alice, address(originPool), new bytes(0))
            ),
            new bytes(0)
        );

        (, int96 deletedFlowRate,,) = sf.cfa.getFlow(superToken, alice, address(originPool));

        assertEq(deletedFlowRate, 0);
    }

    function testCallbackCallsConnext() public {
        vm.expectEmit(false, false, false, false, address(connextMock));
        emit XCall(uint8(0));

        vm.prank(alice);
        sf.host.callAgreement(
            sf.cfa,
            abi.encodeCall(
                sf.cfa.createFlow,
                (superToken, address(originPool), flowRate, new bytes(0))
            ),
            new bytes(0)
        );
    }

    function testRebalance() public {
        vm.expectEmit(false, false, false, false, address(connextMock));
        emit XCall(uint8(0));

        originPool.rebalance();
    }
}
