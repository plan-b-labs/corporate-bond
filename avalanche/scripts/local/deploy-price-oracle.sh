#!/bin/bash

# Check if blockchain name is provided
if [ $# -ne 1 ]; then
  echo "Usage: $0 <blockchain-name>"
  exit 1
fi

EWOQ_ADDRESS=0x8db97C7cEcE249c2b98bDC0226Cc4C2A57BF52FC
EWOQ_PRIVATE_KEY=0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027
BLOCKCHAIN_NAME=$1
C_CHAIN_RPC_URL=http://127.0.0.1:9650/ext/bc/C/rpc
C_CHAIN_EVM_CHAIN_ID=1337
C_CHAIN_BLOCKCHAIN_ID_HEX=0x0a19dff4513d7c6dae8a199295fa48ec5c07b6b8cd4ca169cec4c930bb024060
C_CHAIN_ICM_REGISTRY_ADDRESS=0x17aB05351fC94a1a67Bf3f56DdbB941aE6c63E25

# Get blockchain IDs
BLOCKCHAIN_ID=$(avalanche blockchain describe "$BLOCKCHAIN_NAME" | grep 'BlockchainID (CB58)' | grep -oP '\w{48,49}')
BLOCKCHAIN_ID_HEX=$(avalanche blockchain describe "$BLOCKCHAIN_NAME" | grep 'BlockchainID (HEX)' | grep -oP '0x[a-fA-F0-9]{64}')
BLOCKCHAIN_EVM_CHAIN_ID=$(avalanche blockchain describe "$BLOCKCHAIN_NAME" | grep 'ChainID' | grep -oP '\d+')
BLOCKCHAIN_ICM_REGISTRY_ADDRESS=$(avalanche blockchain describe "$BLOCKCHAIN_NAME" | grep 'ICM Registry' | grep -oP '0x[a-fA-F0-9]{40}')
BLOCKCHAIN_RPC_URL=$(avalanche blockchain describe "$BLOCKCHAIN_NAME" | grep 'RPC Endpoint' | grep -oP 'https?://[^ ]+')
if [ -z "$BLOCKCHAIN_ID" ] || [ -z "$BLOCKCHAIN_ID_HEX" ] || [ -z "$BLOCKCHAIN_ICM_REGISTRY_ADDRESS" ] || [ -z "$BLOCKCHAIN_EVM_CHAIN_ID" ]; then
  echo "Error: Could not get blockchain information for $BLOCKCHAIN_NAME"
  exit 1
fi

# Deploy mock V3 aggregator on the C-Chain
echo "Deploying MockV3Aggregator on C-Chain..."
forge script script/PriceOracle/DeployMockV3Aggregator.s.sol:DeployMockV3Aggregator \
  --rpc-url "$C_CHAIN_RPC_URL" \
  --sig "run(uint8,int256)" \
  8 \
  9500000000000 \
  --private-key "$EWOQ_PRIVATE_KEY" \
  --broadcast

MOCK_V3_AGGREGATOR_ADDRESS=$(jq -r '.receipts[0].contractAddress' "broadcast/DeployMockV3Aggregator.s.sol/${C_CHAIN_EVM_CHAIN_ID}/run-latest.json")

# Deploy Chainlink price feed scraper on the C-Chain
echo "Deploying ChainlinkPriceFeedScraper on C-Chain..."
forge script script/PriceOracle/DeployChainlinkPriceFeedScraper.s.sol:DeployChainlinkPriceFeedScraper \
  --rpc-url "$C_CHAIN_RPC_URL" \
  --sig "run(address,uint256,address,address)" \
  "$C_CHAIN_ICM_REGISTRY_ADDRESS" \
  1 \
  "$EWOQ_ADDRESS" \
  "$MOCK_V3_AGGREGATOR_ADDRESS" \
  --private-key "$EWOQ_PRIVATE_KEY" \
  --broadcast

CHAINLINK_PRICE_FEED_SCRAPER_ADDRESS=$(jq -r '.receipts[0].contractAddress' "broadcast/DeployChainlinkPriceFeedScraper.s.sol/${C_CHAIN_EVM_CHAIN_ID}/run-latest.json")

# Deploy Chainlink price feed proxy on the $BLOCKCHAIN_NAME
echo "Deploying ChainlinkPriceFeedProxy on $BLOCKCHAIN_NAME..."
forge script script/PriceOracle/DeployChainlinkPriceFeedProxy.s.sol:DeployChainlinkPriceFeedProxy \
  --rpc-url "$BLOCKCHAIN_RPC_URL" \
  --sig "run(address,uint256,address,bytes32,address,string,uint8)" \
  "$BLOCKCHAIN_ICM_REGISTRY_ADDRESS" \
  1 \
  "$EWOQ_ADDRESS" \
  "$C_CHAIN_BLOCKCHAIN_ID_HEX" \
  "$CHAINLINK_PRICE_FEED_SCRAPER_ADDRESS" \
  "Proxied Price Feed" \
  8 \
  --private-key "$EWOQ_PRIVATE_KEY" \
  --broadcast

CHAINLINK_PRICE_FEED_PROXY_ADDRESS=$(jq -r '.receipts[0].contractAddress' "broadcast/DeployChainlinkPriceFeedProxy.s.sol/${BLOCKCHAIN_EVM_CHAIN_ID}/run-latest.json")

# Print all deployed contract addresses
echo "Deployed contract addresses:"
echo "- MockV3Aggregator: $MOCK_V3_AGGREGATOR_ADDRESS"
echo "- ChainlinkPriceFeedScraper: $CHAINLINK_PRICE_FEED_SCRAPER_ADDRESS"
echo "- ChainlinkPriceFeedProxy: $CHAINLINK_PRICE_FEED_PROXY_ADDRESS"
