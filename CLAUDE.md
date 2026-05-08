# VideoMaster — Claude Instructions

## Building and deploying

After every code change, run the build-and-install script:

```bash
bash scripts/build_and_install.sh
```

This script:
1. Bumps `CURRENT_PROJECT_VERSION` in `project.yml`
2. Regenerates the Xcode project via `xcodegen`
3. Builds a Release build
4. Installs the app to `/Applications/VideoMaster.app`
5. Cleans up the temp build log

After the script completes, announce the new build number to the user (printed on the last line of script output, e.g. `✓ VideoMaster 0.8.1 (282) [Release]`).
