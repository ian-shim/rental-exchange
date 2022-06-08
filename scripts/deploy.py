#!/usr/bin/env python3

import os
import sys
import subprocess
import pathlib
import toml
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv())

ALCHEMY_KEY = os.getenv('ALCHEMY_KEY')
PK = os.getenv('PK')
NETWORK = sys.argv[1] if len(sys.argv) > 1 else "mainnet"
rpc_url = f"https://eth-{NETWORK}.alchemyapi.io/v2/{ALCHEMY_KEY}"
config = toml.load("foundry.toml")

ETHERSCAN_KEY = os.getenv('ETHERSCAN_API_KEY')
CHAIN_IDS = {
    'mainnet': 1,
    'ropsten': 3,
    'rinkeby': 4,
    'goerli': 5
}

# TODO: have these constants defined as parameters
PROXY_FACTORY_ADDR = "0x18bef085f6dD4Bf6c23aF90465c91cF68D5B74Cb"
WETH = "0x0Bb7509324cE409F7bbC4b701f932eAca9736AB7"
PROTOCOL_FEE_RECIPIENT = "0x891e3465fCD6A67D13762487D2E326e0bF55De2F"
STRATEGY_EXCHANGE_FEE = "400" # 4%

network = sys.argv[1] if len(sys.argv) > 1 else "mainnet"
chain_id = CHAIN_IDS[network]


def parseAddress(str):
    for substr in str.split():
        if substr.startswith("0x"):
            return substr


def parseDeployedAddress(output):
    for line in output.split("\n"):
        if line.startswith("Deployed to:"):
            return parseAddress(line)

# Parses a compiler version from output of `~/.svm/{solc}/solc-{solc} --version`
# ex: `Version: 0.8.13+commit.abaa5c0e.Darwin.appleclang`
#     => 0.8.13+commit.abaa5c0e
def parseCompilerVersion(output):
    output = output.split()[-1]
    beginningOfCommitSha = output.find('commit') + len('commit') + 1
    endOfCommitSha = output.find('.', beginningOfCommitSha)
    return 'v' + output[:endOfCommitSha]


def deploy_contract(contract, *constructor_args):
    address = ""
    args = [
        "forge", "create", "--rpc-url", rpc_url, "--private-key", PK, contract
    ]
    if len(constructor_args) > 0:
        args += ["--constructor-args", *constructor_args]

    contract_name = contract.split(":")[-1]
    print(f"Deploying {contract_name}...")
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True) as process:
        print("Running {}...".format(process.args))
        for line in process.stdout:
            print(line)
            if line.startswith("Deployed to:"):
                address = parseAddress(line)

    return address


def deploy_contracts():
    print(ALCHEMY_KEY, PK, NETWORK)

    fixedPriceStrategy = deploy_contract(
        "src/strategies/StrategyStandardSaleForFixedPrice.sol:StrategyStandardSaleForFixedPrice", STRATEGY_EXCHANGE_FEE)
    currencyManager = deploy_contract(
        "src/CurrencyManager.sol:CurrencyManager")
    executionManager = deploy_contract(
        "src/ExecutionManager.sol:ExecutionManager")
    receiptToken = deploy_contract("src/ReceiptToken.sol:ReceiptToken")
    exchange = deploy_contract("src/RentalExchange.sol:RentalExchange",
                               currencyManager, executionManager, PROXY_FACTORY_ADDR, receiptToken, WETH, PROTOCOL_FEE_RECIPIENT)

    transferManagerERC721 = deploy_contract(
        "src/transferManagers/TransferManagerERC721.sol:TransferManagerERC721", exchange)
    transferManagerERC1155 = deploy_contract(
        "src/transferManagers/TransferManagerERC1155.sol:TransferManagerERC1155", exchange)
    transferSelector = deploy_contract(
        "src/TransferSelectorNFT.sol:TransferSelectorNFT", transferManagerERC721, transferManagerERC1155)

    print("All contracts deployed.")
    print("1. Transfer ownership of the ReceiptToken to the RentalExchange")
    print("2. Add WETH to CurrencyManager")
    print("3. Add the strategy to ExecutionManager")
    print("4. Add TransferSelectorNFT to the Exchange via `updateTransferSelectorNFT`")
    return {
        'fixedPriceStrategy': fixedPriceStrategy,
        'currencyManager': currencyManager,
        'executionManager': executionManager,
        'receiptToken': receiptToken,
        'exchange': exchange,
        'transferManagerERC721': transferManagerERC721,
        'transferManagerERC1155': transferManagerERC1155,
        'transferSelector': transferSelector
    }


