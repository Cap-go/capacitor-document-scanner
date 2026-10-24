require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapgoCapacitorDocumentScanner'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '15.0'
  s.dependency 'Capacitor'
  s.swift_version = '5.1'
  # capgo-visionkit-swizzle: scripts/configure-visionkit-swizzle.mjs sets this during cap sync.
  # false keeps the private VisionKit swizzle out of the App Store binary.
  vision_kit_swizzle_enabled = false
  if vision_kit_swizzle_enabled
    s.pod_target_xcconfig = {
      'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) CAPGO_DOCUMENT_SCANNER_VISIONKIT_SWIZZLE'
    }
  end
end
