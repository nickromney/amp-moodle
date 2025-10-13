# Ansible Rewrite: Moodle Deployment with Infrastructure as Code

## Executive Summary

This document describes how to achieve the same Moodle deployment functionality as `laemp.sh` using Ansible, leveraging the patterns from `ansible-role-moodle` (Geoffrey van Wyk) and Jeff Geerling's ecosystem of infrastructure roles. This represents a migration path from imperative bash scripting to declarative infrastructure as code.

## Why Consider Ansible?

### Advantages Over Bash

1. **Declarative Paradigm**: Describe desired state rather than execution steps
2. **Built-in Idempotency**: Most modules are idempotent by default
3. **Configuration Management**: Jinja2 templating with variable precedence
4. **Cross-platform Support**: Single playbook works across multiple distributions
5. **Testing Infrastructure**: Molecule framework with comprehensive scenario testing
6. **Modularity**: Reusable roles from Ansible Galaxy
7. **Error Handling**: Automatic rollback, detailed error reporting
8. **Community**: Large ecosystem of pre-built, tested roles

### Trade-offs

1. **Learning Curve**: YAML syntax, Jinja2 templates, Ansible concepts
2. **Dependency**: Requires Ansible installation on control node
3. **Complexity**: Additional layer of abstraction
4. **Debugging**: Can be harder to debug than bash
5. **Single-file Simplicity Lost**: Multiple files/directories vs one bash script

## Architecture Comparison

### laemp.sh Structure

```text
amp-moodle/
├── laemp.sh                 # 2,242 lines, all logic
├── test_laemp.bats          # Basic CLI tests
├── Dockerfile.ubuntu        # Test environment
├── Dockerfile.debian        # Test environment
└── logs/                    # Runtime logs
```

### Ansible Equivalent Structure

```text
moodle-playbook/
├── playbook.yml             # Main playbook (entry point)
├── inventory/
│   └── hosts                # Target servers
├── group_vars/
│   ├── all.yml              # Global variables
│   └── production.yml       # Environment-specific vars
├── roles/
│   └── requirements.yml     # External role dependencies
└── molecule/                # Testing scenarios
    ├── default/
    │   ├── molecule.yml
    │   ├── converge.yml
    │   └── verify.yml
    └── mariadb/
        └── ...
```

## Core Ansible Concepts

### Playbooks

**Playbooks** are YAML files defining automation tasks. Equivalent to running `laemp.sh` with specific flags:

```yaml
---
# playbook.yml - Full Moodle deployment
- name: Deploy Moodle LMS
  hosts: webservers
  become: yes  # Run with sudo

  vars:
    moodle_version: "4.5"
    moodle_domain: "moodle.example.com"
    web_server: "nginx"
    database_type: "mysql"

  roles:
    - role: geerlingguy.php
      php_version: "8.3"
    - role: geerlingguy.nginx
    - role: geerlingguy.mysql
    - role: geoffreyvanwyk.moodle
```

**Equivalent bash**: `./laemp.sh -p 8.3 -w nginx -d mysql -m 405`

### Roles

**Roles** are reusable automation units. Each role handles one component:

```yaml
# requirements.yml - Define role dependencies
---
roles:
  - name: geerlingguy.php
    version: 4.10.0
  - name: geerlingguy.nginx
    version: 3.1.4
  - name: geerlingguy.mysql
    version: 4.3.3
  - name: geoffreyvanwyk.moodle
    src: https://github.com/geoffreyvanwyk/ansible-role-moodle
    version: main
```

Install with: `ansible-galaxy install -r requirements.yml`

### Variables and Templating

Variables provide configuration flexibility with precedence ordering:

