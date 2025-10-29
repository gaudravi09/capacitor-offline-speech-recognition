require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name = 'CapacitorOfflineSpeechRecognition'
  s.version = package['version']
  s.summary = package['description']
  s.license = package['license']
  s.homepage = package['repository']['url']
  s.author = package['author']
  s.source = { :git => package['repository']['url'], :tag => s.version.to_s }
  s.source_files = 'ios/Sources/**/*.{swift,h,m,c,cc,mm,cpp}'
  s.ios.deployment_target = '14.0'
  s.dependency 'Capacitor'
  s.dependency 'SSZipArchive'
  # Vosk static library and headers
  s.vendored_frameworks = 'ios/libvosk.xcframework'
  s.public_header_files = 'ios/Sources/OfflineSpeechRecognitionPlugin/*.h'
  # Link required system frameworks and libraries for BLAS/LAPACK and audio
  s.frameworks = 'Accelerate', 'AVFoundation', 'AudioToolbox'
  s.libraries = 'c++'
  s.swift_version = '5.1'
end