def verify_contract(optimizer_runs, compiler_version, address, contract, encoded_constructor_args=None):
    contract_name = contract.split(":")[-1]
    print(f"Verifying {contract_name}...")
    args = [
        "forge", "verify-contract", "--chain-id", str(
            chain_id), "--num-of-optimizations", str(optimizer_runs),
        "--compiler-version", compiler_version, address, contract
    ]

    if encoded_constructor_args:
        args += ["--constructor-args", encoded_constructor_args]

    guid = ""
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True) as process:
        for line in process.stdout:
            print(line)
            if line.strip().startswith('GUID:'):
                guid = line.split()[-1][1:-1]

    return guid


def verify_contracts(addresses):
    solc = config['default']['solc']
    compiler_version = ""
    with subprocess.Popen([f"./.svm/{solc}/solc-{solc}", "--version"],
                          cwd=pathlib.Path.home(), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True) as process:
        for line in process.stdout:
            print(line)
            if line.startswith("Version:"):
                compiler_version = parseCompilerVersion(line)

    # optimizer = config['default']['optimizer']
    optimizer_runs = config['default']['optimizer_runs']

    print(
        f"chain id: {chain_id}, optimizer_runs: {optimizer_runs}, compiler_version: {compiler_version}")
    guids = {}
    encoded_constructor_args = subprocess.check_output(
        ["cast", "abi-encode", "constructor(uint256)", STRATEGY_EXCHANGE_FEE])
    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['fixedPriceStrategy'], "src/strategies/StrategyStandardSaleForFixedPrice.sol:StrategyStandardSaleForFixedPrice", encoded_constructor_args)
    guids['fixedPriceStrategy'] = guid

    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['currencyManager'], "src/CurrencyManager.sol:CurrencyManager")
    guids['currencyManager'] = guid

    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['executionManager'], "src/ExecutionManager.sol:ExecutionManager")
    guids['executionManager'] = guid

    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['receiptToken'], "src/ReceiptToken.sol:ReceiptToken")
    guids['receiptToken'] = guid

    encoded_constructor_args = subprocess.check_output(
        [
            "cast", "abi-encode", "constructor(address,address,address,address,address,address)",
            addresses['currencyManager'],
            addresses['executionManager'],
            PROXY_FACTORY_ADDR,
            addresses['receiptToken'],
            WETH,
            PROTOCOL_FEE_RECIPIENT,
        ]
    )
    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['exchange'], "src/RentalExchange.sol:RentalExchange", encoded_constructor_args)
    guids['exchange'] = guid

    encoded_constructor_args = subprocess.check_output(
        ["cast", "abi-encode", "constructor(address)", addresses['exchange']])
    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['transferManagerERC721'], "src/transferManagers/TransferManagerERC721.sol:TransferManagerERC721", encoded_constructor_args)
    guids['transferManagerERC721'] = guid

    encoded_constructor_args = subprocess.check_output(
        ["cast", "abi-encode", "constructor(address)", addresses['exchange']])
    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['transferManagerERC1155'], "src/transferManagers/TransferManagerERC1155.sol:TransferManagerERC1155", encoded_constructor_args)
    guids['transferManagerERC1155'] = guid

    encoded_constructor_args = subprocess.check_output(
        ["cast", "abi-encode", "constructor(address,address)", addresses['transferManagerERC721'], addresses['transferManagerERC1155']])
    guid = verify_contract(optimizer_runs, compiler_version,
                           addresses['transferSelector'], "src/TransferSelectorNFT.sol:TransferSelectorNFT", encoded_constructor_args)
    guids['transferSelector'] = guid

    return guids


def check_verfication_status(guids):
    for k, v in guids:
        print(f"Verification status for {k}...")
        args = [
            "forge", "verify-check", "--chain-id", str(
                chain_id), k, ETHERSCAN_KEY
        ]

        with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True) as process:
            for line in process.stdout:
                print(line)


addresses = deploy_contracts()
print(addresses)
# addresses = {}
guids = verify_contracts(addresses)

check_verfication_status(guids)

'''
 forge verify-check --chain-id 5 ageh4lqem6xtugdvaj4kniqxxdyynej2xihxmqtbgbsknjwgml U3R9QJTIJ3WZPTYBQY64YPEZDGM532G2RX
 {'fixedPriceStrategy': '0x21a215e51c496d63b0af33fe268fc1e909de4126', 'currencyManager': '0x3398b3c2fbe099bd27d6120d7602ca146e573d25', 'executionManager': '0xead073b90d88e62400395af2fabd44846f58503a', 'receiptToken': '0xab75d70b5ad20be5a71540519989b4b5290f5fcd', 'exchange': '0x1302727142cefebdf3d781646bd29edb4401af25', 'transferManagerERC721': '0x12d8ec1962251b19ebd19e87b5cc70ee1dd5431f', 'transferManagerERC1155': '0x9820dc28d69282e92f946a3bb2a26683bed5bd0a', 'transferSelector': '0x235512d3c1ad5f555ceab7593969f35d26909dbe'}
 '''
