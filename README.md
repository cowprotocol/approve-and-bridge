## Approve and bridge
This is a simple reference implementation of a way to bridge tokens using CoW Protocol.

It provides a simple way to bridge assets within the same transaction as the swap by using [post-hooks](https://docs.cow.fi/cow-protocol/reference/core/intents/hooks).

## How it works

The general idea is:
1. A user creates an order where the `recipient` is modified to a smart contract wallet they control (for example, a 1-1 Safe or a [cow-shed](https://github.com/cowdao-grants/cow-shed)).
2. The swap executes, and the user controlled wallet receives the buy amount (including the surplus).
3. Within the same CoW settlement transaction, a [post-hooks](https://docs.cow.fi/cow-protocol/reference/core/intents/hooks) executes initiating the bridging process for the full amount.
4. Eventually, the bridge will be completed. The recipient of the buy tokens in the target chain is typically the user that initiated the swap (and not the smart contract wallet used for bridging)

## Bridge provider helper contracts
Each bridge provider creates their own helper contract. As a reference [ApproveAndBridge](src/mixin/ApproveAndBridge.sol) abstract contract implements the common logic and defines some `virtual` functions to be overridden by the bridge provider helper contract.

The helper contract makes 2 assumptions:
* The contract assumes it is being called using a `delegatecall` from the account that has the proceeds of the swap. 
* The balance of the account matches what the user intents to bridge. This is a simple way to handle CoW protocol's `surplus`. 
  - This can be achieved if the smart contract wallet is only used for bridging and is set as the `recipient` in the order.
  - For example, the user sell 100 DAI for 100 USDC, but the solvers manage to give the user 101 USDC, then the contract will have exactly 101 USDC in its balance. 

The main logic is defined in `approveAndBridge` function, which:
1. Get the balance of the bridged asset (includes `surplus` from the swap)
2. Performs some validations (like the `minAmount` tokens to bridge)
3. Sets the allowance, so the bridging protocol can pull the bridged amount.
4. Initiate the bridging process. Typically, the assets will be transferred to the bridging protocol.

The bridge provider helper contract overrides the function:
*  `bridge`: Implements the specific logic for the bridge provider.
*  `bridgeApprovalTarget`: Returns the address of the contract that should be approved to bridge the token.


## Disclaimer

This repository is provided solely as a reference and for informational purposes. 

The smart contracts and related materials included here are not audited, may contain vulnerabilities, and must not be relied upon in production or for any security-critical use without independent review and testing.

Certain contracts and examples may be contributed by third parties. Inclusion in this repository does not constitute an endorsement, recommendation, or warranty by the maintainers. The maintainers make no representations or guarantees regarding correctness, security, or fitness for any particular purpose, and disclaim all liability for any loss or damage arising from the use of these materials.

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Format

```shell
forge fmt
```

### Gas Snapshots

```shell
forge snapshot
```

### Anvil

```shell
anvil
```

### Deploy

```shell
forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
cast <subcommand>
```

### Help

```shell
forge --help
anvil --help
cast --help
```
