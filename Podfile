platform :ios, '17.0'
use_frameworks!

target 'AIFormCoach' do
  # MediaPipe 1.0 links against APIs shipped with the current Apple toolchain.
  # Keep the Xcode 15-compatible Apple Vision fallback as the default build.
  pod 'MediaPipeTasksVision', '1.0.0' if ENV['ENABLE_MEDIAPIPE'] == '1'
end
