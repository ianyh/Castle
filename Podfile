# Uncomment the next line to define a global platform for your project
platform :ios, '11.0'

target 'Castle' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  pod 'Anchorage'
  pod 'Kingfisher', '~> 4.0'
  pod 'Moya/RxSwift'
  pod 'RealmSwift'
  pod 'Reveal-SDK', configurations: ['Debug']

  target 'CastleTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'CastleUITests' do
    inherit! :search_paths
    # Pods for testing
  end

  post_install do |installer|
    installer.pods_project.targets.each do |target|
      if target.name == 'Eureka'
        target.build_configurations.each do |config|
          config.build_settings['SWIFT_VERSION'] = '4.0'
        end
      end
    end
  end
end
