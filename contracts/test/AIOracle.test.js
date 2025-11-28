const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("AIOracle", function () {
  let oracle, user, oracleAddress;
  let contract;
  const REQUEST_FEE = ethers.parseEther("0.01");

  beforeEach(async function () {
    [oracle, user] = await ethers.getSigners();
    oracleAddress = oracle.address;

    const AIOracle = await ethers.getContractFactory("AIOracle");
    contract = await AIOracle.deploy(oracleAddress);
  });

  describe("Deployment", function () {
    it("Should set the right oracle address", async function () {
      expect(await contract.oracle()).to.equal(oracleAddress);
    });

    it("Should set correct constants", async function () {
      expect(await contract.REQUEST_FEE()).to.equal(REQUEST_FEE);
    });
  });

  describe("Request AI", function () {
    it("Should create a request with correct fee", async function () {
      const tx = await contract.connect(user).requestAI(
        0, // Summarize template
        "Test input text",
        { value: REQUEST_FEE }
      );

      await expect(tx)
        .to.emit(contract, "AIRequested")
        .withArgs(0, user.address, 0, "Test input text", REQUEST_FEE);

      const request = await contract.getRequest(0);
      expect(request.requester).to.equal(user.address);
      expect(request.input).to.equal("Test input text");
      expect(request.status).to.equal(0); // Pending
    });

    it("Should revert with wrong fee", async function () {
      await expect(
        contract.connect(user).requestAI(0, "Test", { value: ethers.parseEther("0.005") })
      ).to.be.revertedWithCustomError(contract, "InvalidFee");
    });

    it("Should revert with empty input", async function () {
      await expect(
        contract.connect(user).requestAI(0, "", { value: REQUEST_FEE })
      ).to.be.revertedWithCustomError(contract, "InvalidInput");
    });
  });

  describe("Commit-Reveal Flow", function () {
    let requestId;
    const result = "This is the AI generated result";
    const salt = ethers.encodeBytes32String("random_salt_123");

    beforeEach(async function () {
      await contract.connect(user).requestAI(
        0,
        "Summarize this text",
        { value: REQUEST_FEE }
      );
      requestId = 0;
    });

    it("Should allow oracle to commit result", async function () {
      const commitment = ethers.keccak256(
        ethers.solidityPacked(["string", "bytes32"], [result, salt])
      );

      await expect(contract.connect(oracle).commitResult(requestId, commitment))
        .to.emit(contract, "ResultCommitted")
        .withArgs(requestId, commitment, await ethers.provider.getBlock('latest').then(b => b.timestamp + 1));

      const request = await contract.getRequest(requestId);
      expect(request.status).to.equal(1); // Committed
    });

    it("Should allow oracle to reveal with correct commitment", async function () {
      const commitment = ethers.keccak256(
        ethers.solidityPacked(["string", "bytes32"], [result, salt])
      );

      await contract.connect(oracle).commitResult(requestId, commitment);
      
      const oracleBalanceBefore = await ethers.provider.getBalance(oracleAddress);
      
      await expect(contract.connect(oracle).revealResult(requestId, result, salt))
        .to.emit(contract, "ResultRevealed")
        .withArgs(requestId, result, await ethers.provider.getBlock('latest').then(b => b.timestamp + 1));

      const request = await contract.getRequest(requestId);
      expect(request.status).to.equal(2); // Revealed
      expect(request.result).to.equal(result);

      // Oracle should receive payment
      const oracleBalanceAfter = await ethers.provider.getBalance(oracleAddress);
      expect(oracleBalanceAfter).to.be.gt(oracleBalanceBefore);
    });

    it("Should revert reveal with wrong commitment", async function () {
      const wrongCommitment = ethers.keccak256(
        ethers.solidityPacked(["string", "bytes32"], ["wrong result", salt])
      );

      await contract.connect(oracle).commitResult(requestId, wrongCommitment);

      await expect(
        contract.connect(oracle).revealResult(requestId, result, salt)
      ).to.be.revertedWithCustomError(contract, "CommitmentMismatch");
    });

    it("Should revert if non-oracle tries to commit", async function () {
      const commitment = ethers.keccak256(
        ethers.AbiCoder.defaultAbiCoder().encode(
          ["string", "bytes32"],
          [result, salt]
        )
      );

      await expect(
        contract.connect(user).commitResult(requestId, commitment)
      ).to.be.revertedWithCustomError(contract, "Unauthorized");
    });
  });

  describe("Refunds", function () {
    it("Should allow refund after commit timeout", async function () {
      await contract.connect(user).requestAI(
        0,
        "Test input",
        { value: REQUEST_FEE }
      );

      // Increase time past commit timeout
      await ethers.provider.send("evm_increaseTime", [6 * 60]); // 6 minutes
      await ethers.provider.send("evm_mine");

      const userBalanceBefore = await ethers.provider.getBalance(user.address);

      await expect(contract.connect(user).refund(0))
        .to.emit(contract, "Refunded")
        .withArgs(0, user.address, REQUEST_FEE);

      const userBalanceAfter = await ethers.provider.getBalance(user.address);
      expect(userBalanceAfter).to.be.gt(userBalanceBefore);
    });

    it("Should revert refund before timeout", async function () {
      await contract.connect(user).requestAI(
        0,
        "Test input",
        { value: REQUEST_FEE }
      );

      await expect(
        contract.connect(user).refund(0)
      ).to.be.revertedWithCustomError(contract, "TimeoutNotReached");
    });
  });
});