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

- StreamFactory

  - Creates new Streams using minimal clones
  - Supports predicting new Stream contract addresses, making it easier to compose DAO proposals, since a proposal author can know the address of the Stream the proposal will create before it's created

- Stream

  - Supports custom start and end timestamps
  - Does not enforce upfront funding, making it usable for DAOs and other payers that acquire payment tokens post Stream creation

## How to run tests

To run smart contract tests, make sure you have [Foundry](https://book.getfoundry.sh/) installed, then run:

```sh
forge install
forge test
```

## How to deploy

TODO
