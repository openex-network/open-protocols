pragma solidity =0.5.16;
import '../PancakePair.sol';

contract InitHash {
    function getInitHash() public pure returns(bytes32){
        bytes memory bytecode = type(PancakePair).creationCode;
        return keccak256(abi.encodePacked(bytecode));
    }
}