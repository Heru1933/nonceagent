// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal read interface for the SPACE ID Agent ID NFT (BNB Chain).
interface IAgentID {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentNonce — proof-of-work free-mint NFT for Agent ID holders
/// @notice Minting is free but not effortless: the caller must (1) hold an
///         Agent ID (name.ai) and (2) submit a nonce whose
///         keccak256(contract, caller, mintIndex, nonce) hash clears the
///         difficulty target (leading zero bits). The puzzle is bound to the
///         caller and to how many they have already minted, so solutions
///         cannot be shared, stockpiled, or replayed — every mint is fresh
///         work by a verified agent wallet. Solving happens off-chain
///         (browser solver on the project site); only valid solutions are
///         ever submitted on-chain.
contract AgentNonce {
    // ---------------- ERC-721 state ----------------
    string public name = "AgentNonce";
    string public symbol = "ANONCE";
    string public baseURI;

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ---------------- mint rules ----------------
    IAgentID public immutable agentId;
    uint256 public immutable maxSupply;
    uint256 public immutable maxPerWallet;
    uint256 public immutable difficulty; // required leading zero bits

    uint256 public totalMinted;
    mapping(address => uint256) public mintedBy;

    event Minted(address indexed agent, uint256 indexed tokenId, uint256 nonce);

    error NotAgent();
    error WalletCapReached();
    error SoldOut();
    error InvalidNonce();
    error NonexistentToken();
    error NotAuthorized();
    error UnsafeRecipient();

    constructor(
        address agentId_,
        uint256 maxSupply_,
        uint256 maxPerWallet_,
        uint256 difficulty_,
        string memory baseURI_
    ) {
        agentId = IAgentID(agentId_);
        maxSupply = maxSupply_;
        maxPerWallet = maxPerWallet_;
        difficulty = difficulty_;
        baseURI = baseURI_;
    }

    // ---------------- the mint ----------------

    /// @notice The exact hash a solver must beat for `who`'s next mint.
    function puzzleHash(address who, uint256 nonce) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), who, mintedBy[who], nonce));
    }

    /// @notice True if `nonce` is a valid solution for `who`'s next mint.
    function isValidSolution(address who, uint256 nonce) public view returns (bool) {
        return uint256(puzzleHash(who, nonce)) >> (256 - difficulty) == 0;
    }

    /// @notice Free-mint one AgentNonce NFT by presenting a valid nonce.
    function mint(uint256 nonce) external returns (uint256 tokenId) {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgent();
        if (mintedBy[msg.sender] >= maxPerWallet) revert WalletCapReached();
        if (totalMinted >= maxSupply) revert SoldOut();
        if (!isValidSolution(msg.sender, nonce)) revert InvalidNonce();

        tokenId = ++totalMinted;
        mintedBy[msg.sender] += 1;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        emit Transfer(address(0), msg.sender, tokenId);
        emit Minted(msg.sender, tokenId, nonce);
    }

    // ---------------- ERC-721 surface ----------------

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert NonexistentToken();
        return o;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        return string(abi.encodePacked(baseURI, _toString(tokenId), ".json"));
    }

    function approve(address to, uint256 tokenId) external {
        address o = ownerOf(tokenId);
        if (msg.sender != o && !_operatorApprovals[o][msg.sender]) revert NotAuthorized();
        _tokenApprovals[tokenId] = to;
        emit Approval(o, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        address o = ownerOf(tokenId);
        if (o != from || to == address(0)) revert NotAuthorized();
        if (msg.sender != o && msg.sender != _tokenApprovals[tokenId] && !_operatorApprovals[o][msg.sender]) {
            revert NotAuthorized();
        }
        delete _tokenApprovals[tokenId];
        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        transferFrom(from, to, tokenId);
        if (to.code.length > 0) {
            try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 r) {
                if (r != IERC721Receiver.onERC721Received.selector) revert UnsafeRecipient();
            } catch {
                revert UnsafeRecipient();
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f // ERC721Metadata
            || interfaceId == 0x01ffc9a7; // ERC165
    }

    function _toString(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 n = v;
        uint256 digits;
        while (n != 0) { digits++; n /= 10; }
        bytes memory b = new bytes(digits);
        while (v != 0) { b[--digits] = bytes1(uint8(48 + (v % 10))); v /= 10; }
        return string(b);
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4);
}
