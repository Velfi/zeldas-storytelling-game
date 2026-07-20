#!/usr/bin/env python3
"""Export, verify, install, enable, disable, and uninstall ExpansionPack v1 archives."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
import tomllib
import zipfile

FORMAT = "ExpansionPack"
FORMAT_VERSION = 1
SOURCE_VERSION = "ExpansionPack v1"
MANIFEST = "expansion-manifest.json"
PROFILE = "enabled-expansions.json"
REGISTRY = "catalog-registry.toml"
MAX_FILES = 20_000
MAX_BYTES = 2 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024


class ExpansionError(Exception):
    pass


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or "\\" in value or path.is_absolute() or ".." in path.parts:
        raise ExpansionError(f"unsafe expansion path: {value!r}")
    return path


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(CHUNK):
            digest.update(block)
    return digest.hexdigest()


def valid_identity(value: str) -> bool:
    return bool(value) and all(c.isalnum() or c in "-._" for c in value)


def valid_namespace(value: str) -> bool:
    return valid_identity(value) and ":" not in value and value != "core"


def semver(value: str) -> tuple[int, int, int]:
    try:
        parts = value.split(".")
        if len(parts) != 3:
            raise ValueError
        return tuple(int(part) for part in parts)  # type: ignore[return-value]
    except ValueError as error:
        raise ExpansionError(f"invalid semantic version: {value!r}") from error


def library_path() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Zelda's Storytelling Game/Expansions"
    if os.name == "nt":
        return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Zelda's Storytelling Game/Expansions"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zeldas-storytelling-game/Expansions"


def catalog_ids(path: Path, namespace: str) -> list[str]:
    try:
        document = tomllib.loads(path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        raise ExpansionError(f"cannot read expansion catalog {path}: {error}") from error
    ids: list[str] = []
    for family in ("objects", "materials", "presets", "audio", "animations", "characters"):
        records = document.get(family, [])
        if not isinstance(records, list):
            raise ExpansionError(f"catalog {family} must be an array of tables")
        for record in records:
            item = record.get("id") if isinstance(record, dict) else None
            if not isinstance(item, str) or item.count(":") != 1 or not item.startswith(namespace + ":"):
                raise ExpansionError(f"catalog ID must be qualified by {namespace}: {item!r}")
            ids.append(item)
    if len(ids) != len(set(ids)):
        raise ExpansionError("expansion catalogs contain duplicate qualified IDs")
    return ids


def load_source(config_path: Path) -> tuple[Path, dict, dict]:
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        root = config_path.parent.resolve()
        source_path = root / config["manifest"]
        source = tomllib.loads(source_path.read_text(encoding="utf-8"))
    except (OSError, KeyError, ValueError, tomllib.TOMLDecodeError) as error:
        raise ExpansionError(f"cannot read expansion source: {error}") from error
    required = ("id", "namespace", "title", "creator", "description", "version", "engine_min", "engine_max")
    if source.get("format") != SOURCE_VERSION or any(not source.get(key) for key in required):
        raise ExpansionError("expansion source is incomplete or has an unsupported format")
    if not valid_identity(str(source["id"])) or not valid_namespace(str(source["namespace"])):
        raise ExpansionError("expansion ID or namespace is invalid or reserved")
    semver(str(source["version"])); semver(str(source["engine_min"])); semver(str(source["engine_max"]))
    return root, config, source


def source_files(root: Path, config: dict, source: dict) -> list[tuple[Path, str]]:
    requested = list(config.get("include", [])) + list(source.get("catalogs", []))
    if config.get("thumbnail"):
        requested.append(config["thumbnail"])
    excluded = list(config.get("exclude", [])) + ["*/.*", "**/.*", "*.tmp", "*.autosave.*"]
    found: dict[str, Path] = {}
    for value in requested:
        relative = safe_relative(str(value)); candidate = root.joinpath(*relative.parts)
        if not candidate.exists():
            raise ExpansionError(f"included expansion path does not exist: {value}")
        for path in sorted(candidate.rglob("*")) if candidate.is_dir() else [candidate]:
            if path.is_symlink():
                raise ExpansionError(f"symbolic links are not allowed: {path}")
            if path.is_file():
                name = path.relative_to(root).as_posix()
                if not any(fnmatch.fnmatch(name, pattern) for pattern in excluded):
                    found[name] = path
    if not found or len(found) > MAX_FILES or sum(path.stat().st_size for path in found.values()) > MAX_BYTES:
        raise ExpansionError("expansion has an invalid file count or expanded size")
    return [(path, name) for name, path in sorted(found.items())]


def validate_manifest(manifest: dict, engine_version: str | None = None) -> None:
    if manifest.get("format") != FORMAT or manifest.get("format_version") != FORMAT_VERSION:
        raise ExpansionError("unsupported expansion package")
    for key in ("expansion_id", "namespace", "title", "creator", "description", "version", "engine", "catalogs", "files"):
        if key not in manifest:
            raise ExpansionError(f"expansion manifest is missing {key}")
    if not valid_identity(str(manifest["expansion_id"])) or not valid_namespace(str(manifest["namespace"])):
        raise ExpansionError("expansion manifest identity is invalid")
    semver(str(manifest["version"])); minimum = semver(str(manifest["engine"]["minimum"])); maximum = semver(str(manifest["engine"]["maximum"]))
    if minimum > maximum:
        raise ExpansionError("expansion engine range is invalid")
    if engine_version is not None and not minimum <= semver(engine_version) <= maximum:
        raise ExpansionError(f"expansion is incompatible with engine {engine_version}")
    records = manifest["files"]
    if not isinstance(records, list) or not records or len(records) > MAX_FILES:
        raise ExpansionError("expansion integrity table is invalid")
    names: set[str] = set(); total = 0
    for record in records:
        name = record.get("path") if isinstance(record, dict) else None
        if not isinstance(name, str):
            raise ExpansionError("expansion contains an invalid integrity record")
        safe_relative(name)
        if name in names:
            raise ExpansionError(f"duplicate expansion path: {name}")
        names.add(name); size = record.get("size"); digest = record.get("sha256")
        if not isinstance(size, int) or size < 0 or not isinstance(digest, str) or len(digest) != 64:
            raise ExpansionError(f"invalid expansion integrity record: {name}")
        total += size
    if total > MAX_BYTES or any(path not in names for path in manifest["catalogs"]):
        raise ExpansionError("expansion size or catalog entrypoints are invalid")


def verify(path: Path, engine_version: str | None = None) -> dict:
    try:
        with zipfile.ZipFile(path) as archive:
            if MANIFEST not in archive.namelist() or len(archive.namelist()) != len(set(archive.namelist())):
                raise ExpansionError("expansion archive has no manifest or contains duplicate paths")
            manifest = json.loads(archive.read(MANIFEST)); validate_manifest(manifest, engine_version)
            expected = {f"content/{item['path']}": item for item in manifest["files"]}
            actual = {info.filename: info for info in archive.infolist() if info.filename != MANIFEST and not info.is_dir()}
            if set(expected) != set(actual):
                raise ExpansionError("expansion archive contents do not match its manifest")
            for name, record in expected.items():
                data = archive.read(name)
                if len(data) != record["size"] or digest_bytes(data) != record["sha256"]:
                    raise ExpansionError(f"expansion integrity check failed: {record['path']}")
            return manifest
    except (OSError, KeyError, ValueError, json.JSONDecodeError, zipfile.BadZipFile) as error:
        raise ExpansionError(f"invalid expansion archive: {error}") from error


def export(args: argparse.Namespace) -> None:
    root, config, source = load_source(args.config.resolve()); files = source_files(root, config, source)
    all_catalog_ids: list[str] = []
    for catalog in source.get("catalogs", []):
        all_catalog_ids.extend(catalog_ids(root / safe_relative(str(catalog)), str(source["namespace"])))
    if len(all_catalog_ids) != len(set(all_catalog_ids)):
        raise ExpansionError("qualified IDs collide across contributed catalogs")
    capabilities = source.get("capabilities", [])
    if not isinstance(capabilities, list) or any(not isinstance(item, str) or "@" not in item for item in capabilities):
        raise ExpansionError("capabilities must use id@version strings")
    manifest = {
        "format": FORMAT, "format_version": FORMAT_VERSION,
        "expansion_id": source["id"], "namespace": source["namespace"], "version": str(source["version"]),
        "title": source["title"], "creator": source["creator"], "description": source["description"],
        "provenance": source.get("provenance", {}), "licenses": source.get("licenses", []),
        "engine": {"minimum": str(source["engine_min"]), "maximum": str(source["engine_max"])},
        "capabilities": capabilities, "catalogs": list(source.get("catalogs", [])),
        "thumbnail": config.get("thumbnail", ""), "redistribution_permitted": bool(source.get("redistribution_permitted", False)),
        "files": [{"path": name, "size": path.stat().st_size, "sha256": digest_file(path)} for path, name in files],
    }
    output = args.output.resolve(); output.parent.mkdir(parents=True, exist_ok=True); temporary = output.with_name(output.name + ".tmp")
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            archive.writestr(MANIFEST, json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            for source_path, name in files:
                archive.write(source_path, f"content/{name}")
        verify(temporary, args.engine_version); os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Exported {manifest['title']} {manifest['version']} to {output}")


def installed_manifests(root: Path) -> list[tuple[Path, dict]]:
    result = []
    for path in sorted(root.glob("*/*/" + MANIFEST)):
        try:
            result.append((path.parent, json.loads(path.read_text(encoding="utf-8"))))
        except (OSError, ValueError):
            continue
    return result


def profile_read(root: Path) -> set[str]:
    try:
        data = json.loads((root / PROFILE).read_text(encoding="utf-8")); return set(data.get("enabled", []))
    except (OSError, ValueError):
        return set()


def profile_write(root: Path, enabled: set[str]) -> None:
    enabled_manifests = [manifest for _, manifest in installed_manifests(root) if identity(manifest) in enabled]
    namespaces = [str(manifest["namespace"]) for manifest in enabled_manifests]
    if len(namespaces) != len(set(namespaces)):
        raise ExpansionError("enabled expansion versions contain a duplicate namespace")
    root.mkdir(parents=True, exist_ok=True); target = root / PROFILE; temporary = target.with_name(target.name + ".tmp")
    temporary.write_text(json.dumps({"enabled": sorted(enabled)}, indent=2) + "\n", encoding="utf-8"); os.replace(temporary, target)
    lines = ['format = "ExpansionCatalogRegistry v1"']
    for install_root, manifest in installed_manifests(root):
        item_identity = identity(manifest)
        if item_identity not in enabled:
            continue
        catalogs = [str((install_root / safe_relative(path)).resolve()) for path in manifest.get("catalogs", [])]
        quoted = ", ".join(json.dumps(path) for path in catalogs)
        manifest_hash = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()).hexdigest()
        lines.extend(["", "[[expansions]]", f"id = {json.dumps(manifest['expansion_id'])}", f"namespace = {json.dumps(manifest['namespace'])}", f"version = {json.dumps(manifest['version'])}", f"content_hash = {json.dumps(manifest_hash)}", f"catalogs = [{quoted}]"])
    registry = root / REGISTRY; registry_temporary = registry.with_name(registry.name + ".tmp")
    registry_temporary.write_text("\n".join(lines) + "\n", encoding="utf-8"); os.replace(registry_temporary, registry)


def identity(manifest: dict) -> str:
    return f"{manifest['expansion_id']}@{manifest['version']}"


def install_archive(path: Path, root: Path, replace: bool, engine_version: str) -> Path:
    manifest = verify(path.resolve(), engine_version)
    for _, existing in installed_manifests(root):
        if existing.get("namespace") == manifest["namespace"] and existing.get("expansion_id") != manifest["expansion_id"]:
            raise ExpansionError(f"namespace is already owned by {existing['expansion_id']}")
    destination = root / manifest["expansion_id"] / manifest["version"]
    if destination.exists() and not replace:
        raise ExpansionError(f"expansion version is already installed: {destination}")
    root.mkdir(parents=True, exist_ok=True); staging = Path(tempfile.mkdtemp(prefix="expansion-install-", dir=root))
    try:
        with zipfile.ZipFile(path) as archive:
            for record in manifest["files"]:
                target = staging.joinpath(*safe_relative(record["path"]).parts); target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(f"content/{record['path']}") as incoming, target.open("wb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
        (staging / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        backup = destination.with_name(destination.name + ".replace-backup")
        if destination.exists(): os.replace(destination, backup)
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.replace(staging, destination)
        except BaseException:
            if backup.exists(): os.replace(backup, destination)
            raise
        shutil.rmtree(backup, ignore_errors=True)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
    enabled = profile_read(root)
    enabled_namespaces = {item["namespace"] for _, item in installed_manifests(root) if identity(item) in enabled}
    if manifest["namespace"] not in enabled_namespaces:
        enabled.add(identity(manifest))
    profile_write(root, enabled); return destination


def dependent_stories(root: Path, expansion_identity: str) -> list[str]:
    stories_root = root.parent / "Stories"; dependents: list[str] = []
    for path in stories_root.glob("*/*/interactive-story-manifest.json"):
        try:
            manifest = json.loads(path.read_text(encoding="utf-8"))
            if any(f"{item['id']}@{item['version']}" == expansion_identity for item in manifest.get("expansions", [])):
                dependents.append(str(path.parent))
        except (OSError, ValueError, KeyError):
            continue
    return dependents


def set_enabled(root: Path, requested: str, enabled_value: bool) -> None:
    known = {identity(manifest) for _, manifest in installed_manifests(root)}
    if requested not in known: raise ExpansionError(f"expansion is not installed: {requested}")
    if not enabled_value and (dependents := dependent_stories(root, requested)):
        raise ExpansionError("expansion is required by installed stories: " + ", ".join(dependents))
    enabled = profile_read(root)
    if enabled_value:
        requested_manifest = next(manifest for _, manifest in installed_manifests(root) if identity(manifest) == requested)
        conflicts = [identity(manifest) for _, manifest in installed_manifests(root) if identity(manifest) in enabled and manifest["namespace"] == requested_manifest["namespace"] and identity(manifest) != requested]
        if conflicts:
            raise ExpansionError("another version owning this namespace is enabled: " + ", ".join(conflicts))
        enabled.add(requested)
    else: enabled.discard(requested)
    profile_write(root, enabled)


def uninstall(root: Path, requested: str) -> None:
    matches = [(path, manifest) for path, manifest in installed_manifests(root) if identity(manifest) == requested]
    if not matches: raise ExpansionError(f"expansion is not installed: {requested}")
    if dependents := dependent_stories(root, requested):
        raise ExpansionError("expansion is required by installed stories: " + ", ".join(dependents))
    path, _ = matches[0]; tombstone = path.with_name(path.name + ".uninstall"); os.replace(path, tombstone)
    try: shutil.rmtree(tombstone)
    except BaseException: os.replace(tombstone, path); raise
    enabled = profile_read(root); enabled.discard(requested); profile_write(root, enabled)


def main() -> int:
    parser = argparse.ArgumentParser(); sub = parser.add_subparsers(dest="command", required=True)
    export_parser = sub.add_parser("export"); export_parser.add_argument("output", type=Path); export_parser.add_argument("--config", type=Path, default=Path("expansion.package.json")); export_parser.add_argument("--engine-version", default="1.0.0")
    inspect_parser = sub.add_parser("inspect"); inspect_parser.add_argument("package", type=Path); inspect_parser.add_argument("--engine-version", default="1.0.0")
    install_parser = sub.add_parser("install"); install_parser.add_argument("package", type=Path); install_parser.add_argument("--library", type=Path, default=library_path()); install_parser.add_argument("--replace", action="store_true"); install_parser.add_argument("--engine-version", default="1.0.0")
    for command in ("enable", "disable", "uninstall"):
        item = sub.add_parser(command); item.add_argument("identity"); item.add_argument("--library", type=Path, default=library_path())
    args = parser.parse_args()
    if args.command == "export": export(args)
    elif args.command == "inspect": print(json.dumps(verify(args.package.resolve(), args.engine_version), indent=2, sort_keys=True))
    elif args.command == "install": print(install_archive(args.package, args.library.resolve(), args.replace, args.engine_version))
    elif args.command == "enable": set_enabled(args.library.resolve(), args.identity, True)
    elif args.command == "disable": set_enabled(args.library.resolve(), args.identity, False)
    else: uninstall(args.library.resolve(), args.identity)
    return 0


if __name__ == "__main__":
    try: raise SystemExit(main())
    except ExpansionError as error:
        print(f"error: {error}", file=sys.stderr); raise SystemExit(2)
