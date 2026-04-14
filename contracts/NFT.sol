// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {
    
    // 代币ID计数器
    uint256 private _tokenIdCounter;
    
    // 元数据的基础URI
    string private _baseTokenURI;
    
    // 跟踪代币URI是否被冻结的映射
    mapping(uint256 => bool) private _uriFrozen;
    
    event TokenMinted(address indexed to, uint256 indexed tokenId, string uri);
    event URIFrozen(uint256 indexed tokenId);
    
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI
    ) ERC721(name, symbol) Ownable(msg.sender) {
        _baseTokenURI = baseURI;
    }
    
    /**
     * @notice 铸造新的 NFT
     * @param to 代币铸造地址
     * @param uri 精准适配 NFT
     * @return tokenId 新铸造代币的 ID
     */
    function mint(address to, string memory uri) public returns (uint256) {
        require(to != address(0), unicode"NFT：铸造到零地址");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        
        emit TokenMinted(to, tokenId, uri);
        
        return tokenId;
    }
    
    /**
     * @notice 批量铸造多个NFT
     * @param to 代币铸造地址
     * @param uris 代币URI数组
     * @return tokenIds 新铸造代币的ID数组
     */
    function batchMint(address to, string[] memory uris) public returns (uint256[] memory) {
        require(to != address(0), unicode"NFT：铸造到零地址");
        require(uris.length > 0, unicode"NFT：URI数组为空");
        require(uris.length <= 50, unicode"NFT：批量大小过大");
        
        uint256[] memory tokenIds = new uint256[](uris.length);
        
        for (uint256 i = 0; i < uris.length; i++) {
            uint256 tokenId = _tokenIdCounter;
            _tokenIdCounter++;
            
            _safeMint(to, tokenId);
            _setTokenURI(tokenId, uris[i]);
            
            tokenIds[i] = tokenId;
            
            emit TokenMinted(to, tokenId, uris[i]);
        }
        
        return tokenIds;
    }
    
    /**
     * @notice 设置所有代币的基础URI
     * @param baseURI 新的基础URI
     */
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }
    
    /**
     * @notice 获取基础URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
    
    /**
     * @notice 检查代币是否存在
     * @param tokenId 要检查的代币ID
     */
    function exists(uint256 tokenId) public view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
    
    /**
     * @notice 获取已铸造的代币总数
     */
    function totalMinted() public view returns (uint256) {
        return _tokenIdCounter;
    }
    
    /**
     * @notice 获取地址拥有的所有代币ID
     * @param owner 要查询的地址
     */
    function getTokensByOwner(address owner) public view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }
    
    // The following functions are overrides required by Solidity
    
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}