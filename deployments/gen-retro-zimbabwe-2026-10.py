# Generator for the zimbabwe-2026-10 retro records (idea#322); rerun after editing. Not a runtime tool.
import os, shutil, sys
D = os.path.dirname(os.path.abspath(__file__)); REPO = os.path.dirname(D)
CLIENT_SUMS = sys.argv[1] if len(sys.argv) > 1 else "PENDING"
HDR = ["# RETRO record (idea#322), written 2026-10-26 from box evidence (card-log.md, build logs). Not captured on the device.",
       "# UNKNOWN = not recoverable from the box; fill in with tools/repro/capture-device.sh when the device is next online.",
       "schema=idea-deployment-record/1"]
S15M = "manifests/client/idea-client-26.04-20261017-291b962-s15"
B2M = "manifests/router/idea-router-0.1.0-dev-b2f00bc-cudy_wr3000s-v1"
CA = "/workspace/idea-archive/release-assets/field-zimbabwe-2026-10-client-291b962"
client_common = dict(batch="zimbabwe-2026-10", deviceType="client", arch="aarch64",
  model="UNKNOWN (Raspberry Pi classroom client, SD card)", osRelease="Ubuntu 26.04.1 preinstalled desktop arm64+raspi",
  baseImageSha256="8216f54cc1df2fcf7de37530a7edccdd200abd7dcfbc5d4f0407df7513544d6a",
  chromeDebSha256="245fa8da4a52c15bee7811d3e17892792cabd6361ac5b7e9c78ba6482ad18315",
  aptPins="tools/client-image/apt-pins.tsv (build input); installed list = packages.tsv",
  packageArchive=f"{CA} (box; .deb tars + SHA256SUMS + missing-packages.tsv)",
  packageArchiveSha256=f"{CLIENT_SUMS} (sha256 of SHA256SUMS)",
  packageArchiveUrl="not published yet (Koen 2026-10-26); planned: koenswings/idea release field/zimbabwe-2026-10/client-s15",
  secrets="flash-time Wi-Fi PSK (name only; value never recorded)",
  evidence="/workspace/client-card-patch/card-log.md (box, sha256 4b7b93a479573ff661b73ac54c850539b235420ed54ff544373fe9a8e952db23)")
S14 = dict(imageCommit="f00748eb (tag field/zimbabwe-2026-10/client-s14; branch feat/client-image-build, not on main)",
  imageBranch="feat/client-image-build", imageTag="field/zimbabwe-2026-10/client-s14", imageVersion="26.04-20261016-f00748e",
  imageFile="idea-client-26.04-20261016-f00748e-s14.img (psk-patched; box copy gone, contained the Wi-Fi PSK, never publish)",
  imageSha256="54e6b2d0bfaa52f23114004da94718e6d6dba9daea616a77302e0fea627c5ace (raw); xz 1f1641cff062325c0575de6f0157e4444e5202c17df42df9649dc8ae4769f4d2",
  imageManifest=f"UNKNOWN (no s14 manifest; installed package list identical to s15 per build-20261017-121651.log, so packages.tsv = {S15M}/packages.tsv)",
  contentSha256="UNKNOWN",
  **{"postInstall.cardpatch":"2026-10-17 on wh: tools/client-image/field/patch-client-cards.sh (original sha256 82ada65ec84fef6cdb4882a80f36c9c9932b744251d9d0d38c3377e6525dbf57; committed copy is sanitised) PASS: keyboard us, Chrome NewTabPageLocation removed, Engine META.yaml removed, Wi-Fi PSK checked by hash"},
  confidence="high: card-log.md lists this card as PASS")
S15 = dict(imageCommit="291b96253d407f21bf38091e92128bf2149fc974", imageBranch="main", imageTag="field/zimbabwe-2026-10/client-s15",
  imageVersion="26.04-20261017-291b962", imageFile="idea-client-26.04-20261017-291b962-s15.img.xz (published: https://github.com/koenswings/idea/releases/tag/field/zimbabwe-2026-10/client-s15 as .part00-.part09 + IMAGE.SHA256SUMS; cat parts > .img.xz; default credentials only)",
  imageSha256="dd6f6d408a16cdb614d090b02bd771634eb4a74beaeb774a674dc332333ffa6c (xz)",
  readBackSha256="6cadd6b295ced889c96a894e6d3c5e7358037d2fd377a1c7a21ed695303fa353 (13999996928 bytes)",
  imageManifest=S15M, contentSha256="0746a2def620716adca0a9ec7213438945f73d7067700292b73c2f7866d56da8",
  confidence="high: card-log.md records the reflash and read-back hash")
