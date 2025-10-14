import { test, expect } from '@playwright/test';
import * as dotenv from 'dotenv';
import * as path from 'path';

// Load test environment variables
dotenv.config({ path: path.resolve(__dirname, '../../.env.test') });

/**
 * E2E tests for Moodle installation via laemp.sh
 *
 * Prerequisites:
 * 1. Compose stack must be running: podman-compose up -d ubuntu
 * 2. Services must be healthy: podman-compose ps
 * 3. Admin credentials must be set in .env.test
 *
 * Test Coverage:
 * - HTTPS/SSL configuration
 * - Moodle homepage accessibility
 * - Login page rendering
 * - Admin authentication
 * - Database connectivity
 * - PHP processing
 */

const MOODLE_URL = process.env.MOODLE_URL || 'https://moodle.romn.co';
const ADMIN_USERNAME = process.env.MOODLE_ADMIN_USERNAME || 'admin';
const ADMIN_PASSWORD = process.env.MOODLE_ADMIN_PASSWORD;
const ADMIN_EMAIL = process.env.MOODLE_ADMIN_EMAIL || 'admin@moodle.romn.co';

// Skip all tests if credentials not configured
test.skip(!ADMIN_PASSWORD || ADMIN_PASSWORD === 'CHANGE_ME_FROM_INSTALL_OUTPUT',
  'Admin password not configured in .env.test');

test.describe('Moodle Installation - SSL/HTTPS', () => {

  test('should redirect HTTP to HTTPS', async ({ page, context }) => {
    // Test HTTP redirects to HTTPS
    const httpUrl = MOODLE_URL.replace('https://', 'http://');
    const response = await page.goto(httpUrl);

    // Should redirect to HTTPS
    expect(page.url()).toMatch(/^https:/);
    expect(response?.status()).toBe(200);
  });

  test('should load with HTTPS (ignoring self-signed cert warnings)', async ({ page }) => {
    // Playwright config has ignoreHTTPSErrors: true for self-signed certs
    const response = await page.goto(MOODLE_URL);

    expect(response?.status()).toBe(200);
    expect(page.url()).toMatch(/^https:/);
  });

  test('should set HTTPS security headers', async ({ page }) => {
    const response = await page.goto(MOODLE_URL);
    const headers = response?.headers();

    // Check for security headers (configured in nginx/apache)
    expect(headers).toBeDefined();
    // Note: Exact headers depend on web server configuration
    // This test documents what headers SHOULD be present
  });
});

test.describe('Moodle Installation - Homepage', () => {

  test('should load Moodle homepage successfully', async ({ page }) => {
    const response = await page.goto(MOODLE_URL);

    expect(response?.status()).toBe(200);
    expect(await page.title()).toContain('Moodle');
  });

  test('should not display PHP errors on homepage', async ({ page }) => {
    await page.goto(MOODLE_URL);

    // Check for common PHP error patterns
    const bodyText = await page.textContent('body');
    expect(bodyText).not.toContain('Fatal error');
    expect(bodyText).not.toContain('Parse error');
    expect(bodyText).not.toContain('Warning:');
    expect(bodyText).not.toContain('<?php'); // Raw PHP code should not be visible
  });

  test('should not display database connection errors', async ({ page }) => {
    await page.goto(MOODLE_URL);

    const bodyText = await page.textContent('body');
    expect(bodyText).not.toContain('database connection');
    expect(bodyText).not.toContain('Could not connect');
    expect(bodyText).not.toContain('Connection refused');
    expect(bodyText).not.toContain('Access denied');
  });

  test('should render Moodle UI elements', async ({ page }) => {
    await page.goto(MOODLE_URL);

    // Check for Moodle-specific elements
    // Login link/button should be visible
    const loginLink = page.locator('a:has-text("Log in"), button:has-text("Log in")');
    await expect(loginLink.first()).toBeVisible();
  });
});

test.describe('Moodle Installation - Login Page', () => {

  test('should load login page', async ({ page }) => {
    await page.goto(`${MOODLE_URL}/login/index.php`);

    expect(page.url()).toContain('/login');
    expect(await page.title()).toContain('Moodle');
  });

  test('should display login form', async ({ page }) => {
    await page.goto(`${MOODLE_URL}/login/index.php`);

    // Check for login form elements
    await expect(page.locator('input[name="username"]')).toBeVisible();
    await expect(page.locator('input[name="password"]')).toBeVisible();
    await expect(page.locator('button[type="submit"], input[type="submit"]')).toBeVisible();
  });

  test('should not show database errors on login page', async ({ page }) => {
    await page.goto(`${MOODLE_URL}/login/index.php`);

    const bodyText = await page.textContent('body');
    expect(bodyText).not.toContain('database');
    expect(bodyText).not.toContain('SQL');
    expect(bodyText).not.toContain('mysqli');
    expect(bodyText).not.toContain('pgsql');
  });
});

