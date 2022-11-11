import { StreamCreated } from "../generated/StreamFactory/StreamFactory";
import { Stream } from "../generated/schema";

export function handleStreamCreated(event: StreamCreated): void {
  let s = new Stream(event.params.streamAddress);

  s.payer = event.params.payer;
  s.recipient = event.params.recipient;
  s.tokenAmount = event.params.tokenAmount;
  s.tokenAddress = event.params.tokenAddress;
  s.startTime = event.params.startTime;
  s.stopTime = event.params.stopTime;
  s.cancelled = false;

  s.save();
}
