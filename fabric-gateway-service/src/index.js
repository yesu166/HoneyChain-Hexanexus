/**
 * HoneyChain Fabric Gateway — HTTP Service.
 *
 * Exposes a simple HTTP API that the Python backend calls to interact with
 * the real Hyperledger Fabric network. The backend never talks to Fabric
 * directly; it talks to this service.
 *
 * Endpoints:
 *   GET  /health              - Connection health + chaincode status
 *   POST /submit              - Submit a transaction (with commit wait)
 *   POST /evaluate            - Evaluate (query) a transaction
 *   GET  /chaincode-info      - Metadata about the deployed chaincode
 *
 * Truth rules:
 *   - Never fabricate tx IDs, block numbers, or commit status.
 *   - Always distinguish submission success from commit confirmation.
 *   - Return structured errors for every failure mode.
 */

const express = require('express');
const { config, validate } = require('./config');
const { connectGateway, getContract, disconnect, isConnected } = require('./fabricGateway');
const {
  CHAINCODE_FUNCTIONS,
  anchorEvidenceArgs,
  verifyAnchorArgs,
  recordEventArgs,
  getEventArgs,
} = require('./chaincode');

// Security (Phase 15): the gateway must not be an arbitrary chaincode shell.
// Only these contract functions may be submitted or evaluated through HTTP.
// Keep in sync with CHAINCODE_FUNCTIONS in the Python adapter.
const ALLOWED_FUNCTIONS = new Set([
  // reads
  'getEvent',
  'getEventsByType',
  'getBatch',
  'getAllBatches',
  'getAnchor',
  'verifyMerkleRoot',
  'getLineage',
  'getCertificate',
  'getCertificatesForBatch',
  'getHistory',
  'scanRange',
  // writes
  'submitEvent',
  'createBatch',
  'transitionBatch',
  'recordLineage',
  'anchorMerkleRoot',
  'registerCertificate',
  'revokeCertificate',
]);

const app = express();
app.use(express.json({ limit: '1mb' }));

// -----------------------------------------------------------------------
// Health endpoint — the most important endpoint for the backend
// -----------------------------------------------------------------------
app.get('/health', async (_req, res) => {
  const configErrors = validate();
  if (configErrors.length > 0) {
    return res.status(503).json({
      status: 'misconfigured',
      adapter: 'fabric',
      error: `Missing required env vars: ${configErrors.join(', ')}`,
      channel: config.channel,
      chaincode: config.chaincode,
      chaincode_version: null,
      peer: config.peer.endpoint,
      last_verified_at: null,
    });
  }

  const connResult = connectGateway();
  if (!connResult.connected) {
    return res.status(503).json({
      status: 'unavailable',
      adapter: 'fabric',
      error: connResult.error,
      channel: config.channel,
      chaincode: config.chaincode,
      chaincode_version: null,
      peer: config.peer.endpoint,
      last_verified_at: null,
    });
  }

  // Attempt a real query to confirm the peer is actually serving
  try {
    const contract = getContract();
    const resultBytes = await contract.evaluateTransaction(
      CHAINCODE_FUNCTIONS.GET_ANCHOR,
      'health-check-probe',
    );
    const result = JSON.parse(Buffer.from(resultBytes).toString('utf-8'));

    return res.json({
      status: 'connected',
      adapter: 'fabric',
      network: config.channel,
      channel: config.channel,
      chaincode: config.chaincode,
      chaincode_version: '2.0',
      chaincode_sequence: 6,
      peer: config.peer.endpoint,
      msp_id: config.mspId,
      last_verified_at: new Date().toISOString(),
      health_probe_result: result,
      error: null,
    });
  } catch (err) {
    return res.status(503).json({
      status: 'unavailable',
      adapter: 'fabric',
      error: `Health query failed: ${err.message}`,
      channel: config.channel,
      chaincode: config.chaincode,
      chaincode_version: null,
      peer: config.peer.endpoint,
      last_verified_at: null,
    });
  }
});

