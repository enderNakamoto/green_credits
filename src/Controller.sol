// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./CarbonQueue.sol";
import "./RewardsVault.sol";

contract Controller is Ownable(msg.sender) {
    struct VehicleInfo {
        string vin;
        uint256 lastProcessedOdometer;
        uint256 lastProcessedTimestamp;
    }

    CarbonQueue public immutable carbonQueue;
    RewardsVault public immutable rewardsVault;
    IERC20 public immutable usdc;

    uint256 public constant MILES_PER_CREDIT = 100;
    uint256 public creditPrice;
    uint256 public lastPriceUpdate;
    uint256 public totalCreditsMinted;
    uint256 public totalCreditsBurned;
    address public priceOracle;
    address public odometerProcessor;

    mapping(address => uint256) public creditBalance;
    mapping(address => uint256) public creditsMinted;
    mapping(address => uint256) public creditsBurned;

    // EV tracking
    mapping(address => string) public addressToVin;
    mapping(string => VehicleInfo) public vinToVehicleInfo;
    mapping(string => bool) public registeredVins;

    event CreditMinted(
        address indexed holder,
        uint256 amount,
        string vin,
        uint256 milesDriven
    );
    event CreditBurned(
        address indexed burner,
        address indexed seller,
        uint256 amount
    );
    event RewardWithdrawn(address indexed holder, uint256 amount);
    event VehicleRegistered(address indexed owner, string vin);
    event PriceUpdated(uint256 newPrice, uint256 timestamp);

    constructor(
        address _usdc,
        address _priceOracle,
        address _odometerProcessor
    ) {
        require(_usdc != address(0), "Invalid USDC address");
        require(_priceOracle != address(0), "Invalid price oracle address");

        usdc = IERC20(_usdc);
        priceOracle = _priceOracle;
        odometerProcessor = _odometerProcessor;

        carbonQueue = new CarbonQueue(address(this));
        rewardsVault = new RewardsVault(_usdc, address(this));

        creditPrice = 100 * 10 ** 6; // Initial price 100 USDC
        lastPriceUpdate = block.timestamp;

        totalCreditsMinted = 0;
        totalCreditsBurned = 0;
    }

    modifier onlyPriceOracle() {
        require(msg.sender == priceOracle, "Only price oracle");
        _;
    }

    modifier onlyOdometerProcessor() {
        require(msg.sender == odometerProcessor, "Only odometer processor");
        _;
    }

    function setOdometerProcessor(
        address _newOdometerProcessor
    ) external onlyOwner {
        require(
            _newOdometerProcessor != address(0),
            "Invalid odometer processor"
        );
        odometerProcessor = _newOdometerProcessor;
    }

    function setPriceOracle(address _newPriceOracle) external onlyOwner {
        require(_newPriceOracle != address(0), "Invalid price oracle");
        priceOracle = _newPriceOracle;
    }

    function updatePrice(uint256 _newPrice) external onlyPriceOracle {
        creditPrice = _newPrice;
        lastPriceUpdate = block.timestamp;
        emit PriceUpdated(_newPrice, block.timestamp);
    }

    function registerVehicle(address owner, string calldata vin) public {
        require(
            bytes(addressToVin[owner]).length == 0,
            "Address already has vehicle"
        );
        require(!registeredVins[vin], "VIN already registered");

        bytes memory strBytes = bytes(vin);
        bool isValid = (strBytes[0] == "5" &&
            strBytes[1] == "Y" &&
            strBytes[2] == "J") ||
            (strBytes[0] == "2" && strBytes[1] == "S" && strBytes[2] == "C");

        require(
            strBytes.length == 17,
            "VIN code must be exactly 17 characters long"
        );
        require(isValid, "VIN code must start with either 5YJ or 2SC");

        addressToVin[owner] = vin;
        registeredVins[vin] = true;
        vinToVehicleInfo[vin] = VehicleInfo({
            vin: vin,
            lastProcessedOdometer: 0,
            lastProcessedTimestamp: block.timestamp
        });

        emit VehicleRegistered(owner, vin);
    }

    function processOdometerReading(
        address driver,
        uint256 currentOdometer
    ) public onlyOdometerProcessor {
        string memory vin = addressToVin[driver];
        require(bytes(vin).length > 0, "No registered vehicle");

        VehicleInfo storage vehicleInfo = vinToVehicleInfo[vin];
        uint256 roundedCurrentReading = _roundDownToNearestHundred(
            currentOdometer
        );

        require(
            roundedCurrentReading > vehicleInfo.lastProcessedOdometer,
            "New reading must be higher than last processed"
        );

        uint256 creditsEarned = _calculateCreditsEarned(
            roundedCurrentReading,
            vehicleInfo.lastProcessedOdometer
        );

        if (creditsEarned > 0) {
            for (uint256 i = 0; i < creditsEarned; i++) {
                carbonQueue._enqueueCredit(driver);
            }

            creditBalance[driver] += creditsEarned;
            creditsMinted[driver] += creditsEarned;

            totalCreditsMinted += creditsEarned;

            uint256 milesDriven = roundedCurrentReading -
                vehicleInfo.lastProcessedOdometer;
            emit CreditMinted(driver, creditsEarned, vin, milesDriven);
        }

        vehicleInfo.lastProcessedOdometer = roundedCurrentReading;
        vehicleInfo.lastProcessedTimestamp = block.timestamp;
    }

    function burnCredit(uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");
        require(
            carbonQueue._getAvailableCredits() >= amount,
            "Not enough credits"
        );

        uint256 totalCost = amount * creditPrice;
        require(
            usdc.transferFrom(msg.sender, address(rewardsVault), totalCost),
            "USDC transfer failed"
        );

        for (uint256 i = 0; i < amount; i++) {
            address seller = carbonQueue._dequeueCredit();
            creditBalance[seller]--;
            rewardsVault._addReward(seller, creditPrice);
            creditsBurned[msg.sender]++;

            emit CreditBurned(msg.sender, seller, 1);
        }

        totalCreditsBurned += amount;
        creditBalance[msg.sender] += amount;
    }

    function withdrawRewards() public {
        uint256 amount = rewardsVault._withdrawRewards(msg.sender);
        require(amount > 0, "No rewards to withdraw");
        emit RewardWithdrawn(msg.sender, amount);
    }

    // View functions
    function getVehicleInfo(
        string calldata vin
    )
        external
        view
        returns (uint256 lastOdometer, uint256 lastTimestamp, bool isRegistered)
    {
        VehicleInfo memory info = vinToVehicleInfo[vin];
        return (
            info.lastProcessedOdometer,
            info.lastProcessedTimestamp,
            registeredVins[vin]
        );
    }

    function getAvailableCredits() external view returns (uint256) {
        return carbonQueue._getAvailableCredits();
    }

    function getCurrentPrice()
        external
        view
        returns (uint256 price, uint256 lastUpdate)
    {
        return (creditPrice, lastPriceUpdate);
    }

    function getCreditStats(
        address holder
    )
        external
        view
        returns (
            uint256 balance,
            uint256 minted,
            uint256 burned,
            uint256 pendingRewards,
            string memory vin
        )
    {
        return (
            creditBalance[holder],
            creditsMinted[holder],
            creditsBurned[holder],
            rewardsVault._getPendingRewards(holder),
            addressToVin[holder]
        );
    }

    function availableCredits() public view returns (uint256) {
        return carbonQueue._getAvailableCredits();
    }

    // helper functions

    function _roundDownToNearestHundred(
        uint256 number
    ) public pure returns (uint256) {
        return (number / 100) * 100;
    }

    function _calculateCreditsEarned(
        uint256 currentReading,
        uint256 lastProcessedReading
    ) public pure returns (uint256) {
        require(
            currentReading > lastProcessedReading,
            "Invalid reading difference"
        );
        uint256 milesDriven = currentReading - lastProcessedReading;
        return milesDriven / MILES_PER_CREDIT;
    }
}
