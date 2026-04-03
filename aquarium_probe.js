#!/usr/bin/env node
// SPDX-License-Identifier: GPL-2.0
//
// Copyright (c) 2026 Galih Tama <galpt@v.recipes>
//
// Browser-side WebGL Aquarium probe using Playwright.

"use strict";

const fs = require("fs");
const path = require("path");
const { chromium } = require("playwright");

function parseArgs(argv) {
  const args = {
    url: "https://webglsamples.org/aquarium/aquarium.html",
    fishCount: 2000,
    durationSeconds: 45,
    settleSeconds: 5,
    width: 1600,
    height: 900,
    outJson: "",
    headless: false,
    browserPath: "",
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];
    switch (arg) {
      case "--url":
        args.url = next;
        i += 1;
        break;
      case "--fish-count":
        args.fishCount = Number.parseInt(next, 10);
        i += 1;
        break;
      case "--duration-seconds":
        args.durationSeconds = Number.parseInt(next, 10);
        i += 1;
        break;
      case "--settle-seconds":
        args.settleSeconds = Number.parseInt(next, 10);
        i += 1;
        break;
      case "--width":
        args.width = Number.parseInt(next, 10);
        i += 1;
        break;
      case "--height":
        args.height = Number.parseInt(next, 10);
        i += 1;
        break;
      case "--out-json":
        args.outJson = next;
        i += 1;
        break;
      case "--browser-path":
        args.browserPath = next;
        i += 1;
        break;
      case "--headless":
        args.headless = true;
        break;
      default:
        throw new Error(`Unknown option: ${arg}`);
    }
  }

  if (!args.outJson) {
    throw new Error("--out-json is required");
  }
  if (!Number.isFinite(args.fishCount) || args.fishCount <= 0) {
    throw new Error("--fish-count must be a positive integer");
  }
  if (!Number.isFinite(args.durationSeconds) || args.durationSeconds <= 0) {
    throw new Error("--duration-seconds must be a positive integer");
  }
  if (!Number.isFinite(args.settleSeconds) || args.settleSeconds < 0) {
    throw new Error("--settle-seconds must be zero or a positive integer");
  }

  return args;
}

function percentile(sortedValues, q) {
  if (!sortedValues.length) {
    return null;
  }
  if (sortedValues.length === 1) {
    return sortedValues[0];
  }
  const pos = (sortedValues.length - 1) * q;
  const base = Math.floor(pos);
  const rest = pos - base;
  const lower = sortedValues[base];
  const upper = sortedValues[Math.min(base + 1, sortedValues.length - 1)];
  return lower + (upper - lower) * rest;
}

function mean(values) {
  if (!values.length) {
    return null;
  }
  const total = values.reduce((acc, value) => acc + value, 0);
  return total / values.length;
}