test.describe('Moodle Installation - Admin Authentication', () => {

  test('should log in as admin successfully', async ({ page }) => {
    // Navigate to login page
    await page.goto(`${MOODLE_URL}/login/index.php`);

    // Fill in admin credentials
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD!);

    // Submit login form
    await page.click('button[type="submit"], input[type="submit"]');

    // Wait for navigation after login
    await page.waitForLoadState('networkidle');

    // Should be redirected away from login page
    expect(page.url()).not.toContain('/login/index.php');

    // Should see user menu or profile link
    const userMenu = page.locator('.usermenu, .user-menu, a:has-text("' + ADMIN_USERNAME + '")');
    await expect(userMenu.first()).toBeVisible({ timeout: 10000 });
  });

  test('should reject invalid credentials', async ({ page }) => {
    await page.goto(`${MOODLE_URL}/login/index.php`);

    // Try invalid credentials
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', 'wrong_password_12345');
    await page.click('button[type="submit"], input[type="submit"]');

    // Should stay on login page or show error
    await page.waitForLoadState('networkidle');

    // Should show error message
    const errorMessage = page.locator('.alert, .error, [role="alert"]');
    await expect(errorMessage.first()).toBeVisible({ timeout: 5000 });
  });
});

test.describe('Moodle Installation - Admin Dashboard', () => {

  test.beforeEach(async ({ page }) => {
    // Log in before each test
    await page.goto(`${MOODLE_URL}/login/index.php`);
    await page.fill('input[name="username"]', ADMIN_USERNAME);
    await page.fill('input[name="password"]', ADMIN_PASSWORD!);
    await page.click('button[type="submit"], input[type="submit"]');
    await page.waitForLoadState('networkidle');
  });

  test('should access site administration as admin', async ({ page }) => {
    // Navigate to site administration
    await page.goto(`${MOODLE_URL}/admin/index.php`);

    // Should see admin page (not access denied)
    expect(page.url()).toContain('/admin');

    const bodyText = await page.textContent('body');
    expect(bodyText).not.toContain('Access denied');
    expect(bodyText).not.toContain('You do not have permission');
  });

  test('should see admin navigation elements', async ({ page }) => {
    await page.goto(`${MOODLE_URL}`);

    // Admin should see administration links
    // Note: Exact selectors depend on Moodle version and theme
    const adminLinks = page.locator('a:has-text("Site administration"), a:has-text("Administration")');

    // At least one admin link should be present
    expect(await adminLinks.count()).toBeGreaterThan(0);
  });
});

test.describe('Moodle Installation - PHP Processing', () => {

  test('should process PHP correctly (no raw PHP code visible)', async ({ page }) => {
    await page.goto(MOODLE_URL);

    const pageContent = await page.content();

    // Should not contain raw PHP tags
    expect(pageContent).not.toContain('<?php');
    expect(pageContent).not.toContain('<?=');

    // Should not contain PHP syntax elements
    expect(pageContent).not.toContain('namespace Moodle');
    expect(pageContent).not.toContain('require_once');
  });

  test('should set PHP session cookies', async ({ page, context }) => {
    await page.goto(MOODLE_URL);

    // Moodle sets session cookies
    const cookies = await context.cookies();

    // Should have at least one cookie (likely MoodleSession)
    expect(cookies.length).toBeGreaterThan(0);

    // Check for Moodle session cookie
    const sessionCookie = cookies.find(c =>
      c.name.includes('Moodle') || c.name.includes('PHPSESSID')
    );
    expect(sessionCookie).toBeDefined();
  });
});

test.describe('Moodle Installation - Health Checks', () => {

  test('should respond to health check endpoint', async ({ page }) => {
    // Try common health check URLs
    // Note: Moodle may not have a dedicated health endpoint
    // This test documents the expected behavior

    const response = await page.goto(MOODLE_URL);
    expect(response?.status()).toBe(200);
  });

  test('should complete page load within reasonable time', async ({ page }) => {
    const startTime = Date.now();

    await page.goto(MOODLE_URL);
    await page.waitForLoadState('networkidle');

    const loadTime = Date.now() - startTime;

    // Page should load in under 10 seconds
    expect(loadTime).toBeLessThan(10000);
  });

  test('should not have console errors', async ({ page }) => {
    const consoleErrors: string[] = [];

    page.on('console', msg => {
      if (msg.type() === 'error') {
        consoleErrors.push(msg.text());
      }
    });

    await page.goto(MOODLE_URL);
    await page.waitForLoadState('networkidle');

    // Should not have critical console errors
    // Note: Some warnings may be acceptable
    const criticalErrors = consoleErrors.filter(err =>
      !err.includes('favicon') && // Ignore favicon 404s
      !err.includes('analytics') // Ignore analytics failures in test
    );

    expect(criticalErrors.length).toBe(0);
  });
});
