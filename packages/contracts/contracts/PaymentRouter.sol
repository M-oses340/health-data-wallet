// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ConsentRegistry.sol";
import "./DataEscrow.sol";

/**
 * PaymentRouter — orchestrates milestone-triggered dividend payments and
 * consent-revocation refunds.
 *
 * Requirements: 5.1, 5.4, 5.6
 */
contract PaymentRouter {

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    ConsentRegistry public immutable registry;
    DataEscrow      public immutable escrow;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    /**
     * Emitted when a Data Dividend is paid to a patient.
     * Requirement 5.4 — DividendPaid event with contractId, patientWallet, amount, timestamp.
     */
    event DividendPaid(
        bytes32 indexed contractId,
        address indexed patientWallet,
        uint256 amount,
        uint256 timestamp
    );

    event EscrowRefunded(
        bytes32 indexed contractId,
        address indexed researcherWallet,
        uint256 amount,
        uint256 timestamp
    );

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error ConsentNotActive(bytes32 contractId);

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _registry, address _escrow) {
        registry = ConsentRegistry(_registry);
        escrow   = DataEscrow(_escrow);
    }

    // -----------------------------------------------------------------------
    // Computation Engine: release dividend on milestone completion
    // Requirements: 5.1, 5.4
    // -----------------------------------------------------------------------

    function releaseDividend(bytes32 contractId) external {
        if (!registry.isConsentActive(contractId)) {
            revert ConsentNotActive(contractId);
        }

        // Fetch patient wallet from registry
        ConsentRegistry.ConsentRecord memory rec = registry.getRecord(contractId);

        // Mark contract completed on-chain
        registry.markCompleted(contractId);

        // Release escrowed funds to patient
        escrow.releaseFunds(contractId);

        emit DividendPaid(
            contractId,
            rec.patientWallet,
            rec.dataDividend,
            block.timestamp
        );
    }

    // -----------------------------------------------------------------------
    // Called after patient revokes consent — refund researcher
    // Requirement 5.6
    // -----------------------------------------------------------------------

    function processRevocationRefund(bytes32 contractId) external {
        ConsentRegistry.ConsentRecord memory rec = registry.getRecord(contractId);

        // Refund escrowed funds to researcher
        escrow.refundFunds(contractId);

        emit EscrowRefunded(
            contractId,
            rec.researcherWallet,
            escrow.escrowed(contractId),
            block.timestamp
        );
    }
}
