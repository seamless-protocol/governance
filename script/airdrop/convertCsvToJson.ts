import fs from "fs";
import path from "path";
import { toChecksumAddress } from "ethereumjs-util";
import { logger } from "./utils/logger";
import { ethers } from "ethers";

// Input CSV file path
const csvFilePath: string = path.join(__dirname, "./input/addresses.csv");

// Output JSON file path
const jsonFilePath: string = path.join(__dirname, "./input/addresses.json");

/**
 * Throws error and exits process
 * @param {string} error to log
 */
function throwErrorAndExit(error: string): void {
  logger.error(error);
  process.exit(1);
}

(async () => {
  // Check if CSV file exists
  if (!fs.existsSync(csvFilePath)) {
    throwErrorAndExit("Missing data.csv. Please add.");
  }

  // Read CSV file
  const csvFile: string[] = fs
    .readFileSync(csvFilePath, "utf-8")
    .toString()
    .split("\n");

  let jsonFile: any = {};
  let sum = 0;
  let count = 0;
  csvFile.forEach((line: string) => {
    const [address, amount] = line.split(",");

    if (!ethers.isAddress(address)) {
      throwErrorAndExit(`Invalid address found: ${address}`);
    }
    if (jsonFile[address]) {
      throwErrorAndExit(`Duplicate address found: ${address}`);
    }
    if (!Number(amount)) {
      throwErrorAndExit(`Invalid amount found for address: ${address}`);
    }

    jsonFile[toChecksumAddress(address)] = amount.toString();
    count++;
    sum += Number(amount);
  });
  console.log("Total addresses: ", count);
  console.log("Total amount: ", sum);

  const output = {
    decimals: 18,
    airdrop: jsonFile,
  };

  // Write JSON data to output file
  fs.writeFileSync(jsonFilePath, JSON.stringify(output, null, 2), {
    flag: "w",
    encoding: "utf8",
  });

  logger.info("Conversion completed successfully.");
})();
