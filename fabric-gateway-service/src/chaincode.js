/**
 * HoneyChain chaincode contract mapping.
 *
 * These are the EXACT function names from the deployed chaincode v2.0
 * on the live Fabric network. Verified by inspecting the chaincode
 * container on EC2 (dev-peer0.org1.example.com-honeychain_2.0-...).
 *
 * Source: /usr/local/src/lib/honeychain.js (HoneyChainContract)
 *
 * Read functions:
 *   getEvent(eventId) -> JSON
 *   getEventsByType(eventType) -> JSON array
 *   getBatch(batchId) -> JSON
 *   getAllBatches() -> JSON array
 *   getAnchor(batchId) -> JSON
 *   verifyMerkleRoot(batchId, expectedRoot) -> JSON
 *   getLineage(batchId) -> JSON
 *   getCertificate(certificateId) -> JSON
 *   getCertificatesForBatch(batchId) -> JSON array
 *   getHistory(key) -> JSON array
 *   scanRange(prefix) -> JSON array
 *
 * Write functions:
 *   submitEvent(eventJson) -> JSON (created event record)
 *   createBatch(batchJson) -> JSON (created batch record)
 *   transitionBatch(batchId, newState, actorId, note, serverTimestamp) -> JSON
 *   recordLineage(lineageJson) -> JSON
 *   anchorMerkleRoot(anchorJson) -> JSON (created anchor record)
 *   registerCertificate(certJson) -> JSON (created cert record)
 *   revokeCertificate(certificateId, reason, revokedAt) -> JSON
 */

const CHAINCODE_FUNCTIONS = Object.freeze({
  // Read
  GET_EVENT: 'getEvent',
  GET_EVENTS_BY_TYPE: 'getEventsByType',
  GET_BATCH: 'getBatch',
  GET_ALL_BATCHES: 'getAllBatches',
  GET_ANCHOR: 'getAnchor',
  VERIFY_MERKLE_ROOT: 'verifyMerkleRoot',
  GET_LINEAGE: 'getLineage',
  GET_CERTIFICATE: 'getCertificate',
  GET_CERTIFICATES_FOR_BATCH: 'getCertificatesForBatch',
  GET_HISTORY: 'getHistory',
  SCAN_RANGE: 'scanRange',

  // Write
  SUBMIT_EVENT: 'submitEvent',
  CREATE_BATCH: 'createBatch',
  TRANSITION_BATCH: 'transitionBatch',
  RECORD_LINEAGE: 'recordLineage',
  ANCHOR_MERKLE_ROOT: 'anchorMerkleRoot',
  REGISTER_CERTIFICATE: 'registerCertificate',
  REVOKE_CERTIFICATE: 'revokeCertificate',

  // Legacy aliases (mapped to actual functions)
  ANCHOR_EVIDENCE: 'anchorMerkleRoot',
  VERIFY_ANCHOR: 'verifyMerkleRoot',
  RECORD_EVENT: 'submitEvent',
});

/**
 * Build the arguments array for anchorMerkleRoot.
 * Expects a single JSON string with the anchor details.
 */
function anchorEvidenceArgs(anchorJson) {
  return [anchorJson];
}

/**
 * Build the arguments array for verifyMerkleRoot.
 */
function verifyAnchorArgs(batchId, expectedRoot) {
  return [batchId, expectedRoot];
}

/**
 * Build the arguments array for submitEvent.
 * Expects a single JSON string with the event details.
 */
function recordEventArgs(eventJson) {
  return [eventJson];
}

/**
 * Build the arguments array for getEvent.
 */
function getEventArgs(eventId) {
  return [eventId];
}

module.exports = {
  CHAINCODE_FUNCTIONS,
  anchorEvidenceArgs,
  verifyAnchorArgs,
  recordEventArgs,
  getEventArgs,
};
