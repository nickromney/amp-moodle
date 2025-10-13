# AMP Moodle Testing Guide

This project has three tiers of tests: Unit, Integration, and End-to-End (E2E).

## Test Tiers

### Tier 1: Unit Tests (test_laemp.bats)
**Purpose:** Test command-line option parsing and flag combinations

**Runtime:** Seconds
**Location:** Run on macOS host
**Requirements:** None (uses dry-run mode)

```bash
# Run all unit tests
bats test_laemp.bats

# Run specific test
bats test_laemp.bats --filter "php flag"
```

**Coverage:**
- Web server flags (`-w apache`, `-w nginx`)
- Database flags (`-d mysql`, `-d pgsql`)
- PHP version flags (`-p`, `-P`)
- SSL certificate flags (`-S`, `-a`)
- Monitoring and caching flags (`-r`, `-M`)
- Error conditions and invalid options

---

### Tier 2: Integration Tests (test_integration.bats)
**Purpose:** Test full script execution inside Podman containers

**Runtime:** Minutes per test
**Location:** Run on macOS host, execute in Podman containers
**Requirements:** Podman images built

```bash
# Build test images first (one-time setup)
podman build --platform linux/amd64 -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
podman build --platform linux/amd64 -f Dockerfile.debian -t amp-moodle-debian:13 .

# Run all integration tests
bats test_integration.bats

# Run specific test
bats test_integration.bats --filter "install nginx with php"

# Run with parallel execution (faster)
bats -j 4 test_integration.bats
```

**Coverage:**
- Basic installations (nginx/apache with PHP)
- Database installations (MySQL/PostgreSQL)
- SSL certificate creation
- Full Moodle installations (with database)
- Monitoring stack installation
- Configuration file verification
- Idempotency (running script twice)
- Service status verification
- Error handling
- Cross-distribution testing (Ubuntu 24.04/Debian 13)

**How it works:**
1. BATS runs on macOS host
2. Each test starts a fresh Podman container
3. Test copies `laemp.sh` into container
4. Test executes `laemp.sh` with specific flags via `podman exec`
5. Test verifies file existence, service status, configurations
6. Container is cleaned up after test

---

### Tier 3: End-to-End Tests (tests/e2e/moodle.spec.ts)
**Purpose:** Test actual web behavior with Playwright

**Runtime:** Seconds per test (after stack startup)
**Location:** Run on macOS host, test against containers
**Requirements:** Compose stack running, admin credentials configured

```bash
# 1. Start compose stack (prerequisite)
podman-compose up -d ubuntu  # or debian

# 2. Wait for services to be healthy
podman-compose ps

# 3. Get admin credentials from install output
podman-compose logs ubuntu | grep "Admin password"
# Example output: Admin password: aB3dEf9GhJ2kLmN4pQ

# 4. Configure test credentials
cp .env.test .env.test.local
# Edit .env.test.local and set MOODLE_ADMIN_PASSWORD

# 5. Install dependencies (first time only)
npm install

# 6. Run E2E tests
npm test

# Other useful commands:
npm run test:ui       # Run with Playwright UI
npm run test:headed   # Run with visible browser
npm run test:debug    # Run in debug mode
npm run test:report   # View HTML report
```

**Coverage:**
- HTTPS/SSL verification (redirects, self-signed certs)
- Moodle homepage accessibility
- Login page rendering
- Admin authentication
- Dashboard access
- Database connectivity (no connection errors)
- PHP processing (no raw PHP visible)
- Console error checking
- Performance (page load times)

**Test Structure:**
```
tests/e2e/moodle.spec.ts
├── SSL/HTTPS tests (3 tests)
├── Homepage tests (4 tests)
├── Login page tests (3 tests)
├── Admin authentication tests (2 tests)
├── Admin dashboard tests (2 tests)
├── PHP processing tests (2 tests)
└── Health checks (3 tests)
```

---

## Running All Tests

```bash
# 1. Unit tests (fast, no dependencies)
bats test_laemp.bats

# 2. Integration tests (requires images)
bats test_integration.bats

# 3. E2E tests (requires running compose stack)
podman-compose up -d ubuntu
npm test
```

---

## Test Architecture Decisions

### Why Three Tiers?

1. **Unit tests** validate logic without side effects (fast feedback)
2. **Integration tests** verify system behavior in realistic environment
3. **E2E tests** validate user-facing behavior (web tier)

### Why Not Auto-Start Compose in E2E Tests?

**Decision:** Tests assume compose stack is already running

**Rationale:**
- Faster test execution (no startup overhead between test runs)
- Easier debugging (stack stays running, can inspect manually)
- Simpler test code (no Docker/Podman orchestration from Node)
- Explicit stack lifecycle (developers control when to start/stop)

**Trade-off:**
- Requires manual stack management
- Tests may fail if stack is in bad state

**Solution:** Document prerequisites clearly (see E2E section above)

---

## Troubleshooting

### Integration Tests Hang

**Problem:** Test timeout or hangs during execution

**Solutions:**
```bash
# Check if Podman is running
podman ps

# Check Podman machine (macOS)
podman machine list
podman machine start  # if stopped

# Clean up stale containers
podman ps -a --filter name=laemp-test
podman rm -f $(podman ps -a --filter name=laemp-test -q)
```

### E2E Tests Fail with Connection Errors

**Problem:** Cannot connect to Moodle at https://moodle.romn.co

**Solutions:**
```bash
# 1. Check compose stack is running
podman-compose ps

# 2. Check container health
podman-compose logs ubuntu

# 3. Verify port mappings
podman port <container-name>

# 4. Check host resolution (add to /etc/hosts if needed)
echo "127.0.0.1 moodle.romn.co" | sudo tee -a /etc/hosts

# 5. Test direct connection
curl -k https://moodle.romn.co
```

### E2E Tests Skip with "Admin password not configured"

**Problem:** Tests skip because credentials not set

**Solution:**
```bash
# 1. Get admin password from container logs
podman-compose logs ubuntu | grep "Admin password"

# 2. Update .env.test
vi .env.test
# Set: MOODLE_ADMIN_PASSWORD=<password from logs>

# 3. Verify configuration loaded
cat .env.test | grep MOODLE_ADMIN_PASSWORD
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Tests

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install BATS
        run: sudo apt-get install -y bats
      - name: Run unit tests
        run: bats test_laemp.bats

  integration-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build test images
        run: |
          podman build -f Dockerfile.ubuntu -t amp-moodle-ubuntu:24.04 .
      - name: Run integration tests
        run: bats test_integration.bats

  e2e-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Start compose stack
        run: podman-compose up -d ubuntu
      - name: Wait for services
        run: sleep 30
      - name: Configure test credentials
        run: |
          ADMIN_PASS=$(podman-compose logs | grep "Admin password" | awk '{print $NF}')
          echo "MOODLE_ADMIN_PASSWORD=$ADMIN_PASS" >> .env.test
      - name: Install Node dependencies
        run: npm ci
      - name: Run Playwright tests
        run: npm test
      - name: Upload test report
        if: always()
        uses: actions/upload-artifact@v3
        with:
          name: playwright-report
          path: playwright-report/
```

---

## Additional Resources

- **Container testing guide:** `docs/container-testing.md`
- **BATS documentation:** https://bats-core.readthedocs.io/
- **Playwright documentation:** https://playwright.dev/
- **Moodle documentation:** https://docs.moodle.org/
