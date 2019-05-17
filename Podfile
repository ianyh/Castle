platform :ios, '11.0'

target 'Castle' do
  use_frameworks!

  pod 'Anchorage'
  pod 'CouchbaseLite-Swift', '~> 2.5.1'
  pod 'Kingfisher', '~> 5.0'
  pod 'Moya/RxSwift'
  pod 'RealmSwift'
  pod 'Reveal-SDK', configurations: ['Debug']

  target 'CastleTests' do
    inherit! :search_paths
  end

  target 'CastleUITests' do
    inherit! :search_paths
  end
end
