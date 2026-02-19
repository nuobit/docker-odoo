#!/usr/bin/env python
"""
Generate addons_path parameter for odoo.conf from repos.yaml and update odoo.conf
"""
import io
import re
import os
# shlex.quote is Python 3+; fall back to pipes.quote for Python 2
try:
    from shlex import quote
except ImportError:
    from pipes import quote
import subprocess

import yaml

from collections import OrderedDict

def load_yaml_ordered(stream):
    class OrderedLoader(yaml.SafeLoader):
        pass

    def construct_mapping(loader, node):
        loader.flatten_mapping(node)
        return OrderedDict(loader.construct_pairs(node))

    OrderedLoader.add_constructor(
        yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG,
        construct_mapping,
    )
    return yaml.load(stream, OrderedLoader)

def source_env(path):
    out = subprocess.check_output(
        ['bash', '-c', 'set -a; source {}; env -0'.format(quote(path))],
    ).decode('utf-8')
    return dict(
        item.split('=', 1) for item in sorted(out.split('\0')) if item
    )


def get_repos_yaml_addons_path(repos_yaml, base_dir, order=None, check_existence=True):
    order_dirs = {}
    if order:
        order_dirs = {od.strip(): i for i, od in enumerate(order.split(','))}
    last_pos = len(order_dirs)
    
    with open(repos_yaml, 'r') as f:
        repos_yaml_content = load_yaml_ordered(f)
    
    addons_path_weighted = []
    for path in repos_yaml_content.keys():
        full_path = os.path.join(base_dir, path)
        norm_full_path = os.path.normpath(full_path)
        if check_existence and not os.path.exists(norm_full_path):
            raise Exception("ERROR: {} not found".format(norm_full_path))
        relative_path = os.path.relpath(norm_full_path, base_dir)
        m = re.match(r'^([^/]+)(.*)$', relative_path)
        if not m:
            raise Exception("ERROR: Invalid path: {}".format(path))
        first_dir, rest = m.groups()
        addons_path_weighted.append((order_dirs.get(first_dir, last_pos), rest, norm_full_path))

    if order:
        addons_path_sorted_l = [
            fp for _, _, fp in sorted(addons_path_weighted, key=lambda x: (x[0], x[1]))
        ]  
    else:
        addons_path_sorted_l = [fp for _, _, fp in addons_path_weighted]     

    return ','.join(addons_path_sorted_l)


def update_odoo_conf_addons_path(odoo_conf, addons_path):
    with io.open(odoo_conf, 'r', encoding='utf-8') as f:
        odoo_conf_content = f.read()

    # Check if there's duplicate addons_path key
    # It has to be on a separate check before replacement, otherwise
    # we might end up with multiple addons_path lines after replacement
    duplicate_pattern = r'^(\s*addons_path\s*=\s*)'
    duplicated = re.findall(duplicate_pattern, odoo_conf_content, flags=re.MULTILINE)
    if len(duplicated) > 1:
        raise Exception("ERROR: Multiple addons_path lines found in odoo.conf. Please remove duplicates.")

    # Replace addons_path line (matches "addons_path = ..." with any whitespace)
    pattern = r'^(\s*addons_path\s*=\s*).*$'
    matches = list(re.finditer(pattern, odoo_conf_content, flags=re.MULTILINE))
    m = matches[-1] if matches else None  # Get the last match for addons_path
    if m:
        key = m.group(1).rstrip()
    else:
        key = 'addons_path ='

    replacement = r'%s %s' % (key, addons_path)

    if m:
        odoo_conf_content = re.sub(pattern, replacement, odoo_conf_content, flags=re.MULTILINE)
    else:
        # addons_path doesn't exist, add it to [options] section
        options_pattern = r'(\[options\])'
        if re.search(options_pattern, odoo_conf_content, flags=re.IGNORECASE):
            odoo_conf_content = re.sub(
                options_pattern,
                r'\1\naddons_path = {}'.format(addons_path),
                odoo_conf_content,
                flags=re.IGNORECASE
            )
        else:
            # No [options] section, add it at the beginning
            odoo_conf_content = '[options]\naddons_path = {}\n\n'.format(addons_path) + odoo_conf_content

    # Write back
    with io.open(odoo_conf, 'w', encoding='utf-8') as f:
        f.write(odoo_conf_content)


def main():
    # Load paths from configuration file
    config = source_env("%s/dist/defaults.env" % os.environ['HOME'])

    # REPOS
    src_dir = config['SRC_DIR']
    if not os.path.isdir(src_dir):
        raise Exception("ERROR: SRC_DIR not found at: {}".format(src_dir))
    repos_yaml = config['INSTANCE_REPOS']
    if not os.path.isfile(repos_yaml):
        raise Exception("ERROR: repos.yaml not found at: {}".format(repos_yaml))
    
    addons_path = get_repos_yaml_addons_path(
        repos_yaml, 
        src_dir, 
        order=config.get('SRC_REPOS_ORDER'), 
        check_existence=False,
    )
    
    # ODOO CONFIG
    # Check if odoo.conf exists
    odoo_conf = config['ODOO_CONF']
    if not os.path.isfile(odoo_conf):
        raise Exception("ERROR: ODOO_CONF not found at: {}".format(odoo_conf))

    update_odoo_conf_addons_path(odoo_conf, addons_path)


if __name__ == '__main__':
    main()
