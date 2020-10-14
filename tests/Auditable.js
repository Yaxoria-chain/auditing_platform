// const Auditable = artifacts.require("Auditable");
const truffleAssert = require("truffle-assertions");

contract("Auditable", async (accounts) => {

    let owner;
    // let auditable;
    let platform;
    let test;

    before(() => {
        owner = accounts[0];
        auditor = accounts[1];
        platform = accounts[2];
    });

    beforeEach(async () => {
        // auditable = await Auditable.new(_auditor = auditor, _platform = platform, {from: owner});
        console.log("Testing")
    });

    // it("Sets the platform", () => {
    //     const transaction = auditable.setPlatform(_platform = accounts[4], {from: owner});
    //     console.log(transaction);
    // });

})