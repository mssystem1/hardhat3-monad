// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FortuneCookiesAI is ERC721, Ownable, ERC2981, ReentrancyGuard {
    using Strings for uint256;

    /* ========= existing events kept ========= */
    event CookieMinted(address indexed minter, uint256 indexed tokenId, string fortune);
    event CookieMintedWithImage(address indexed minter, uint256 indexed tokenId, string fortune, string imageURI);

    /* ========= ids, fortunes, images ========= */
    uint256 private _nextId = 1;
    mapping(uint256 => string) private _fortuneByToken;
    mapping(uint256 => string) private _imageURIByToken;

    /* ========= NEW: record “who minted which id” ========= */
    struct MintRecord { uint256 id; address wallet; bool withImage; }
    MintRecord[] private _mints;                 // ordered history
    mapping(uint256 => address) private _minterOf; // minter by tokenId (immutable after mint)

    /* ========= logo upload (kept from your version) ========= */
    string  private _logoMIME;
    bytes   private _logoRaw;
    string  private _logoB64;
    bool    private _logoSealed;

    /* ========= pricing/receiver (chain-agnostic; on Base it’s ETH) ========= */
    uint256 public mintPrice;     // in wei
    address public fundsReceiver;

    /* ========= optional: who used which flow (kept & compatible) ========= */
    address[] private _textMinters;
    address[] private _imageMinters;

    constructor(string memory logoMIME)
        ERC721("Fortune Cookies AI (MONAD)", "COOKIE")
        Ownable(msg.sender)
    {
        _logoMIME = logoMIME;
        mintPrice = 0;
        fundsReceiver = msg.sender;
    }

    /* ---------------- Admin ---------------- */
    function setMintPrice(uint256 newPrice) external onlyOwner { mintPrice = newPrice; }
    function setFundsReceiver(address to) external onlyOwner { require(to != address(0), "zero addr"); fundsReceiver = to; }

    // Royalties
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner { _setDefaultRoyalty(receiver, feeNumerator); }
    function deleteDefaultRoyalty() external onlyOwner { _deleteDefaultRoyalty(); }

    // Logo upload (raw bytes in chunks)
    function resetLogo() external onlyOwner { _logoRaw = ""; _logoSealed = false; }
    function appendLogoChunk(bytes calldata chunk) external onlyOwner { require(!_logoSealed, "logo sealed"); require(chunk.length > 0, "empty"); _logoRaw = bytes.concat(_logoRaw, chunk); }
    function finalizeLogo() external onlyOwner { _logoSealed = true; }
    function setLogoMIME(string calldata mime) external onlyOwner { _logoMIME = mime; }

    /* ---------------- Mint ---------------- */
    function mintWithFortune(string calldata fortune) external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value >= mintPrice, "insufficient funds");
        _requireShort(fortune);

        tokenId = _nextId++;
        _safeMint(msg.sender, tokenId);
        _fortuneByToken[tokenId] = fortune;

        // recorders
        _textMinters.push(msg.sender);
        _minterOf[tokenId] = msg.sender;
        _mints.push(MintRecord({ id: tokenId, wallet: msg.sender, withImage: false }));

        emit CookieMinted(msg.sender, tokenId, fortune);
    }

    function mintWithImage(string calldata fortune, string calldata imageURI) external payable nonReentrant returns (uint256 tokenId) {
        require(msg.value >= mintPrice, "insufficient funds");
        _requireShort(fortune);
        require(bytes(imageURI).length >= 6, "bad imageURI");

        tokenId = _nextId++;
        _safeMint(msg.sender, tokenId);
        _fortuneByToken[tokenId] = fortune;
        _imageURIByToken[tokenId] = imageURI;

        // recorders
        _imageMinters.push(msg.sender);
        _minterOf[tokenId] = msg.sender;
        _mints.push(MintRecord({ id: tokenId, wallet: msg.sender, withImage: true }));

        emit CookieMintedWithImage(msg.sender, tokenId, fortune, imageURI);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "no funds");
        payable(fundsReceiver).transfer(bal);
    }

    /* ---------------- Reads ---------------- */
    function getFortune(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "no token");
        return _fortuneByToken[tokenId];
    }

    function getImageURI(uint256 tokenId) public view returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "no token");
        return _imageURIByToken[tokenId];
    }

    // existing helpers for your dapp (kept)
    function getTextMinters() external view returns (address[] memory) { return _textMinters; }
    function getImageMinters() external view returns (address[] memory) { return _imageMinters; }

    /* ===== NEW PUBLIC READS: “ID, wallet address” ===== */

    /// Return the original minter of a specific tokenId.
    function minterOf(uint256 tokenId) external view returns (address) {
        address w = _minterOf[tokenId];
        require(w != address(0), "no token");
        return w;
    }

    /// Total number of mints recorded.
    function totalMinted() external view returns (uint256) {
        return _mints.length;
    }

    /// Paginated read of all mints as parallel arrays: IDs and wallet addresses.
	function getAllMints() external view returns (MintRecord[] memory) {
		return _mints;
	}
	
    /* ---------------- Metadata ---------------- */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "no token");
        string memory fortune = _fortuneByToken[tokenId];
        string memory imageURI = _imageURIByToken[tokenId];

        if (bytes(imageURI).length > 0) {
            string memory jsonExternal = Base64.encode(
                abi.encodePacked(
                    '{"name":"COOKIE #', tokenId.toString(),
                    '","description":"AI-generated fortune with AI-generated image.",',
                    '"attributes":[{"trait_type":"fortune","value":"', _escapeJSON(fortune), '"}],',
                    '"image":"', imageURI, '"}'
                )
            );
            return string.concat("data:application/json;base64,", jsonExternal);
        }

        // Base-themed SVG
        string memory svg = string.concat(
            _svgHead(),   // Base colors
            _svgLogo(),
            _svgFortune(_escapeXML(fortune)),
            _svgFoot(tokenId)
        );

        string memory jsonOnchain = Base64.encode(
            abi.encodePacked(
                '{"name":"COOKIE #', tokenId.toString(),
                '","description":"AI-generated fortune. On-chain SVG with Base styling.",',
                '"image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '"}'
            )
        );
        return string.concat("data:application/json;base64,", jsonOnchain);
    }

    function logoInfo() external view returns (string memory mime, uint256 rawBytes, uint256 legacyB64Chars, bool isSealed) {
        return (_logoMIME, _logoRaw.length, bytes(_logoB64).length, _logoSealed);
    }

    /* ============================= Helpers ============================= */

    function _requireShort(string memory s) internal pure {
        bytes memory b = bytes(s);
        require(b.length > 0, "empty");
        require(b.length <= 240, "too long");
    }

    function _escapeJSON(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 2);
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == '"' || c == '\\') { out[j++] = '\\'; out[j++] = c; }
            else if (c == 0x0A) { out[j++] = '\\'; out[j++] = 'n'; }
            else if (c == 0x0D) { out[j++] = '\\'; out[j++] = 'r'; }
            else if (c == 0x09) { out[j++] = '\\'; out[j++] = 't'; }
            else { out[j++] = c; }
        }
        assembly { mstore(out, j) }
        return string(out);
    }

    function _escapeXML(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        bytes memory out = new bytes(b.length * 6);
        uint256 j = 0;
        for (uint256 i = 0; i < b.length; i++) {
            bytes1 c = b[i];
            if (c == '&') { out[j++] = bytes1("&"); out[j++] = "a"; out[j++] = "m"; out[j++] = "p"; out[j++] = ";"; }
            else if (c == '<') { out[j++] = bytes1("&"); out[j++] = "l"; out[j++] = "t"; out[j++] = ";"; }
            else if (c == '>') { out[j++] = bytes1("&"); out[j++] = "g"; out[j++] = "t"; out[j++] = ";"; }
            else { out[j++] = c; }
        }
        assembly { mstore(out, j) }
        return string(out);
    }

    /* ----------------------------- SVG parts (Base theme) ----------------------------- */

    // Base blue: #0052FF; darker accent: #003BDD; light accent: #A6BFFF
    function _svgHead() internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "<svg xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink' width='800' height='500' viewBox='0 0 800 500'>",
                "<defs>",
                  "<linearGradient id='bg' x1='0' y1='0' x2='1' y2='1'>",
					"<stop offset='0%' stop-color='#5441bf'/>",
					"<stop offset='100%' stop-color='#6E54FF'/>",
                  "</linearGradient>",
                  "<filter id='s'><feDropShadow dx='0' dy='4' stdDeviation='6' flood-color='#000' flood-opacity='0.28'/></filter>",
                "</defs>",
                "<rect width='100%' height='100%' fill='url(#bg)'/>",
                "<g filter='url(#s)'>",
                  "<rect x='120' y='100' width='560' height='300' rx='26' ry='26' fill='#ffffff' opacity='0.98'/>"
            )
        );
    }

    function _svgLogo() internal view returns (string memory) {
        string memory imgTag;
        if (_logoRaw.length > 0) {
            string memory dataUri = string(abi.encodePacked("data:", _logoMIME, ";base64,", Base64.encode(_logoRaw)));
            imgTag = string(abi.encodePacked(
                "<image x='340' y='110' width='120' height='80' href='", dataUri,
                "' xlink:href='", dataUri, "' preserveAspectRatio='xMidYMid meet'/>"
            ));
        } else if (bytes(_logoB64).length > 0) {
            imgTag = string(abi.encodePacked(
                "<image x='340' y='110' width='120' height='80' href='data:", _logoMIME, ";base64,", _logoB64,
                "' xlink:href='data:", _logoMIME, ";base64,", _logoB64, "' preserveAspectRatio='xMidYMid meet'/>"
            ));
        } else {
            imgTag = "<rect x='340' y='110' width='120' height='80' fill='#E6ECFF' stroke='#A6BFFF' stroke-width='1'/>";
        }
        return string(
            abi.encodePacked(
                imgTag,
                "<text x='400' y='220' text-anchor='middle' font-family='sans-serif' font-size='24' fill='#0052FF'>Your fortune:</text>"
            )
        );
    }

    function _svgFortune(string memory fortuneEsc) internal pure returns (string memory) {
        return string.concat(
            "<foreignObject x='160' y='240' width='480' height='130'>",
              "<div xmlns='http://www.w3.org/1999/xhtml' style='font-family:sans-serif;font-size:22px;color:#0B1B46;text-align:center;line-height:1.35;'>",
                fortuneEsc,
              "</div>",
            "</foreignObject>"
        );
    }

    function _svgFoot(uint256 tokenId) internal pure returns (string memory) {
        return string.concat(
            "</g>",
            "<text x='400' y='480' text-anchor='middle' font-family='monospace' font-size='14' fill='#ffffff'>COOKIE #",
              tokenId.toString(),
            "</text>",
            "</svg>"
        );
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}