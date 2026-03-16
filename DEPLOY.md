# Deploy

## Prerequisites

- Xcode (`/Applications/Xcode.app`)
- `codesign`, `hdiutil` (macOS built-in)

## Build

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -scheme TokenGarden -destination 'platform=macOS' \
  -derivedDataPath .claude/tmp/DerivedData \
  -configuration Release build
```

## Package

```bash
# 1. Copy binary
cp .claude/tmp/DerivedData/Build/Products/Release/TokenGarden \
   build/TokenGarden.app/Contents/MacOS/TokenGarden

# 2. Bump version (Info.plist)
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString X.Y.Z" build/TokenGarden.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion N" build/TokenGarden.app/Contents/Info.plist

# 3. Ad-hoc sign
codesign --force --sign - build/TokenGarden.app

# 4. DMG
cp -R build/TokenGarden.app build/dmg_staging/TokenGarden.app
rm -f build/TokenGarden.dmg
hdiutil create -volname "Token Garden" -srcfolder build/dmg_staging -ov -format UDZO build/TokenGarden.dmg

# 5. Zip
cd build && rm -f TokenGarden.zip && zip -r TokenGarden.zip TokenGarden.app && cd ..
```

## Commit & Push

```bash
git add build/TokenGarden.app build/TokenGarden.dmg build/TokenGarden.zip
git commit -m "build: vX.Y.Z release artifacts"
git push origin main
```

## Notes

- `swift build`는 SwiftData 매크로 이슈로 사용 불가 — 반드시 `xcodebuild` 사용
- DerivedData는 `.claude/tmp/DerivedData`에 생성 (`/tmp` 사용 금지, SentinelOne EDR 정책)
- 앱 번들 구조(`Info.plist`, `Resources/AppIcon.icns`)는 `build/TokenGarden.app/Contents/`에 유지
