# Patches

Your own changes to code this repo pulls in but does not own, such as the cleanyourtv launcher. Patches are **personal**:
everything in this folder except this README is git-ignored, so each person keeps their own and nothing here is shared.
The tools apply them to a fresh copy at build time. The submodules themselves are never edited.

| Folder | Applies to | Applied by |
|---|---|---|
| `launcher/` | the cleanyourtv launcher (`upstream/cleanyourtv/launcher`) | `tools/install-launcher.sh`, after copying the launcher and the device's `config.xml` into `build/launcher` |

`tools/install-launcher.sh` applies every `patches/launcher/*.patch` in name order with `patch -p1` (paths relative to
`launcher/`). If a patch no longer applies, for example after a submodule update, the install stops and names it.
Two patches may touch the same file. A later patch's hunks then land at an offset, which is fine as long as the context
still matches. With no patches the launcher builds exactly as upstream ships it.

If a patch declares `<uses-permission android:name="android.permission.WRITE_SECURE_SETTINGS" />`, the install grants it with
`pm grant` (only adb can). Some TV Settings screens refuse apps without it. It also lets the launcher change any secure or
global setting, so declare it only when a patch needs it.

## Making a patch

```sh
cp -R upstream/cleanyourtv/launcher /tmp/launcher-dev && cd /tmp/launcher-dev
git init -q && git add -A && git commit -qm upstream
# edit, build and test here (put sdk.dir in local.properties, which git should ignore)
git add -A && git diff --cached HEAD -- . ':!local.properties' > <repo>/patches/launcher/<feature>.patch
```

To refresh a patch after a submodule update, repeat this with the new upstream: apply the old patch
(`patch -p1 < <repo>/patches/launcher/<feature>.patch`), fix what fails, and write the diff again.

## Rules

- **One feature per patch**, named for what it adds (`remote-buttons.patch`). Prefix a number if one depends on another.
- **Per-device settings do not belong here.** They go in `devices/<model>/config.xml`. A patch changes the launcher's
  behaviour, not one projector's setup.
- **Keep a note next to your patches** (for example `launcher/README.md`, also ignored) saying what each one adds.
- **Send what others would want upstream.** A patch that upstream accepts can be deleted here.