cards = [(c, "s14", None) for c in ["8nbzz084u0myiktx8cp","9qqttxdncddatorix8h","ivuhrvg10resw5xcde1","orx0hdq4po36orzp1dl","b5d5j51g3aebdmop51z","tvkj9ikz9jvr6w25liu"]]
cards += [("reflash-1-pmx6b5vpzn62cmaeygi","s15","pmx6b5vpzn62cmaeygi (wrong psk before reflash)"),("reflash-2-v55frduh38x3ko0zszt","s15","v55frduh38x3ko0zszt")]
def write(rel, kv, pk):
    d = os.path.join(D, rel); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "record.txt"), "w").write("\n".join(HDR + [f"{k}={v}" for k, v in kv.items()]) + "\n")
    shutil.copy(os.path.join(REPO, pk), os.path.join(d, "packages.tsv"))
for name, img, prev in cards:
    kv = dict(client_common); kv["cardId"] = name if prev is None else "UNKNOWN (new card)"
    if prev: kv["previousCardId"] = prev
    kv["deployedAt"] = "2026-10-17 (wh)"; kv.update(S14 if img == "s14" else S15)
    kv["open"] = "confirm with tools/repro/capture-device.sh" + ("; s14 packages.tsv is inferred from s15" if img == "s14" else "")
    write(f"clients/{name}/retro-2026-10-17", kv, f"{S15M}/packages.tsv")
RA = "https://github.com/koenswings/idea/releases/download/field/zimbabwe-2026-10/router-b2f00bc"
for r in ["sunny-robin", "happy-zebra", "kind-panda"]:
    kv = dict(batch="zimbabwe-2026-10", deviceType="router", hostname=f"{r}-router", stickerName=r, arch="aarch64",
      model="Cudy WR3000S v1", osRelease="OpenWrt 25.12.5 (mediatek/filogic)",
      imageCommit="b2f00bcf (tag field/zimbabwe-2026-10/router-b2f00bc; #271 head, squash-merged, not on main)",
      imageBranch="fix/router-image-dnsmasq-local-teachers-off", imageTag="field/zimbabwe-2026-10/router-b2f00bc", imageVersion="0.1.0-dev-b2f00bc",
      setupRef="7eedd03",
      imageFile="idea-router-0.1.0-dev-b2f00bc-cudy_wr3000s-v1-squashfs-sysupgrade.bin (published: https://github.com/koenswings/idea/releases/download/field/zimbabwe-2026-10/router-b2f00bc/idea-router-0.1.0-dev-b2f00bc-cudy_wr3000s-v1-squashfs-sysupgrade.bin, listed in release SHA256SUMS; default credentials only)",
      imageSha256="8e084dc0d891f8141277f0f152307a12c2cc6f13759e561a659232b9cc1ace61",
      imageManifest=B2M, contentSha256="dee4275a665ae4865dc326ba16ae0d427779aaf359e6101ad2425489875ebc4f",
      imageBuilder=f"{RA}/openwrt-imagebuilder-25.12.5-mediatek-filogic.Linux-x86_64.tar.zst sha256 7fb6cf626582ebcbfb46974da48c1eae577213f38879eaf6b1d982041e843461 (upstream https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/)",
      cudyIntermediate=f"{RA}/cudy_wr3000s-v1-sysupgrade_20251119.bin sha256 463e6e31e7361ec8177d2c3a136674297fd179eafaa166fe459731cdf1b35773 (Cudy source URL UNKNOWN)",
      packageArchive="/workspace/idea-archive/router/b2f00bc-openwrt-25.12.5/apk (box, SHA256SUMS); release asset router-b2f00bc-apk.tar",
      packageArchiveSha256="4da39be3d91056250862e5c68184b21b129adc783f52f95bad7112fa01b52ffe (router-b2f00bc-apk.tar); box SHA256SUMS 8b0056776b9ddc8e2a16faa621c67dedc979076c07951d82aa37a58f8e0a8f86",
      packageArchiveUrl=f"{RA}/router-b2f00bc-apk.tar (release SHA256SUMS: {RA}/SHA256SUMS)",
      rebuildCheck="2026-10-26: offline rebuild from the archived apks is byte-identical (8e084dc0...)",
      secrets="baked default root password in this image (value not recorded); Tailscale key at enrol time",
      deployedAt="UNKNOWN (#271, before 2026-10-18)", evidence="router-fix-out/SHA256SUMS (box) lists only b2f00bc; #271",
      confidence="likely: only kit-era build on the box; not captured on a device", open="confirm with tools/repro/capture-device.sh")
    write(f"routers/{r}/retro-2026-10-18", kv, f"{B2M}/packages.tsv")
