// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title AIOracle
 * @notice Commit-reveal oracle for AI-generated responses on Avalanche
 * @dev Users pay 0.01 AVAX per request, oracle commits then reveals results
 */
contract AIOracle {
    // Constants
    uint256 public constant REQUEST_FEE = 0.01 ether;
    uint256 public constant COMMIT_TIMEOUT = 5 minutes;
    uint256 public constant REVEAL_TIMEOUT = 2 minutes;
    uint256 public constant MAX_RESPONSE_LENGTH = 1000;

    // Enums
    enum RequestStatus { Pending, Committed, Revealed, Refunded }
    enum PromptTemplate { Summarize, SentimentAnalysis, NFTDescription }

    // Structs
    struct Request {
        address requester;
        PromptTemplate template;
        string input;
        uint256 timestamp;
        RequestStatus status;
        bytes32 commitment;
        uint256 commitTimestamp;
        string result;
        uint256 fee;
    }

    // State
    address public oracle;
    uint256 public requestCounter;
    mapping(uint256 => Request) public requests;

    // Events
    event AIRequested(
        uint256 indexed requestId,
        address indexed requester,
        PromptTemplate template,
        string input,
        uint256 fee
    );
    
    event ResultCommitted(
        uint256 indexed requestId,
        bytes32 commitment,
        uint256 timestamp
    );
    
    event ResultRevealed(
        uint256 indexed requestId,
        string result,
        uint256 timestamp
    );
    
    event Refunded(
        uint256 indexed requestId,
        address indexed requester,
        uint256 amount
    );

    event OracleChanged(address indexed oldOracle, address indexed newOracle);

    // Errors
    error InvalidFee();
    error InvalidInput();
    error ResponseTooLong();
    error Unauthorized();
    error InvalidRequestId();
    error InvalidStatus();
    error TimeoutNotReached();
    error CommitmentMismatch();
    error AlreadyProcessed();

    // Modifiers
    modifier onlyOracle() {
        if (msg.sender != oracle) revert Unauthorized();
        _;
    }

    modifier validRequest(uint256 requestId) {
        if (requestId >= requestCounter) revert InvalidRequestId();
        _;
    }

    constructor(address _oracle) {
        oracle = _oracle;
    }

    /**
     * @notice Submit AI request with one of three templates
     * @param template The prompt template to use
     * @param input User's input text (max 500 chars to prevent gas issues)
     */
    function requestAI(
        PromptTemplate template,
        string calldata input
    ) external payable returns (uint256 requestId) {
        if (msg.value != REQUEST_FEE) revert InvalidFee();
        if (bytes(input).length == 0 || bytes(input).length > 500) revert InvalidInput();

        requestId = requestCounter++;
        
        requests[requestId] = Request({
            requester: msg.sender,
            template: template,
            input: input,
            timestamp: block.timestamp,
            status: RequestStatus.Pending,
            commitment: bytes32(0),
            commitTimestamp: 0,
            result: "",
            fee: msg.value
        });

        emit AIRequested(requestId, msg.sender, template, input, msg.value);
    }

    /**
     * @notice Oracle commits hash of result before revealing
     * @param requestId The request ID
     * @param commitment Hash of (result + salt)
     */
    function commitResult(
        uint256 requestId,
        bytes32 commitment
    ) external onlyOracle validRequest(requestId) {
        Request storage req = requests[requestId];
        
        if (req.status != RequestStatus.Pending) revert InvalidStatus();
        if (block.timestamp > req.timestamp + COMMIT_TIMEOUT) revert TimeoutNotReached();
        
        req.commitment = commitment;
        req.commitTimestamp = block.timestamp;
        req.status = RequestStatus.Committed;

        emit ResultCommitted(requestId, commitment, block.timestamp);
    }

    /**
     * @notice Oracle reveals result, contract verifies commitment
     * @param requestId The request ID
     * @param result The AI-generated result (max 1000 chars)
     * @param salt Random bytes used in commitment
     */
    function revealResult(
        uint256 requestId,
        string calldata result,
        bytes32 salt
    ) external onlyOracle validRequest(requestId) {
        Request storage req = requests[requestId];
        
        if (req.status != RequestStatus.Committed) revert InvalidStatus();
        if (block.timestamp > req.commitTimestamp + REVEAL_TIMEOUT) revert TimeoutNotReached();
        if (bytes(result).length > MAX_RESPONSE_LENGTH) revert ResponseTooLong();

        // Verify commitment matches hash(result + salt)
        bytes32 computedHash = keccak256(abi.encodePacked(result, salt));
        if (computedHash != req.commitment) revert CommitmentMismatch();

        req.result = result;
        req.status = RequestStatus.Revealed;

        // Pay oracle
        payable(oracle).transfer(req.fee);

        emit ResultRevealed(requestId, result, block.timestamp);
    }

    /**
     * @notice Requester claims refund if oracle fails to commit or reveal in time
     * @param requestId The request ID
     */
    function refund(uint256 requestId) external validRequest(requestId) {
        Request storage req = requests[requestId];
        
        if (req.requester != msg.sender) revert Unauthorized();
        if (req.status == RequestStatus.Refunded || req.status == RequestStatus.Revealed) {
            revert AlreadyProcessed();
        }

        bool canRefund = false;
        
        // Refund if oracle never committed within timeout
        if (req.status == RequestStatus.Pending && 
            block.timestamp > req.timestamp + COMMIT_TIMEOUT) {
            canRefund = true;
        }
        
        // Refund if oracle committed but never revealed within timeout
        if (req.status == RequestStatus.Committed && 
            block.timestamp > req.commitTimestamp + REVEAL_TIMEOUT) {
            canRefund = true;
        }

        if (!canRefund) revert TimeoutNotReached();

        req.status = RequestStatus.Refunded;
        payable(req.requester).transfer(req.fee);

        emit Refunded(requestId, req.requester, req.fee);
    }

    /**
     * @notice Get request details
     */
    function getRequest(uint256 requestId) 
        external 
        view 
        validRequest(requestId) 
        returns (Request memory) 
    {
        return requests[requestId];
    }

    /**
     * @notice Change oracle address (for upgrades/maintenance)
     */
    function setOracle(address _newOracle) external onlyOracle {
        address oldOracle = oracle;
        oracle = _newOracle;
        emit OracleChanged(oldOracle, _newOracle);
    }

    /**
     * @notice Get human-readable prompt template name
     */
    function getTemplateName(PromptTemplate template) external pure returns (string memory) {
        if (template == PromptTemplate.Summarize) return "Summarize";
        if (template == PromptTemplate.SentimentAnalysis) return "Sentiment Analysis";
        if (template == PromptTemplate.NFTDescription) return "NFT Description";
        return "Unknown";
    }
}