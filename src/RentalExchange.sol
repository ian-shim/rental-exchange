// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ICurrencyManager} from "./interfaces/ICurrencyManager.sol";
import {IExecutionManager} from "./interfaces/IExecutionManager.sol";
import {IExecutionStrategy} from "./interfaces/IExecutionStrategy.sol";
import {ITransferManagerNFT} from "./interfaces/ITransferManagerNFT.sol";
import {ITransferSelectorNFT} from "./interfaces/ITransferSelectorNFT.sol";
import {INFTNFTWalletValidator} from "./interfaces/INFTNFTWalletValidator.sol";
import {INFTNFTWallet} from "./interfaces/INFTNFTWallet.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IWETH} from "./interfaces/IWETH.sol";

import {OrderTypes} from "./libraries/OrderTypes.sol";

contract RentalExchange is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    using OrderTypes for OrderTypes.MakerOrder;
    using OrderTypes for OrderTypes.TakerOrder;

    address public immutable WETH;
    bytes32 public immutable DOMAIN_SEPARATOR;

    address public protocolFeeRecipient;

    ICurrencyManager public currencyManager;
    IExecutionManager public executionManager;
    ITransferSelectorNFT public transferSelectorNFT;
    INFTNFTWalletValidator public walletValidator;
    IReceiptToken public receiptToken;

    mapping(address => uint256) public userMinOrderNonce;
    mapping(address => mapping(uint256 => bool)) private _isUserOrderNonceExecutedOrCancelled;

    event CancelAllOrders(address indexed user, uint256 newMinNonce);
    event CancelMultipleOrders(address indexed user, uint256[] orderNonces);
    event NewCurrencyManager(address indexed currencyManager);
    event NewExecutionManager(address indexed executionManager);
    event NewWalletValidator(address indexed walletValidator);
    event NewProtocolFeeRecipient(address indexed protocolFeeRecipient);
    event NewTransferSelectorNFT(address indexed transferSelectorNFT);

    event MakerAskMatched(
        bytes32 orderHash, // bid hash of the maker order
        address indexed maker, // maker address of the initial bid order
        uint256 orderNonce, // user order nonce
        address strategy,
        address currency,
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount // amount of tokens transferred
    );

    event MatchingTakerBid(
        bytes32 orderHash, // bid hash of the maker order
        address indexed taker, // sender address for the taker ask order
        uint256 pricePerHour,
        uint256 numHours
    );

    event MakerBidMatched(
        bytes32 orderHash, // bid hash of the maker order
        address indexed maker, // maker address of the initial bid order
        uint256 orderNonce, // user order nonce
        address strategy,
        address currency,
        address collection, // collection address
        uint256 tokenId, // tokenId transferred
        uint256 amount // amount of tokens transferred
    );

    event MatchingTakerAsk(
        bytes32 orderHash, // bid hash of the maker order
        address indexed taker, // sender address for the taker ask order
        uint256 pricePerHour,
        uint256 numHours
    );

    /**
     * @notice Constructor
     * @param _currencyManager currency manager address
     * @param _executionManager execution manager address
     * @param _WETH wrapped ether address (for other chains, use wrapped native asset)
     * @param _protocolFeeRecipient protocol fee recipient
     */
    constructor(
        address _currencyManager,
        address _executionManager,
        address _walletValidator,
        address _receiptToken,
        address _WETH,
        address _protocolFeeRecipient
    ) {
        // Calculate the domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f, // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
                0x626af73bd36f97b6b0f094db8772850c4a6e2eaec1b1dc866a93994f3d5fc53a, // keccak256("RentalExchange")
                0xc89efdaa54c0f20c7adf612882df0950f5a951637e0307cdcb4c672f298b8bc6, // keccak256(bytes("1")) for versionId = 1
                block.chainid,
                address(this)
            )
        );

        currencyManager = ICurrencyManager(_currencyManager);
        executionManager = IExecutionManager(_executionManager);
        walletValidator = INFTNFTWalletValidator(_walletValidator);
        receiptToken = IReceiptToken(_receiptToken);
        WETH = _WETH;
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    /**
     * @notice Cancel all pending orders for a sender
     * @param minNonce minimum user nonce
     */
    function cancelAllOrdersForSender(uint256 minNonce) external {
        require(minNonce > userMinOrderNonce[msg.sender], "Cancel: Order nonce lower than current");
        require(minNonce < userMinOrderNonce[msg.sender] + 500000, "Cancel: Cannot cancel more orders");
        userMinOrderNonce[msg.sender] = minNonce;

        emit CancelAllOrders(msg.sender, minNonce);
    }

    /**
     * @notice Cancel maker orders
     * @param orderNonces array of order nonces
     */
    function cancelMultipleMakerOrders(uint256[] calldata orderNonces) external {
        require(orderNonces.length > 0, "Cancel: Cannot be empty");

        for (uint256 i = 0; i < orderNonces.length; i++) {
            require(orderNonces[i] >= userMinOrderNonce[msg.sender], "Cancel: Order nonce lower than current");
            _isUserOrderNonceExecutedOrCancelled[msg.sender][orderNonces[i]] = true;
        }

        emit CancelMultipleOrders(msg.sender, orderNonces);
    }

    /**
     * @notice Match ask with a taker bid order using ETH
     * @param takerBid taker bid (borrower) order
     * @param makerAsk maker ask (lender) order
     */
    function matchAskWithTakerBidUsingETHAndWETH(
        OrderTypes.TakerOrder calldata takerBid,
        OrderTypes.MakerOrder calldata makerAsk
    ) external payable nonReentrant {
        OrderTypes.MakerRentConfig calldata rentConfig = makerAsk.rentConfig;
        require(walletValidator.isWalletApproved(msg.sender) == 0x3657e851, "Order: Wallet not approved");
        require((makerAsk.isOrderAsk) && (!takerBid.isOrderAsk), "Order: Wrong sides");
        require(rentConfig.currency == WETH, "Order: Currency must be WETH");
        require(msg.sender == takerBid.taker, "Order: Taker must be the sender");

        // If not enough ETH to cover the price, use WETH
        uint256 totalPrice = takerBid.pricePerHour * takerBid.numHours;
        if (totalPrice > msg.value) {
            IERC20(WETH).safeTransferFrom(msg.sender, address(this), (totalPrice - msg.value));
        } else {
            require(totalPrice == msg.value, "Order: Msg.value too high");
        }

        // Wrap ETH sent to this contract
        IWETH(WETH).deposit{value: msg.value}();

        // Check the maker ask order
        bytes32 askHash = makerAsk.hash();
        _validateOrder(makerAsk, askHash);

        // Retrieve execution parameters
        (bool isExecutionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(makerAsk.strategy)
            .canExecuteTakerBid(takerBid, makerAsk);

        require(isExecutionValid, "Strategy: Execution invalid");

        // Update maker ask order status to true (prevents replay)
        _isUserOrderNonceExecutedOrCancelled[makerAsk.signer][makerAsk.nonce] = true;

        // Execution part 1/2
        _transferFeesAndFundsWithWETH(
            makerAsk.strategy,
            makerAsk.signer,
            totalPrice
        );

        // Execution part 2/2
        _transferNFT(rentConfig.target.collection, makerAsk.signer, takerBid.taker, tokenId, amount);

        // Mint a receipt to the original owner
        receiptToken.mint(
            makerAsk.signer,
            takerBid.taker,
            rentConfig.target.collection,
            tokenId,
            block.timestamp + takerBid.numHours * 1 hours
        );

        emit MakerAskMatched(
            askHash,
            makerAsk.signer,
            makerAsk.nonce,
            makerAsk.strategy,
            rentConfig.currency,
            rentConfig.target.collection,
            tokenId,
            amount
        );
        
        emit MatchingTakerBid(
            askHash,
            takerBid.taker,
            takerBid.pricePerHour,
            takerBid.numHours
        );
    }

    /**
     * @notice Match a takerBid with a matchAsk
     * @param takerBid taker bid order
     * @param makerAsk maker ask order
     */
    function matchAskWithTakerBid(OrderTypes.TakerOrder calldata takerBid, OrderTypes.MakerOrder calldata makerAsk)
        external
        nonReentrant
    {
        OrderTypes.MakerRentConfig calldata rentConfig = makerAsk.rentConfig;
        require(walletValidator.isWalletApproved(msg.sender) == 0x3657e851, "Order: Wallet not approved");
        require((makerAsk.isOrderAsk) && (!takerBid.isOrderAsk), "Order: Wrong sides");
        require(msg.sender == takerBid.taker, "Order: Taker must be the sender");

        // Check the maker ask order
        bytes32 askHash = makerAsk.hash();
        _validateOrder(makerAsk, askHash);

        (bool isExecutionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(makerAsk.strategy)
            .canExecuteTakerBid(takerBid, makerAsk);

        require(isExecutionValid, "Strategy: Execution invalid");

        // Update maker ask order status to true (prevents replay)
        _isUserOrderNonceExecutedOrCancelled[makerAsk.signer][makerAsk.nonce] = true;

        // Execution part 1/2
        _transferFeesAndFunds(
            makerAsk.strategy,
            rentConfig.currency,
            msg.sender,
            makerAsk.signer,
            takerBid.pricePerHour * takerBid.numHours
        );

        // Execution part 2/2
        _transferNFT(rentConfig.target.collection, makerAsk.signer, takerBid.taker, tokenId, amount);

        // Mint a receipt to the original owner
        receiptToken.mint(
            makerAsk.signer, 
            takerBid.taker, 
            rentConfig.target.collection, 
            tokenId, 
            block.timestamp + takerBid.numHours * 1 hours
        );

        emit MakerAskMatched(
            askHash,
            makerAsk.signer,
            makerAsk.nonce,
            makerAsk.strategy,
            rentConfig.currency,
            rentConfig.target.collection,
            tokenId,
            amount
        );
        
        emit MatchingTakerBid(
            askHash,
            takerBid.taker,
            takerBid.pricePerHour,
            takerBid.numHours
        );
    }

    /**
     * @notice Match a takerAsk with a makerBid
     * @param takerAsk taker ask order
     * @param makerBid maker bid order
     */
    function matchBidWithTakerAsk(OrderTypes.TakerOrder calldata takerAsk, OrderTypes.MakerOrder calldata makerBid)
        external
        nonReentrant
    {
        OrderTypes.MakerRentConfig calldata rentConfig = makerBid.rentConfig;
        require(walletValidator.isWalletApproved(makerBid.signer) == 0x3657e851, "Order: Wallet not approved");
        require((!makerBid.isOrderAsk) && (takerAsk.isOrderAsk), "Order: Wrong sides");
        require(msg.sender == takerAsk.taker, "Order: Taker must be the sender");

        // Check the maker bid order
        bytes32 bidHash = makerBid.hash();
        _validateOrder(makerBid, bidHash);

        (bool isExecutionValid, uint256 tokenId, uint256 amount) = IExecutionStrategy(makerBid.strategy)
            .canExecuteTakerAsk(takerAsk, makerBid);

        require(isExecutionValid, "Strategy: Execution invalid");

        // Update maker bid order status to true (prevents replay)
        _isUserOrderNonceExecutedOrCancelled[makerBid.signer][makerBid.nonce] = true;

        // Execution part 1/2
        _transferNFT(rentConfig.target.collection, msg.sender, makerBid.signer, tokenId, amount);

        // Execution part 2/2
        _transferFeesAndFunds(
            makerBid.strategy,
            rentConfig.currency,
            makerBid.signer,
            takerAsk.taker,
            takerAsk.pricePerHour * takerAsk.numHours
        );

        // Mint a receipt to the original owner
        receiptToken.mint(
            takerAsk.taker,
            makerBid.signer,
            rentConfig.target.collection,
            tokenId,
            block.timestamp + takerAsk.numHours * 1 hours
        );

        emit MakerBidMatched(
            bidHash,
            makerBid.signer,
            makerBid.nonce,
            makerBid.strategy,
            rentConfig.currency,
            rentConfig.target.collection,
            tokenId,
            amount
        );
        
        emit MatchingTakerAsk(
            bidHash,
            takerAsk.taker,
            takerAsk.pricePerHour,
            takerAsk.numHours
        );
    }

    /**
     * @notice Update currency manager
     * @param _currencyManager new currency manager address
     */
    function updateCurrencyManager(address _currencyManager) external onlyOwner {
        require(_currencyManager != address(0), "Owner: Cannot be null address");
        currencyManager = ICurrencyManager(_currencyManager);
        emit NewCurrencyManager(_currencyManager);
    }

    /**
     * @notice Update execution manager
     * @param _executionManager new execution manager address
     */
    function updateExecutionManager(address _executionManager) external onlyOwner {
        require(_executionManager != address(0), "Owner: Cannot be null address");
        executionManager = IExecutionManager(_executionManager);
        emit NewExecutionManager(_executionManager);
    }

    /**
     * @notice Update wallet validator
     * @param _walletValidator new wallet validator address
     */
    function updateWalletValidator(address _walletValidator) external onlyOwner {
        require(_walletValidator != address(0), "Owner: Cannot be null address");
        walletValidator = INFTNFTWalletValidator(_walletValidator);
        emit NewWalletValidator(_walletValidator);
    }

    /**
     * @notice Update protocol fee and recipient
     * @param _protocolFeeRecipient new recipient for protocol fees
     */
    function updateProtocolFeeRecipient(address _protocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = _protocolFeeRecipient;
        emit NewProtocolFeeRecipient(_protocolFeeRecipient);
    }

    /**
     * @notice Update transfer selector NFT
     * @param _transferSelectorNFT new transfer selector address
     */
    function updateTransferSelectorNFT(address _transferSelectorNFT) external onlyOwner {
        require(_transferSelectorNFT != address(0), "Owner: Cannot be null address");
        transferSelectorNFT = ITransferSelectorNFT(_transferSelectorNFT);

        emit NewTransferSelectorNFT(_transferSelectorNFT);
    }

    /**
     * @notice Check whether user order nonce is executed or cancelled
     * @param user address of user
     * @param orderNonce nonce of the order
     */
    function isUserOrderNonceExecutedOrCancelled(address user, uint256 orderNonce) external view returns (bool) {
        return _isUserOrderNonceExecutedOrCancelled[user][orderNonce];
    }

    /**
     * @notice Transfer fees and funds to royalty recipient, protocol, and seller
     * @param strategy address of the execution strategy
     * @param from sender of the funds
     * @param to seller's recipient
     * @param amount amount being transferred (in currency)
     */
    function _transferFeesAndFunds(
        address strategy,
        address currency,
        address from,
        address to,
        uint256 amount
    ) internal {
        // Initialize the final amount that is transferred to seller
        uint256 finalSellerAmount = amount;

        uint256 protocolFeeAmount = _calculateProtocolFee(strategy, amount);

        // Check if the protocol fee is different than 0 for this strategy
        if ((protocolFeeRecipient != address(0)) && (protocolFeeAmount != 0)) {
            IERC20(currency).safeTransferFrom(from, protocolFeeRecipient, protocolFeeAmount);
            finalSellerAmount -= protocolFeeAmount;
        }

        IERC20(currency).safeTransferFrom(from, to, finalSellerAmount);
    }

    /**
     * @notice Transfer fees and funds to royalty recipient, protocol, and seller
     * @param strategy address of the execution strategy
     * @param to seller's recipient
     * @param amount amount being transferred (in currency)
     */
    function _transferFeesAndFundsWithWETH(
        address strategy,
        address to,
        uint256 amount
    ) internal {
        // Initialize the final amount that is transferred to seller
        uint256 finalSellerAmount = amount;

        uint256 protocolFeeAmount = _calculateProtocolFee(strategy, amount);

        // Check if the protocol fee is different than 0 for this strategy
        if ((protocolFeeRecipient != address(0)) && (protocolFeeAmount != 0)) {
            IERC20(WETH).safeTransfer(protocolFeeRecipient, protocolFeeAmount);
            finalSellerAmount -= protocolFeeAmount;
        }

        IERC20(WETH).safeTransfer(to, finalSellerAmount);
    }

    /**
     * @notice Transfer NFT
     * @param collection address of the token collection
     * @param from address of the sender
     * @param to address of the recipient
     * @param tokenId tokenId
     * @param amount amount of tokens (1 for ERC721, 1+ for ERC1155)
     * @dev For ERC721, amount is not used
     */
    function _transferNFT(
        address collection,
        address from,
        address to,
        uint256 tokenId,
        uint256 amount
    ) internal {
        require(walletValidator.isWalletApproved(to) == 0x3657e851, "Transfer: Wallet not approved");
        // Retrieve the transfer manager address
        address transferManager = transferSelectorNFT.checkTransferManagerForToken(collection);

        // If no transfer manager found, it returns address(0)
        require(transferManager != address(0), "Transfer: No NFT transfer manager available");

        // If one is found, transfer the token
        ITransferManagerNFT(transferManager).transferNonFungibleToken(collection, from, to, tokenId, amount);

        // Give approval to the exchange so it can retrieve later
        // INFTNFTWallet(to).setOperatorApprovalForNFT(collection);
    }

    /**
     * @notice Calculate protocol fee for an execution strategy
     * @param executionStrategy strategy
     * @param amount amount to transfer
     */
    function _calculateProtocolFee(address executionStrategy, uint256 amount) internal view returns (uint256) {
        uint256 protocolFee = IExecutionStrategy(executionStrategy).viewProtocolFee();
        return (protocolFee * amount) / 10000;
    }
    
    /**
     * @notice Verify the validity of the maker order
     * @param makerOrder maker order
     * @param orderHash computed hash for the order
     */
    function _validateOrder(OrderTypes.MakerOrder calldata makerOrder, bytes32 orderHash) internal view {
        // Verify whether order nonce has expired
        require(
            (!_isUserOrderNonceExecutedOrCancelled[makerOrder.signer][makerOrder.nonce]) &&
                (makerOrder.nonce >= userMinOrderNonce[makerOrder.signer]),
            "Order: Matching order expired"
        );

        // Verify the signer is not address(0)
        require(makerOrder.signer != address(0), "Order: Invalid signer");

        // Verify the amount is not 0
        require(makerOrder.rentConfig.target.amount > 0, "Order: Amount cannot be 0");

        // Verify the validity of the signature
        require(
            SignatureChecker.isValidSignatureNow(makerOrder.signer, ECDSA.toTypedDataHash(DOMAIN_SEPARATOR, orderHash), makerOrder.signature),
            "Signature: Invalid"
        );

        // Verify whether the currency is whitelisted
        require(currencyManager.isCurrencyWhitelisted(makerOrder.rentConfig.currency), "Currency: Not whitelisted");

        // Verify whether strategy can be executed
        require(executionManager.isStrategyWhitelisted(makerOrder.strategy), "Strategy: Not whitelisted");
    }
}
