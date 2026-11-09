#!/bin/bash
# install_cis.sh - CIS Docker Benchmark at deployment, both stacks. Run as ansible on ansible-forge, from the
# folder holding cis-at-deploy.tar.gz:   bash install_cis.sh
#   1. backs up every file it replaces or edits to /opt/ansible/molecule/backups/cis-<date>/
#   2. installs from cis-at-deploy.tar.gz:
#        configure_guacamole and configure_grafana_stack: tasks/cis-benchmark.yml (new: runs the benchmark
#          install_docker_python staged in /root/bin/cis_docker and copies the report back), tasks/main.yml
#          (runs it as the last step), defaults/main.yml (cis_docker_enabled, cis_docker_dir, cis_results_dir)
#        run-guac16.sh, run-grafana12-deploy.sh: keep each run's CIS report in /opt/ansible/molecule/reports/cis/
#        grafana12-deploy verify.yml: checks the report was copied back
#   3. edits the installed guac16 verify.yml in place to check the report was copied back too
# Safe to run twice.
set -euo pipefail
TARBALL="${1:-cis-at-deploy.tar.gz}"
[ "$(id -un)" = ansible ] || { echo "run this as ansible"; exit 1; }
[ -f "$TARBALL" ] || { echo "missing $TARBALL"; exit 1; }
GV=/opt/ansible/nucleus/roles/configure_guacamole/molecule/guac16/verify.yml
BK=/opt/ansible/molecule/backups/cis-$(date +%F-%H%M); mkdir -p "$BK"
{ tar -tzf "$TARBALL" | grep -v '/$' | sed 's#^#/#'; echo "$GV"; } | while read -r f; do
  [ -f "$f" ] && { mkdir -p "$BK$(dirname "$f")"; cp -p "$f" "$BK$f"; }
done
tar -xzf "$TARBALL" -C / --no-same-owner --no-overwrite-dir -m
chmod +x /opt/ansible/molecule/run-guac16.sh /opt/ansible/molecule/run-grafana12-deploy.sh
echo "installed $(tar -tzf "$TARBALL" | grep -vc '/$') files"
python3 - "$GV" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
if 'CIS Docker Benchmark report copied back by the role' in s:
    print('guac16 verify.yml already checks the CIS report - left unchanged'); sys.exit(0)
anchor = '''        - name: Login, data and proxy checks
          ansible.builtin.assert:
            that:
'''
assert s.count(anchor) == 1, 'assert block not found once in %s - nothing changed' % p
s = s.replace(anchor, '''        - name: CIS Docker Benchmark report copied back by the role
          ansible.builtin.find:
            paths: "{{ art }}/provenance/{{ cls }}"
            patterns: "docker_cis_report-*.csv"
          delegate_to: localhost
          become: false
          register: cis

''' + anchor + '''              - cis.files | length > 0
''', 1)
s = s.replace("#   - nginx serves Guacamole over TLS", "#   - the role ran the CIS Docker Benchmark and copied its report back to the control node\n#   - nginx serves Guacamole over TLS", 1)
open(p, 'w').write(s); print('guac16 verify.yml: added the CIS report check')
PY
echo "Backups: $BK"
