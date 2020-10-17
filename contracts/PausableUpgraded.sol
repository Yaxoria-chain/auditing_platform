// SPDX-License-Identifier: AGPL v3

pragma solidity ^0.6.0;

import "@openzeppelin/contracts/GSN/Context.sol";

contract PausableUpgraded is Context {

    bool private __paused;

    modifier whenNotPaused() {
        require(!__paused, "Action is suspended");
        _;
    }

    modifier whenPaused() {
        require(__paused, "Action is active");
        _;
    }

    event Paused(   address indexed _sender);
    event Unpaused( address indexed _sender);

    constructor () internal {}

    function paused() external view returns (bool) {
        return _paused();
    }

    function _paused() internal view returns (bool) {
        return __paused;
    }

    function _pause() internal {
        require(!__paused, "Action is suspended");
        __paused = true;
        emit Paused(_msgSender());
    }

    function _unpause() internal {
        require(__paused, "Action is active");
        __paused = false;
        emit Unpaused(_msgSender());
    }
}
