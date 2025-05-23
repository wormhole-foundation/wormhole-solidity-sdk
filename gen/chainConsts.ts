import { toCapsSnakeCase } from "./utils";
import {
  platformToChains,
  contracts,
  rpc,
  circle,
} from "@wormhole-foundation/sdk-base";
import { EvmAddress } from "@wormhole-foundation/sdk-evm";

const {coreBridge, tokenBridge, relayer, circleContracts} = contracts;
const {usdcContract, circleChainId} = circle;

console.log(
`// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

// ╭──────────────────────────────────────╮
// │ Auto-generated by gen/chainConsts.ts │
// ╰──────────────────────────────────────╯

// This file contains 2 libraries and an associated set of free standing functions:
//
// The libraries:
//  1. MainnetChainConstants
//  2. TestnetChainConstants
//
// Both provide the same set of functions, which are also provided as free standing functions
//   with an additional network parameter, though library functions use an underscore prefix to
//   avoid a declaration shadowing bug that has been first reported in the solc Github in 2020...
//   see https://github.com/ethereum/solidity/issues/10155
//
//          Function        │ Parameter │  Returns
//  ────────────────────────┼───────────┼────────────
//   chainName              │  chainId  │  string
//   defaultRPC             │  chainId  │  string
//   coreBridge             │  chainId  │  address
//   tokenBridge            │  chainId  │  address
//   wormholeRelayer        │  chainId  │  address
//   cctpDomain             │  chainId  │ cctpDomain
//   usdc                   │  chainId  │  address
//   cctpMessageTransmitter │  chainId  │  address
//   cctpTokenMessenger     │  chainId  │  address
//
// Empty fields return invalid values (empty string, address(0), INVALID_CCTP_DOMAIN)

import "wormhole-sdk/constants/Chains.sol";
import "wormhole-sdk/constants/CctpDomains.sol";

uint32 constant INVALID_CCTP_DOMAIN = type(uint32).max;
error UnsupportedChainId(uint16 chainId);
error UnsupportedCctpDomain(uint32 cctpDomain);
`
);

const evmChains = platformToChains("Evm");
type EvmChain = typeof evmChains[number];
const networks = ["Mainnet", "Testnet"] as const;

const networkChains = {
  Mainnet: evmChains.filter(chain =>
    contracts.coreBridge.has("Mainnet", chain)),
  //remove testnets that were superseded by Sepolia testnets
  Testnet: evmChains.filter(chain =>
    contracts.coreBridge.has("Testnet", chain) &&
    chain !== "Ethereum" &&
    !evmChains.includes(chain + "Sepolia" as EvmChain)
  )
}

enum AliasType {
  String     = "string",
  Address    = "address",
  CctpDomain = "uint32",
}

const emptyValue = {
  [AliasType.String    ]: "",
  [AliasType.Address   ]: "address(0)",
  [AliasType.CctpDomain]: "INVALID_CCTP_DOMAIN",
}

const returnParam = (aliasType: AliasType) =>
  aliasType === AliasType.String ? "string memory" : aliasType;

const toReturnValue = (value: string, returnType: AliasType) => {
  if (returnType === AliasType.Address && value)
    return new EvmAddress(value).toString(); //ensures checksum format
  
  const ret = value || emptyValue[returnType];
  return returnType === AliasType.String
    ? `\"${ret}\"`
    : ret;
}

const functions = [
  ["chainName",              AliasType.String    ],
  ["defaultRPC",             AliasType.String    ],
  ["coreBridge",             AliasType.Address   ],
  ["tokenBridge",            AliasType.Address   ],
  ["wormholeRelayer",        AliasType.Address   ],
  ["cctpDomain",             AliasType.CctpDomain],
  ["usdc",                   AliasType.Address   ],
  ["cctpMessageTransmitter", AliasType.Address   ],
  ["cctpTokenMessenger",     AliasType.Address   ],
] as const;

const indent = (lines: string[]) => lines.map(line => `  ${line}`);

console.log(
  functions.map(([name, returnType]) => [
      `function ${name}(bool mainnet, uint16 chainId)` +
        ` pure returns (${returnParam(returnType)}) {`,
      ...indent([
        `return mainnet`,
        `  ? MainnetChainConstants._${name}(chainId)`,
        `  : TestnetChainConstants._${name}(chainId);`,
      ]),
      `}`
    ].join("\n")
  ).join("\n\n")
);

for (const network of networks) {
  const functionDefinition = (
    name: string,
    returnType: AliasType,
    mapping: (chain: EvmChain) => string,
  ) => indent([
    `function _${name}(uint16 chainId) internal pure returns (${returnParam(returnType)}) {`,
    ...indent([
      ...networkChains[network].map(chain => [
        `if (chainId == CHAIN_ID_${toCapsSnakeCase(chain)})`,
        `  return ${toReturnValue(mapping(chain), returnType)};`
      ]).flat(),
      `revert UnsupportedChainId(chainId);`
    ]),
    `}`
  ]).join("\n");

  const cctpDomainConst = (chain: EvmChain) =>
    circleChainId.has(network, chain)
      ? `CCTP_DOMAIN_${toCapsSnakeCase(chain)}`
      : "INVALID_CCTP_DOMAIN";

  const mappings = {
    chainName:              chain => chain,
    defaultRPC:             chain => rpc.rpcAddress(network, chain),
    coreBridge:             chain => coreBridge.get(network, chain),
    tokenBridge:            chain => tokenBridge.get(network, chain),
    wormholeRelayer:        chain => relayer.get(network, chain),
    cctpDomain:             chain => cctpDomainConst(chain),
    usdc:                   chain => usdcContract.get(network, chain),
    cctpMessageTransmitter: chain => circleContracts.get(network, chain)?.messageTransmitter,
    cctpTokenMessenger:     chain => circleContracts.get(network, chain)?.tokenMessenger,
  };

  console.log([
      ``,
      `library ${network}ChainConstants {`,
      functions
        .map(([name, returnType]) => functionDefinition(name, returnType, mappings[name]))
        .join("\n\n"),
      `}`
    ].join("\n")
  );
}
