import { newMockEvent } from "matchstick-as";
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts";
import { StreamCreated } from "../generated/StreamFactory/StreamFactory";
import { TokensWithdrawn, StreamCancelled } from "../generated/templates/Stream/Stream";

export function createStreamCreatedEvent(
  createdAt: BigInt,
  msgSender: Address,
  payer: Address,
  recipient: Address,
  tokenAmount: BigInt,
  tokenAddress: Address,
  startTime: BigInt,
  stopTime: BigInt,
  streamAddress: Address,
): StreamCreated {
  let newEvent = changetype<StreamCreated>(newMockEvent());

  newEvent.block.timestamp = createdAt;

  newEvent.parameters = new Array();
  newEvent.parameters.push(new ethereum.EventParam("msgSender", ethereum.Value.fromAddress(msgSender)));
  newEvent.parameters.push(new ethereum.EventParam("payer", ethereum.Value.fromAddress(payer)));
  newEvent.parameters.push(new ethereum.EventParam("recipient", ethereum.Value.fromAddress(recipient)));
  newEvent.parameters.push(new ethereum.EventParam("tokenAmount", ethereum.Value.fromUnsignedBigInt(tokenAmount)));
  newEvent.parameters.push(new ethereum.EventParam("tokenAddress", ethereum.Value.fromAddress(tokenAddress)));
  newEvent.parameters.push(new ethereum.EventParam("startTime", ethereum.Value.fromUnsignedBigInt(startTime)));
  newEvent.parameters.push(new ethereum.EventParam("stopTime", ethereum.Value.fromUnsignedBigInt(stopTime)));
  newEvent.parameters.push(new ethereum.EventParam("streamAddress", ethereum.Value.fromAddress(streamAddress)));

  return newEvent;
}

export function createStreamCancelledEvent(
  txHash: Bytes,
  logIndex: BigInt,
  timestamp: BigInt,
  msgSender: Address,
  stream: Address,
  payerBalance: BigInt,
  recipientBalance: BigInt,
): StreamCancelled {
  let newEvent = changetype<StreamCancelled>(newMockEvent());

  newEvent.transaction.hash = txHash;
  newEvent.logIndex = logIndex;
  newEvent.block.timestamp = timestamp;
  newEvent.address = stream;

  newEvent.parameters = new Array();
  newEvent.parameters.push(new ethereum.EventParam("msgSender", ethereum.Value.fromAddress(msgSender)));
  newEvent.parameters.push(
    new ethereum.EventParam(
      "payer",
      ethereum.Value.fromAddress(Address.fromString("0x0000000000000000000000000000000000000000")),
    ),
  );
  newEvent.parameters.push(
    new ethereum.EventParam(
      "recipient",
      ethereum.Value.fromAddress(Address.fromString("0x0000000000000000000000000000000000000000")),
    ),
  );
  newEvent.parameters.push(new ethereum.EventParam("payerBalance", ethereum.Value.fromUnsignedBigInt(payerBalance)));
  newEvent.parameters.push(
    new ethereum.EventParam("recipientBalance", ethereum.Value.fromUnsignedBigInt(recipientBalance)),
  );

  return newEvent;
}

export function createTokensWithdrawnEvent(
  txHash: Bytes,
  logIndex: BigInt,
  timestamp: BigInt,
  msgSender: Address,
  stream: Address,
  amount: BigInt,
): TokensWithdrawn {
  let newEvent = changetype<TokensWithdrawn>(newMockEvent());

  newEvent.transaction.hash = txHash;
  newEvent.logIndex = logIndex;
  newEvent.block.timestamp = timestamp;
  newEvent.address = stream;

  newEvent.parameters = new Array();
  newEvent.parameters.push(new ethereum.EventParam("msgSender", ethereum.Value.fromAddress(msgSender)));
  newEvent.parameters.push(
    new ethereum.EventParam(
      "recipient",
      ethereum.Value.fromAddress(Address.fromString("0x0000000000000000000000000000000000000000")),
    ),
  );
  newEvent.parameters.push(new ethereum.EventParam("amount", ethereum.Value.fromUnsignedBigInt(amount)));

  return newEvent;
}
