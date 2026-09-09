#!/usr/bin/env bash
# start-network.sh — bootstrap the local Fabric 2.5 network:
#  1. generate MSP (cryptogen) + genesis/channel tx (configtxgen) via the CLI container
#  2. start orderer + peer
#  3. join the orderer to the 'honeychain' channel (osnadmin) and the peer to it
# Requires a running Docker daemon + the fabric-tools image. NOT executed here.
set -e
cd "$(dirname "$0")/.." || exit 1

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker daemon is not running." >&2
  exit 1
fi

CHANNEL_NAME=honeychain
CLI="docker exec cli"
CLI_PEER=/opt/gopath/src/github.com/hyperledger/fabric/peer

# ---- 1. MSP material -------------------------------------------------------
mkdir -p crypto-config _artifacts
docker run --rm -v "$PWD":/work -w /work hyperledger/fabric-tools:2.5 \
  cryptogen generate --config=crypto-config.yaml --output=crypto-config

# ---- 2. Genesis + channel tx -------------------------------------------------
docker run --rm -v "$PWD":/work -w /work hyperledger/fabric-tools:2.5 \
  configtxgen -profile Genesis -channelID sys-channel -outputBlock _artifacts/genesis.block -configPath .
docker run --rm -v "$PWD":/work -w /work hyperledger/fabric-tools:2.5 \
  configtxgen -profile Honeychain -channelID "$CHANNEL_NAME" \
  -outputCreateChannelTx _artifacts/channel.tx -configPath .

# ---- 3. Start orderer + peer -------------------------------------------------
docker compose -f docker-compose.yaml up -d
sleep 8

# ---- 4. Join orderer to the channel (Fabric 2.5 channel participation) ------
docker run --rm -v "$PWD":/work -w /work --network honeychain_fabric \
  hyperledger/fabric-tools:2.5 osnadmin channel join \
  --channelID "$CHANNEL_NAME" \
  --config-block /work/_artifacts/genesis.block \
  -o orderer.example.com:7053 \
  --ca-file /work/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/ca.crt \
  --client-cert /work/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.crt \
  --client-key  /work/crypto-config/ordererOrganizations/example.com/orderers/orderer.example.com/tls/server.key

# ---- 5. Create channel block + join peer ---------------------------------------
$CLI peer channel create -o orderer.example.com:7050 \
  -c "$CHANNEL_NAME" -f "$CLI_PEER/artifacts/channel.tx" \
  --tls --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

$CLI peer channel join -b "${CHANNEL_NAME}.block" --tls \
  --cafile /opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

echo "Network up: channel '$CHANNEL_NAME' created and joined."