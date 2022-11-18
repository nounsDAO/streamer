import { StreamCreated } from "../generated/StreamFactory/StreamFactory";
import { Stream } from "../generated/schema";
import { Stream as StreamTemplate } from "../generated/templates";

export function handleStreamCreated(event: StreamCreated): void {
  const stream = new Stream(event.params.streamAddress);

  stream.createdAt = event.block.timestamp;
  stream.createdBy = event.params.msgSender;
  stream.payer = event.params.payer;
  stream.recipient = event.params.recipient;
  stream.tokenAmount = event.params.tokenAmount;
  stream.tokenAddress = event.params.tokenAddress;
  stream.startTime = event.params.startTime;
  stream.stopTime = event.params.stopTime;

  StreamTemplate.create(event.params.streamAddress);

  stream.save();
}
