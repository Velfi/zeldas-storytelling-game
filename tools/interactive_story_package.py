#!/usr/bin/env python3
"""Export, inspect, verify, and install InteractiveStoryPackage archives."""

from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tempfile
import tomllib
import zipfile

if str(Path(__file__).resolve().parent) not in sys.path:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
import expansion_package

FORMAT = "InteractiveStoryPackage"
FORMAT_VERSION = 1
MANIFEST = "interactive-story-manifest.json"
MAX_FILES = 20_000
MAX_BYTES = 2 * 1024 * 1024 * 1024
CHUNK = 1024 * 1024
DETERMINISTIC_ZIP_TIME = (1980, 1, 1, 0, 0, 0)


class PackageError(Exception):
    pass


def deterministic_zip_write(archive: zipfile.ZipFile, name: str, data: bytes | str) -> None:
    """Write an entry without inheriting filesystem mtimes or host attributes."""
    info = zipfile.ZipInfo(name, DETERMINISTIC_ZIP_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)


def digest_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(CHUNK):
            digest.update(block)
    return digest.hexdigest()


def safe_relative(value: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if not value or "\\" in value or path.is_absolute() or ".." in path.parts:
        raise PackageError(f"unsafe package path: {value!r}")
    return path


def config_files(root: Path, config: dict) -> list[tuple[Path, str]]:
    requested = list(config.get("include", []))
    requested.append(config["story"])
    if config.get("level"):
        requested.append(config["level"])
    if config.get("thumbnail"):
        requested.append(config["thumbnail"])
    excluded = list(config.get("exclude", [])) + ["*/.*", "**/.*", "*.tmp", "*.autosave.*"]
    found: dict[str, Path] = {}
    for value in requested:
        relative = safe_relative(value)
        source = root.joinpath(*relative.parts)
        if not source.exists():
            raise PackageError(f"included path does not exist: {value}")
        candidates = sorted(source.rglob("*")) if source.is_dir() else [source]
        for candidate in candidates:
            if candidate.is_symlink():
                raise PackageError(f"symbolic links are not allowed: {candidate}")
            if candidate.is_file():
                name = candidate.relative_to(root).as_posix()
                if not any(fnmatch.fnmatch(name, pattern) for pattern in excluded):
                    found[name] = candidate
    if not found or len(found) > MAX_FILES:
        raise PackageError("package has an invalid number of files")
    if sum(path.stat().st_size for path in found.values()) > MAX_BYTES:
        raise PackageError("package exceeds the expanded size limit")
    return [(source, name) for name, source in sorted(found.items())]


def load_source(root: Path, config_path: Path) -> tuple[dict, dict]:
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        story = tomllib.loads((root / config["story"]).read_text(encoding="utf-8"))
    except (OSError, KeyError, ValueError, tomllib.TOMLDecodeError) as error:
        raise PackageError(f"cannot read story package source: {error}") from error
    for key in ("story", "author", "description", "content_version"):
        if not config.get(key):
            raise PackageError(f"package config is missing {key}")
    if story.get("version") != "InteractiveStory v1" or not story.get("id") or not story.get("title"):
        raise PackageError("entrypoint is not a valid InteractiveStory v1 source")
    if str(story.get("content_version")) != str(config["content_version"]):
        raise PackageError("package and story content versions do not match")
    return config, story


def validate_manifest(manifest: dict) -> None:
    if manifest.get("format") != FORMAT or manifest.get("format_version") != FORMAT_VERSION:
        raise PackageError("unsupported interactive story package")
    for key in ("story_id", "title", "author", "description", "content_version", "capabilities", "expansions", "resolved_content_identity", "entrypoints"):
        if key not in manifest or key not in {"capabilities", "expansions"} and not manifest.get(key):
            raise PackageError(f"manifest is missing {key}")
    identity = manifest["story_id"] + manifest["content_version"]
    if any(not (character.isalnum() or character in "-._") for character in identity):
        raise PackageError("story identity is not filesystem-safe")
    records = manifest.get("files")
    if not isinstance(records, list) or not records or len(records) > MAX_FILES:
        raise PackageError("manifest file list is invalid")
    names: set[str] = set()
    total = 0
    for record in records:
        name = record.get("path") if isinstance(record, dict) else None
        if not isinstance(name, str):
            raise PackageError("manifest contains an invalid file record")
        safe_relative(name)
        if name in names:
            raise PackageError(f"duplicate manifest path: {name}")
        names.add(name)
        size, digest = record.get("size"), record.get("sha256")
        if not isinstance(size, int) or size < 0 or not isinstance(digest, str) or len(digest) != 64:
            raise PackageError(f"invalid integrity record: {name}")
        total += size
    if total > MAX_BYTES:
        raise PackageError("manifest exceeds the expanded size limit")
    if manifest["entrypoints"].get("story") not in names:
        raise PackageError("story entrypoint is absent from content")
    level = manifest["entrypoints"].get("level", "")
    if level and level not in names:
        raise PackageError("level entrypoint is absent from content")
    seen_capabilities: set[str] = set()
    for item in manifest["capabilities"]:
        if not isinstance(item, dict) or not item.get("id") or not item.get("version") or item["id"] in seen_capabilities:
            raise PackageError("manifest contains an invalid or duplicate capability")
        seen_capabilities.add(item["id"])
    seen_expansions: set[str] = set()
    for item in manifest["expansions"]:
        if not isinstance(item, dict) or not item.get("id") or not item.get("version") or item["id"] in seen_expansions or item.get("distribution") not in {"reference", "embed"}:
            raise PackageError("manifest contains an invalid or duplicate expansion")
        if item.get("optional") and item.get("fallback") != "omit":
            raise PackageError("optional expansion requires the omit fallback")
        if item.get("distribution") == "embed" and not item.get("embedded_path"):
            raise PackageError("embedded expansion has no archive record")
        seen_expansions.add(item["id"])


def verify(path: Path) -> dict:
    try:
        with zipfile.ZipFile(path) as archive:
            infos = archive.infolist()
            if len(infos) > MAX_FILES + 1 or len({info.filename for info in infos}) != len(infos):
                raise PackageError("archive has too many or duplicate entries")
            if MANIFEST not in archive.namelist():
                raise PackageError("archive has no interactive story manifest")
            manifest = json.loads(archive.read(MANIFEST))
            validate_manifest(manifest)
            expected = {f"content/{item['path']}": item for item in manifest["files"]}
            for item in manifest["expansions"]:
                if item.get("distribution") == "embed":
                    expected[item["embedded_path"]] = item
            actual = {info.filename: info for info in infos if info.filename != MANIFEST and not info.is_dir()}
            if set(expected) != set(actual):
                raise PackageError("archive contents do not match the manifest")
            for name, record in expected.items():
                safe_relative(name)
                digest = hashlib.sha256()
                size = 0
                with archive.open(name) as stream:
                    while block := stream.read(CHUNK):
                        size += len(block)
                        digest.update(block)
                if size != record["size"] or digest.hexdigest() != record["sha256"]:
                    raise PackageError(f"integrity check failed: {record['path']}")
                if name.startswith("expansions/"):
                    with tempfile.NamedTemporaryFile(suffix=".expansion") as temporary:
                        temporary.write(archive.read(name)); temporary.flush(); embedded = expansion_package.verify(Path(temporary.name))
                    if embedded["expansion_id"] != record["id"] or embedded["version"] != record["version"] or not embedded.get("redistribution_permitted"):
                        raise PackageError(f"embedded expansion identity or redistribution policy is invalid: {record['id']}")
            return manifest
    except (OSError, zipfile.BadZipFile, KeyError, ValueError, json.JSONDecodeError) as error:
        raise PackageError(f"invalid interactive story package: {error}") from error


def export(args: argparse.Namespace) -> None:
    root = args.root.resolve()
    config, story = load_source(root, args.config.resolve())
    if not args.skip_engine_validation:
        validator = args.validator.resolve()
        checked = subprocess.run([str(validator), "--validate-story", config["story"]], cwd=root, text=True, capture_output=True)
        if checked.returncode:
            raise PackageError("engine validation failed: " + (checked.stderr or checked.stdout).strip())
    files = config_files(root, config)
    # Structural engine validation is implemented. Exhaustive state-space proof
    # is not yet available, so the exporter must never describe this package as
    # proven. Creators explicitly acknowledge that limitation in source config.
    if not config.get("acknowledge_incomplete_validation"):
        raise PackageError("state-space proof is incomplete; set acknowledge_incomplete_validation in the package config")
    capabilities = story.get("capabilities", [])
    requirements = story.get("expansions", [])
    if not isinstance(capabilities, list) or not isinstance(requirements, list):
        raise PackageError("story capabilities and expansions must be arrays of tables")
    configured_archives = config.get("expansion_packages", {})
    expansion_records: list[dict] = []
    embedded_archives: list[tuple[Path, str]] = []
    for requirement in requirements:
        if not isinstance(requirement, dict):
            raise PackageError("story expansion requirement is invalid")
        expansion_id, version = str(requirement.get("id", "")), str(requirement.get("version", ""))
        distribution = str(requirement.get("distribution", "reference"))
        record = {"id": expansion_id, "version": version, "optional": bool(requirement.get("optional", False)), "distribution": distribution, "fallback": str(requirement.get("fallback", "none"))}
        if distribution == "embed":
            configured = configured_archives.get(f"{expansion_id}@{version}")
            if not configured:
                raise PackageError(f"embedded expansion archive is not configured: {expansion_id}@{version}")
            archive_path = (root / safe_relative(str(configured))).resolve(); embedded = expansion_package.verify(archive_path)
            if embedded["expansion_id"] != expansion_id or embedded["version"] != version or not embedded.get("redistribution_permitted"):
                raise PackageError(f"embedded expansion is incompatible or not redistributable: {expansion_id}@{version}")
            archive_name = f"expansions/{expansion_id}-{version}.expansion"
            record.update({"embedded_path": archive_name, "path": archive_name, "size": archive_path.stat().st_size, "sha256": digest_file(archive_path)})
            embedded_archives.append((archive_path, archive_name))
        expansion_records.append(record)
    resolution = json.dumps({"capabilities": capabilities, "expansions": expansion_records}, sort_keys=True, separators=(",", ":")).encode()
    manifest = {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "story_id": story["id"],
        "title": story["title"],
        "author": config["author"],
        "description": config["description"],
        "content_version": str(config["content_version"]),
        "capabilities": [{"id": str(item.get("id", "")), "version": str(item.get("version", ""))} for item in capabilities],
        "expansions": expansion_records,
        "resolved_content_identity": hashlib.sha256(resolution).hexdigest(),
        "entrypoints": {"story": config["story"], "level": config.get("level", "")},
        "thumbnail": config.get("thumbnail", ""),
        "validation": {"required_invariants_proven": False, "coverage_complete": False, "incomplete_acknowledged": True},
        "files": [{"path": name, "size": source.stat().st_size, "sha256": digest_file(source)} for source, name in files],
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    try:
        with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            deterministic_zip_write(archive, MANIFEST, json.dumps(manifest, indent=2, sort_keys=True) + "\n")
            for source, name in files:
                deterministic_zip_write(archive, f"content/{name}", source.read_bytes())
            for source, name in embedded_archives:
                deterministic_zip_write(archive, name, source.read_bytes())
        verify(temporary)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Exported {story['title']} {config['content_version']} to {output}")


def library_path() -> Path:
    if sys.platform == "darwin":
        return Path.home() / "Library/Application Support/Zelda's Storytelling Game/Stories"
    if os.name == "nt":
        return Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Zelda's Storytelling Game/Stories"
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "zeldas-storytelling-game/Stories"


def install(args: argparse.Namespace) -> None:
    manifest = verify(args.package.resolve())
    root = args.library.resolve(); expansions_root = root.parent / "Expansions"
    destination = root / manifest["story_id"] / manifest["content_version"]
    if destination.exists() and not args.replace:
        raise PackageError(f"story version is already installed: {destination}")
    installed_expansions = {(item["expansion_id"], item["version"]): path for path, item in expansion_package.installed_manifests(expansions_root)}
    enabled = expansion_package.profile_read(expansions_root)
    for requirement in manifest["expansions"]:
        key = (requirement["id"], requirement["version"]); expansion_identity = f"{key[0]}@{key[1]}"
        if requirement["distribution"] == "reference" and key not in installed_expansions and not requirement.get("optional"):
            raise PackageError(f"required expansion is not installed: {expansion_identity}")
        if key in installed_expansions and expansion_identity not in enabled and not requirement.get("optional"):
            raise PackageError(f"required expansion is disabled: {expansion_identity}")
    root.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="story-install-", dir=root))
    installed_during_transaction: list[Path] = []
    backup = destination.with_name(destination.name + ".replace-backup")
    committed = False
    try:
        with zipfile.ZipFile(args.package.resolve()) as archive:
            for requirement in manifest["expansions"]:
                if requirement["distribution"] != "embed" or (requirement["id"], requirement["version"]) in installed_expansions:
                    continue
                with tempfile.NamedTemporaryFile(suffix=".expansion", delete=False) as temporary_expansion:
                    temporary_expansion.write(archive.read(requirement["embedded_path"])); expansion_path = Path(temporary_expansion.name)
                try:
                    installed_during_transaction.append(
                        expansion_package.install_archive(expansion_path, expansions_root, False, args.engine_version)
                    )
                finally:
                    expansion_path.unlink(missing_ok=True)
            for record in manifest["files"]:
                source = f"content/{record['path']}"
                target = staging.joinpath(*safe_relative(record["path"]).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                with archive.open(source) as incoming, target.open("wb") as outgoing:
                    shutil.copyfileobj(incoming, outgoing)
        (staging / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        story_path = (destination / safe_relative(manifest["entrypoints"]["story"])).resolve()
        level_entry = manifest["entrypoints"].get("level", ""); level_path = (destination / safe_relative(level_entry)).resolve() if level_entry else Path("")
        campaign_text = (
            'version = "MysteryCampaign v2"\n'
            f'id = "story-{manifest["story_id"]}"\n'
            f'title = {json.dumps(manifest["title"])}\ncreator = {json.dumps(manifest["author"])}\n'
            f'description = {json.dumps(manifest["description"])}\ncontent_version = {json.dumps(manifest["content_version"])}\nthumbnail = ""\n\n'
            '[[cases]]\n'
            f'id = {json.dumps(manifest["story_id"])}\ntitle = {json.dumps(manifest["title"])}\n'
            f'story_path = {json.dumps(str(story_path))}\nlevel_path = {json.dumps(str(level_path) if level_entry else "")}\n'
            f'content_version = {json.dumps(manifest["content_version"])}\nrequired = true\noptional = false\n'
        )
        (staging / "standalone-campaign.toml").write_text(campaign_text, encoding="utf-8")
        if destination.exists():
            if backup.exists():
                shutil.rmtree(backup)
            os.replace(destination, backup)
        destination.parent.mkdir(parents=True, exist_ok=True)
        try:
            os.replace(staging, destination)
        except BaseException:
            if backup.exists():
                os.replace(backup, destination)
            raise
        committed = True
        shutil.rmtree(backup, ignore_errors=True)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
        if not committed:
            for installed in reversed(installed_during_transaction):
                shutil.rmtree(installed, ignore_errors=True)
            if backup.exists() and not destination.exists():
                os.replace(backup, destination)
    print(destination)


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    export_parser = sub.add_parser("export")
    export_parser.add_argument("output", type=Path)
    export_parser.add_argument("--root", type=Path, default=Path.cwd())
    export_parser.add_argument("--config", type=Path, default=Path("story.package.json"))
    export_parser.add_argument("--validator", type=Path, default=Path("build/chicago"))
    export_parser.add_argument("--skip-engine-validation", action="store_true")
    inspect_parser = sub.add_parser("inspect")
    inspect_parser.add_argument("package", type=Path)
    install_parser = sub.add_parser("install")
    install_parser.add_argument("package", type=Path)
    install_parser.add_argument("--library", type=Path, default=library_path())
    install_parser.add_argument("--replace", action="store_true")
    install_parser.add_argument("--engine-version", default="1.0.0")
    args = parser.parse_args()
    if args.command == "export":
        export(args)
    elif args.command == "inspect":
        print(json.dumps(verify(args.package.resolve()), indent=2, sort_keys=True))
    else:
        install(args)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PackageError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
