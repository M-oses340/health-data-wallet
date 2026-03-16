// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * ConsentRegistry — manages on-chain Consent Records between patients and researchers.
 *
 * Lifecycle:  PENDING_SIGNATURE → ACTIVE → COMPLETED | REVOKED | EXPIRED
 *
 * Requirements: 3.1, 3.3, 3.5, 3.6
 */
contract ConsentRegistry {

    // -----------------------------------------------------------------------
    // Enums & structs
    // -----------------------------------------------------------------------

    enum ContractStatus { PENDING_SIGNATURE, ACTIVE, COMPLETED, REVOKED, EXPIRED }

    struct ConsentRecord {
        bytes32     contractId;
        address     patientWallet;
        address     researcherWallet;
        string      dataCategory;
        string      permittedScope;
        uint256     accessDuration;   // seconds
        uint256     dataDividend;     // wei
        uint8       computationMethod; // 0 = FL, 1 = ZKP
        uint256     createdAt;
        uint256     expiresAt;
        ContractStatus status;
    }

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    mapping(bytes32 => ConsentRecord) private _records;

    // -----------------------------------------------------------------------
    // Events  (Requirement 3.3, 3.6)
    // -----------------------------------------------------------------------

    event ContractCreated(
        bytes32 indexed contractId,
        address indexed patientWallet,
        address indexed researcherWallet,
        uint256 dataDividend
    );

    event ContractSigned(
        bytes32 indexed contractId,
        address indexed patientWallet,
        uint256 expiresAt
    );

    event ConsentRevoked(
        bytes32 indexed contractId,
        address indexed patientWallet,
        uint256 revokedAt
    );

    event ContractCompleted(
        bytes32 indexed contractId,
        uint256 completedAt
    );

    event ContractExpired(
        bytes32 indexed contractId,
        uint256 expiredAt
    );

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error ContractAlreadyExists(bytes32 contractId);
    error ContractNotFound(bytes32 contractId);
    error NotPatient(bytes32 contractId);
    error NotPendingSignature(bytes32 contractId);
    error NotActive(bytes32 contractId);
    error AlreadyExpired(bytes32 contractId);

    // -----------------------------------------------------------------------
    // Researcher: create a consent contract (pending patient signature)
    // Requirement 3.1
    // -----------------------------------------------------------------------

    function createContract(
        bytes32     contractId,
        address     patientWallet,
        string calldata dataCategory,
        string calldata permittedScope,
        uint256     accessDuration,
        uint256     dataDividend,
        uint8       computationMethod
    ) external {
        if (_records[contractId].createdAt != 0) {
            revert ContractAlreadyExists(contractId);
        }

        _records[contractId] = ConsentRecord({
            contractId:        contractId,
            patientWallet:     patientWallet,
            researcherWallet:  msg.sender,
            dataCategory:      dataCategory,
            permittedScope:    permittedScope,
            accessDuration:    accessDuration,
            dataDividend:      dataDividend,
            computationMethod: computationMethod,
            createdAt:         block.timestamp,
            expiresAt:         0,
            status:            ContractStatus.PENDING_SIGNATURE
        });

        emit ContractCreated(contractId, patientWallet, msg.sender, dataDividend);
    }

    // -----------------------------------------------------------------------
    // Patient: sign and activate the contract
    // Requirement 3.3
    // -----------------------------------------------------------------------

    function signContract(bytes32 contractId) external {
        ConsentRecord storage rec = _getRecord(contractId);

        if (rec.status != ContractStatus.PENDING_SIGNATURE) {
            revert NotPendingSignature(contractId);
        }
        if (msg.sender != rec.patientWallet) {
            revert NotPatient(contractId);
        }

        rec.expiresAt = block.timestamp + rec.accessDuration;
        rec.status    = ContractStatus.ACTIVE;

        emit ContractSigned(contractId, msg.sender, rec.expiresAt);
    }

    // -----------------------------------------------------------------------
    // Patient: revoke consent
    // Requirement 3.6
    // -----------------------------------------------------------------------

    function revokeConsent(bytes32 contractId) external {
        ConsentRecord storage rec = _getRecord(contractId);

        if (msg.sender != rec.patientWallet) {
            revert NotPatient(contractId);
        }
        if (rec.status != ContractStatus.ACTIVE) {
            revert NotActive(contractId);
        }

        rec.status = ContractStatus.REVOKED;

        emit ConsentRevoked(contractId, msg.sender, block.timestamp);
    }

    // -----------------------------------------------------------------------
    // Internal: mark contract completed (called by PaymentRouter)
    // -----------------------------------------------------------------------

    function markCompleted(bytes32 contractId) external {
        ConsentRecord storage rec = _getRecord(contractId);
        if (rec.status != ContractStatus.ACTIVE) {
            revert NotActive(contractId);
        }
        rec.status = ContractStatus.COMPLETED;
        emit ContractCompleted(contractId, block.timestamp);
    }

    // -----------------------------------------------------------------------
    // Anyone: expire a contract whose accessDuration has elapsed
    // Requirement 3.5
    // -----------------------------------------------------------------------

    function expireContract(bytes32 contractId) external {
        ConsentRecord storage rec = _getRecord(contractId);
        if (rec.status != ContractStatus.ACTIVE) {
            revert NotActive(contractId);
        }
        if (block.timestamp < rec.expiresAt) {
            revert AlreadyExpired(contractId);
        }
        rec.status = ContractStatus.EXPIRED;
        emit ContractExpired(contractId, block.timestamp);
    }

    // -----------------------------------------------------------------------
    // View helpers
    // -----------------------------------------------------------------------

    /**
     * Returns true only when the contract is ACTIVE and not yet expired.
     * Requirement 3.4 — Computation Engine checks this before starting.
     */
    function isConsentActive(bytes32 contractId) external view returns (bool) {
        ConsentRecord storage rec = _records[contractId];
        if (rec.createdAt == 0) return false;
        if (rec.status != ContractStatus.ACTIVE) return false;
        if (block.timestamp >= rec.expiresAt) return false;
        return true;
    }

    function getRecord(bytes32 contractId) external view returns (ConsentRecord memory) {
        return _getRecord(contractId);
    }

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    function _getRecord(bytes32 contractId) private view returns (ConsentRecord storage) {
        if (_records[contractId].createdAt == 0) {
            revert ContractNotFound(contractId);
        }
        return _records[contractId];
    }
}