```yaml
# group_vars/all.yml - Defaults for all hosts
---
php_version: "8.3"
php_packages:
  - "php{{ php_version }}-common"
  - "php{{ php_version }}-cli"
  - "php{{ php_version }}-fpm"
  - "php{{ php_version }}-mysql"
  - "php{{ php_version }}-gd"
  - "php{{ php_version }}-intl"
  # ... all Moodle-required extensions

php_memory_limit: "256M"
php_max_input_vars: 5000
php_upload_max_filesize: "100M"
php_post_max_size: "100M"
```

```yaml
# group_vars/production.yml - Override for production
---
moodle_env: production
moodle_web_letsencrypt: true
moodle_db_install: true
```

```yaml
# group_vars/development.yml - Override for development
---
moodle_env: development
moodle_web_letsencrypt: false  # Use self-signed
moodle_db_install: true
```

**Jinja2 Templates** generate configuration files:

```jinja2
{# templates/php-fpm-pool.conf.j2 #}
[{{ pool_name }}]
user = {{ pool_user }}
group = {{ pool_group }}

listen = /run/php/php{{ php_version }}-{{ pool_name }}.sock
listen.owner = {{ listen_user }}
listen.group = {{ listen_group }}
listen.mode = 0660

pm = dynamic
pm.max_children = 50
pm.start_servers = 10
pm.min_spare_servers = 5
pm.max_spare_servers = 20
pm.max_requests = 500

php_admin_value[memory_limit] = {{ php_memory_limit }}
php_admin_value[max_input_vars] = {{ php_max_input_vars }}
php_admin_value[upload_max_filesize] = {{ php_upload_max_filesize }}
php_admin_value[post_max_size] = {{ php_post_max_size }}
```

Compare to `laemp.sh` heredoc (line 1460):

```bash
cat > "${pool_conf}" << EOF
[${pool_name}]
user = ${pool_user}
...
EOF
```

## Feature-by-Feature Migration

### 1. PHP Installation

**laemp.sh approach** (line 1342):

```bash
php_ensure() {
  # Detect OS
  # Add ondrej/php PPA
  # Install php8.3 package
  # Install extensions
}
```

**Ansible approach**:

```yaml
# Use geerlingguy.php role
- name: Install PHP
  hosts: webservers
  become: yes

  roles:
    - role: geerlingguy.php
      vars:
        php_version: "8.3"
        php_enable_webserver: false  # We'll use FPM
        php_enable_php_fpm: true
        php_packages:
          - "php{{ php_version }}-common"
          - "php{{ php_version }}-cli"
          - "php{{ php_version }}-fpm"
          - "php{{ php_version }}-mysql"
          - "php{{ php_version }}-gd"
          - "php{{ php_version }}-intl"
          - "php{{ php_version }}-mbstring"
          - "php{{ php_version }}-soap"
          - "php{{ php_version }}-xml"
          - "php{{ php_version }}-xmlrpc"
          - "php{{ php_version }}-zip"
          - "php{{ php_version }}-sodium"
          - "php{{ php_version }}-opcache"
          - "php{{ php_version }}-ldap"
        php_fpm_pools:
          - name: moodle
            user: www-data
            group: www-data
            listen: "/run/php/php{{ php_version }}-moodle.sock"
            pm: dynamic
            pm_max_children: 50
            pm_start_servers: 10
            pm_min_spare_servers: 5
            pm_max_spare_servers: 20
            pm_max_requests: 500
        php_ini_settings:
          memory_limit: "256M"
          max_execution_time: "300"
          max_input_vars: "5000"
          upload_max_filesize: "100M"
          post_max_size: "100M"
```

**Benefits**:

- Role handles OS detection automatically (Ubuntu/Debian/RedHat)
- Repository setup included (ondrej/sury PPAs)
- Idempotent: Can run multiple times safely
- Testable: Molecule scenarios validate configuration

### 2. Web Server Installation (Nginx)

**laemp.sh approach** (line 1145):

```bash
nginx_ensure() {
  # Add repository
  # Install nginx
  # Create optimized config
  # Create vhost
  # Enable and start
}
```