function roundMaybe(value, digits = 3) {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return null;
  }
  return Number(value.toFixed(digits));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const pageUrl = new URL(args.url);
  pageUrl.searchParams.set("numFish", String(args.fishCount));

  const launchArgs = [
    "--enable-webgl",
    "--ignore-gpu-blocklist",
    "--disable-background-timer-throttling",
    "--disable-backgrounding-occluded-windows",
    "--disable-renderer-backgrounding",
  ];

  const browser = await chromium.launch({
    headless: args.headless,
    executablePath: args.browserPath || undefined,
    args: launchArgs,
  });

  const context = await browser.newContext({
    viewport: { width: args.width, height: args.height },
  });
  const page = await context.newPage();

  await page.addInitScript(() => {
    const probe = {
      active: false,
      lastTs: null,
      dts: [],
      fpsTexts: [],
      domFps: "",
      canvasWidth: null,
      canvasHeight: null,
    };
    window.__scxAquariumProbe = probe;

    function tick(ts) {
      if (probe.lastTs !== null && probe.active) {
        probe.dts.push(ts - probe.lastTs);
      }
      probe.lastTs = ts;
      window.requestAnimationFrame(tick);
    }

    window.requestAnimationFrame(tick);

    window.setInterval(() => {
      const fpsElem = document.getElementById("fps");
      const canvas = document.getElementById("canvas");

      if (probe.active && fpsElem) {
        const text = fpsElem.textContent || "";
        const parsed = Number.parseFloat(text);
        if (Number.isFinite(parsed)) {
          probe.fpsTexts.push(parsed);
        }
        probe.domFps = text.trim();
      }

      if (canvas) {
        probe.canvasWidth = canvas.width;
        probe.canvasHeight = canvas.height;
      }
    }, 250);
  });

  await page.goto(pageUrl.toString(), { waitUntil: "networkidle" });
  await page.waitForSelector("#fps", { timeout: 30000 });
  await page.waitForFunction(() => {
    const fps = Number.parseFloat(document.querySelector("#fps")?.textContent || "");
    return Number.isFinite(fps);
  }, { timeout: 30000 });

  await page.waitForTimeout(args.settleSeconds * 1000);
  await page.evaluate(() => {
    window.__scxAquariumProbe.active = true;
  });
  await page.waitForTimeout(args.durationSeconds * 1000);
  const raw = await page.evaluate(() => {
    const probe = window.__scxAquariumProbe;
    probe.active = false;
    return {
      dts: probe.dts,
      fpsTexts: probe.fpsTexts,
      domFps: probe.domFps,
      canvasWidth: probe.canvasWidth,
      canvasHeight: probe.canvasHeight,
      documentTitle: document.title,
    };
  });

  await browser.close();

  const frameMs = raw.dts.filter((value) => Number.isFinite(value) && value > 0);
  const fpsSamples = raw.fpsTexts.filter((value) => Number.isFinite(value) && value > 0);
  const sortedFrameMs = [...frameMs].sort((a, b) => a - b);
  const fpsFromFrames = frameMs.map((dt) => 1000 / dt).filter((value) => Number.isFinite(value) && value > 0);
  const sortedFps = [...fpsFromFrames].sort((a, b) => a - b);

  const avgFrameMs = mean(frameMs);
  const avgFps = avgFrameMs ? 1000 / avgFrameMs : null;
  const medianFps = percentile(sortedFps, 0.5);
  const onePercentLow = percentile(sortedFps, 0.01);
  const p95FrameMs = percentile(sortedFrameMs, 0.95);
  const p99FrameMs = percentile(sortedFrameMs, 0.99);
  const jankOver33 = frameMs.filter((dt) => dt > 33.333).length;
  const jankOver50 = frameMs.filter((dt) => dt > 50).length;
  const jankOver100 = frameMs.filter((dt) => dt > 100).length;

  const result = {
    aquarium_url: pageUrl.toString(),
    fish_count: args.fishCount,
    duration_seconds: args.durationSeconds,
    settle_seconds: args.settleSeconds,
    viewport_width: args.width,
    viewport_height: args.height,
    canvas_width: raw.canvasWidth,
    canvas_height: raw.canvasHeight,
    document_title: raw.documentTitle,
    ui_avg_fps: roundMaybe(mean(fpsSamples), 3),
    ui_last_fps: roundMaybe(Number.parseFloat(raw.domFps || ""), 3),
    raf_avg_fps: roundMaybe(avgFps, 3),
    raf_median_fps: roundMaybe(medianFps, 3),
    raf_1p_low_fps: roundMaybe(onePercentLow, 3),
    p95_frame_ms: roundMaybe(p95FrameMs, 3),
    p99_frame_ms: roundMaybe(p99FrameMs, 3),
    jank_over_33ms: jankOver33,
    jank_over_50ms: jankOver50,
    jank_over_100ms: jankOver100,
    frame_samples: frameMs.length,
  };

  fs.mkdirSync(path.dirname(args.outJson), { recursive: true });
  fs.writeFileSync(args.outJson, `${JSON.stringify(result, null, 2)}\n`, "utf8");
}

main().catch((error) => {
  console.error(`[aquarium-probe] ${error.message}`);
  process.exit(1);
});
