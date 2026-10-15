"""Render services/*.yaml for `gcloud run ... replace`.

Substitutes ${BACKEND_IMAGE} / ${FRONTEND_IMAGE} from releases/*.txt and fills
every container named "django" with the environment in services/env.yaml,
followed by any env entries the file itself gives that container.
Writes the results to build/ with the same relative paths.
"""

import pathlib
import string
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent.parent


def release(name: str) -> str:
    path = ROOT / "releases" / f"{name}.txt"
    return path.read_text().strip() if path.exists() else ""


def django_env() -> list[dict]:
    spec = yaml.safe_load((ROOT / "services" / "env.yaml").read_text())
    env = [{"name": k, "value": str(v)} for k, v in spec["plain"].items()]
    env += [
        {"name": k, "valueFrom": {"secretKeyRef": {"name": secret, "key": "latest"}}}
        for k, secret in spec["secret"].items()
    ]
    return env


def fill(node, env):
    if isinstance(node, dict):
        if node.get("name") == "django" and "image" in node:
            # The shared environment, then whatever the file itself declares
            # (e.g. the seed job's ALFEE_DEMO_PASSWORD).
            node["env"] = env + (node.get("env") or [])
        for value in node.values():
            fill(value, env)
    elif isinstance(node, list):
        for item in node:
            fill(item, env)


def main() -> None:
    images = {"BACKEND_IMAGE": release("backend"), "FRONTEND_IMAGE": release("frontend")}
    env = django_env()
    out_root = ROOT / "build"
    for src in sorted((ROOT / "services").rglob("*.yaml")):
        if src.name == "env.yaml":
            continue
        text = string.Template(src.read_text()).safe_substitute(images)
        doc = yaml.safe_load(text)
        fill(doc, env)
        dest = out_root / src.relative_to(ROOT / "services")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(yaml.safe_dump(doc, sort_keys=False))
        print(f"rendered {dest.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
