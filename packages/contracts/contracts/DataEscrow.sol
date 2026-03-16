// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * DataEscrow — holds researcher funds until milestone completion or revocation.
 *
 * Requirements: 5.2, 5.3, 5.6
 */
contract DataEscrow {

    // -----------------------------------------------------------------------
    // State
    // -----------------------------------------------------------------------

    struct EscrowRecord {
        address researcherWallet;
        address patientWallet;
        uint256 amount;          // wei escrowed
        uint256 dividendAmount;  // agreed dividend (must be <= amount)
        bool    released;
        bool    refunded;
    }

    mapping(bytes32 => EscrowRecord) private _escrows;

    // Authorised caller that can release or refund (PaymentRouter address)
    address public router;
    address public owner;

    // -----------------------------------------------------------------------
    // Events
    // -----------------------------------------------------------------------

    event FundsEscrowed(bytes32 indexed contractId, address indexed researcher, uint256 amount);
    event FundsReleased(bytes32 indexed contractId, address indexed patient,    uint256 amount);
    event FundsRefunded(bytes32 indexed contractId, address indexed researcher, uint256 amount);

    // -----------------------------------------------------------------------
    // Errors
    // -----------------------------------------------------------------------

    error InsufficientEscrow(uint256 sent, uint256 required);
    error EscrowAlreadyExists(bytes32 contractId);
    error EscrowNotFound(bytes32 contractId);
    error AlreadySettled(bytes32 contractId);
    error Unauthorized();

    // -----------------------------------------------------------------------
    // Constructor
    // -----------------------------------------------------------------------

    constructor(address _router) {
        router = _router;
        owner  = msg.sender;
    }

    /// Allow the deployer to update the router address after deployment.
    function setRouter(address _router) external {
        require(msg.sender == owner, "Not owner");
        router = _router;
    }

    // -----------------------------------------------------------------------
    // Researcher: deposit funds when creating a contract
    // Requirement 5.2, 5.3 — escrowed amount must cover the dividend
    // -----------------------------------------------------------------------

    function escrowFunds(
        bytes32 contractId,
        address patientWallet,
        uint256 dividendAmount
    ) external payable {
        if (_escrows[contractId].researcherWallet != address(0)) {
            revert EscrowAlreadyExists(contractId);
        }
        if (msg.value < dividendAmount) {
            revert InsufficientEscrow(msg.value, dividendAmount);
        }

        _escrows[contractId] = EscrowRecord({
            researcherWallet: msg.sender,
            patientWallet:    patientWallet,
            amount:           msg.value,
            dividendAmount:   dividendAmount,
            released:         false,
            refunded:         false
        });

        emit FundsEscrowed(contractId, msg.sender, msg.value);
    }

    // -----------------------------------------------------------------------
    // PaymentRouter: release dividend to patient on milestone
    // Requirement 5.3
    // -----------------------------------------------------------------------

    function releaseFunds(bytes32 contractId) external {
        if (msg.sender != router) revert Unauthorized();

        EscrowRecord storage esc = _getEscrow(contractId);
        if (esc.released || esc.refunded) revert AlreadySettled(contractId);

        esc.released = true;
        uint256 amount = esc.dividendAmount;

        (bool ok, ) = esc.patientWallet.call{value: amount}("");
        require(ok, "Transfer to patient failed");

        // Refund any surplus to researcher
        uint256 surplus = esc.amount - amount;
        if (surplus > 0) {
            (bool ok2, ) = esc.researcherWallet.call{value: surplus}("");
            require(ok2, "Surplus refund failed");
        }

        emit FundsReleased(contractId, esc.patientWallet, amount);
    }

    // -----------------------------------------------------------------------
    // PaymentRouter: refund researcher on revocation
    // Requirement 5.6
    // -----------------------------------------------------------------------

    function refundFunds(bytes32 contractId) external {
        if (msg.sender != router) revert Unauthorized();

        EscrowRecord storage esc = _getEscrow(contractId);
        if (esc.released || esc.refunded) revert AlreadySettled(contractId);

        esc.refunded = true;
        uint256 amount = esc.amount;

        (bool ok, ) = esc.researcherWallet.call{value: amount}("");
        require(ok, "Refund to researcher failed");

        emit FundsRefunded(contractId, esc.researcherWallet, amount);
    }

    // -----------------------------------------------------------------------
    // View
    // -----------------------------------------------------------------------

    function getEscrow(bytes32 contractId) external view returns (EscrowRecord memory) {
        return _getEscrow(contractId);
    }

    function escrowed(bytes32 contractId) external view returns (uint256) {
        return _escrows[contractId].amount;
    }

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    function _getEscrow(bytes32 contractId) private view returns (EscrowRecord storage) {
        if (_escrows[contractId].researcherWallet == address(0)) {
            revert EscrowNotFound(contractId);
        }
        return _escrows[contractId];
    }
}
