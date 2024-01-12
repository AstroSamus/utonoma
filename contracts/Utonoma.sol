// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ContentStorage} from "contracts/ContentStorage.sol";
import {Users} from "contracts/Users.sol";
import {Time} from "contracts/Time.sol";

contract Utonoma is ERC20, ContentStorage, Users, Time {
    
    address internal _owner;

    constructor(uint256 initialSupply) ERC20("Omas", "OMA") {
        _mint(msg.sender, initialSupply);
        _owner = msg.sender;
    }

    /// @dev uploads a content by using the createContent method
    /**
    * @notice in case that the user has strikes, it will have to pay the respective fee, this call 
    * counts as a user interaction
    */ 
    function upload(bytes32 contentHash, bytes32 metadataHash, ContentTypes contentType) external returns(Identifier memory) {
        uint64 strikes = getUserProfile(msg.sender).strikes;
        if(strikes > 0) { //if content creator has strikes it will have to pay the fee
            collectFee(calculateFeeForUsersWithStrikes(strikes, currentPeriodMAU()));
        } 
        logUserInteraction(block.timestamp, _startTimeOfTheNetwork);
        Content memory content = Content(
            msg.sender,
            contentHash,
            metadataHash,
            0,
            0,
            0,
            new uint256[](0),
            new uint8[](0),
            new uint256[](0),
            new uint8[](0)
        );
        Identifier memory id = createContent(content, contentType);
        emit uploaded(msg.sender, id.index, uint256(id.contentType));
        return id;
    }

    /// @dev adds one to the likes count of the content
    /// @notice this call counts as a user interaction
    function like(Identifier calldata id) external {
        collectFee(calculateFee(currentPeriodMAU()));
        Content memory content = getContentById(id);
        content.likes++;
        updateContent(content, id);
        logUserInteraction(block.timestamp, _startTimeOfTheNetwork);
        emit liked(id.index, uint256(id.contentType));
    }

    /// @dev adds one to the likes count of the content
    /// @notice this call counts as a user interaction
    function dislike(Identifier calldata id) external {
        collectFee(calculateFee(currentPeriodMAU()));
        Content memory content = getContentById(id);
        content.dislikes++;
        updateContent(content, id);
        logUserInteraction(block.timestamp, _startTimeOfTheNetwork);
        emit disliked(id.index, uint256(id.contentType));
    }

    /**
    * @dev mints new tokens and assing them to the content creator, calculation of the amount is based on the 
    * return of the calculate reward method by the number of likes - dislikes - harvested likes
    * harvested likes it's the number of likes that where already cashed
    */
    /// @notice if a content gets a dislike, lesser the amount of the granted tokens will be
    function harvestLikes(Identifier calldata id) external {
        Content memory content = getContentById(id);
        require(content.likes > content.dislikes, "Likes should be greater than dislikes");
        require(shouldContentBeEliminated(content.likes, content.dislikes) == false, "Content should be eliminated");
        require(content.likes > (content.dislikes + content.harvestedLikes), "There are no more likes to harvest");
        
        uint64 likesToHarvest = content.likes - content.dislikes - content.harvestedLikes;
        content.harvestedLikes += likesToHarvest;
        updateContent(content, id);
        uint256 reward = likesToHarvest * calculateReward(currentPeriodMAU());
        _mint(content.contentOwner, reward);
        emit harvested(id.index, uint256(id.contentType), reward);
    }

    /// @dev validates and deletes a content from the content library and adds a strike to the creator's user profile
    function deletion(Identifier calldata id) external {
        Content memory content = getContentById(id);
        require(shouldContentBeEliminated(content.likes, content.dislikes));
        deleteContent(id);
        addStrike(content.contentOwner);
        emit deleted(content.contentOwner, content.contentHash, content.metadataHash, id.index, uint8(id.contentType));
    }

    /// @dev This method allows the user to delete content that they uploaded
    /// @notice only the creator can delete it
    function voluntarilyDelete(Identifier calldata id) external {        
        require(msg.sender == getContentById(id).contentOwner, "Only the content owner can voluntarily delete it");
        deleteContent(id);
    }

    /// @dev adds a content to the reply list of other content
    /// @param replyId it is the id of the content that works as a reply to other content
    /// @param replyingToId it is the id of the content that is being replied
    function reply(Identifier calldata replyId, Identifier calldata replyingToId) external {
        require(msg.sender == getContentById(replyId).contentOwner, "Only the owner of the content can use it as a reply");
        createReply(replyId, replyingToId);
        emit replied(replyId.index, uint256(replyId.contentType), replyingToId.index, uint256(replyingToId.contentType));
    }

    /// @dev allows the contract's owner to withdraw all the gathered fees
    function withdraw() external {
        require(msg.sender == _owner, "Only the owner can withdraw");
        uint256 maxBalance = IERC20(address(this)).balanceOf(address(this));
        require(maxBalance > 0, "Nothing to withdraw");
        IERC20(address(this)).transfer(_owner, maxBalance);
    }

    event uploaded(address indexed contentCreator, uint256 index, uint256 contentType);

    event liked(uint256 indexed index, uint256 indexed contentType);

    event disliked(uint256 indexed index, uint256 indexed contentType);

    event harvested(uint256 indexed index, uint256 indexed contentType, uint256 amount);

    event deleted(address indexed owner, bytes32 content, bytes32 metadata, uint256 index, uint8 contentType);

    event replied(uint256 replyIndex, uint256 replyContentType, uint256 indexed replyingToIndex, uint256 indexed replyingToContentType);

}