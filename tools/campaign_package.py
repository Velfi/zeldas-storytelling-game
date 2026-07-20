#!/usr/bin/env python3
"""Export, verify, and install portable campaign archives with pinned cases."""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import sys
import tempfile
import tomllib
import zipfile

import interactive_story_package as story_package

FORMAT = "ChicagoMysteryCampaign"
FORMAT_VERSION = 1
MANIFEST = "campaign-manifest.json"
MAX_FILES = 512
MAX_BYTES = 2 * 1024 * 1024 * 1024
FIXED_TIME = (1980, 1, 1, 0, 0, 0)


class CampaignPackageError(Exception):
    pass


def safe_name(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or "\\" in name or path.is_absolute() or ".." in path.parts:
        raise CampaignPackageError(f"unsafe archive path: {name!r}")
    if path.parts[0] not in {"content", "cases"}:
        raise CampaignPackageError(f"unexpected archive path: {name!r}")
    return path


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024):
            value.update(block)
    return value.hexdigest()


def write_deterministic(archive: zipfile.ZipFile, name: str, data: bytes) -> None:
    info = zipfile.ZipInfo(name, FIXED_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data, compresslevel=6)


def load_config(path: Path) -> tuple[dict, dict]:
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        document_path = path.parent / config["campaign"]
        document = tomllib.loads(document_path.read_text(encoding="utf-8"))
    except (OSError, KeyError, ValueError, tomllib.TOMLDecodeError) as error:
        raise CampaignPackageError(f"cannot read campaign config: {error}") from error
    for key in ("campaign", "author", "description", "content_version", "cases"):
        if not config.get(key):
            raise CampaignPackageError(f"campaign config is missing {key}")
    if document.get("version") != "MysteryCampaign v2" or not document.get("id") or not document.get("title"):
        raise CampaignPackageError("campaign document requires MysteryCampaign v2, id, and title")
    if str(document.get("content_version", "")) != str(config["content_version"]):
        raise CampaignPackageError("campaign document and package content versions differ")
    return config, document


