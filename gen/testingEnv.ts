import * as base from "@wormhole-foundation/sdk-base";
import * as tokens from "@wormhole-foundation/sdk-base/tokens";

function errorExit(reason: string): never {
  console.error(reason);
  process.exit(1);
}

if (process.argv.length != 4)
  errorExit("Usage: <network (e.g. Mainnet)> <chain (e.g. Ethereum)>");

const network = (() => {
  const network = process.argv[2];
  if (!base.network.isNetwork(network))
    errorExit(`Invalid network: ${network}`);

  return network;
})();

const chain = (() => {
  const chain = process.argv[3];
  if (!base.chain.isChain(chain))
    errorExit(`Invalid chain: ${chain}`);

  return chain;
})();

const testVars = ([
  ["RPC_URL", base.rpc.rpcAddress(network, chain)],
  ["USDC_ADDRESS", base.circle.usdcContract.get(network, chain)],
  [
    "CCTP_TOKEN_MESSENGER_ADDRESS",
    base.contracts.circleContracts.get(network, chain)?.tokenMessenger
  ],
  [
    "CCTP_MESSAGE_TRANSMITTER_ADDRESS",
    base.contracts.circleContracts.get(network, chain)?.messageTransmitter
  ],
  [
    "WNATIVE_ADDRESS",
    tokens.getTokenByKey(network, chain, tokens.getNative(network, chain)?.wrappedKey)?.address
  ],
  ["WORMHOLE_ADDRESS", base.contracts.coreBridge.get(network, chain)],
  ["TOKEN_BRIDGE_ADDRESS", base.contracts.tokenBridge.get(network, chain)]
] as const satisfies [string, string | undefined][]).map(([varName, val]) => {
  if (!val)
    errorExit(`No value for ${varName} for ${network} ${chain}`);

  return `TEST_${varName}=${val}`;
});

console.log(testVars.join("\n"));
