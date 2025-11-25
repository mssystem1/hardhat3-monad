# Monad Fortune Cookies AI · Hardhat 3 + Ignition

[![Solidity](https://img.shields.io/badge/Solidity-0.8.x-363636?logo=solidity)](https://soliditylang.org/)
[![Hardhat](https://img.shields.io/badge/Hardhat-3.x-ffcc00?logo=hardhat)](https://hardhat.org/)
[![Network](https://img.shields.io/badge/Network-Monad_Mainnet-7b3fe4)](https://monad.xyz/)
[![License](https://img.shields.io/badge/License-MIT-informational)](#license)

This repository contains a minimal, production-ready setup for deploying and verifying the **`FortuneCookiesAI`** ERC-721 contract on **Monad mainnet** using:

- **Hardhat 3**  
- **Hardhat Ignition (viem)** for deployment  
- **MonadScan + Sourcify** for verification  
- **OpenZeppelin Contracts** for ERC-721, royalties, etc.

Deployed & verified example:

> **Monad Mainnet**  
> `FortuneCookiesAI` at  
> `0x6AcADd703eE8D45F97bff72609290B0463D6566e`  
> Constructor arg: `"image/png"`

---

## Table of Contents

1. [Project Structure](#project-structure)  
2. [Requirements](#requirements)  
3. [Installation](#installation)  
4. [Environment Variables](#environment-variables)  
5. [Hardhat Configuration](#hardhat-configuration)  
6. [Compilation](#compilation)  
7. [Deployment with Ignition](#deployment-with-ignition)  
8. [Verification on MonadScan](#verification-on-monadscan)  
9. [Useful Commands](#useful-commands)  
10. [Notes & Gotchas](#notes--gotchas)  
11. [License](#license)

---

## Project Structure

Core files relevant to Monad deployment:

```text```
.
├─ contracts/
│  └─ FortuneCookiesAI.sol         # NFT contract
├─ ignition/
│  └─ modules/
│     └─ FortuneCookiesAI.ts       # Ignition deployment module
├─ params/
│  └─ fortuneCookiesAI.json        # Deployment parameters for Ignition
├─ hardhat.config.ts               # Hardhat 3 config (Monad networks + verify)
├─ package.json
├─ tsconfig.json
├─ .gitignore
└─ README.md

## Requirements

** Node.js ≥ 18.x** 

** npm or pnpm or yarn** 

** A funded Monad mainnet EOA private key (MON for gas)** 

** An Etherscan API key (used via Monad’s Etherscan v2 integration)** 

## Installation

Clone the repo and install dependencies:
git clone https://github.com/YOUR_USERNAME/monad-fortune-cookies-hardhat3.git
cd monad-fortune-cookies-hardhat3

npm install
or: pnpm install

## Environment Variables

Create a .env file in the project root:

PRIVATE_KEY=0xyour_monad_mainnet_private_key
ETHERSCAN_API_KEY=your_etherscan_api_key

PRIVATE_KEY – the deployer wallet for Monad networks

ETHERSCAN_API_KEY – standard Etherscan v2 API key (Monad uses it under the hood)

⚠️ Do not commit .env – it’s ignored via .gitignore.

## Hardhat Configuration

hardhat.config.ts is configured for:

**Solidity 0.8.x with optimizer enabled**

**Hardhat network (edr-simulated)**

**Monad Testnet (chainId: 10143)**

**Monad Mainnet (chainId: 143)**

**Built-in Hardhat 3 verification via:**

	Etherscan v2 API (MonadScan)

	Sourcify (MonadVision)

## Compilation

To compile all contracts:
`npx hardhat build`

Artifacts are created under artifacts/ and cache/.

## Deploy to Monad Mainnet

To deploy FortuneCookiesAI to Monad Mainnet (chainId 143):
`npx hardhat ignition deploy ignition/modules/FortuneCookiesAI.ts --network monadMainnet --parameters params/fortuneCookiesAI.json`

## Verification on MonadScan

Once deployed, you can verify the contract on MonadScan (via Etherscan v2) and Sourcify with a single command.

Example: Verify FortuneCookiesAI

`npx hardhat verify 0xyour_smart_contract "image/png" --network monadMainnet`

## Notes & Gotchas

**Windows + Ignition parameters**
The --parameters flag expects a path to a JSON file, not inline JSON.
Using a file (like params/fortuneCookiesAI.json) avoids quoting issues on Windows shells.

**Do not commit secrets**

.env contains your private key and API key

**It’s ignored via .gitignore by default**

Multiple networks
The same project can deploy to both monadTestnet and monadMainnet using the same Ignition module; just switch --network.

## License

This project is licensed under the MIT License.
You’re free to use, modify, and distribute it as part of your own Monad / DeFi / NFT infrastructure.