**Ansible approach**:

```yaml
# Use geerlingguy.nginx role
- name: Install and configure Nginx
  hosts: webservers
  become: yes

  roles:
    - role: geerlingguy.nginx
      vars:
        nginx_remove_default_vhost: true
        nginx_vhosts:
          - listen: "443 ssl http2"
            server_name: "{{ moodle_domain }}"
            root: "{{ moodle_deploy_destination }}"
            index: "index.php index.html"
            error_page: ""
            access_log: "/var/log/nginx/{{ moodle_domain }}.access.log"
            error_log: "/var/log/nginx/{{ moodle_domain }}.error.log"
            extra_parameters: |
              ssl_certificate {{ moodle_web_certificatefile }};
              ssl_certificate_key {{ moodle_web_certificatekeyfile }};

              location / {
                  try_files $uri $uri/ /index.php?$query_string;
              }

              location ~ [^/]\.php(/|$) {
                  fastcgi_split_path_info ^(.+\.php)(/.+)$;
                  if (!-f $document_root$fastcgi_script_name) {
                      return 404;
                  }

                  include fastcgi_params;
                  fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
                  fastcgi_param PATH_INFO $fastcgi_path_info;
                  fastcgi_pass unix:/run/php/php{{ php_version }}-{{ moodle_domain }}.sock;
                  fastcgi_index index.php;
              }

              include /etc/nginx/global/*.conf;

        nginx_extra_conf_options: |
          worker_processes auto;
          worker_rlimit_nofile 8192;

        nginx_extra_http_options: |
          client_max_body_size 100M;
          fastcgi_buffers 16 16k;
          fastcgi_buffer_size 32k;

          # Gzip compression
          gzip on;
          gzip_comp_level 5;
          gzip_min_length 256;
          gzip_types text/plain text/css application/json application/javascript text/xml;
```

**Benefits**:

- Role handles service management (enable, start, reload)
- Configuration validation before reload
- Handler-based restarts (only when config changes)
- SSL configuration templating

### 3. Database Installation (MySQL)

**laemp.sh approach** (NOT YET IMPLEMENTED):

```bash
mysql_ensure() {
  # Install MySQL server
  # Secure installation
  # Create database and user
  # Configure for Moodle
}
```

**Ansible approach**:

```yaml
# Use geerlingguy.mysql role
- name: Install and configure MySQL
  hosts: webservers
  become: yes

  roles:
    - role: geerlingguy.mysql
      vars:
        mysql_root_password: "{{ vault_mysql_root_password }}"  # From Ansible Vault
        mysql_databases:
          - name: "{{ moodle_db_name }}"
            encoding: utf8mb4
            collation: utf8mb4_unicode_ci
        mysql_users:
          - name: "{{ moodle_db_username }}"
            host: "localhost"
            password: "{{ vault_moodle_db_password }}"
            priv: "{{ moodle_db_name }}.*:ALL"
        mysql_innodb_file_per_table: "1"
        mysql_innodb_buffer_pool_size: "1G"
        mysql_innodb_log_file_size: "256M"
```

**Ansible Vault** for secrets:

```bash
# Create encrypted vault
ansible-vault create group_vars/all/vault.yml

# Contents (encrypted):
---
vault_mysql_root_password: "SuperSecureRootPassword123!"
vault_moodle_db_password: "MoodleDbPassword456!"
```

**Benefits**:

- Secrets encrypted at rest (Ansible Vault)
- No plaintext passwords in version control
- Idempotent database creation
- Automatic MySQL secure installation

### 4. Moodle Deployment

**laemp.sh approach** (line 837):

```bash
moodle_ensure() {
  # Download tarball
  # Extract to destination
  # Configure directories
  # Generate config.php
  # Run CLI installer (MISSING in current code)
}
```

**Ansible approach** (using `geoffreyvanwyk.moodle`):

