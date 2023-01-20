import { log } from "@graphprotocol/graph-ts";
import { TokensWithdrawn, StreamCancelled, TokensRecovered, ETHRescued } from "../generated/templates/Stream/Stream";
import { Withdrawal, Cancellation, TokenRecovery, ETHRescue } from "../generated/schema";

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
  cancellation.recipientBalance = event.params.recipientBalance;

  cancellation.save();
}

export function handleTokensRecovered(event: TokensRecovered): void {
  const tokenRecovery = new TokenRecovery(event.transaction.hash.toHex() + "-" + event.logIndex.toString());

  tokenRecovery.recoveredAt = event.block.timestamp;
  tokenRecovery.stream = event.address;
  tokenRecovery.tokenAddress = event.params.tokenAddress;
  tokenRecovery.amount = event.params.amount;
  tokenRecovery.sentTo = event.params.to;

  tokenRecovery.save();
}

export function handleETHRescued(event: ETHRescued): void {
  const ethRescue = new ETHRescue(event.transaction.hash.toHex() + "-" + event.logIndex.toString());

  ethRescue.rescuedAt = event.block.timestamp;
  ethRescue.stream = event.address;
  ethRescue.to = event.params.to;
  ethRescue.amount = event.params.amount;

  ethRescue.save();
}
