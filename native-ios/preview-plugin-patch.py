import subprocess
for cmd in ["cat ios/App/App/Info.plist","cat ios/App/App/Base.lproj/LaunchScreen.storyboard","cat ios/App/App/Base.lproj/Main.storyboard","grep -nE 'TARGETED_DEVICE_FAMILY|UILaunch|SDKROOT|IPHONEOS_DEPLOYMENT|INFOPLIST' ios/App/App.xcodeproj/project.pbxproj","xcodebuild -version","ls ios/App/App"]:
    print("=== DIAG", cmd, flush=True)
    print(subprocess.run(cmd, shell=True, capture_output=True, text=True).stdout, flush=True)
# PREVIEW-ONLY patch, applied in CI right after `cap sync` and before pod
# install, only when sign_and_upload is false. The DjOpsUnlock plugin stores
# its gate key with a SecAccessControl requiring .userPresence and the
# WhenPasscodeSetThisDeviceOnly accessibility. That accessibility class makes
# SecItemAdd fail on a device with no passcode set - and the CI simulator has
# no passcode. For the preview build only, store the dummy key with plain
# AfterFirstUnlockThisDeviceOnly instead. The LocalAuthentication
# evaluatePolicy(.deviceOwnerAuthentication) call in unlock() still runs, so
# the user-presence gate stays exercised end to end in the preview. Signed
# TestFlight builds use the unmodified plugin.
import glob, sys

paths = glob.glob('node_modules/djops-unlock/ios/Sources/DjOpsUnlockPlugin/*.swift')
if not paths:
    sys.exit('plugin swift source not found under node_modules/djops-unlock')
p = paths[0]
s = open(p).read()
old = """        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, &error) else {
            call.reject("Could not create access control"); return
        }
        var attrs = base
        attrs[kSecValueData as String] = Data(bytes)
        attrs[kSecAttrAccessControl as String] = access"""
new = """        var attrs = base
        attrs[kSecValueData as String] = Data(bytes)
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly"""
if old not in s:
    sys.exit('plugin source drifted; preview patch no longer applies - inspect DjOpsUnlockPlugin.swift')
open(p, 'w').write(s.replace(old, new))
print('preview plugin patch applied to', p)
