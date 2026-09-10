platform :ios, '12.0'
inhibit_all_warnings!

project 'Matnami.xcodeproj'

target 'Matnami' do
  use_frameworks!
  pod 'SwiftSoup', '~> 2.7'
  pod 'libwebp', :modular_headers => true
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
