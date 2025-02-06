import { defineConfig } from "@wagmi/cli";
import { foundry } from "@wagmi/cli/plugins";

export default defineConfig({
  out: "types/generated.ts",
  plugins: [
    foundry({
      project: "./",
      forge: {
        clean: true,
        build: true,
      },
    }),
  ],
});
