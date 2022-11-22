import { assert, describe, test, clearStore, afterEach } from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { handleTokensWithdrawn, handleStreamCancelled } from "../src/Stream";
import { createStreamCancelledEvent, createStreamCreatedEvent, createTokensWithdrawnEvent } from "./utils";
import { Cancellation, Stream, Withdrawal } from "../generated/schema";
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
    const payerBalance = BigInt.fromI32(1234);
    const recipientBalance = BigInt.fromI32(4321);

    handleStreamCancelled(
      createStreamCancelledEvent(txHash, logIndex, timestamp, msgSender, streamAddress, payerBalance, recipientBalance),
    );

    const c = Cancellation.load(txHash.toHex() + "-" + logIndex.toString());

    assert.bigIntEquals(c!.cancelledAt, timestamp);
    assert.stringEquals(c!.cancelledBy.toHex(), msgSender.toHex());
    assert.stringEquals(c!.stream.toHex(), streamAddress.toHex());
    assert.bigIntEquals(c!.payerBalance, payerBalance);
    assert.bigIntEquals(c!.recipientBalance, recipientBalance);
  });
});
