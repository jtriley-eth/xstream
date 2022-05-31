// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISuperToken, ISuperTokenFactory} from "sf/interfaces/superfluid/ISuperfluid.sol";
import {SuperfluidFrameworkDeployer} from "sf/utils/SuperfluidFrameworkDeployer.sol";
import {ERC1820RegistryCompiled} from "sf/libs/ERC1820RegistryCompiled.sol";
import {ERC20} from "oz/token/ERC20/ERC20.sol";
import {IERC20} from "oz/token/ERC20/IERC20.sol";
import {Test} from "std/Test.sol";

contract ContractTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    ERC20 internal token;
    ISuperToken internal superToken;

    address internal constant deployer = address(1);
    address internal constant alice = address(2);

    function setUp() public {
        vm.startPrank(deployer);

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        sf = new SuperfluidFrameworkDeployer().getFramework();

        token = new ERC20("My Token", "MyT");

        ISuperTokenFactory.Upgradability upgradability =
            ISuperTokenFactory.Upgradability.SEMI_UPGRADABLE;

        superToken = ISuperToken(
            sf.superTokenFactory.createERC20Wrapper(
                IERC20(token),
                18,
                upgradability,
                "Super My Token",
                "MyTx"
            )
        );

        vm.stopPrank();
    }

    function testExample() public pure {

        assert(true);

    }
}
