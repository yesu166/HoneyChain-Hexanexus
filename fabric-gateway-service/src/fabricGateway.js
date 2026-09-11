/**
 * Fabric Gateway connection manager.
 *
 * Uses the official @hyperledger/fabric-gateway SDK to connect to a
 * running Fabric peer via the Fabric Gateway service (port 7051+).
 *
 * Identity: Org1 Admin MSP (loaded from PEM files on disk).
 * Network topology: direct peer connection (no load balancer).
 */

const grpc = require('@grpc/grpc-js');
const crypto = require('node:crypto');
const { connect, hash, signers } = require('@hyperledger/fabric-gateway');
const { config, readPem } = require('./config');

let _client = null;
let _gateway = null;
let _network = null;
let _contract = null;
let _connected = false;

/**
 * Establish a gRPC connection to the Fabric peer and create a gateway.
 *
 * @returns {{ connected: boolean, error: string|null }}
 */
function connectGateway() {
  if (_connected && _contract) {
    return { connected: true, error: null };
  }

  try {
    const tlsCert = readPem(config.tls.caCertPath);
    const certPem = readPem(config.identity.certPath);
    const keyPem = readPem(config.identity.keyPath);

    const tlsCredentials = grpc.credentials.createSsl(tlsCert);

    _client = new grpc.Client(config.peer.endpoint, tlsCredentials, {
      'grpc.ssl_target_name_override': config.peer.hostAlias,
    });

    const privateKey = crypto.createPrivateKey(keyPem);

    _gateway = connect({
      client: _client,
      identity: { mspId: config.mspId, credentials: certPem },
      signer: signers.newPrivateKeySigner(privateKey),
      hash: hash.sha256,
      evaluateOptions: () => ({ deadline: Date.now() + 30000 }),
      endorseOptions: () => ({ deadline: Date.now() + 60000 }),
      submitOptions: () => ({ deadline: Date.now() + 30000 }),
      commitStatusOptions: () => ({ deadline: Date.now() + 120000 }),
    });

    _network = _gateway.getNetwork(config.channel);
    _contract = _network.getContract(config.chaincode);
    _connected = true;

    return { connected: true, error: null };
  } catch (err) {
    _connected = false;
    _contract = null;
    return { connected: false, error: err.message };
  }
}

/**
 * Get the connected contract. Throws if not connected.
 */
function getContract() {
  if (!_contract) {
    const result = connectGateway();
    if (!result.connected) {
      throw new Error(`FABRIC_UNAVAILABLE: ${result.error}`);
    }
  }
  return _contract;
}

/**
 * Disconnect and clean up.
 */
function disconnect() {
  try {
    if (_gateway) _gateway.close();
    if (_client) _client.close();
  } catch (_) {}
  _client = null;
  _gateway = null;
  _network = null;
  _contract = null;
  _connected = false;
}

function isConnected() {
  return _connected && _contract !== null;
}

module.exports = { connectGateway, getContract, disconnect, isConnected };
