//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC404} from "./interfaces/IERC404.sol";
import {ERC721Receiver} from "./lib/ERC721Receiver.sol";
import {DoubleEndedQueue} from "./lib/DoubleEndedQueue.sol";
import {IERC165} from "./lib/interfaces/IERC165.sol";
import {IERC721} from "./lib/interfaces/IERC721.sol";
import "./ERC721A/ERC721AQueryable.sol";
import "hardhat/console.sol";

abstract contract ERC404M is IERC404 {
  using DoubleEndedQueue for DoubleEndedQueue.Uint256Deque;

  /// @dev The queue of ERC-721 tokens stored in the contract.
  DoubleEndedQueue.Uint256Deque private _storedERC721Ids;

  /// @dev Token name
  string public name;

  /// @dev Token symbol
  string public symbol;

  /// @dev Decimals for ERC-20 representation
  uint8 public  decimals;

  /// @dev Units for ERC-20 representation
  uint256 public  units;

  /// @dev Total supply in ERC-20 representation
  uint256 public totalSupply;

  /// @dev Current mint counter which also represents the highest
  ///      minted id, monotonically increasing to ensure accurate ownership
  uint256 internal _minted;

  /// @dev Initial chain id for EIP-2612 support
  uint256 internal INITIAL_CHAIN_ID;

  /// @dev Initial domain separator for EIP-2612 support
  bytes32 internal INITIAL_DOMAIN_SEPARATOR;

  /// @dev Balance of user in ERC-20 representation
  mapping(address => uint256) public balanceOf;

  /// @dev Allowance of user in ERC-20 representation
  mapping(address => mapping(address => uint256)) public allowance;

  /// @dev Approval in ERC-721 representaion
  mapping(uint256 => address) public getApproved;

  /// @dev Approval for all in ERC-721 representation
  mapping(address => mapping(address => bool)) public isApprovedForAll;

  /// @dev Packed representation of ownerOf and owned indices
  mapping(uint256 => uint256) internal _ownedData;

  /// @dev Array of owned ids in ERC-721 representation
  // mapping(address => mapping(uint256 = uint256[]) internal _owned;

  /// @dev Array of owned ids in NFT series representation
  mapping(address => mapping(uint256 => uint256[])) private _ownedSeriesNFTs;

  /// @dev Array of each NFT series representation
  uint256[] public tokenPerSeries;

  /// @dev Addresses whitelisted from minting / banking for gas savings (pairs, routers, etc)
  mapping(address => bool) public whitelist;

  /// @dev EIP-2612 nonces
  mapping(address => uint256) public nonces;

  /// @dev Address bitmask for packed ownership data
  uint256 private constant _BITMASK_ADDRESS = (1 << 160) - 1;

   /// @dev Owned index bitmask for packed series data
  uint256 private constant _BITMASK_SERIES_INDEX = 3 << 254;

  /// @dev Owned index bitmask for packed ownership data
  uint256 private constant _BITMASK_OWNED_INDEX = ((1 << 64) - 1) << 160;

  mapping(uint256 => uint256) private _packedOwnerships;

  function ERC404Minitialize(string memory name_, string memory symbol_, uint8 decimals_,uint256[] memory _initialTokenPerSeries) public {
    name = name_;
    symbol = symbol_;
    tokenPerSeries = _initialTokenPerSeries;

    if (decimals_ < 18) {
      revert DecimalsTooLow();
    }

    decimals = decimals_;
    units = 10 ** decimals;

    // EIP-2612 initialization
    INITIAL_CHAIN_ID = block.chainid;
    INITIAL_DOMAIN_SEPARATOR = _computeDomainSeparator();
  }

  /// @notice Function to find owner of a given ERC-721 token
  function ownerOf(
    uint256 id_
  ) public view virtual returns (address erc721Owner) {
    erc721Owner = _getOwnerOf(id_);

    // If the id_ is beyond the range of minted tokens, is 0, or the token is not owned by anyone, revert.
    if (id_ > _minted || id_ == 0 || erc721Owner == address(0)) {
      revert NotFound();
    }
  }

  function owned(
    address owner_,
    uint256 seriesId
  ) public view virtual returns (uint256[] memory) {
    return _ownedSeriesNFTs[owner_][seriesId];
  }

  function erc721BalanceOf(
    address owner_,
    uint256 seriesId
  ) public view virtual returns (uint256) {
    return _ownedSeriesNFTs[owner_][seriesId].length;
  }

  function erc20BalanceOf(
    address owner_
  ) public view virtual returns (uint256) {
    return balanceOf[owner_];
  }

  function erc20TotalSupply() public view virtual returns (uint256) {
    return totalSupply;
  }

  function erc721TotalSupply() public view virtual returns (uint256) {
    return _minted;
  }

  function erc721TokensBankedInQueue() public view virtual returns (uint256) {
    return _storedERC721Ids.length();
  }

  function getUnits(uint256 valueOrId_) public view returns (uint256) {
        return tokenPerSeries[valueOrId_] * 10 ** decimals;
    }
  
  /// @notice tokenURI must be implemented by child contract
  function tokenURI(uint256 id_) public view virtual returns (string memory);

  /// @notice Function for token approvals
  /// @dev This function assumes the operator is attempting to approve an ERC-721
  ///      if valueOrId is less than the minted count. Note: Unlike setApprovalForAll,
  ///      spender_ must be allowed to be 0x0 so that approval can be revoked.
  function approve(
    address spender_,
    uint256 valueOrId_
  ) public virtual returns (bool) {
    // The ERC-721 tokens are 1-indexed, so 0 is not a valid id and indicates that
    // operator is attempting to set the ERC-20 allowance to 0.
    if (valueOrId_ <= _minted && valueOrId_ > 0) {
      // Intention is to approve as ERC-721 token (id).
      uint256 id = valueOrId_;
      address erc721Owner = _getOwnerOf(id);

      if (
        msg.sender != erc721Owner && !isApprovedForAll[erc721Owner][msg.sender]
      ) {
        revert Unauthorized();
      }

      getApproved[id] = spender_;

      emit ERC721Approval(erc721Owner, spender_, id);
    } else {
      // Prevent granting 0x0 an ERC-20 allowance.
      if (spender_ == address(0)) {
        revert InvalidSpender();
      }

      // Intention is to approve as ERC-20 token (value).
      uint256 value = valueOrId_;
      allowance[msg.sender][spender_] = value;

      emit ERC20Approval(msg.sender, spender_, value);
    }

    return true;
  }

  /// @notice Function for ERC-721 approvals
  function setApprovalForAll(address operator_, bool approved_) public virtual {
    // Prevent approvals to 0x0.
    if (operator_ == address(0)) {
      revert InvalidOperator();
    }
    isApprovedForAll[msg.sender][operator_] = approved_;
    emit ApprovalForAll(msg.sender, operator_, approved_);
  }

  /// @notice Function for mixed transfers from an operator that may be different than 'from'.
  /// @dev This function assumes the operator is attempting to transfer an ERC-721
  ///      if valueOrId is less than or equal to current max id.
  function transferFrom(
    address from_,
    address to_,
    uint256 valueOrId_
  ) public virtual returns (bool) {
    // Prevent transferring tokens from 0x0.
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // Prevent burning tokens to 0x0.
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    if (valueOrId_ <= _minted) {
      // Intention is to transfer as ERC-721 token (id).
      uint256 id = valueOrId_;

      if (from_ != _getOwnerOf(id)) {
        revert Unauthorized();
      }

      // Check that the operator is either the sender or approved for the transfer.
      if (
        msg.sender != from_ &&
        !isApprovedForAll[from_][msg.sender] &&
        msg.sender != getApproved[id]
      ) {
        revert Unauthorized();
      }

      // Transfer 1 * units ERC-20 and 1 ERC-721 token.
      uint256 serieId = getSeriesIndex(id);
      _transferERC20(from_, to_, getUnits(serieId));
      _transferERC721(from_, to_, id);
    } else {
      // Intention is to transfer as ERC-20 token (value).
      
      uint256 value = valueOrId_;
      uint256 allowed = allowance[from_][msg.sender];

      // Check that the operator has sufficient allowance.
      if (allowed != type(uint256).max) {
        allowance[from_][msg.sender] = allowed - value;
      }

      // Transferring ERC-20s directly requires the _transfer function.
      _transferERC20WithERC721(from_, to_, value);
    }

    return true;
  }

  /// @notice Function for ERC-20 transfers.
  /// @dev This function assumes the operator is attempting to transfer as ERC-20
  ///      given this function is only supported on the ERC-20 interface
  function transfer(address to_, uint256 value_) public virtual returns (bool) {
    // Prevent burning tokens to 0x0.
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    // Transferring ERC-20s directly requires the _transfer function.
    return _transferERC20WithERC721(msg.sender, to_, value_);
  }

  /// @notice Function for ERC-721 transfers with contract support.
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_
  ) public virtual {
    safeTransferFrom(from_, to_, id_, "");
  }

  /// @notice Function for ERC-721 transfers with contract support and callback data.
  function safeTransferFrom(
    address from_,
    address to_,
    uint256 id_,
    bytes memory data_
  ) public virtual {

    if (id_ > _minted || id_ == 0) {
      revert InvalidId();
    }
    
    transferFrom(from_, to_, id_);

    if (
      to_.code.length != 0 &&
      ERC721Receiver(to_).onERC721Received(msg.sender, from_, id_, data_) !=
      ERC721Receiver.onERC721Received.selector
    ) {
      revert UnsafeRecipient();
    }
  }

  /// @notice Function for EIP-2612 permits
  function permit(
    address owner_,
    address spender_,
    uint256 value_,
    uint256 deadline_,
    uint8 v_,
    bytes32 r_,
    bytes32 s_
  ) public virtual {
    if (deadline_ < block.timestamp) {
      revert PermitDeadlineExpired();
    }

    if (value_ <= _minted && value_ > 0) {
      revert InvalidApproval();
    }

    if (spender_ == address(0)) {
      revert InvalidSpender();
    }

    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR(),
            keccak256(
              abi.encode(
                keccak256(
                  "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                ),
                owner_,
                spender_,
                value_,
                nonces[owner_]++,
                deadline_
              )
            )
          )
        ),
        v_,
        r_,
        s_
      );

      if (recoveredAddress == address(0) || recoveredAddress != owner_) {
        revert InvalidSigner();
      }

      allowance[recoveredAddress][spender_] = value_;
    }

    emit ERC20Approval(owner_, spender_, value_);
  }

  /// @notice Returns domain initial domain separator, or recomputes if chain id is not equal to initial chain id
  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return
      block.chainid == INITIAL_CHAIN_ID
        ? INITIAL_DOMAIN_SEPARATOR
        : _computeDomainSeparator();
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual returns (bool) {
    return
      interfaceId == type(IERC404).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  /// @notice Internal function to compute domain separator for EIP-2612 permits
  function _computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
          ),
          keccak256(bytes(name)),
          keccak256("1"),
          block.chainid,
          address(this)
        )
      );
  }

  /// @notice This is the lowest level ERC-20 transfer function, which
  ///         should be used for both normal ERC-20 transfers as well as minting.
  /// Note that this function allows transfers to and from 0x0.
  function _transferERC20(
    address from_,
    address to_,
    uint256 value_
  ) internal virtual {
    // Minting is a special case for which we should not check the balance of
    // the sender, and we should increase the total supply.
    if (from_ == address(0)) {
      totalSupply += value_;
    } else {
      // Deduct value from sender's balance.
      balanceOf[from_] -= value_;
    }

    // Update the recipient's balance.
    // Can be unchecked because on mint, adding to totalSupply is checked, and on transfer balance deduction is checked.
    unchecked {
      balanceOf[to_] += value_;
    }

    emit ERC20Transfer(from_, to_, value_);
  }

  /// @notice Consolidated record keeping function for transferring ERC-721s.
  /// @dev Assign the token to the new owner, and remove from the old owner.
  /// Note that this function allows transfers to and from 0x0.
  function _transferERC721(
    address from_,
    address to_,
    uint256 id_
  ) internal virtual {
    uint256 serieId = getSeriesIndex(id_);

    // If this is not a mint, handle record keeping for transfer from previous owner.
    if (from_ != address(0)) {
      // On transfer of an NFT, any previous approval is reset.
      delete getApproved[id_];
      uint256 updatedId = _ownedSeriesNFTs[from_][serieId][_ownedSeriesNFTs[from_][serieId].length - 1];

      if (updatedId != id_) {
        uint256 updatedIndex = _getOwnedIndex(id_);
        // update _owned for sender
        _ownedSeriesNFTs[from_][serieId][updatedIndex] = updatedId;
        // update index for the moved id
        _setOwnedIndex(updatedId, updatedIndex);
      }

      // pop
      _ownedSeriesNFTs[from_][serieId].pop();
    }

    if (to_ != address(0)) {
      // Update owner of the token to the new owner.
      _setOwnerOf(id_, to_);
      // Push token onto the new owner's stack.
      _ownedSeriesNFTs[to_][serieId].push(id_);
      // Update index for new owner's stack.
      _setOwnedIndex(id_, _ownedSeriesNFTs[to_][serieId].length - 1);
    } else {
      delete _ownedData[id_];
    }

    emit Transfer(from_, to_, id_);
  }



  function encodeOperation(uint128 mintCount, uint128 burnCount) internal pure returns (uint256) {
      return (uint256(mintCount) << 128) | uint256(burnCount);
  }


  function decodeOperation(uint256 data) internal pure returns (uint128 mintCount, uint128 burnCount) {
      mintCount = uint128(data >> 128);
      burnCount = uint128(data);
  }

  function _processSeriesOperations(address account, uint256[] memory operations) internal {
      for (uint256 i = 0; i < operations.length; i++) {
          (uint128 mintCount, uint128 burnCount) = decodeOperation(operations[i]);

          for (uint256 j = 0; j < mintCount; j++) {
              _retrieveOrMintERC721(account, i);
          }

          for (uint256 k = 0; k < burnCount; k++) {
              _withdrawAndStoreERC721(account, i);
          }
      }
  }

  function _transferERC20WithERC721(
      address from_,
      address to_,
      uint256 value_
  ) internal virtual returns (bool) {
      _transferERC20(from_, to_, value_);

      
      if (!whitelist[from_]) {
          
          uint256[] memory senderOperations = _calculateOperations(from_, value_, false);
          _processSeriesOperations(from_, senderOperations);
      }
      if (!whitelist[to_]) {
          
          uint256[] memory receiverOperations = _calculateOperations(to_, value_, true);
          _processSeriesOperations(to_, receiverOperations);
      }

      return true;
  }


  function _calculateOperations(
      address account,
      uint256 valueChange,
      bool isReceiver
  ) internal view returns (uint256[] memory) {
      uint256 allSeries = tokenPerSeries.length;
      uint256[] memory operations = new uint256[](allSeries);

      uint256 newBalance = balanceOf[account];
      uint256 oldBalance = isReceiver ? newBalance - valueChange : newBalance + valueChange;

      uint256 remainingNewBalance = newBalance;
      uint256 remainingOldBalance = oldBalance;

      for (uint256 i = allSeries; i > 0; i--) {
          uint256 index = i - 1; 
          uint256 tokenPerNFT = getUnits(index);

          uint256 nftCountBeforeChange = remainingOldBalance / tokenPerNFT;
          uint256 nftCountAfterChange = remainingNewBalance / tokenPerNFT;

          uint256 diff;
          if (isReceiver) {
              diff = nftCountAfterChange > nftCountBeforeChange ? nftCountAfterChange - nftCountBeforeChange : 0;
          } else {
              diff = nftCountBeforeChange > nftCountAfterChange ? nftCountBeforeChange - nftCountAfterChange : 0;
          }

          if (diff > 0) {
              operations[index] = encodeOperation(isReceiver ? uint128(diff) : 0, isReceiver ? 0 : uint128(diff));
          }

          remainingNewBalance -= nftCountAfterChange * tokenPerNFT;
          remainingOldBalance -= nftCountBeforeChange * tokenPerNFT;
      }

      return operations;
  }



  /// @notice Internal function for ERC20 minting
  /// @dev This function will allow minting of new ERC20s.
  ///      If mintCorrespondingERC721s_ is true, it will also mint the corresponding ERC721s.
  function _mintERC20(
    address to_,
    uint256 value_,
    bool mintCorrespondingERC721s_
  ) internal virtual {
    /// You cannot mint to the zero address (you can't mint and immediately burn in the same transfer).
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    _transferERC20(address(0), to_, value_);

    // If mintCorrespondingERC721s_ is true, mint the corresponding ERC721s.
    if (mintCorrespondingERC721s_) {
        uint256 allSeries = tokenPerSeries.length;
        for (uint256 i = allSeries; i > 0; i--) {
            uint256 index = i - 1; 
            uint256 tokenPerNFT = getUnits(index);
            if (value_ >= tokenPerNFT) { 
                uint256 nftsToRetrieveOrMint = value_ / tokenPerNFT;
                for (uint256 j = 0; j < nftsToRetrieveOrMint; j++) {
                    unchecked {
                        value_ -= tokenPerNFT;
                    }
                    _retrieveOrMintERC721(to_, index);
                }
            }
        }
    }

  }

  /// @notice Internal function for ERC-721 minting and retrieval from the bank.
  /// @dev This function will allow minting of new ERC-721s up to the total fractional supply. It will
  ///      first try to pull from the bank, and if the bank is empty, it will mint a new token.
  function _retrieveOrMintERC721(address to_,uint256 serieId) internal virtual {
    if (to_ == address(0)) {
      revert InvalidRecipient();
    }

    uint256 id;

    if (!DoubleEndedQueue.empty(_storedERC721Ids)) {
      // If there are any tokens in the bank, use those first.
      // Pop off the end of the queue (FIFO).
      console.log("here");
      id = _storedERC721Ids.popBack();
      _setSeriesIndex(id, serieId);
    } else {
      // Otherwise, mint a new token, should not be able to go over the total fractional supply.
      _minted++;
      id = _minted;
      _setSeriesIndex(id, serieId);
    }

    address erc721Owner = _getOwnerOf(id);

    // The token should not already belong to anyone besides 0x0 or this contract.
    // If it does, something is wrong, as this should never happen.
    if (erc721Owner != address(0)) {
      revert AlreadyExists();
    }

    // Transfer the token to the recipient, either transferring from the contract's bank or minting.
    _transferERC721(erc721Owner, to_, id);
  }

  /// @notice Internal function for ERC-721 deposits to bank (this contract).
  /// @dev This function will allow depositing of ERC-721s to the bank, which can be retrieved by future minters.
  function _withdrawAndStoreERC721(address from_,uint256 serieId) internal virtual {
    if (from_ == address(0)) {
      revert InvalidSender();
    }

    // Retrieve the latest token added to the owner's stack (LIFO).
    uint256 id = _ownedSeriesNFTs[from_][serieId][_ownedSeriesNFTs[from_][serieId].length - 1];

    // Transfer the token to the contract.
    _transferERC721(from_, address(0), id);

    // Record the token in the contract's bank queue.
    _storedERC721Ids.pushFront(id);
  }

  /// @notice Initialization function to set pairs / etc, saving gas by avoiding mint / burn on unnecessary targets
  function _setWhitelist(address target_, bool state_) internal virtual {
    // If the target has at least 1 full ERC-20 token, they should not be removed from the whitelist
    // because if they were and then they attempted to transfer, it would revert as they would not
    // necessarily have ehough ERC-721s to bank.
    if (erc20BalanceOf(target_) >= units && !state_) {
      revert CannotRemoveFromWhitelist();
    }
    whitelist[target_] = state_;
  }

  function _getOwnerOf(
    uint256 id_
  ) public view virtual returns (address ownerOf_) {
    uint256 data = _ownedData[id_];

    assembly {
      ownerOf_ := and(data, _BITMASK_ADDRESS)
    }
  }

  function getSeriesIndex(uint256 id_) public view virtual returns (uint256) {
      uint256 data = _ownedData[id_];


      return (data & _BITMASK_SERIES_INDEX) >> 254;
  }

  function _setSeriesIndex(uint256 id_, uint256 seriesIndex_) internal virtual {
      require(seriesIndex_ < 4, "Series index out of bounds"); 

      uint256 data = _ownedData[id_];


      data &= ~_BITMASK_SERIES_INDEX;


      data |= (seriesIndex_ << 254);

      _ownedData[id_] = data;
  }
  
  function _setOwnerOf(uint256 id_, address owner_) internal virtual {
      uint256 data = _ownedData[id_];
     
      data &= ~_BITMASK_ADDRESS;

      data |= uint256(uint160(owner_));
      _ownedData[id_] = data;
  }

  function _getOwnedIndex(uint256 id_) public view returns (uint256 ownedIndex_) {
      uint256 data = _ownedData[id_];
    
      ownedIndex_ = (data & _BITMASK_OWNED_INDEX) >> 160;
  }
  function _setOwnedIndex(uint256 id_, uint256 index_) internal virtual {
      uint256 data = _ownedData[id_];

      require(index_ < (1 << 64), "Owned index overflow");

 
      data &= ~_BITMASK_OWNED_INDEX;

      data |= (index_ << 160);
      _ownedData[id_] = data;
  }
}