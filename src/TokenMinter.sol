/* SPDX-License-Identifier: UNLICENSED
 *
 * Copyright (c) 2022, Circle Internet Financial Trading Company Limited.
 * All rights reserved.
 *
 * Circle Internet Financial Trading Company Limited CONFIDENTIAL
 *
 * This file includes unpublished proprietary source code of Circle Internet
 * Financial Trading Company Limited, Inc. The copyright notice above does not
 * evidence any actual or intended publication of such source code. Disclosure
 * of this source code or any related proprietary information is strictly
 * prohibited without the express written permission of Circle Internet Financial
 * Trading Company Limited.
 */
pragma solidity ^0.7.6;

import "./interfaces/IMinter.sol";
import "./interfaces/IMintBurnToken.sol";
import "./roles/Pausable.sol";
import "./roles/Rescuable.sol";
import "./TokenMessenger.sol";

/**
 * @title TokenMinter
 * @notice Token Minter and Burner
 * @dev Maintains registry of local mintable tokens and corresponding tokens on remote domains.
 * This registry can be used by caller to determine which token on local domain to mint for a
 * burned token on a remote domain, and vice versa.
 * It is assumed that local and remote tokens are fungible at a constant 1:1 exchange rate.
 */
contract TokenMinter is IMinter, Pausable, Rescuable {
    /**
     * @notice Emitted when a local TokenMessenger is added
     * @param localTokenMessenger address of local TokenMessenger
     * @notice Emitted when a local TokenMessenger is added
     */
    event LocalTokenMessengerAdded(address indexed localTokenMessenger);

    /**
     * @notice Emitted when a local TokenMessenger is removed
     * @param localTokenMessenger address of local TokenMessenger
     * @notice Emitted when a local TokenMessenger is removed
     */
    event LocalTokenMessengerRemoved(address indexed localTokenMessenger);

    // Supported mintable tokens on the local domain
    // local token (address) => supported (bool)
    mapping(address => bool) public localTokens;

    // Supported mintable tokens on remote domains, mapped to their corresponding local token
    // hash(remote domain & remote token bytes32 address) => local token (address)
    mapping(bytes32 => address) public remoteTokensToLocalTokens;

    // Local TokenMessenger with permission to call mint and burn on this TokenMinter
    address public localTokenMessenger;

    /**
     * @notice Only accept messages from the registered message transmitter on local domain
     */
    modifier onlyLocalTokenMessenger() {
        require(_isLocalTokenMessenger(), "Caller not local TokenMessenger");
        _;
    }

    /**
     * @notice Mint tokens.
     * @param mintToken Mintable token address.
     * @param to Address to receive minted tokens.
     * @param amount Amount of tokens to mint. Must be less than or equal
     * to the minterAllowance of this TokenMinter for given `_mintToken`.
     */
    function mint(
        address mintToken,
        address to,
        uint256 amount
    ) external override whenNotPaused onlyLocalTokenMessenger {
        require(localTokens[mintToken], "Mint token not supported");

        IMintBurnToken _token = IMintBurnToken(mintToken);
        require(_token.mint(to, amount), "Mint operation failed");
    }

    /**
     * @notice Burn tokens owned by this TokenMinter.
     * @param burnToken burnable token address.
     * @param amount amount of tokens to burn. Must be less than or equal to this
     * TokenMinter's balance of given `burnToken`.
     */
    function burn(address burnToken, uint256 amount)
        external
        override
        whenNotPaused
        onlyLocalTokenMessenger
    {
        require(localTokens[burnToken], "Burn token not supported");

        IMintBurnToken _token = IMintBurnToken(burnToken);
        _token.burn(amount);
    }

    /**
     * @notice Links a pair of local and remote tokens to be supported by this TokenMinter.
     * @dev Associates a (`remoteToken`, `localToken`) pair by updating remoteTokensToLocalTokens mapping.
     * Reverts if the remote token (for the given `remoteDomain`) already maps to a nonzero local token.
     * Note:
     * - A remote token (on a certain remote domain) can only map to one local token, but many remote tokens
     * can map to the same local token.
     * - Setting a token pair does not enable the `localToken` (that requires calling setLocalTokenEnabledStatus.)
     */
    function linkTokenPair(
        address localToken,
        uint32 remoteDomain,
        bytes32 remoteToken
    ) external override onlyOwner {
        bytes32 _remoteTokensKey = _hashRemoteDomainAndToken(
            remoteDomain,
            remoteToken
        );

        // remote token must not be already linked to a local token
        require(
            remoteTokensToLocalTokens[_remoteTokensKey] == address(0),
            "Unable to link token pair"
        );

        remoteTokensToLocalTokens[_remoteTokensKey] = localToken;

        emit TokenPairLinked(localToken, remoteDomain, remoteToken);
    }

    /**
     * @notice Unlinks a pair of local and remote tokens for this TokenMinter.
     * @dev Removes link from `remoteToken`, to `localToken` for given `remoteDomain`
     * by updating remoteTokensToLocalTokens mapping.
     * Reverts if the remote token (for the given `remoteDomain`) already maps to the zero address.
     * Note:
     * - A remote token (on a certain remote domain) can only map to one local token, but many remote tokens
     * can map to the same local token.
     * - Unlinking a token pair does not disable the `localToken` (that requires calling setLocalTokenEnabledStatus.)
     */
    function unlinkTokenPair(
        address localToken,
        uint32 remoteDomain,
        bytes32 remoteToken
    ) external override onlyOwner {
        bytes32 _remoteTokensKey = _hashRemoteDomainAndToken(
            remoteDomain,
            remoteToken
        );

        // remote token must be linked to a local token before unlink
        require(
            remoteTokensToLocalTokens[_remoteTokensKey] != address(0),
            "Unable to unlink token pair"
        );

        delete remoteTokensToLocalTokens[_remoteTokensKey];

        emit TokenPairUnlinked(localToken, remoteDomain, remoteToken);
    }

    /**
     * @notice Add TokenMessenger for the local domain. Only this TokenMessenger
     * has permission to call mint() and burn() on this TokenMinter.
     * @dev Reverts if a TokenMessenger is already set for the local domain.
     * @param newLocalTokenMessenger The address of the new TokenMessenger on the local domain.
     */
    function addLocalTokenMessenger(address newLocalTokenMessenger)
        external
        onlyOwner
    {
        require(
            newLocalTokenMessenger != address(0),
            "Invalid TokenMessenger address"
        );

        require(
            localTokenMessenger == address(0),
            "Local TokenMessenger already set"
        );

        localTokenMessenger = newLocalTokenMessenger;

        emit LocalTokenMessengerAdded(localTokenMessenger);
    }

    /**
     * @notice Remove the TokenMessenger for the local domain.
     * @dev Reverts if the TokenMessenger of the local domain is not set.
     */
    function removeLocalTokenMessenger() external onlyOwner {
        address _localTokenMessengerBeforeRemoval = localTokenMessenger;
        require(
            _localTokenMessengerBeforeRemoval != address(0),
            "No local TokenMessenger is set"
        );

        delete localTokenMessenger;
        emit LocalTokenMessengerRemoved(_localTokenMessengerBeforeRemoval);
    }

    /**
     * @notice Enable or disable a local token
     * @dev Sets `enabledStatus` boolean for given `localToken`. (True to enable, false to disable.)
     * @param localToken Local token to set enabled status of.
     * @param enabledStatus Enabled/disabled status to set for `localToken`.
     * (True to enable, false to disable.)
     */
    function setLocalTokenEnabledStatus(address localToken, bool enabledStatus)
        external
        override
        onlyOwner
    {
        localTokens[localToken] = enabledStatus;

        emit LocalTokenEnabledStatusSet(localToken, enabledStatus);
    }

    /**
     * @notice Get the enabled local token associated with the given remote domain and token.
     * @dev Reverts if unable to find an enabled local token for the
     * given (`remoteDomain`, `remoteToken`) pair.
     * @param remoteDomain Remote domain
     * @param remoteToken Remote token
     * @return Local token address
     */
    function getEnabledLocalToken(uint32 remoteDomain, bytes32 remoteToken)
        external
        view
        override
        returns (address)
    {
        bytes32 _remoteTokensKey = _hashRemoteDomainAndToken(
            remoteDomain,
            remoteToken
        );

        address _associatedLocalToken = remoteTokensToLocalTokens[
            _remoteTokensKey
        ];

        // an enabled local token must be associated with remote domain and token pair
        require(
            _associatedLocalToken != address(0) &&
                localTokens[_associatedLocalToken],
            "Local token not enabled"
        );

        return _associatedLocalToken;
    }

    /**
     * @notice hashes packed `_remoteDomain` and `_remoteToken`.
     * @param remoteDomain Domain where message originated from
     * @param remoteToken Address of remote token as bytes32
     * @return keccak hash of packed remote domain and token
     */
    function _hashRemoteDomainAndToken(uint32 remoteDomain, bytes32 remoteToken)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(remoteDomain, remoteToken));
    }

    /**
     * @notice Returns true if the message sender is the registered local TokenMessenger
     * @return True if the message sender is the registered local TokenMessenger
     */
    function _isLocalTokenMessenger() internal view returns (bool) {
        return
            address(localTokenMessenger) != address(0) &&
            msg.sender == address(localTokenMessenger);
    }
}