// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/GSN/Context.sol";

contract Ownable is Context {

    // We need owner to be payable so this contract is basically the same + some improvements
    address payable private _owner;

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() internal {
        transferOwnership(_msgSender());
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function _owner() internal view returns (address) {
        return _owner;
    }

    function renounceOwnership() external onlyOwner {
        address prevOwner = _owner;
        _owner = address(0);

        emit OwnershipTransferred(prevOwner, _owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");

        address prevOwner = _owner;
        _owner = newOwner;

        emit OwnershipTransferred(prevOwner, _owner);  
    }
}
