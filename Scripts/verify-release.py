#!/usr/bin/env python3
"""Check release assets and privacy boundaries using only the standard library."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import zipfile


def verify(archive, version):
    if not __debug__:
        raise RuntimeError("Release verification must not run with Python optimization enabled")
    repo = Path(__file__).resolve().parent.parent
    pets = {"whisky", "cling", "whisky-ink", "cling-ink", "whisky-color", "cling-color"}
    private_files = {"settings.json", "pets.json", "personal-vocabulary.json", "learning-progress.json",
                     "browser-pairing-token", "example-translations.json", "learning-progress.pre-fsrs.json"}
    private_content = re.compile(rb"/Users/[A-Za-z0-9._-]+/|wxid_|-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----|sk-[A-Za-z0-9_-]{20,}|github_pat_[A-Za-z0-9_]{20,}")
    with zipfile.ZipFile(archive) as package:
        assert package.testzip() is None, "Archive CRC failed"
        files = [i for i in package.infolist() if not i.is_dir() and not i.filename.startswith("__MACOSX/")]
        def decoded_name(item):
            if item.flag_bits & 0x800:
                return item.filename
            # macOS ditto writes UTF-8 entry bytes without setting ZIP's UTF-8 flag.
            try:
                return item.filename.encode("cp437").decode("utf-8")
            except UnicodeError:
                return item.filename

        members = {decoded_name(i): i for i in files}
        assert len(members) == len(files), "Duplicate archive entries"
        roots = {PurePosixPath(name).parts[0] for name in members}
        assert len(roots) == 1, "Expected one release directory"
        root = next(iter(roots))
        assert root == f"whiskycolin-v{version}-macos-arm64", "Directory/version mismatch"
        for item in files:
            name = PurePosixPath(decoded_name(item))
            assert not name.is_absolute() and ".." not in name.parts, "Unsafe archive entry"
            assert name.name not in private_files, f"Private runtime file included: {name.name}"
            assert item.file_size < 100_000_000, "Oversized archive entry"
            assert not private_content.search(package.read(item)), f"Potential private content in {name.name}"

        def read(relative):
            return package.read(members[f"{root}/{relative}"])

        app = "Whisky&Cling.app/Contents"
        info = plistlib.loads(read(f"{app}/Info.plist"))
        assert info["CFBundleShortVersionString"] == version, "App version mismatch"
        binary = read(f"{app}/MacOS/whiskycolin")
        assert binary[:4] == b"\xcf\xfa\xed\xfe" and struct.unpack_from("<I", binary, 4)[0] == 0x0100000C, "Expected arm64 Mach-O"
        resources = f"{app}/Resources/CodexDesktopPet_CodexPetApp.bundle"
        for pet in sorted(pets):
            base = f"{resources}/Pets/{pet}"
            manifest = json.loads(read(f"{base}/pet.json"))
            assert manifest["id"] == pet, "Pet identifier mismatch"
            sprite = manifest["spritesheetPath"]
            assert PurePosixPath(sprite).name == sprite, "Unsafe sprite path"
            assert read(f"{base}/{sprite}") == (repo / "Sources/CodexPetApp/Resources/Pets" / pet / sprite).read_bytes(), f"Missing or stale sprite: {pet}"
        dictionary_bytes = read(f"{resources}/雅思高频单词.json")
        assert dictionary_bytes == (repo / "Sources/CodexPetApp/Resources/Dictionaries/雅思高频单词.json").read_bytes(), "Stale dictionary"
        dictionary = json.loads(dictionary_bytes)
        assert dictionary["name"] == "雅思高频单词" and len(dictionary["entries"]) == 3674, "Vocabulary count mismatch"
        assert all(e.get("term") and e.get("meaning") and e.get("phonetic") for e in dictionary["entries"]), "Incomplete vocabulary fields"
        assert read(f"{resources}/Themes/storybook-duo.png") == (repo / "Sources/CodexPetApp/Resources/Themes/storybook-duo.png").read_bytes(), "Missing theme artwork"
        for base in ("ChromeExtension", f"{app}/Resources/ChromeExtension"):
            assert json.loads(read(f"{base}/manifest.json"))["version"] == version, "Extension version mismatch"
            for name in ("manifest.json", "content.js", "capture.html", "capture.js", "client.js", "parse.js", "style.css", "background.js", "icon.png"):
                assert read(f"{base}/{name}") == (repo / "ChromeExtension" / name).read_bytes(), f"Stale extension: {name}"
        for name in ("bin/petctl", "Scripts/install-codex-skill.sh", "skills/codex-desktop-pet/SKILL.md", "README.md", "INSTALL.md"):
            assert read(name), f"Missing release file: {name}"
        notices = (repo / "THIRD_PARTY_NOTICES.md").read_bytes()
        assert read("THIRD_PARTY_NOTICES.md") == notices, "Missing dependency notice in release"
        assert read(f"{app}/Resources/THIRD_PARTY_NOTICES.md") == notices, "Missing dependency notice in app"
        upstream_license = (repo / ".build/checkouts/swift-fsrs/LICENSE").read_text().strip()
        assert upstream_license in notices.decode(), "Incomplete swift-fsrs MIT notice"
    return {"version": version, "platform": "macOS 14+ arm64", "pets": sorted(pets),
            "dictionary": dictionary["name"], "wordCount": len(dictionary["entries"]),
            "extensionVersion": version, "privacyScan": "passed", "personalDataIncluded": False,
            "sha256": hashlib.sha256(Path(archive).read_bytes()).hexdigest(), "signing": "ad-hoc, not notarized"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive")
    parser.add_argument("--version", required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.archive, args.version.removeprefix("v")), ensure_ascii=False, indent=2))
