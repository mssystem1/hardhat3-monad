import { readFileSync } from "fs";
import * as path from "path";
import process from "process";
import { ethers } from "ethers";

// hard RPC fee cap the node enforces; default 1 ETH
const FEE_CAP_WEI = BigInt(process.env.TX_FEE_CAP_WEI || "1000000000000000000");
// the smallest piece we’ll try before giving up
const MIN_CHUNK = parseInt(process.env.MIN_CHUNK || "512", 10);

// ---- CLI args ----
function arg(name, def = undefined) {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : def;
}
const ADDRESS = arg("--address");
const FILE = arg("--file", "111.txt");
const MIME = arg("--mime", "image/png");
const CHUNK = parseInt(arg("--chunk", "20000"), 10);

// ---- ENV (RPC + KEY) ----
const RPC = process.env.BASE_RPC || arg("--rpc");
const PK  = process.env.PRIVATE_KEY || arg("--pk");
if (!ADDRESS) throw new Error("Missing --address 0x...");
if (!RPC) throw new Error("Missing BASE_RPC env or --rpc");
if (!PK) throw new Error("Missing PRIVATE_KEY env or --pk");

// ---- Decode helpers ----
function decodeDataUri(str) {
  const m = /^data:([^;,]+)(?:;charset=[^;,]+)?;base64,(.+)$/i.exec(str.trim());
  if (!m) return null;
  return { mime: m[1], bytes: Buffer.from(m[2], "base64") };
}

function smartLoad(filePath) {
  let raw = readFileSync(filePath, "utf8").trim();
  if (raw.startsWith("string:")) raw = raw.slice(7).trim();
  if (raw.startsWith("data:")) {
    const first = decodeDataUri(raw);
    if (!first) throw new Error("Unrecognized data URI");
    if (first.mime.toLowerCase().includes("application/json")) {
      const json = JSON.parse(first.bytes.toString("utf8"));
      if (!json.image) throw new Error("JSON metadata has no 'image'");
      const img = decodeDataUri(json.image);
      if (!img) throw new Error("image field is not data URI");
      return { mime: img.mime, bytes: img.bytes };
    }
    return { mime: first.mime, bytes: first.bytes };
  }
  // raw binary fallback
  const bin = readFileSync(filePath);
  const isSvg = bin.slice(0, 200).toString("utf8").includes("<svg");
  return { mime: isSvg ? "image/svg+xml" : "image/png", bytes: bin };
}

// ---- Minimal ABI for the methods we need ----
const ABI = [
  "function owner() view returns (address)",
  "function setLogoMIME(string mime) external",
  "function resetLogo() external",
  "function appendLogoChunk(bytes chunk) external",
  "function finalizeLogo() external",
  "function logoInfo() view returns (string mime, uint256 rawBytes, uint256 legacyB64Chars, bool isSealed)",
  "function tokenURI(uint256 id) view returns (string)"
];

