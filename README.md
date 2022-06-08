# RentalExchange

Smart contracts for NFT rental exchange. 

_WARNING: This code has not been comprehensively tested or audited. The author is not responsible for any loss of funds. Meanwhile, please open an issue or a PR if you find any bugs or vulnerabilities._

# Contracts

- `RentalExchange.sol` \
Exchange contracts that faciliates an order matching given a signed maker order and a fulfilling taker order. 

- `CurrencyManager.sol` \
Manages currencies that can be used to fulfill orders (ex. WETH). 

- `ExecutionManager.sol` \
Manages order matching strategies (ex. Fixed price sale, Dutch auction).

- `ReceiptToken.sol` \
An ERC721 token that represents a receipt for a borrowed asset. Encodes the asset, borrower, and rental expiration. A lender uses this receipt to claim and retrieve the lent asset upon the expiry. 

- `TransferSelectorNFT.sol` \
Helper contract that returns appropriate `TransferManager` given a collection (NFT) contract.

- `TransferManagerERCxxx.sol` \
Facilitates an actual NFT transfer.

# Deployed Contract Addresses
## RentalExchange
mainnet: \
goerli: [0x1302727142cEfebDf3d781646bd29EDb4401Af25](https://goerli.etherscan.io/address/0x1302727142cefebdf3d781646bd29edb4401af25)

## CurrencyManager
mainnet: \
goerli: [0x3398B3C2FbE099Bd27D6120d7602CA146e573d25](https://goerli.etherscan.io/address/0x3398b3c2fbe099bd27d6120d7602ca146e573d25)

## ExecutionManager
mainnet: \
goerli: [0xead073B90d88e62400395AF2FaBd44846f58503a](https://goerli.etherscan.io/address/0xead073b90d88e62400395af2fabd44846f58503a)

## ReceiptToken
mainnet: \
goerli: [0xaB75D70b5Ad20bE5A71540519989B4b5290f5Fcd](https://goerli.etherscan.io/address/0xab75d70b5ad20be5a71540519989b4b5290f5fcd)

## TransferSelectorNFT
mainnet: \
goerli: [0x235512d3C1Ad5f555CEaB7593969f35D26909Dbe](https://goerli.etherscan.io/address/0x235512d3c1ad5f555ceab7593969f35d26909dbe)

## TransferManagerERC721
mainnet: \
goerli: [0x12D8eC1962251B19Ebd19e87B5cc70ee1Dd5431F](https://goerli.etherscan.io/address/0x12d8ec1962251b19ebd19e87b5cc70ee1dd5431f)

## TransferManagerERC1155
mainnet: \
goerli: [0x9820dC28d69282e92f946a3bB2a26683BeD5Bd0a](https://goerli.etherscan.io/address/0x9820dc28d69282e92f946a3bb2a26683bed5bd0a)

# Usage

## Install [Foundry](https://github.com/foundry-rs/foundry)
Download `foundryup`:
```
$ curl -L https://foundry.paradigm.xyz | bash
```
Then install Foundry:
```
$ foundryup
```

Clone the repo:
```
$ git clone https://github.com/ian-shim/rental-exchange.git
```

## Running tests
Unit tests:
```
$ forge test [-vvvv]
```

Integration tests require forking mode: \
(_integration tests fork and use actual deployed contracts. Make sure the deployed addresses in the tests are correct_)
```
$ forge test --fork-url <NODE_URL> --chain-id <CHAIN_ID> --etherscan-api-key <ETHERSCAN_KEY>
```
