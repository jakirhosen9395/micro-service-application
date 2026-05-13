import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/main.ts"],
  format: ["esm"],
  target: "node24",
  platform: "node",
  dts: false,
  sourcemap: true,
  clean: true,
  splitting: false,
  minify: false,
  treeshake: true,
  external: [
    "@aws-sdk/client-s3",
    "bullmq",
    "csv-stringify",
    "dotenv",
    "elastic-apm-node",
    "exceljs",
    "fastify",
    "ioredis",
    "jsonwebtoken",
    "kafkajs",
    "mongodb",
    "pdfkit",
    "pg",
    "swagger-ui-dist",
    "zod"
  ]
});
