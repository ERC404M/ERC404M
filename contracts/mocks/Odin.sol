//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable} from "../lib/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ERC404M} from "../ERC404M.sol";

 contract Odin is Ownable,ERC404M{
  string public dataURI;

  string public baseTokenURI;

  function init(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address initialOwner_,
    uint256[] memory _initialTokenPerSeries
  ) public {
    OwnableInitialize(initialOwner_);
    ERC404Minitialize(name_, symbol_, decimals_,_initialTokenPerSeries);}

  function mintERC20(
    address account_,
    uint256 value_,
    bool mintCorrespondingERC721s_
  ) external Ownable.onlyOwner {
    _mintERC20(account_, value_, mintCorrespondingERC721s_);
  }

  function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }



    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

  function tokenURI(uint256 id_) public view override returns (string memory) {
    uint256 seriesIndex = getSeriesIndex(id_);

    if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI,Strings.toString(seriesIndex) ,Strings.toString(id_));
        } else if(seriesIndex == 1) {
            uint8 seed = uint8(bytes1(keccak256(abi.encodePacked(id_))));
            string memory image;
            string memory color;
            if (seed <= 100) {
                image = "box/boxblack.png";
                color = "Black";
            } else if (seed <= 160) {
                image = "box/boxblue.png";
                color = "Blue";
            } else if (seed <= 210) {
                image = "box/boxgreen.png";
                color = "Green";
            } else if (seed <= 240) {
                image = "box/boxred.png";
                color = "Red";
            } else if (seed <= 255) {
                image = "box/boxyellow.png";
                color = "Yellow";
            }

            string memory jsonPreImage = string.concat(
                string.concat(
                    string.concat('{"name": "Odin #', Strings.toString(id_)),
                    string.concat('","description":"A collection of 10 Replicants enabled by ERC404M, an experimental token standard.","external_url":"erc404m.xyz","image":"')
                ),
                string.concat(dataURI, image)
            );
            string memory jsonPostImage = string.concat(
                '","attributes":[{"trait_type":"Type", "value":"box"},{"trait_type":"Power", "value":"',Strings.toString(seed),'"},{"trait_type":"Color","value":"',
                color
            );
            string memory jsonPostTraits = '"}]}';
            return
                string.concat(
                    "data:application/json;utf8,",
                    string.concat(
                        string.concat(jsonPreImage, jsonPostImage),
                        jsonPostTraits
                    )
                );
        }else{
          uint8 seed = uint8(bytes1(keccak256(abi.encodePacked(id_))));
            string memory image;
            string memory color;

            if (seed <= 100) {
                image = "gold/goldblack.png";
                color = "Black";
            } else if (seed <= 160) {
                image = "gold/goldblue.png";
                color = "Blue";
            } else if (seed <= 210) {
                image = "gold/goldgreen.png";
                color = "Green";
            } else if (seed <= 240) {
                image = "gold/goldred.png";
                color = "Red";
            } else if (seed <= 255) {
                image = "gold/goldyellow.png";
                color = "Yellow";
            }

            string memory jsonPreImage = string.concat(
                string.concat(
                    string.concat('{"name": "Odin #', Strings.toString(id_)),
                    string.concat('","description":"A collection of 10,0000 Replicants enabled by ERC404M, an experimental token standard.","external_url":"erc404m.xyz", "image":"')
                ),
                string.concat(dataURI, image)
            );
            string memory jsonPostImage = string.concat(
                '","attributes":[{"trait_type":"Type", "value":"gold"},{"trait_type":"Lucky", "value":"',Strings.toString(seed),'"}, {"trait_type":"Color","value":"',
                color
            );
            string memory jsonPostTraits = '"}]}';

            return
                string.concat(
                    "data:application/json;utf8,",
                    string.concat(
                        string.concat(jsonPreImage, jsonPostImage),
                        jsonPostTraits
                    )
                );
        }
    }  

  function setWhitelist(address account_, bool value_) external Ownable.onlyOwner {
    _setWhitelist(account_, value_);
  }
}
