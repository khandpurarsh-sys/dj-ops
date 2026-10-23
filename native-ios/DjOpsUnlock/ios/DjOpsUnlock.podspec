require 'json'
package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

Pod::Spec.new do |s|
  s.name = 'DjOpsUnlock'
  s.version = package['version']
  s.summary = 'Face ID / device-unlock gate for DJ Ops native shell'
  s.license = 'MIT'
  s.homepage = 'https://localhost'
  s.author = 'DJ Ops'
  s.source = { :git => 'https://localhost', :tag => package['version'] }
  s.source_files = 'Sources/DjOpsUnlockPlugin/**/*.{swift,h,m}'
  s.ios.deployment_target = '16.4'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
end
