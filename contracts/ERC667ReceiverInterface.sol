pragma solidity ^0.4.17;

interface ERC667ReceiverInterface {
    function tokenFallback(address from, uint256 amount, bytes data) public returns (bool success);
}