// -----------------------------------------------------------------------
// Submit transaction (with commit confirmation)
// -----------------------------------------------------------------------
app.post('/submit', async (req, res) => {
  try {
    const { function: fn, args = [] } = req.body;

    if (!fn || typeof fn !== 'string') {
      return res.status(400).json({
        status: 'error',
        error: 'Missing or invalid "function" field',
      });
    }

    if (!ALLOWED_FUNCTIONS.has(fn)) {
      return res.status(403).json({
        status: 'error',
        error: `function "${fn}" is not allowlisted for submission`,
      });
    }

    if (!Array.isArray(args)) {
      return res.status(400).json({
        status: 'error',
        error: '"args" must be an array of strings',
      });
    }

    const contract = getContract();
    const stringArgs = args.map(String);

    const startSubmit = Date.now();
    // newProposal + submit + commitStatus gives us the REAL transaction id
    // (the txid the proposal was signed with) before we report anything.
    // submitTransaction() alone returns only the chaincode result bytes, so
    // the gateway used to answer with tx_id: null and the backend stored an
    // empty tx_hash on the anchor. No id is ever fabricated here.
    const proposal = contract.newProposal(fn, ...stringArgs);
    const txId = proposal.getTransactionId();
    const signedProposal = await proposal.endorse();
    const submittedTx = await contract.submit(signedProposal);
    const commitStatus = await contract.commitStatus(submittedTx);
    const commitMs = Date.now() - startSubmit;

    // Truth rules: submission success is distinct from commit confirmation.
    // Only report committed when the commit status says so.
    const commitCode = commitStatus.code; // 0 = OK (NOT_COMMITTED is 10)
    const committed = commitCode === 0;
    if (!committed) {
      return res.status(502).json({
        status: 'FABRIC_NOT_COMMITTED',
        adapter: 'fabric',
        function: fn,
        args: stringArgs,
        tx_id: txId,
        error: `transaction ${txId} was not committed (status code ${commitCode})`,
        channel: config.channel,
        chaincode: config.chaincode,
        submitted_at: new Date().toISOString(),
      });
    }

    // The chaincode result bytes (what submitTransaction would have returned).
    let resultPayload = null;
    try {
      const raw = Buffer.from(submittedTx.getResult()).toString('utf-8');
      try {
        resultPayload = JSON.parse(raw);
      } catch (_) {
        resultPayload = raw;
      }
    } catch (_) {}

    return res.json({
      status: 'committed',
      adapter: 'fabric',
      function: fn,
      args: stringArgs,
      result: resultPayload,
      tx_id: txId,
      submitted_at: new Date().toISOString(),
      commit: {
        committed: true,
        commit_ms: commitMs,
      },
      channel: config.channel,
      chaincode: config.chaincode,
    });
  } catch (err) {
    const errMsg = err.message || String(err);
    let errStatus = 'FABRIC_TRANSACTION_FAILED';
    let errDetail = null;

    if (errMsg.includes('ENDORSEMENT_POLICY_FAILURE')) {
      errStatus = 'FABRIC_ENDORSEMENT_FAILED';
    } else if (errMsg.includes('MVCC_READ_CONFLICT')) {
      errStatus = 'FABRIC_MVCC_CONFLICT';
    } else if (errMsg.includes('timed out') || errMsg.includes('DEADLINE_EXCEEDED')) {
      errStatus = 'FABRIC_TIMEOUT';
    } else if (errMsg.includes('UNAVAILABLE') || errMsg.includes('connect')) {
      errStatus = 'FABRIC_UNAVAILABLE';
    } else if (errMsg.includes('UNAUTHENTICATED') || errMsg.includes('PERMISSION_DENIED')) {
      errStatus = 'FABRIC_AUTH_FAILED';
    }

    return res.status(502).json({
      status: errStatus,
      adapter: 'fabric',
      function: req.body?.function || null,
      args: req.body?.args || [],
      error: errMsg,
      detail: errDetail,
      channel: config.channel,
      chaincode: config.chaincode,
      submitted_at: new Date().toISOString(),
    });
  }
});

// -----------------------------------------------------------------------
// Evaluate (query) transaction
// -----------------------------------------------------------------------
app.post('/evaluate', async (req, res) => {
  try {
    const { function: fn, args = [] } = req.body;

    if (!fn || typeof fn !== 'string') {
      return res.status(400).json({
        status: 'error',
        error: 'Missing or invalid "function" field',
      });
    }

    if (!ALLOWED_FUNCTIONS.has(fn)) {
      return res.status(403).json({
        status: 'error',
        error: `function "${fn}" is not allowlisted for evaluation`,
      });
    }

    const contract = getContract();
    const stringArgs = args.map(String);

    const startEval = Date.now();
    const resultBytes = await contract.evaluateTransaction(fn, ...stringArgs);
    const evalMs = Date.now() - startEval;

    let resultPayload = null;
    try {
      const raw = Buffer.from(resultBytes).toString('utf-8');
      try {
        resultPayload = JSON.parse(raw);
      } catch (_) {
        resultPayload = raw;
      }
    } catch (_) {}

    return res.json({
      status: 'success',
      adapter: 'fabric',
      function: fn,
      args: stringArgs,
      result: resultPayload,
      evaluated_at: new Date().toISOString(),
      evaluate_ms: evalMs,
      channel: config.channel,
      chaincode: config.chaincode,
    });
  } catch (err) {
    const errMsg = err.message || String(err);
    return res.status(502).json({
      status: 'FABRIC_QUERY_FAILED',
      adapter: 'fabric',
      function: req.body?.function || null,
      args: req.body?.args || [],
      error: errMsg,
      channel: config.channel,
      chaincode: config.chaincode,
    });
  }
});

