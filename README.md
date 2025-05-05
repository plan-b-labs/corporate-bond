# Plan B Corporate Bond Protocol

A protocol for issuing and managing corporate bonds on the Plan B L1.

## Components

### Corporate Bond System

- `CorporateBondNFT`: ERC721 token representing ownership of corporate bonds
- `CorporateBondRepayVault`: Manages bond repayments and fees
- `CorporateBondRepayVaultFactory`: Creates new repayment vaults for bonds

### Price Oracle System

The protocol includes a cross-chain price oracle system using Chainlink and ICM (Inter-Chain Messaging):

- `ChainlinkPriceFeedScraper`: Reads price data from Chainlink feeds and sends it to other chains via ICM
- `ChainlinkPriceFeedProxy`: Receives price data via ICM and exposes it through the standard Chainlink interface

This allows the protocol to access price feeds that may only exist on specific chains while maintaining Chainlink's standard interface for price consumption.

## Development

### Prerequisites

- Foundry
- Avalanche CLI

### Installation

```bash
forge install
```

### Testing

```bash
forge test
```

### Deployment

#### Local

To bootstrap a local Avalanche network, run the following commands:

```bash
# Import the Plan B blockchain configuration
avalanche blockchain import file ./avalanche/blockchains/planb.json

# Deploy the Plan B blockchain
avalanche blockchain deploy PlanB --local
```

For local deployment of the price oracle system:

```bash
./avalanche/scripts/local/deploy-price-oracle.sh PlanB
```

Test the price oracle system:

```bash
# Define environment variables
PLANB_RPC_URL=$(avalanche blockchain describe PlanB | grep 'RPC Endpoint' | grep -oP 'https?://[^ ]+')
PLANB_BLOCKCHAIN_ID_HEX=$(avalanche blockchain describe PlanB | grep 'BlockchainID (HEX)' | grep -oP '0x[a-fA-F0-9]{64}')
PRICE_FEED_ADDRESS=0xa4cd3b0eb6e5ab5d8ce4065bccd70040adab1f00
PRICE_FEED_SCRAPER_ADDRESS=0xa4dff80b4a1d748bf28bc4a271ed834689ea3407
PRICE_FEED_PROXY_ADDRESS=0xa4cd3b0eb6e5ab5d8ce4065bccd70040adab1f00
FEE_TOKEN_ADDRESS=0x0000000000000000000000000000000000000000

# Get the latest round data from the price feed on the C-Chain
cast call $PRICE_FEED_ADDRESS \
  'latestRoundData()(uint80,int256,uint256,uint256,uint80)' \
  --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc

# Check that the price feed scraper is able to read the latest round data from the price feed on the C-Chain
cast call $PRICE_FEED_SCRAPER_ADDRESS \
  'getLatestRoundData()(uint80,int256,uint256,uint256,uint80)' \
  --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc

# Check the latest round data value of the price feed proxy on PlanB (zero after deployment)
cast call $PRICE_FEED_PROXY_ADDRESS \
  'latestRoundData()(uint80,int256,uint256,uint256,uint80)' \
  --rpc-url "$PLANB_RPC_URL"

# Send the latest round data with the price feed scraper to the price feed proxy on PlanB
cast send "$PRICE_FEED_SCRAPER_ADDRESS" \
  'sendLatestRoundData(bytes32,address,address,uint256,uint256)(bytes32)' \
  "$PLANB_BLOCKCHAIN_ID_HEX" \
  "$PRICE_FEED_PROXY_ADDRESS" \
  "$FEE_TOKEN_ADDRESS" \
  0 \
  200000 \
  --rpc-url http://127.0.0.1:9650/ext/bc/C/rpc \
  --private-key '0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027'

# Check that the price feed has been updated in the price feed proxy on PlanB
cast call $PRICE_FEED_PROXY_ADDRESS \
  'latestRoundData()(uint80,int256,uint256,uint256,uint80)' \
  --rpc-url "$PLANB_RPC_URL"
```

## License

MIT License
