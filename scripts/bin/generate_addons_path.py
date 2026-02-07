#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Generate addons_path parameter for odoo.conf from repos.yaml and update odoo.conf
"""
import os
import re
import sys
import yaml


def load_config():
    """Load configuration from config.env"""
    config_file = '/opt/odoo/etc/config.env'
    config = {}
    
    if os.path.isfile(config_file):
        with open(config_file, 'r') as f:
            for line in f:
                line = line.strip()
                # Skip comments and empty lines
                if not line or line.startswith('#'):
                    continue
                # Parse KEY=VALUE or KEY=${VAR:-default}
                if '=' in line:
                    key, value = line.split('=', 1)
                    key = key.strip()
                    value = value.strip()
                    
                    # Handle ${VAR:-default} syntax - extract default value
                    match = re.match(r'\$\{[^:}]+:-([^}]+)\}', value)
                    if match:
                        value = match.group(1)
                    
                    # Expand ${VAR} references using already-parsed values
                    value = re.sub(r'\$\{([^}]+)\}', lambda m: config.get(m.group(1), ''), value)
                    
                    config[key] = value
    
    return config


def main():
    # Load configuration
    config = load_config()
    
    # Get paths from config (environment variables take precedence)
    odoo_conf_dir = os.environ.get('ODOO_CONF_DIR') or config.get('ODOO_CONF_DIR', '/etc/odoo')
    odoo_conf = os.environ.get('ODOO_CONF') or config.get('ODOO_CONF') or os.path.join(odoo_conf_dir, 'odoo.conf')
    repos_yaml = os.environ.get('SRC_REPOS_FILENAME') or config.get('SRC_REPOS_FILENAME', 'repos.yaml')
    
    # Check if repos.yaml exists
    if not os.path.isfile(repos_yaml):
        print("ERROR: repos.yaml not found at: {}".format(repos_yaml), file=sys.stderr)
        sys.exit(1)
    
    # Read repos.yaml
    try:
        with open(repos_yaml, 'r') as f:
            repos = yaml.safe_load(f)
    except Exception as e:
        print("ERROR: Failed to read repos.yaml: {}".format(e), file=sys.stderr)
        sys.exit(1)
    
    if not repos:
        print("ERROR: repos.yaml is empty", file=sys.stderr)
        sys.exit(1)
    
    # Get all paths (keys) from repos.yaml
    # Example: './odoo', './oca/account-closing', etc.
    paths = list(repos.keys())
    
    # Sort for consistent output
    paths.sort()
    
    # Join with comma for odoo.conf addons_path format
    addons_path = ','.join(paths)
    
    # Check if odoo.conf exists
    if not os.path.isfile(odoo_conf):
        print("ERROR: odoo.conf not found at: {}".format(odoo_conf), file=sys.stderr)
        sys.exit(1)
    
    # Read odoo.conf
    try:
        with open(odoo_conf, 'r') as f:
            content = f.read()
    except Exception as e:
        print("ERROR: Failed to read {}: {}".format(odoo_conf, e), file=sys.stderr)
        sys.exit(1)
    
    # Replace addons_path line (matches "addons_path = ..." with any whitespace)
    pattern = r'^(\s*addons_path\s*=\s*).*$'
    replacement = r'\g<1>{}'.format(addons_path)
    
    new_content, count = re.subn(pattern, replacement, content, flags=re.MULTILINE)
    
    if count == 0:
        # addons_path doesn't exist, add it to [options] section
        options_pattern = r'(\[options\])'
        if re.search(options_pattern, new_content, flags=re.IGNORECASE):
            new_content = re.sub(
                options_pattern,
                r'\1\naddons_path = {}'.format(addons_path),
                new_content,
                flags=re.IGNORECASE
            )
        else:
            # No [options] section, add it at the beginning
            new_content = '[options]\naddons_path = {}\n\n'.format(addons_path) + new_content
    
    # Write back
    try:
        with open(odoo_conf, 'w') as f:
            f.write(new_content)
    except Exception as e:
        print("ERROR: Failed to write {}: {}".format(odoo_conf, e), file=sys.stderr)
        sys.exit(1)
    
    print("Updated {} with addons_path: {}".format(odoo_conf, addons_path))


if __name__ == '__main__':
    main()