```yaml
# Use specialized Moodle role
- name: Deploy Moodle
  hosts: webservers
  become: yes

  roles:
    - role: geoffreyvanwyk.moodle
      vars:
        moodle_version: "4.5"
        moodle_deploy_destination: "/var/www/html/moodle"
        moodle_deploy_update: true

        moodle_web_domain: "moodle.example.com"
        moodle_web_protocol: "https"
        moodle_web_letsencrypt: true

        moodle_db_install: true
        moodle_db_type: "pgsql"  # or "mariadb"
        moodle_db_name: "moodle_prod"
        moodle_db_username: "moodler"
        moodle_db_password: "{{ vault_moodle_db_password }}"

        moodle_site_fullname: "My Moodle LMS"
        moodle_site_shortname: "Moodle"
        moodle_admin_username: "admin"
        moodle_admin_password: "{{ vault_moodle_admin_password }}"
        moodle_admin_email: "admin@example.com"

        # Plugin installation
        moodle_plugins_git:
          - name: mod_hvp
            repository: https://github.com/h5p/moodle-mod_hvp.git
            version: stable
```

**Key features from `ansible-role-moodle`**:

1. **Git-based Deployment**: Clones from official Moodle repository
2. **ACL Permissions**: Uses `ansible.posix.acl` for fine-grained control
3. **Complete Installation**: Runs `admin/cli/install_database.php`
4. **Config.php Templating**: 1127-line Jinja2 template with all options
5. **Plugin Management**: Supports Frankenstyle naming, zip archives, Git repos
6. **Upgrade Support**: Detects existing installations, runs upgrade when needed
7. **Cron Setup**: Creates uniquely-named cron jobs per instance

### 5. SSL Certificates

**laemp.sh approach** (line 417, 1515):

```bash
acme_cert_request() {
  # Run certbot with --challenge flag (BROKEN)
}

self_signed_cert_request() {
  # Generate with openssl
}
```

**Ansible approach**:

```yaml
# Use geerlingguy.certbot role
- name: Install SSL certificates
  hosts: webservers
  become: yes

  roles:
    - role: geerlingguy.certbot
      when: moodle_web_letsencrypt | bool
      vars:
        certbot_create_if_missing: true
        certbot_create_method: standalone  # or webroot
        certbot_admin_email: "{{ moodle_admin_email }}"
        certbot_certs:
          - domains:
              - "{{ moodle_domain }}"
        certbot_auto_renew: true
        certbot_auto_renew_user: root
        certbot_auto_renew_hour: "3"
        certbot_auto_renew_minute: "30"
```

For self-signed (development):

```yaml
- name: Generate self-signed certificate
  when: not (moodle_web_letsencrypt | bool)
  block:
    - name: Ensure SSL directory exists
      ansible.builtin.file:
        path: /etc/ssl/private
        state: directory
        mode: '0700'

    - name: Generate private key
      community.crypto.openssl_privatekey:
        path: "/etc/ssl/private/{{ moodle_domain }}.key"
        size: 2048

    - name: Generate self-signed certificate
      community.crypto.x509_certificate:
        path: "/etc/ssl/certs/{{ moodle_domain }}.crt"
        privatekey_path: "/etc/ssl/private/{{ moodle_domain }}.key"
        provider: selfsigned
        selfsigned_not_after: "+365d"
        subject_alt_name:
          - "DNS:{{ moodle_domain }}"
          - "DNS:www.{{ moodle_domain }}"
```

**Benefits**:

- Role handles certbot installation and configuration
- Automatic renewal with cron job
- Certificate validation before use
- Support for multiple domains (SAN certificates)

### 6. Prometheus Monitoring

**laemp.sh approach** (line 1560):

```bash
prometheus_ensure() {
  # Download prometheus binary
  # Create systemd service
  # Install exporters manually
}
```

**Ansible approach**:

