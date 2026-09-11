/**
 * HoneyChain Fabric Gateway — configuration.
 *
 * All secrets come from environment variables. Nothing is hardcoded.
 *
 * Required env vars for a working connection:
 *   FABRIC_PEER_ENDPOINT        e.g. localhost:7051
 *   FABRIC_PEER_HOST_ALIAS      e.g. peer0.org1.example.com
 *   FABRIC_MSP_ID              e.g. Org1MSP
 *   FABRIC_CERT_PATH           path to Admin cert PEM
 *   FABRIC_KEY_PATH            path to Admin private key PEM
 *   FABRIC_TLS_CA_CERT_PATH    path to TLS CA cert PEM
 *   FABRIC_CHANNEL             e.g. mychannel
 *   FABRIC_CHAINCODE           e.g. honeychain
 *
 * Optional:
 *   FABRIC_GATEWAY_PORT         HTTP listen port (default 9443)
 *   FABRIC_ORDERER_ENDPOINT     e.g. localhost:7050
 *   FABRIC_ORDERER_HOST_ALIAS   e.g. orderer.example.com
 *   FABRIC_ORDERER_TLS_CA_CERT  path to orderer TLS CA cert
 */

const fs = require('fs');
const path = require('path');

const ENV = process.env;

const config = {
  peer: {
    endpoint: ENV.FABRIC_PEER_ENDPOINT || '',
    hostAlias: ENV.FABRIC_PEER_HOST_ALIAS || '',
  },
  mspId: ENV.FABRIC_MSP_ID || '',
  identity: {
    certPath: ENV.FABRIC_CERT_PATH || '',
    keyPath: ENV.FABRIC_KEY_PATH || '',
  },
  tls: {
    caCertPath: ENV.FABRIC_TLS_CA_CERT_PATH || '',
  },
  channel: ENV.FABRIC_CHANNEL || 'mychannel',
  chaincode: ENV.FABRIC_CHAINCODE || 'honeychain',
  gatewayPort: parseInt(ENV.FABRIC_GATEWAY_PORT || '9443', 10),
  orderer: {
    endpoint: ENV.FABRIC_ORDERER_ENDPOINT || '',
    hostAlias: ENV.FABRIC_ORDERER_HOST_ALIAS || '',
    tlsCaCertPath: ENV.FABRIC_ORDERER_TLS_CA_CERT || '',
  },
};

function readPem(filePath) {
  if (!filePath) return Buffer.alloc(0);
  const resolved = path.resolve(filePath);
  if (!fs.existsSync(resolved)) {
    throw new Error(`PEM file not found: ${resolved}`);
  }
  return fs.readFileSync(resolved);
}

function validate() {
  const errors = [];
  if (!config.peer.endpoint) errors.push('FABRIC_PEER_ENDPOINT');
  if (!config.peer.hostAlias) errors.push('FABRIC_PEER_HOST_ALIAS');
  if (!config.mspId) errors.push('FABRIC_MSP_ID');
  if (!config.identity.certPath) errors.push('FABRIC_CERT_PATH');
  if (!config.identity.keyPath) errors.push('FABRIC_KEY_PATH');
  if (!config.tls.caCertPath) errors.push('FABRIC_TLS_CA_CERT_PATH');
  if (!config.channel) errors.push('FABRIC_CHANNEL');
  if (!config.chaincode) errors.push('FABRIC_CHAINCODE');
  return errors;
}

module.exports = { config, readPem, validate };
