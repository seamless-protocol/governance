import fs from "fs";
import path from "path";
import { logger } from "./utils/logger";

// Input CSV file path
const csvFilePath: string = path.join(__dirname, "./input/data.csv");

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
  csvFile.forEach((line: string) => {
    const [address, amount] = line.split(",");

    if (jsonFile[address]) {
      throwErrorAndExit(`Duplicate address found: ${address}`);
    }
    if (!Number(amount)) {
      throwErrorAndExit(`Invalid amount found for address: ${address}`);
    }

    jsonFile[address] = Number(amount);
  });

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
