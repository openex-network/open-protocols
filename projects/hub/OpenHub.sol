// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";
import {Signable} from "../libraries/Signable.sol";

/**
 * @title OpenHub
 */
contract OpenHub is Signable {
    using SafeERC20 for IERC20;

    event NativeReceived(address indexed sender, uint256 amount);

    constructor() EIP712("OpenHub", "1") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _sendToken(address to, address token, uint256 amount) internal {
        if (token == address(0)) {
            return _sendNative(to, amount);
        }

        require(IERC20(token).balanceOf(address(this)) > amount, "Balance Not Enough");

        IERC20(token).transfer(to, amount);
    }

    function _sendNative(address to, uint256 amount) internal {
        require(address(this).balance > amount, "Balance Not Enough");
        payable(to).transfer(amount);
    }

    function execute(SignerTicket calldata ticket) external override onlyRole(VALIDATOR_ROLE) {
        bytes32 ticketHash = hash(ticket);
        _validateTicket(ticket, ticketHash);
        require(ticket.signer != msg.sender, "Validator = Signer");
        _setExecuted(ticket);
        _sendToken(ticket.to, ticket.token, ticket.amount);
    }

    function cancel(SignerTicket calldata ticket) external override onlyRole(VALIDATOR_ROLE) {
        bytes32 ticketHash = hash(ticket);
        _validateTicket(ticket, ticketHash);
        _setExecuted(ticket);
    }

    fallback() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }

    receive() external payable {
        emit NativeReceived(msg.sender, msg.value);
    }
}
