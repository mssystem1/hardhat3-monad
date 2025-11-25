import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const FortuneCookiesAIModule = buildModule("FortuneCookiesAIModule", (m) => {
  // constructor(string memory logoMIME)
  const logoMIME = m.getParameter("logoMIME", "image/png");

  const cookie = m.contract("FortuneCookiesAI", [logoMIME]);

  return { cookie };
});

export default FortuneCookiesAIModule;
