pragma solidity ^ 0.4 .22;
import "contracts/Escrow.sol";


contract EcommerceStore {
    enum ProductStatus {
        Open,
        Sold,
        Unsold
    }

    enum ProductCondition {
        New,
        Used
    }

    uint public productIndex;
    mapping(address => mapping(uint => Product)) stores;
    mapping(uint => address) productIdInStore;
    mapping(uint => address) productEscrow;

    struct Product {
        uint id;
        string name;
        string category;
        string imageLink;
        string descLink;
        uint auctionStartTime;
        uint auctionEndTime;
        uint startPrice;
        address highestBidder;
        uint highestBid;
        uint secondHighestBid;
        uint totalBids;
        ProductStatus status;
        ProductCondition condition;
        mapping(address => mapping(bytes32 => Bid)) bids;
    }

    struct Bid {
        address bidder;
        uint productId;
        uint value;
        bool revealed;
    }

    constructor() public {
        productIndex = 0;
    }

    function numberOfItems() public constant returns(uint) {
        return productIndex;
    }

    event BidCast(address bidder, uint productId, uint value);

    function bid2() public pure returns(bool) {
        // BidCast(msg.sender, 1, 2);
        return true;
    }

    event NewProduct(uint _productId, string _name, string _category, string _imageLink, string _descLink,
        uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition);

    function bid(uint _productId, bytes32 _bid) public payable returns(bool) {

        Product storage product = stores[productIdInStore[_productId]][_productId];
        require(now >= product.auctionStartTime);
        require(now <= product.auctionEndTime);
        require(msg.value > product.startPrice);
        emit BidCast(msg.sender, _productId, msg.value);
        require(product.bids[msg.sender][_bid].bidder == 0);
        //emit BidCast(msg.sender, _productId, msg.value);
        product.bids[msg.sender][_bid] = Bid(msg.sender, _productId, msg.value, false);
        product.totalBids += 1;
        return true;
    }

    function revealBid(uint _productId, string _amount, string _secret) {
        Product storage product = stores[productIdInStore[_productId]][_productId];
        require(now > product.auctionEndTime);
        bytes32 sealedBid = sha3(_amount, _secret);

        Bid memory bidInfo = product.bids[msg.sender][sealedBid];
        require(bidInfo.bidder > 0);
        require(bidInfo.revealed == false);

        uint refund;

        uint amount = stringToUint(_amount);

        if (bidInfo.value < amount) {
            // They didn't send enough amount, they lost
            refund = bidInfo.value;
        } else {
            // If first to reveal set as highest bidder
            if (address(product.highestBidder) == 0) {
                product.highestBidder = msg.sender;
                product.highestBid = amount;
                product.secondHighestBid = product.startPrice;
                refund = bidInfo.value - amount;
            } else {
                if (amount > product.highestBid) {
                    product.secondHighestBid = product.highestBid;
                    product.highestBidder = msg.sender;
                    product.highestBid = amount;
                    refund = bidInfo.value - amount;
                } else if (amount > product.secondHighestBid) {
                    product.secondHighestBid = amount;
                    refund = amount;
                } else {
                    refund = amount;
                }
            }
            if (refund > 0) {
                msg.sender.transfer(refund);
                product.bids[msg.sender][sealedBid].revealed = true;
            }
        }
    }

    function highestBidderInfo(uint _productId) returns(address, uint, uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return (product.highestBidder, product.highestBid, product.secondHighestBid);
    }

    function totalBids(uint _productId) returns(uint) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return product.totalBids;
    }

    function stringToUint(string s) constant returns(uint) {
        bytes memory b = bytes(s);
        uint result = 0;
        for (uint i = 0; i < b.length; i++) {
            if (b[i] >= 48 && b[i] <= 57) {
                result = result * 10 + (uint(b[i]) - 48);
            }
        }
        return result;
    }

    function addProductToStore(string _name, string _category, string _imageLink, string _descLink, uint _auctionStartTime, uint _auctionEndTime, uint _startPrice, uint _productCondition) {
        require(_auctionStartTime < _auctionEndTime);
        productIndex += 1;
        Product memory product = Product(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, 0, 0, 0, 0, ProductStatus.Open, ProductCondition(_productCondition));
        stores[msg.sender][productIndex] = product;
        productIdInStore[productIndex] = msg.sender;
        NewProduct(productIndex, _name, _category, _imageLink, _descLink, _auctionStartTime, _auctionEndTime, _startPrice, _productCondition);
    }

    function getProduct(uint _productId) returns(uint, string, string, string, string, uint, uint, uint, ProductStatus, ProductCondition) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        return (product.id, product.name, product.category, product.imageLink, product.descLink, product.auctionStartTime,
            product.auctionEndTime, product.startPrice, product.status, product.condition);
    }

    function finalizeAuction(uint _productId) {
        Product memory product = stores[productIdInStore[_productId]][_productId];
        // 48 hours to reveal the bid
        require(now > product.auctionEndTime);
        require(product.status == ProductStatus.Open);
        require(product.highestBidder != msg.sender);
        require(productIdInStore[_productId] != msg.sender);

        if (product.totalBids == 0) {
            product.status = ProductStatus.Unsold;
        } else {
            // Whoever finalizes the auction is the arbiter
            Escrow escrow = (new Escrow).value(product.secondHighestBid)(_productId, product.highestBidder, productIdInStore[_productId], msg.sender);
            productEscrow[_productId] = address(escrow);
            product.status = ProductStatus.Sold;
            // The bidder only pays the amount equivalent to second highest bidder
            // Refund the difference
            uint refund = product.highestBid - product.secondHighestBid;
            product.highestBidder.transfer(refund);

        }
    }

    function escrowAddressForProduct(uint _productId) returns(address) {
        return productEscrow[_productId];
    }

    function escrowInfo(uint _productId) returns(address, address, address, bool, uint, uint) {
        return Escrow(productEscrow[_productId]).escrowInfo();
    }

    function releaseAmountToSeller(uint _productId) {
        Escrow(productEscrow[_productId]).releaseAmountToSeller(msg.sender);
    }

    function refundAmountToBuyer(uint _productId) {
        Escrow(productEscrow[_productId]).refundAmountToBuyer(msg.sender);
    }


}
