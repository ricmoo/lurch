#!/usr/bin/env node

"use strict";

const fs = require("fs");
const { inherits } = require("util");

const { ethers } = require("ethers");

const { cli } = require("@ethersproject/cli");

const { version } = require("../package.json");
const { compile, getAddress, solcVersion } = require("../index");


const logger = new ethers.utils.Logger(version);


const rootedCli = new cli.CLI();

function RootedPlugin() {
    this.contract = null;
    this.filename = null;
    this.args = [ ];
    this.source = null;
    this.optimize = true;
    this.version = "v0";
}
inherits(RootedPlugin, cli.Plugin);

RootedPlugin.getHelp = function() {
    return {
        name: "FILENAME",
        help: "Solidity source to deploy"
    };
}

RootedPlugin.getOptionHelp = function() {
    return [
        {
            name: "--contract",
            help: "specify the contract to deploy"
        },
        {
            name: "--args",
            help: "specify JSON encoded constructor args"
        },
        {
            name: "--no-optimize",
            help: "do not run the optimizer"
        },
        {
            name: "--version",
            help: "the version to use (default: v0)"
        },
    ];
}

RootedPlugin.prototype.prepareArgs = async function(args) {
    await cli.Plugin.prototype.prepareArgs(args);

    switch (args.length) {
        case 0:
            this.throwError("missing source filename");

        case 1:
            try {
                this.filename = args[0];
                this.source = fs.readFileSync(this.filename).toString();
            } catch (error) {
                throw error;
            }
            break;

        default:
            this.throwError("exactly one source filename required");
    }
}

RootedPlugin.prototype.prepareOptions = async function(argParser) {
    await cli.Plugin.prototype.prepareOptions(argParser);

    if (this.accounts.length !== 1) {
        this.throwError("Exactly one accounts is required for deployment.");
    }
    //const address = await getAddress(this.accounts[0]);
    //

    this.optimize = !argParser.consumeFlag("no-optimize");
    this.contract = argParser.consumeOption("contract");
    this.version = argParser.consumeOption("version") || "v0";

    // Check this utility supports the version
    if (this.version !== "v0") {
        this.throwError("Unsupported version: " + this.version);
    }

    const args = argParser.consumeOption("args");
    if (args) {
        try {
            this.args = JSON.parse(args)
        } catch (error) {
            this.throwError("Failed to parse JSON encoded constructor arguments");
        }
    }
}

RootedPlugin.prototype.run = async function() {
    let codes = null;

    try {
        codes = compile(this.source, {
            filename: this.filename,
            optimize: this.optimize
        });

    } catch (error) {
        if (error.errors) {
            error.errors.forEach((error) => {
                console.log(error);
            });
            this.throwError("Compilation Error(s)");
        }
        throw error;
    }

    let code = null;

    if (codes.length === 1) {
        code = codes[0];

    } else {

        if (this.contract == null) {
            this.throwError(`Multiple contracts found; specify --contract NAME (one of ${ codes.map((c) => c.name).join(", ") })`);
        }

        codes = codes.filter((code) => (code.name === this.contract));
        if (codes.length === 1) {
            code = codes[0];
        } else if (codes.length > 1) {
            this.throwError(`Too many contracts named "${ this.contract }" found.`);
        }

    }

    if (this.contract && code.name !== this.contract) {
        this.throwError(`No contract named "${ this.contract }" found.`);
    }

    const inputs = code.interface.deploy.inputs;
    const args = this.args;

    if (inputs.length !== args.length) {
         this.throwError(`Constructor requires ${ inputs.length } arguments; ${ args.length } given`);
    }

    let encodedArgs = null;
    try {
        encodedArgs = code.interface.encodeDeploy(args);
    } catch (error) {
        this.throwError(`Invalid arguments for ${ code.deploy.format("full") }; got ${ args.join(", ") }`);
    }

    cli.dump("Deploy: " + this.filename, {
        "Contract Address": await getAddress(this.accounts[0], this.version)
    });

    const tx = {
        data: ethers.utils.hexlify(ethers.utils.concat([ code.bytecode, encodedArgs ])),
        to: (this.version + ".rooted.eth")
    }

    await this.accounts[0].sendTransaction(tx);
}

rootedCli.setPlugin(RootedPlugin);

rootedCli.run(process.argv.slice(2));
