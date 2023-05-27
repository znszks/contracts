
pragma solidity ^0.8.0;


interface PriceOracle {
    /**
     * @dev Returns the price to register or renew a name.
     * @param name The name being registered or renewed.
     * @param expires When the name presently expires (0 if this is a new registration).
     * @param duration How long the name is being registered or extended for, in seconds.
     * @return The price of this renewal or registration, in wei.
     */
    function price(string calldata name, uint expires, uint duration) external view returns(uint);
}

interface ENS {

    // Logged when the owner of a node assigns a new owner to a subnode.
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);

    // Logged when the owner of a node transfers ownership to a new account.
    event Transfer(bytes32 indexed node, address owner);

    // Logged when the resolver for a node changes.
    event NewResolver(bytes32 indexed node, address resolver);

    // Logged when the TTL of a node changes
    event NewTTL(bytes32 indexed node, uint64 ttl);

    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external returns(bytes32);
    function setResolver(bytes32 node, address resolver) external;
    function setOwner(bytes32 node, address owner) external;
    function setTTL(bytes32 node, uint64 ttl) external;
    function setApprovalForAll(address operator, bool approved) external;
    function owner(bytes32 node) external view returns (address);
    function resolver(bytes32 node) external view returns (address);
    function ttl(bytes32 node) external view returns (uint64);
    function recordExists(bytes32 node) external view returns (bool);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC165 {
    /**
     * @notice Query if a contract implements an interface
     * @param interfaceId The interface identifier, as specified in ERC-165
     * @dev Interface identification is specified in ERC-165. This function
     * uses less than 30,000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) public virtual view returns (uint256 balance);
    function ownerOf(uint256 tokenId) public virtual view returns (address owner);

    function approve(address to, uint256 tokenId) public virtual;
    function getApproved(uint256 tokenId) public virtual view returns (address operator);

    function setApprovalForAll(address operator, bool _approved) public virtual;
    function isApprovedForAll(address owner, address operator) public virtual view returns (bool);

    function transferFrom(address from, address to, uint256 tokenId) public virtual;
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual;

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual;
}

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @return the address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * @notice Renouncing to ownership will leave the contract without an owner.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

abstract contract BaseRegistrar is IERC721, Ownable {
    uint constant public GRACE_PERIOD = 90 days;

    event ControllerAdded(address indexed controller);
    event ControllerRemoved(address indexed controller);
    event NameMigrated(uint256 indexed id, address indexed owner, uint expires);
    event NameRegistered(uint256 indexed id, address indexed owner, uint expires);
    event NameRenewed(uint256 indexed id, uint expires);

    // The ENS registry
    ENS public ens;

    // The namehash of the TLD this registrar owns (eg, .eth)
    bytes32 public baseNode;

    // A map of addresses that are authorised to register and renew names.
    mapping(address=>bool) public controllers;

    // Authorises a controller, who can register and renew domains.
    function addController(address controller) external virtual;

    // Revoke controller permission for an address.
    function removeController(address controller) external virtual;

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external virtual;

    // Returns the expiration timestamp of the specified label hash.
    function nameExpires(uint256 id) external virtual view returns(uint);

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) public virtual view returns(bool);

    /**
     * @dev Register a name.
     */
    function register(string calldata name, uint256 id, address owner, uint duration) external virtual returns(uint);

    function renew(uint256 id, uint duration) external virtual returns(uint);

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external virtual;
}

library StringUtils {
    /**
     * @dev Returns the length of a given string
     *
     * @param s The string to measure the length of
     * @return The length of the input string
     */
    function strlen(string memory s) internal pure returns (uint) {
        bytes memory inputBytes = bytes(s);
        return inputBytes.length;
    }
}

interface Resolver {
    event AddrChanged(bytes32 indexed node, address a);
    event AddressChanged(bytes32 indexed node, uint coinType, bytes newAddress);
    event NameChanged(bytes32 indexed node, string name);
    event ABIChanged(bytes32 indexed node, uint256 indexed contentType);
    event PubkeyChanged(bytes32 indexed node, bytes32 x, bytes32 y);
    event TextChanged(bytes32 indexed node, string indexed indexedKey, string key);
    event ContenthashChanged(bytes32 indexed node, bytes hash);
    /* Deprecated events */
    event ContentChanged(bytes32 indexed node, bytes32 hash);

    function ABI(bytes32 node, uint256 contentTypes) external view returns (uint256, bytes memory);
    function addr(bytes32 node) external view returns (address);
    function addr(bytes32 node, uint coinType) external view returns(bytes memory);
    function contenthash(bytes32 node) external view returns (bytes memory);
    function dnsrr(bytes32 node) external view returns (bytes memory);
    function name(bytes32 node) external view returns (string memory);
    function pubkey(bytes32 node) external view returns (bytes32 x, bytes32 y);
    function text(bytes32 node, string calldata key) external view returns (string memory);
    function interfaceImplementer(bytes32 node, bytes4 interfaceID) external view returns (address);