// -----------------------------------------------------------------------
// Chaincode info — returns the contract mapping and deployment info
// -----------------------------------------------------------------------
app.get('/chaincode-info', (_req, res) => {
  res.json({
    channel: config.channel,
    chaincode: config.chaincode,
    chaincode_version: '2.0',
    chaincode_sequence: 6,
    msp_id: config.mspId,
    peer: config.peer.endpoint,
    functions: Object.values(CHAINCODE_FUNCTIONS),
    contract_mapping: {
      getEvent: {
        description: 'Retrieve an event by id',
        args: ['eventId'],
        returns: 'JSON event record',
      },
      getEventsByType: {
        description: 'List events by type',
        args: ['eventType'],
        returns: 'JSON array',
      },
      getBatch: {
        description: 'Retrieve a batch by id',
        args: ['batchId'],
        returns: 'JSON batch record',
      },
      getAllBatches: {
        description: 'List all batches',
        args: [],
        returns: 'JSON array',
      },
      getAnchor: {
        description: 'Retrieve the latest anchor for a batch',
        args: ['batchId'],
        returns: 'JSON { batchId, anchored, ... }',
      },
      verifyMerkleRoot: {
        description: 'Verify a Merkle root against the stored anchor',
        args: ['batchId', 'expectedRoot'],
        returns: 'JSON { batchId, verified, ... }',
      },
      getLineage: {
        description: 'Retrieve lineage for a batch',
        args: ['batchId'],
        returns: 'JSON',
      },
      getCertificate: {
        description: 'Retrieve a certificate by id',
        args: ['certificateId'],
        returns: 'JSON cert record',
      },
      getCertificatesForBatch: {
        description: 'List certificates for a batch',
        args: ['batchId'],
        returns: 'JSON array',
      },
      getHistory: {
        description: 'Retrieve state history for a key',
        args: ['key'],
        returns: 'JSON array',
      },
      scanRange: {
        description: 'Scan all keys with a prefix',
        args: ['prefix'],
        returns: 'JSON array',
      },
      submitEvent: {
        description: 'Record a business event on the ledger',
        args: ['eventJson'],
        returns: 'JSON created event record',
      },
      createBatch: {
        description: 'Create a batch',
        args: ['batchJson'],
        returns: 'JSON created batch record',
      },
      transitionBatch: {
        description: 'Transition a batch state',
        args: ['batchId', 'newState', 'actorId', 'note', 'serverTimestamp'],
        returns: 'JSON updated batch record',
      },
      recordLineage: {
        description: 'Record a lineage operation',
        args: ['lineageJson'],
        returns: 'JSON lineage record',
      },
      anchorMerkleRoot: {
        description: 'Anchor a Merkle root for a batch',
        args: ['anchorJson'],
        returns: 'JSON created anchor record',
      },
      registerCertificate: {
        description: 'Register a certificate',
        args: ['certJson'],
        returns: 'JSON created cert record',
      },
      revokeCertificate: {
        description: 'Revoke a certificate',
        args: ['certificateId', 'reason', 'revokedAt'],
        returns: 'JSON updated cert record',
      },
    },
  });
});

// -----------------------------------------------------------------------
// Graceful shutdown
// -----------------------------------------------------------------------
process.on('SIGINT', () => {
  disconnect();
  process.exit(0);
});

process.on('SIGTERM', () => {
  disconnect();
  process.exit(0);
});

// -----------------------------------------------------------------------
// Start
// -----------------------------------------------------------------------
const PORT = config.gatewayPort;

app.listen(PORT, () => {
  const errors = validate();
  if (errors.length > 0) {
    console.warn(
      `[WARN] Fabric Gateway starting with missing config: ${errors.join(', ')}`,
    );
    console.warn('[WARN] Health endpoint will report misconfigured.');
  }
  console.log(`[INFO] HoneyChain Fabric Gateway listening on port ${PORT}`);
  console.log(`[INFO] Channel: ${config.channel} | Chaincode: ${config.chaincode}`);
  console.log(`[INFO] Peer: ${config.peer.endpoint} | MSP: ${config.mspId}`);
});
