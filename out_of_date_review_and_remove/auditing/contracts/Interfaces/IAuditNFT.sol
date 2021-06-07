// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.1;

interface IAuditNFT {

    function mint( address auditor, address contract_, address deployer, bool approved, bytes calldata hash ) external;

}

