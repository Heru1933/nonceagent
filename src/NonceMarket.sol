// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface INonceAgent {
    function ownerOf(uint256 tokenId) external view returns (address);
    function getApproved(uint256 tokenId) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

/// @title NonceMarket — the built-in marketplace for NonceAgent NFTs
/// @notice Fixed-price listings traded directly on the project website.
///         No custody: the NFT stays in the seller's wallet until the moment
///         of sale (the market only needs an ERC-721 approval). No protocol
///         fee — the seller receives 100% of the price. Listings go stale if
///         the seller moves the NFT or revokes approval; a stale listing can
///         be cleaned up by anyone via `cleanStale`.
contract NonceMarket {
    struct Listing {
        address seller;
        uint256 price; // wei
    }

    INonceAgent public immutable nft;

    mapping(uint256 => Listing) public listings;
    uint256[] public listedTokenIds;
    mapping(uint256 => uint256) private _listedIndex; // tokenId -> index+1

    bool private _locked;

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event PriceUpdated(uint256 indexed tokenId, uint256 price);
    event Cancelled(uint256 indexed tokenId, address indexed seller);
    event Sold(uint256 indexed tokenId, address indexed seller, address indexed buyer, uint256 price);

    error NotOwner();
    error BadPrice();
    error NotListed();
    error NotSeller();
    error WrongPayment();
    error StaleListing();
    error NotApproved();
    error Reentrant();
    error PaymentFailed();

    modifier nonReentrant() {
        if (_locked) revert Reentrant();
        _locked = true;
        _;
        _locked = false;
    }

    constructor(address nft_) {
        nft = INonceAgent(nft_);
    }

    // ---------------- trading ----------------

    /// @notice List your NonceAgent for sale at `price` wei. Approve this
    ///         contract on the NFT first (approve or setApprovalForAll).
    function list(uint256 tokenId, uint256 price) external {
        if (nft.ownerOf(tokenId) != msg.sender) revert NotOwner();
        if (price == 0) revert BadPrice();
        if (!_isApproved(msg.sender, tokenId)) revert NotApproved();
        if (listings[tokenId].seller == address(0)) {
            _listedIndex[tokenId] = listedTokenIds.length + 1;
            listedTokenIds.push(tokenId);
        }
        listings[tokenId] = Listing(msg.sender, price);
        emit Listed(tokenId, msg.sender, price);
    }

    function updatePrice(uint256 tokenId, uint256 price) external {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        if (l.seller != msg.sender) revert NotSeller();
        if (price == 0) revert BadPrice();
        listings[tokenId].price = price;
        emit PriceUpdated(tokenId, price);
    }

    function cancel(uint256 tokenId) external {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        if (l.seller != msg.sender) revert NotSeller();
        _remove(tokenId);
        emit Cancelled(tokenId, msg.sender);
    }

    /// @notice Buy a listed NonceAgent. Pay exactly the listing price.
    function buy(uint256 tokenId) external payable nonReentrant {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        if (msg.value != l.price) revert WrongPayment();
        if (nft.ownerOf(tokenId) != l.seller || !_isApproved(l.seller, tokenId)) revert StaleListing();

        _remove(tokenId);
        nft.transferFrom(l.seller, msg.sender, tokenId);
        (bool ok,) = payable(l.seller).call{value: msg.value}("");
        if (!ok) revert PaymentFailed();
        emit Sold(tokenId, l.seller, msg.sender, msg.value);
    }

    /// @notice Remove a listing whose seller no longer owns the NFT or has
    ///         revoked approval. Callable by anyone.
    function cleanStale(uint256 tokenId) external {
        Listing memory l = listings[tokenId];
        if (l.seller == address(0)) revert NotListed();
        if (nft.ownerOf(tokenId) == l.seller && _isApproved(l.seller, tokenId)) revert StaleListing();
        _remove(tokenId);
        emit Cancelled(tokenId, l.seller);
    }

    // ---------------- views ----------------

    function listedCount() external view returns (uint256) {
        return listedTokenIds.length;
    }

    function getListing(uint256 tokenId) external view returns (address seller, uint256 price) {
        Listing memory l = listings[tokenId];
        return (l.seller, l.price);
    }

    function _isApproved(address seller, uint256 tokenId) internal view returns (bool) {
        return nft.getApproved(tokenId) == address(this) || nft.isApprovedForAll(seller, address(this));
    }

    function _remove(uint256 tokenId) internal {
        uint256 idx = _listedIndex[tokenId];
        if (idx == 0) return;
        uint256 i = idx - 1;
        uint256 last = listedTokenIds[listedTokenIds.length - 1];
        listedTokenIds[i] = last;
        _listedIndex[last] = idx;
        listedTokenIds.pop();
        delete _listedIndex[tokenId];
        delete listings[tokenId];
    }
}
