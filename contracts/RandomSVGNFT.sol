// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "./lib/URI.sol";

/**
 * @title A contract to create a collection of NFTs that output random SVG code in their URI
 * @author leovct
 * @dev Compliant with OpenZeppelin's implementation of the ERC721 spec draft
 */
contract RandomSVGNFT is ERC721URIStorage, VRFConsumerBase {
    using Counters for Counters.Counter;
    using Strings for uint256;
    
    Counters.Counter private _tokenIdCounter;

    // Chainlink VRF parameters
    bytes32 private keyHash;
    uint256 private fee;

    // SVG parameters
    uint256 public maxNumberOfPaths;
    uint256 public maxNumberOfPathCommands;
    uint256 public size;
    string[2] public pathCommands;
    string[6] public colors;

    mapping(bytes32 => address) private requestIdToSender;
    mapping(bytes32 => uint256) private requestIdToTokenId;
    mapping(uint256 => uint256) private tokenIdToRandomNumber;

    event RequestedRandomSVGNFT(
        bytes32 indexed requestId,
        uint256 indexed tokenId
    );
    event ReceivedRandomNumber(
        bytes32 indexed requestId,
        uint256 indexed tokenId,
        uint256 randomNumber
    );
    event CreatedRandomSVGNFT(uint256 indexed tokenId, string tokenURI);

    /**
     * @notice Constructor of the RandomSVGNFT smart contract
     * @param _vrfCoordinator address of the Chainlink VRF Coordinator. This component proves that 
     the generator random number is actually random and not pseudo-random.
     * @param _linkToken LINK token address on the corresponding network (Ethereum, Polygon, BSC, 
     etc). This is the currency used to pay the fees on the Chainlink network.
     * @param _keyHash public key against which randomness is generated
     * @param _fee fee required to fulfill a VRF request (varies by network)
     */
    constructor(
        address _vrfCoordinator,
        address _linkToken,
        bytes32 _keyHash,
        uint256 _fee
    )
        ERC721("Random Scalable Vector Graphics NFT", "RSVGNFT")
        VRFConsumerBase(_vrfCoordinator, _linkToken)
    {
        // Chainlink VRF parameters
        keyHash = _keyHash;
        fee = _fee;

        // SVG parameters
        maxNumberOfPaths = 10;
        maxNumberOfPathCommands = 5;
        size = 500;
        pathCommands = ["M", "L"];
        colors = ["red", "blue", "green", "yellow", "black", "purple"];
    }

    /**
     * @notice Start minting a Random SVG NFT
     * @dev It also requests a random number from Chainlink VRF
     * @return requestId the id of the request submitted to Chainlink VRF
     */
    function startMint() public returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );

        // Get the id of the request
        requestId = requestRandomness(keyHash, fee);

        // Link the id of the request to the sender
        requestIdToSender[requestId] = msg.sender;

        // Also link the id of the request to the id of the NFT
        uint256 tokenId = _tokenIdCounter.current();
        requestIdToTokenId[requestId] = tokenId;
        _tokenIdCounter.increment();

        emit RequestedRandomSVGNFT(requestId, tokenId);

        return requestId;
    }

    /**
     * @notice Finish minting a random SVG NFT
     * @param _tokenId the id of the NFT
     * @dev It uses Chainlink VRF (Verifiable Random Function) to generate the random svgs
     */
    function finishMint(uint256 _tokenId) public {
        // Check if the NFT has been minted
        require(
            bytes(tokenURI(_tokenId)).length <= 0,
            "The URI of the token is already set!"
        );
        require(
            _tokenIdCounter.current() > _tokenId,
            "The token has not been minted yet!"
        );

        // Check if the random number has been returned
        require(
            tokenIdToRandomNumber[_tokenId] > 0,
            "Need to wait for Chainlink VRF to respond and generate a random number"
        );

        // Generate the random SVG code
        uint256 randomNumber = tokenIdToRandomNumber[_tokenId];
        string memory svg = generateSVG(randomNumber);

        // Update the URI of the token with the svg code stored on-chain
        string memory svgURI = URI._svgToImageURI(svg);
        string memory tokenURI = URI._formatTokenURI(_tokenId, svgURI);
        _setTokenURI(_tokenId, tokenURI);

        emit CreatedRandomSVGNFT(_tokenId, tokenURI);
    }

    /**
     * @notice Callback function used by VRF Coordinator to validate and return the generated 
     random number
     * @param _requestId the id of the request submitted to Chainlink VRF
     * @param _randomNumber the random number generated by Chainlink VRF
     */
    function fulfillRandomness(bytes32 _requestId, uint256 _randomNumber)
        internal
        override
    {
        // Mint the NFT
        address owner = requestIdToSender[_requestId];
        uint256 tokenId = requestIdToTokenId[_requestId];
        _safeMint(owner, tokenId);

        // Store the random number
        tokenIdToRandomNumber[tokenId] = _randomNumber;

        emit ReceivedRandomNumber(_requestId, tokenId, _randomNumber);
    }

    /**
     * @notice Generate a random svg
     * @param _randomNumber the random number generated by Chainlink VRF
     */
    function generateSVG(uint256 _randomNumber)
        public
        view
        returns (string memory)
    {
        // Create the header of the svg
        string memory svg = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" width="',
                size.toString(),
                '" height="',
                size.toString(),
                '">'
            )
        );

        // Add the random shapes
        uint256 numberOfPaths = (_randomNumber % maxNumberOfPaths) + 1;
        for (uint256 i = 0; i < numberOfPaths; i++) {
            // Generate a new random number using the random number
            // This enables to generate different svg shapes using one random number
            uint256 newRNG = _generateNewRNG(_randomNumber, i); // TODO: maybe update this with the github?
            string memory pathSvg = generateSVGPath(newRNG);
            svg = string(abi.encodePacked(svg, pathSvg));
        }
        
        // Return the svg with the footer
        return string(abi.encodePacked(svg, "</svg>"));
    }

    /**
     * @notice Generate a random svg path
     * @param _randomNumber the random number generated by Chainlink VRF
     */
    function generateSVGPath(uint256 _randomNumber)
        public
        view
        returns (string memory)
    {
        // Create the header of the path
        uint256 randomNumberOfPathCommands = (_randomNumber %
            maxNumberOfPathCommands) + 1;
        string memory pathSvg = '<path d="';

        // Add the random path commands
        for (uint256 i = 0; i < randomNumberOfPathCommands; i++) {
            uint256 newRNG = _generateNewRNG(_randomNumber, i + size);
            string memory pathCommand = generateSVGPathCommand(newRNG);
            pathSvg = string(abi.encodePacked(pathSvg, pathCommand));
        }

        // Return the svg path with some colors
        string memory color = colors[_randomNumber % colors.length];
        return
            string(
                abi.encodePacked(
                    pathSvg,
                    ' fill="transparent" stroke="',
                    color,
                    '">'
                )
            );
    }

    /**
     * @notice Generate a random svg path command
     * @param _randomNumber the random number generated by Chainlink VRF
     */
    function generateSVGPathCommand(uint256 _randomNumber)
        public
        view
        returns (string memory)
    {
        string memory randomCommandPath = pathCommands[
            _randomNumber % pathCommands.length
        ];
        uint256 parameter1 = _generateNewRNG(_randomNumber, size * 2) % size;
        uint256 parameter2 = _generateNewRNG(_randomNumber, size * 2 + 1) %
            size;
        return
            string(
                abi.encodePacked(
                    randomCommandPath,
                    " ",
                    parameter1.toString(),
                    " ",
                    parameter2.toString()
                )
            );
    }

    /**
     * @notice Generate a new RNG
     * @param _oldRandomNumber the old random number generated by Chainlink VRF
     * @param _n another number
     */
    function _generateNewRNG(uint256 _oldRandomNumber, uint256 _n)
        private
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(_oldRandomNumber, _n)));
    }
}
