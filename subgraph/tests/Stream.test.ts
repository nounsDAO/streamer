import { assert, describe, test, clearStore, afterEach } from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { handleTokensWithdrawn, handleStreamCancelled, handleTokensRecovered, handleETHRescued } from "../src/Stream";
import {
  createStreamCancelledEvent,
  createStreamCreatedEvent,
  createTokensWithdrawnEvent,
  createTokensRecoveredEvent,
  createETHRescuedEvent,
} from "./utils";
import { Cancellation, Withdrawal, TokenRecovery, ETHRescue } from "../generated/schema";
import { handleStreamCreated } from "../src/StreamFactory";

describe("Stream", () => {
  afterEach(() => {
    clearStore();
  });

  test("Creates a new Withdrawal", () => {
    const streamAddress = Address.fromString("0x0000000000000000000000000000000000000011");
    handleStreamCreated(
      createStreamCreatedEvent(
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        BigInt.fromI32(0),
        streamAddress,
      ),
    );

    const txHash = Bytes.fromHexString("0x4242");
    const logIndex = BigInt.fromI32(0);
    const timestamp = BigInt.fromI32(1000);
    const msgSender = Address.fromString("0x0000000000000000000000000000000000000001");
    const amount = BigInt.fromI32(42);

    handleTokensWithdrawn(createTokensWithdrawnEvent(txHash, logIndex, timestamp, msgSender, streamAddress, amount));

    const w = Withdrawal.load(txHash.toHex() + "-" + logIndex.toString());

    assert.bigIntEquals(w!.withdrawnAt, timestamp);
    assert.stringEquals(w!.executedBy.toHex(), msgSender.toHex());
    assert.stringEquals(w!.stream.toHex(), streamAddress.toHex());
    assert.bigIntEquals(w!.amount, amount);
  });

  test("Creates a new Cancellation", () => {
    const streamAddress = Address.fromString("0x0000000000000000000000000000000000000011");
    handleStreamCreated(
      createStreamCreatedEvent(
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        BigInt.fromI32(0),
        streamAddress,
      ),
    );

    const txHash = Bytes.fromHexString("0x4242");
    const logIndex = BigInt.fromI32(0);
    const timestamp = BigInt.fromI32(1000);
    const msgSender = Address.fromString("0x0000000000000000000000000000000000000001");
    const recipientBalance = BigInt.fromI32(4321);

    handleStreamCancelled(
      createStreamCancelledEvent(txHash, logIndex, timestamp, msgSender, streamAddress, recipientBalance),
    );

    const c = Cancellation.load(txHash.toHex() + "-" + logIndex.toString());

    assert.bigIntEquals(c!.cancelledAt, timestamp);
    assert.stringEquals(c!.cancelledBy.toHex(), msgSender.toHex());
    assert.stringEquals(c!.stream.toHex(), streamAddress.toHex());
    assert.bigIntEquals(c!.recipientBalance, recipientBalance);
  });

  test("Creates a new TokenRecovery", () => {
    const streamAddress = Address.fromString("0x0000000000000000000000000000000000000011");
    const payerAddress = Address.fromString("0x0000000000000000000000000000000000000022");
    handleStreamCreated(
      createStreamCreatedEvent(
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        payerAddress,
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        BigInt.fromI32(0),
        streamAddress,
      ),
    );

    const txHash = Bytes.fromHexString("0x4242");
    const logIndex = BigInt.fromI32(0);
    const timestamp = BigInt.fromI32(1000);
    const tokenAddress = Address.fromString("0x0000000000000000000000000000000000000042");
    const amount = BigInt.fromI32(4321);

    handleTokensRecovered(
      createTokensRecoveredEvent(txHash, logIndex, timestamp, streamAddress, payerAddress, tokenAddress, amount),
    );

    const tr = TokenRecovery.load(txHash.toHex() + "-" + logIndex.toString());

    assert.bigIntEquals(tr!.recoveredAt, timestamp);
    assert.stringEquals(tr!.stream.toHex(), streamAddress.toHex());
    assert.stringEquals(tr!.tokenAddress.toHex(), tokenAddress.toHex());
    assert.bigIntEquals(tr!.amount, amount);
  });

  test("Creates a new ETHRescue", () => {
    const streamAddress = Address.fromString("0x0000000000000000000000000000000000000011");
    const payerAddress = Address.fromString("0x0000000000000000000000000000000000000022");
    handleStreamCreated(
      createStreamCreatedEvent(
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        payerAddress,
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        Address.fromString("0x0000000000000000000000000000000000000000"),
        BigInt.fromI32(0),
        BigInt.fromI32(0),
        streamAddress,
      ),
    );

    const txHash = Bytes.fromHexString("0x4242");
    const logIndex = BigInt.fromI32(0);
    const timestamp = BigInt.fromI32(1000);
    const to = Address.fromString("0x0000000000000000000000000000000000000055");
    const amount = BigInt.fromI32(4321);

    handleETHRescued(createETHRescuedEvent(txHash, logIndex, timestamp, streamAddress, payerAddress, to, amount));

    const er = ETHRescue.load(txHash.toHex() + "-" + logIndex.toString());

    assert.bigIntEquals(er!.rescuedAt, timestamp);
    assert.stringEquals(er!.stream.toHex(), streamAddress.toHex());
    assert.stringEquals(er!.to.toHex(), to.toHex());
    assert.bigIntEquals(er!.amount, amount);
  });
});
