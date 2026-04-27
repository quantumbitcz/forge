# Detox Best Practices
> Support tier: contract-verified
## Overview
Detox is a gray-box E2E testing framework for React Native applications. Use it for testing iOS and Android apps built with React Native where you need automated UI testing with synchronization (automatic waiting for animations, network, and async operations). Avoid it for non-React-Native apps (use XCUITest/Espresso), web-only testing (use Cypress/Playwright), or when Appium's cross-platform approach is required.

## Conventions

### Test Structure
```javascript
describe("Login Flow", () => {
  beforeAll(async () => {
    await device.launchApp();
  });

  beforeEach(async () => {
    await device.reloadReactNative();
  });

  it("should login with valid credentials", async () => {
    await element(by.id("email-input")).typeText("alice@example.com");
    await element(by.id("password-input")).typeText("password123");
    await element(by.id("login-button")).tap();

    await expect(element(by.id("home-screen"))).toBeVisible();
    await expect(element(by.text("Welcome, Alice"))).toBeVisible();
  });

  it("should show error for invalid credentials", async () => {
    await element(by.id("email-input")).typeText("alice@example.com");
    await element(by.id("password-input")).typeText("wrong");
    await element(by.id("login-button")).tap();

    await expect(element(by.id("error-message"))).toBeVisible();
  });
});
```

### Device Commands
```javascript
await device.launchApp({ newInstance: true });
await device.reloadReactNative();
await device.takeScreenshot("login-success");
await device.setURLBlacklist([".*analytics.*"]);
```

## Configuration

```javascript
// .detoxrc.js
module.exports = {
  testRunner: { args: { config: "e2e/jest.config.js" }, jest: { setupTimeout: 120000 } },
  apps: {
    "ios.debug": { type: "ios.app", binaryPath: "ios/build/MyApp.app", build: "xcodebuild ..." },
    "android.debug": { type: "android.apk", binaryPath: "android/app/build/outputs/apk/debug/app-debug.apk", build: "cd android && ./gradlew assembleDebug" }
  },
  devices: {
    simulator: { type: "ios.simulator", device: { type: "iPhone 15" } },
    emulator: { type: "android.emulator", device: { avdName: "Pixel_7" } }
  },
  configurations: {
    "ios.sim.debug": { device: "simulator", app: "ios.debug" },
    "android.emu.debug": { device: "emulator", app: "android.debug" }
  }
};
```

## Dos
- Use `testID` props in React Native components for element selection — they work on both iOS and Android.
- Use `device.reloadReactNative()` between tests for isolation — faster than relaunching the app.
- Use `waitFor(element).toBeVisible().withTimeout(5000)` for elements that appear after async operations.
- Use `device.takeScreenshot()` on failure for debugging CI failures.
- Use `setURLBlacklist` to ignore analytics/tracking requests that cause sync issues.
- Run Detox tests on CI with dedicated simulators/emulators — not on physical devices.
- Mock API responses with a mock server (MSW, WireMock) for deterministic tests.

## Don'ts
- Don't select elements by text content for dynamic data — use `testID` for stable selectors.
- Don't rely on `sleep()` for waiting — Detox auto-synchronizes; use `waitFor` for edge cases.
- Don't run all E2E tests on every PR — run smoke tests on PR, full suite nightly.
- Don't test third-party SDKs (maps, payments) via Detox — mock their interfaces.
- Don't share state between tests — each test should start from a known app state.
- Don't ignore flaky tests — investigate synchronization issues, missing waits, or race conditions.
- Don't test on only one platform — run critical flows on both iOS and Android.