def export_campaign(args: argparse.Namespace) -> None:
    config_path = args.config.resolve()
    config, document = load_config(config_path)
    root = config_path.parent
    document_path = (root / config["campaign"]).resolve()
    cases = []
    external_cases = []
    seen = set()
    for configured in config["cases"]:
        if isinstance(configured, dict) and configured.get("external"):
            identity = (str(configured.get("id", "")), str(configured.get("content_version", "")))
            if not all(identity):
                raise CampaignPackageError("external case requires id and content_version")
            if identity in seen:
                raise CampaignPackageError(f"duplicate case pin {identity[0]} {identity[1]}")
            seen.add(identity)
            external_cases.append(identity)
            continue
        if not isinstance(configured, str):
            raise CampaignPackageError("embedded cases must be paths and external cases must be objects")
        story_archive = (root / configured).resolve()
        try:
            case_manifest = story_package.verify(story_archive)
        except story_package.PackageError as error:
            raise CampaignPackageError(f"invalid embedded case {configured}: {error}") from error
        identity = (case_manifest["story_id"], case_manifest["content_version"])
        if identity in seen:
            raise CampaignPackageError(f"duplicate embedded case {identity[0]} {identity[1]}")
        seen.add(identity)
        cases.append((story_archive, case_manifest))
    declared = {(item.get("id"), str(item.get("content_version", ""))) for item in document.get("cases", [])}
    packaged = {(manifest["story_id"], manifest["content_version"]) for _, manifest in cases} | set(external_cases)
    if declared != packaged:
        raise CampaignPackageError("campaign case pins do not match embedded and external case declarations")
    campaign_bytes = document_path.read_bytes()
    thumbnail_record = None
    thumbnail_path = None
    authored_thumbnail = str(document.get("thumbnail", "")).strip()
    if authored_thumbnail:
        thumbnail_path = (root / authored_thumbnail).resolve()
        if not thumbnail_path.is_file():
            raise CampaignPackageError(f"campaign thumbnail does not exist: {authored_thumbnail}")
        thumbnail_record = {
            "path": f"content/campaign-thumbnail{thumbnail_path.suffix.lower()}",
            "size": thumbnail_path.stat().st_size,
            "sha256": digest(thumbnail_path),
        }
    case_records = [
        {
            "story_id": manifest["story_id"],
            "content_version": manifest["content_version"],
            "path": f"cases/{manifest['story_id']}-{manifest['content_version']}.interactive-story",
            "size": path.stat().st_size,
            "sha256": digest(path),
        }
        for path, manifest in sorted(cases, key=lambda pair: (pair[1]["story_id"], pair[1]["content_version"]))
    ]
    case_records.extend({"story_id": story_id, "content_version": version, "external": True}
                        for story_id, version in sorted(external_cases))
    expansion_records: dict[tuple[str, str], dict] = {}
    for _, case_manifest in cases:
        for requirement in case_manifest.get("expansions", []):
            key = (str(requirement.get("id", "")), str(requirement.get("version", "")))
            if key in expansion_records and expansion_records[key].get("sha256") != requirement.get("sha256"):
                raise CampaignPackageError(f"campaign cases resolve {key[0]} {key[1]} to different expansion content")
            expansion_records[key] = {name: requirement[name] for name in ("id", "version", "optional", "distribution", "fallback", "sha256") if name in requirement}
    manifest = {
        "format": FORMAT,
        "format_version": FORMAT_VERSION,
        "campaign_id": document["id"],
        "title": document["title"],
        "author": config["author"],
        "description": config["description"],
        "content_version": str(config["content_version"]),
        "campaign_document": "content/campaign.toml",
        "campaign_sha256": hashlib.sha256(campaign_bytes).hexdigest(),
        "thumbnail": thumbnail_record,
        "cases": case_records,
        "expansions": [expansion_records[key] for key in sorted(expansion_records)],
    }
    output = args.output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    try:
        with zipfile.ZipFile(temporary, "w") as archive:
            write_deterministic(archive, MANIFEST, (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode())
            write_deterministic(archive, "content/campaign.toml", campaign_bytes)
            if thumbnail_record and thumbnail_path:
                write_deterministic(archive, thumbnail_record["path"], thumbnail_path.read_bytes())
            by_identity = {(item["story_id"], item["content_version"]): item for item in case_records if not item.get("external")}
            for path, case_manifest in sorted(cases, key=lambda pair: (pair[1]["story_id"], pair[1]["content_version"])):
                record = by_identity[(case_manifest["story_id"], case_manifest["content_version"])]
                write_deterministic(archive, record["path"], path.read_bytes())
        verify_campaign(temporary)
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    print(f"Exported {document['title']} {config['content_version']} to {output}")


def inspect_campaign(path: Path) -> tuple[dict, zipfile.ZipFile]:
    try:
        archive = zipfile.ZipFile(path)
        infos = archive.infolist()
        if len(infos) > MAX_FILES or len({item.filename for item in infos}) != len(infos):
            raise CampaignPackageError("campaign archive has too many or duplicate entries")
        if sum(item.file_size for item in infos) > MAX_BYTES:
            raise CampaignPackageError("campaign archive exceeds its size limit")
        for item in infos:
            if item.filename != MANIFEST:
                safe_name(item.filename)
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise CampaignPackageError("campaign archive contains a symbolic link")
        manifest = json.loads(archive.read(MANIFEST))
        if manifest.get("format") != FORMAT or manifest.get("format_version") != FORMAT_VERSION:
            raise CampaignPackageError("unsupported campaign package format")
        for key in ("campaign_id", "title", "author", "description", "content_version", "campaign_document", "campaign_sha256", "cases"):
            if key not in manifest:
                raise CampaignPackageError(f"campaign manifest is missing {key}")
        identity = manifest["campaign_id"] + manifest["content_version"]
        if not identity or any(not (c.isalnum() or c in "-._") for c in identity):
            raise CampaignPackageError("campaign identity is not filesystem-safe")
        expected = {MANIFEST, manifest["campaign_document"]}
        if manifest.get("thumbnail"):
            safe_name(manifest["thumbnail"]["path"])
            expected.add(manifest["thumbnail"]["path"])
        for record in manifest["cases"]:
            if record.get("external"):
                if not record.get("story_id") or not record.get("content_version"):
                    raise CampaignPackageError("external case identity is incomplete")
                continue
            safe_name(record["path"])
            expected.add(record["path"])
        if set(archive.namelist()) != expected:
            raise CampaignPackageError("campaign archive contents do not match its manifest")
        return manifest, archive
    except (OSError, KeyError, ValueError, zipfile.BadZipFile, json.JSONDecodeError) as error:
        raise CampaignPackageError(f"invalid campaign package: {error}") from error


def verify_campaign(path: Path) -> dict:
    manifest, archive = inspect_campaign(path)
    try:
        campaign_data = archive.read(manifest["campaign_document"])
        if hashlib.sha256(campaign_data).hexdigest() != manifest["campaign_sha256"]:
            raise CampaignPackageError("campaign document integrity check failed")
        thumbnail = manifest.get("thumbnail")
        if thumbnail:
            thumbnail_data = archive.read(thumbnail["path"])
            if len(thumbnail_data) != thumbnail["size"] or hashlib.sha256(thumbnail_data).hexdigest() != thumbnail["sha256"]:
                raise CampaignPackageError("campaign thumbnail integrity check failed")
        document = tomllib.loads(campaign_data.decode())
        if document.get("id") != manifest["campaign_id"] or str(document.get("content_version", "")) != manifest["content_version"]:
            raise CampaignPackageError("campaign document identity does not match manifest")
        for record in manifest["cases"]:
            if record.get("external"):
                continue
            data = archive.read(record["path"])
            if len(data) != record["size"] or hashlib.sha256(data).hexdigest() != record["sha256"]:
                raise CampaignPackageError(f"embedded case integrity check failed: {record['path']}")
            with tempfile.NamedTemporaryFile(suffix=".interactive-story") as temporary:
                temporary.write(data)
                temporary.flush()
                nested = story_package.verify(Path(temporary.name))
            if nested["story_id"] != record["story_id"] or nested["content_version"] != record["content_version"]:
                raise CampaignPackageError("embedded case identity does not match campaign manifest")
    finally:
        archive.close()
    return manifest


def library_path() -> Path:
    return story_package.library_path().parent / "Campaigns"


def materialize_runtime(staging: Path, destination: Path, campaign_data: bytes, manifest: dict, archive: zipfile.ZipFile, library: Path) -> None:
    """Build the verified, player-readable view consumed by the native browser."""
    document = tomllib.loads(campaign_data.decode("utf-8"))
    installed_cases: dict[tuple[str, str], dict[str, Path]] = {}
    for record in manifest["cases"]:
        if record.get("external"):
            case_root = library / record["story_id"] / record["content_version"]
            marker = case_root / story_package.MANIFEST
            if not marker.is_file():
                raise CampaignPackageError(f"external case is not installed: {record['story_id']} {record['content_version']}")
            nested_manifest = json.loads(marker.read_text(encoding="utf-8"))
            if nested_manifest.get("story_id") != record["story_id"] or nested_manifest.get("content_version") != record["content_version"]:
                raise CampaignPackageError("installed external case identity does not match its pin")
            installed_cases[(record["story_id"], record["content_version"])] = {
                key: (case_root / value).resolve() for key, value in nested_manifest["entrypoints"].items()
            }
            continue
        payload = archive.read(record["path"])
        with zipfile.ZipFile(io.BytesIO(payload)) as nested:
            nested_manifest = json.loads(nested.read(story_package.MANIFEST))
            relative_root = Path("runtime") / "cases" / record["story_id"] / record["content_version"]
            case_root = staging / relative_root
            for file_record in nested_manifest["files"]:
                relative = PurePosixPath(file_record["path"])
                target = case_root.joinpath(*relative.parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(nested.read(f"content/{file_record['path']}"))
            installed_cases[(record["story_id"], record["content_version"])] = {
                key: (destination / relative_root / value).resolve()
                for key, value in nested_manifest["entrypoints"].items()
            }

    case_order = document.get("cases", [])
    case_index = -1
    rewritten: list[str] = []
    runtime_thumbnail = ""
    if manifest.get("thumbnail"):
        source = manifest["thumbnail"]["path"]
        suffix = Path(source).suffix.lower()
        runtime_thumbnail = str((destination / "runtime" / f"campaign-thumbnail{suffix}").resolve())
        target = staging / "runtime" / f"campaign-thumbnail{suffix}"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(archive.read(source))
    for line in campaign_data.decode("utf-8").splitlines():
        stripped = line.strip()
        if case_index < 0 and runtime_thumbnail and (stripped.startswith("thumbnail ") or stripped.startswith("thumbnail=")):
            value = runtime_thumbnail.replace("\\", "\\\\").replace('"', '\\"')
            line = f'thumbnail = "{value}"'
        if stripped == "[[cases]]":
            case_index += 1
        if 0 <= case_index < len(case_order):
            item = case_order[case_index]
            entrypoints = installed_cases.get((item.get("id"), str(item.get("content_version", ""))))
            if entrypoints:
                field = next((name for name in ("story_path", "level_path") if stripped.startswith(name + " ") or stripped.startswith(name + "=")), None)
                if field:
                    source = {"story_path": "story", "level_path": "level"}[field]
                    value = str(entrypoints[source]).replace("\\", "\\\\").replace('"', '\\"')
                    line = f'{field} = "{value}"'
        rewritten.append(line)
    runtime = staging / "runtime"
    runtime.mkdir(parents=True, exist_ok=True)
    (runtime / "campaign.toml").write_text("\n".join(rewritten) + "\n", encoding="utf-8")


def import_campaign(args: argparse.Namespace) -> None:
    package = args.package.resolve()
    manifest = verify_campaign(package)
    library = (args.library or library_path()).resolve()
    destination = library / manifest["campaign_id"] / manifest["content_version"]
    if destination.exists():
        marker = destination / MANIFEST
        if marker.is_file() and json.loads(marker.read_text()) == manifest:
            print(f"Already installed: {destination}")
            return
        raise CampaignPackageError(f"version conflict at {destination}; install a different version")
    destination.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=".campaign-install-", dir=destination.parent))
    try:
        checked, archive = inspect_campaign(package)
        try:
            for name in archive.namelist():
                if name == MANIFEST:
                    continue
                target = staging.joinpath(*PurePosixPath(name).parts)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))
            materialize_runtime(staging, destination, archive.read(checked["campaign_document"]), checked, archive, library)
            (staging / MANIFEST).write_text(json.dumps(checked, indent=2, sort_keys=True) + "\n")
        finally:
            archive.close()
        os.replace(staging, destination)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f"Installed {manifest['title']} {manifest['content_version']} at {destination}")


def show_campaign(args: argparse.Namespace) -> None:
    manifest = verify_campaign(args.package.resolve())
    print(json.dumps(manifest, indent=2, sort_keys=True))


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    commands = result.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export")
    export.add_argument("output", type=Path)
    export.add_argument("--config", type=Path, default=Path("campaign.package.json"))
    export.set_defaults(run=export_campaign)
    inspect = commands.add_parser("inspect")
    inspect.add_argument("package", type=Path)
    inspect.set_defaults(run=show_campaign)
    install = commands.add_parser("import")
    install.add_argument("package", type=Path)
    install.add_argument("--library", type=Path)
    install.set_defaults(run=import_campaign)
    return result


def main() -> int:
    try:
        args = parser().parse_args()
        args.run(args)
        return 0
    except (CampaignPackageError, story_package.PackageError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
