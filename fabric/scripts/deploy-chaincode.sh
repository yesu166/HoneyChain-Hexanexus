#!/usr/bin/env bash
# deploy-chaincode.sh — package/install/approve/commit the tracer chaincode.
# Requires start-network.sh to have succeeded. NOT executed in this environment.
set -e
cd "$(dirname "$0")/.." || exit 1

CHANNEL_NAME=honeychain
CHAINCODE_NAME=tracer
CHAINCODE_VERSION=1.0
CC_SRC_PATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/chaincode/tracer

ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
ENV_ARGS=(-e CORE_PEER_TLS_ENABLED=true -e "ORDERER_CA=${ORDERER_CA}")
CLI=("docker" "exec" "${ENV_ARGS[@]}" cli)

# ---- package + install (Node chaincode) --------------------------------------
OUT=$("${CLI[@]}" peer lifecycle chaincode package tracer.tar.gz \
  --path "$CC_SRC_PATH" --lang node --label "${CHAINCODE_NAME}_${CHAINCODE_VERSION}")
PKGID=$("${CLI[@]}" peer lifecycle chaincode install tracer.tar.gz \
  | sed -n 's/.*Package ID: \([^,]*\).*/\1/p')
if [ -z "$PKGID" ]; then
  echo "ERROR: could not determine package ID" >&2
  exit 1
fi

# ---- approve + commit ----------------------------------------------------------
"${CLI[@]}" peer lifecycle chaincode approveformyorg -o orderer.example.com:7050 \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --package-id "$PKGID" --sequence 1 --tls --cafile "$ORDERER_CA"

"${CLI[@]}" peer lifecycle chaincode commit -o orderer.example.com:7050 \
  --channelID "$CHANNEL_NAME" --name "$CHAINCODE_NAME" --version "$CHAINCODE_VERSION" \
  --sequence 1 --tls --cafile "$ORDERER_CA"

echo "Chaincode '$CHAINCODE_NAME' committed on '$CHANNEL_NAME'."