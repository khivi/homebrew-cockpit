"""Check the installed venv is a complete dependency closure for cockpit.

Homebrew installs every resource with `--no-deps` (`Formula#std_pip_args`), so
nothing in a normal build ever evaluates a `Requires-Dist`. The resource blocks
ARE the dependency set, and a formula that is missing one, or pins below a
declared floor, installs cleanly and fails on the user's first `cockpit watch`.
This walks the requirements brew skipped.

Reachability from cockpit defines the subject. A bare `pip check` would do this
in one line, but it fails on the formula's venv today ("wheel requires
packaging, which is not installed") — Homebrew's scaffolding, not cockpit's
closure. Walking forward from the root never reaches pip/setuptools/wheel, so
nothing has to be ignored.

Usage: check_closure.py <site-packages-dir> [root-distribution]
"""

from __future__ import annotations

import sys
from importlib.metadata import Distribution, distributions

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name

ROOT = "cmux-cockpit"


def installed(site_packages: str) -> dict[str, Distribution]:
    return {canonicalize_name(d.metadata["Name"]): d for d in distributions(path=[site_packages])}


def wanted(dist: Distribution, extras: frozenset[str]) -> list[Requirement]:
    """Requirements that apply to this dist given the extras asked of it.

    Extras must be carried, not dropped: textual asks for
    `markdown-it-py[linkify,plugins]`, and linkify-it-py is reachable ONLY
    through that request. Pruning it makes a broken closure read as an unused
    resource.
    """
    contexts = [{"extra": ""}, *({"extra": e} for e in sorted(extras))]
    out = []
    for raw in dist.requires or []:
        req = Requirement(raw)
        if req.marker is None or any(req.marker.evaluate(c) for c in contexts):
            out.append(req)
    return out


def main() -> int:
    site_packages = sys.argv[1]
    root = canonicalize_name(sys.argv[2] if len(sys.argv) > 2 else ROOT)

    dists = installed(site_packages)
    if root not in dists:
        print(f"::error::{root} is not installed in {site_packages}")
        return 1

    broken: list[str] = []
    # name -> extras already expanded for it. A dist reached a second time with
    # a new extra has to be walked again, or requirements behind that extra go
    # unchecked.
    seen: dict[str, frozenset[str]] = {}
    queue: list[tuple[str, frozenset[str]]] = [(root, frozenset())]
    while queue:
        name, extras = queue.pop()
        done = seen.get(name)
        if done is not None and extras <= done:
            continue
        seen[name] = (done or frozenset()) | extras
        for req in wanted(dists[name], seen[name]):
            dep = canonicalize_name(req.name)
            if dep not in dists:
                broken.append(f"{name} requires {req}, which has no resource block")
                continue
            have = dists[dep].version
            if not req.specifier.contains(have, prereleases=True):
                broken.append(f"{name} requires {req}, but the pinned resource is {dep} {have}")
                continue
            queue.append((dep, frozenset(canonicalize_name(e) for e in req.extras)))

    if broken:
        for line in broken:
            print(f"::error::{line}")
        # No orphan report here on purpose: the walk stopped at each broken
        # edge, so everything downstream of one looks unreachable. Printing that
        # buries the one real error under a wall of false ones.
        print(f"\n{len(broken)} unsatisfied requirement(s). Regenerate with:")
        print("  brew update-python-resources Formula/cockpit.rb")
        return 1

    # Unreachable but installed: a resource whose last consumer dropped it. Not
    # breakage; a staleness signal that `brew update-python-resources` has not
    # run since that dependency moved.
    orphans = sorted(set(dists) - set(seen) - {"pip", "setuptools", "wheel"})
    for orphan in orphans:
        print(f"::warning::{orphan} {dists[orphan].version} is a resource nothing in cockpit's closure requires")

    print(f"closure ok: {len(seen)} packages reachable from {root}, every requirement satisfied")
    return 0


if __name__ == "__main__":
    sys.exit(main())
