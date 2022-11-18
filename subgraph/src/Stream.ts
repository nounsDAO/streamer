import { log } from "@graphprotocol/graph-ts";
import { TokensWithdrawn, StreamCancelled } from "../generated/templates/Stream/Stream";
import { Withdrawal, Cancellation } from "../generated/schema";

export function handleTokensWithdrawn(event: TokensWithdrawn): void {
  const withdrawal = new Withdrawal(event.transaction.hash.toHex() + "-" + event.logIndex.toString());

  withdrawal.withdrawnAt = event.block.timestamp;
  withdrawal.executedBy = event.params.msgSender;
  withdrawal.stream = event.address;
  withdrawal.amount = event.params.amount;

  withdrawal.save();
}

export function handleStreamCancelled(event: StreamCancelled): void {
  const cancellation = new Cancellation(event.transaction.hash.toHex() + "-" + event.logIndex.toString());

  cancellation.cancelledAt = event.block.timestamp;
  cancellation.cancelledBy = event.params.msgSender;
  cancellation.stream = event.address;
  cancellation.payerBalance = event.params.payerBalance;
  cancellation.recipientBalance = event.params.recipientBalance;

  cancellation.save();
}
