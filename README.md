# XStream

The first cross-chain streaming protocol.

Built with Superfluid and Connext.

## OriginPool.sol

The `OriginPool` is a registered "Super App", a smart contract that receives
callbacks from the Superfluid Host contract on the creation of a stream from
any address.

The creation, updating, or deletion of a stream triggers the appropriate
callback. When this happens, `OriginPool` sends a message to the Connext
contract to be sent to the `DestinationPool`.

The `OriginPool` also exposes a `rebalance` function that takes no arguments,
it simply downgrades the Super Token to its underlying asset, then sends the
full balance to the `DestinationPool`. Since the stream is one-way, there is no
need to keep any tokens in the `OriginPool`. Notice that the underlying asset
must be transferred, _not_ the Super Token itself.

## DestinationPool.sol

The `DestinationPool` is an EIP-4626 Standardized Token Vault where the `asset`
is the Super Token, _not_ the underlying asset. The `totalFees` function
accounts for fees that have 'accrued' based on the most recent flow update and
rebalance call.

When a flow message is received, the fee accrual rate is updated and a stream
is created with a flow rate equal `99.9%` of the sender's `flowRate`. The
receiver of the current iteration is the same address that sent the stream.

When a rebalance message is received, the contract _must_ receive a non-zero
transfer of the underlying asset, since the call is permissioned from the
`OriginPool`. Therefore, the contract upgrades the entire balance of the
underlying asset to the Super Token. This also updates the `feesPending`
appropriately.

## Testnet Deployments

Origin Goerli:     0x4dda7f1a17721ec3a86b73141153ab7d1c7a2f9a
Destination Kovan: 0x9c8c227188192ecebfcfb96e266bec1595227259

SuperTest Goerli: 0x9a66388541b5c32ca6caa245406fe67cedf663f8
SuperTest Kovan:  0x720e4f8508c44955417b1e781956f368585ba239