async function main() {
  const filePath = path.isAbsolute(FILE) ? FILE : path.join(process.cwd(), FILE);
  const { mime: detected, bytes } = smartLoad(filePath);
  const mime = MIME || detected;

  console.log("RPC:", RPC);
  const provider = new ethers.JsonRpcProvider(RPC);
  const wallet = new ethers.Wallet(PK, provider);

  const net = await provider.getNetwork();
  console.log("chainId:", net.chainId.toString());
  if (net.chainId !== 8453n) {
    console.log("WARN: chainId isn’t 8453 (Base mainnet).");
  }

  const code = await provider.getCode(ADDRESS);
  if (code === "0x") throw new Error(`No bytecode at ${ADDRESS}`);

  const c = new ethers.Contract(ADDRESS, ABI, wallet);

  // Ownership check (best effort)
  try {
    const owner = await c.owner();
    console.log("owner:", owner);
    if (owner.toLowerCase() !== wallet.address.toLowerCase()) {
      throw new Error(`You are not owner (${wallet.address})`);
    }
  } catch {
    console.log("owner() not callable (ok if not Ownable, but then setters may revert).");
  }

  console.log(`Loaded ${FILE}: ${bytes.length} bytes, detected: ${detected}, using MIME: ${mime}`);
  // Try calling each function selector first (static) to ensure ABI exists
  const selectors = [
    { name: "setLogoMIME", data: c.interface.encodeFunctionData("setLogoMIME", [mime]) },
    { name: "resetLogo",   data: c.interface.encodeFunctionData("resetLogo", []) },
    { name: "appendLogoChunk", data: c.interface.encodeFunctionData("appendLogoChunk", [new Uint8Array([1])]) },
    { name: "finalizeLogo", data: c.interface.encodeFunctionData("finalizeLogo", []) },
  ];
  for (const s of selectors) {
    try {
      await provider.call({ to: ADDRESS, data: s.data });
      console.log(`${s.name}: selector exists`);
    } catch {
      console.log(`${s.name}: selector likely exists but reverted on call (ok for non-view)`);
    }
  }
  
  // Send a tx with maxFeePerGas/maxPriorityFeePerGas capped so (gas * price) ≤ FEE_CAP_WEI
async function sendCapped(estimateFn, sendFn) {
  // 1) estimate gas for this call
  const gas = await estimateFn();

  // 2) get suggested fees
  const fee = await provider.getFeeData();
  let maxFeePerGas = fee.maxFeePerGas ?? fee.gasPrice; // ethers v6
  let maxPriority  = fee.maxPriorityFeePerGas ?? (maxFeePerGas ? maxFeePerGas / 5n : null);

  // 3) enforce a per-gas cap so total fee fits under the node’s 1 ETH cap
  const perGasCap = FEE_CAP_WEI / gas;                   // max price per gas allowed by cap
  if (!maxFeePerGas || maxFeePerGas > perGasCap) maxFeePerGas = perGasCap;
  if (!maxPriority  || maxPriority  > maxFeePerGas)      maxPriority  = maxFeePerGas / 5n;

  // 4) ensure we don’t end up at zero
  const oneGwei = 1_000_000_000n;
  if (maxPriority < oneGwei)   maxPriority = oneGwei;
  if (maxFeePerGas < maxPriority + oneGwei) maxFeePerGas = maxPriority + oneGwei;

  // 5) send tx with explicit gas & fees
  return sendFn({ gasLimit: gas, maxFeePerGas, maxPriorityFeePerGas: maxPriority });
}

  // Do the actual writes
  console.log(`setLogoMIME("${mime}")...`);
	await (await sendCapped(
	  () => c.setLogoMIME.estimateGas(mime),
	  (ov) => c.setLogoMIME(mime, ov)
	)).wait();

  console.log("resetLogo()...");
	await (await sendCapped(
	  () => c.resetLogo.estimateGas(),
	  (ov) => c.resetLogo(ov)
	)).wait();
  
/*
  for (let i = 0; i < bytes.length; i += CHUNK) {
    const part = bytes.subarray(i, Math.min(i + CHUNK, bytes.length));
    console.log(`appendLogoChunk ${i}..${i + part.length - 1} (${part.length})`);
    await (await c.appendLogoChunk(part)).wait();
  }
*/

let i = 0;
while (i < bytes.length) {
  let partLen = Math.min(CHUNK, bytes.length - i);

  while (true) {
    const part = bytes.subarray(i, i + partLen);

    // estimate with current size; if revert, shrink
    let gas;
    try {
      gas = await c.appendLogoChunk.estimateGas(part);
    } catch (e) {
      if (partLen > MIN_CHUNK) { partLen = Math.floor(partLen / 2); continue; }
      throw e;
    }

    // check fee cap using current gas and provider fee data
    const fee = await provider.getFeeData();
    const maxFee = (fee.maxFeePerGas ?? fee.gasPrice) ?? 0n;
    if (maxFee && (gas * maxFee) > FEE_CAP_WEI && partLen > MIN_CHUNK) {
      partLen = Math.floor(partLen / 2);
      continue;
    }

    console.log(`appendLogoChunk ${i}..${i + partLen - 1} (${partLen})`);
    const tx = await sendCapped(
      () => Promise.resolve(gas),                 // reuse the estimate we already got
      (ov) => c.appendLogoChunk(part, ov)
    );
    await tx.wait();
    i += partLen;
    break;
  }
}

  console.log("finalizeLogo()...");
	await (await sendCapped(
	  () => c.finalizeLogo.estimateGas(),
	  (ov) => c.finalizeLogo(ov)
	)).wait();

  // Try logoInfo (optional)
  try {
    const info = await c.logoInfo();
    console.log("logoInfo:", {
      mime: info.mime,
      rawBytes: info.rawBytes.toString(),
      legacyB64Chars: info.legacyB64Chars.toString(),
      isSealed: info.isSealed
    });
  } catch {
    console.log("logoInfo() not implemented — skip.");
  }

  console.log("DONE. Now mint and check tokenURI.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
