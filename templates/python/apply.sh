#!/bin/sh
# Python overlay for /new-project. Run it from the new repo's root, on
# feature/scaffold, after the base files and this folder's gitignore:
#   sh ~/.claude/templates/python/apply.sh "<one-line description>"
# It makes a packaged src layout with a console entry point, pins Python 3.10,
# adds pytest with one smoke test, and runs the tests.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
desc=${1:?usage: apply.sh "<one-line description>"}
if [ -e pyproject.toml ]; then
    echo "pyproject.toml already exists, so this isn't a fresh repo. Not touching it." >&2
    exit 1
fi

# --vcs none: the repo already exists. The base README is kept as it is (uv only
# points pyproject's readme at it), and --python 3.10 sets both
# requires-python >=3.10 and .python-version.
uv init --package --app --vcs none --author-from none --python 3.10 --description "$desc" .
uv add --dev pytest

pkg=$(basename "$(ls -d src/*/)")  # the import name, as uv normalised it
mkdir -p tests
sed "s/PACKAGE/$pkg/" "$here/test_smoke.py" > tests/test_smoke.py
uv run pytest