```yaml
# Use cloudalchemy.prometheus and exporters
- name: Install monitoring stack
  hosts: webservers
  become: yes

  roles:
    - role: cloudalchemy.prometheus
      vars:
        prometheus_version: "2.47.2"
        prometheus_global:
          scrape_interval: 15s
          evaluation_interval: 15s
        prometheus_scrape_configs:
          - job_name: 'prometheus'
            static_configs:
              - targets: ['localhost:9090']
          - job_name: 'node'
            static_configs:
              - targets: ['localhost:9100']
          - job_name: 'nginx'
            static_configs:
              - targets: ['localhost:9113']
          - job_name: 'php-fpm'
            static_configs:
              - targets: ['localhost:9253']

    - role: cloudalchemy.node_exporter

    - role: cloudalchemy.nginx_exporter
      vars:
        nginx_exporter_scrape_uri: "http://127.0.0.1:8080/nginx_status"
```

**Benefits**:

- Roles handle binary downloads and updates
- Systemd service creation and management
- Configuration templating
- Service dependency ordering

## Complete Playbook Example

**Full production deployment** equivalent to:
`./laemp.sh -p 8.3 -w nginx -d mysql -m 405 -a -r -M`

```yaml
---
# site.yml - Complete Moodle deployment playbook
- name: Deploy Moodle LMS with monitoring
  hosts: webservers
  become: yes

  vars_files:
    - group_vars/all.yml
    - group_vars/production.yml
    - group_vars/all/vault.yml

  pre_tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: yes
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"

  roles:
    # Phase 1: Base Infrastructure
    - role: geerlingguy.php
      tags: ['php']

    - role: geerlingguy.nginx
      tags: ['nginx', 'webserver']

    - role: geerlingguy.mysql
      when: moodle_db_type == "mysql"
      tags: ['database', 'mysql']

    - role: geerlingguy.postgresql
      when: moodle_db_type == "pgsql"
      tags: ['database', 'postgres']

    # Phase 2: SSL Certificates
    - role: geerlingguy.certbot
      when: moodle_web_letsencrypt | bool
      tags: ['ssl', 'certificates']

    # Phase 3: Caching
    - role: geerlingguy.memcached
      when: moodle_use_memcached | bool
      tags: ['cache', 'memcached']

    # Phase 4: Moodle Application
    - role: geoffreyvanwyk.moodle
      tags: ['moodle', 'application']

    # Phase 5: Monitoring
    - role: cloudalchemy.prometheus
      when: install_monitoring | bool
      tags: ['monitoring', 'prometheus']

    - role: cloudalchemy.node_exporter
      when: install_monitoring | bool
      tags: ['monitoring', 'exporters']

    - role: cloudalchemy.nginx_exporter
      when: install_monitoring | bool and webserver == "nginx"
      tags: ['monitoring', 'exporters']

  post_tasks:
    - name: Verify Moodle is accessible
      ansible.builtin.uri:
        url: "https://{{ moodle_domain }}"
        validate_certs: no
        return_content: yes
      register: moodle_check
      failed_when: "'Moodle' not in moodle_check.content"
      tags: ['verify']

    - name: Display access information
      ansible.builtin.debug:
        msg: |
          ===============================================
          Moodle deployment complete!

          URL: https://{{ moodle_domain }}
          Admin: {{ moodle_admin_username }}
          Password: (stored in vault)

          Prometheus: http://{{ ansible_host }}:9090
          ===============================================
      tags: ['verify']
```

**Run playbook**:

```bash
# Install role dependencies first
ansible-galaxy install -r requirements.yml

# Run playbook
ansible-playbook -i inventory/hosts site.yml --ask-vault-pass

# Run specific phases
ansible-playbook -i inventory/hosts site.yml --tags "php,nginx,database"

# Dry run (check mode)
ansible-playbook -i inventory/hosts site.yml --check --diff
```

## Testing with Molecule

**Molecule** is to Ansible what BATS would be to `laemp.sh` (but far more comprehensive).

