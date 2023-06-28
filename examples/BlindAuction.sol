// SPDX-License-Identifier: BSD-3-Clause-Clear

pragma solidity >=0.8.13 <0.9.0;

import "../lib/TFHE.sol";

import "./abstract/EIP712WithModifier.sol";

import "./EncryptedERC20.sol";

contract BlindAuction is EIP712WithModifier {
    uint public endTime;

    address public beneficiary;

    // Current highest bid.
    euint32 internal highestBid;

    // Mapping from bidder to their bid value.
    mapping(address => euint32) public bids;

    // Number of bid
    uint public bidCounter;

    // The token contract used for encrypted bids.
    EncryptedERC20 public tokenContract;

    // Whether the auction object has been claimed.
    bool public objectClaimed;

    // If the token has been transferred to the beneficiary
    bool public tokenTransferred;

    bool public stoppable;

    bool public manuallyStopped = false;

    // The function has been called too early.
    // Try again at `time`.
    error TooEarly(uint time);
    // The function has been called too late.
    // It cannot be called after `time`.
    error TooLate(uint time);

    event Winner(address who);

    constructor(
        address _beneficiary,
        EncryptedERC20 _tokenContract,
        uint biddingTime,
        bool isStoppable
    ) EIP712WithModifier("Authorization token", "1") {
        beneficiary = _beneficiary;
        tokenContract = _tokenContract;
        endTime = block.timestamp + biddingTime;
        objectClaimed = false;
        tokenTransferred = false;
        bidCounter = 0;
        stoppable = isStoppable;
    }

    // Bid an `encryptedValue`.
    function bid(bytes calldata encryptedValue) public onlyBeforeEnd {
        euint32 value = TFHE.asEuint32(encryptedValue);
        euint32 existingBid = bids[msg.sender];
        if (TFHE.isInitialized(existingBid)) {
            euint32 isHigher = TFHE.lt(existingBid, value);
            // Update bid with value
            bids[msg.sender] = TFHE.cmux(isHigher, value, existingBid);
            // Transfer only the difference between existing and value
            euint32 toTransfer = TFHE.sub(value, existingBid);
            // Transfer only if bid is higher
            euint32 amount = TFHE.mul(isHigher, toTransfer);
            tokenContract.transferFrom(msg.sender, address(this), amount);
        } else {
            bidCounter++;
            bids[msg.sender] = value;
            tokenContract.transferFrom(msg.sender, address(this), value);
        }
        euint32 currentBid = bids[msg.sender];
        if (!TFHE.isInitialized(highestBid)) {
            highestBid = currentBid;
        } else {
            highestBid = TFHE.cmux(
                TFHE.lt(highestBid, currentBid),
                currentBid,
                highestBid
            );
        }
    }

    function getBid(
        bytes32 publicKey,
        bytes calldata signature
    )
        public
        view
        onlySignedPublicKey(publicKey, signature)
        returns (bytes memory)
    {
        if (TFHE.isInitialized(bids[msg.sender])) {
            return TFHE.reencrypt(bids[msg.sender], publicKey);
        } else {
            return TFHE.reencrypt(TFHE.asEuint32(0), publicKey);
        }
    }

    // Returns the user bid
    function stop() public {
        require(stoppable);
        manuallyStopped = true;
    }

    // Returns an encrypted value of 0 or 1 under the caller's public key, indicating
    // if the caller has the highest bid.
    function doIHaveHighestBid(
        bytes32 publicKey,
        bytes calldata signature
    )
        public
        view
        onlyAfterEnd
        onlySignedPublicKey(publicKey, signature)
        returns (bytes memory)
    {
        if (
            TFHE.isInitialized(highestBid) &&
            TFHE.isInitialized(bids[msg.sender])
        ) {
            return
                TFHE.reencrypt(
                    TFHE.le(highestBid, bids[msg.sender]),
                    publicKey
                );
        } else {
            return TFHE.reencrypt(TFHE.asEuint32(0), publicKey);
        }
    }

    // Claim the object. Succeeds only if the caller has the highest bid.
    function claim() public onlyAfterEnd {
        require(!objectClaimed);
        TFHE.req(TFHE.le(highestBid, bids[msg.sender]));

        objectClaimed = true;
        bids[msg.sender] = euint32.wrap(0);
        emit Winner(msg.sender);
    }

    // Transfer token to beneficiary
    function auctionEnd() public onlyAfterEnd {
        require(!tokenTransferred);

        tokenTransferred = true;
        tokenContract.transfer(beneficiary, highestBid);
    }

    // Withdraw a bid from the auction to the caller once the auction has stopped.
    function withdraw() public onlyAfterEnd {
        euint32 bidValue = bids[msg.sender];
        if (!objectClaimed) {
            TFHE.req(TFHE.lt(bidValue, highestBid));
        }
        tokenContract.transfer(msg.sender, bidValue);
        bids[msg.sender] = euint32.wrap(0);
    }

    modifier onlyBeforeEnd() {
        if (block.timestamp >= endTime || manuallyStopped == true)
            revert TooLate(endTime);
        _;
    }

    modifier onlyAfterEnd() {
        if (block.timestamp <= endTime && manuallyStopped == false)
            revert TooEarly(endTime);
        _;
    }
}
