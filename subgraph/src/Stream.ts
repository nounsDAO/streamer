import { log } from "@graphprotocol/graph-ts";
import { TokensWithdrawn, StreamCancelled } from "../generated/templates/Stream/Stream";
import { Stream, Withdrawal } from "../generated/schema";

export function handleTokensWithdrawn(event: TokensWithdrawn): void {
  let withdrawal = new Withdrawal(event.transaction.hash.toHex() + "-" + event.logIndex.toString());
  withdrawal.stream = event.address;
  withdrawal.amount = event.params.amount;
  withdrawal.save();
}

export function handleStreamCancelled(event: StreamCancelled): void {
  let s = Stream.load(event.address);
  if (s == null) {
    log.error("Stream not found: {}", [event.address.toString()]);
    return;
  }

  s.cancelled = true;
  s.cancelledAt = event.block.timestamp;

  s.save();
}
