import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

const frontendRoot = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  base: "./",
  plugins: [react()],
  resolve: {
    alias: [
      {
        find: "@testing-library/jest-dom",
        replacement: resolve(
          frontendRoot,
          "node_modules/@testing-library/jest-dom",
        ),
      },
      {
        find: "@testing-library/react",
        replacement: resolve(
          frontendRoot,
          "node_modules/@testing-library/react",
        ),
      },
      {
        find: "@testing-library/user-event",
        replacement: resolve(
          frontendRoot,
          "node_modules/@testing-library/user-event",
        ),
      },
      {
        find: /^vitest$/,
        replacement: resolve(frontendRoot, "node_modules/vitest/dist/index.js"),
      },
      {
        find: "react",
        replacement: resolve(frontendRoot, "node_modules/react"),
      },
      {
        find: "react-dom",
        replacement: resolve(frontendRoot, "node_modules/react-dom"),
      },
    ],
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    fs: {
      allow: ["../.."],
    },
    proxy: {
      "/api": "http://127.0.0.1:5080",
    },
  },
  test: {
    environment: "jsdom",
    setupFiles: "../../tests/frontend/component/setup.ts",
    include: ["../../tests/frontend/component/**/*.test.tsx"],
  },
});
