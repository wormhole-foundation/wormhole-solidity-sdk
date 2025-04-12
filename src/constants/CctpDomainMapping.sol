// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

import {
  CCTP_DOMAIN_ETHEREUM,
  CCTP_DOMAIN_AVALANCHE,
  CCTP_DOMAIN_OPTIMISM,
  CCTP_DOMAIN_ARBITRUM,
  CCTP_DOMAIN_SOLANA,
  CCTP_DOMAIN_BASE,
  CCTP_DOMAIN_POLYGON,
  CCTP_DOMAIN_SUI,
  CCTP_DOMAIN_APTOS,
  CCTP_DOMAIN_UNICHAIN,
  CCTP_DOMAIN_SEPOLIA,
  CCTP_DOMAIN_OPTIMISM_SEPOLIA,
  CCTP_DOMAIN_ARBITRUM_SEPOLIA,
  CCTP_DOMAIN_BASE_SEPOLIA
} from "wormhole-sdk/constants/CctpDomains.sol";

import {
  CHAIN_ID_ETHEREUM,
  CHAIN_ID_AVALANCHE,
  CHAIN_ID_OPTIMISM,
  CHAIN_ID_ARBITRUM,
  CHAIN_ID_SOLANA,
  CHAIN_ID_BASE,
  CHAIN_ID_POLYGON,
  CHAIN_ID_SUI,
  CHAIN_ID_APTOS,
  CHAIN_ID_UNICHAIN,
  CHAIN_ID_SEPOLIA,
  CHAIN_ID_OPTIMISM_SEPOLIA,
  CHAIN_ID_ARBITRUM_SEPOLIA,
  CHAIN_ID_BASE_SEPOLIA
} from "wormhole-sdk/constants/Chains.sol";

//noble (cctp domain 4) is not supported

//use uint256 as array of chain ids i.e. uint16s
//naming is slightly inaccurate because NOBLE is skipped and Aptos is not supported
uint256 constant MAINNET_CCTP_DOMAIN_TO_CHAIN_ID =
  (uint(CHAIN_ID_ETHEREUM ) << 16 * CCTP_DOMAIN_ETHEREUM ) +
  (uint(CHAIN_ID_AVALANCHE) << 16 * CCTP_DOMAIN_AVALANCHE) +
  (uint(CHAIN_ID_OPTIMISM ) << 16 * CCTP_DOMAIN_OPTIMISM ) +
  (uint(CHAIN_ID_ARBITRUM ) << 16 * CCTP_DOMAIN_ARBITRUM ) +
  (uint(CHAIN_ID_SOLANA   ) << 16 * CCTP_DOMAIN_SOLANA   ) +
  (uint(CHAIN_ID_BASE     ) << 16 * CCTP_DOMAIN_BASE     ) +
  (uint(CHAIN_ID_POLYGON  ) << 16 * CCTP_DOMAIN_POLYGON  ) +
  (uint(CHAIN_ID_SUI      ) << 16 * CCTP_DOMAIN_SUI      ) +
  (uint(CHAIN_ID_APTOS    ) << 16 * CCTP_DOMAIN_APTOS    ) +
  (uint(CHAIN_ID_UNICHAIN ) << 16 * CCTP_DOMAIN_UNICHAIN );

uint256 constant TESTNET_CCTP_DOMAIN_TO_CHAIN_ID =
  (uint(CHAIN_ID_SEPOLIA         ) << 16 * CCTP_DOMAIN_SEPOLIA         ) +
  (uint(CHAIN_ID_AVALANCHE       ) << 16 * CCTP_DOMAIN_AVALANCHE       ) +
  (uint(CHAIN_ID_OPTIMISM_SEPOLIA) << 16 * CCTP_DOMAIN_OPTIMISM_SEPOLIA) +
  (uint(CHAIN_ID_ARBITRUM_SEPOLIA) << 16 * CCTP_DOMAIN_ARBITRUM_SEPOLIA) +
  (uint(CHAIN_ID_SOLANA          ) << 16 * CCTP_DOMAIN_SOLANA          ) +
  (uint(CHAIN_ID_BASE_SEPOLIA    ) << 16 * CCTP_DOMAIN_BASE_SEPOLIA    ) +
  (uint(CHAIN_ID_POLYGON         ) << 16 * CCTP_DOMAIN_POLYGON         ) +
  (uint(CHAIN_ID_SUI             ) << 16 * CCTP_DOMAIN_SUI             ) +
  (uint(CHAIN_ID_APTOS           ) << 16 * CCTP_DOMAIN_APTOS           ) +
  (uint(CHAIN_ID_UNICHAIN        ) << 16 * CCTP_DOMAIN_UNICHAIN        );

function mainnetCctpDomainToChainId(uint cctpDomain) pure returns (uint16) { unchecked {
  return uint16(MAINNET_CCTP_DOMAIN_TO_CHAIN_ID >> (cctpDomain * 16));
}}

function testnetCctpDomainToChainId(uint cctpDomain) pure returns (uint16) { unchecked {
  return uint16(TESTNET_CCTP_DOMAIN_TO_CHAIN_ID >> (cctpDomain * 16));
}}
