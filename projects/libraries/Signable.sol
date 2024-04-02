// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/access/AccessControl.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {SignatureChecker} from "./SignatureChecker.sol";

/**
 * @title Signable
 */
abstract contract Signable is EIP712, AccessControl {
    bytes32 public constant SIGNER_ROLE = keccak256("SIGNER_ROLE");
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
    bytes32 internal constant TICKET_HASH =
        keccak256(
            "SignerTicket(address signer,address to,address token,uint256 amount,uint256 nonce,uint256 startTime,uint256 endTime)"
        );

    mapping(address => uint256) public userMinTicketNonce;
    mapping(address => mapping(uint256 => bool)) internal _isUserTicketNonceExecutedOrCancelled;

    struct SignerTicket {
        address signer; // signer of the ticket
        address to; // owner of the tokens
        address token; // address of the token
        uint256 amount; // amount of the token
        uint256 nonce; // ticket nonce (must be unique unless new ticket is meant to override existing one)
        uint256 startTime; // startTime in timestamp
        uint256 endTime; // endTime in timestamp
        uint8 v; // v: parameter (27 or 28)
        bytes32 r; // r: parameter
        bytes32 s; // s: parameter
    }

    // ------------------------------------------------------------------------
    // event
    // ------------------------------------------------------------------------
    event ERC20ExtSignerTicketExecuted(address indexed to, uint256 amount, uint256 indexed nonce);

    function hash(SignerTicket memory ticket) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    TICKET_HASH,
                    ticket.signer,
                    ticket.to,
                    ticket.token,
                    ticket.amount,
                    ticket.nonce,
                    ticket.startTime,
                    ticket.endTime
                )
            );
    }

    function _validateTicket(SignerTicket calldata ticket, bytes32 ticketHash) internal view {
        // Verify SIGNER_ROLE
        _checkRole(SIGNER_ROLE, ticket.signer);

        // Verify whether ticket nonce has expired
        require(
            (!_isUserTicketNonceExecutedOrCancelled[ticket.signer][ticket.nonce]) &&
                (ticket.nonce >= userMinTicketNonce[ticket.signer]),
            "Ticket: Matching ticket expired"
        );

        // Verify ticket time
        require(_canExecuteTicket(ticket), "Ticket: Invalid ticket time");

        // Verify the validity of the signature
        require(
            SignatureChecker.verify(ticketHash, ticket.signer, ticket.v, ticket.r, ticket.s, _domainSeparatorV4()),
            "Signature: Invalid"
        );
    }

    function _setExecuted(SignerTicket calldata ticket) internal {
        _isUserTicketNonceExecutedOrCancelled[ticket.signer][ticket.nonce] = true;
        emit ERC20ExtSignerTicketExecuted(ticket.to, ticket.amount, ticket.nonce);
    }

    function _canExecuteTicket(SignerTicket calldata ticket) internal view returns (bool) {
        return ((ticket.endTime >= block.timestamp) && (ticket.startTime <= block.timestamp));
    }

    // ------------------------------------------------------------------------
    // view
    // ------------------------------------------------------------------------
    /**
     * @notice Check whether user ticket nonce is executed or cancelled
     * @param user address of user
     * @param ticketNonce nonce of the ticket
     */
    function isUserTicketNonceExecutedOrCancelled(address user, uint256 ticketNonce) external view returns (bool) {
        return _isUserTicketNonceExecutedOrCancelled[user][ticketNonce];
    }

    // ------------------------------------------------------------------------
    // virtual
    // ------------------------------------------------------------------------

    function execute(SignerTicket calldata ticket) external virtual;

    function cancel(SignerTicket calldata ticket) external virtual;
}