### Test Scenario Structure

```yaml
# molecule/default/molecule.yml
---
driver:
  name: docker
platforms:
  - name: moodle-ubuntu-2204
    image: geerlingguy/docker-ubuntu2204-ansible
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    privileged: true
    pre_build_image: true
  - name: moodle-debian-11
    image: geerlingguy/docker-debian11-ansible
    command: /lib/systemd/systemd
    volumes:
      - /sys/fs/cgroup:/sys/fs/cgroup:ro
    privileged: true
    pre_build_image: true

provisioner:
  name: ansible
  playbooks:
    converge: converge.yml
    verify: verify.yml

verifier:
  name: ansible
```

### Converge Playbook (Installation)

```yaml
# molecule/default/converge.yml
---
- name: Converge
  hosts: all
  become: yes

  vars:
    moodle_version: "4.5"
    moodle_db_install: true
    moodle_web_letsencrypt: false  # Self-signed for testing

  roles:
    - role: geerlingguy.php
    - role: geerlingguy.nginx
    - role: geerlingguy.mysql
    - role: geoffreyvanwyk.moodle
```

### Verification Playbook

```yaml
# molecule/default/verify.yml
---
- name: Verify
  hosts: all
  gather_facts: no

  tasks:
    - name: Check Nginx is running
      ansible.builtin.systemd:
        name: nginx
        state: started
      check_mode: yes
      register: nginx_status
      failed_when: nginx_status.changed

    - name: Check PHP-FPM is running
      ansible.builtin.systemd:
        name: php8.3-fpm
        state: started
      check_mode: yes
      register: fpm_status
      failed_when: fpm_status.changed

    - name: Check MySQL is running
      ansible.builtin.systemd:
        name: mysql
        state: started
      check_mode: yes
      register: mysql_status
      failed_when: mysql_status.changed

    - name: Verify Moodle database exists
      community.mysql.mysql_db:
        name: moodle
        state: present
      check_mode: yes
      register: db_check
      failed_when: db_check.changed

    - name: Verify Moodle files exist
      ansible.builtin.stat:
        path: /var/www/html/moodle/config.php
      register: config_file
      failed_when: not config_file.stat.exists

    - name: Test web access
      ansible.builtin.uri:
        url: https://127.0.0.1
        validate_certs: no
        return_content: yes
      register: web_check
      failed_when: "'Moodle' not in web_check.content"
```

### Run Molecule Tests

```bash
# Full test lifecycle
molecule test

# Individual phases
molecule create     # Create test containers
molecule converge   # Run playbook
molecule verify     # Run verification tests
molecule destroy    # Clean up

# Idempotence test (run converge twice)
molecule converge
molecule idempotence

# Login to test container for debugging
molecule login -h moodle-ubuntu-2204
```

**Equivalent to**:

```bash
# What laemp.sh testing would look like:
podman build -f Dockerfile.ubuntu -t amp-moodle-ubuntu .
podman run -it amp-moodle-ubuntu
sudo ./laemp.sh -p -w nginx -d mysql -m 405 -S
# Manual verification...
```

## Migration Path

### Option 1: Coexistence

Keep `laemp.sh` for simple, single-server deployments. Use Ansible for:

- Multi-server deployments
- Complex configurations
- Continuous deployments
- Infrastructure updates

### Option 2: Gradual Migration

1. Start with Ansible for new installations
2. Use `laemp.sh` as documentation for role development
3. Migrate components incrementally
4. Keep bash script as fallback

### Option 3: Full Rewrite

1. Adopt `ansible-role-moodle` as base
2. Customize with additional roles
3. Add organization-specific configurations
4. Develop comprehensive Molecule test suite

## Jeff Geerling's Role Patterns

### Key Principles

1. **Defaults First**:

```yaml
# defaults/main.yml - User-configurable with sensible defaults
php_memory_limit: "256M"
php_webserver_daemon: "nginx"
php_enable_php_fpm: true
```

