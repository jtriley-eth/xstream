// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.13;

import {IExecutor} from "./IExecutor.sol";

struct CallParams {
  address to;
  bytes callData;
  uint32 originDomain;
  uint32 destinationDomain;
  address recovery;
  address callback;
  uint256 callbackFee;
  bool forceSlow;
  bool receiveLocal;
}

struct XCallArgs {
  CallParams params;
  address transactingAssetId; // Could be adopted, local, or wrapped
  uint256 amount;
  uint256 relayerFee;
}

interface IConnextHandler {
    function executor() external view returns (IExecutor);
    function xcall(XCallArgs calldata) external;
}
