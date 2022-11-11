import { newMockEvent } from "matchstick-as";
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts";
import { StreamCreated } from "../generated/StreamFactory/StreamFactory";

export function createStreamCreatedEvent(
  payer: Address,
  recipient: Address,
  tokenAmount: BigInt,
  tokenAddress: Address,
  startTime: BigInt,
  stopTime: BigInt,
  streamAddress: Address,
): StreamCreated {
  let newEvent = changetype<StreamCreated>(newMockEvent());
  newEvent.parameters = new Array();

  newEvent.parameters.push(new ethereum.EventParam("payer", ethereum.Value.fromAddress(payer)));
  newEvent.parameters.push(new ethereum.EventParam("recipient", ethereum.Value.fromAddress(recipient)));
  newEvent.parameters.push(new ethereum.EventParam("tokenAmount", ethereum.Value.fromUnsignedBigInt(tokenAmount)));
  newEvent.parameters.push(new ethereum.EventParam("tokenAddress", ethereum.Value.fromAddress(tokenAddress)));
  newEvent.parameters.push(new ethereum.EventParam("startTime", ethereum.Value.fromUnsignedBigInt(startTime)));
  newEvent.parameters.push(new ethereum.EventParam("stopTime", ethereum.Value.fromUnsignedBigInt(stopTime)));
  newEvent.parameters.push(new ethereum.EventParam("streamAddress", ethereum.Value.fromAddress(streamAddress)));

  return newEvent;
}
