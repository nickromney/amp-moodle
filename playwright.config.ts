import { defineConfig, devices } from '@playwright/test';

/**
 * Playwright configuration for AMP Moodle E2E tests
 *
 * Prerequisites:
 * 1. Start compose stack: podman-compose up -d ubuntu
 * 2. Wait for services: podman-compose ps (check health)
 * 3. Get credentials: podman-compose logs ubuntu | grep "Admin password"
 * 4. Set MOODLE_URL and MOODLE_ADMIN_PASSWORD in .env.test
 *
 * Run tests: npm test
 */
export default defineConfig({
  testDir: './tests/e2e',

  /* Maximum time one test can run for */
  timeout: 30 * 1000,

  /* Run tests in files in parallel */
  fullyParallel: true,

  /* Fail the build on CI if you accidentally left test.only in the source code */
  forbidOnly: !!process.env.CI,

  /* Retry on CI only */
  retries: process.env.CI ? 2 : 0,

  /* Reporter to use */
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report' }]
  ],

  /* Shared settings for all the projects below */
  use: {
    /* Base URL - override in .env.test */
    baseURL: process.env.MOODLE_URL || 'https://moodle.romn.co',

    /* Collect trace when retrying the failed test */
    trace: 'on-first-retry',

    /* Screenshots on failure */
    screenshot: 'only-on-failure',

    /* Ignore HTTPS errors (self-signed certs in test environment) */
    ignoreHTTPSErrors: true,
  },

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },

    // Uncomment to test on other browsers
    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] },
    // },
    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] },
    // },
  ],
});