1. **OS-Specific Variables**:

```yaml
# vars/Debian.yml
php_packages:
  - "php{{ php_version }}-common"
  - "php{{ php_version }}-cli"

# vars/RedHat.yml
php_packages:
  - "php-common"
  - "php-cli"
```

1. **Handlers for Service Management**:

```yaml
# handlers/main.yml
- name: restart nginx
  ansible.builtin.systemd:
    name: nginx
    state: restarted
    daemon_reload: yes
```

1. **Minimal External Dependencies**:

```yaml
# meta/main.yml
dependencies: []  # Or minimal, well-maintained roles
```

1. **Comprehensive Testing**:

- Multiple OS distributions
- Different configuration scenarios
- Idempotence verification
- Upgrade paths

### Popular Geerling Roles for LAMP/LEMP

1. **geerlingguy.apache** (3000+ stars)
   - Cross-platform (Debian, RedHat, Arch, Solaris)
   - Configurable modules, vhosts, SSL
   - Comprehensive Molecule tests

2. **geerlingguy.nginx** (2500+ stars)
   - Similar cross-platform support
   - Template-based vhost configuration
   - Upstream configuration support

3. **geerlingguy.php** (3500+ stars)
   - Version management
   - Extension installation
   - FPM pool configuration
   - Multiple SAPI support

4. **geerlingguy.mysql** (2800+ stars)
   - Secure installation automation
   - Database and user management
   - Replication support
   - Performance tuning

5. **geerlingguy.certbot** (600+ stars)
   - Let's Encrypt automation
   - Auto-renewal setup
   - Multiple domain support

### Pattern: Modular Design

Rather than one monolithic role (like `laemp.sh` in one file), Geerling advocates composition:

```yaml
# Bad: Monolithic Moodle role that does everything
- role: monolithic_moodle
  vars:
    everything: configured_here

# Good: Composed from focused roles
- role: geerlingguy.php
- role: geerlingguy.nginx
- role: geerlingguy.mysql
- role: organization.moodle  # Just Moodle-specific logic
```

**Benefits**:

- Each role maintained by experts
- Mix and match for different stacks
- Easy to swap components (Nginx → Apache)
- Reusable across projects

## Conclusion

### When to Use laemp.sh (Bash)

****Good for**:

- Quick, one-off installations
- Learning/understanding the installation process
- Environments without Ansible
- Simple, single-server deployments
- Air-gapped systems (one file to transfer)
- When team expertise is primarily bash

### When to Use Ansible

****Good for**:

- Multi-server deployments
- Configuration management at scale
- Continuous deployment pipelines
- Complex infrastructure requirements
- Team collaboration (Git-based workflow)
- Compliance and audit requirements
- When reusability across projects matters

### Hybrid Approach

Many organizations use both:

- **Ansible** for production infrastructure
- **Bash scripts** for development environments
- **Ansible** calls bash scripts for custom tasks
- **Bash scripts** bootstrap Ansible installation

### Learning Resources

1. **Ansible for DevOps** by Jeff Geerling (book)
2. Geerling's YouTube channel - Ansible 101 series
3. Ansible Galaxy roles - <https://galaxy.ansible.com/geerlingguy>
4. Molecule documentation - <https://molecule.readthedocs.io/>

### Next Steps for amp-moodle Project

If migrating to Ansible:

1. **Study `ansible-role-moodle` (already cloned in `reference/`)
2. Create minimal playbook using existing roles
3. Test in Molecule with multiple scenarios
4. Add organization-specific customizations
5. Develop CI/CD pipeline with GitHub Actions
6. Document for team adoption

The `laemp.sh` script has been invaluable for understanding the installation process. This knowledge directly informs better Ansible automation. Even if migrating to Ansible, keeping `laemp.sh` as documentation of the "how" behind the "what" has significant value.
