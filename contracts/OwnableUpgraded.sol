// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/GSN/Context.sol";

// openzeppelin has Ownable and the compiler cries about duplicated names possibly causing unexpected
// behavior therefore use OwnableUpgraded instead
contract OwnableUpgraded is Context {

    // We need owner to be payable so this contract is basically the same + some improvements
    // double underscore so that we can use external/internal visibility (automatic getter blocks otherwise)
    address payable private __owner;

    modifier onlyOwner() {
        require(__owner == _msgSender(), "OwnableUpgraded: caller is not the owner");
        _;
    }

    event OwnershipTransferred(address indexed _previousOwner, address indexed _newOwner);

    constructor() internal {
        __owner = _msgSender();
        emit OwnershipTransferred(address(0), __owner);  
    }

    function owner() external view returns (address payable) {
        return _owner();
    }

    function _owner() internal view returns (address payable) {
        return __owner;
    }

    function renounceOwnership() external onlyOwner() {
        address prevOwner = __owner;
        __owner = address(0);

        emit OwnershipTransferred(prevOwner, __owner);
    }

    function transferOwnership(address payable _newOwner) external onlyOwner() {
        _transferOwnership(_newOwner);
    }

    function _transferOwnership(address payable _newOwner) internal onlyOwner() {
        require(_newOwner != address(0), "OwnableUpgraded: new owner is the zero address");

        address prevOwner = __owner;
        __owner = _newOwner;

        emit OwnershipTransferred(prevOwner, __owner);
    }
}