    function setABI(bytes32 node, uint256 contentType, bytes calldata data) external;
    function setAddr(bytes32 node, address addr) external;
    function setAddr(bytes32 node, uint coinType, bytes calldata a) external;
    function setContenthash(bytes32 node, bytes calldata hash) external;
    function setDnsrr(bytes32 node, bytes calldata data) external;
    function setName(bytes32 node, string calldata _name) external;
    function setPubkey(bytes32 node, bytes32 x, bytes32 y) external;
    function setText(bytes32 node, string calldata key, string calldata value) external;
    function setInterface(bytes32 node, bytes4 interfaceID, address implementer) external;

    function supportsInterface(bytes4 interfaceID) external pure returns (bool);

    /* Deprecated functions */
    function content(bytes32 node) external view returns (bytes32);
    function multihash(bytes32 node) external view returns (bytes memory);
    function setContent(bytes32 node, bytes32 hash) external;
    function setMultihash(bytes32 node, bytes calldata hash) external;
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint);
    function transfer(address recipient, uint amount) external returns (bool);
}

pragma experimental ABIEncoderV2;

contract ZNSRegistrarController is Ownable {
    using StringUtils for *;

    uint constant public ONE_YEAR_DURATION = 365 days;
    uint constant public MIN_REGISTRATION_DURATION =  ONE_YEAR_DURATION;

    struct Epoch {
        uint256 openTime;
        uint minLength;
        uint maxLength;
    }

    struct WhiteList {
        uint minLength;
        uint freeCount;
        uint allowedCount;
    }
    
    Epoch[] epochs;

    uint256 public WL_PRIORITY_PERIOD = 1 hours;
    mapping(address=> WhiteList) WLMap;

    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private COMMITMENT_CONTROLLER_ID = bytes4(
        keccak256("rentPrice(string,uint256)") ^
        keccak256("available(string)") ^
        keccak256("makeCommitment(string,address,bytes32)") ^
        keccak256("commit(bytes32)") ^
        keccak256("register(string,address,uint256,bytes32)") ^
        keccak256("renew(string,uint256)")
    );

    bytes4 constant private COMMITMENT_WITH_CONFIG_CONTROLLER_ID = bytes4(
        keccak256("registerWithConfig(string,address,uint256,bytes32,address,address)") ^
        keccak256("makeCommitmentWithConfig(string,address,bytes32,address,address)")
    );

    BaseRegistrar base;

    uint public YearlyBasePrice;
    mapping(uint=>uint256) public YearlyPriceMap; 

    address payable teamAddress;

    event NameRegistered(string name, bytes32 indexed label, address indexed owner, uint cost, uint expires);
    event NameRenewed(string name, bytes32 indexed label, uint cost, uint expires);
    event NewPriceOracle(address indexed oracle);

    constructor(BaseRegistrar _base, uint _price, address payable _teamAddress) public {
        base = _base;
        YearlyBasePrice = _price;
        teamAddress = _teamAddress;
    }

    function addEpoch(uint256 openTime, uint minLength, uint maxLength) public onlyOwner {
        epochs.push(Epoch(openTime, minLength, maxLength));
    }

    function addToWL(uint minLength, uint freeCount, uint allowedCount, address[] memory users) public onlyOwner {
        for (uint i = 0; i < users.length; i ++) {
            WLMap[users[i]].minLength = minLength;
            WLMap[users[i]].freeCount += freeCount;
            WLMap[users[i]].allowedCount += allowedCount;
        }
    }

    function setTeamAddress(address payable _teamAddress) public onlyOwner {
        teamAddress = _teamAddress;
    }

    function setWLPriority(uint256 _time) public onlyOwner {
        WL_PRIORITY_PERIOD = _time;
    }

    function setPrice(uint nameLength, uint256 price) public onlyOwner {
        require(nameLength > 0);
        YearlyPriceMap[nameLength] = price;
    }

    function checkWL(address user) view public returns (uint, uint, uint) {
        WhiteList memory wl = WLMap[user];
        return (wl.minLength, wl.freeCount, wl.allowedCount);
    }

    function rentPrice(string memory name, uint yearCount) view public returns(uint256) {
        uint256 price = YearlyPriceMap[name.strlen()];
        if (price == 0) {
            price = YearlyBasePrice;
        }
        return price * yearCount;
    }

    function rentPriceForUser(string memory name, address user, uint yearCount) view public returns(uint256) {
        uint256 price = rentPrice(name, yearCount);
        if (WLMap[user].freeCount > 0) {
            price -= rentPrice(name, 1);
        }
        return price;
    }

    function canRegister(string memory name, address user) view public returns (bool, bool) {
        bool isAvailable = available(name);
        if (!isAvailable) {
            return (false, false);
        }
        bool canMint = false;
        Epoch memory current = currentEpoch();
        if (current.openTime != 0) {
            uint nameLength = name.strlen();
            if (nameLength <= current.maxLength) {
                if (WLMap[user].allowedCount > 0) {
                    canMint = block.timestamp >= current.openTime && (nameLength >= WLMap[user].minLength || nameLength >= current.minLength);
                } else {
                    canMint = (block.timestamp >= current.openTime + WL_PRIORITY_PERIOD) && (nameLength >= current.minLength);
                }
            }
        }
        return (isAvailable, canMint);
    }

    function currentEpoch() view public returns (Epoch memory) {
        Epoch memory current = Epoch(0,9999, 0);
        for (uint i = 0; i < epochs.length; i ++) {
            Epoch memory temp = epochs[i];
            if (block.timestamp >= temp.openTime) {
                current = temp;
            }
        }
        return current;
    }

    function openTimeInfo() view public returns (uint256, uint256) {
        Epoch memory current = currentEpoch();
        if (current.openTime == 0) {
            return (0, 0);
        }
        return (current.openTime, current.openTime + WL_PRIORITY_PERIOD);
    } 

    function valid(string memory name) public pure returns(bool) {
        return name.strlen() >= 1;
    }

    function available(string memory name) public view returns(bool) {
        bytes32 label = keccak256(bytes(name));
        return valid(name) && base.available(uint256(label));
    }

    function register(string calldata name, address owner, uint yearCount) external payable {
      registerWithConfig(name, owner, yearCount, address(0), address(0));
    }

    function registerWithConfig(string memory name, address owner, uint yearCount, address resolver, address addr) public payable {
        require(valid(name), "Name not valid");
        (bool isAvailable, bool canMint) = canRegister(name, msg.sender);
        require(isAvailable && canMint, "You can not register this name at this moment.");
        uint cost = _consume(name, yearCount);

        bytes32 label = keccak256(bytes(name));
        uint256 tokenId = uint256(label);

        uint duration = yearCount * ONE_YEAR_DURATION;

        uint expires;
        if(resolver != address(0)) {
            // Set this contract as the (temporary) owner, giving it
            // permission to set up the resolver.
            expires = base.register(name, tokenId, address(this), duration);

            // The nodehash of this label
            bytes32 nodehash = keccak256(abi.encodePacked(base.baseNode(), label));

            // Set the resolver
            base.ens().setResolver(nodehash, resolver);

            // Configure the resolver
            if (addr != address(0)) {
                Resolver(resolver).setAddr(nodehash, addr);
            }

            // Now transfer full ownership to the expeceted owner
            base.reclaim(tokenId, owner);
            base.transferFrom(address(this), owner, tokenId);
        } else {
            require(addr == address(0));
            expires = base.register(name, tokenId, owner, duration);
        }

        emit NameRegistered(name, label, owner, cost, expires);

        // Refund any extra payment
        if(msg.value > cost) {
            msg.sender.call{value: msg.value - cost}("");
        }
        teamAddress.call{value:cost}("");

        if (WLMap[msg.sender].allowedCount > 0) {
            WLMap[msg.sender].allowedCount --;
        }
        if (WLMap[msg.sender].freeCount > 0) {
            WLMap[msg.sender].freeCount --;
        }
    }

    function renew(string calldata name, uint yearCount) external payable {

        uint cost = rentPrice(name, yearCount);
        require(msg.value >= cost);
        uint duration = yearCount * ONE_YEAR_DURATION;
        
        bytes32 label = keccak256(bytes(name));
        uint expires = base.renew(uint256(label), duration);

        if(msg.value > cost) {
            msg.sender.call{value: msg.value - cost}("");
        }
        teamAddress.call{value:cost}("");

        emit NameRenewed(name, label, cost, expires);
    }

    function setYearlyBasePrice(uint price) public onlyOwner {
        YearlyBasePrice = price;
    }

    function setBase(BaseRegistrar _base) public onlyOwner {
        base = _base;
    }

    function withdraw() public onlyOwner {
        msg.sender.call{value: address(this).balance}("");
    }

    function withdrawToken(address _tokenContract) public onlyOwner {
        IERC20 tokenContract = IERC20(_tokenContract);
        uint256 balance = tokenContract.balanceOf(address(this));
        tokenContract.transfer(msg.sender, balance);
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == COMMITMENT_CONTROLLER_ID ||
               interfaceID == COMMITMENT_WITH_CONFIG_CONTROLLER_ID;
    }

    function _consume(string memory name, uint yearCount) internal returns (uint256) {
        require(available(name));
        require(yearCount >= 1);
        uint cost = rentPriceForUser(name, msg.sender, yearCount);
        require(msg.value >= cost);

        return cost;
    }
}