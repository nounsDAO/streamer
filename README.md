# Streamer by Nouns DAO

## Motivation

This project solves the problem of allowing payers of token streams to create streams and fund them after the fact,
i.e. first create the stream, then fund it later when funds are available.

For example, Nouns DAO can use [Token Buyer](https://github.com/nounsDAO/token-buyer/) with Streamer and create proposals that:

1. Create a Stream
2. Ask TokenBuyer's Payer contract to send tokens to the newly created Stream when it has the funds
3. TokenBuyer acuiqres the funds, sends them to Payer, Payer funds the Stream
4. The Stream's recipient can start withdrawing funds

## Contracts

- [StreamFactory](https://github.com/nounsDAO/streamer/blob/master/src/StreamFactory.sol)

  - Creates new Streams using minimal clones
  - Supports predicting new Stream contract addresses, making it easier to compose DAO proposals, since a proposal author can know the address of the Stream the proposal will create before it's created

- [Stream](https://github.com/nounsDAO/streamer/blob/master/src/Stream.sol)

  - Supports custom start and end timestamps
  - Does not enforce upfront funding, making it usable for DAOs and other payers that acquire payment tokens post Stream creation

## How to run tests

To run smart contract tests, make sure you have [Foundry](https://book.getfoundry.sh/) installed, then run:

```sh
forge install
forge test
```

## How to deploy and manually test locally

Run Foundry's local node:

```sh
anvil
```

Copy one of anvil's test account's address and private key, to use in commands below.

Deploy StreamFactory:

```sh
forge script script/DeployStreamFactory.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sender <anvil test account address> --private-key <anvil test account private key>
```

Deploy MockToken, which you can use to mint tokens to your test Streams:

```sh
forge script script/DeployMockToken.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --sender <anvil test account address> --private-key <anvil test account private key>
```

Go to `./broadcast/DeployStreamFactory.s.sol/31337/run-latest.json` and copy the value of `contractAddress` for `StreamFactory`.
Go to `./broadcast/DeployMockToken.s.sol/31337/run-latest.json` and copy the value of `contractAddress` for `ERC20Mock`.

Copy another anvil test account and private key to use as your stream recipient.

If you want to create a stream that starts or ends in the future, you can use `foundry.toml` to override anvil's first block timestamp, or run `cast block latest` and copy the timestamp of the current block as a starting point to your stream.

Simulate stream creation:

```sh
cast call --rpc-url http://127.0.0.1:8545  --private-key <your first anvil test account private key> <your StreamFactory address> "createStream(address,uint256,address,uint256,uint256)" <your second test account, the recipient of the stream> <the token amount to stream, e.g. 1000> <your ERC20Mock contract address> <stream start timestamp, e.g. as taken from running cast block latest above> <stream end timestamp, e.g. start time + 1000 to make it predictable>
```

The output will look something like:

```sh
0x00000000000000000000000033f456c89902746ffed70041f8bc8672e3a171fd
```

This is the expected new stream address, you just need to trim it down a bit, in this case to be: `0x33f456c89902746ffed70041f8bc8672e3a171fd`.

Execute stream creation using the same inputs, by running the same command as above, only using `cast send` instead of `cast call`.

To make sure you're stream has been created, get the recipient's balance; it should be greater than zero:

```sh
cast call --rpc-url http://127.0.0.1:8545  --private-key <a test account private key> <stream contract address> "balanceOf(address)(uint256)" <stream recipient address>
```

To withdraw, you'll need to mint tokens to fund the stream, then call withdraw using the recipient account:

```sh
cast send --rpc-url http://127.0.0.1:8545  --private-key <a test account private key> <the ERC20Mock contract address> "mint(address,uint256)" <the stream contract address> <the stream amount, e.g. 1000>

cast send --rpc-url http://127.0.0.1:8545  --private-key <the payer or recipient account private key> <the stream contract address> "withdraw(uint256)" <the withdrawal amount, should not exceed recipient current balance>
```

### Local subgraph setup

In `./subgraph/networks.json`, make sure StreamFactory's address matches the one you recently deployed.

Spin up your local node: (you need Docker installed and running in the background)

```sh
yarn local-node
```

Then run:

```sh
yarn
yarn codegen
yarn build
yarn create-local
yarn deploy-local
```

You should now be able to query the subgraph and see your recently created streams and any withdrawals and cancellation events related to it. You can use Postman or any other HTTP request tool, send a POST request to `http://localhost:8000/subgraphs/name/streamer` with a GraphQL query like:

```
query {
    streams (limit: 10) {
        id
        createdAt
        createdBy
        payer
        recipient
        tokenAmount
        tokenAddress
        startTime
        stopTime
        withdrawals {
            id
            withdrawnAt
            executedBy
            amount
        }
        cancellations {
            id
            cancelledAt
            cancelledBy
            payerBalance
            recipientBalance
        }
    }
}
```

## How to deploy

TODO
