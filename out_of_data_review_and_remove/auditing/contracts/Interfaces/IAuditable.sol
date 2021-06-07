// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.1;

interface IAuditable {
    
    function confirmAuditor( address auditor ) external;

    function approveAudit( address auditor ) external;

    function opposeAudit( address auditor ) external;

}


