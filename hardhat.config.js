module.exports = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      }
      // viaIR: true,
      // optimizer: {
      //   enabled: true,
      //   details: {
      //     yulDetails: {
      //       optimizerSteps: "u",
      //     },
      //   },
      // },
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 10000000,
    },
  }
};
